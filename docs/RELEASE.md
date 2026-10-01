# MemoBuddy 출시 안내 (Mac App Store · Microsoft Store)

2026-09-30 작성. 이 문서는 "계정 주인이 직접 해야 하는 일"과 "이미 준비된 것"을 나눈다. 계정·결제·본인 인증·스토어 제출은 계정 주인만 할 수 있다.

## 한눈에 보기

| | Mac App Store | Microsoft Store |
| --- | --- | --- |
| 계정 | Apple Developer Program **연 $99**(유료) | 개인 개발자 등록 **무료**(신분증·셀카 인증) |
| 포장 | 서명된 `.pkg` (`scripts/build-mas.sh`, 이 맥에서 실행) | MSIX (GitHub CI가 push마다 만듦, artifact `MemoBuddy-msix`) |
| 서명 | Apple 인증서 2개 + 프로비저닝 프로파일 | Store가 서명(따로 살 인증서 없음) |
| 심사 | 보통 1~3일 | 보통 1~3영업일 |
| 준비 상태 | 스크립트·권한 파일 준비됨, 계정 필요 | 제품 `MemoBuddy` 예약(Store ID 9MV1CLQJV6CX, 2026-10-01), 식별값을 CI에 넣음. 먼저 만든 `MemoPet` 제품(9NDZWVPXSJGH)은 쓰지 않음 |

두 스토어 공통으로 **개인정보 처리방침 공개 URL**이 필요하다. 초안은 `docs/PRIVACY.md`에 있다. GitHub Pages 같은 곳에 공개한다.

---

## A. Mac App Store — 계정 주인이 할 일

1. **Apple Developer Program 가입** (연 $99): <https://developer.apple.com/programs/enroll/>. Apple 계정에 이중 인증이 켜져 있어야 한다. 개인으로 가입하면 D-U-N-S 번호는 필요 없다.
2. **팀 ID 확인**: <https://developer.apple.com/account> → Membership details → Team ID(영문·숫자 10자).
3. **인증서 2개 만들기** (이 맥에서): Xcode → Settings → Accounts → 계정 선택 → Manage Certificates → `+` → **Apple Distribution**, 그리고 **Mac Installer Distribution**. 이 맥 키체인에 설치된다. 확인은 다음 명령으로 한다.
   ```sh
   security find-identity -v -p codesigning   # "Apple Distribution: ..." 이 보여야 함
   security find-identity -v                  # "3rd Party Mac Developer Installer: ..." 이 보여야 함
   ```
4. **App ID 등록**: Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs → App → Bundle ID **Explicit** `app.memopet.desktop`. 추가 기능은 켜지 않는다.
5. **프로비저닝 프로파일**: Profiles → `+` → Distribution의 **Mac App Store Connect** → 위 App ID → Apple Distribution 인증서 → 다운로드(`.provisionprofile`).
6. **App Store Connect에 앱 만들기**: <https://appstoreconnect.apple.com> → 앱 → `+` → 새로운 앱 → 플랫폼 macOS, 이름 `MemoBuddy – Floating Memo`(이미 쓰이면 `MemoBuddy: Floating Memo`, 한국어 현지화는 `MemoBuddy – 떠다니는 메모`, `docs/STORE_LISTING.md` A절), 기본 언어는 **English (U.S.)**(다른 나라 사용자가 보는 기본 문구, 한국어는 현지화로 추가), 번들 ID `app.memopet.desktop`, SKU 아무 값(예 `memopet-mac`).
7. **스토어 정보 입력** (문구 초안: `docs/STORE_LISTING.md`)
   - 스크린샷: 16:10(2880×1800) 6장. 이 맥의 `work/screenshots/out-v2/en/`(English)과 `…/ko/`(한국어 현지화)에 있다(저장소에는 없음).
   - App Preview(미리보기 영상): `work/screenshots/preview/memopet-preview-en.mp4`, `…-ko.mp4`. 포스터 프레임은 13초 부근.
   - 부제·설명·키워드·지원 URL·**개인정보 처리방침 URL**.
   - 카테고리: 생산성(Productivity).
   - 앱 개인정보(App Privacy): **데이터를 수집하지 않음**.
   - 연령 등급 설문: 모두 "없음" → 4+.
   - 가격: 무료(추천).
