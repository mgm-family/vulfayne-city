# DXF間取り図 → SketchUp 3Dモデル生成ツール

DXF形式の間取り図(レイヤー構成: `Walls` / `Doors` / `Windows` / `Furniture`)から、
SketchUpで読み込み可能な3Dモデルを自動生成するためのRubyスクリプト一式。

> **注記**: 今回の依頼メッセージには「添付DXFファイル」への言及がありましたが、
> このセッションの作業環境にDXFファイルは見当たりませんでした。そのため、特定の
> 間取りデータに固定した出力ではなく、`Walls/Doors/Windows/Furniture` の
> レイヤー命名規則に従う **任意のDXF** に対して動作する汎用スクリプトとして
> 作成しています。実データで検証したい場合はファイルを共有してください。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `dxf_parser.rb` | 最小限のASCII DXFパーサー(SketchUp API非依存、単体テスト可能) |
| `floorplan_builder.rb` | 壁の立ち上げ・建具開口カット・家具押し出しのコアロジック(SketchUp API使用、入力元非依存) |
| `run_from_dxf.rb` | DXFファイルを直接パースして3Dモデルを生成するエントリーポイント |
| `run_from_native_import.rb` | SketchUp純正のDXFインポート結果を後処理して3Dモデルを生成するエントリーポイント |

2種類のエントリーポイントを用意しているのは、DXFの複雑さ(円弧・スプラインの有無など)
によって適切な経路が変わるため。

## どちらの経路を使うか

- **`run_from_dxf.rb`(直接パース)**: 壁・建具・家具がすべて直線・ポリラインで
  描かれている典型的な間取りDXFに向く。SketchUp Pro/Makeの区別なく動作し、
  ワンステップで完結する。円弧・スプラインには非対応。
- **`run_from_native_import.rb`(純正インポート後処理)**: DXFに円弧やスプライン、
  複雑なブロック定義が含まれる場合に確実。先に SketchUp の `ファイル > インポート`
  でDXFを読み込み(レイヤーはSketchUpの「タグ」として保持される)、その後このスクリプトで
  タグ名を見て壁・建具・家具を分類し、同じビルダーロジック(`floorplan_builder.rb`)に渡す。

いずれの経路でも「壁交差部分をクリーンなジオメトリにする」処理は同じ実装
(`FloorplanBuilder.build_walls`)を使う。壁セグメントごとに矩形ソリッドを作り、
SketchUpのSolid Tools (`union`) で結合することで、T字・十字交差部の内部に
余分な面が残らない単一ソリッドを生成する。

## 実行方法

SketchUpの `ウィンドウ > Ruby コンソール` を開き、以下を入力(パスは環境に合わせて変更):

```ruby
dir = 'C:/path/to/tools/dxf-to-sketchup' # または /path/to/tools/dxf-to-sketchup

# 直接DXFをパースする場合
load File.join(dir, 'dxf_parser.rb')
load File.join(dir, 'floorplan_builder.rb')
load File.join(dir, 'run_from_dxf.rb')
RunFromDxf.run   # ファイル選択ダイアログが開く

# もしくは、純正インポート後に処理する場合
# (事前に ファイル > インポート でDXFを読み込んでおく)
load File.join(dir, 'floorplan_builder.rb')
load File.join(dir, 'run_from_native_import.rb')
RunFromNativeImport.run
```

繰り返し使う場合は、拡張機能(Extension)としてパッケージ化することも可能。

## 前提ルール・レイヤー名の扱い

- レイヤー名は `Walls` / `Doors` / `Windows` / `Furniture` を含む文字列に
  大文字小文字を無視した部分一致でマッチさせている(`run_from_dxf.rb` /
  `run_from_native_import.rb` の `LAYER_MATCHERS`)。角括弧`[ ]`付きの
  レイヤー名(`[Walls]`など)であっても正規表現マッチなのでそのまま動作する。
