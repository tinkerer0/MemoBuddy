import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  convertLegacyStrokes,
  DEFAULT_STROKE_WIDTH,
  drawingExtent,
  ERASER_RADII,
  erasing,
  MIN_POINT_DISTANCE,
  PEN_WIDTHS,
  type Point,
  type Stroke,
} from "../shared/drawing";
import { setLanguage, t } from "../shared/i18n";

type Space = "absolutePoints" | null;
type NoteDto = { id: string; title: string | null; text: string; strokes: Stroke[]; drawingCoordinateSpace: Space };
type NotebookDto = { notes: NoteDto[]; selectedId: string; recoveryNotice: string | null; generationFloor: number };
type Note = NoteDto & { generation: number; savedGeneration: number; undo: Stroke[][] };
type Tool = "none" | "draw" | "erase";

const $ = <T extends HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const memo = $<HTMLElement>("#memo");
const tabs = $<HTMLDivElement>("#tabs");
const addButton = $<HTMLButtonElement>("#add");
const penButton = $<HTMLButtonElement>("#pen");
const eraserButton = $<HTMLButtonElement>("#eraser");
const scroller = $<HTMLDivElement>("#scroller");
const sheet = $<HTMLDivElement>("#sheet");
const editor = $<HTMLTextAreaElement>("#editor");
const canvas = $<HTMLCanvasElement>("#canvas");
const status = $<HTMLDivElement>("#status");
const statusText = $<HTMLSpanElement>("#status-text");
const statusAction = $<HTMLButtonElement>("#status-action");

const UNDO_DEPTH = 50;

// Pen and eraser sizes: small / medium / large, remembered on this computer.
const storedIndex = (key: string) => {
  try {
    // Nothing stored yet (null) must mean the middle size, not Number(null) = 0.
    const value = localStorage.getItem(key);
    return value !== null && /^[0-2]$/.test(value) ? Number(value) : 1;
  } catch {
    return 1;
  }
};
let penIndex = storedIndex("memopet.penSize");
let eraserIndex = storedIndex("memopet.eraserSize");
const rememberIndex = (key: string, value: number) => {
  try {
    localStorage.setItem(key, String(value));
  } catch {
    // Private storage unavailable: the choice lasts until the app quits.
  }
};
const SAVE_DELAY_MS = 300;
/** Typing without a pause still saves at least this often. */
const SAVE_MAX_WAIT_MS = 1000;

let notes: Note[] = [];
let selectedId = "";
let tool: Tool = "none";
let busy = false;
let closing = false;
let saveError = "";
let notice = "";
/** First-run tip (click / right-click), shown until dismissed. */
let tip = false;
let clockValue = Date.now() * 1000;
const clock = () => ++clockValue;
const timers = new Map<string, number>();
/** When each note's oldest unsaved change was made (for SAVE_MAX_WAIT_MS). */
const unsavedSince = new Map<string, number>();
const inflight = new Map<string, Promise<boolean>>();

const current = () => notes.find((note) => note.id === selectedId) ?? notes[0];
const titleOf = (note: Note) => note.title?.trim() || t(`메모 ${notes.indexOf(note) + 1}`, `Note ${notes.indexOf(note) + 1}`);
const dirtyCount = () => notes.filter((note) => note.savedGeneration < note.generation).length;

// ---------- saving ----------

function markDirty(note: Note) {
  note.generation = clock();
  const now = Date.now();
  const since = unsavedSince.get(note.id) ?? now;
  unsavedSince.set(note.id, since);
  window.clearTimeout(timers.get(note.id));
  const delay = Math.max(0, Math.min(SAVE_DELAY_MS, since + SAVE_MAX_WAIT_MS - now));
  timers.set(note.id, window.setTimeout(() => void saveNote(note), delay));
}

async function saveNote(note: Note): Promise<boolean> {
  window.clearTimeout(timers.get(note.id));
  timers.delete(note.id);
  unsavedSince.delete(note.id);
  // Join whatever save is running, including one another waiter started just
  // before us, so a slow reply does not release several identical saves.
  for (let running = inflight.get(note.id); running; running = inflight.get(note.id)) await running;
  if (note.savedGeneration >= note.generation) return true;
  const generation = note.generation;
  const request = invoke<{ saved: boolean; stale: boolean }>("save_note", {
    noteId: note.id,
    generation,
    text: note.text,
    strokes: note.strokes,
    drawingCoordinateSpace: note.drawingCoordinateSpace,
  }).then(
    () => {
      note.savedGeneration = Math.max(note.savedGeneration, generation);
      if (saveError && dirtyCount() === 0) setError("");
      return true;
    },
    (error: unknown) => {
      setError(String(error));
      return false;
    },
  );
  inflight.set(note.id, request);
  const ok = await request;
  inflight.delete(note.id);
  if (ok && note.savedGeneration < note.generation) return saveNote(note);
  return ok;
}