8. **빌드·업로드** (이 맥 터미널):
   ```sh
   cd MemoBuddy   # 이 저장소를 받은 폴더
   TEAM_ID=ABCDE12345 \
   BUILD_NUMBER=1 \
   APP_SIGN_IDENTITY="Apple Distribution: 이름 (ABCDE12345)" \
   INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: 이름 (ABCDE12345)" \
   PROVISIONING_PROFILE=~/Downloads/MemoBuddy_Mac_App_Store.provisionprofile \
   ./scripts/build-mas.sh
   ```
   결과물은 `dist-mas/MemoBuddy.pkg`다. 업로드는 두 방법 중 하나로 한다.
   - Mac App Store의 **Transporter** 앱에 `MemoBuddy.pkg`를 끌어다 놓고 "전달".
   - 또는 App Store Connect → 사용자 및 액세스 → 통합 → 개별 키에서 API 키를 만든다. 내려받은 키 파일은 Apple 안내대로 홈 폴더의 `.appstoreconnect` 아래 `private_keys` 폴더에 둔다. 그다음 `APPLE_API_KEY_ID`·`APPLE_API_ISSUER`를 붙여 위 명령을 다시 실행하면 자동으로 올라간다. 이 키는 비밀정보이니 저장소나 채팅에 붙이지 않는다.
9. **TestFlight로 먼저 확인**(추천) → 심사 제출.
10. **다시 올릴 때**: 빌드 번호(`BUILD_NUMBER`)는 올릴 때마다 전보다 커야 하고, 앱 버전을 올려도 처음으로 돌아가지 않는다(macOS 규칙). 첫 업로드 1, 그다음 2, 3…으로 쓰고 마지막 번호를 적어 둔다. 새 버전을 낼 때는 `package.json`·`src-tauri/tauri.conf.json`·`src-tauri/Cargo.toml`의 버전을 함께 올린다.

심사 대비 메모(심사자에게 남길 설명)는 `docs/STORE_LISTING.md` A절의 "App Review Information → Notes" 문장을 그대로 붙여 넣는다(메뉴에서 고를 때만 브라우저로 개인정보 처리방침·라이선스 페이지를 연다는 설명 포함).

## B. Microsoft Store — 계정 주인이 할 일

1. **개인 개발자 등록(무료)**: <https://storedeveloper.microsoft.com> → 개인으로 등록 → 신분증·셀카 인증.
2. **앱 이름 예약**: Partner Center → Apps and games → New product → MSIX or PWA app → `MemoBuddy`.
3. **Product identity 값 3개 확인**: 앱 → Product management → Product identity의 `Package/Identity/Name`, `Package/Identity/Publisher`(`CN=...`), `Package/Properties/PublisherDisplayName`.
4. **MSIX 받기**: 식별값(`xixxxx.MemoBuddy`, `CN=EF58497A-…`, `xixxxx`)은 `.github/workflows/ci.yml`에 들어 있다. 공개 저장소에 push하면 CI의 Windows 작업이 `scripts/pack-msix.ps1 -SkipBuild`로 MSIX를 만들어 artifact **`MemoBuddy-msix`**(`MemoBuddy_1.0.0.0_x64.msix`)로 올린다. GitHub에 로그인해 최근 성공한 CI 실행에서 내려받는다. Windows PC는 필요 없다.
5. **(선택) Windows에서 미리 설치해 보기**: 스토어 제출용 MSIX는 서명이 없어 그대로는 설치되지 않는다. 설치해 보려면 Windows 11에서 `winget install microsoft.winappcli --source winget` 뒤 `.\scripts\pack-msix.ps1 -DevCert`로 개발용 인증서가 붙은 패키지를 만들고, 관리자 PowerShell에서 `winapp cert install`로 인증서를 한 번 신뢰한다. 서명 없는 CI 설치 파일(`MemoBuddy-windows-installer`)로도 앱 동작은 확인할 수 있다.
6. **스토어 정보**: 기본 언어는 영어(미국), 한국어를 추가 언어로. 문구는 `docs/STORE_LISTING.md` B절. 스크린샷은 이 맥의 `work/screenshots/out-v2-win/en/`·`…/ko/`(3200×1800, 6장), 트레일러는 `work/screenshots/preview/memopet-trailer-windows-en.mp4`·`…-ko.mp4`(썸네일 `poster-en.png`·`poster-ko.png`). 카테고리 생산성, **개인정보 처리방침 URL**, 연령 등급(IARC 설문), 가격 무료.
7. **제한된 기능 설명**: 패키지가 `runFullTrust`를 쓰므로 제출 화면에서 이유를 묻는다. 예시: "MemoBuddy is a desktop app built with Tauri. runFullTrust is required to run its desktop executable, which shows an always-on-top character and memo window. It does not access other apps' data."
8. `.msix`를 올리고 심사 제출. 다시 올릴 때는 `-Version`을 전보다 크게 한다(예: `1.0.1.0`). Store 제출용은 네 번째 자리를 `0`으로 둔다.

