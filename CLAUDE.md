# CLAUDE.md

## Project Overview

MIDI2Sniffer is a passive MIDI 2.0 / Property Exchange sniffer for macOS. It captures and displays MIDI 2.0 UMP messages in real-time for debugging and analysis.

### 主目的

KORG Module と KeyStage を接続した際の MIDI 2.0 Property Exchange 手続きを解析すること。Module は接続するだけで DeviceInfo を取得し、PE 経由で PG名・CC名を KeyStage に送って表示させている。この一連の手続き（Discovery → PE Capability → ResourceList → ChCtrlList/ProgramList）をキャプチャ・解析し、MIDI 2.0 関連プロジェクト（MIDI2Kit、SimpleMIDIController 等）に応用するのが本アプリの目的。

### 解析で判明した PE ハンドシェイク手順

KeyStage が能動的に Module のリソースを取得する構造:

1. Module → Discovery (ブロードキャスト)
2. KeyStage → DiscoveryReply
3. 双方 PE CapInquiry / CapReply
4. **KeyStage → Module: PE GET ResourceList**
5. Module → Reply: DeviceInfo, ChannelList, ProgramList, JSONSchema, X-ParameterList, X-ProgramEdit
6. **KeyStage → Module: PE GET DeviceInfo, ChannelList, ProgramList, X-ParameterList, X-ProgramEdit, JSONSchema**
7. KeyStage → Module: PE Subscribe (ChannelList, ProgramList, X-ParameterList, X-ProgramEdit)

Module の X-ParameterList に CC名（EQ Low=CC#100, Release Time=CC#72 等）、ProgramList に PG名（Song 1〜5 + bankPC）が含まれる。

### 現在の課題: KeyStage ハング問題

Sniffer 起動中に PE 通信をキャプチャすると、KeyStage の表示がハングする現象が発生。

**ログ分析で判明した原因:**

1. **ResourceList GET の異常リトライ** — KeyStage が同じ ResourceList GET (reqID=0) を4回送信（3ms〜18ms 間隔）。各回に Module が3チャンクの Reply を返すため Reply が洪水状態になる
2. **複数の MIDI-CI セッション並行** — Module が複数の MUID（0x186FA82, 0x6919C81, 0xC3C9C81）で同時にセッションを開く。KeyStage は全セッションに応答し、Module からの Reply も全セッション分受け取る
3. **謎の第三者 MUID** — `0xC3C9C81→0xCBD32ED` という未知の MUID ペアが PE GET-Reply を出している（macOS CoreMIDI の内部 MIDI-CI セッションの可能性）
4. **Reply の重複洪水** — Module→KeyStage 方向の GET-Reply が52件。正常なら各リソース1回ずつで十分なはずが、複数セッション × リトライで大量に届き、KeyStage がハング

**根本原因の仮説:** 接続時に複数の Discovery サイクルが走り、Module が複数 MUID セッションを並行して開くことで PE Reply が重複する。Sniffer 自体はパッシブ（仮想エンドポイント非作成）だが、macOS CoreMIDI が内部的に MIDI-CI セッションを開いている可能性がある。

**再現性:** KeyStage 電源再起動後も同一パターンで再発（capture-20260223-keystage-reboot-hang）。全 PE GET-Reply が2重に届く一貫したパターン:
- DiscoveryReply x2, CapReply x2, SubscribeReply x2
- マルチチャンク Reply で最終チャンクが追加で1回余分に届く（chunk 3/3 が2回等）
- 謎の MUID `0xC3C9C81→0xCBD32ED` も毎回出現
- ResourceList GET のリトライ（reqID=0 を2回送信）も再現

**過去プロジェクトでの関連報告（MIDI2Kit docs）:**
- `KORG-PE-Compatibility.md`: iPad 環境でマルチチャンク chunk 2/3 欠落（CoreMIDI/BLE 転送レイヤーの問題と推定）
- `KnownIssues.md`: BLE MIDI マルチチャンクパケットロス（90%失敗率）
- `KORG-Module-Pro-Limitations.md`: ResourceList 3チャンクでランダムにチャンク欠落（CoreMIDI 仮想ポートバッファリングの問題と推定）
- 今回の USB 接続でも Reply 重複が発生 → BLE 固有の問題ではなく CoreMIDI レイヤーの問題

### キャプチャデータ

| ファイル | 内容 |
|----------|------|
| `docs/capture-20260223-102754-with-timingclock.midi2sniff.json` | 初回（Timing Clock含む、6205件） |
| `docs/capture-20260223-keystage-reconnect.midi2sniff.json` | USB再接続（System除外、35件） |
| `docs/capture-20260223-keystage-hang.midi2sniff.json` | PE全手続き＋ハング発生（165件） |
| `docs/capture-20260223-keystage-reboot-hang.midi2sniff.json` | 電源再起動後＋再ハング（84件） |

## Build & Run

The project uses **XCGen** (`project.yml`) to generate the Xcode project. Open `MIDI2Sniffer.xcworkspace`.

```bash
# macOS build
xcodebuild build -workspace MIDI2Sniffer.xcworkspace -scheme MIDI2Sniffer -destination 'platform=macOS'
```

**Requirements:** Xcode 16.0+, Swift 6.0+, macOS 15.0+
**Local dependency:** MIDI2Kit at `../../MIDI2Kit`

## Architecture

- **MIDI2SnifferPackage** (Swift Package) contains all logic in `MIDI2SnifferKit`
- **MIDI2Sniffer/** is the thin macOS app shell with `@main` entry point

### Key Types

| Type | Role |
|------|------|
| `MIDISnifferEngine` | MIDI device enumeration and UMP message capture via MIDI2Kit |
| `CaptureSession` | Recording session management |
| `MessageDecoder` | UMP message decoding to human-readable format |
| `SnifferState` | @Observable shared state container |
| `SnifferMainView` | Root SwiftUI view |

## Coding Conventions

- **Swift 6 strict concurrency** enabled
- **MV pattern** (Model-View, no ViewModel)
- **@Observable** macro (no ObservableObject)
- **Swift Concurrency** only (no GCD)