async function flushAll(): Promise<boolean> {
  finishGesture();
  await commitComposition();
  syncEditor();
  const results = await Promise.all(notes.map((note) => saveNote(note)));
  return results.every(Boolean);
}

let composing = false;
let compositionEnded: (() => void) | null = null;
editor.addEventListener("compositionstart", () => (composing = true));
editor.addEventListener("compositionend", () => {
  composing = false;
  compositionEnded?.();
});

/** Ends an IME composition so its final characters are in the value. */
async function commitComposition() {
  if (!composing) return;
  const ended = new Promise<void>((resolve) => {
    compositionEnded = resolve;
    window.setTimeout(resolve, 300);
  });
  editor.blur();
  await ended;
  compositionEnded = null;
  await new Promise((resolve) => window.setTimeout(resolve, 0));
}

function syncEditor() {
  const note = current();
  if (note && note.text !== editor.value) {
    note.text = editor.value;
    markDirty(note);
  }
}

function setError(message: string) {
  saveError = message;
  paintStatus();
}

function paintStatus() {
  if (saveError) {
    status.hidden = false;
    status.dataset.kind = "error";
    statusText.textContent = saveError;
    statusAction.textContent = t("다시 저장", "Save Again");
  } else if (notice) {
    status.hidden = false;
    status.dataset.kind = "info";
    statusText.textContent = notice;
    statusAction.textContent = t("확인", "OK");
  } else if (tip) {
    status.hidden = false;
    status.dataset.kind = "info";
    statusText.textContent = t(
      "캐릭터를 누르면 메모가 열리고, 다른 곳을 누르면 저장돼요. 캐릭터를 우클릭하면 캐릭터·크기·테마를 바꿀 수 있어요.",
      "Click the pet to open your memo; click anywhere else to save and close. Right-click the pet to change its look, size and theme.",
    );
    statusAction.textContent = t("알겠어요", "Got it");
  } else {
    status.hidden = true;
  }
}

statusAction.onclick = async () => {
  if (saveError) {
    if (await flushAll()) setError("");
  } else if (notice) {
    notice = "";
    paintStatus();
  } else if (tip) {
    try {
      await invoke("dismiss_tip");
      tip = false;
    } catch {
      // Not saved: keep the tip so it can be dismissed again.
    }
    paintStatus();
  }
};

// ---------- loading ----------

function hydrate(book: NotebookDto) {
  clockValue = Math.max(clockValue, book.generationFloor ?? 0);
  const previous = new Map(notes.map((note) => [note.id, note]));
  notes = book.notes.map((dto) => {
    const old = previous.get(dto.id);
    // A stroke being drawn right now keeps drawing into the same note object.
    if (old && old === gestureNote) {
      old.title = dto.title;
      return old;
    }
    // Typing that happened while this reply was on its way wins over the
    // older copy in the reply; it stays dirty and saves normally.
    if (old && old.generation > old.savedGeneration) {
      return { ...dto, text: old.text, strokes: old.strokes, drawingCoordinateSpace: old.drawingCoordinateSpace, generation: old.generation, savedGeneration: old.savedGeneration, undo: old.undo };
    }
    const generation = old ? Math.max(old.generation, old.savedGeneration) : clock();
    return { ...dto, strokes: dto.strokes ?? [], generation, savedGeneration: generation, undo: old?.undo ?? [] };
  });
  selectedId = book.selectedId;
  for (const note of notes) if (note.savedGeneration < note.generation) markDirty(note);
  if (book.recoveryNotice) {
    notice = book.recoveryNotice;
    paintStatus();
  }
  showSelected();
}

function showSelected() {
  const note = current();
  if (!note) return;
  if (editor.value !== note.text) editor.value = note.text;
  editor.setAttribute("aria-label", `${t("메모", "Note")}: ${titleOf(note)}`);
  layout();
  if (note.drawingCoordinateSpace === null && note.strokes.length) {
    note.strokes = convertLegacyStrokes(note.strokes, canvas.clientWidth, canvas.clientHeight);
    note.drawingCoordinateSpace = "absolutePoints";
    markDirty(note);
    layout();
  }
  paintTabs();
  redraw();
}

