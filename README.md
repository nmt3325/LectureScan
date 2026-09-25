# LectureScan

授業中の書類・黒板・プロジェクター画面を、静かに撮影してすぐ貼り付けるための iPhone アプリです。

## 主な機能

- **無音撮影**
  - iOS 18 以降で端末・地域が対応している場合は、Apple の公開 API `isShutterSoundSuppressionEnabled` を使った高画質撮影。
  - シャッター音抑制を利用できない端末・地域では、`AVCaptureVideoDataOutput` の最新フレームを取得する方式へ自動切り替え。静止画シャッターを呼ばず、アプリ側でも撮影音を再生しません。
- **安全なハイブリッド矩形検知** — Vision の Document Segmentation と複数のRectangle候補を、幾何検証・検出器間consensus・時間方向priorで選別。曖昧な場合は誤った自動cropを行わず元画像を保存し、状態に応じて単一検出とdual probeを切り替えます。
- **自動切り抜き・任意の後編集** — Core Image の `CIPerspectiveCorrection` で自動補正。撮影直後はカメラを継続し、必要なときだけ左下の撮影ライブラリから画像を選び、「編集」で四隅を修正できます。ポイントのドラッグ中は周囲を 3 倍に拡大する円形ルーペを表示します。
- **撮影ライブラリ** — 元画像・補正済み画像・切り抜き情報・サムネイルをアプリ内へ永続保存し、一覧表示、詳細表示、再コピー、後編集に対応します。
- **写真ライブラリ保存・自動コピー** — 撮影時に補正済み JPEG を写真ライブラリへ自動保存し、同時に `UIPasteboard` へコピー。編集は必須ではなく、手動修正版も新しい写真として保存・コピーします。
- **授業向け操作** — タップフォーカス、通常時は `.5 / 1× / 2` のようにコンパクトな倍率プリセットを表示し、タップで切り替え。倍率表示をスライドしている間だけ目盛り付き円弧ダイヤルを展開し、指の移動方向と円盤の回転感が一致する方向でズームできます。プレビューの2本指回転・ピンチにも対応します（端末の対応範囲内・最大8倍）。
- **システム表示倍率に対応** — iOS 18 以降では Apple 公開の `displayVideoZoomFactorMultiplier` を使い、複合カメラの広角端を `.5×` などシステムカメラと同じ基準で表示します。iOS 17 では倍率 1 を基準にフォールバックします。
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

## 未署名 IPA・AltStore / LiveContainer 配布

`main` へコミットが push されるたびに GitHub Actions の **Unsigned IPA** が自動実行されます（手動実行も可能です）。実機向け Release ビルドを署名なしで作成し、Workflow Artifact に加えて `nightly` リリースへ次のファイルを更新します。

- `LectureScan-unsigned.ipa`
- `LectureScan-unsigned.ipa.sha256`
- `altstore-source.json`

### 公開 URL

- リポジトリ: <https://github.com/nmt3325/LectureScan>
- AltStore / SideStore / LiveContainer 互換ソース: <https://github.com/nmt3325/LectureScan/releases/download/nightly/altstore-source.json>
- 最新の未署名 IPA: <https://github.com/nmt3325/LectureScan/releases/download/nightly/LectureScan-unsigned.ipa>
- Nightly リリース: <https://github.com/nmt3325/LectureScan/releases/tag/nightly>

AltStore の「Sources」には上記の互換ソース URL を追加してください。LiveContainer の Sources にも同じ URL を追加できます。URL スキームを使う場合:

```text
altstore://source?url=https%3A%2F%2Fgithub.com%2Fnmt3325%2FLectureScan%2Freleases%2Fdownload%2Fnightly%2Faltstore-source.json
livecontainer://install?url=https%3A%2F%2Fgithub.com%2Fnmt3325%2FLectureScan%2Freleases%2Fdownload%2Fnightly%2FLectureScan-unsigned.ipa
```

ワークフローは `macos-15` で Xcode 26.6（利用できない場合は runner の既定 Xcode）を選択し、`iphoneos` 向けにビルドします。署名・プロビジョニングプロファイルが含まれていないことを検証し、コミットごとの build number、IPA サイズ、ダウンロード URL を含む AltStore v2 互換 JSON を生成します。LiveContainer の AltStore source parser が読む `versions` / `buildNumber` 形式にも対応しています。

> 未署名 IPA を通常の iPhone アプリとして直接インストールする場合は、利用する端末と Apple ID に対応した証明書・プロビジョニングプロファイルで再署名してください。LiveContainer へ読み込む場合は、LiveContainer 側の導入・署名要件に従ってください。

## 開発書記（必須）

このリポジトリで人が変更コミットを作成する場合は、**同じコミットに対応する開発書記を必ず含めてください**。書記のない変更は完了扱いにしません。

- 保存先・履歴索引: [`docs/development-journal/`](docs/development-journal/README.md)
- 新規作成用: [`docs/development-journal/TEMPLATE.md`](docs/development-journal/TEMPLATE.md)
- 必須内容: 実施内容、改善点、問題、原因、対処、検証、結果、残る問題・制約

実装と書記を別コミットに分けず、検証できた事実と未確認事項を区別して記録してください。Simulatorや合成fixtureの結果を実機結果として記載しないでください。

## 構成

- `CameraModel.swift` — AVFoundation セッション、無音方式の選択、撮影、クリップボード
- `CameraPreview.swift` — プレビュー、矩形オーバーレイ、タップフォーカス
- `DocumentProcessor.swift` — hybrid Vision候補生成、台形補正、画質調整
- `RectangleDetection.swift` — 候補の幾何検証、IoU、consensus、安全な選択
- `LiveRectangleTracker.swift` — live検出の状態機械、平滑化、世代管理
- `CameraScreen.swift` — SwiftUI カメラ UI と左下のライブラリ導線
- `CaptureLibraryStore.swift` — 元画像・補正画像・メタデータ・サムネイルの永続保存
- `CaptureLibraryScreen.swift` — 撮影一覧、詳細、コピー、後編集 UI
- `CropEditorScreen.swift` — 四隅をドラッグできる切り抜き修正 UI と円形拡大ルーペ
- `LectureScanTests/` — 補正、保存、矩形選択、live trackerの回帰テスト
- `docs/development-journal/` — コミット単位の開発書記

## プライバシー

撮影画像は端末内で処理されます。補正後の JPEG を写真ライブラリへ保存してクリップボードにも書き込み、後編集用の元画像と補正画像をアプリの Application Support 内にも保存します。写真への追加権限のみを要求し、写真ライブラリの読み取りや外部サーバーへの画像送信は行いません。アプリ内ライブラリはアプリを削除すると消えますが、写真ライブラリへ保存済みの画像は残ります。

## License

MIT License
