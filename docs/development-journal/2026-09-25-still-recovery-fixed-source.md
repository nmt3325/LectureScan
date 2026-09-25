# Recover still-image rectangles and publish a fixed AltStore source

| 項目 | 内容 |
|---|---|
| Commit | この書記を含むコミット |
| 日時 | 2026-09-25 15:51 UTC |
| 種別 | fix / test / ci / docs |
| 状態 | Simulator・合成fixture・unsigned device buildで完了、添付実画像と実機性能は未検証 |

## 要約

実機撮影した壁掛けカレンダーとホワイトボードで自動矩形が得られず、元画像全体が保存される報告に対し、still撮影時だけApple Visionの矩形検出を複数profile・前処理画像で再実行する回復経路を追加した。Document SegmentationとRectangle detectorが外枠／内側領域を別々に返す場合は、包含関係を証拠として安全な外枠またはDocumentを選べるようにした。

同時に、AltStore sourceを毎回同じRelease asset URLへ上書きする方式を改め、固定URLのJSONが実行固有名のIPAを参照する構成へ変更した。これにより、新しいJSONを取得したのにCDNやクライアントcacheから古いIPAを受け取る経路を避ける。

## 問題

### still画像の自動crop

前コミットでは「Visionが返した候補のうち最大の安全な矩形を優先する」選択規則を改善したが、実機の失敗画像では候補生成そのものが不足する可能性が残っていた。確認対象は次の2種類である。

- 白い壁と紙の境界が弱く、写真部と日付部が別矩形にもなり得る壁掛けカレンダー。
- 木枠、内側の白面、紐、磁石、ペン、背景棚を含み、外枠と内側面が入れ子になるホワイトボード。

矩形を安全に確定できないとresolverは意図どおりabstainし、その結果として保存画像は元画像全体になる。誤cropを避ける安全策自体は必要だが、今回の対象では回復できる候補と関係性を増やす必要があった。

### AltStore source

`nightly/altstore-source.json`と`nightly/LectureScan-unsigned.ipa`を同じ名前で上書きしていた。JSONとIPAは別々にcacheされるため、更新後のJSONから同じIPA URLへアクセスしても古いbinaryを取得する可能性があり、利用者が修正版を試したつもりでも旧buildのままになる余地があった。

## 原因

### 確認できた直接原因

- still撮影とlive previewが同じ単一の`VNDetectRectanglesRequest`を使用していた。設定はconfidence 0.55、minimum size 0.16、minimum aspect ratio 0.22、quadrature tolerance 35で、低contrast、遠方、横長の対象を候補生成段階で落とし得た。
- Document SegmentationとRectangle detectorが同一物体の内側／外側や、カレンダーの部分領域を返すと、既存resolverは単純なdetector disagreementとしてabstainし得た。
- 複数passを追加した場合、従来の広い「同一target」判定で候補を統合すると、外枠と内側面まで1候補に潰れる可能性があった。
- AltStore配布では、rolling JSONだけでなくrolling IPAも同じURLだったため、JSONの更新確認だけではbinaryの一意性を保証できなかった。

### 未確認の仮説

添付された2枚をGHA runnerへ完全転送できなかったため、それぞれに対してApple Visionが実際に返す候補数、confidence、選択証拠は未計測である。カレンダーでは低contrastな外周と内部の写真／日付領域、ホワイトボードでは木枠と内側白面の入れ子が主因と推定したが、実画像上の直接計測結果ではない。

## 実施内容・対処

### still専用の多段候補生成

live previewの負荷と誤検出率を変えず、`.still`の場合だけ次を実行するようにした。

1. 従来のpreview profileを元画像へ適用。
2. balanced profile（20候補、confidence 0.30、minimum size 0.08、aspect 0.12）を適用。
3. recall profile（20候補、confidence 0.10、minimum size 0.03、aspect 0.08）を適用。
4. grayscale、contrast 1.42、unsharp mask radius 2 / intensity 0.75の回復画像へenhanced profileを適用。

