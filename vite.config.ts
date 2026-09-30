/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import { resolve } from "node:path";

// Two pages: the memo bubble (both platforms) and the character (Windows;
// macOS draws the character natively).
export default defineConfig(() => ({
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: false,
    watch: { ignored: ["**/src-tauri/**"] },
  },
  // Only this project's tests (review clones under work/ are ignored).
  test: { include: ["src/**/*.test.ts"] },
  build: {
    target: "safari16",
    rollupOptions: {
      input: {
        bubble: resolve(__dirname, "bubble.html"),
        character: resolve(__dirname, "character.html"),
      },
    },
  },
}));
