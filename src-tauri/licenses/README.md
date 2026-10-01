# License texts for crates published without license files

A few crates that ship inside the app do not include their license files in
the crates.io package. `scripts/third-party-licenses.py` uses these copies,
taken from each crate's `repository` on 2026-10-01, so the notices carry the
real copyright lines instead of a template. Folder names are
`<owner>__<repository>`.

| Folder | Source | Crates |
| --- | --- | --- |
| `dropbox__rust-alloc-no-stdlib` | https://github.com/dropbox/rust-alloc-no-stdlib (`LICENSE`) | alloc-stdlib |
| `madsmtm__objc2` | https://github.com/madsmtm/objc2 (`LICENSE-*.txt`, `LICENSE.md`) | objc2, block2, dispatch2, objc2-* |
| `wravery__webview2-rs` | https://github.com/wravery/webview2-rs (`LICENSE`) | webview2-com, webview2-com-sys |
| `servo__stylo` | https://www.mozilla.org/MPL/2.0/ (the repository states MPL-2.0 per file) | selectors |
