# 間取り図 → SketchUp 3Dモデル生成ツール

DXF形式の間取り図(レイヤー構成: `Walls` / `Doors` / `Windows` / `Furniture`)、
または写真・PNG/JPGなどラスター画像の間取り図から、SketchUpで読み込み可能な
3Dモデルを自動生成するためのスクリプト一式。

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
| `image_to_floorplan.py` | 写真/PNG/JPG等の間取り図から壁・扉・窓・家具を検出し、共通JSON(`floorplan.json`)に変換するPythonスクリプト(SketchUp外、事前処理用) |
| `run_from_json.rb` | `floorplan.json`(画像由来、またはDXF由来を変換したもの)を読み込んで3Dモデルを生成するエントリーポイント |

DXF入力には2種類、画像入力には1種類のエントリーポイントを用意している。
DXFの場合は複雑さ(円弧・スプラインの有無など)によって適切な経路が変わり、
画像の場合はレイヤー情報がないため一度Python側でベクトル化(JSON化)してから
SketchUp側で3D化する2段階構成になっている。

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

## 写真・PNG等の画像から生成する場合

DXFと違い、ラスター画像にはレイヤーという概念がないため「壁・扉・窓・家具を
区別する情報」がそもそも存在しない。`image_to_floorplan.py` は画像処理
(線の太さ・長さ・隙間・輪郭形状)から**推定**でこれを補うツールで、DXF経路と
違って100%の精度は前提にしていない。CADから書き出したクリーンな線画PNGでは
実用的な精度が出るが、手書きやスマホ写真(照明ムラ・斜め撮影・歪み)は
誤検出が増える。**必ず検出結果を目視確認・補正してから3D化すること。**

### 1. 実寸スケールを用意する

画像だけでは何pxが何mmかは分からないため、以下のいずれかを必ず指定する。

- 図面上の既知の2点(例: 寸法線の両端)のpx座標と実寸(mm)を指定する
  (`--reference-px x1,y1,x2,y2 --reference-mm <実寸mm>`)
- 1pxあたりのmmが分かっている場合は直接指定する(`--mm-per-px <値>`)

### 2. ベクトル化(Python)

```bash
pip install opencv-python numpy

python3 image_to_floorplan.py plan.png \
    --reference-px 120,80,120,640 --reference-mm 3640 \
    --out floorplan.json

# 照明ムラの多いスマホ写真の場合
python3 image_to_floorplan.py plan_photo.jpg \
    --reference-px 120,80,120,640 --reference-mm 3640 \
    --photo-mode --out floorplan.json
```

実行すると `floorplan.json`(共通データ, 単位mm)と
`floorplan_debug.png`(検出結果を壁=赤・扉=緑丸・窓=青丸・家具=黄/黒の
輪郭で重ね描きした確認用画像)が出力される。**SketchUpで3D化する前に
`floorplan_debug.png` を必ず開いて確認すること。** ずれている壁、
door/windowの取り違え、不要な家具の誤検出などがあれば `floorplan.json`
をテキストエディタで直接編集して補正する(JSON構造は下記参照)。

```json
{
  "unit": "mm",
  "walls": [ { "points": [[x1,y1], [x2,y2]], "thickness_mm": 150 } ],
  "doors": [ { "point": [x, y], "width_mm": 800 } ],
  "windows": [ { "point": [x, y], "width_mm": 1200 } ],
  "furniture": [ { "points": [[x,y], ...], "label": "unknown" } ]
}
```

### 3. 3Dモデル生成(SketchUp)

```ruby
dir = 'C:/path/to/tools/dxf-to-sketchup'
load File.join(dir, 'floorplan_builder.rb')
load File.join(dir, 'run_from_json.rb')
RunFromJson.run('C:/path/to/floorplan.json')
```

壁のunion・開口カット・家具の押し出しはDXF経路と完全に同じロジック
(`floorplan_builder.rb`)を使うため、壁交差部のクリーン化やキッチン等の
除外・レポートも同様に働く。

### 2階建て以上を1つのモデルに重ねる

`RunFromJson.run` は `z_offset_mm:` を指定でき、同じSketchUpモデル内で
フロアごとに複数回呼び出すことで、1階の上に2階を正しい高さで積み上げた
1つの建物モデルを作れる。

```ruby
RunFromJson.run('1F.json', z_offset_mm: 0)
RunFromJson.run('2F.json', z_offset_mm: 2700)
```

★`z_offset_mm`(階高)の目安: 壁高2,400mm(`CONFIG[:wall_height_mm]`)に
床・天井構造分(200〜400mm程度)を足した値。実際の階高寸法が断面図等で
分かっている場合はそちらを優先すること。1階と2階でCONFIGの壁高が異なる
場合は、2階を生成する前に`FloorplanBuilder::CONFIG[:wall_height_mm]`を
書き換えてから呼び出す。

### 画像検出特有の調整ポイント・限界(★コード内コメントにも記載済み)

- `kernel_size`(`image_to_floorplan.py` の `detect_wall_mask`, 既定4px):
  壁線とそれ以外の細線(家具・寸法線)を線の太さで区別するための
  モルフォロジー処理のカーネルサイズ。画像解像度・線の太さに応じて
  調整が必須(大きすぎると壁ごと消え、小さすぎると細線を壁と誤検出する)。
- `--max-bridge-gap-px`(既定200px): 同一直線上の壁の断片を1本に結合する際に
  許容する隙間の上限。扉・窓の開口幅より少し大きい値にする。
- 扉/窓の判定(`classify_opening`)は開口付近に円弧(ドアの開き勝手線)らしい
  輪郭があるかどうかのヒューリスティックで、**誤判定しうる**。生成された
  `floorplan.json` の `doors`/`windows` 配列は必ず目視で見直すこと。
- 家具は輪郭形状から検出するのみで、種類(ソファ/ベッド等)は判別できない。
  `label` は `"unknown"`(単純形状)または `"unknown_complex"`(頂点数が多く
  複雑な形状 = キッチン等の可能性)になる。DXF経路のような
  キーワードベースの高さ推定・自動除外は働かないため、`"unknown_complex"`
  の項目やドアの開き勝手線がノイズとして家具に混入していないかを
  `floorplan_debug.png` で確認し、不要なら `floorplan.json` から
  該当エントリを削除するか、`label` を手動で書き換えて
  `furniture_height_overrides_mm` のキーワードに一致させること。
- `ARC`/曲線で構成された壁(円弧壁)は非対応。直線壁の間取り図を前提とする。

## 実行方法(DXF)

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
- `image_to_floorplan.py` はサンプル画像での検証時、扉の開き勝手線(円弧)
  そのものが小さな「家具」として誤検出されることがあった。
  `floorplan_debug.png` で黒枠の `unknown_complex` 項目が扉付近にある場合は
  ノイズの可能性が高いため、`floorplan.json` から該当エントリを削除すること。
