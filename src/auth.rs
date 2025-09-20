use bcrypt_pbkdf::bcrypt_pbkdf;
use rand::random;
use std::collections::{HashMap, hash_map::Entry};

pub type UserId = u64;
pub type SessionId = u64;
type PassHash = [u8; 32];
type Salt = [u8; 32];
const BCRYPT_ROUNDS: u32 = 10;

#[derive(Debug, Clone, Default)]
pub struct Users {
    users: HashMap<UserId, UserData>,
    sessions: HashMap<SessionId, UserId>,
}

#[derive(Debug, Clone)]
pub struct UserData {
    username: String,
    pass_hash: PassHash,
    salt: Salt,
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
            .find(|u| {
                if u.1.username == username {
                    // TODO: fix for possible timing attack
                    let user = u.1;
                    let mut pass_hash = PassHash::default();
                    bcrypt_pbkdf(&password, &user.salt, BCRYPT_ROUNDS, &mut pass_hash).unwrap();
                    pass_hash == user.pass_hash
                } else {
                    false
                }
            })
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

    pub fn logout_session(&mut self, session_id: SessionId) {
        self.sessions.remove(&session_id);
    }
}

pub enum AccountCreationError {
    PasswordTooShort,
}

impl UserData {
    pub fn new(username: String, password: String) -> Result<Self, AccountCreationError> {
        let salt: Salt = random();
        let mut pass_hash = PassHash::default();
        bcrypt_pbkdf(&password, &salt, BCRYPT_ROUNDS, &mut pass_hash)
            .map_err(|_| AccountCreationError::PasswordTooShort)?;
        Ok(Self {
            username,
            pass_hash,
            salt,
        })
    }
}
