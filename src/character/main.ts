// Windows character window. macOS draws the character natively instead.
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { setLanguage, t } from "../shared/i18n";

type Look = { kind: "classic" | "image"; source: string | null; animate: boolean };

const button = document.querySelector<HTMLButtonElement>("#character")!;
const classic =
  '<svg viewBox="0 0 80 80" aria-hidden="true"><circle class="classic-bg" cx="40" cy="40" r="35"/>' +
  '<g class="classic-fg" fill="none" stroke-linecap="round"><rect x="28.8" y="26.8" width="22.4" height="26.4" rx="2.5" stroke-width="2"/>' +
  '<path d="M32.8 34.4h14.4M32.8 40h14.4M32.8 45.6h14.4" stroke-width="1.5"/></g></svg>';

let renderSerial = 0;

function render(look: Look) {
  const serial = ++renderSerial;
  if (look.kind === "classic" || !look.source) {
    button.innerHTML = classic;
    return;
  }
  const image = new Image();
  image.alt = "";
  image.draggable = false;
  // A slower earlier image must not replace a newer choice.
  image.onerror = () => {
    if (serial === renderSerial) button.innerHTML = classic;
  };
  image.onload = () => {
    if (serial !== renderSerial) return;
    if (look.animate) {
      button.replaceChildren(image);
      return;
    }
    // Reduce Motion / animations off: show the first frame only.
    const canvas = document.createElement("canvas");
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    canvas.getContext("2d")?.drawImage(image, 0, 0);
    canvas.style.cssText = "display:block;width:100%;height:100%;object-fit:contain;pointer-events:none";
    button.replaceChildren(canvas);
  };
  image.src = look.source;
}

let press: { x: number; y: number; id: number } | null = null;
let dragging = false;

button.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  press = { x: event.screenX, y: event.screenY, id: event.pointerId };
  dragging = false;
});

button.addEventListener("pointermove", (event) => {
  if (!press || dragging || event.pointerId !== press.id) return;
  if (Math.hypot(event.screenX - press.x, event.screenY - press.y) < 4) return;
  dragging = true;
  press = null;
  void getCurrentWindow().startDragging();
});

button.addEventListener("pointerup", (event) => {
  if (!press || event.pointerId !== press.id) return;
  press = null;
  if (!dragging) void invoke("character_clicked");
});

button.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    void invoke("character_clicked");
  }
});

button.addEventListener("contextmenu", (event) => {
  event.preventDefault();
  void invoke("character_menu");
});

async function start() {
  // Listen first; a change that arrives before the initial replies wins.
  let themeChanged = false;
  let lookChanged = false;
  await listen<Look>("character:look", (event) => {
    lookChanged = true;
    render(event.payload);
  });
  await listen<string>("memo:theme", (event) => {
    themeChanged = true;
    document.documentElement.dataset.theme = event.payload;
  });
  try {
    const info = await invoke<{ language: string; theme: string }>("ui_info");
    setLanguage(info.language);
    if (!themeChanged) document.documentElement.dataset.theme = info.theme;
  } catch {
    // Keep the browser language.
  }
  button.ariaLabel = button.title = t("MemoPet 메모 열기", "Open MemoPet memo");
  const look = await invoke<Look>("character_look");
  if (!lookChanged) render(look);
}

void start();
