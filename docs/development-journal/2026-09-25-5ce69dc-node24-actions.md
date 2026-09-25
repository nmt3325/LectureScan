# Update artifact workflow actions to Node 24 releases

| 項目 | 内容 |
|---|---|
| Commit | `5ce69dc4217df0ebb8b6649f2a03602a261b8a0a` |
| 日時 | 2026-09-25 11:21 UTC |
| 種別 | ci |
| 状態 | 完了 |

## 要約

unsigned IPA workflowで使用するGitHub公式ActionsをNode 24世代へ更新した。

## 問題点と原因

`actions/checkout@v4`と`actions/upload-artifact@v4`は旧Node runtime世代を利用し、runner側のruntime移行警告や将来の非互換要因になっていた。アプリやpackage処理ではなく、workflow action versionが原因だった。

## 対処

- `actions/checkout@v4`を`actions/checkout@v7`へ更新した。
- `actions/upload-artifact@v4`を`actions/upload-artifact@v7`へ更新した。
- build、package、release処理そのものは変更せず、runtime移行だけを分離した。

## 検証・結果

GitHub Actions run [36128958180](https://github.com/nmt3325/LectureScan/actions/runs/36128958180)が成功し、checkout、unsigned build、artifact upload、nightly Release更新が維持された。

## 残る問題・制約

Actionのmajor version更新はGitHub側の提供状況に依存する。今後もdeprecated runtime警告を監視し、workflow全体を再実行して互換性を確認する必要がある。

## 主な変更ファイル

- `.github/workflows/unsigned-ipa.yml` — checkout/upload-artifactのversion更新
