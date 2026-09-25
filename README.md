# LectureScan

授業中の書類・黒板・プロジェクター画面を、静かに撮影してすぐ貼り付けるための iPhone アプリです。

## 主な機能

- **無音撮影**
  - iOS 18 以降で端末・地域が対応している場合は、Apple の公開 API `isShutterSoundSuppressionEnabled` を使った高画質撮影。
  - シャッター音抑制を利用できない端末・地域では、`AVCaptureVideoDataOutput` の最新フレームを取得する方式へ自動切り替え。静止画シャッターを呼ばず、アプリ側でも撮影音を再生しません。
- **リアルタイム矩形検知** — Vision の `VNDetectRectanglesRequest` で書類・黒板・スクリーンを検出し、黄色い枠で表示。
- **自動切り抜き・台形補正** — Core Image の `CIPerspectiveCorrection` で撮影後に自動補正。
- **クリップボードへ自動コピー** — 補正済み JPEG を `UIPasteboard` に保存。写真ライブラリ権限は不要。
- **授業向け操作** — タップフォーカス、控えめなトーチ、再コピー用サムネイル。
- **端末内処理** — 画像のアップロードや外部通信は行いません。

## 無音撮影の実装方針

Apple の公開 API は、シャッター音を無効化できない地域では `isShutterSoundSuppressionSupported == false` を返します。LectureScan はその場合、カメラの連続プレビューから 1 フレームを取得して画像化するため、`AVCapturePhotoOutput` の静止画シャッターを実行しません。プライベート API やシステム音量の変更は使用していません。

フレーム方式は端末によって静止画モードより解像度が低い場合があります。日本向け実機で、画質・矩形認識・無音動作を確認してください。OS や端末側の挙動をアプリから完全に上書きすることはできません。

## 要件

- iOS 17.0 以降
- Xcode 16.0 以降（Xcode 26.6 / iOS 26.5 Simulator で検証）
- 実機でのカメラテストには Apple Development の署名設定が必要

## ビルド

生成済みの `LectureScan.xcodeproj` を開き、Signing & Capabilities で Team を選択して実機へ実行します。

```bash
open LectureScan.xcodeproj
```

プロジェクトを再生成する場合:

```bash
brew install xcodegen
xcodegen generate
```

コマンドラインでの確認:

```bash
xcodebuild \
  -project LectureScan.xcodeproj \
  -scheme LectureScan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test \
  CODE_SIGNING_ALLOWED=NO
```

> iOS Simulator にはカメラがないため、カメラ入力・撮影音・トーチは実機で確認してください。画像補正ロジックのユニットテストは Simulator で実行できます。

## 未署名 IPA の CI

GitHub Actions の **Unsigned IPA** ワークフローを手動実行すると、実機向け Release ビルドを署名なしで作成し、次のファイルを Artifact として 14 日間保存します。

- `LectureScan-unsigned.ipa`
- `LectureScan-unsigned.ipa.sha256`

実行手順:

1. リポジトリの **Actions** を開く
2. **Unsigned IPA** を選択する
3. **Run workflow** を実行する
4. 完了した run の **Artifacts** から `LectureScan-unsigned-<commit SHA>` をダウンロードする

ワークフローは `macos-15` で Xcode 26.6（利用できない場合は runner の既定 Xcode）を選択し、`iphoneos` 向けにビルドし、署名・プロビジョニングプロファイルが含まれていないことを確認してから IPA を生成します。署名証明書や秘密情報を GitHub に登録する必要はありません。

> 未署名 IPA はそのまま通常の iPhone へインストールできません。使用する端末と Apple ID に対応した証明書・プロビジョニングプロファイルで、利用者自身が再署名してください。また、PRIVATE リポジトリの macOS runner は課金対象のため、GitHub Actions の spending limit を有効にしてから実行してください。

## 構成

- `CameraModel.swift` — AVFoundation セッション、無音方式の選択、撮影、クリップボード
- `CameraPreview.swift` — プレビュー、矩形オーバーレイ、タップフォーカス
- `DocumentProcessor.swift` — Vision 検知、台形補正、画質調整
- `CameraScreen.swift` — SwiftUI UI
- `LectureScanTests/` — Core Image 補正処理のテスト

## プライバシー

撮影画像は端末内で処理され、補正後の JPEG のみクリップボードへ書き込まれます。写真ライブラリや外部サーバーには自動保存しません。

## License

MIT License
