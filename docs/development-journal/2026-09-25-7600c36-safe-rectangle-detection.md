# Improve safe rectangle detection and tracking

| 項目 | 内容 |
|---|---|
| Commit | `7600c36f81305467814f68200ed9c8182a278afd` |
| 日時 | 2026-09-25 12:58 UTC |
| 種別 | fix / feature / test |
| 状態 | 合成fixtureと記録済み候補で完了、実機検証は未完了 |

## 要約

矩形検出を「Visionの上位候補をそのまま採用する方式」から、Document Segmentation、複数Rectangle候補、幾何検証、検出器間consensus、時間方向priorを組み合わせる方式へ変更した。確信できない場合は誤った自動cropを行わず、元画像全体を保存する安全側の設計にした。

## 問題点

合成した9ケースで旧top-1選択を評価すると、平均IoUは0.724、平均corner errorは0.103、IoU 0.80以上は7/9だった。特に次の失敗があった。

- `paper_small_distant`: 正解はRectangle候補の5番目（面積約0.04、IoU 0.967）だが、大きな窓候補を選択した。
- `paper_with_larger_distractor`: 正解は2番目（IoU 0.940）だが、左側の大きな別対象を選択した。
- Document Segmentation単独では紙・projectorに強い一方、`blackboard_wide`で画像境界3辺に張り付くfull-frame近似をconfidence 0.99で返した。
- live処理では古い非同期結果が新しいZoom・回転・session状態へ混入し、overlayや撮影priorを汚染し得た。
- 異なる対象間まで平滑化すると、枠が対象間を滑って移動し、一時的にどちらでもないcropを作る危険があった。

## 原因

Rectangle detector内のoracle（各候補から正解に最も近いものを選ぶ評価）は平均IoU 0.947、9/9でIoU 0.80以上だった。したがって主因は候補生成不足ではなく、面積やVision順位に偏った**候補選択**だった。

また、`VNObservation.confidence`は常に候補の正しさを比較できる値ではなく、Document Segmentationも学習対象に似た画面境界を文書とみなす場合がある。live側は「連続miss回数と単一EMA」だけで、対象identity、detector mode、geometry generationを表現していなかった。

## 調査と設計判断

- Appleの`VNDetectDocumentSegmentationRequest`は1文書の検出に強く、`VNDetectRectanglesRequest`は複数候補を返せるため、相互補完するhybridを採用した。
- warm計測ではdocument約44.1ms、rectangle約20.5ms、同一handlerでのdual約58.8ms、別handler順次約72.7msだった。そのため常時dualではなく状態に応じてrequestを切り替えた。
- `VNTrackRectangleRequest`は初期誤選択への固着、drift、周期的再検出とlifecycle管理が必要なため見送った。
- rectangle request parameter自体は変更せず、selector改善の効果と混同しないようにした。

## 対処・実装

### 候補生成と検証

- `DocumentProcessor.detectCandidates`でDocument Segmentationと最大6件のRectangle候補を同一`VNImageRequestHandler.perform`へ投入した。
- finite、bounds、convex、自交差、面積、最短辺、角度を検証した。
- 面積0.65以上、画像境界3辺以上、frame corner RMS 0.18以下をfull-frame hallucination riskとして扱った。

### 候補解決

`RectangleResolver`は次の順に選択する。

1. 有効なlive priorと同じ対象
2. documentとrectangleのcross-detector consensus
3. rectangle候補がない場合の高confidence document
4. 十分なscoreとmarginがある保守的rectangle acquisition
5. それ以外はabstain

credibleなdocumentとrectangleが不一致の場合、独立rectangle acquisitionを禁止して`detectorDisagreement`とした。priorは候補rankingにだけ使い、priorそのものをcropとして返さない。

### live trackerと競合対策

