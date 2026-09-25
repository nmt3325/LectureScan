# Initial release of LectureScan

| 項目 | 内容 |
|---|---|
| Commit | `7feaa322361cca0bc4a9fdf734f8f2c1832c8a67` |
| 日時 | 2026-09-25 08:55 UTC |
| 種別 | feature / test / ci / docs |
| 状態 | 初期版完成 |

## 要約

LectureScanの最初の動作可能な版を作成した。SwiftUIのカメラ画面、AVFoundationによる撮影、Visionの矩形検出、Core Imageの台形補正、クリップボード出力、テスト、XcodeGen設定、CI、READMEを一括して導入した。

## 背景・問題点

授業中の書類、黒板、プロジェクター画面を静かに撮影し、貼り付け可能な補正済み画像へ短時間で変換するアプリが存在していなかった。日本などシャッター音抑制を利用できない環境でも、非公開APIや音量操作に依存しない経路が必要だった。

## 原因

初期開発のため既存不具合の原因はない。必要な撮影、検出、補正、出力の各層が未実装だったことが直接の課題だった。

## 対処・実装

- iOS 18以降で利用可能な公開APIによるシャッター音抑制対応と、利用不能時の`AVCaptureVideoDataOutput`フレーム取得を実装した。
- `VNDetectRectanglesRequest`で四隅を検出し、`CIPerspectiveCorrection`で台形補正した。
- 補正結果をJPEG化し、`UIPasteboard`へコピーした。
- SwiftUI UI、タップフォーカス、トーチ、プレビューoverlayを実装した。
- XcodeGenの`project.yml`、生成済みXcode project、ユニットテスト、GitHub Actions buildを追加した。
- 公開APIのみを使う方針と、端末内処理の範囲をREADMEへ記載した。

## 検証

コミットには`DocumentProcessorTests.swift`とbuild workflowが含まれる。今回の書記は履歴からの遡及記録であり、この初期スナップショット単体のテストを再実行してはいない。

## 結果

撮影から矩形補正、JPEGコピーまでの最小構成が成立し、その後のZoom、手動編集、ライブラリ、配布改善の基盤になった。

## 残る問題・制約

- Simulatorでは実カメラ、撮影音、トーチを検証できない。
- 検出候補の選択、overlay座標、手動修正、永続ライブラリ、配布方法は後続コミットで改善する必要があった。
- フレーム方式は静止画撮影より解像度が低い場合がある。

## 主な変更ファイル

- `LectureScan/CameraModel.swift` — カメラセッションと撮影
- `LectureScan/DocumentProcessor.swift` — 矩形検出と画像補正
- `LectureScan/CameraPreview.swift` — プレビューとoverlay
- `LectureScanTests/DocumentProcessorTests.swift` — 補正ロジックのテスト
- `.github/workflows/build.yml` — build workflow
