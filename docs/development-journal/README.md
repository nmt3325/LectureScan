# 開発書記

LectureScanの変更理由と検証証拠を、コミット単位で残すための記録です。過去8コミットはGit履歴と当時の差分から遡及して作成し、以後は変更コミットと同時に書記を追加します。

## 必須ルール

1. **人が作成する変更コミットごとに1件の書記を作る。** 実装、修正、リファクタリング、CI、文書だけの変更も対象です。
2. 書記はその変更と**同じコミット**に含めます。書記のない変更は完了扱いにしません。
3. ファイル名は `YYYY-MM-DD-<short-sha-or-topic>-<slug>.md` とします。コミット作成前でSHAが不明な場合はtopicを使い、本文のCommit欄を「この書記を含むコミット」とします。SHA記入だけのためにamendしてハッシュを変え続ける必要はありません。
4. squashした場合は最終コミットに対応する1件へ統合します。複数コミットを残す場合は、各コミットに別々の書記が必要です。
5. 少なくとも「実施内容」「改善点」「問題」「原因」「対処」「検証」「結果」「残る問題」を記載します。
6. 成功した確認だけでなく、失敗した実験、採用しなかった案、環境依存の制約も記載します。
7. 数値には母集団と条件を添えます。実機未確認なら必ずそう書きます。

## コミット前チェック

- [ ] 対応する書記を新規作成した
- [ ] 問題と原因を分けて説明した
- [ ] 実装・変更ファイルを列挙した
- [ ] 実行したテスト／ビルド／ベンチマークと結果を書いた
- [ ] 未実施の確認と残るリスクを書いた
- [ ] READMEや利用方法に影響する場合は同時に更新した
- [ ] `git diff --check` を通した

## 索引

| 日付 (UTC) | Commit | 主題 | 書記 |
|---|---|---|---|
| 2026-09-25 | `7feaa32` | 初期リリース | [Initial release](2026-09-25-7feaa32-initial-release.md) |
| 2026-09-25 | `5e3add8` | macOS CIの手動化 | [Manual macOS CI](2026-09-25-5e3add8-manual-ci.md) |
| 2026-09-25 | `3c40084` | 未署名IPA Artifact | [Unsigned IPA artifact](2026-09-25-3c40084-unsigned-ipa.md) |
| 2026-09-25 | `7cc098b` | カメラ式Zoom UI | [Zoom controls](2026-09-25-7cc098b-zoom-controls.md) |
| 2026-09-25 | `9669888` | overlay座標と手動crop | [Crop editor](2026-09-25-9669888-crop-editor.md) |
| 2026-09-25 | `b2a25b3` | 撮影ライブラリと自動配布 | [Library and distribution](2026-09-25-b2a25b3-library-distribution.md) |
| 2026-09-25 | `5ce69dc` | Actions Node 24移行 | [Node 24 actions](2026-09-25-5ce69dc-node24-actions.md) |
| 2026-09-25 | `7600c36` | 安全な矩形検出と追跡 | [Safe rectangle detection](2026-09-25-7600c36-safe-rectangle-detection.md) |
| 2026-09-25 | この書記を含むコミット | 書記制度の導入 | [Documentation policy](2026-09-25-documentation-policy.md) |

## 新規作成

[`TEMPLATE.md`](TEMPLATE.md) をコピーし、空欄を埋めてからコミットしてください。
