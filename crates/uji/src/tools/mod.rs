pub mod builtin;
pub mod policy;
pub mod policy_lua;

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use crate::llm::ToolSpec;

#[async_trait]
pub trait Tool: Send + Sync {
    fn spec(&self) -> ToolSpec;
    fn subject(&self, args: &Value) -> String;
    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String>;
}

#[derive(Default)]
pub struct ToolRegistry {
    tools: HashMap<String, Arc<dyn Tool>>,
}

impl ToolRegistry {
    pub fn register(&mut self, tool: Arc<dyn Tool>) {
        self.tools.insert(tool.spec().name.clone(), tool);
    }

    pub fn specs(&self) -> Vec<ToolSpec> {
        self.tools.values().map(|tool| tool.spec()).collect()
    }

    pub fn get(&self, name: &str) -> Option<&Arc<dyn Tool>> {
        self.tools.get(name)
    }
}

pub fn builtin_registry() -> ToolRegistry {
    let mut registry = ToolRegistry::default();
    registry.register(Arc::new(builtin::ReadFile));
    registry.register(Arc::new(builtin::WriteFile));
    registry.register(Arc::new(builtin::ListDir));
    registry.register(Arc::new(builtin::Grep));
    registry.register(Arc::new(builtin::RunCommand));
    registry
}
