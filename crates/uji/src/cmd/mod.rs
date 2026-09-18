pub mod compact;
pub mod effort;
pub mod help;
pub mod login;
pub(crate) mod lua;
pub mod models;
pub mod quit;
pub mod reload;
pub mod sync;
pub mod thinking;

pub use compact::Compact;
pub use effort::EffortPick;
pub use help::Help;
pub use login::Login;
pub(crate) use lua::LuaAction;
pub use models::Models;
pub use quit::Quit;
pub use reload::Reload;
pub use sync::Sync;
pub use thinking::Thinking;

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
use uji_agent::llm::Provider;
use uji_agent::session::store::Setting;
use uji_ui::app::Echo;

pub trait Context {
    fn open_select(&mut self, title: String, items: Vec<String>);
    fn open_prompt(&mut self, title: String, value: String, echo: Echo);
    fn set_setting(&mut self, key: &Setting, value: &str);
    fn get_setting(&mut self, key: &Setting) -> Option<String>;
    fn save_credential(&mut self, provider: &str, key: &str);
    fn resolve_llm(&mut self);
    fn reload(&mut self);
    fn quit(&mut self);
    fn compact(&mut self) -> bool;
    fn toggle_thinking(&mut self);
    fn sync_packs(&mut self);
    fn start_oauth(&mut self, provider_id: &str);
    fn notify(&mut self, message: &str);
    fn finish(&mut self);
    fn providers(&self) -> Vec<Provider>;
    fn provider(&self, id: &str) -> Option<Provider>;
    fn provider_by_name(&self, name: &str) -> Option<Provider>;
    fn command_names(&self) -> Vec<String>;
}

pub(crate) fn remember_model(ctx: &mut dyn Context, provider_id: &str, model: &str) {
    ctx.set_setting(&Setting::Model, model);
    ctx.set_setting(&Setting::ModelFor(provider_id.to_string()), model);
}

pub(crate) fn model_for(ctx: &mut dyn Context, provider: &Provider) -> String {
    let stored = ctx
        .get_setting(&Setting::ModelFor(provider.id.clone()))
        .or_else(|| ctx.get_setting(&Setting::Model));
    provider.usable_model(stored)
}

pub trait Action {
    fn start(&mut self, ctx: &mut dyn Context, args: &Args);
    fn on_select(&mut self, _ctx: &mut dyn Context, _item: String) {}
    fn on_prompt(&mut self, _ctx: &mut dyn Context, _value: String) {}
    fn on_cancel(&mut self, _ctx: &mut dyn Context) {}
}
