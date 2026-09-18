use super::{Action, Args, Context};

#[derive(Default)]
pub struct Quit;

impl Action for Quit {
    fn start(&mut self, ctx: &mut dyn Context, _args: &Args) {
        ctx.quit();
        ctx.finish();
    }
}
