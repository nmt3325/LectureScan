# Prioritize the largest safe rectangle

| 項目 | 内容 |
|---|---|
| Commit | この書記を含むコミット |
| 日時 | 2026-09-25 14:50 UTC |
| 種別 | fix / test / docs |
| 状態 | Simulator・記録済み候補・合成実験で完了、実機検証は未完了 |

## 要約

画面内に複数の矩形があるとき、中央にある小さな候補やVision上位の候補ではなく、幾何的に安全で他候補より明確に大きい矩形を優先するようにした。ただし、画像全体に近い誤検知、大きさが近い複数対象、既存のDocument Segmentation consensusやlive priorは無条件に上書きせず、判断できない場合は従来どおりabstainする。

## 背景・問題点

黒板やプロジェクター画面などの大きな主対象が見えていても、内部の掲示物、窓、机上の紙など、より小さく中央寄りの矩形を選ぶ場合があった。期待動作は「認識できる安全な矩形のうち最大のものを優先する」ことだが、次の安全性は維持する必要があった。

- 画像境界に張り付くfull-frame近似を最大候補として採用しない。
- ほぼ同じ大きさの別対象がある場合は、面積だけで決め打ちしない。
- Document SegmentationとRectangle detectorが一致する対象を、少し大きいだけのdistractorで上書きしない。
- live追跡中の対象切替は1フレームで確定せず、既存の2 processed-frame確認を維持する。
- 判定に確信がない場合は、誤った自動cropより元画像保存を優先する。

## 原因

変更前の`RectangleResolver.acquisitionScore`は、最短辺45%、矩形bounding box内のfill 30%、Vision順位15%、中心性10%で、四角形面積そのものを評価していなかった。最短辺utilityは画像短辺の25%で飽和するため、大きく横長な黒板と、小さく正方形に近い中央候補がどちらも最大値になり得た。その後はVision順位と中心性が小候補を有利にしていた。

また、Document Segmentationとのconsensusや時間方向priorは安全性には有効だが、小候補へ一度lockした後に明確な大候補が現れても、その小候補を先に返す経路になっていた。`VNObservation.confidence`は「実際の矩形らしさ」であり、利用者が意図する主対象の大きさを示す値ではないため、confidenceやVision順序だけでは今回の要件を表現できなかった。

## 調査と設計判断

### Apple Vision

- [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest)は、各種サイズ・方向の矩形を検出する。confidenceは矩形らしさの指標であり、主対象の面積を直接表さない。
- [`maximumObservations`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest/maximumobservations)の既定値は1で、0はunlimitedである。複数候補をアプリ側で比較するため、LectureScanの上限を6から15へ広げた。
- [`minimumSize`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest/minimumsize)の既定値は0.2で、設定値未満の矩形を返さない。遠い紙などを候補生成段階で一律に消さないため、既存の0.16は変更しなかった。

### 他実装

