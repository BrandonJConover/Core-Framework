//! RSA login-block decryption.
//!
//! Byte-for-byte port of `com.openrsc.server.net.rsc.Crypto.decryptRSA(...)`:
//!
//! ```java
//! public static byte[] decryptRSA(byte[] data, int offset, int length) {
//!     byte newData[] = new byte[length];
//!     System.arraycopy(data, offset, newData, 0, length);
//!     return new BigInteger(newData)
//!         .modPow(privateKey.getPrivateExponent(), privateKey.getModulus())
//!         .toByteArray();
//! }
//! ```
//!
//! This is *raw* RSA — no PKCS#1 padding stripping is done by `decryptRSA`
//! itself. The login-block contents (checksum byte 10, ISAAC keys, password,
//! nonces) are interpreted by `LoginPacketHandler` directly from the byte
//! array returned here. To match Java byte-for-byte we must:
//!
//! 1. Treat the input as a `BigInteger(byte[])` — a *signed* big-endian
//!    two's-complement integer. In practice the client sends a positive
//!    number < n, so the high bit is clear; but if it ever isn't, Java
//!    interprets it as negative and modPow normalises into [0, n).
//! 2. Run modular exponentiation with the private exponent d and modulus n
//!    parsed from a PKCS#8-encoded PEM file (Java reads `server.pem` via
//!    `KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(...))`).
//! 3. Return `BigInteger.toByteArray()` — minimal *signed* two's-complement
//!    big-endian. For positive results that means: if the MSB of the natural
//!    big-endian representation has its high bit set, prepend a single 0x00
//!    byte; otherwise emit just the magnitude.
//!
//! ## Modulus & exponent
//!
//! Both are loaded from `server.pem` at boot — there is no hardcoded modulus
//! in the OpenRSC Java code (`Crypto.generateRSAKeys()` creates one if the
//! file is missing, with default Java `KeyPairGenerator` settings: 512-bit
//! key, public exponent F4 = 65537). The Rust port therefore takes the PEM
//! contents at runtime, just like Java does.

use rsa::pkcs8::DecodePrivateKey;
use rsa::traits::PrivateKeyParts;
use rsa::traits::PublicKeyParts;
use rsa::BigUint;
use rsa::RsaPrivateKey;

/// Errors that `decrypt_rsa` can return.
#[derive(Debug, thiserror::Error)]
pub enum RsaError {
    #[error("failed to parse PKCS#8 PEM private key: {0}")]
    KeyParse(#[from] rsa::pkcs8::Error),
    #[error("RSA private key is missing the private exponent (d)")]
    MissingPrivateExponent,
}

/// RSA private key wrapper that caches the modulus and private exponent for
/// repeated `decrypt_rsa` calls. In OpenRSC, the Java server parses the PEM
/// file once at boot via `Crypto.loadRSAKeys()` and stores it in static
/// fields — this struct plays the same role for the Rust port.
#[derive(Debug, Clone)]
pub struct RsaKey {
    modulus: BigUint,
    private_exponent: BigUint,
}

impl RsaKey {
    /// Parse a PKCS#8-encoded PEM private key (i.e. `-----BEGIN PRIVATE KEY-----`,
    /// the format Java writes via `keyPair.getPrivate().getEncoded()` wrapped
    /// in PEM). This is exactly what `server.pem` contains.
    pub fn from_pkcs8_pem(pem: &str) -> Result<Self, RsaError> {
        let key = RsaPrivateKey::from_pkcs8_pem(pem)?;
        let d = key.d().clone();
        let n = key.n().clone();
        if d == BigUint::from(0u32) {
            return Err(RsaError::MissingPrivateExponent);
        }
        Ok(Self {
            modulus: n,
            private_exponent: d,
        })
    }

    /// Build a key directly from raw `(n, d)` components — useful for tests
    /// and for callers that loaded the key out-of-band.
    pub fn from_components(modulus: BigUint, private_exponent: BigUint) -> Self {
        Self {
            modulus,
            private_exponent,
        }
    }

    /// Modulus n.
    pub fn modulus(&self) -> &BigUint {
        &self.modulus
    }

