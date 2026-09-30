# MemoPet 출시 안내 (Mac App Store · Microsoft Store)

2026-09-30 작성. 이 문서는 "계정 주인이 직접 해야 하는 일"과 "이미 준비된 것"을 나눈다. 계정·결제·본인 인증·스토어 제출은 계정 주인만 할 수 있다.

## 한눈에 보기

| | Mac App Store | Microsoft Store |
| --- | --- | --- |
| 계정 | Apple Developer Program **연 $99**(유료) | 개인 개발자 등록 **무료**(신분증·셀카 인증) |
| 포장 | 서명된 `.pkg` (`scripts/build-mas.sh`, 이 맥에서 실행) | MSIX (`scripts/pack-msix.ps1`, **Windows 11 PC 필요**) |
| 서명 | Apple 인증서 2개 + 프로비저닝 프로파일 | Store가 서명(따로 살 인증서 없음) |
| 심사 | 보통 1~3일 | 보통 1~3영업일 |
| 준비 상태 | 스크립트·권한 파일 준비됨, 계정 필요 | 매니페스트·스크립트 준비됨(Windows에서 미실행), 계정·Windows PC 필요 |

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
6. **App Store Connect에 앱 만들기**: <https://appstoreconnect.apple.com> → 앱 → `+` → 새로운 앱 → 플랫폼 macOS, 이름 `MemoPet`(이미 쓰이면 `MemoPet – Floating Notes` 등), 기본 언어는 **English (U.S.)**(다른 나라 사용자가 보는 기본 문구, 한국어는 현지화로 추가), 번들 ID `app.memopet.desktop`, SKU 아무 값(예 `memopet-mac`).
7. **스토어 정보 입력** (문구 초안: `docs/STORE_LISTING.md`)
   - 스크린샷: 16:10 비율 1장 이상(1280×800, 1440×900, 2560×1600, 2880×1800 중 하나).
   - 부제·설명·키워드·지원 URL·**개인정보 처리방침 URL**.
   - 카테고리: 생산성(Productivity).
   - 앱 개인정보(App Privacy): **데이터를 수집하지 않음**.
   - 연령 등급 설문: 모두 "없음" → 4+.
   - 가격: 무료(추천).
8. **빌드·업로드** (이 맥 터미널):
   ```sh
   cd MemoPet   # 이 저장소를 받은 폴더
   TEAM_ID=ABCDE12345 \
   BUILD_NUMBER=1 \
   APP_SIGN_IDENTITY="Apple Distribution: 이름 (ABCDE12345)" \
   INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: 이름 (ABCDE12345)" \
   PROVISIONING_PROFILE=~/Downloads/MemoPet_Mac_App_Store.provisionprofile \
   ./scripts/build-mas.sh
   ```
   결과물은 `dist-mas/MemoPet.pkg`다. 업로드는 두 방법 중 하나로 한다.
   - Mac App Store의 **Transporter** 앱에 `MemoPet.pkg`를 끌어다 놓고 "전달".
   - 또는 App Store Connect → 사용자 및 액세스 → 통합 → 개별 키에서 API 키를 만든다. 내려받은 키 파일은 Apple 안내대로 홈 폴더의 `.appstoreconnect` 아래 `private_keys` 폴더에 둔다. 그다음 `APPLE_API_KEY_ID`·`APPLE_API_ISSUER`를 붙여 위 명령을 다시 실행하면 자동으로 올라간다. 이 키는 비밀정보이니 저장소나 채팅에 붙이지 않는다.
9. **TestFlight로 먼저 확인**(추천) → 심사 제출.
10. **다시 올릴 때**: 빌드 번호(`BUILD_NUMBER`)는 올릴 때마다 전보다 커야 하고, 앱 버전을 올려도 처음으로 돌아가지 않는다(macOS 규칙). 첫 업로드 1, 그다음 2, 3…으로 쓰고 마지막 번호를 적어 둔다. 새 버전을 낼 때는 `package.json`·`src-tauri/tauri.conf.json`·`src-tauri/Cargo.toml`의 버전을 함께 올린다.

심사 대비 메모(심사자에게 남길 설명): "MemoPet is a menu bar app (no Dock icon). Click the character floating at the lower right of the screen, or choose Open Memo from the menu bar icon, to open the notebook. Notes stay on the Mac; there is no account and no network use."

## B. Microsoft Store — 계정 주인이 할 일

