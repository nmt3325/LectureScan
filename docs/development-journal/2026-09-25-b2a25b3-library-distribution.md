# Add capture library and automated unsigned distribution

| 項目 | 内容 |
|---|---|
| Commit | `b2a25b3b148968e8132b6141205ab76cc990990b` |
| 日時 | 2026-09-25 11:18 UTC |
| 種別 | feature / fix / test / ci / docs |
| 状態 | 完了 |

## 要約

撮影直後の編集を必須にせず、撮影を続けながら後で選択・再編集できる永続ライブラリへ変更した。同時にcorner拡大鏡とZoom dial方向修正を行い、`main` pushから未署名IPAとAltStore互換sourceを自動公開する経路を構築した。

## 問題点

- 撮影直後にfull-screen editorが開き、講義中の連続撮影を中断した。
- 最後の1枚しか保持されず、後から過去画像を再コピー・再編集できなかった。
- 四隅の指位置で細部が隠れ、正確な調整が難しかった。
- Zoom dialのdrag方向と視覚上の円盤回転が逆だった。
- 未署名IPAが手動workflowの一時Artifactだけで、固定URLから取得できなかった。

## 原因

撮影状態が`lastImage`と`editableCapture`というmemory上の単一値に結合され、撮影完了をeditor表示triggerとしていた。永続index、元画像、補正画像、thumbnailを管理するstorage層がなかった。Zoom計算ではangle deltaの符号がUIの回転方向と一致していなかった。配布workflowは`workflow_dispatch`とArtifact uploadまでしか実装していなかった。

## 対処・実装

- `CaptureLibraryStore`を追加し、Application Supportへ`source.jpg`、`processed.jpg`、`thumbnail.jpg`、四隅を含む`index.json`をatomicに保存した。
- 一覧・詳細・再コピー・後編集画面を追加し、撮影完了後はカメラ画面を維持した。
- editorのcorner drag中に3倍の円形拡大鏡とcrosshairを表示した。
- `ZoomDialMath`に計算を分離し、angle deltaを反転して操作方向を修正した。
- `main` pushでunsigned workflowを起動し、commitごとのbuild number、SHA-256、AltStore v2/SideStore/LiveContainer互換JSONを生成した。
- `nightly` tag/releaseを更新し、IPA、checksum、`altstore-source.json`を固定URLで公開した。
- storage、Zoom計算、互換JSONに関するテスト・検査を追加した。

## 検証・結果

GitHub Actions run [36128718037](https://github.com/nmt3325/LectureScan/actions/runs/36128718037)が成功し、nightly Release更新経路が動作した。撮影と編集が分離され、過去の撮影を永続的に選び直せるようになった。

## 残る問題・制約

- アプリ削除時にはApplication Support内のライブラリも消える。写真ライブラリへ保存済みの画像は残る。
- 未署名IPAは通常のiPhoneへそのまま導入できず、再署名またはLiveContainerが必要である。
- 画像件数増加時の容量管理・削除UIは未実装である。

## 主な変更ファイル

- `LectureScan/CaptureLibraryStore.swift` — 永続storage
- `LectureScan/CaptureLibraryScreen.swift` — 一覧・詳細・後編集
- `LectureScan/CropEditorScreen.swift` — 3倍拡大鏡
- `.github/workflows/unsigned-ipa.yml` — push連動配布
- `.github/scripts/generate_altstore_source.py` — 互換source生成
