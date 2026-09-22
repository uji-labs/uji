use mlua::Function;

pub const DEFAULT_PRIORITY: i64 = 50;

pub struct Handler {
    pub name: String,
    pub priority: i64,
    pub call: Function,
}

#[derive(Default)]
pub struct Handlers {
    by_event: Vec<(String, Vec<Handler>)>,
    anonymous: u64,
}

impl Handlers {
    pub fn add(&mut self, event: String, handler: Handler) {
        let mut at = self.by_event.iter().position(|(name, _)| *name == event);
        if at.is_none() {
            self.by_event.push((event, Vec::new()));
            at = Some(self.by_event.len().saturating_sub(1));
        }
        let Some((_, list)) = at.and_then(|at| self.by_event.get_mut(at)) else {
            return;
        };
        list.retain(|existing| existing.name != handler.name);
        list.push(handler);
        list.sort_by_key(|handler| handler.priority);
    }

    pub fn remove(&mut self, event: &str, name: &str) -> bool {
        let Some((_, list)) = self.by_event.iter_mut().find(|(each, _)| each == event) else {
            return false;
        };
        let before = list.len();
        list.retain(|handler| handler.name != name);
        list.len() != before
    }

    pub fn anonymous(&mut self) -> String {
        self.anonymous = self.anonymous.saturating_add(1);
        format!("#{}", self.anonymous)
    }

    pub fn has(&self, event: &str) -> bool {
        self.by_event
            .iter()
            .any(|(name, list)| name == event && !list.is_empty())
    }

    pub fn get(&self, event: &str) -> Vec<Function> {
        self.by_event
            .iter()
            .find(|(name, _)| name == event)
            .map(|(_, list)| list.iter().map(|handler| handler.call.clone()).collect())
            .unwrap_or_default()
    }
}
