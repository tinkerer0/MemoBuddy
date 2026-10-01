# MemoBuddy 스토어 입력 내용 (붙여넣기용)

기본 언어는 **English (U.S.)**, 한국어는 현지화로 추가한다. 괄호 안 숫자는 칸의 글자 수 제한이고, 아래 값은 모두 제한 안에 들어가는 것을 글자 수를 세어 확인했다(2026-09-30).

## A. App Store Connect (Mac)

| 칸 | 값 |
| --- | --- |
| 이름 (30) | `MemoBuddy – Floating Memo` — 이미 쓰이면 `MemoBuddy: Floating Memo`. 한국어 현지화 이름은 `MemoBuddy – 떠다니는 메모` |
| 번들 ID / SKU | `app.memopet.desktop` / `memopet-mac` |
| 카테고리 | Productivity(생산성), 보조 Utilities(유틸리티) |
| 가격·국가 | 무료, 모든 국가 |
| 연령 등급 | 모든 질문 "None/없음" → 4+ |
| 앱 개인정보(App Privacy) | **Data Not Collected**(데이터를 수집하지 않음) |
| 개인정보 처리방침 URL | https://github.com/tinkerer0/MemoBuddy/blob/main/docs/PRIVACY.md |
| 지원 URL | https://github.com/tinkerer0/MemoBuddy/issues |
| 마케팅 URL(선택) | https://github.com/tinkerer0/MemoBuddy |
| 저작권 | `2026 MemoBuddy contributors` |
| 암호화 수출 규정 | Info.plist의 `ITSAppUsesNonExemptEncryption = false` 덕분에 추가 질문 없음 |
| 로그인 필요 | 아니요 |

### English (U.S.) — 기본

**Subtitle (30)**
```text
A cute pet for quick notes
```

**Promotional Text (170)**
```text
Meet the little pet that lives on your desktop and keeps your notes. Click to write, click away to save. Pick one of nine pets, or use your own photo or GIF.
```

**Description (4000)**
```text
A tiny pet lives at the edge of your screen and keeps your notes. Click it and your notebook opens right there. Type or doodle, click anywhere else, and it's saved and out of your way.

No note app to find, no windows to arrange, no save button. Just a little friend who is always one click away, even over full-screen apps.

WHAT IT DOES
• Click the pet to open your notes; click anywhere else to save and close
• Tabs for different notes: add, rename, drag to reorder, delete with confirmation
• Type and draw in the same note, with three pen widths and a round eraser
• Saves as you go, including emoji and line breaks, and recovers from a backup if a file is ever damaged
• A short tip on first launch shows how it works

MAKE IT YOURS
• Nine characters: a writing bear, a penguin, a ghost, a shiba, a humble pebble, two planets, a crescent moon and the Classic icon
• Or turn any photo or GIF you like into your pet (GIF, PNG, JPEG, WebP)
• Three sizes, and a white or dark theme
• Right-click the pet, or use the menu bar icon

PRIVATE BY DESIGN
• No account, no ads, no tracking
• Works offline. Your notes stay on your Mac.
```

**Keywords (100)**
```text
memo,sticky,notepad,companion,floating,scratchpad,drawing,doodle,sketch,character,gif,kawaii,menubar
```

### 한국어 — 현지화

**이름 (30)**
```text
MemoBuddy – 떠다니는 메모
```

**부제 (30)**
```text
귀여운 펫이 지켜 주는 빠른 메모
```

**홍보 문구 (170)**
```text
화면에 사는 작은 펫이 메모를 지켜 줘요. 누르면 쓰고, 다른 곳을 누르면 저장. 펫 9종 중에 고르거나 좋아하는 사진·GIF로 바꿔 보세요.
```

**설명 (4000)**
```text
화면 한쪽에 사는 작은 펫이 메모를 지켜 줘요. 누르면 바로 그 자리에 메모장이 열리고, 적거나 그린 뒤 다른 곳을 누르면 저장되고 사라져요.

메모 앱을 찾을 필요도, 창을 정리할 필요도, 저장 버튼도 없어요. 전체 화면 앱을 쓰는 중에도 한 번만 누르면 되는 작은 친구예요.

이런 걸 해요
• 펫을 누르면 메모가 열리고, 다른 곳을 누르면 저장 후 닫힘
• 탭으로 여러 메모 관리: 추가, 이름 바꾸기, 끌어서 순서 바꾸기, 삭제 확인
• 한 메모에 글과 그림을 함께: 펜 굵기 3단계와 둥근 지우개
• 한글·이모지·줄바꿈까지 자동 저장, 파일이 손상되면 백업에서 복구
• 처음 실행하면 짧은 사용법 안내가 나와요

나만의 펫으로
• 캐릭터 9종: 글 쓰는 곰, 펭귄, 유령, 시바견, 하찮은 돌멩이, 행성 둘, 초승달, 클래식 아이콘
• 좋아하는 사진이나 GIF를 골라 나만의 펫으로(GIF·PNG·JPEG·WebP)
• 크기 3단계, 화이트/다크 테마
• 펫을 우클릭하거나 메뉴 막대 아이콘에서 바꿔요

개인정보는 그대로
• 계정·광고·추적 없음
• 인터넷 없이도 돼요. 메모는 이 Mac에만 저장돼요.
```