- WeScan系の[`VisionRectangleDetector`](https://github.com/CoderHuiYu/ZLScanX/blob/9357964cb68a81808a79e5bb5f7860a54232fc94/WeScan/Common/VisionRectangleDetector.swift)は`maximumObservations = 15`で複数候補を取得し、[`Array+Utils`](https://github.com/CoderHuiYu/ZLScanX/blob/9357964cb68a81808a79e5bb5f7860a54232fc94/WeScan/Extensions/Array%2BUtils.swift)でperimeter最大の四角形を選ぶ。
- PyImageSearchの[document scanner](https://pyimagesearch.com/2014/09/01/build-kick-ass-mobile-document-scanner-just-5-minutes/)はcontourを面積降順で調べ、最大の4点contourを主対象とする。

これらは「Visionの先頭候補を主対象とみなさず、複数候補へ明示的なサイズ優先を適用する」根拠として参照した。一方、LectureScanでは誤った最大候補を常に採用しないよう、面積だけのhard maxではなく既存の幾何検証・consensus・abstainと組み合わせた。

## 対処・実装

### 最大候補の安全な優先

- hard geometry validation後、frame-like候補を最大面積判定から除外した。still modeではsoft shape riskも除外した。
- IoU・corner association上で同じ対象と判断される重複候補は、面積最大の代表候補へまとめてから比較した。
- distinct target中の最大候補が次点の1.25倍以上なら「明確に最大」と判断する。
- Document Segmentation consensusまたはtracking priorを上書きする場合は、最大候補のnormalized areaが0.14以上、かつ参照対象の1.50倍以上であることも必須にした。
- 大きさが近い候補には最大優先を適用せず、既存のscore marginとabstainを維持した。
- 独立acquisitionでは最大面積の70%以上の候補だけを最終ranking対象にした。

### scoreの変更

acquisition scoreを次の配分へ変更した。

| utility | 変更前 | 変更後 |
|---|---:|---:|
| 最大候補に対する相対面積 | 0% | 35% |
| 絶対面積 | 0% | 25% |
| 最短辺 | 45% | 15% |
| fill | 30% | 10% |
| Vision順位 | 15% | 5% |
| 中心性 | 10% | 10% |

Vision順位utilityは範囲外indexでも0...1にclampするようにした。`VNDetectRectanglesRequest.maximumObservations`は6から15へ変更し、`minimumConfidence`、`minimumSize`、`minimumAspectRatio`など他のrequest parameterは変更していない。

### live動作と安全策

- `.largestAreaPreference`を選択証拠として追加した。
- 小対象へlockした後に明確な大対象が現れても、既存のtrackerが1フレーム目をpending/ambiguousとして旧overlayを保持し、2 processed-frame目で切り替える設計を維持した。
- priorそのものをcropとして返さない設計、full-frame近似の除外、detector disagreement時のabstain、同程度の対象に対するmargin判定を維持した。

## 検討した代替案

- **常に面積最大を採用**: full-frame hallucinationや近い大きさの別対象を誤採用するため不採用。
- **Vision confidenceまたは先頭候補を採用**: confidenceは主対象の大きさではなく矩形らしさであり、今回の失敗原因を解消しないため不採用。
- **`minimumSize`を引き上げて小候補を消す**: 遠い紙など正当な小対象も候補生成段階で失うため不採用。
- **最大候補が出た瞬間にlive lockを切り替える**: 単発ノイズでoverlayが跳ぶため不採用。既存の2フレーム確認を維持した。
- **`maximumObservations = 0`で無制限取得**: 候補数と処理量の上限がなくなるため見送り、他scanner実装でも使われる15件を採用した。

## データ実験

### 候補選択policyのMonte Carlo

`tools/rectangle_selection_benchmark.py --assert-improvement`で、seed 7600、20,000 sceneを生成した。各sceneはnormalized area 0.16〜0.48の主対象1件と、主対象の0.08〜0.95倍の小候補1〜5件からなり、Vision順位、中心位置、aspect、fillを乱数化した。この実験では定義上「最大のvalid rectangle」を正解とし、変更前scoreと面積優先policyを比較した。

| policy | 正解 | 小候補を選択 | abstain |
|---|---:|---:|---:|
| 変更前 | 2,378 / 20,000 (11.89%) | 2,072 (10.36%) | 15,550 |
| 面積優先 | 13,075 / 20,000 (65.38%) | 0 (0.00%) | 6,925 |

これはcandidate-levelの合成policy実験であり、画像からの候補生成、実講義環境、実機カメラを含む精度ではない。65.38%を実画像の認識精度として扱わない。near-tieでは新方式も安全側にabstainする。

### Vision候補上限の小規模計測

macOS上で既存3 fixtureを`maximumObservations` 6 / 12 / 15の各設定で13回実行し、初回を除く12回を集計した。3 fixtureとも返却候補数と候補面積列は全設定で同一だった。

| fixture | max=6 平均 | max=15 平均 |
|---|---:|---:|
| `blackboard_wide` | 12.69 ms | 11.94 ms |
| `paper_small_distant` | 10.28 ms | 10.25 ms |
| `paper_with_larger_distractor` | 15.22 ms | 11.05 ms |

実行順、warm cache、macOS VisionとiOS実機の差があるため、15件設定が高速だとは結論しない。この限定計測では15件化による明確な悪化を観測しなかった、という範囲に留める。

## 検証

- Xcode 26.6 / iPhone 17 Pro / iOS 26.5 Simulatorのfull suite: 35 tests、0 failures、`TEST SUCCEEDED`。
- selector・tracker・記録済み候補のtargeted suite: 24 tests、0 failures、`TEST SUCCEEDED`。
- unsigned Release `iphoneos` clean build: `BUILD SUCCEEDED`。AppIntents未使用によるmetadata extraction skip warningのみ。
- `python3 tools/rectangle_selection_benchmark.py --assert-improvement`: 成功。
- `python3 -m py_compile tools/rectangle_selection_benchmark.py`: 成功。生成した`tools/__pycache__/`は削除した。
- `git diff --check`: 成功。
- Markdown相対リンク検査: 成功。
- 記録済み候補:
  - `blackboard_wide`: 最大の非frame-like Rectangle候補index 0を選択し、ground truth基準を満たした。
  - `paper_small_distant`: 大きい誤候補群が互いに近い大きさのためabstainした。
  - `paper_with_larger_distractor`: 約11%大きいdistractorではなく、Document/Rectangle consensus対象を維持した。
- 実機カメラ、実講義環境、回転、thermal負荷は未検証。

## 結果

中央・Vision上位という理由だけで小矩形が勝つ経路を抑え、明確に最大で安全な矩形を優先できるようになった。同時に、full-frame近似、near-tie、記録済みの小さい遠方紙、大きさが近いdistractorでは既存の安全側動作を維持した。

合成policy実験では小候補選択が2,072/20,000から0/20,000になり、正解定義に合う選択が2,378/20,000から13,075/20,000へ増えた。この数値は実画像精度ではなく、今回変更した候補選択規則が意図どおり面積を優先することの再現可能な検証である。

## 残る問題・制約

- 実機カメラおよび実際の教室での精度改善は未確認。
- iOS実機で`maximumObservations = 15`にした場合のlatency、energy、thermal影響は未計測。
- 合成sceneは主対象を最大矩形と定義しているため、利用者が小さい紙を意図的に撮る状況の品質を表さない。その状況はDocument Segmentation consensus、prior、near-tie safetyで保護する設計だが、実データ追加が必要。
- 90度回転、極端なperspective、反射、部分的な遮蔽、連続的なZoom変更は実機回帰が必要。
- request parameterは候補数以外を固定したため、`minimumSize`やaspect thresholdの最適化は今後の独立課題である。

## 主な変更ファイル

- `LectureScan/RectangleDetection.swift` — 面積tier、最大候補dominance/override、重複target統合、area-aware score。
- `LectureScan/DocumentProcessor.swift` — Rectangle候補上限を6から15へ変更。
- `LectureScanTests/RectangleDetectionTests.swift` — 最大候補、consensus/prior override、near-tie、frame-like、live 2フレーム切替、記録済み候補の回帰テスト。
- `tools/rectangle_selection_benchmark.py` — 変更前後policyの決定論的Monte Carlo実験。
- `README.md` — 最大の安全な矩形を優先する挙動を説明。
- `docs/development-journal/README.md` — 本書記を索引へ追加。
- `docs/development-journal/2026-09-25-largest-rectangle-priority.md` — 調査、設計、実験、検証、制約の記録。
