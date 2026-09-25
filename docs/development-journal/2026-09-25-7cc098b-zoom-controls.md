# Add camera-style zoom controls

| 項目 | 内容 |
|---|---|
| Commit | `7cc098bd79703494c6f50e28c87920a2c83f649a` |
| 日時 | 2026-09-25 09:50 UTC |
| 種別 | feature / test / docs |
| 状態 | 完了（操作方向は後続コミットで修正） |

## 要約

システムカメラに近い倍率表示と操作を追加した。倍率preset、円弧dial、pinch、2本指回転、VoiceOver adjustable actionから同じZoom APIを操作できるようにした。

## 問題点と原因

初期版にはZoom状態と操作UIがなく、複合カメラのhardware zoom値をそのまま表示すると、利用者が期待する`.5× / 1× / 2×`表記と一致しない。端末ごとの最小・最大倍率を考慮したclampも必要だった。

## 対処・実装

- `CameraModel`に`zoomFactor`と`CameraZoomRange`を追加した。
- iOS 18以降では`displayVideoZoomFactorMultiplier`を使い、表示倍率とhardware倍率を相互変換した。iOS 17では1をfallbackにした。
- 端末の利用可能範囲へclampし、画質上限として8倍を設定した。
- `.5 / 1 / 2`などのpreset、drag中だけ表示する目盛り付き円弧dial、preview pinch・rotationを追加した。
- accessibility label/value/hintとadjustable actionを追加した。

## 検証・結果

Zoom範囲のmodelとDocumentProcessor testsを更新し、端末差を吸収する入口を一本化した。履歴からの遡及記録であり、当時の全端末範囲を再検証してはいない。

## 残る問題・制約

- 円弧dragの符号が利用者の円盤回転感と逆で、後の`b2a25b3`で修正した。
- 実際のlens切替や画質は端末依存であり、実機確認が必要である。

## 主な変更ファイル

- `LectureScan/CameraModel.swift` — Zoom設定と表示倍率変換
- `LectureScan/CameraPreview.swift` — pinch・rotation gesture
- `LectureScan/CameraScreen.swift` — presetと円弧dial
- `LectureScan/Models.swift` — `CameraZoomRange`