**키워드 (100)**
```text
메모장,메모앱,노트,필기,그리기,낙서,스티키,캐릭터,움짤,GIF,데스크탑,생산성
```

### App Review Information → Notes (영어)

```text
MemoBuddy is a menu bar app (LSUIElement, no Dock icon). On first launch the memo opens by itself with a short tip. Afterwards, click the small pet at the lower right of the main screen, or choose "Open Memo" from the menu bar icon, to open the notebook. Clicking elsewhere saves and closes it; Esc also closes it. Right-click the pet for pet, size, theme and quit. Notes are stored locally in the app container; there is no account and the app sends no data anywhere. Its only network use is opening the privacy policy or license page in the browser when the user picks it from the menu. The com.apple.security.network.client entitlement is only there because WebKit in the App Sandbox needs it to load the app's own bundled pages.
```

## B. Microsoft Store (Partner Center)

| 칸 | 값 |
| --- | --- |
| 제품 이름 | 예약한 이름(`MemoBuddy`) |
| 카테고리 | Productivity(생산성) |
| 가격·시장 | 무료, 모든 시장 |
| 개인정보 처리방침 URL | https://github.com/tinkerer0/MemoBuddy/blob/main/docs/PRIVACY.md |
| 웹 사이트 | https://github.com/tinkerer0/MemoBuddy |
| 지원 연락처 | https://github.com/tinkerer0/MemoBuddy/issues |
| 저작권 및 상표 정보 | `© 2026 MemoBuddy contributors` |
| 연령 등급(IARC 설문) | 폭력·성적 내용·언어·도박·사용자 간 소통·위치 공유·디지털 구매 모두 "없음" → 전체 이용가 |
| 시스템 요구 사항 | Windows 11 이상, x64 (Windows 11에는 WebView2가 기본으로 들어 있음) |
| 이번 버전의 새로운 기능 | `First release.` / `첫 출시` |
| 제한된 기능(runFullTrust) 사유 | 아래 영어 문장 |

**runFullTrust 사유**
```text
MemoBuddy is a desktop app built with Tauri. runFullTrust is required to run its desktop executable, which shows an always-on-top pet and a memo window. It does not access other apps' data and sends no data anywhere; its menu can open the privacy policy and license pages in the browser.
```

**Short description (English)**
```text
A tiny pet lives on your desktop and keeps your notes. Click it to write or draw; click anywhere else and it's saved. Nine pets, or your own photo or GIF.
```

**Short description (한국어)**
```text
화면에 사는 작은 펫이 메모를 지켜 줘요. 누르면 쓰거나 그리고, 다른 곳을 누르면 저장돼요. 펫 9종 또는 좋아하는 사진·GIF로.
```

**Description**: 위 App Store 설명과 같다. 다만 영어 마지막 줄은 `Works offline. Your notes stay on your PC.`, 한국어 마지막 줄은 `인터넷 없이도 돼요. 메모는 이 PC에만 저장돼요.`로 바꾸고, "menu bar icon / 메뉴 막대 아이콘"은 "system tray / 알림 영역"으로 바꾼다. 둘째 문단의 ", even over full-screen apps"와 "전체 화면 앱을 쓰는 중에도 "는 뺀다(Windows에서 전체 화면 앱 위 표시는 확인하지 않았다).

**Product features (각 200자, 최대 20개)**
```text
Click the pet to open your notes; click anywhere else to save and close
Stays on top of your other windows
Tabs for different notes: add, rename, drag to reorder, delete with confirmation
Type and draw in the same note, with three pen widths and a round eraser
Saves as you go, with a backup and damaged-file recovery
Nine pets, from a writing bear to a humble pebble
Turn any photo or GIF you like into your pet (GIF, PNG, JPEG, WebP)
Three sizes, white or dark theme, from the pet's right-click menu or the system tray
No account, ads or tracking; works offline and notes stay on your PC
```
```text
펫을 누르면 메모가 열리고, 다른 곳을 누르면 저장 후 닫힘
다른 창 위에 늘 떠 있음
탭으로 여러 메모 관리: 추가, 이름 바꾸기, 끌어서 순서 바꾸기, 삭제 확인
한 메모에 글과 그림을 함께: 펜 굵기 3단계와 둥근 지우개
자동 저장, 백업과 손상 파일 복구
캐릭터 9종(글 쓰는 곰부터 하찮은 돌멩이까지)
좋아하는 사진이나 GIF를 나만의 펫으로(GIF·PNG·JPEG·WebP)
크기 3단계, 화이트/다크 테마: 펫 우클릭 메뉴나 알림 영역에서
계정·광고·추적 없음, 인터넷 없이도 되고 메모는 이 PC에만 저장
```