## C. 이미 준비된 것

| 항목 | 위치 |
| --- | --- |
| App Sandbox 권한(고른 이미지 읽기, WebKit용 네트워크 클라이언트) | `src-tauri/Entitlements.plist` |
| 스토어 제출용 권한 템플릿(팀 ID 자리) | `src-tauri/Entitlements.appstore.plist.template` |
| 메뉴바 앱 설정(Dock 아이콘 없음)·암호화 수출 신고 | `src-tauri/Info.plist` |
| Mac App Store 빌드·서명·업로드 스크립트 | `scripts/build-mas.sh` |
| MSIX 매니페스트 템플릿·타일 이미지 | `packaging/windows/` |
| MSIX 포장 스크립트(**Windows에서 미실행**) | `scripts/pack-msix.ps1` |
| CI(맥·윈도우 빌드·테스트) | `.github/workflows/ci.yml`(GitHub 저장소를 만들어 push해야 동작, 승인 필요) |
| 개인정보 처리방침 초안 | `docs/PRIVACY.md` |

private API를 쓰지 않도록 구성했다(`macOSPrivateApi` 꺼짐, 투명 창은 공개 API로 구현). 자체 업데이트 확인도 넣지 않아서 App Store 규칙과 충돌하지 않는다. 실제 심사 통과 여부는 제출 전까지 알 수 없다.

## D. 권한 설명 (심사 대비)

- `com.apple.security.app-sandbox`: App Store 필수.
- `com.apple.security.files.user-selected.read-only`: "캐릭터 → 이미지 선택…"에서 고른 이미지 읽기.
- `com.apple.security.network.client`: 샌드박스 안의 WebKit이 앱 자체 화면을 불러오는 데 필요하다(없으면 메모 창이 빈 화면, 2026-09-30 실측). 앱은 데이터를 어디에도 보내지 않고, 메뉴에서 고를 때만 개인정보 처리방침·라이선스 페이지를 브라우저로 연다.

## E. 알려진 한계 (2026-09-30 기준)

- **Windows**: 2026-09-30 GitHub CI의 시험용 설치 파일로 Windows PC에서 설치·실행이 된다는 보고를 받았다(세부 항목은 기록 없음). MSIX 포장과 스토어 심사는 아직이다.
- **macOS 로그아웃·시스템 종료**: Tauri의 창 라이브러리(tao)가 종료 확인(`applicationShouldTerminate:`)을 받지 않아 저장 절차 없이 끝난다. 입력은 멈춘 뒤 0.3초, 계속 입력해도 최대 1초 안에 저장되므로 마지막 저장 이후 그 사이에 친 글자만 위험하다. ⌘Q·메뉴의 종료는 저장한 뒤 끝난다.
- **실행 중 "동작 줄이기" 설정 변경**은 다음 캐릭터 교체나 재실행 때 반영된다.
- **메뉴 막대(트레이) 아이콘**은 VoiceOver의 누르기 동작으로 메뉴가 열리지 않는다(tray-icon 라이브러리 한계). 캐릭터 우클릭 메뉴와 메모 창은 키보드로 쓸 수 있다.
- **시스템 암호 창**(다른 앱이 띄운 관리자 암호 요청)이 앞에 있으면 메모가 잠깐 떴다가 닫힌다. 암호 창을 닫은 뒤 다시 누르면 된다.
- **비공개 API**: tao가 재정의하던 비공개 NSView 메서드 `_wantsKeyDownForEvent:`는 vendor/tao 패치로 등록하지 않는다(2026-09-30). `scripts/check-private-api.sh`는 이 이름이 바이너리에 있으면 실패하고, `build-mas.sh`가 제출용 앱에서 이 검사를 돌린다. 그 대가로 Ctrl-Tab·Ctrl-Esc는 앱 화면에 따로 전달되지 않는다(MemoBuddy는 이 키를 쓰지 않는다). 실제 심사 결과는 제출해야 알 수 있다.
