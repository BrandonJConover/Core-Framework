use anyhow::Result;
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use constant_time_eq::constant_time_eq;
use sha2::{Digest, Sha256};
use std::path::Path;

/// Hash a password using Argon2id.
pub fn hash_password(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)?
        .to_string();
    Ok(password_hash)
}

/// Verify a password against a stored hash.
pub fn verify_password(password: &str, hash: &str) -> bool {
    match PasswordHash::new(hash) {
        Ok(parsed_hash) => Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok(),
        Err(_) => false,
    }
}

/// Generate a secure random token.
pub fn generate_token(length: usize) -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes: Vec<u8> = (0..length).map(|_| rng.gen()).collect();
    base64_url_encode(&bytes)
}

/// Hash a username for privacy-preserving logging.
pub fn hash_username(username: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(username.to_lowercase().as_bytes());
    let result = hasher.finalize();
    hex::encode(&result[..8])
}

/// Validate a username.
pub fn validate_username(username: &str) -> Result<(), &'static str> {
    if username.is_empty() || username.len() > 12 {
        return Err("Username must be 1-12 characters");
    }

    if !username.chars().all(|c| c.is_alphanumeric() || c == '_') {
        return Err("Username can only contain letters, numbers, and underscores");
    }

    let lower = username.to_lowercase();
    for reserved in &["admin", "mod", "staff", "jagex"] {
        if lower.contains(reserved) {
            return Err("Username contains reserved words");
        }
    }

    Ok(())
}

/// Validate a password.
pub fn validate_password(password: &str) -> Result<(), &'static str> {
    if password.is_empty() {
        return Err("Password is required");
    }

    if password.len() < 5 {
        return Err("Password must be at least 5 characters");
    }

    if password.len() > 20 {
        return Err("Password must be at most 20 characters");
    }

    Ok(())
}

/// Sanitize chat message input.
pub fn sanitize_chat_message(message: &str, max_length: usize) -> String {
    message
        .chars()
        .take(max_length)
        .filter(|c| c.is_ascii() && *c >= ' ' && *c <= '~')
        .collect::<String>()
        .trim()
        .to_string()
}

/// Check if a command input is safe.
pub fn is_command_safe(command: &str) -> bool {
    if command.is_empty() {
        return false;
    }

    // Block potential injection patterns
    !command.contains("..")
        && !command.contains("//")
        && !command.contains(';')
        && !command.contains('\'')
        && !command.contains('"')
        && !command.contains('`')
}

/// Validate an IP address.
pub fn is_valid_ip(ip: &str) -> bool {
    ip.parse::<std::net::IpAddr>().is_ok()
}

/// Check if an IP is in a private range.
pub fn is_private_ip(ip: &str) -> bool {
    match ip.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(addr)) => {
            let octets = addr.octets();
            octets[0] == 10
                || octets[0] == 127
                || (octets[0] == 172 && (16..=31).contains(&octets[1]))
                || (octets[0] == 192 && octets[1] == 168)
        }
        Ok(std::net::IpAddr::V6(addr)) => addr.is_loopback(),
        Err(_) => false,
    }
}

/// Validate a file path to prevent path traversal.
pub fn validate_path(base_path: &str, file_path: &str) -> Result<String> {
    let base = Path::new(base_path).canonicalize()?;
    let target = base.join(file_path).canonicalize()?;

    if !target.starts_with(&base) {
        return Err(anyhow::anyhow!(
            "Path traversal attempt detected: {}",
            file_path
        ));
    }

    Ok(target.to_string_lossy().to_string())
}

/// Validate a SQL identifier (table name, column name).
pub fn validate_sql_identifier(identifier: &str) -> Result<&str> {
    if identifier.is_empty() {
        return Ok(identifier);
    }

    if identifier.len() > 64 {
        return Err(anyhow::anyhow!("Identifier too long: max 64 characters"));
    }

    let first_char = identifier.chars().next().unwrap();
    if !first_char.is_ascii_alphabetic() && first_char != '_' {
        return Err(anyhow::anyhow!(
            "Invalid SQL identifier: must start with letter or underscore"
        ));
    }

    if !identifier
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return Err(anyhow::anyhow!(
            "Invalid SQL identifier: only alphanumeric and underscores allowed"
        ));
    }

    Ok(identifier)
}

/// Constant-time comparison of two byte slices.
pub fn secure_compare(a: &[u8], b: &[u8]) -> bool {
    constant_time_eq(a, b)
}

/// Base64 URL-safe encoding.
fn base64_url_encode(data: &[u8]) -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    URL_SAFE_NO_PAD.encode(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_password_hashing() {
        let password = "test_password_123";
        let hash = hash_password(password).unwrap();

        assert!(verify_password(password, &hash));
        assert!(!verify_password("wrong_password", &hash));
    }

    #[test]
    fn test_username_validation() {
        assert!(validate_username("player1").is_ok());
        assert!(validate_username("test_user").is_ok());
        assert!(validate_username("").is_err());
        assert!(validate_username("toolongusername").is_err());
        assert!(validate_username("admin123").is_err());
        assert!(validate_username("player@123").is_err());
    }

    #[test]
    fn test_password_validation() {
        assert!(validate_password("secure123").is_ok());
        assert!(validate_password("").is_err());
        assert!(validate_password("1234").is_err());
        assert!(validate_password("a".repeat(21).as_str()).is_err());
    }

    #[test]
    fn test_chat_sanitization() {
        assert_eq!(sanitize_chat_message("Hello, World!", 80), "Hello, World!");
        assert_eq!(sanitize_chat_message("  spaces  ", 80), "spaces");
        assert_eq!(sanitize_chat_message("long message", 5), "long");
    }

    #[test]
    fn test_command_safety() {
        assert!(is_command_safe("spawn item 10"));
        assert!(!is_command_safe("../../../etc/passwd"));
        assert!(!is_command_safe("cmd; rm -rf /"));
        assert!(!is_command_safe(""));
    }

    #[test]
    fn test_ip_validation() {
        assert!(is_valid_ip("192.168.1.1"));
        assert!(is_valid_ip("::1"));
        assert!(!is_valid_ip("invalid"));
    }

    #[test]
    fn test_private_ip() {
        assert!(is_private_ip("10.0.0.1"));
        assert!(is_private_ip("192.168.1.1"));
        assert!(is_private_ip("172.16.0.1"));
        assert!(is_private_ip("127.0.0.1"));
        assert!(!is_private_ip("8.8.8.8"));
    }

    #[test]
    fn test_sql_identifier() {
        assert!(validate_sql_identifier("valid_table").is_ok());
        assert!(validate_sql_identifier("_column").is_ok());
        assert!(validate_sql_identifier("123invalid").is_err());
        assert!(validate_sql_identifier("table;drop").is_err());
    }
}
