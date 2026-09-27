use std::cell::RefCell;
use std::error::Error;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crossterm::event::{Event, KeyCode, KeyEvent, KeyModifiers};
use serde_json::Value;
use uji_kernel::{Options, Outcome, Sources, Terminal, VirtualHandle, virtual_terminal};

use crate::model::Message;

pub const ALLOW_ALL: &str = r#"
local allow = { default = "allow" }
uji.tool.policy({ default = "allow", read_file = allow, edit_file = allow, write_file = allow, run_command = allow })
"#;

pub const SUBMIT: &str = r#"uji.schedule(function() uji.session.submit("go") end)"#;

const WIDTH: u16 = 120;
const HEIGHT: u16 = 40;
const POLL: Duration = Duration::from_millis(5);
const GRACE: Duration = Duration::from_secs(10);
const ASKING: &str = "what to do differently (esc)";
const ENTRY: &str = "uji.boot";
const PROBE_WIDTH: u16 = 80;
const PROBE_HEIGHT: u16 = 24;
const PROBE_DEADLINE: Duration = Duration::from_secs(30);
const WARM: &str = r#"uji.net.request({ method = "GET", url = "http://127.0.0.1:9" })"#;

const PROBE: &str = r##"
local probe = PROBE
local seen = assert(io.open(probe.out, "w"))

function emit(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value == nil then
            value = uji.json.null
        end
        seen:write(uji.json.encode(value), "\n")
    end
    seen:flush()
end

local function body()
BODY
end

uji.schedule(function()
    require("uji.app").session.directory = probe.work
    local ok, err = pcall(body)
    if not ok then
        emit({ probe_error = tostring(err) })
    end
    seen:close()
    require("uji.ui"):quit()
end)
"##;

const HARNESS: &str = r#"
do
    local app = require("uji.app")
    local event = require("uji.event")
    local model = require("uji.model")
    local notices = require("uji.notices")
    local harness = HARNESS

    model.set_setting("llm.provider", "test")
    model.set_setting("llm.model", "m")
    uji.ui.open_win({ view = "input", split = "bottom", size = "auto" })

    local function write(path, lines)
        local file = assert(io.open(path, "w"))
        for _, line in ipairs(lines) do
            file:write(line, "\n")
        end
        file:close()
    end

    local function finish()
        require("uji.ui"):quit()
    end

    event.on("before_quit", function()
        local rows = app.store.db:query(
            "SELECT data FROM messages WHERE session_id = ? ORDER BY seq",
            { app.session.id }
        )
        local lines = {}
        for index, row in ipairs(rows) do
            lines[index] = row.data
        end
        write(harness.messages, lines)
    end, { name = "harness.before_quit" })

    event.on("session_created", function()
        if #notices.pending > 0 then
            write(harness.notices, notices.pending)
            uji.os.exit(0)
            return
        end
        app.session.directory = harness.work
        app.session:rename("test")
        for _, message in ipairs(uji.json.decode(harness.history, { nulls = false })) do
            app.session:append(message)
        end
    end, { name = "harness.session_created" })

    if harness.title then
        event.on("session_titled", function(payload)
            if payload.title == harness.title then
                finish()
            end
        end, { name = "harness.session_titled" })
    else
        event.on("turn_finished", function()
            if #app.agent.queue == 0 then
                finish()
            end
        end, { name = "harness.turn_finished" })
    end
end
"#;

#[derive(Clone, Copy)]
pub enum Until {
    TurnFinished,
    Title(&'static str),
}

static SANDBOXES: AtomicUsize = AtomicUsize::new(0);

fn long(text: &str) -> String {
    let mut fence = String::new();
    loop {
        let close = format!("]{fence}]");
        if format!("{text}{close}").find(&close) == Some(text.len()) {
            return format!("[{fence}[{text}{close}");
        }
        fence.push('=');
    }
}

fn key(key: char) -> Event {
    Event::Key(KeyEvent::new(KeyCode::Char(key), KeyModifiers::NONE))
}

fn quit() -> Event {
    Event::Key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL))
}

fn wait(
    worker: &JoinHandle<Outcome>,
    handle: &VirtualHandle,
    answers: &[char],
    deadline: Duration,
) {
    let started = Instant::now();
    let mut frames = handle.frames();
    let mut answers = answers.iter();
    let mut answered: Option<Vec<String>> = None;
    let mut quitting = false;
    while !worker.is_finished() {
        if frames.has_changed().unwrap_or(false) {
            let frame = frames.borrow_and_update().clone();
            if !frame.iter().any(|row| row.contains(ASKING)) {
                answered = None;
            } else if answered.as_ref() != Some(&frame) {
                if let Some(answer) = answers.next() {
                    handle.send(key(*answer));
                }
                answered = Some(frame);
            }
        }
        let elapsed = started.elapsed();
        if !quitting && elapsed > deadline {
            handle.send(quit());
            quitting = true;
        }
        if elapsed > deadline + GRACE {
            return;
        }
        std::thread::sleep(POLL);
    }
}

pub struct Sandbox {
    root: PathBuf,
    history: RefCell<Vec<Message>>,
}

