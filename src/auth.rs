use std::collections::HashMap;

pub type Entry<'a> = std::collections::hash_map::Entry<'a, String, UserData>;

#[derive(Debug, Clone, Default)]
pub struct Users(HashMap<String, UserData>);

#[derive(Debug, Clone)]
pub struct UserData {
    password: String,
}

impl Users {
    pub fn find(&mut self, username: String) -> Entry<'_> {
        self.0.entry(username)
    }

    pub fn get(&self, username: String) -> Option<UserData> {
        self.0.get(&username).cloned()
    }
}

impl UserData {
    pub fn new(password: String) -> Self {
        Self { password }
    }

    pub fn matches_password(&self, password: &str) -> bool {
        self.password == password
    }
}