still検出画像は、呼び出し側が明示しない場合に最大辺2,048 pxへ制限する。primary requestが成功した後の追加passはfail-softとし、個別の回復pass失敗で撮影処理全体を失敗させない。複数passの候補はIoU 0.88以上、またはnormalized corner distance 0.04以下かつarea ratio 0.80以上の場合だけ同一観測として統合し、入れ子矩形は別候補に残す。

### detector disagreementの包含回復

still resolverへ次の順序を追加した。

- Documentを面積1.08倍以上の安全なRectangleが包含する場合、外側Rectangleを選ぶ。
- 高confidence Documentが十分な大きさのRectangle部分領域を包含する場合、その不一致を内部構造として説明し、Documentを選ぶ。
- 包含関係のないDocumentとRectangleは、従来どおりdetector disagreementとしてabstainする。
- live acquisitionにはこの緩和を適用しない。

また、画像の3辺以上へ接する細いstripをsoft shape riskとした。Simulator fixtureでDocument Segmentationが机／壁の帯をconfidence約0.965で返したため、confidenceだけでは採用しない安全策である。

### 固定URLのAltStore source

- 固定source URLを`https://raw.githubusercontent.com/nmt3325/LectureScan/altstore-source/altstore-source.json`とした。
- source専用の`altstore-source` branchへ、`altstore-source.json`だけを含むcommitを`git hash-object` / `git mktree` / `git commit-tree`で作る。
- IPAは`LectureScan-unsigned-<build>-<run-id>.ipa`という実行固有名でもReleaseへuploadし、JSONのapp-levelとversion-levelの両`downloadURL`からそのassetを参照する。
- 実行固有IPAがRelease assetsに存在することを確認してからsource branchを更新する。
- 更新後はcache-busting query付きの固定URLを最大12回取得し、download URL、build number、commit short SHAを検証する。
- 手動取得用のcanonical `LectureScan-unsigned.ipa`とSHA-256、および後方互換用Release assetのJSONは維持する。

## 改善点

- 前回の候補選択改善だけでなく、still画像の候補生成recallそのものを増やした。
- DocumentとRectangleの不一致を一律に拒否せず、包含という明示的な幾何証拠がある場合だけ回復できるようにした。
- 内側面と外枠を重複候補として潰さず、ホワイトボードのような入れ子対象を比較できるようにした。
- live previewは従来の単一profileのままとし、capture時だけ追加計算を行う。
- 固定source JSONから取得するIPA URLをbuildごとに一意にし、rolling assetのcacheによる旧build混入を避けた。

## 失敗した実験・検討した代替案

- **stillなら高confidence Documentを無条件採用**: `blackboard_wide` fixtureで画像下端の細いstripを選び、targeted test 20件中2 integration test・4 assertionが失敗したため不採用。3辺接触stripのsoft riskと、包含証拠によるgatingへ変更した。
- **低thresholdのRectangle候補を追加するだけ**: `paper_small_distant`と`blackboard_wide`で有害な自動cropが再現したため不十分だった。候補追加とresolverの安全条件を同時に変更した。
- **Document/Rectangle不一致時に常にDocumentを優先**: 無関係な対象を選ぶため不採用。包含関係がある場合だけ回復する。
- **広いassociationで複数pass候補を統合**: 外枠と内側面まで同一targetになり得るため不採用。より厳しいduplicate observation判定を分離した。
- **rolling IPA URLを維持してHTTP headerだけでcache回避**: AltStore/SideStore/LiveContainerやCDNの全cache挙動を制御できないため不採用。immutable asset URLへ変更した。
- **添付画像のbase64転送**: tool出力上限で完全復元できず、attachment downloadにもrunnerから使えるtoken付きURLを得られなかった。実画像検証を行ったとは扱わない。

## 検証

### 最終テスト

