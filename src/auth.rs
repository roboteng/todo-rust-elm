use rand::random;
use std::collections::{HashMap, hash_map::Entry};

pub type UserId = u64;

#[derive(Debug, Clone, Default)]
pub struct Users {
    users: HashMap<UserId, UserData>,
}

#[derive(Debug, Clone)]
pub struct UserData {
    username: String,
    password: String,
}

impl Users {
    pub fn try_add(&mut self, user: UserData) -> Option<UserId> {
        if self.users.iter().any(|u| u.1.username == user.username) {
            None
        } else {
            loop {
                let id = random();
                if let Entry::Vacant(e) = self.users.entry(id) {
                    e.insert(user);
                    return Some(id);
                } else {
                    continue;
                }
            }
        }
    }

    pub fn get(&self, username: impl AsRef<str>) -> Option<UserData> {
        self.users
            .iter()
            .find(|u| u.1.username.as_str() == username.as_ref())
            .map(|(_, data)| data.clone())
    }
}

impl UserData {
    pub fn new(username: String, password: String) -> Self {
        Self { username, password }
    }

    pub fn matches_password(&self, password: &str) -> bool {
        self.password == password
    }
}
