//! Platform-independent core: notebook model, on-disk store, window placement
//! math and the read-only mobile mirror. Ported from the Swift `MemoPetCore`
//! in `desk-utils/memo_pet`; `notes.json` v4 stays byte-compatible in meaning
//! with that app so data can move between them.

mod fsutil;
pub mod mirror;
pub mod model;
pub mod placement;
pub mod store;
