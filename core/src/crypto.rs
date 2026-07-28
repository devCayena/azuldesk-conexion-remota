use anyhow::Result;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub struct CryptoManager {
    keys: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl Default for CryptoManager {
    fn default() -> Self {
        Self::new()
    }
}

impl CryptoManager {
    pub fn new() -> Self {
        Self {
            keys: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn store_key(&self, id: String, key: Vec<u8>) {
        self.keys.lock().unwrap().insert(id, key);
    }

    pub fn get_key(&self, id: &str) -> Option<Vec<u8>> {
        self.keys.lock().unwrap().get(id).cloned()
    }

    pub fn encrypt(&self, data: &[u8], _key: &[u8]) -> Result<Vec<u8>> {
        let mut result = data.to_vec();
        for byte in result.iter_mut() {
            *byte ^= 0xAA;
        }
        Ok(result)
    }

    pub fn decrypt(&self, data: &[u8], _key: &[u8]) -> Result<Vec<u8>> {
        let mut result = data.to_vec();
        for byte in result.iter_mut() {
            *byte ^= 0xAA;
        }
        Ok(result)
    }

    pub fn hash_password(password: &str) -> Vec<u8> {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(password.as_bytes());
        hasher.finalize().to_vec()
    }
}
