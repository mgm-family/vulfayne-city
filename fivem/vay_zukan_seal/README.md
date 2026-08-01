# vay_zukan_seal（FiveM / QBCore / ox_target / ox_inventory）

シール集め専用の独立リソースです（10シート × 1シート10個 = 100種）。オーパーツ・骨董品はそれぞれ `vay_zukan_oopart` / `vay_zukan_antique` という別リソースです。

## 依存リソース

- `qb-core`
- `ox_target`
- `ox_lib`
- `oxmysql`
- `ox_inventory`

## 導入手順

1. このフォルダを `resources/[任意のカテゴリ]/` にコピー
2. `sql/install.sql` をDBに一度だけ流す
3. `ox_inventory` の `data/items.lua` に下記アイテムを追加
4. `server.cfg` に `ensure vay_zukan_seal`（`qb-core` / `ox_target` / `ox_inventory` / `oxmysql` より後）
5. 起動

## 仕組み（他2つとの違い）

シールは**その場で直接登録**されます。アイテムやNPCへの受け渡しは不要です。

- マップに隠れた target（ox_targetのスフィアゾーン）を選択 → その場でサーバーが所持データに登録
- まだ持っていないシールだけ target を登録するので、他プレイヤーからは見えても自分からはもう見えません（`vay_zukan_seal`テーブルに `citizenid` 単位で永続化）
- 1シート（10個）揃うと、シールコレクターNPCに話しかけて景品を受け取れます（デフォルトはQBCoreの銀行口座への入金）

## 図鑑アイテムで開く

`ox_inventory` の `data/items.lua` に以下を追加してください。

```lua
['vay_zukan_seal'] = {
	label = 'シール図鑑',
	weight = 200,
	stack = false,
	close = true,
	description = '集めたシールを記録できる図鑑。青い装丁。',
	client = {
		export = 'vay_zukan_seal.useZukan',
	},
},
```

使用してもアイテムは消費されません。テスト用付与は `/additem [自分のID] vay_zukan_seal 1` など。`F6`（`/vay_zukan_seal`コマンド）も保険で残していますが、こちらもアイテム所持が条件です。不要なら `client/main.lua` の `RegisterCommand('vay_zukan_seal', ...)` と `RegisterKeyMapping(...)` を削除してください。

このアイテムのインベントリ表示画像は `ox_inventory_item_image/vay_zukan_seal.png` に用意済みです。`ox_inventory/web/images/items/vay_zukan_seal.png` としてコピーすれば、ファイル名がアイテムキーと一致しているので自動的に使われます（`data/items.lua` に `image = ...` の追記は不要）。

## UI

図鑑は `html/backgrounds/sheet.jpg`（1376x768、10マス×1シート分のイラスト）を背景に使い、その上にシート名・進捗・アイテム画像をJSで重ねて描画しています。◀▶ボタン（または左右矢印キー）でシートをめくると、ページが横に回転してめくれるようなアニメーションで切り替わります。マスは未登録だと「？」、登録済みになると画像で表示されます。

シール図鑑のテーマカラーは**青**（`#4b6a8a` / 明るい青 `#6f93b6`、Vulfayne City公式サイトの `--blue` トークンと同じ）です。`shared/data.lua` の `Zukan.ThemeColor` / `Zukan.ThemeColorBright` で変更できます（ボタンや縁取りの色に反映されます。背景画像そのものの色は変わりません）。

背景画像の枠位置がずれた場合は `html/script.js` 冒頭の `SLOT_RECTS` / `PLAQUE_RECT`（%指定）を調整してください。

## 隠し場所（target・NPC）の設定

このリポジトリには実際のマップ情報が無いため、座標はこちらで決め打ちできませんでした。`shared/data.lua` の各アイテムの `Coords` と `Zukan.Npc.Coords` は未設定だと暫定の自動配置になります（起動時に警告が出ます）。ゲーム内で `/vay_zukan_seal_getcoord` を実行すると、今いる場所の座標が `vector3(...)`（アイテム用）と `vector4(...)`（NPC用）でチャット・コンソールに出力されるので、それをコピーして `shared/data.lua` の該当アイテム／ `Zukan.Npc.Coords` に貼り付けてください。

## 画像の用意

`html/images/<アイテムID>.png`（例: `Seal_S1_I3.png`）に画像を置くと図鑑に反映されます。未設置でも動作します。

**100枚とも、テーマカラーのバッジにアイテム名を載せただけの自動生成プレースホルダー画像が最初から入っています。** 本物のイラストに差し替えたい場合は、`IMAGE_PROMPTS.md` に100件ぶんの画像生成プロンプト（ChatGPT/DALL-E・Bing Image Creator・Midjourneyなどにそのまま貼り付け可能）をまとめてあるので、生成した画像を同じファイル名で上書きしてください。

## 報酬のカスタマイズ

`server/main.lua` の `vay_zukan_seal:talk` イベント内、`if reward.Kind == 'Money' then ... end` の部分に分岐を追加してください。
