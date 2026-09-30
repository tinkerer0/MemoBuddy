# MemoPet 스토어 등록 문구 (초안)

두 스토어에 그대로 붙여 넣을 수 있게 한국어·영어를 함께 적었다. 이름이 이미 쓰이고 있으면 `MemoPet – Floating Notes`로 바꾼다.

## 공통

- 이름: **MemoPet**
- 카테고리: 생산성(Productivity)
- 가격: 무료
- 연령 등급: 전체(4+ / IARC 3+) — 사용자 생성 콘텐츠 공유·채팅·구매·광고·위치 없음
- 개인정보: 수집하지 않음(docs/PRIVACY.md를 공개 URL로 올려 입력)
- 지원 URL: https://github.com/tinkerer0/MemoPet/issues (또는 지원 이메일)

## 한국어

**부제(30자 이내)**: 화면 위에 떠 있는 작은 메모장

**홍보 문구**: 작은 캐릭터를 누르면 바로 메모가 열립니다. 적고, 그리고, 딴 데 누르면 저장되고 사라져요.

**설명**:
MemoPet은 화면 한쪽에 떠 있는 작은 캐릭터입니다. 누르면 말풍선 같은 메모장이 바로 열리고, 다른 곳을 누르면 자동으로 저장된 뒤 닫힙니다. 메모 앱을 따로 열 필요 없이 떠오른 생각을 잠깐 적고 하던 일로 돌아가세요.

- 캐릭터를 눌러 바로 열기, 다른 곳을 누르면 자동 저장 후 닫기
- 탭으로 여러 메모 관리: 추가, 이름 변경, 끌어서 순서 바꾸기, 삭제 확인
- 한 메모에 글과 그림을 함께: 펜과 원형 지우개
- 한글·이모지·줄바꿈까지 자동 저장, 손상되면 백업에서 복구
- 캐릭터 3종과 내 이미지(GIF·PNG·JPEG·WebP), 크기 3단계
- 모든 데스크톱과 전체화면 앱 위에 떠 있음
- 메뉴 막대(윈도우는 알림 영역)에서 메모 열기, 캐릭터·크기·테마(화이트/다크) 바꾸기
- 펜 굵기와 지우개 크기 3단계(버튼 우클릭으로 바로 선택)
- 계정·광고·추적 없음. 메모는 이 컴퓨터에만 저장됩니다.

**키워드(100자 이내, 쉼표 구분)**: 메모,메모장,포스트잇,스티키,노트,빠른메모,필기,그리기,데스크톱,펫,캐릭터,생산성

## English

**Subtitle (≤30 chars)**: A notebook that floats nearby

**Promotional text**: Click the little character and your memo is already open. Type or draw, click away, and it's saved.

**Description**:
MemoPet is a tiny character that floats at the edge of your screen. Click it and a memo opens right there; click anywhere else and it saves and gets out of your way. No need to switch to a notes app for a quick thought — jot it down and get back to work.

- Click the character to open, click elsewhere to save and close
- Tabs for multiple notes: add, rename, drag to reorder, delete with confirmation
- Text and drawing in the same note, with a pen and a round eraser
- Saves automatically, including emoji and line breaks, and recovers from a backup if a file is damaged
- Three characters or your own image (GIF, PNG, JPEG, WebP), in three sizes
- Floats above every desktop and full-screen app
- Menu bar (or system tray on Windows) to open the memo and change the character, size and theme (white or dark)
- Three pen widths and eraser sizes (right-click the pen or eraser to pick)
- No account, ads or tracking. Your notes stay on your computer.

**Keywords (≤100 chars)**: memo,notes,sticky,notepad,quick note,scratchpad,drawing,desktop pet,floating,productivity

## 심사자 메모 (App Review Information → Notes)

MemoPet is a menu bar app (LSUIElement, no Dock icon). After launch, a small character appears at the lower right of the main screen. Click it, or choose "Open Memo" from the menu bar icon, to open the notebook. Clicking elsewhere saves and closes it; Esc also closes it. Right-click the character for character, size and quit options. Notes are stored locally in the app container; the app makes no network requests and has no account.

## 스크린샷 계획

1. 캐릭터 + 열린 메모(글과 그림이 함께 있는 탭 3개)
2. 탭 이름 변경·끌어서 정렬 순간
3. 펜으로 그린 메모
4. 캐릭터 3종 비교
5. 메뉴 막대 메뉴(캐릭터·크기·테마)

Mac: 2880×1800(16:10), Microsoft Store: 1920×1080. 잠금이 풀린 화면에서 실제 앱으로 찍는다.

앱 화면 언어는 시스템 언어를 따른다(한국어 시스템은 한국어, 그 밖은 영어). 영어 스크린샷은 시스템 설정 → 일반 → 언어 및 지역 → 응용 프로그램에서 MemoPet만 English로 바꾸고 다시 실행해 찍는다(터미널: `defaults write app.memopet.desktop AppleLanguages -array en`, 되돌리기: `defaults delete app.memopet.desktop AppleLanguages`).
