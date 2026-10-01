//! Built-in characters. To add one, put its GIF (square, transparent, about
//! 256 × 256) in `public/characters/` and add a line to `BUILT_IN`; settings,
//! menus and both platforms read this list. `scripts/character-gif.py` makes
//! such a GIF from a picture on a chroma-green background (`art/characters/`).

use tauri::AppHandle;

#[derive(Debug, PartialEq, Eq)]
pub struct Builtin {
    /// Saved in settings.json, so it must never change once released.
    pub id: &'static str,
    /// Shown in the menus: a name, the same in every language.
    pub name: &'static str,
    /// File in `public/characters/`.
    pub file: &'static str,
}

/// In menu order. The first one is the default character.
pub const BUILT_IN: &[Builtin] = &[
    Builtin { id: "memoWriter", name: "Memo Writer", file: "memo-writer.gif" },
    Builtin { id: "penguin", name: "Penguin", file: "penguin.gif" },
    Builtin { id: "ghost", name: "Ghost", file: "ghost.gif" },
    Builtin { id: "shiba", name: "Shiba", file: "shiba.gif" },
    Builtin { id: "pebble", name: "Pebble", file: "pebble.gif" },
    Builtin { id: "orbitingPlanet", name: "Orbiting Planet", file: "orbiting-planet.gif" },
    Builtin { id: "bluePlanet", name: "Blue Planet", file: "blue-planet.gif" },
    Builtin { id: "crescentMoon", name: "Crescent Moon", file: "crescent-moon.gif" },
];

pub fn find(id: &str) -> Option<&'static Builtin> {
    BUILT_IN.iter().find(|builtin| builtin.id == id)
}

/// Where the web pages load it from (the Windows character page).
#[cfg_attr(target_os = "macos", allow(dead_code))]
pub fn url(builtin: &Builtin) -> String {
    format!("/characters/{}", builtin.file)
}

/// The GIF itself, from the frontend files bundled into the app.
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
pub fn bytes(app: &AppHandle, builtin: &Builtin) -> Option<Vec<u8>> {
    let bundled = app
        .asset_resolver()
        .get(format!("characters/{}", builtin.file))
        .map(|asset| asset.bytes)
        // A missing file can resolve to index.html; only a GIF counts.
        .filter(|bytes| bytes.starts_with(b"GIF8"));
    // `tauri dev` without a built frontend: read the source folder.
    #[cfg(debug_assertions)]
    let bundled = bundled.or_else(|| {
        std::fs::read(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../public/characters").join(builtin.file)).ok()
    });
    bundled
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::path::Path;

    #[test]
    fn every_built_in_has_a_unique_id_and_a_gif() {
        let mut ids = HashSet::new();
        for builtin in BUILT_IN {
            assert!(ids.insert(builtin.id), "duplicate id {}", builtin.id);
            assert!(!matches!(builtin.id, "classic" | "custom"), "{} is reserved", builtin.id);
            let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../public/characters").join(builtin.file);
            let bytes = std::fs::read(&path).unwrap_or_else(|_| panic!("missing {}", path.display()));
            assert!(bytes.starts_with(b"GIF8"), "{} is not a GIF", builtin.file);
            // The size in the GIF header: square, like the character window.
            let (width, height) = (u16::from_le_bytes([bytes[6], bytes[7]]), u16::from_le_bytes([bytes[8], bytes[9]]));
            assert!(width == height && (64..=512).contains(&width), "{} is {width} × {height}", builtin.file);
        }
        // Earlier versions saved these ids; they must keep working.
        assert!(find("memoWriter").is_some() && find("orbitingPlanet").is_some());
        assert_eq!(BUILT_IN[0].id, "memoWriter");
    }
}
