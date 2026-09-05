use uji_cmd::{Action, Args, Context, Help, Providers};

pub(crate) enum Builtin {
    Providers(Providers),
    Help(Help),
}

impl Builtin {
    pub(crate) const ALL: &[(&str, &str)] = &[
        ("providers", "pick a provider, model and auth"),
        ("help", "list commands"),
    ];

    pub(crate) fn from_name(name: &str) -> Option<Self> {
        match name {
            "providers" | "models" => Some(Self::Providers(Providers::default())),
            "help" => Some(Self::Help(Help)),
            _ => None,
        }
    }

    pub(crate) fn start<C: Context>(&mut self, ctx: &mut C, args: &Args) {
        match self {
            Self::Providers(p) => p.start(ctx, args),
            Self::Help(h) => h.start(ctx, args),
        }
    }

    pub(crate) fn on_select<C: Context>(&mut self, ctx: &mut C, item: String) {
        match self {
            Self::Providers(p) => p.on_select(ctx, item),
            Self::Help(h) => h.on_select(ctx, item),
        }
    }

    pub(crate) fn on_prompt<C: Context>(&mut self, ctx: &mut C, value: String) {
        match self {
            Self::Providers(p) => p.on_prompt(ctx, value),
            Self::Help(h) => h.on_prompt(ctx, value),
        }
    }

    pub(crate) fn on_cancel<C: Context>(&mut self, ctx: &mut C) {
        match self {
            Self::Providers(p) => p.on_cancel(ctx),
            Self::Help(h) => h.on_cancel(ctx),
        }
    }
}