- 壁の表現方法(中心線1本 vs 内外形状のダブルライン)によって
  `FloorplanBuilder::CONFIG[:wall_representation]` を `:centerline` または
  `:outline` に切り替えること。判別できない場合は `:centerline`(既定)のまま
  実行し、結果を見て必要なら切り替える。

## ★調整が必要になりやすい箇所(コード内コメントにも記載済み)

`floorplan_builder.rb` の `CONFIG` ハッシュにまとめてあります。

- `wall_thickness_mm` (既定150mm): DXFに壁厚情報がない場合のデフォルト値。
  実際の壁厚と異なる場合は要調整。壁ごとに厚みを変えたい場合は、
  DXF側の各壁エンティティに拡張データ(XDATA)として`thickness_mm`を
  持たせるか、`normalize`関数でレイヤー名やハッチパターンから厚みを
  推定するロジックを追加する必要がある(現状は一律デフォルト値)。
- `opening_overrun_mm` (既定50mm): 扉・窓の開口カット用ボリュームを
  壁面から前後にはみ出させる量。斜め壁や壁厚のばらつきでカットが
  貫通しない場合はこの値を増やす。
- `door_default_width_mm` / `window_default_width_mm`: 建具がDXF上で
  幅を持たない点(INSERTブロックの挿入点のみ)で表現されている場合に
  使うデフォルト幅。実際の建具幅と異なる場合は個別に見直すこと。
- `door_height_mm` / `window_sill_height_mm` / `window_head_height_mm`:
  開口の高さ。日本の一般的な住宅基準を仮置きしているため、実際の
  建具仕様に合わせて調整すること。
- `DXF_UNIT_TO_MM`(`run_from_dxf.rb`): DXFの図面単位がmmでない場合は
  ここを変更(メートル単位なら`1000.0`、インチなら`25.4`)。

## 家具生成について

- `furniture_height_overrides_mm` にキーワード(ブロック名・レイヤー名の
  部分一致)ごとの高さテーブルを用意している。一致しない家具は
  `furniture_default_height_mm`(既定750mm)で押し出す。
- **キッチン・複雑形状の除外**: `excluded_furniture_keywords` に一致する
  家具(システムキッチン、シンク、コンロ、冷蔵庫、ユニットバス等)は
  自動生成の対象から除外し、ベースモデルには含めない。
  - `run_from_dxf.rb` は除外・失敗した家具の一覧を
    `<DXFファイル名>_skipped_furniture.txt` に書き出す。
  - `run_from_native_import.rb` はRubyコンソールに一覧を出力する。
  - **提案**: 除外された家具は、(1) SketchUpの3D Warehouseから該当する
    実寸コンポーネントを検索して配置する、(2) メーカーの製品図面や
    実測値をもとに個別に採寸してモデリングする、のいずれかで
    ベースモデルに追加することを推奨する。自動生成は外形図形からの
    単純押し出しに留まるため、天板・扉・配管などのディテールを
    持つ複雑な什器には元々不向き。

## 既知の制限

- `dxf_parser.rb` は `LINE` / `LWPOLYLINE` / `POLYLINE` / `INSERT` / `CIRCLE`
  のみに対応。`ARC` / `SPLINE` / `ELLIPSE` を含む図面は、CAD側で事前に
  直線・ポリラインへ分解(エクスプロード)するか、`run_from_native_import.rb`
  の経路(SketchUp純正インポーターに変換を任せる)を使うこと。
- バイナリDXF(.dxfのバイナリ版)には非対応。ASCII DXFとして書き出すこと。
- `union` / `subtract` などのSolid Tools操作はSketchUpのバージョンや
  ジオメトリの状態によって失敗することがある。失敗時は警告をコンソールに
  出力し、該当ソリッドを未結合のまま残すので、SketchUp付属の
  「ソリッドインスペクター」拡張機能で手動確認・修復することを推奨する。
