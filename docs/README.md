# LectureScan documentation

このディレクトリは、READMEだけでは扱いきれない設計判断、検証根拠、失敗と未解決事項を保存する場所です。

## 文書一覧

- [開発書記の運用規則と索引](development-journal/README.md)
- [開発書記テンプレート](development-journal/TEMPLATE.md)

## 記録方針

Gitの差分は「何が変わったか」を示しますが、「なぜ変えたか」「何を試して失敗したか」「どこまで確認できたか」までは残しません。そのため、LectureScanでは人が作成するすべての変更コミットに開発書記を同梱します。

記録では、確認済みの事実、推測、未検証事項を分離します。Simulator、合成fixture、記録済みVision候補による結果を、実機・実講義環境での結果として扱ってはいけません。