**Search terms (최대 7개, 각 30자)**
```text
desktop pet
sticky notes
quick notes
memo
notepad
cute
drawing
```

## C. 스크린샷·미리보기 영상

- **Mac App Store 스크린샷**: 16:10, 2880×1800, 6장(영어·한국어 따로). 첫 세 장이 검색 결과와 첫 화면에 보이므로 무엇인지 → 캐릭터 → 쓰는 법 순서로 둔다.
  1. 화면 위 펫과 열린 메모 — "A tiny pet that keeps your notes" / "메모를 지켜 주는 작은 펫"
  2. 캐릭터 9종과 '내 사진·GIF' 칸 — "Pick a pet you love" / "마음에 드는 펫을 골라요"
  3. 누르고 → 쓰고 → 다른 곳을 누르면 저장 — "Click. Write. Done." / "누르고, 쓰고, 끝."
  4. 펜 굵기 메뉴가 열린 다크 메모 — "Doodle right next to your words" / "글 옆에 바로 그림도"
  5. 크기 3단계와 우클릭 메뉴 — "Make it yours" / "나만의 펫으로 꾸며요"
  6. 계정·광고·추적 없음 — "Your notes stay on your Mac" / "메모는 이 Mac에만"
  - 완성본은 로컬 `work/screenshots/out-v2/en/`, `work/screenshots/out-v2/ko/`(저장소에는 없음), 생성기는 `work/screenshots/compose_v2.py`. 캐릭터를 더하면 LINEUP과 "Nine characters" 문구를 고치고 다시 만든다.
  - 앱 화면은 실제 캡처(영어 화면)와 앱의 캐릭터 GIF만 쓴다. 화살표·반짝이·단계 번호는 앱 밖의 설명 그림이다. 한국어판도 앱 화면은 영어이므로, 한국어 화면 캡처로 바꾸면 더 좋다.
- **App Preview(미리보기 영상)**: 완성본 `work/screenshots/preview/memopet-preview-en.mp4`(영어판), `memopet-preview-ko.mp4`(한국어 현지화), 로컬 전용. 1920×1080, 30fps, H.264, 무음 스테레오 AAC, 25초(허용 15~30초). 실제 앱(샌드박스 시험 사본)을 녹화했다: 펫이 움직임 → 펫을 누름 → 메모가 열림 → 체크 표시와 웃는 얼굴을 그림 → 다른 곳을 누름(저장) → 우클릭 → 캐릭터 → 펭귄. 영어판은 영어 메뉴·메모, 한국어판은 한국어 메뉴·메모. 포스터 프레임은 13초 부근(메모가 열리고 그림이 있는 장면, `poster-en.png`·`poster-ko.png`). 데스크톱 펫 앱은 움직임이 핵심이라 영상을 스크린샷보다 앞에 둔다(Pets Therapy 방식). 녹화 도구는 `work/screenshots/preview/tools/`.
- **Microsoft Store**: 스크린샷 `work/screenshots/out-v2-win/en/`, `…/ko/`(3200×1800, 16:9, 6장, 로컬). Mac 캡처로 만들되 Windows에서 모양이 다른 우클릭 메뉴는 빼고(5번은 화이트·다크 메모로 대체) "Mac"을 "PC"로 바꿨다. 메모 화면·펜 굵기 메뉴·캐릭터는 같은 웹 화면과 GIF라 Windows에서도 같고, 글꼴만 SF 대신 Segoe UI로 보인다. 트레일러는 `work/screenshots/preview/memopet-trailer-windows-en.mp4`, `…-ko.mp4`(16.6초, macOS 메뉴가 나오기 전까지), 썸네일은 `poster-en.png`·`poster-ko.png`. 스토어 정책 10.1(스크린샷 등이 기능·사용 경험을 정확히 보여야 함)에 맞춘 구성이다. 더 정확하게 하려면 Windows에서 우클릭 메뉴를 한 장 찍어 5번에 넣는다.
- 캡처는 잠금이 풀린 화면에서, Mac에서 손을 뗀 1분 동안 찍는다(자동 조작이 커서를 움직이기 때문).
