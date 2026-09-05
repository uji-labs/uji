use super::{Action, Args, Context};

pub struct Help;

impl Action for Help {
    fn name(&self) -> &'static str {
        "help"
    }

    fn desc(&self) -> &'static str {
        "list commands"
    }

    fn start<C: Context>(&mut self, ctx: &mut C, _args: &Args) {
        ctx.open_select("commands".into(), ctx.command_names());
    }

    fn on_select<C: Context>(&mut self, ctx: &mut C, _item: String) {
        ctx.finish();
    }

    fn on_cancel<C: Context>(&mut self, ctx: &mut C) {
        ctx.finish();
    }
}
