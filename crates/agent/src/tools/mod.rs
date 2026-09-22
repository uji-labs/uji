pub mod builtin;
pub mod lines;
pub mod policy;
pub mod progress;
pub mod prompt;

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use crate::llm::CancelToken;
use crate::llm::ToolSpec;
use crate::tools::progress::Progress;

/// Everything a tool is handed for one invocation.
pub struct Invocation<'a> {
    pub cwd: &'a Path,
    pub cancel: &'a CancelToken,
    pub progress: &'a Progress,
}

impl<'a> Invocation<'a> {
    pub fn new(cwd: &'a Path, cancel: &'a CancelToken, progress: &'a Progress) -> Self {
        Self {
            cwd,
            cancel,
            progress,
        }
    }
}

#[async_trait]
pub trait Tool: Send + Sync {
    fn spec(&self) -> ToolSpec;
    fn subject(&self, args: &Value) -> String;
    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String>;
}

#[derive(Default)]
pub struct ToolRegistry {
    tools: BTreeMap<String, Arc<dyn Tool>>,
}

impl ToolRegistry {
    pub fn register(&mut self, tool: Arc<dyn Tool>) {
        self.tools.insert(tool.spec().name, tool);
    }

    pub fn specs(&self) -> Vec<ToolSpec> {
        self.tools.values().map(|tool| tool.spec()).collect()
    }

    pub fn get(&self, name: &str) -> Option<&Arc<dyn Tool>> {
        self.tools.get(name)
    }

    pub fn disable(&mut self, names: &BTreeSet<String>) {
        self.tools.retain(|name, _| !names.contains(name));
    }
}

pub fn builtin_registry(roots: builtin::Roots) -> ToolRegistry {
    let mut registry = ToolRegistry::default();
    registry.register(Arc::new(builtin::ReadFile {
        roots: roots.clone(),
    }));
    registry.register(Arc::new(builtin::EditFile {
        roots: roots.clone(),
    }));
    registry.register(Arc::new(builtin::WriteFile {
        roots: roots.clone(),
    }));
    registry.register(Arc::new(builtin::ListDir {
        roots: roots.clone(),
    }));
    registry.register(Arc::new(builtin::Grep {
        roots: roots.clone(),
    }));
    registry.register(Arc::new(builtin::RunCommand { roots }));
    registry
}