- `coldStart`、`documentLocked`、`rectangleLocked`、`ambiguous`、`lost`の5状態を導入した。
- acquisition、対象切替、detector mode切替は2 processed-frameの確認を必須にした。
- 同じ対象だけEMAを適用し、対象切替時は補間しない。
- document lock中はdocument request、rectangle lock中はrectangle requestを基本とし、600msごとにdual probeを実行した。
- `GenerationScopedLiveRectangleTracker`を追加し、Zoom、回転、source size、session変更前のVision完了を内部状態更新前に拒否した。
- UI用の平滑化quadと撮影ranking用のraw trusted candidateを分離した。
- 撮影priorはgeneration、source size、rotation、Zoomが一致し、age 200ms以内の場合だけ利用した。
- detector disagreementが続いた場合はoverlayを期限切れにし、誤った枠を保持し続けないようにした。

### 安全な保存

候補が曖昧、検出器が不一致、geometryが不正の場合は自動cropせず全画像を保存する。iOS 18のphoto経路ではlive priorを使わず、撮影画像自身にdual detectionを実行する。video-frame経路はframeとpriorをatomic snapshotする。

## 検討した代替案

- `VNTrackRectangleRequest`: driftと誤選択固定のriskから延期。
- segmentation maskやedge consistency: 追加精度の可能性はあるが、今回の主因がselectorと判明したため延期。
- thermal状態に応じるadaptive circuit breaker: 実機計測が必要なため延期。
- priorを直接cropに利用: stale geometryによる有害cropを避けるため不採用。

## 検証

- iPhone 17 Pro / iOS 26.5 Simulator: 29 tests、0 failures、`TEST SUCCEEDED`。
- unsigned Release `iphoneos` build: `BUILD SUCCEEDED`。
- `git diff --check`: 成功。
- 9 fixtureを現在のresolverで再評価: 8件選択、1件abstain、harmful auto-crop 0件。
- 選択した8件の平均IoU 0.965、平均corner error 0.009。
- `blackboard_wide`: rectangle fallback、IoU 0.893。
- `paper_with_larger_distractor`: cross-detector consensus、IoU 0.966。
- `paper_small_distant`: detector disagreementとしてabstainし、誤cropを回避。
- GitHub Actions [36138078580](https://github.com/nmt3325/LectureScan/actions/runs/36138078580): unsigned build、IPA検証、Artifact、nightly Release更新が成功。
- [nightly Release](https://github.com/nmt3325/LectureScan/releases/tag/nightly)のtagが当該commitを指すこと、IPAのSHA-256照合が成功することを確認した。

## 結果

| 指標 | 旧方式 | 新方式 |
|---|---:|---:|
| IoU 0.80以上または安全なabstain | 7/9 | 9/9 |
| harmful auto-crop | 2 | 0 |
| 自動選択 | 9 | 8 |
| 安全側へのabstain | 0 | 1 |
| 新方式で選択した8件の平均IoU | — | 0.965 |

この結果は「すべてを無理にcropする」改善ではなく、「高確度の8件をcropし、判断できない1件は元画像を残す」改善である。

## 残る問題・制約

- 合成fixtureと記録済みdevice-capable Vision候補上の結果であり、実講義環境での改善は未確認。
- Simulator上のDocument Segmentationは実行ごとに欠落、zero-confidence full-frame、低品質結果になる場合があり、実Vision経路では主にharmful cropがないことを検証した。
- 実機での90度回転、overlayと保存cropの一致、長時間運用時のthermal影響は未確認。
- Thread Sanitizerで実カメラqueueの競合を再現する試験は未実施。

## 主な変更ファイル

- `LectureScan/RectangleDetection.swift` — validator、IoU、resolver、policy
- `LectureScan/LiveRectangleTracker.swift` — 5状態trackerとgeneration gate
- `LectureScan/DocumentProcessor.swift` — hybrid Vision requestと安全なprocess
- `LectureScan/CameraModel.swift` — live scheduler、prior、geometry同期
- `LectureScanTests/RectangleDetectionTests.swift` — state・selection・fixture regression
- `LectureScanTests/Fixtures/` — 画像、正解四隅、記録済み候補