impl Sandbox {
    pub fn new(name: &str) -> io::Result<Self> {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "uji-test-{name}-{}-{stamp}-{}",
            std::process::id(),
            SANDBOXES.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(root.join("cfg"))?;
        std::fs::create_dir_all(root.join("work"))?;
        std::fs::create_dir_all(root.join("data"))?;
        Ok(Self {
            root,
            history: RefCell::default(),
        })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn work(&self) -> PathBuf {
        self.root.join("work")
    }

    pub fn file(&self, relative: &str, content: impl AsRef<[u8]>) -> io::Result<()> {
        let path = self.work().join(relative);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, content)
    }

    pub fn remember(&self, message: Message) {
        self.history.borrow_mut().push(message);
    }

    pub fn config(&self, lua: &str) -> io::Result<()> {
        std::fs::write(self.root.join("cfg/init.lua"), lua)
    }

    fn harness(&self, until: &Until) -> Result<String, Box<dyn Error>> {
        let history = serde_json::to_string(&*self.history.borrow())?;
        let title = match until {
            Until::TurnFinished => String::from("nil"),
            Until::Title(title) => long(title),
        };
        let table = format!(
            "{{ messages = {}, notices = {}, work = {}, history = {}, title = {title} }}",
            long(&self.root.join("messages.jsonl").display().to_string()),
            long(&self.root.join("notices.txt").display().to_string()),
            long(&self.work().display().to_string()),
            long(&history),
        );
        Ok(HARNESS.replace("HARNESS", &table))
    }

    fn boot(
        &self,
        width: u16,
        height: u16,
        answers: &[char],
        deadline: Duration,
    ) -> Result<Outcome, Box<dyn Error>> {
        let args = [
            "uji",
            "new",
            "--config-dir",
            &self.root.join("cfg").display().to_string(),
            "--data-dir",
            &self.root.join("data").display().to_string(),
            "--db",
            &self.root.join("uji.db").display().to_string(),
        ]
        .map(String::from)
        .to_vec();
        let (terminal, handle) = virtual_terminal(width, height);
        let worker = std::thread::spawn(move || {
            uji_kernel::run(Options {
                sources: Sources::Embedded(uji_lua::FILES),
                entry: String::from(ENTRY),
                args,
                terminal: Terminal::Virtual(terminal),
            })
        });
        wait(&worker, &handle, answers, deadline);
        if !worker.is_finished() {
            return Err("uji did not stop after the deadline".into());
        }
        Ok(worker.join().map_err(|_| "the kernel thread panicked")?)
    }

    pub fn run(
        &self,
        until: Until,
        answers: &[char],
        deadline: Duration,
    ) -> Result<Vec<Message>, Box<dyn Error>> {
        warm_network()?;
        let init = self.root.join("cfg/init.lua");
        let config = std::fs::read_to_string(&init).unwrap_or_default();
        std::fs::write(&init, format!("{config}\n{}", self.harness(&until)?))?;
        let outcome = self.boot(WIDTH, HEIGHT, answers, deadline)?;
        if let Ok(notices) = std::fs::read_to_string(self.root.join("notices.txt")) {
            return Err(format!("boot notices: {:?}", notices.lines().collect::<Vec<_>>()).into());
        }
        if outcome.code != 0 {
            return Err(format!("uji exited with {}: {:?}", outcome.code, outcome.errors).into());
        }
        let messages = std::fs::read_to_string(self.root.join("messages.jsonl"))
            .map_err(|err| format!("uji left no messages ({err}): {:?}", outcome.errors))?;
        Ok(messages
            .lines()
            .map(serde_json::from_str)
            .collect::<Result<_, _>>()?)
    }

    pub fn probe(&self, lua: &str) -> Result<Vec<Value>, Box<dyn Error>> {
        self.probe_on(PROBE_WIDTH, PROBE_HEIGHT, lua)
    }

    pub fn probe_on(
        &self,
        width: u16,
        height: u16,
        lua: &str,
    ) -> Result<Vec<Value>, Box<dyn Error>> {
        let out = self.root.join("probe.jsonl");
        let table = format!(
            "{{ out = {}, work = {} }}",
            long(&out.display().to_string()),
            long(&self.work().display().to_string()),
        );
        let script = PROBE.replace("PROBE", &table).replace("BODY", lua);
        std::fs::write(self.root.join("cfg/init.lua"), script)?;
        let outcome = self.boot(width, height, &[], PROBE_DEADLINE)?;
        let seen = std::fs::read_to_string(&out)
            .map_err(|err| format!("the probe wrote nothing ({err}): {:?}", outcome.errors))?;
        let values: Vec<Value> = seen
            .lines()
            .map(serde_json::from_str)
            .collect::<Result<_, _>>()?;
        if let Some(failure) = values.iter().find_map(|value| value.get("probe_error")) {
            return Err(format!("the probe failed: {failure}").into());
        }
        Ok(values)
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

pub fn provider(url: &str, context: u64) -> String {
    format!(
        r#"uji.provider.add({{ id = "test", name = "Test", wire = "openai-chat", base_url = "{url}/v1", models = {{ {{ id = "m", context = {context}, output = 1000 }} }} }})"#
    )
}

pub fn tool_results(messages: &[Message]) -> Vec<String> {
    messages
        .iter()
        .filter_map(|message| match message {
            Message::Tool { content, .. } => Some(content.clone()),
            _ => None,
        })
        .collect()
}

fn warm_network() -> Result<(), Box<dyn Error>> {
    Sandbox::new("warm")?.probe(WARM)?;
    Ok(())
}

pub fn probe(lua: &str) -> Result<Vec<Value>, Box<dyn Error>> {
    Sandbox::new("probe")?.probe(lua)
}
