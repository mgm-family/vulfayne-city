# vay_zukan_oopart（FiveM / QBCore / ox_target / ox_inventory）

オーパーツ集め専用の独立リソースです（10シート × 1シート9個 = 90種）。シール・骨董品はそれぞれ `vay_zukan_seal` / `vay_zukan_antique` という別リソースです。

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
4. `server.cfg` に `ensure vay_zukan_oopart`（`qb-core` / `ox_target` / `ox_inventory` / `oxmysql` より後）
5. 起動

## 仕組み（シールとの違い）

オーパーツは**アイテムとして手に入れて、専用NPCに渡すことで登録**されます。

1. マップに隠れた target（ox_targetのスフィアゾーン）を選択すると、`vay_oopart_relic`（未鑑定のオーパーツ、どのオーパーツかはmetadataで区別）を1つ入手します。この時点ではまだ図鑑には登録されません。
2. オーパーツコレクターNPCに話しかける（納品する）と、その時点で持っている `vay_oopart_relic` を**まとめて**図鑑に登録し、アイテムは消費されます。同時に、その場でシート（9個）が揃っていれば景品も受け取れます。
3. まだ持っていない、かつ図鑑未登録のオーパーツだけ target が出現するので、他プレイヤーからは見えても自分からはもう見えません。

## サーバー再起動での挙動

- `vay_oopart_relic` を持ったまま（＝NPCに渡す前）サーバーが再起動すると、そのアイテムは消失し、対応するtargetは再び回収可能になります。**再起動を挟まなければ、再ログインしても持ち続けられます**（通常のox_inventory永続化のまま）。
- 実現方法: このリソース起動のたびに変わる内部の「起動ID」を `SetResourceKvp`/`GetResourceKvpString`（citizenidごと）で記録し、あるプレイヤーが新しい起動IDのもとで初めてログインした瞬間に、その時点で持っている `vay_oopart_relic` を全て回収（削除）します。DBのスキーマを直接触るような危険な処理はしていません。
- 注意点: この掃除処理は「プレイヤーがログインしてキャラクターを読み込んだ瞬間」に行われます。倉庫やドロップ品として地面・トランクなどに置かれたままの `vay_oopart_relic` までは掃除しません（対象は各プレイヤーの手持ちインベントリのみ）。

## 図鑑アイテムで開く／未鑑定オーパーツの登録

`ox_inventory` の `data/items.lua` に以下2つを追加してください。

```lua
['vay_zukan_oopart'] = {
	label = 'オーパーツ図鑑',
	weight = 200,
	stack = false,
	close = true,
	description = '集めたオーパーツを記録できる図鑑。赤い装丁。',
	client = {
		export = 'vay_zukan_oopart.useZukan',
	},
},

['vay_oopart_relic'] = {
	label = '未鑑定のオーパーツ',
	weight = 100,
	stack = false,
	close = false,
	description = 'コレクターNPCに渡すと図鑑に登録できる。',
},
```

`vay_zukan_oopart`（図鑑本体）は使用してもアイテムは消費されません。`vay_oopart_relic`（未鑑定品）はNPCへの納品時にサーバー側で自動的に削除されます。テスト用に図鑑アイテムを渡すには `/additem [自分のID] vay_zukan_oopart 1` など。`F7`（`/vay_zukan_oopart`コマンド）も保険で残していますが、こちらも `vay_zukan_oopart` 所持が条件です。不要なら `client/main.lua` の `RegisterCommand('vay_zukan_oopart', ...)` と `RegisterKeyMapping(...)` を削除してください。

## UIカラー

オーパーツ図鑑のテーマカラーは**赤**（`#ad3a2b` / 明るい赤 `#d5543f`、Vulfayne City公式サイトの `--vermillion` トークンと同じ）です。`shared/data.lua` の `Zukan.ThemeColor` / `Zukan.ThemeColorBright` で変更できます。シートの各マスは、未登録だと薄いシルエット＋「？」、登録済みになると画像＋テーマカラーの縁取りで表示されます。

## 隠し場所（target・NPC）の設定

このリポジトリには実際のマップ情報が無いため、座標はこちらで決め打ちできませんでした。`shared/data.lua` の各アイテムの `Coords` と `Zukan.Npc.Coords` は未設定だと暫定の自動配置になります（起動時に警告が出ます）。ゲーム内で `/vay_zukan_oopart_getcoord` を実行すると、今いる場所の座標が `vector3(...)`（アイテム用）と `vector4(...)`（NPC用）でチャット・コンソールに出力されるので、それをコピーして `shared/data.lua` の該当アイテム／ `Zukan.Npc.Coords` に貼り付けてください。

## 画像の用意

`html/images/<アイテムID>.png`（例: `Oopart_S1_I3.png`）に画像を置くと図鑑に反映されます。未設置でも動作します。

## 報酬のカスタマイズ

`server/main.lua` の `vay_zukan_oopart:talk` イベント内、`if reward.Kind == 'Money' then ... end` の部分に分岐を追加してください。
