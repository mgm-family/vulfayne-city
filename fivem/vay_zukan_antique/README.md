# vay_zukan_antique（FiveM / QBCore / ox_target / ox_inventory）

骨董品集め専用の独立リソースです（10シート × 1シート9個 = 90種）。シール・オーパーツはそれぞれ `vay_zukan_seal` / `vay_zukan_oopart` という別リソースです。

## 依存リソース

- `qb-core`
- `ox_target`
- `ox_lib`
- `oxmysql`
- `ox_inventory`

## 導入手順

1. このフォルダを `resources/[任意のカテゴリ]/` にコピー
2. `sql/install.sql` をDBに一度だけ流す
3. `ox_inventory` の `data/items.lua` に下記2つのアイテムを追加
4. `server.cfg` に `ensure vay_zukan_antique`（`qb-core` / `ox_target` / `ox_inventory` / `oxmysql` より後）
5. 起動

## 仕組み（シールとの違い）

骨董品は**アイテムとして手に入れて、専用NPCに渡すことで登録**されます（オーパーツと同じ流れです）。

1. マップに隠れた target（ox_targetのスフィアゾーン）を選択すると、`vay_antique_piece`（未鑑定の骨董品、どの骨董品かはmetadataで区別）を1つ入手します。この時点ではまだ図鑑には登録されません。
2. 骨董品コレクターNPCに話しかける（納品する）と、その時点で持っている `vay_antique_piece` を**まとめて**図鑑に登録し、アイテムは消費されます。同時に、その場でシート（9個）が揃っていれば景品も受け取れます。
3. まだ持っていない、かつ図鑑未登録の骨董品だけ target が出現するので、他プレイヤーからは見えても自分からはもう見えません。

## サーバー再起動での挙動

- `vay_antique_piece` を持ったまま（＝NPCに渡す前）サーバーが再起動すると、そのアイテムは消失し、対応するtargetは再び回収可能になります。**再起動を挟まなければ、再ログインしても持ち続けられます**（通常のox_inventory永続化のまま）。
- 実現方法: このリソース起動のたびに変わる内部の「起動ID」を `SetResourceKvp`/`GetResourceKvpString`（citizenidごと）で記録し、あるプレイヤーが新しい起動IDのもとで初めてログインした瞬間に、その時点で持っている `vay_antique_piece` を全て回収（削除）します。DBのスキーマを直接触るような危険な処理はしていません。
- 注意点: この掃除処理は「プレイヤーがログインしてキャラクターを読み込んだ瞬間」に行われます。倉庫やドロップ品として地面・トランクなどに置かれたままの `vay_antique_piece` までは掃除しません（対象は各プレイヤーの手持ちインベントリのみ）。

## 図鑑アイテムで開く／未鑑定骨董品の登録

`ox_inventory` の `data/items.lua` に以下2つを追加してください。

```lua
['vay_zukan_antique'] = {
	label = '骨董品図鑑',
	weight = 200,
	stack = false,
	close = true,
	description = '集めた骨董品を記録できる図鑑。金の装丁。',
	client = {
		export = 'vay_zukan_antique.useZukan',
	},
},

['vay_antique_piece'] = {
	label = '未鑑定の骨董品',
	weight = 100,
	stack = false,
	close = false,
	description = 'コレクターNPCに渡すと図鑑に登録できる。',
},
```

`vay_zukan_antique`（図鑑本体）は使用してもアイテムは消費されません。`vay_antique_piece`（未鑑定品）はNPCへの納品時にサーバー側で自動的に削除されます。テスト用に図鑑アイテムを渡すには `/additem [自分のID] vay_zukan_antique 1` など。`F8`（`/vay_zukan_antique`コマンド）も保険で残していますが、こちらも `vay_zukan_antique` 所持が条件です。不要なら `client/main.lua` の `RegisterCommand('vay_zukan_antique', ...)` と `RegisterKeyMapping(...)` を削除してください。

## UIカラー

骨董品図鑑のテーマカラーは**金**（`#c9a227` / 明るい金 `#e6c352`、Vulfayne City公式サイトの `--gold` トークンと同じ）です。`shared/data.lua` の `Zukan.ThemeColor` / `Zukan.ThemeColorBright` で変更できます。シートの各マスは、未登録だと薄いシルエット＋「？」、登録済みになると画像＋テーマカラーの縁取りで表示されます。

## 隠し場所（target・NPC）の設定

このリポジトリには実際のマップ情報が無いため、座標はこちらで決め打ちできませんでした。`shared/data.lua` の各アイテムの `Coords` と `Zukan.Npc.Coords` は未設定だと暫定の自動配置になります（起動時に警告が出ます）。ゲーム内で `/vay_zukan_antique_getcoord` を実行すると、今いる場所の座標が `vector3(...)`（アイテム用）と `vector4(...)`（NPC用）でチャット・コンソールに出力されるので、それをコピーして `shared/data.lua` の該当アイテム／ `Zukan.Npc.Coords` に貼り付けてください。

## 画像の用意

`html/images/<アイテムID>.png`（例: `Antique_S1_I3.png`）に画像を置くと図鑑に反映されます。未設置でも動作します。

## 報酬のカスタマイズ

`server/main.lua` の `vay_zukan_antique:talk` イベント内、`if reward.Kind == 'Money' then ... end` の部分に分岐を追加してください。
