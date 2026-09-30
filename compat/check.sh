#!/usr/bin/env bash
# Rust -> Swift JSON compatibility check (acceptance criterion 4b).
#
# 1. Runs the Rust store's `write_fixture_for_swift_reader` test, which
#    saves a known notebook (Korean+emoji text, an absolute-point drawing
#    note, and a legacy note with no `drawingCoordinateSpace`) to a fixed
#    temp dir with the real Rust `MemoNotebookStore`.
# 2. Runs `compat/swift-reader read <dir>`, which copies that dir to its own
#    temp dir (never touches the Rust output in place) and loads it with the
#    real Swift `MemoNotebookStore`, printing a JSON summary.
# 3. Asserts the summary matches what the Rust side wrote and prints the
#    actual JSON.
#
# Never touches `~/Library/Application Support/MemoPet`. Requires `cargo`
# (PATH must include ~/.cargo/bin) and `swift`; both fetch only local
# workspace dependencies, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export PATH="$HOME/.cargo/bin:$PATH"

echo "== 1/3: writing a known notebook with the Rust store =="
cd "$REPO_ROOT/src-tauri"
RUST_TEST_OUTPUT="$(cargo test --lib -- --ignored --exact core::store::tests::write_fixture_for_swift_reader --nocapture 2>&1)"
echo "$RUST_TEST_OUTPUT" | grep -E "^test result:" || true
RUST_DIR="$(echo "$RUST_TEST_OUTPUT" | grep -o 'COMPAT_RUST_DIR=.*' | head -1 | cut -d= -f2-)"
if [ -z "$RUST_DIR" ]; then
  echo "FAIL: could not find COMPAT_RUST_DIR in cargo test output" >&2
  echo "$RUST_TEST_OUTPUT" >&2
  exit 1
fi
echo "Rust wrote: $RUST_DIR"
ls -la "$RUST_DIR"
# The drawing note carries a pen width the Swift app does not know about.
WIDTH_IN_FILE="$(jq -c '[.notes[].strokes[]?.width // empty]' "$RUST_DIR/notes.json")"
if [ "$(jq '[.notes[].strokes[]?.width // empty] == [5]' "$RUST_DIR/notes.json")" != "true" ]; then
  echo "FAIL: expected one stroke width 5 in the Rust file, got $WIDTH_IN_FILE" >&2
  exit 1
fi
echo "Rust file stroke widths: $WIDTH_IN_FILE"

echo
echo "== 2/3: reading it back with the real Swift MemoPetCore =="
cd "$REPO_ROOT/compat/swift-reader"
SUMMARY_JSON="$(swift run swift-reader read "$RUST_DIR" 2>/tmp/memopet-swift-reader-stderr.txt)"
echo "$SUMMARY_JSON"

echo
echo "== 3/3: comparing against what the Rust side wrote =="
FAILED=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc ($actual)"
  else
    echo "FAIL: $desc (expected $expected, got $actual)"
    FAILED=1
  fi
}

check "version"                 "4" "$(echo "$SUMMARY_JSON" | jq -r '.version')"
check "note count"              "3" "$(echo "$SUMMARY_JSON" | jq -r '.noteCount')"
check "selected index"          "0" "$(echo "$SUMMARY_JSON" | jq -r '.selectedIndex')"
check "note 0 title"            "Rust Fixture 다시" "$(echo "$SUMMARY_JSON" | jq -r '.notes[0].title')"
check "note 0 has coord space"  "true" "$(echo "$SUMMARY_JSON" | jq -r '.notes[0].hasDrawingCoordinateSpace')"
check "note 1 stroke points (stroke has an unknown width key)" "4" "$(echo "$SUMMARY_JSON" | jq -r '.notes[1].strokePointCounts[0]')"
check "note 2 title"            "Legacy" "$(echo "$SUMMARY_JSON" | jq -r '.notes[2].title')"
check "note 2 stroke points"    "2" "$(echo "$SUMMARY_JSON" | jq -r '.notes[2].strokePointCounts[0]')"
check "note 2 has coord space (must be false: legacy notes omit the key)" "false" "$(echo "$SUMMARY_JSON" | jq -r '.notes[2].hasDrawingCoordinateSpace')"
# Contents, not just counts (a writer that blanked text or zeroed points must fail).
check "note 0 text"             "$(printf 'rust text line1\nrust text line2 emoji 🦀')" "$(echo "$SUMMARY_JSON" | jq -r '.notes[0].text')"
check "note 1 text"             "" "$(echo "$SUMMARY_JSON" | jq -r '.notes[1].text')"
check "note 2 text"             "legacy from rust" "$(echo "$SUMMARY_JSON" | jq -r '.notes[2].text')"
check "note 1 points"           "[[[1,2],[3.5,4.5],[10,0],[0,10]]]" "$(echo "$SUMMARY_JSON" | jq -c '.notes[1].points')"
check "note 2 points (legacy normalized values kept)" "[[[0.2,0.4],[0.6,0.8]]]" "$(echo "$SUMMARY_JSON" | jq -c '.notes[2].points')"

echo
if [ "$FAILED" = "0" ]; then
  echo "RESULT: PASS — Rust-written notes.json loads correctly in the real Swift MemoPetCore."
else
  echo "RESULT: FAIL — see above."
  exit 1
fi
