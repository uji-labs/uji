use mlua::Function;

pub const DEFAULT_PRIORITY: i64 = 50;

pub struct Entry {
    pub name: String,
    pub priority: i64,
    pub call: Function,
}

#[derive(Default)]
pub struct Registry {
    entries: Vec<Entry>,
}

impl Registry {
    pub fn add(&mut self, entry: Entry) {
        self.entries.retain(|existing| existing.name != entry.name);
        self.entries.push(entry);
        self.entries.sort_by_key(|entry| entry.priority);
    }

    pub fn remove(&mut self, name: &str) -> bool {
        let before = self.entries.len();
        self.entries.retain(|entry| entry.name != name);
        self.entries.len() != before
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn calls(&self) -> Vec<(String, Function)> {
        self.entries
            .iter()
            .map(|entry| (entry.name.clone(), entry.call.clone()))
            .collect()
    }

    pub fn functions(&self) -> Vec<Function> {
        self.entries
            .iter()
            .map(|entry| entry.call.clone())
            .collect()
    }
}
