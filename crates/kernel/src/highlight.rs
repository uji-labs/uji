use std::convert::Infallible;
use std::str::FromStr;
use std::sync::LazyLock;

use syntect::highlighting::ScopeSelectors;
use syntect::parsing::{ParseState, ScopeStack, SyntaxSet};
use uji_macros::{function, value};

use crate::io::{self, Blocked};

static SYNTAXES: LazyLock<SyntaxSet> = LazyLock::new(two_face::syntax::extra_newlines);

static KINDS: LazyLock<Vec<(Kind, ScopeSelectors)>> = LazyLock::new(|| {
    [
        (Kind::Comment, "comment"),
        (Kind::String, "string"),
        (Kind::Number, "constant.numeric"),
        (Kind::Constant, "constant.language, constant.character, constant.other, support.constant"),
        (Kind::Keyword, "keyword - keyword.operator, storage, variable.language"),
        (Kind::Func, "entity.name.function, support.function, variable.function"),
        (Kind::Type, "entity.name.type, entity.name.class, entity.other.inherited-class, support.type, support.class"),
    ]
    .into_iter()
    .filter_map(|(kind, scopes)| ScopeSelectors::from_str(scopes).ok().map(|selectors| (kind, selectors)))
    .collect()
});

#[value]
#[derive(Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum Kind {
    Plain,
    Keyword,
    String,
    Number,
    Comment,
    Func,
    Type,
    Constant,
}

#[value]
struct Token {
    text: String,
    kind: Kind,
}

fn kind(scopes: &ScopeStack) -> Kind {
    KINDS
        .iter()
        .filter_map(|(kind, selectors)| {
            selectors
                .does_match(scopes.as_slice())
                .map(|power| (power, *kind))
        })
        .max_by_key(|(power, _)| *power)
        .map_or(Kind::Plain, |(_, kind)| kind)
}

fn push(tokens: &mut Vec<Token>, text: &str, kind: Kind) {
    match tokens.last_mut() {
        Some(last) if last.kind == kind => last.text.push_str(text),
        _ if !text.is_empty() => tokens.push(Token {
            text: text.to_string(),
            kind,
        }),
        _ => {}
    }
}

fn line(parse: &mut ParseState, scopes: &mut ScopeStack, text: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let Ok(ops) = parse.parse_line(&format!("{text}\n"), &SYNTAXES) else {
        push(&mut tokens, text, Kind::Plain);
        return tokens;
    };
    let mut at = 0;
    for (index, op) in ops {
        let index = index.min(text.len());
        if let Some(piece) = text.get(at..index) {
            push(&mut tokens, piece, kind(scopes));
            at = index;
        }
        if scopes.apply(&op).is_err() {
            break;
        }
    }
    push(
        &mut tokens,
        text.get(at..).unwrap_or_default(),
        kind(scopes),
    );
    tokens
}

fn highlighted(language: &str, text: &str) -> Option<Vec<Vec<Token>>> {
    let syntax = SYNTAXES.find_syntax_by_token(language)?;
    let mut parse = ParseState::new(syntax);
    let mut scopes = ScopeStack::new();
    Some(
        text.split('\n')
            .map(|piece| {
                line(
                    &mut parse,
                    &mut scopes,
                    piece.strip_suffix('\r').unwrap_or(piece),
                )
            })
            .collect(),
    )
}

pub(crate) fn warm() {
    LazyLock::force(&SYNTAXES);
}

#[function]
async fn highlight(
    language: String,
    text: String,
) -> Result<Option<Vec<Vec<Token>>>, Blocked<Infallible>> {
    io::blocking(move || Ok(highlighted(&language, &text))).await
}
