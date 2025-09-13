use rand::random;
use std::collections::{HashMap, hash_map::Entry};

pub type UserId = u64;
pub type SessionId = u64;

#[derive(Debug, Clone, Default)]
pub struct Users {
    users: HashMap<UserId, UserData>,
    sessions: HashMap<SessionId, UserId>,
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

    pub fn try_login(&mut self, username: String, password: String) -> Option<UserId> {
        let user_id = self
            .users
            .iter()
            .find(|u| u.1.username == username && u.1.password == password)
            .map(|(id, _)| *id)?;
        let session_id = random();
        self.sessions.insert(session_id, user_id);
        Some(session_id)
    }

    pub fn get_session(&self, session_id: SessionId) -> Option<UserId> {
        self.sessions.get(&session_id).copied()
    }

    pub fn get_sessions(&self, id: UserId) -> Vec<SessionId> {
        self.sessions
            .iter()
            .filter(|(_session, user_id)| **user_id == id)
            .map(|(id, _)| *id)
            .collect()
    }
}

impl UserData {
    pub fn new(username: String, password: String) -> Self {
        Self { username, password }
    }
}
