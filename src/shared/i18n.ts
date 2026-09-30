let korean = typeof navigator !== "undefined" && navigator.language.toLowerCase().startsWith("ko");

export function setLanguage(code: string) {
  korean = code === "ko";
  document.documentElement.lang = korean ? "ko" : "en";
}

export function t(ko: string, en: string): string {
  return korean ? ko : en;
}
