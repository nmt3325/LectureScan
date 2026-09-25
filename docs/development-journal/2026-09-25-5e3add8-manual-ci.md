# Make macOS CI manually dispatchable

| 項目 | 内容 |
|---|---|
| Commit | `5e3add85912729cf131edd9bd16b72ead31ff48e` |
| 日時 | 2026-09-25 08:58 UTC |
| 種別 | ci |
| 状態 | 完了 |

## 要約

macOS build workflowの自動実行を停止し、`workflow_dispatch`による手動実行へ変更した。

## 問題点と原因

private repositoryのmacOS hosted runnerは課金時間を消費する。workflowが`push`と`pull_request`の両方で起動する設定だったため、軽微な変更でも意図せず課金対象のjobが実行される構造だった。

## 対処

`.github/workflows/build.yml`のtriggerを`workflow_dispatch`だけに変更し、Actions spending limitを設定してから手動実行する旨をコメントで明示した。

## 検証・結果

YAML差分で自動triggerが除去され、UIまたはAPIから明示的に起動した場合だけ実行される構成になった。履歴からの遡及記録であり、この過去スナップショットでworkflowを再実行してはいない。

## 残る問題・制約

自動CIによる即時フィードバックは失われる。費用管理と回帰検知のどちらを優先するかは、リポジトリ公開状態とActions予算に応じて再評価が必要である。

## 主な変更ファイル

- `.github/workflows/build.yml` — triggerを手動実行へ限定
