use std::collections::BTreeMap;

use mlua::Function;

use super::registry::{Entry, Registry};

#[derive(Default)]
pub struct Handlers {
    by_event: BTreeMap<String, Registry>,
}

impl Handlers {
    pub fn add(&mut self, event: String, entry: Entry) {
        self.by_event.entry(event).or_default().add(entry);
    }

    pub fn remove(&mut self, event: &str, name: &str) -> bool {
        self.by_event
            .get_mut(event)
            .is_some_and(|registry| registry.remove(name))
    }

    pub fn has(&self, event: &str) -> bool {
        self.by_event
            .get(event)
            .is_some_and(|registry| !registry.is_empty())
    }

    pub fn get(&self, event: &str) -> Vec<Function> {
        self.by_event
            .get(event)
            .map(Registry::functions)
            .unwrap_or_default()
    }
}
