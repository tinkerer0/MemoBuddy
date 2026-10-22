# MemoBuddy Privacy Policy / 개인정보 처리방침

Last updated: 2026-10-15

## English

MemoBuddy is a notebook that runs entirely on your own device: your computer (macOS, Windows) or your Android phone.

- **No data collection.** MemoBuddy has no account, no analytics, no advertising and no telemetry. Its developer does not receive your notes, drawings, settings or any other information about you.
- **Network use.** MemoBuddy itself makes no network requests. The only exception is when you choose **Privacy Policy** or **Open-Source Licenses** from its menu: that page opens in your web browser.
- **Windows.** MemoBuddy's windows are drawn by Microsoft Edge WebView2, a part of Windows. Like other parts of Windows, WebView2 may send Microsoft required diagnostic data, optional diagnostic data if you allow it in Windows settings, and crash reports. MemoBuddy does not add your notes or any other data to it. See [Microsoft's WebView2 data and privacy page](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy).
- **Where your data lives.** Notes, drawings, settings and any custom character image you choose are stored only on your computer, in MemoBuddy's app data folder (on macOS inside the app's sandbox container). They are not encrypted by MemoBuddy; other software running under your user account may be able to read them.
- **Deleting your data.** Delete a note inside the app to remove it from the notes file. To recover from a damaged file, MemoBuddy keeps a backup of the previous notes file (`notes.backup.json`), so a deleted note can stay in that backup until MemoBuddy saves your notes again at least 30 seconds later. If a notes file was ever damaged, MemoBuddy keeps the damaged copies (`notes-corrupt-…`, and `notes-backup-corrupt-…` if the backup was damaged too) instead of deleting them, and a `note.txt` from a very old version may also remain. To remove everything, quit MemoBuddy and delete its whole app data folder: on macOS, delete the app and the folder `~/Library/Containers/app.memopet.desktop`; on Windows, uninstall MemoBuddy (the Microsoft Store version removes its data with it) and, if you used a test build before, also delete `%APPDATA%\app.memopet.desktop`.
- **Android.** The Android app has no internet permission, so it cannot send anything over the network. Its memo screen is drawn by Android System WebView, a part of Android; like other parts of Android it may send Google crash reports and usage data if you allow that in your device settings, and MemoBuddy adds nothing to it. The "Display over other apps" permission is used only to show the pet on top of other apps; MemoBuddy does not read what other apps show. While the pet is on screen, Android shows a notification for it. Notes, drawings and settings are stored in MemoBuddy's private app storage on the phone, which other apps cannot read. MemoBuddy turns off Android's cloud backup; Android's device-to-device transfer, which you start yourself when setting up a new phone, can still copy them to that phone. If the notes file was ever damaged, MemoBuddy keeps it as `notebook.json.bad-…` in the same storage instead of deleting it. Uninstalling MemoBuddy deletes all of it.
- **Children.** MemoBuddy does not knowingly collect any information from anyone, including children.
- **Contact.** Questions about this policy: <https://github.com/tinkerer0/MemoBuddy/issues>

## 한국어

MemoBuddy는 사용자의 기기, 즉 컴퓨터(macOS·Windows)나 Android 폰 안에서만 동작하는 메모장입니다.

- **수집하지 않습니다.** 계정·분석·광고·원격 수집이 없습니다. 개발자는 메모·그림·설정이나 사용자에 관한 어떤 정보도 받지 않습니다.
- **네트워크.** MemoBuddy 자체는 네트워크 요청을 하지 않습니다. 메뉴에서 **개인정보 처리방침**이나 **오픈소스 라이선스**를 고를 때만 해당 페이지가 웹 브라우저에서 열립니다.
- **Windows.** MemoBuddy의 창은 Windows 구성요소인 Microsoft Edge WebView2가 그립니다. WebView2는 다른 Windows 구성요소처럼 Microsoft에 필수 진단 데이터, (Windows 설정에서 허용한 경우) 선택 진단 데이터, 오류 보고를 보낼 수 있습니다. MemoBuddy는 여기에 메모나 다른 정보를 더하지 않습니다. [Microsoft의 WebView2 데이터·개인정보 안내](https://learn.microsoft.com/ko-kr/microsoft-edge/webview2/concepts/data-privacy)를 참고하세요.
- **데이터 위치.** 메모·그림·설정과 직접 고른 캐릭터 이미지는 이 컴퓨터의 MemoBuddy 앱 데이터 폴더(macOS에서는 앱 샌드박스 컨테이너 안)에만 저장됩니다. MemoBuddy가 따로 암호화하지는 않으므로 같은 사용자 계정에서 실행되는 다른 프로그램은 읽을 수 있습니다.
- **삭제.** 앱에서 메모를 지우면 메모 파일에서 지워집니다. 다만 파일 손상에 대비해 직전 메모 파일의 백업(`notes.backup.json`)을 두기 때문에, 지운 메모는 30초 이상 지나 다음에 저장될 때까지 백업에 남을 수 있습니다. 메모 파일이 손상된 적이 있으면 손상된 사본(`notes-corrupt-…`, 백업도 손상됐다면 `notes-backup-corrupt-…`)을 지우지 않고 남겨 두며, 아주 옛 버전의 `note.txt`가 남아 있을 수도 있습니다. 전부 지우려면 MemoBuddy를 종료하고 앱 데이터 폴더 전체를 지우세요. macOS에서는 앱과 `~/Library/Containers/app.memopet.desktop` 폴더를 지우고, Windows에서는 MemoBuddy를 제거한 뒤(Microsoft Store 버전은 데이터도 함께 지워짐) 전에 테스트 빌드를 썼다면 `%APPDATA%\app.memopet.desktop` 폴더도 지우면 됩니다.
- **Android.** Android 앱에는 인터넷 권한이 없어 네트워크로 아무것도 보낼 수 없습니다. 메모 화면은 Android 구성요소인 Android System WebView가 그립니다. WebView는 다른 Android 구성요소처럼 기기 설정에서 허용한 경우 Google에 오류 보고와 사용 데이터를 보낼 수 있으며, MemoBuddy는 여기에 아무것도 더하지 않습니다. "다른 앱 위에 표시" 권한은 펫을 다른 앱 위에 보여 주는 데만 쓰고, 다른 앱의 화면 내용은 읽지 않습니다. 펫이 화면에 있는 동안 Android가 알림을 하나 보여 줍니다. 메모·그림·설정은 폰 안의 MemoBuddy 전용 저장 공간에 저장되며 다른 앱은 읽을 수 없습니다. MemoBuddy는 Android 클라우드 백업을 끄지만, 새 폰을 설정할 때 사용자가 직접 시작하는 기기 간 전송은 이 데이터를 새 폰으로 옮길 수 있습니다. 메모 파일이 손상된 적이 있으면 지우지 않고 같은 공간에 `notebook.json.bad-…`로 남겨 둡니다. MemoBuddy를 삭제하면 모두 지워집니다.
- **아동.** MemoBuddy는 아동을 포함해 누구의 정보도 수집하지 않습니다.
- **문의.** 이 방침에 관한 문의: <https://github.com/tinkerer0/MemoBuddy/issues>