async function reload() {
  hydrate(await invoke<NotebookDto>("load_notebook"));
}

// ---------- layout and drawing ----------

function layout() {
  const note = current();
  const top = scroller.scrollTop;
  editor.style.height = "0px";
  const height = Math.max(editor.scrollHeight, scroller.clientHeight, note ? drawingExtent(note.strokes) : 0);
  editor.style.height = `${height}px`;
  sheet.style.height = `${height}px`;
  const width = sheet.clientWidth;
  const ratio = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
  }
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  scroller.scrollTop = top;
}

function redraw() {
  const note = current();
  const context = canvas.getContext("2d");
  if (!context || !note) return;
  const ratio = window.devicePixelRatio || 1;
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.strokeStyle = context.fillStyle = getComputedStyle(editor).color;
  context.lineCap = "round";
  context.lineJoin = "round";
  for (const stroke of note.strokes) {
    const [first, ...rest] = stroke.points;
    if (!first) continue;
    const width = stroke.width ?? DEFAULT_STROKE_WIDTH;
    context.lineWidth = width;
    if (!rest.length) {
      context.beginPath();
      context.arc(first.x, first.y, width / 2, 0, Math.PI * 2);
      context.fill();
      continue;
    }
    context.beginPath();
    context.moveTo(first.x, first.y);
    for (const point of rest) context.lineTo(point.x, point.y);
    context.stroke();
  }
}

let activeStroke: Stroke | null = null;
let lastErase: Point | null = null;
let strokeChanged = false;
/** The note a stroke or erase is being drawn on (kept across replies). */
let gestureNote: Note | null = null;

function pointFrom(event: PointerEvent): Point {
  return { x: Math.min(Math.max(event.offsetX, 0), canvas.clientWidth), y: Math.min(Math.max(event.offsetY, 0), canvas.clientHeight) };
}

function pushUndo(note: Note) {
  note.undo.push(note.strokes.map((stroke) => ({ ...stroke, points: [...stroke.points] })));
  if (note.undo.length > UNDO_DEPTH) note.undo.shift();
}

canvas.addEventListener("pointerdown", (event) => {
  const note = current();
  if (tool === "none" || event.button !== 0 || !note) return;
  event.preventDefault();
  canvas.setPointerCapture(event.pointerId);
  gestureNote = note;
  pushUndo(note);
  strokeChanged = false;
  const point = pointFrom(event);
  if (tool === "draw") {
    activeStroke = { points: [point], width: PEN_WIDTHS[penIndex] };
    note.strokes.push(activeStroke);
    note.drawingCoordinateSpace = "absolutePoints";
    strokeChanged = true;
  } else {
    lastErase = point;
    eraseTo(note, point);
  }
  redraw();
});

canvas.addEventListener("pointermove", (event) => {
  // The note the gesture began on, even if a reply switched tabs meanwhile.
  const note = gestureNote;
  if (!note || !canvas.hasPointerCapture(event.pointerId)) return;
  const point = pointFrom(event);
  if (activeStroke) {
    const last = activeStroke.points[activeStroke.points.length - 1];
    if (Math.hypot(point.x - last.x, point.y - last.y) < MIN_POINT_DISTANCE) return;
    activeStroke.points.push(point);
  } else if (lastErase) {
    eraseTo(note, point);
    lastErase = point;
  }
  redraw();
});

function eraseTo(note: Note, point: Point) {
  const next = erasing(note.strokes, lastErase ?? point, point, ERASER_RADII[eraserIndex]);
  if (next !== note.strokes && JSON.stringify(next) !== JSON.stringify(note.strokes)) {
    note.strokes = next;
    strokeChanged = true;
  }
}

function endStroke(event: PointerEvent) {
  if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
  finishGesture();
}

/** Commits a stroke or erase that is still in progress (e.g. Esc mid-draw). */
function finishGesture() {
  const note = gestureNote;
  if (note && (activeStroke || lastErase)) {
    if (strokeChanged) {
      markDirty(note);
      layout();
      redraw();
    } else {
      note.undo.pop();
    }
  }
  activeStroke = null;
  lastErase = null;
  gestureNote = null;
}

canvas.addEventListener("contextmenu", (event) => {
  event.preventDefault();
  if (tool !== "none") openSizeMenu(tool, event.clientX, event.clientY);
});

canvas.addEventListener("pointerup", endStroke);
canvas.addEventListener("pointercancel", endStroke);

