# vulfayne-collections（FiveM / QBCore / ox_target）

シール集め・オーパーツ集め・骨董品集めの3種類が同じ仕組み（1種類あたり10シート × 1シート9個 = 90個）を共有する形で実装された FiveM リソースです。QBCore・ox_target・ox_lib・oxmysql を前提にしています。

> 補足: このリポジトリには元々 Roblox 用に作った `roblox/` フォルダもありますが、実際のサーバーは FiveM とのことなので、そちらは無視して構いません（不要であれば削除してもらって大丈夫です）。

## 依存リソース

- `qb-core`（または互換のQBox）
- `ox_target`
- `ox_lib`（`ox_target`の依存でもあるので通常は既に入っています）
- `oxmysql`
- `ox_inventory`（図鑑アイテムの使用トリガーに使用）

`server.cfg` で、これらより後に `ensure vulfayne-collections` してください。

## 導入手順

1. このフォルダ（`vulfayne-collections`）を丸ごと `resources/[任意のカテゴリ]/` にコピー
2. `sql/install.sql` をデータベースに一度だけ流す
3. `ox_inventory` の `data/items.lua` に、下記「図鑑アイテムで開く」の項目を追加
4. `server.cfg` に `ensure vulfayne-collections` を追加（`qb-core` / `ox_target` / `ox_inventory` / `oxmysql` より後）
5. サーバーを起動

これだけで一応動作します（target・NPCの位置は暫定の自動配置、画像は未設定の状態）。実運用前に下記の「隠し場所の設定」と「画像の用意」をしてください。

## 図鑑アイテムで開く

図鑑UIは `vay_zukan` という ox_inventory アイテムを**使用（use）することで開きます**。`vay_ammo_compat.useAmmo` と同じ、ox_inventory のモダンな `client.export` 方式です。`ox_inventory` の `data/items.lua` に以下を追加してください。

```lua
['vay_zukan'] = {
	label = '収集図鑑',
	weight = 200,
	stack = false,
	close = true,
	description = 'シール・オーパーツ・骨董品の収集状況を記録できる図鑑。',
	client = {
		export = 'vulfayne-collections.useZukan',
	},
},
```

- 使用してもアイテムは消費されません（本や手帳のような扱いです。何度でも使えます）。
- テスト用にアイテムを自分に渡すには、管理者権限で `/additem [自分のID] vay_zukan 1` などお使いのアドミンコマンドで付与してください。
- `client/main.lua` には保険として `F6`（`/vulfayne_zukan`）キーバインドも残していますが、こちらも `vay_zukan` を所持していないと開けないようにしてあります（＝図鑑は常にアイテム所持が前提）。キーバインド自体が不要であれば、`client/main.lua` の `RegisterCommand('vulfayne_zukan', ...)` と `RegisterKeyMapping(...)` の2行を削除してください。

## 隠し場所（target・NPC）の設定

このリポジトリには実際のマップの建物配置などの情報が無いため、座標はこちらで決め打ちできませんでした。代わりに以下のようになっています。

- 各アイテム／NPCの座標は `shared/seal_data.lua` / `shared/oopart_data.lua` / `shared/antique_data.lua` の `Coords` フィールド（アイテム）・`Npc = { Coords = ... }`（NPC、シートごとではなくカテゴリごとに1体）で指定します。今は未設定なので、リソース起動時に何個未設定か警告が出ます。
- 未設定のままでも、アイテムIDから決定的に計算される暫定の座標に自動配置されて動作はします（サーバー再起動しても同じ場所）。ただし実際の建物・地形を考慮していないため、壁の中や地下、海の上などに出てしまう可能性が高いです。**本番運用前に必ず実座標を設定してください。**
- 実座標の設定を楽にするため、ゲーム内で `/vulfayne_getcoord` を実行すると、今立っている場所の座標がチャットとコンソールに `vector3(...)`（アイテム用）と `vector4(...)`（NPC用、向きつき）の両方の形式で出力されます。それをコピーして該当アイテムの `Coords = vector3(x, y, z),` として貼り付けてください。

```lua
-- 例: shared/seal_data.lua の該当アイテム
I('巡査シール', '新人巡査に配られる基本記章。'), -- ここを↓に置き換え
{ Name = '巡査シール', Description = '新人巡査に配られる基本記章。', Coords = vector3(441.9, -981.2, 30.7) },
```

（`I(name, desc)` ヘルパーはテーブルを返すだけなので、`Coords` を後から直接テーブルに足しても、`I()` の呼び出し自体を展開して書いても、どちらでも構いません。）

NPCも同様に、各データファイル末尾のコメントアウトされた行を参考にしてください:

```lua
Npc = { Coords = vector4(410.3, -975.8, 30.7, 160.0), Model = 'a_m_y_business_01' },
```

## 画像の用意

`html/images/<アイテムID>.png` に画像を置くと、図鑑UIで取得済みアイテムの画像として表示されます。アイテムIDは `<CategoryId>_S<シート番号>_I<アイテム番号>`（例: `Seal_S1_I3`）です。用意していないアイテムは画像なし（背景色のみ）で表示されます。

## 仕組み

- **収集**: `client/main.lua` が、まだ持っていないアイテムだけ `ox_target` のスフィアゾーンを登録します（`拾う`）。選択すると `server/main.lua` が距離チェックの上で所持データに追加します。
- **1人1回・2回目は見えなくなる**: 所持データは `citizenid` に紐づけて `oxmysql` に保存されます（`vulfayne_collectibles` テーブル）。クライアントは自分が既に持っているアイテムのターゲットゾーンをそもそも登録しないので、他のプレイヤーからは（まだ持っていなければ）引き続き見えますが、自分からは見えません。再ログイン後もサーバーからデータを取得してから登録するので、すぐに反映されます。
- **NPCでの景品受け取り**: 1シート（9個）を集め終えると、対応するNPC（カテゴリごとに1体）に `ox_target` で話しかけることで景品を受け取れます。デフォルトの報酬は `QBCore` の銀行口座への入金です（`Player.Functions.AddMoney('bank', amount, ...)`）。
- **UI**: `vay_zukan` アイテムを使用すると図鑑が開きます（保険の `F6` も同じくアイテム所持が条件）。カテゴリタブ→シートをめくる→3×3のマス目から集めたアイテムを確認でき、マスをクリックすると画像と説明文が拡大表示されます（未取得のものは「？？？」）。

## 報酬のカスタマイズ

デフォルトでは各シートの報酬は `Kind = 'Money'`（QBCoreの銀行口座に加算）です。アイテム付与やバッジなど別の報酬にしたい場合は、`server/main.lua` の `vulfayne_collect:talk` イベント内、`if reward.Kind == 'Money' then ... end` の部分に分岐を追加してください（`reward` には `Kind` / `Account` / `Amount` / `DisplayName` / `Description` が入っています）。

## ファイル構成

```
vulfayne-collections/
  fxmanifest.lua
  sql/install.sql              -- 初回に1度だけ実行するテーブル定義
  shared/
    data_helpers.lua           -- 共通ヘルパー（Id採番・暫定座標の自動計算）
    seal_data.lua               -- シール集め: 10シート x 9個
    oopart_data.lua             -- オーパーツ集め: 10シート x 9個
    antique_data.lua            -- 骨董品集め: 10シート x 9個
  client/main.lua               -- ox_targetゾーン登録、NPC生成、図鑑UIの開閉
  server/main.lua               -- DB読み書き、付与・景品判定
  html/                         -- 図鑑UI（NUI）
    index.html / style.css / script.js
    images/                     -- ここにアイテム画像を置く
```
