pub mod help;
pub mod providers;

pub use help::Help;
pub use providers::Providers;

pub struct Args {
    pub raw: String,
    pub tokens: Vec<String>,
}

impl Args {
    pub fn parse(raw: &str) -> Self {
        let raw = raw.trim().to_string();
        let tokens = raw.split_whitespace().map(str::to_string).collect();
        Self { raw, tokens }
    }
}

pub trait Context {
    fn open_select(&mut self, title: String, items: Vec<String>);
    fn open_prompt(&mut self, title: String, value: String, secret: bool);
    fn set_setting(&mut self, key: &str, value: &str);
    fn get_setting(&mut self, key: &str) -> Option<String>;
    fn save_credential(&mut self, provider: &str, key: &str);
    fn resolve_llm(&mut self);
    fn notify(&mut self, message: &str);
    fn finish(&mut self);
    fn command_names(&self) -> Vec<String>;
}

pub trait Action {
    fn name(&self) -> &'static str;
    fn desc(&self) -> &'static str {
        ""
    }
    fn start<C: Context>(&mut self, ctx: &mut C, args: &Args);
    fn on_select<C: Context>(&mut self, _ctx: &mut C, _item: String) {}
    fn on_prompt<C: Context>(&mut self, _ctx: &mut C, _value: String) {}
    fn on_cancel<C: Context>(&mut self, _ctx: &mut C) {}
}