function undoDrawing() {
  const note = current();
  const previous = note?.undo.pop();
  if (!note || !previous) return;
  note.strokes = previous;
  markDirty(note);
  layout();
  redraw();
}

const sizeNames = () => [t("가늘게", "Thin"), t("보통", "Medium"), t("굵게", "Thick")];
const eraserNames = () => [t("작게", "Small"), t("보통", "Medium"), t("크게", "Large")];

function paintTools() {
  const sizeHint = t(" · 우클릭으로 크기", " · right-click for size");
  penButton.setAttribute("aria-pressed", String(tool === "draw"));
  eraserButton.setAttribute("aria-pressed", String(tool === "erase"));
  penButton.title = penButton.ariaLabel =
    (tool === "draw" ? t("글쓰기로 돌아가기", "Return to Text") : t("그리기", "Draw")) + ` (${sizeNames()[penIndex]})` + sizeHint;
  eraserButton.title = eraserButton.ariaLabel =
    (tool === "erase" ? t("글쓰기로 돌아가기", "Return to Text") : t("지우개", "Erase Drawing")) + ` (${eraserNames()[eraserIndex]})` + sizeHint;
  const radius = ERASER_RADII[eraserIndex];
  const side = radius * 2 + 4;
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='${side}' height='${side}'><circle cx='${side / 2}' cy='${side / 2}' r='${radius}' fill='rgba(128,128,128,.12)' stroke='%23888' stroke-width='1.2'/></svg>`;
  canvas.style.cursor = tool === "erase" ? `url("data:image/svg+xml,${svg}") ${side / 2} ${side / 2}, crosshair` : "";
}

function setTool(next: Tool) {
  tool = tool === next ? "none" : next;
  memo.dataset.tool = tool;
  editor.readOnly = tool !== "none";
  paintTools();
  if (tool === "none") focusEditor(false);
}

// ---------- pen / eraser size menu (right-click) ----------

const sizeMenu = document.createElement("div");
sizeMenu.id = "size-menu";
sizeMenu.setAttribute("role", "menu");
sizeMenu.hidden = true;
document.body.append(sizeMenu);
let sizeMenuReturn: HTMLElement | null = null;

function openSizeMenu(kind: Tool, x?: number, y?: number, returnFocus?: HTMLElement) {
  if (kind === "none") return;
  closeMenu();
  sizeMenuReturn = returnFocus ?? null;
  const pen = kind === "draw";
  const names = pen ? sizeNames() : eraserNames();
  const selected = pen ? penIndex : eraserIndex;
  const title = document.createElement("div");
  title.className = "size-title";
  title.textContent = pen ? t("선 굵기", "Line Width") : t("지우개 크기", "Eraser Size");
  const items = names.map((name, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("role", "menuitemradio");
    button.setAttribute("aria-checked", String(index === selected));
    const check = document.createElement("span");
    check.className = "check";
    check.textContent = index === selected ? "✓" : "";
    const dot = document.createElement("span");
    dot.className = "dot";
    const diameter = pen ? Math.max(3, PEN_WIDTHS[index] + 1) : ERASER_RADII[index];
    dot.style.width = dot.style.height = `${diameter}px`;
    const label = document.createElement("span");
    label.textContent = name;
    button.append(check, dot, label);
    button.onclick = () => {
      if (pen) {
        penIndex = index;
        rememberIndex("memopet.penSize", index);
      } else {
        eraserIndex = index;
        rememberIndex("memopet.eraserSize", index);
      }
      closeSizeMenu(true);
      if (tool !== kind) setTool(kind);
      else paintTools();
    };
    return button;
  });
  sizeMenu.replaceChildren(title, ...items);
  sizeMenu.hidden = false;
  const anchor = (pen ? penButton : eraserButton).getBoundingClientRect();
  const left = x ?? anchor.right - sizeMenu.offsetWidth;
  const top = y ?? anchor.bottom + 3;
  sizeMenu.style.left = `${Math.max(6, Math.min(window.innerWidth - sizeMenu.offsetWidth - 6, left))}px`;
  sizeMenu.style.top = `${Math.max(6, Math.min(window.innerHeight - sizeMenu.offsetHeight - 6, top))}px`;
  items[selected].focus();
}

function closeSizeMenu(restoreFocus = false) {
  sizeMenu.hidden = true;
  if (restoreFocus) sizeMenuReturn?.focus();
  sizeMenuReturn = null;
}

sizeMenu.onkeydown = (event) => {
  const items = [...sizeMenu.querySelectorAll<HTMLButtonElement>("button")];
  const index = items.indexOf(document.activeElement as HTMLButtonElement);
  if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    closeSizeMenu(true);
  } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    const next = (index + (event.key === "ArrowDown" ? 1 : items.length - 1)) % items.length;
    items[next].focus();
  }
};

document.addEventListener(
  "pointerdown",
  (event) => {
    if (!sizeMenu.hidden && !(event.target instanceof Node && sizeMenu.contains(event.target))) closeSizeMenu();
  },
  { capture: true },
);

for (const [button, kind] of [
  [penButton, "draw"],
  [eraserButton, "erase"],
] as const) {
  button.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    openSizeMenu(kind, event.clientX, event.clientY, button);
  });
  button.addEventListener("keydown", (event) => {
    if (event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")) {
      event.preventDefault();
      openSizeMenu(kind, undefined, undefined, button);
    }
  });
}

penButton.onclick = () => setTool("draw");
eraserButton.onclick = () => setTool("erase");

editor.addEventListener("input", () => {
  const note = current();
  if (!note) return;
  note.text = editor.value;
  markDirty(note);
  layout();
});

function focusEditor(toEnd: boolean) {
  if (tool !== "none") return;
  editor.focus({ preventScroll: true });
  if (toEnd) {
    const end = editor.value.length;
    editor.setSelectionRange(end, end);
    scroller.scrollTop = scroller.scrollHeight;
  }
}

// ---------- tabs ----------

async function mutate(command: string, args: Record<string, unknown>, takeFocus = true): Promise<boolean> {
  if (busy) return false;
  busy = true;
  paintTabs();
  try {
    if (!(await flushAll())) return false;
    hydrate(await invoke<NotebookDto>(command, args));
    if (takeFocus) focusEditor(true);
    return true;
  } catch (error) {
    setError(String(error));
    return false;
  } finally {
    busy = false;
    paintTabs();
  }
}

const iconRename =
  '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m10.5 2.5 3 3-7.8 7.8-3.6.6.6-3.6z"/></svg>';
const iconDelete =
  '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.7 8.5h5.6l.7-8.5"/></svg>';

function paintTabs() {
  const existing = new Map([...tabs.children].map((child) => [(child as HTMLElement).dataset.noteId!, child as HTMLElement]));
  for (const [id, element] of existing) if (!notes.some((note) => note.id === id)) element.remove();
  notes.forEach((note, index) => {
    let item = existing.get(note.id);
    if (!item) {
      item = createTab(note.id);
    }
    const button = item.querySelector<HTMLButtonElement>(".tab")!;
    const title = titleOf(note);
    button.textContent = title;
    button.title = `${title} · ${t("끌어서 순서 변경 · 더블클릭으로 이름 변경", "Drag to reorder · double-click to rename")}`;
    button.setAttribute("aria-selected", String(note.id === selectedId));
    item.classList.toggle("selected", note.id === selectedId);
    button.tabIndex = note.id === selectedId ? 0 : -1;
    button.disabled = busy;
    const [rename, remove] = item.querySelectorAll<HTMLButtonElement>(".tab-actions button");
    rename.disabled = remove.disabled = busy;
    rename.title = rename.ariaLabel = t(`${title} 이름 변경`, `Rename ${title}`);
    remove.title = remove.ariaLabel = t(`${title} 삭제`, `Delete ${title}`);
    if (tabs.children[index] !== item) tabs.insertBefore(item, tabs.children[index] ?? null);
  });
  addButton.disabled = busy;
  const selected = tabs.querySelector<HTMLElement>('.tab[aria-selected="true"]');
  selected?.scrollIntoView({ block: "nearest", inline: "nearest" });
}

function createTab(id: string): HTMLElement {
  const item = document.createElement("div");
  item.className = "tab-item";
  item.dataset.noteId = id;
  item.setAttribute("role", "presentation");
  const button = document.createElement("button");
  button.type = "button";
  button.className = "tab";
  button.setAttribute("role", "tab");
  button.onclick = () => {
    if (!dragMoved && id !== selectedId) void mutate("select_note", { noteId: id });
  };
  button.ondblclick = () => openRename(id);
  item.oncontextmenu = (event) => {
    event.preventDefault();
    openMenu(id, button, event.clientX, event.clientY);
  };
  button.onkeydown = (event) => onTabKey(event, id, button);
  button.onpointerdown = (event) => beginDrag(event, id, item);
  const actions = document.createElement("span");
  actions.className = "tab-actions";
  const rename = document.createElement("button");
  const remove = document.createElement("button");
  for (const action of [rename, remove]) {
    action.type = "button";
    action.className = "icon-button";
    action.tabIndex = -1;
  }
  rename.innerHTML = iconRename;
  remove.innerHTML = iconDelete;
  rename.onclick = (event) => {
    event.stopPropagation();
    openRename(id);
  };
  remove.onclick = (event) => {
    event.stopPropagation();
    openDelete(id);
  };
  actions.append(rename, remove);
  item.append(button, actions);
  return item;
}

function onTabKey(event: KeyboardEvent, id: string, button: HTMLButtonElement) {
  if (event.isComposing) return;
  const index = notes.findIndex((note) => note.id === id);
  if (event.altKey && (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
    event.preventDefault();
    const target = index + (event.key === "ArrowLeft" ? -1 : 1);
    if (target < 0 || target >= notes.length) return;
    const beforeId = event.key === "ArrowLeft" ? notes[target].id : (notes[target + 1]?.id ?? null);
    void mutate("move_note", { noteId: id, beforeId }, false).then(() => focusTab(id));
    return;
  }
  if (event.key === "F2") {
    event.preventDefault();
    openRename(id);
    return;
  }
  if (event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")) {
    event.preventDefault();
    openMenu(id, button);
    return;
  }
  if (event.key === "Delete" || event.key === "Backspace") {
    event.preventDefault();
    openDelete(id);
    return;
  }
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  const next =
    event.key === "Home"
      ? 0
      : event.key === "End"
        ? notes.length - 1
        : (index + (event.key === "ArrowLeft" ? -1 : 1) + notes.length) % notes.length;
  const target = notes[next].id;
  void mutate("select_note", { noteId: target }, false).then(() => focusTab(target));
}

function focusTab(id: string) {
  tabs.querySelector<HTMLButtonElement>(`.tab-item[data-note-id="${id}"] .tab`)?.focus();
}

// Pointer-based reordering (HTML drag and drop is unreliable inside panels).
let drag: { id: string; item: HTMLElement; startX: number; pointerId: number } | null = null;
let dragMoved = false;

function beginDrag(event: PointerEvent, id: string, item: HTMLElement) {
  if (event.button !== 0 || busy) return;
  drag = { id, item, startX: event.clientX, pointerId: event.pointerId };
  dragMoved = false;
}

function clearDropMarks() {
  for (const element of tabs.querySelectorAll(".drop-before, .drop-after")) element.classList.remove("drop-before", "drop-after");
}

function dropTarget(clientX: number): string | null {
  const items = [...tabs.querySelectorAll<HTMLElement>(".tab-item")].filter((item) => item.dataset.noteId !== drag?.id);
  clearDropMarks();
  const next = items.find((item) => {
    const rect = item.getBoundingClientRect();
    return clientX < rect.left + rect.width / 2;
  });
  if (next) {
    next.classList.add("drop-before");
    return next.dataset.noteId!;
  }
  items.at(-1)?.classList.add("drop-after");
  return null;
}

window.addEventListener("pointermove", (event) => {
  if (!drag || event.pointerId !== drag.pointerId) return;
  if (!dragMoved && Math.abs(event.clientX - drag.startX) < 5) return;
  if (!dragMoved) {
    dragMoved = true;
    drag.item.classList.add("dragging");
  }
  dropTarget(event.clientX);
  const rect = tabs.getBoundingClientRect();
  if (event.clientX < rect.left + 20) tabs.scrollLeft -= 10;
  if (event.clientX > rect.right - 20) tabs.scrollLeft += 10;
});

window.addEventListener("pointerup", (event) => {
  if (!drag || event.pointerId !== drag.pointerId) return;
  const moving = drag;
  const beforeId = dragMoved ? dropTarget(event.clientX) : null;
  drag = null;
  moving.item.classList.remove("dragging");
  if (dragMoved) {
    clearDropMarks();
    const unchanged = beforeId === (notes[notes.findIndex((note) => note.id === moving.id) + 1]?.id ?? null);
    if (!unchanged) void mutate("move_note", { noteId: moving.id, beforeId }, false);
    window.setTimeout(() => (dragMoved = false), 0);
  }
});

window.addEventListener("pointercancel", () => {
  drag?.item.classList.remove("dragging");
  drag = null;
  clearDropMarks();
});

addButton.onclick = () => void mutate("add_note", {});

// ---------- tab context menu ----------

const menu = document.createElement("div");
menu.id = "tab-menu";
menu.setAttribute("role", "menu");
menu.hidden = true;
const menuRename = document.createElement("button");
const menuDelete = document.createElement("button");
for (const button of [menuRename, menuDelete]) {
  button.type = "button";
  button.setAttribute("role", "menuitem");
}
menu.append(menuRename, menuDelete);
document.body.append(menu);
let menuTarget: { id: string; button: HTMLButtonElement } | null = null;

function openMenu(id: string, button: HTMLButtonElement, x?: number, y?: number) {
  if (busy || document.querySelector("dialog[open]")) return;
  menuTarget = { id, button };
  menuRename.textContent = t("이름 변경…", "Rename…");
  menuDelete.textContent = t("삭제…", "Delete…");
  menu.hidden = false;
  const rect = button.getBoundingClientRect();
  menu.style.left = `${Math.max(6, Math.min(window.innerWidth - menu.offsetWidth - 6, x ?? rect.left))}px`;
  menu.style.top = `${Math.max(6, Math.min(window.innerHeight - menu.offsetHeight - 6, y ?? rect.bottom + 3))}px`;
  menuRename.focus();
}

function closeMenu(restoreFocus = false) {
  const target = menuTarget;
  menu.hidden = true;
  menuTarget = null;
  if (restoreFocus) target?.button.focus();
}

menuRename.onclick = () => {
  const target = menuTarget;
  closeMenu();
  if (target) openRename(target.id);
};
menuDelete.onclick = () => {
  const target = menuTarget;
  closeMenu();
  if (target) openDelete(target.id);
};
menu.onkeydown = (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    closeMenu(true);
  } else if (["ArrowDown", "ArrowUp"].includes(event.key)) {
    event.preventDefault();
    (document.activeElement === menuRename ? menuDelete : menuRename).focus();
  }
};
document.addEventListener(
  "pointerdown",
  (event) => {
    if (!menu.hidden && !(event.target instanceof Node && menu.contains(event.target))) closeMenu();
  },
  { capture: true },
);

// ---------- dialogs ----------

function dialog(html: string): HTMLDialogElement {
  const element = document.createElement("dialog");
  element.innerHTML = html;
  document.body.append(element);
  return element;
}

const renameDialog = dialog(
  '<form method="dialog"><h2 id="rename-title"></h2><input id="rename-input" maxlength="80" autocomplete="off"><div class="dialog-actions"><button type="button" value="cancel"></button><button class="primary" type="submit"></button></div></form>',
);
renameDialog.setAttribute("aria-labelledby", "rename-title");
const renameInput = renameDialog.querySelector<HTMLInputElement>("input")!;
let renameTarget = "";

function openRename(id: string) {
  const note = notes.find((item) => item.id === id);
  if (!note || busy || document.querySelector("dialog[open]")) return;
  renameTarget = id;
  renameDialog.querySelector("h2")!.textContent = t("메모 이름", "Note Name");
  renameInput.placeholder = t(`비워 두면 “${titleOf(note)}”`, `Leave empty for “${titleOf(note)}”`);
  renameInput.value = note.title ?? "";
  const [cancel, save] = renameDialog.querySelectorAll("button");
  cancel.textContent = t("취소", "Cancel");
  save.textContent = t("저장", "Save");
  cancel.onclick = () => renameDialog.close();
  renameDialog.showModal();
  renameInput.focus();
  renameInput.select();
}

renameDialog.querySelector("form")!.onsubmit = (event) => {
  event.preventDefault();
  if (renameInput.matches(":focus") && (event as SubmitEvent & { isComposing?: boolean }).isComposing) return;
  const title = renameInput.value.trim();
  renameDialog.close();
  void mutate("rename_note", { noteId: renameTarget, title }, false).then(() => focusTab(renameTarget));
};

const deleteDialog = dialog(
  '<form method="dialog"><h2 id="delete-title"></h2><p></p><div class="dialog-actions"><button type="button"></button><button class="destructive" type="submit"></button></div></form>',
);
deleteDialog.setAttribute("aria-labelledby", "delete-title");
let deleteTarget = "";

function openDelete(id: string) {
  const note = notes.find((item) => item.id === id);
  if (!note || busy || document.querySelector("dialog[open]")) return;
  if (notes.length === 1 && !note.text && !note.strokes.length && !note.title) return;
  deleteTarget = id;
  deleteDialog.querySelector("h2")!.textContent = t("메모 삭제", "Delete Note");
  deleteDialog.querySelector("p")!.textContent = t(
    `“${titleOf(note)}”을(를) 삭제할까요? 삭제하면 되돌릴 수 없습니다.`,
    `Delete “${titleOf(note)}”? This can't be undone.`,
  );
  const [cancel, confirm] = deleteDialog.querySelectorAll("button");
  cancel.textContent = t("취소", "Cancel");
  confirm.textContent = t("삭제", "Delete");
  cancel.onclick = () => deleteDialog.close();
  deleteDialog.showModal();
  cancel.focus();
}

