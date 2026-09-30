import Foundation
import MemoPetCore

// compat/swift-reader — a tiny CLI used only for cross-language JSON
// compatibility checks between the Rust core (this repo) and the real
// Swift MemoPetCore (`../../../memo_pet`).
//
//   swift-reader read <dir>      Copies <dir> to a temp dir, loads it with
//                                 MemoNotebookStore (never touches <dir>
//                                 itself), and prints a JSON summary
//                                 (note count, titles, text lengths, stroke
//                                 point counts) to stdout.
//   swift-reader generate <dir>  Writes a dummy fixture notebook (Korean +
//                                 emoji text, a titled note, absolute-point
//                                 strokes, and a legacy note with no
//                                 drawingCoordinateSpace) to <dir> using the
//                                 real MemoNotebookStore, for `fixtures/`.
//
// Never points at `~/Library/Application Support/MemoPet` (real user data);
// both modes only ever touch the directory passed on the command line (plus
// a private temp copy for `read`).

struct NoteSummary: Codable {
  let title: String?
  let text: String
  let textLength: Int
  let strokePointCounts: [Int]
  let points: [[[Double]]]
  let hasDrawingCoordinateSpace: Bool
}

struct NotebookSummary: Codable {
  let version: Int
  let noteCount: Int
  let selectedIndex: Int
  let notes: [NoteSummary]
}

func printJSON<T: Encodable>(_ value: T) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
  let data = try encoder.encode(value)
  print(String(data: data, encoding: .utf8)!)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(1)
}

func readMode(sourceDir: String) throws {
  let sourceURL = URL(fileURLWithPath: sourceDir, isDirectory: true)
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
    fail("Not a directory: \(sourceDir)")
  }

  // Read-only with respect to the caller's directory: copy into a private
  // temp dir and let MemoNotebookStore create/chmod/normalize only there.
  let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
    "swift-reader-\(UUID().uuidString)", isDirectory: true
  )
  try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: tempDir) }

  let items = try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
  for item in items {
    let destination = tempDir.appendingPathComponent(item.lastPathComponent)
    try FileManager.default.copyItem(at: item, to: destination)
  }

  let store = try MemoNotebookStore(directoryURL: tempDir)
  let notebook = try store.load()

  let summary = NotebookSummary(
    version: notebook.version,
    noteCount: notebook.notes.count,
    selectedIndex: notebook.selectedIndex,
    notes: notebook.notes.map { note in
      NoteSummary(
        title: note.title,
        text: note.text,
        textLength: note.text.count,
        strokePointCounts: note.strokes.map { $0.points.count },
        points: note.strokes.map { $0.points.map { [$0.x, $0.y] } },
        hasDrawingCoordinateSpace: note.drawingCoordinateSpace != nil
      )
    }
  )
  try printJSON(summary)
}

func generateMode(outputDir: String) throws {
  let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)

  let titled = MemoNote(
    title: "장보기 목록",
    text: "fixture text 가나다\n둘째 줄 with emoji 🐈\nthird line"
  )
  let absoluteDrawing = MemoNote(
    title: "Sketch",
    text: "",
    strokes: [
      MemoStroke(points: [
        MemoPoint(x: 12, y: 24),
        MemoPoint(x: 48, y: 96.5),
        MemoPoint(x: 100, y: 12),
      ])
    ],
    drawingCoordinateSpace: .absolutePoints
  )
  let legacyDrawing = MemoNote(
    text: "Legacy normalized drawing (no drawingCoordinateSpace key)",
    strokes: [
      MemoStroke(points: [
        MemoPoint(x: 0.1, y: 0.25),
        MemoPoint(x: 0.9, y: 0.75),
      ])
    ],
    drawingCoordinateSpace: nil
  )
  let plainEmpty = MemoNote()

  let notebook = MemoNotebook(
    notes: [titled, absoluteDrawing, legacyDrawing, plainEmpty],
    selectedNoteID: titled.id
  )

  let store = try MemoNotebookStore(directoryURL: outputURL)
  try store.save(notebook)
  FileHandle.standardError.write("Generated fixture at \(store.notebookURL.path)\n".data(using: .utf8)!)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  fail("Usage: swift-reader read <dir> | swift-reader generate <dir>")
}
let mode = arguments[1]
let path = arguments[2]

do {
  switch mode {
  case "read":
    try readMode(sourceDir: path)
  case "generate":
    try generateMode(outputDir: path)
  default:
    fail("Unknown mode: \(mode)")
  }
} catch {
  fail("Error: \(error)")
}
