# Android Wi-Fi network binding repair — 2026-11-01

## 19:26 follow-up: App-only 0.3.2 default-Wi-Fi compatibility

After delivery of 0.3.1 the user again reported `Binding socket to network 146 failed: EPERM`. The exact installed version was not independently verified; the previous HTML banner was incorrectly fixed at 0.3.0. Network146 is a runtime identifier, not a new error code. Owning a network request did not establish that this handset permits explicit socket binding, and the earlier permission/lifecycle correction must not be claimed as a confirmed field fix.

0.3.2/code11 keeps the Wi-Fi request but uses an ordinary, OS-routed TCP socket when Android reports that this exact requested Wi-Fi is already the calling App's active default network and it is not a VPN. Before returning the connected socket to the protocol layer, it rechecks the default network and confirms the socket's local address belongs to that Wi-Fi's link addresses. A changed/missing route is rejected and closed before HELLO. If the default is cellular, another Wi-Fi, a VPN, blocked or unknown, the existing per-Wi-Fi socket path remains; there is no ordinary-socket fallback to those networks. Permission failures remain explicit. No root operation, global process routing change or system-policy modification is performed.

Logs now show requested/default network identifiers and the selected connection method. The native package version, Android API and device model are shown, and the HTML banner/cache versions are updated. Tests cover actual production session logic with 20 modeled scenarios, including the observed bind denial avoided by a legitimate ordinary default-Wi-Fi socket, non-Wi-Fi default guards, wrong local address, route changes, missing link metadata, ordinary-socket denial/refusal and cleanup. The full existing phone suite also passes. These are not real-phone tests.

- Current APK: `E:/gaoyun_builds/phone_apk_20261101_192632_139730/FPGA-Performance.apk`.
- SHA256: `CD9F17CE14BED5BCDF0B63585030AE54AC83A68A0AB4CE2DE7227EBA5D12C026`.
- `release_verification.json`: same signer as0.3.1, v2/v3, packaged0.3.2/code11, visible banner, source/assets and both test snapshots verified.
- Wi-Fi proof: `E:/gaoyun_builds/phone_wifi_20261101_192612_724320/result.json`.
- Existing-suite proof: `E:/gaoyun_builds/phone_selection_20261101_192612_699827/result.json`.

Install over the previous App, confirm the visible0.3.2 version, keep the ESP hotspot, and reconnect192.168.4.1:333. If Android still makes cellular the default and explicit binding is refused, the App advises temporarily disabling mobile-data/automatic-network-switching while keeping the ESP hotspot, then retrying. It does not change these settings itself. Preserve the full method/phase/error log if failure remains. This step changed only the phone-side application and its tests/docs; no ESP/FPGA source edits, firmware writes or Gowin operations. Real EPERM recovery and long-duration stability are still pending.

Official sources consulted again: Android Developers `ConnectivityManager.getActiveNetwork` returns the calling App's default network, or null when absent/blocked; `Network.getSocketFactory` explicitly binds created sockets to that network. Sources: https://developer.android.com/reference/android/net/ConnectivityManager and https://developer.android.com/reference/android/net/Network . Normal sockets on an already-selected default Wi-Fi avoid an unnecessary explicit binding operation while retaining Android's normal network policy enforcement.

## Earlier 0.3.1 evidence and implementation

## Field evidence and diagnosis boundary

After the ESP LED firmware update, the user saw a brief TCP connection followed by the Wi-Fi-only double flash. The App reported `Binding socket to network 144 failed: EPERM (Operation not permitted)` (transcribed by the user as `bending`). The user confirmed the UI FPGA was not powered down, although the ESP was hot-plugged. This does not establish that power transients caused the failure.

This particular error occurs in Android's per-network socket binding, before `Socket.connect()` reaches the ESP TCP endpoint and before any FPGA HELLO/UART exchange. The number 144 is an Android runtime network identifier, not an IP, port or protocol setting. It must not be hard-coded.

The old App picked the first Wi-Fi entry returned by `getAllNetworks()` and immediately used its socket factory. It did not own a network request or track network loss. This leaves network selection/access and lifetime dependent on a snapshot. The error proves the binding was refused; it does not prove that a missing manifest permission alone caused it, or identify the cause of every previous disconnect.

## Implementation

- `phone_android/AndroidManifest.xml`: version 0.3.1 / code10; add the normal `CHANGE_NETWORK_STATE` permission required by `requestNetwork`.
- New production `WifiNetworkSession.java`: request a Wi-Fi transport without requiring Internet connectivity, await its callback, create the socket on that network, and retain the request throughout TCP communication. Release both socket and callback on cancellation, failure, disconnect or activity destruction. `onLost` closes the affected socket and preserves a useful diagnosis. No global process binding, cellular fallback or suppressed EPERM errors.
- `MainActivity.java`: replace network enumeration with the session; use a connection generation to prevent a late failed connection from tearing down its replacement. Record whether failure occurs during network request, socket binding, TCP connect or TCP I/O.
- `performance_web/phone_app.js`: identify Wi-Fi before connection succeeds, so a pre-connect error is not mislabeled as a Bluetooth disconnect. Existing HELLO, calibration, CRC, recording and file transfer protocols are unchanged.

The existing 8-second network request and 5-second TCP-connect deadlines are separate from the FPGA protocol retry budget. Protocol handshake timeout itself does not close TCP in this App.

## Verification and release

Eleven tests execute the actual production session with modeled Android callbacks/socket failures: network ownership, EPERM, request permission denial, unavailable network, TCP refusal, selected/unrelated network loss, pending cancellation, late-created socket cleanup, already-released callbacks, and independent reconnect sessions. This is not an Android device or RF test.

- Final Wi-Fi evidence: `E:/gaoyun_builds/phone_wifi_20261101_191225_711158/result.json`.
- Existing phone regressions: `E:/gaoyun_builds/phone_selection_20261101_191155_130811/result.json`; native file selection, WAV cache/resume, 22,663 MIDI adaptation cases, CRC/client, download, handshake and 15 durable-recording scenarios all passed. The handshake test also covers a pre-connect EPERM being labeled as Wi-Fi.
- APK: `E:/gaoyun_builds/phone_apk_20261101_191226_545939/FPGA-Performance.apk`.
- SHA256: `B31D8C35E9FE32276FE330F54ABACD04200F28894675209B351521CB01413D8F`.
- `release_verification.json` in the APK directory verifies v2/v3 signing, the same signer as 0.3.0, packaged permission/version, all build-source hashes, every embedded web asset, and both test snapshots.

Install 0.3.1 over the existing App; do not uninstall and discard its local recording cache. Keep the already-flashed ESP LED firmware. Connect the phone to `FPGA-ESP01S` (password `PianoLink1M`), keep the local-only Wi-Fi connection, then use App Wi-Fi TCP `192.168.4.1:333`.

Real-device EPERM recovery and sustained connection/recording transfer remain pending. If it fails, preserve the complete new stage-specific log rather than claiming a hardware root cause or repeatedly reflashing the FPGA. This change did not modify or reflash ESP, UI FPGA or audio FPGA; no Gowin run or file deletion was performed. Source changes are local and uncommitted.

## Reference consulted

Android Developers official `ConnectivityManager` API documentation, accessed 2026-11-01:
https://developer.android.com/reference/android/net/ConnectivityManager

The documentation deprecates `getAllNetworks()` as inefficient and prone to network-state races, specifies `CHANGE_NETWORK_STATE` for `requestNetwork`, and requires releasing callbacks. These API requirements support the lifecycle correction; they do not substitute for testing the user's Android device.