deleteDialog.querySelector("form")!.onsubmit = (event) => {
  event.preventDefault();
  deleteDialog.close();
  void mutate("delete_note", { noteId: deleteTarget });
};

// ---------- open / close / quit ----------

async function close(explicit: boolean) {
  if (closing) return;
  closing = true;
  try {
    closeMenu();
    closeSizeMenu();
    for (const open of document.querySelectorAll<HTMLDialogElement>("dialog[open]")) open.close();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    if (!(await flushAll())) return; // keep the memo open with the error showing
    await invoke("close_bubble", { explicit });
  } finally {
    closing = false;
  }
}

document.addEventListener(
  "keydown",
  (event) => {
    if (event.isComposing || event.keyCode === 229) return;
    const command = event.metaKey || event.ctrlKey;
    if (event.key === "Escape") {
      if (!menu.hidden || !sizeMenu.hidden || document.querySelector("dialog[open]")) return;
      event.preventDefault();
      void close(true);
    } else if (command && event.key.toLowerCase() === "n") {
      event.preventDefault();
      void mutate("add_note", {});
    } else if (command && event.key.toLowerCase() === "w") {
      event.preventDefault();
      void close(true);
    } else if (command && event.shiftKey && (event.key === "[" || event.key === "{" || event.key === "]" || event.key === "}")) {
      event.preventDefault();
      const index = notes.findIndex((note) => note.id === selectedId);
      const next = index + (event.key === "[" || event.key === "{" ? -1 : 1);
      if (next >= 0 && next < notes.length) void mutate("select_note", { noteId: notes[next].id });
    } else if (command && !event.shiftKey && event.key.toLowerCase() === "z" && tool !== "none") {
      event.preventDefault();
      undoDrawing();
    }
  },
  { capture: true },
);

