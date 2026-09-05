use super::{Action, Args, Context};

const PROVIDERS: [&str; 3] = ["openai", "ollama", "echo"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum Step {
    #[default]
    Provider,
    Model,
    BaseUrl,
    ApiKey,
}

#[derive(Default)]
struct Draft {
    provider: String,
    model: String,
    base_url: String,
    api_key: String,
}

#[derive(Default)]
pub struct Providers {
    step: Step,
    draft: Draft,
}

impl Action for Providers {
    fn name(&self) -> &'static str {
        "providers"
    }

    fn desc(&self) -> &'static str {
        "pick a provider, model and auth"
    }

    fn start<C: Context>(&mut self, ctx: &mut C, _args: &Args) {
        self.step = Step::Provider;
        self.draft = Draft::default();
        ctx.open_select(
            "provider".into(),
            PROVIDERS.iter().map(|p| (*p).to_string()).collect(),
        );
    }

    fn on_select<C: Context>(&mut self, ctx: &mut C, item: String) {
        if self.step == Step::Provider {
            self.draft.provider = item;
            let default = default_model(&self.draft.provider);
            ctx.open_prompt(prompt_title("model", &default), String::new(), false);
            self.step = Step::Model;
        }
    }

    fn on_prompt<C: Context>(&mut self, ctx: &mut C, value: String) {
        match self.step {
            Step::Model => {
                self.draft.model = if value.is_empty() {
                    default_model(&self.draft.provider)
                } else {
                    value
                };
                let default = default_base_url(&self.draft.provider);
                ctx.open_prompt(prompt_title("base_url", &default), String::new(), false);
                self.step = Step::BaseUrl;
            }
            Step::BaseUrl => {
                self.draft.base_url = if value.is_empty() {
                    default_base_url(&self.draft.provider)
                } else {
                    value
                };
                ctx.open_prompt("api_key (enter to skip)".into(), String::new(), true);
                self.step = Step::ApiKey;
            }
            Step::ApiKey => {
                self.draft.api_key = value;
                if !self.draft.api_key.is_empty() {
                    ctx.save_credential(&self.draft.provider, &self.draft.api_key);
                }
                ctx.set_setting("llm.provider", &self.draft.provider);
                ctx.set_setting("llm.model", &self.draft.model);
                ctx.set_setting("llm.base_url", &self.draft.base_url);
                ctx.resolve_llm();
                ctx.notify(&format!(
                    "configured {}/{}",
                    self.draft.provider, self.draft.model
                ));
                ctx.finish();
            }
            Step::Provider => {}
        }
    }

    fn on_cancel<C: Context>(&mut self, ctx: &mut C) {
        ctx.finish();
    }
}

fn default_model(provider: &str) -> String {
    match provider {
        "ollama" => "llama3.2".into(),
        "openai" => "gpt-4o-mini".into(),
        _ => String::new(),
    }
}

fn default_base_url(provider: &str) -> String {
    match provider {
        "ollama" => "http://localhost:11434".into(),
        "openai" => "https://api.openai.com/v1".into(),
        _ => String::new(),
    }
}

fn prompt_title(label: &str, default: &str) -> String {
    if default.is_empty() {
        label.to_string()
    } else {
        format!("{label} (default: {default})")
    }
}
