# Add commit-scoped development journal

| 項目 | 内容 |
|---|---|
| Commit | この書記とdocsを含むコミット（作成時点ではSHA未確定） |
| 日時 | 2026-09-25 |
| 種別 | docs |
| 状態 | 完了 |

## 要約

変更の背景、原因、対処、検証、結果、未解決事項をGit履歴だけに依存せず残すため、`docs/development-journal/`を新設した。既存8コミットを遡及記録し、以後は人が作成する変更コミットごとに書記を同梱するルールをREADMEとdocsへ明記した。

## 問題点

従来はcommit message、差分、会話履歴に情報が分散していた。差分から実装内容は復元できても、失敗例、根本原因、採用しなかった案、検証環境、実機未確認事項を後から正確に判断しにくかった。

## 原因

リポジトリにdocs directory、書記template、commit前checklist、履歴indexがなく、変更完了条件に文書更新が含まれていなかった。

## 対処・実装

- `docs/README.md`を文書入口として追加した。
- `docs/development-journal/README.md`へ必須ルール、commit前checklist、履歴indexを追加した。
- 再利用可能な`TEMPLATE.md`を追加した。
- 既存8コミットについて、問題、原因、対処、検証、結果、制約をGit差分と確認済み実行結果から遡及記録した。
- root `README.md`へ「開発書記（必須）」節を追加し、書記がない変更を完了扱いにしない方針を明記した。
- 最新のhybrid矩形検出に合わせ、READMEの機能説明と構成一覧も更新した。

## 検証

- 全Markdown linkの相対参照先が存在することをscriptで検査する。
- `git diff --check`を実行する。
- docsのみの変更だが、push時に起動するUnsigned IPA workflowが成功することを確認する。

## 結果

各commitの意図と検証範囲をリポジトリ内だけで追跡できる構造になった。今後の変更者は同じcommitに書記を含めることで、コードと判断根拠のずれを防げる。

## 残る問題・制約

- 過去コミットの書記は当時同時に書かれたものではなく、Git差分と残存する検証証拠からの遡及記録である。
- 現時点では書記の存在をCIで強制していない。運用漏れが起きる場合はcommit/PR checkの追加を検討する。

## 主な変更ファイル

- `docs/README.md` — 文書index
- `docs/development-journal/README.md` — 運用規則と履歴index
- `docs/development-journal/TEMPLATE.md` — 書記template
- `docs/development-journal/*.md` — commit単位の記録
- `README.md` — 今後の必須運用