// No browser context menu ("Reload" would drop unsaved state); text fields
// keep theirs for copy, paste and spelling.
document.addEventListener("contextmenu", (event) => {
  const target = event.target;
  if (target instanceof HTMLTextAreaElement || target instanceof HTMLInputElement) return;
  event.preventDefault();
});

window.addEventListener("resize", () => {
  layout();
  redraw();
});


async function start() {
  // Listen before asking for the initial values: a theme picked in between
  // must not be lost, or undone by the older ui_info reply.
  let themeChanged = false;
  await listen<{ explicit: boolean }>("memo:close-request", (event) => void close(event.payload.explicit));
  await listen("memo:opened", () => {
    // Every open starts in text mode, ready to type.
    if (tool !== "none") setTool(tool);
    layout();
    redraw();
    focusEditor(true);
  });
  await listen("memo:reload", () => void reload());
  await listen<string>("memo:theme", (event) => {
    themeChanged = true;
    document.documentElement.dataset.theme = event.payload;
    redraw();
  });
  await listen("memo:quit-request", async () => {
    await invoke("quit_ack");
    if (await flushAll()) {
      await invoke("quit_app");
    } else {
      // Keep the app and the unsaved text; the memo shows the save error.
      await invoke("quit_cancelled");
    }
  });
  let firstRun = false;
  try {
    const info = await invoke<{ language: string; platform: string; theme: string; firstRun: boolean; showTip: boolean }>("ui_info");
    setLanguage(info.language);
    document.documentElement.dataset.platform = info.platform;
    if (!themeChanged) document.documentElement.dataset.theme = info.theme;
    firstRun = info.firstRun;
    tip = info.showTip;
  } catch {
    // Keep the browser language.
  }
  editor.placeholder = t("기억할 내용을 적으세요. 자동으로 저장됩니다.", "Write something to remember. It saves automatically.");
  addButton.title = addButton.ariaLabel = t("새 메모 (⌘N)", "New Note (⌘N)");
  tabs.setAttribute("aria-label", t("메모 목록", "Notes"));
  setTool("none");
  await reload();
  paintStatus();
  // First launch: open the memo once by itself so the tip is seen right away.
  if (firstRun) void invoke("open_memo");
}

void start();