    /// Private exponent d.
    pub fn private_exponent(&self) -> &BigUint {
        &self.private_exponent
    }
}

/// Decrypt a raw RSA-encrypted login block, byte-for-byte equivalent to
/// `Crypto.decryptRSA(ciphertext, 0, ciphertext.len())` in the Java server.
///
/// The returned `Vec<u8>` is the raw `BigInteger.toByteArray()` output:
/// signed big-endian, minimal length, with a leading `0x00` iff the natural
/// magnitude's MSB has the high bit set (so consumers can call e.g.
/// `result[0] == 10` for the authentic-client checksum, exactly as Java
/// `LoginPacketHandler.processLogin()` does — *with* the leading zero, since
/// that's how Java sees it).
pub fn decrypt_rsa(ciphertext: &[u8], private_key_pem: &str) -> Result<Vec<u8>, RsaError> {
    let key = RsaKey::from_pkcs8_pem(private_key_pem)?;
    Ok(decrypt_rsa_with_key(ciphertext, &key))
}

/// As [`decrypt_rsa`] but accepts a pre-parsed key — preferred in production
/// hot paths so we don't re-parse the PEM on every login.
pub fn decrypt_rsa_with_key(ciphertext: &[u8], key: &RsaKey) -> Vec<u8> {
    // `new BigInteger(byte[])` is signed two's-complement. We replicate that.
    let m = bigint_from_signed_be(ciphertext);

    // Java: m.modPow(d, n).
    // BigInteger.modPow normalises a negative base into [0, n) before
    // exponentiating, so we do the same: take m mod n as an unsigned value.
    let n = &key.modulus;
    let m_mod_n = match m {
        SignedBig::Positive(v) => v % n,
        SignedBig::Negative(abs) => {
            // -abs mod n  ==  n - (abs mod n)   (when abs mod n != 0)
            let r = abs % n;
            if r == BigUint::from(0u32) {
                BigUint::from(0u32)
            } else {
                n - r
            }
        }
    };
    let plaintext = m_mod_n.modpow(&key.private_exponent, n);

    // Java's BigInteger.toByteArray(): minimal signed two's-complement.
    bigint_to_signed_be(&plaintext)
}

/// Internal: signed BigInteger result of parsing a Java-style signed big-endian
/// byte array.
enum SignedBig {
    Positive(BigUint),
    Negative(BigUint), // stored as the absolute value
}

/// Mirror Java's `new BigInteger(byte[] val)`: interpret as two's-complement
/// big-endian. Empty array → 0. Negative high bit → negative.
fn bigint_from_signed_be(bytes: &[u8]) -> SignedBig {
    if bytes.is_empty() {
        return SignedBig::Positive(BigUint::from(0u32));
    }
    if bytes[0] & 0x80 == 0 {
        // Non-negative — bytes are the magnitude directly.
        SignedBig::Positive(BigUint::from_bytes_be(bytes))
    } else {
        // Negative — invert and add 1 to recover the magnitude.
        let mut inverted: Vec<u8> = bytes.iter().map(|b| !b).collect();
        // Add 1 (with carry) to the inverted big-endian representation.
        for byte in inverted.iter_mut().rev() {
            let (sum, carry) = byte.overflowing_add(1);
            *byte = sum;
            if !carry {
                break;
            }
        }
        SignedBig::Negative(BigUint::from_bytes_be(&inverted))
    }
}

/// Mirror Java's `BigInteger.toByteArray()` for a *non-negative* value:
/// minimal big-endian, with a single leading 0x00 when the natural MSB
/// has its high bit set (so the value reads as positive in two's-complement).
///
/// Special case: zero → `[0x00]` (Java returns a single zero byte for zero).
fn bigint_to_signed_be(value: &BigUint) -> Vec<u8> {
    if *value == BigUint::from(0u32) {
        return vec![0u8];
    }
    let mut bytes = value.to_bytes_be();
    if bytes[0] & 0x80 != 0 {
        bytes.insert(0, 0x00);
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Round-trip with a small handcrafted key: encrypt with the public side
    /// (m^e mod n) and decrypt with our function — output must equal the
    /// original plaintext interpreted as a Java BigInteger then re-serialised
    /// (i.e. `BigInteger(plaintext).toByteArray()`).
    ///
    /// This exercises the full modPow + signed-byte-array round-trip.
    #[test]
    fn raw_modpow_round_trip_small_key() {
        // Tiny RSA: p = 17, q = 23, n = 391, phi = 16 * 22 = 352.
        // e = 3 (gcd(3, 352) = 1). d = 3^-1 mod 352 = 235.
        let n = BigUint::from(391u32);
        let e = BigUint::from(3u32);
        let d = BigUint::from(235u32);
        let key = RsaKey::from_components(n.clone(), d);

        // Plaintext: 42.
        let plaintext_int = BigUint::from(42u32);
        let cipher_int = plaintext_int.modpow(&e, &n); // 42^3 mod 391

        // Serialise ciphertext as signed BE (matches what Java's
        // BigInteger.toByteArray() would emit on the client side).
        let cipher_bytes = bigint_to_signed_be(&cipher_int);

        // Decrypt.
        let decrypted = decrypt_rsa_with_key(&cipher_bytes, &key);

        // Expected: BigInteger(42).toByteArray() == [42].
        assert_eq!(decrypted, vec![42u8]);
    }

    /// Negative-input handling: if a ciphertext byte array has its high bit
    /// set, Java treats the value as negative. Our parser should normalise
    /// (mod n) the same way before exponentiating.
    #[test]
    fn handles_high_bit_set_input_like_java() {
        // n = 391 again. Pick ciphertext bytes [0x82] which is -126 in Java
        // signed interpretation. -126 mod 391 = 265.  265^235 mod 391 should
        // equal what Java would produce.
        let n = BigUint::from(391u32);
        let d = BigUint::from(235u32);
        let key = RsaKey::from_components(n.clone(), d);

        let cipher_bytes = vec![0x82u8];
        let got = decrypt_rsa_with_key(&cipher_bytes, &key);

        // Independently compute Java-style: ((-126).mod(391)) = 265, then 265^235 mod 391.
        let expected_int = BigUint::from(265u32).modpow(&BigUint::from(235u32), &n);
        let expected = bigint_to_signed_be(&expected_int);
        assert_eq!(got, expected);
    }

    /// Output formatting: a result whose magnitude has MSB high-bit set
    /// must come out with a leading 0x00 byte (matches Java).
    #[test]
    fn output_prepends_zero_for_high_bit_magnitude() {
        // Value 0xFF — natural BE is [0xFF], but Java's signed encoding adds
        // a 0x00 prefix → [0x00, 0xFF].
        let v = BigUint::from(0xFFu32);
        assert_eq!(bigint_to_signed_be(&v), vec![0x00, 0xFF]);

        // Value 0x80 — same story.
        let v = BigUint::from(0x80u32);
        assert_eq!(bigint_to_signed_be(&v), vec![0x00, 0x80]);

        // Value 0x7F — fits without prefix.
        let v = BigUint::from(0x7Fu32);
        assert_eq!(bigint_to_signed_be(&v), vec![0x7F]);

        // Zero — single 0x00 byte.
        let v = BigUint::from(0u32);
        assert_eq!(bigint_to_signed_be(&v), vec![0x00]);
    }

    /// Input parsing: empty / leading-zero / negative cases.
    #[test]
    fn input_parsing_matches_java_biginteger() {
        // Empty -> 0.
        match bigint_from_signed_be(&[]) {
            SignedBig::Positive(v) => assert_eq!(v, BigUint::from(0u32)),
            SignedBig::Negative(_) => panic!("empty bytes should be positive zero"),
        }

        // [0x00, 0xFF] -> 255.
        match bigint_from_signed_be(&[0x00, 0xFF]) {
            SignedBig::Positive(v) => assert_eq!(v, BigUint::from(255u32)),
            _ => panic!("expected positive"),
        }

        // [0xFF] -> -1 in Java (0xFF as signed byte).
        match bigint_from_signed_be(&[0xFF]) {
            SignedBig::Negative(abs) => assert_eq!(abs, BigUint::from(1u32)),
            _ => panic!("expected negative"),
        }

        // [0x80] -> -128.
        match bigint_from_signed_be(&[0x80]) {
            SignedBig::Negative(abs) => assert_eq!(abs, BigUint::from(128u32)),
            _ => panic!("expected negative"),
        }
    }
}