- 環境: GHA macOS arm64 runner、Xcode 26.6、iPhone 17 Pro / iOS 26.5 Simulator。
- full suite: 42 tests、0 failures、`TEST SUCCEEDED`。
- `RectangleResolverTests` 19件 + `RectangleDetectionIntegrationTests` 4件を3反復: 各23 tests、合計69 test executions、0 failures。
- image-based still integration fixtureの1回のtest case時間は0.085秒、0.093秒、0.348秒だった。これはGHA runner上のSimulator／host Visionでの3 fixtureだけの値であり、iPhone実機latencyではない。
- 初期のunsafe実装では前述の4 assertion failureを確認し、安全条件追加後に解消した。

### buildと配布workflow

- unsigned `iphoneos` Release clean build: `BUILD SUCCEEDED`。
- 検証用build number 999999、version 1.0.0、IPA 643,649 bytes、SHA-256 `42d5c7cec193161ed449d07e41ae2a0234fd63b2eb21647404052f618f42c684`。
- `.app`にcodesign署名、`_CodeSignature`、`embedded.mobileprovision`がないことを確認した。
- workflow YAML parse、全`run` blockの`bash -n`、actionlint 1.7.12に成功した。
- dummy immutable URLを使ったsource generatorで、app/version両download URL、build number、commit descriptionを検証した。
- `hash-object` / `mktree` / `commit-tree`による1ファイルsource commitをローカル構築し、tree内容を照合した。
- `git diff --check`に成功した。

### 未実施

- 添付されたカレンダーJPEGとホワイトボードHEICをApple Visionへ入力する検証。
- iPhone実機での検出成功率、capture latency、energy、thermal測定。
- `main` push後に初めて作られる実`altstore-source` branchと固定raw URLのend-to-end確認。これは同コミットのCI完了後に確認する。

## 結果

既存の合成／記録fixtureでは、still専用の低threshold候補を追加しても有害な自動cropを起こさず、Documentの内部構造と安全な外枠を包含関係から選べるようになった。full suiteと3反復のtargeted suiteはすべて成功し、unsigned device buildも作成できた。

配布workflowは、固定JSONからbuild固有IPAへ到達する設計になった。ただし、この時点ではまだcommit前であり、固定raw URLと新しいnightly assetがGitHub上で公開済みとは記載しない。CI成功後に実assetとJSONの一致を確認する。

## 残る問題・制約

- 最重要: 添付実画像をrunnerへ転送できていないため、報告された2枚で自動cropが成功することは未確認。次の実機試行結果が必要である。
- Simulator／合成fixtureの成功は実機カメラの成功率を示さない。特に反射、blur、露出、HEIC処理、端末世代差は未評価。
- still時は最大4回のRectangle requestを行うため、実機ではcapture後の待ち時間、energy、thermal影響を計測する必要がある。
- safety優先のため、包含証拠がないnear-tieや無関係なdetector disagreementでは今後も元画像保存へabstainする。
- 固定JSON自体にはraw.githubusercontent.com側の短時間cacheが残り得る。JSONが指すIPA URLは一意なので、更新後JSONから旧IPAを取る問題は避けられる。
- 実行固有IPA assetはnightly Releaseへ蓄積する。GitHub Releaseのasset数・容量を監視し、必要なら古いimmutable assetのcleanup policyを別変更で追加する。
- source branch publish後にbranch protectionやtoken権限でpushが拒否される可能性は、実CIでのみ確認できる。

## 主な変更ファイル

- `LectureScan/DocumentProcessor.swift` — still専用のmulti-pass Rectangle検出、2,048 px上限、回復前処理、候補重複除去。
- `LectureScan/RectangleDetection.swift` — request profile、strict duplicate判定、包含判定、still disagreement回復、3辺接触stripの安全策。
- `LectureScanTests/RectangleDetectionTests.swift` — 包含回復、live非緩和、無関係不一致、edge strip、入れ子候補、still integrationの回帰テスト。
- `.github/workflows/unsigned-ipa.yml` — immutable IPA asset、固定source branch、公開順序、公開後検証。
- `README.md` — 固定source URL、再登録手順、immutable IPAとcache設計の説明。
- `docs/development-journal/README.md` — 本書記の索引。
- `docs/development-journal/2026-09-25-still-recovery-fixed-source.md` — 問題、原因、失敗実験、実装、検証、未確認事項の記録。
