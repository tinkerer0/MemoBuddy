//! Korean when the system prefers Korean, English otherwise.

use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Language {
    Korean,
    English,
}

pub fn language() -> Language {
    static LANGUAGE: OnceLock<Language> = OnceLock::new();
    *LANGUAGE.get_or_init(|| {
        let preferred = sys_locale::get_locale().unwrap_or_default();
        if preferred.to_ascii_lowercase().starts_with("ko") {
            Language::Korean
        } else {
            Language::English
        }
    })
}

pub fn code() -> &'static str {
    match language() {
        Language::Korean => "ko",
        Language::English => "en",
    }
}

/// `tr("메모 열기", "Open Memo")`
pub fn tr(korean: &'static str, english: &'static str) -> &'static str {
    match language() {
        Language::Korean => korean,
        Language::English => english,
    }
}
