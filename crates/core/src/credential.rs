use std::collections::HashMap;
use std::path::PathBuf;

const SERVICE: &str = "uji";

#[derive(Debug, thiserror::Error)]
pub enum CredentialError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
}

pub fn get(provider: &str) -> Option<String> {
    keyring_get(provider).or_else(|| read_file().and_then(|map| map.get(provider).cloned()))
}

pub fn set(provider: &str, key: &str) -> Result<(), CredentialError> {
    if keyring_set(provider, key).is_ok() {
        return Ok(());
    }
    let mut map = read_file().unwrap_or_default();
    map.insert(provider.to_string(), key.to_string());
    write_file(&map)
}

fn keyring_get(provider: &str) -> Option<String> {
    let entry = keyring::Entry::new(SERVICE, provider).ok()?;
    entry.get_password().ok()
}

fn keyring_set(provider: &str, key: &str) -> Result<(), keyring::Error> {
    let entry = keyring::Entry::new(SERVICE, provider)?;
    entry.set_password(key)
}

fn path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".local/share/uji/auth.json")
}

fn read_file() -> Option<HashMap<String, String>> {
    let text = std::fs::read_to_string(path()).ok()?;
    serde_json::from_str(&text).ok()
}

fn write_file(map: &HashMap<String, String>) -> Result<(), CredentialError> {
    let path = path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let text = serde_json::to_string_pretty(map)?;
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&path)?;
        file.write_all(text.as_bytes())?;
    }
    #[cfg(not(unix))]
    std::fs::write(&path, text)?;
    Ok(())
}