1. **개인 개발자 등록(무료)**: <https://storedeveloper.microsoft.com> → 개인으로 등록 → 신분증·셀카 인증.
2. **앱 이름 예약**: Partner Center → Apps and games → New product → MSIX or PWA app → `MemoPet`.
3. **Product identity 값 3개 확인**: 앱 → Product management → Product identity의 `Package/Identity/Name`, `Package/Identity/Publisher`(`CN=...`), `Package/Properties/PublisherDisplayName`.
4. **Windows 11 PC 준비**: MSIX 포장과 실제 창 동작 확인에 필요하다. 먼저 시험만 할 때는 GitHub Actions의 최근 성공한 CI 실행에서 `MemoPet-windows-installer`(서명 없는 설치 파일, GitHub 로그인 필요, 90일 보관)를 받아 Windows PC에서 설치해 본다. SmartScreen이 막으면 "추가 정보 → 실행". 관리자 권한 없이 현재 사용자에게 설치된다. Windows PC는 다음 중 하나로 구한다.
   - 가족·지인의 Windows 11 PC를 잠시 빌린다.
   - 맥에 UTM과 Windows 11 Arm 평가판(무료 90일, 디스크 약 64GB)을 설치한다.
   - 유료 클라우드 Windows VM을 쓴다.
5. **포장** (Windows 11 PowerShell):
   ```powershell
   winget install OpenJS.NodeJS --source winget
   winget install Rustlang.Rustup --source winget
   winget install microsoft.winappcli --source winget
   git clone <저장소> memopet; cd memopet
   .\scripts\pack-msix.ps1 -IdentityName "<Name>" -Publisher "<CN=...>" -PublisherDisplayName "<표시 이름>" -Version 1.0.0.0
   ```
   출시 전 로컬 시험은 `.\scripts\pack-msix.ps1 -DevCert`로 만든 패키지를 설치해 확인한다. 이때 개발용 인증서를 한 번 신뢰해야 한다. 관리자 PowerShell에서 `winapp cert install`로 등록하고, 인증서 파일은 `packaging/windows` 폴더에 생긴다.
6. **스토어 정보**: 기본 언어는 영어(미국), 한국어를 추가 언어로. 스크린샷 1장 이상(1366×768 이상, 1920×1080 추천), 설명, 카테고리 생산성, **개인정보 처리방침 URL**, 연령 등급(IARC 설문), 가격 무료.
7. **제한된 기능 설명**: 패키지가 `runFullTrust`를 쓰므로 제출 화면에서 이유를 묻는다. 예시: "MemoPet is a desktop app built with Tauri. runFullTrust is required to run its desktop executable, which shows an always-on-top character and memo window. It does not access other apps' data."
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
- `com.apple.security.network.client`: 샌드박스 안의 WebKit이 앱 자체 화면을 불러오는 데 필요하다(없으면 메모 창이 빈 화면, 2026-09-30 실측). 앱은 네트워크 요청을 보내지 않는다.

## E. 알려진 한계 (2026-09-30 기준)

- **Windows는 실행해 보지 않았다.** 코드는 Windows 타깃으로 컴파일만 확인했다. 캐릭터 창 투명도·포커스·트레이·MSIX 포장은 Windows 11 PC에서 처음 확인하게 된다.
- **macOS 로그아웃·시스템 종료**: Tauri의 창 라이브러리(tao)가 종료 확인(`applicationShouldTerminate:`)을 받지 않아 저장 절차 없이 끝난다. 입력은 멈춘 뒤 0.3초, 계속 입력해도 최대 1초 안에 저장되므로 마지막 저장 이후 그 사이에 친 글자만 위험하다. ⌘Q·메뉴의 종료는 저장한 뒤 끝난다.
- **실행 중 "동작 줄이기" 설정 변경**은 다음 캐릭터 교체나 재실행 때 반영된다.
- **메뉴 막대(트레이) 아이콘**은 VoiceOver의 누르기 동작으로 메뉴가 열리지 않는다(tray-icon 라이브러리 한계). 캐릭터 우클릭 메뉴와 메모 창은 키보드로 쓸 수 있다.
- **시스템 암호 창**(다른 앱이 띄운 관리자 암호 요청)이 앞에 있으면 메모가 잠깐 떴다가 닫힌다. 암호 창을 닫은 뒤 다시 누르면 된다.
- **심사 위험**: 바이너리에 tao가 재정의한 NSView 메서드 이름 `_wantsKeyDownForEvent:`가 들어 있다. Apple 비공개 API 호출이 아니고 Tauri 공식 App Store 안내도 문제로 다루지 않지만, 실제 심사 결과는 제출해야 알 수 있다(`scripts/check-private-api.sh`가 안내 줄로 보여 준다).
