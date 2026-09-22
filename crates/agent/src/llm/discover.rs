use serde::Deserialize;

use super::catalog::Provider;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Windows {
    pub model: String,
    pub context: Option<u64>,
    pub output: Option<u64>,
}

#[derive(Deserialize)]
struct Info {
    data: Vec<Entry>,
}

#[derive(Deserialize)]
struct Entry {
    model_name: String,
    #[serde(default)]
    model_info: Limits,
}

#[derive(Deserialize, Default)]
struct Limits {
    #[serde(default)]
    max_input_tokens: Option<u64>,
    #[serde(default)]
    max_output_tokens: Option<u64>,
}

pub async fn windows(
    client: &reqwest::Client,
    provider: &Provider,
    key: Option<&str>,
) -> Option<Vec<Windows>> {
    let url = format!("{}/model/info", provider.base_url.trim_end_matches('/'));
    let mut request = client.get(url);
    if let Some(key) = key {
        request = request.bearer_auth(key);
    }
    let response = request.send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    let info = response.json::<Info>().await.ok()?;
    let found = info
        .data
        .into_iter()
        .filter(|entry| {
            entry.model_info.max_input_tokens.is_some()
                || entry.model_info.max_output_tokens.is_some()
        })
        .map(|entry| Windows {
            model: entry.model_name,
            context: entry.model_info.max_input_tokens,
            output: entry.model_info.max_output_tokens,
        })
        .collect();
    Some(found)
}
