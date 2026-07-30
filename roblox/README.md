# コレクション系スクリプト（シール／オーパーツ／骨董品）

Vulfayne City 用の収集要素システム一式。**シール集め**・**オーパーツ集め**・**骨董品集め**の3種類が、同じ仕組み（1種類あたり10シート × 1シート9個 = 90個）を共有する形で実装されています。

このリポジトリには元々ウェブサイト (`index.html`) しか含まれていなかったため、この `roblox/` フォルダは Roblox Studio 側にコピーして使うスクリプト一式として追加しています。フォルダ名がそのまま置き場所（Roblox の Service）に対応しています。

## 導入手順（Rojo を使う場合はそのまま `default.project.json` に組み込み、使わない場合は下記の対応関係で手動コピー）

| このリポジトリのパス | Roblox 側の配置先 |
| --- | --- |
| `roblox/ReplicatedStorage/Collectibles/*` | `ReplicatedStorage.Collectibles`（ModuleScript） |
| `roblox/ServerScriptService/Collectibles/*` | `ServerScriptService.Collectibles` |
| `roblox/StarterPlayer/StarterPlayerScripts/Collectibles/*` | `StarterPlayer.StarterPlayerScripts.Collectibles` |
| `roblox/StarterGui/Collectibles/*` | `StarterGui.Collectibles` |

`CollectionServer.server.lua` と `TargetHider.client.lua` / `CollectionBookUI.client.lua` の拡張子（`.server.lua` / `.client.lua`）はそれぞれ Script / LocalScript を表しています。

## 仕組み

- **データ定義**: `SealData.lua` / `OopartData.lua` / `AntiqueData.lua` が各10シート×9個のアイテム（名前・説明文・画像ID・シート報酬）を定義しています。`Image` は現状ダミー (`rbxassetid://0`) なので、実際の画像アセットIDに差し替えてください。
- **収集**: `CollectionManager.lua` がカテゴリごとにアイテム1個につき1つの「target」（光る球状のPart + ProximityPrompt）をマップ内に自動生成します。プレイヤーが近づいて「拾う」を実行すると、そのプレイヤーだけの所持データに追加されます。
- **1人1回・2回目は見えなくなる**: 所持データはプレイヤーごとに DataStore へ保存されます。`TargetHider.client.lua` が各クライアントで独立して動作し、「自分が既に持っているtarget」だけを透明化・当たり判定オフ・ProximityPrompt無効化します。他のプレイヤーからは（まだ持っていなければ）引き続き見えます。再ログイン後もサーバーからデータを読み込み次第すぐに非表示になります。
- **NPCでの景品受け取り**: 1シート（9個）を集め終えると、対応するNPCに話しかけることで景品を受け取れます。NPCは `Workspace` 内から名前で検索されます（デフォルト: `SealCollectorNPC` / `OopartCollectorNPC` / `AntiqueCollectorNPC`）。Model でも単一の Part でも構いません。見つからない場合はサーバー起動時に `warn` が出ます。
- **UI**: `CollectionBookUI.client.lua` が図鑑UIを生成します（右下の「図鑑 [C]」ボタン、または `C` キーで開閉）。カテゴリタブ→シートをめくる→3×3のマス目から集めたアイテムを確認でき、マスにカーソルを合わせてクリックすると画像と説明文が拡大表示されます（未取得のものは「？？？」表示）。

## マップ内の隠し場所について

このリポジトリには実際のマップ（.rbxlの地形やビル配置）が含まれていないため、targetの座標はこちらで決められませんでした。代わりに以下の2段構えにしています。

1. **手動配置（推奨）**: `Workspace` に `CollectibleMarkers` という Folder を作り、その中にアイテムIDと同じ名前の Part または Attachment を置くと、そこがtargetの出現位置として使われます。アイテムIDは `<CategoryId>_S<シート番号>_I<アイテム番号>` の形式です（例: シール集め・1シート目・3番目のアイテムなら `Seal_S1_I3`）。マーカー自体は非表示にしておいて構いません（座標の参照にしか使いません）。
2. **フォールバック（マーカーが無い場合）**: `CollectionManager.new` に渡す `RegionCenter` / `RegionRadius`（`CollectionServer.server.lua` 内）を中心に、アイテムIDから決定的に計算した円形パターンで自動的にばら撒きます。高さも4〜55stud程度でランダムに変化するので、屋上・裏路地・地下などに紛れているような雰囲気になります。サーバーを再起動しても同じアイテムは同じ位置に出ます。

実際のマップが Studio 側にあるなら、気に入った場所に `CollectibleMarkers` の中身を置いていくだけで、その場所が正式な隠し場所になります。

## 景品（報酬）の中身について

デフォルトでは各シートの報酬は `Kind = "Currency"` で、`leaderstats.Money`（NumberValue）があればそこに加算します。実際の経済システム・アイテム付与・バッジ付与などに差し替えたい場合は、`CollectionServer.server.lua` で `CollectionManager.new(data, { OnGrantReward = function(player, reward, sheetIndex, data) ... end })` を渡してください。`reward` には `DisplayName` / `Description` / `Amount` などシートごとの情報が入っています。

## 注意事項

- DataStore はパブリッシュ済みのゲームでのみ確実に動作します。Studio でテストする場合はゲーム設定で「Studio からのAPIサービスへのアクセスを有効にする」をオンにしてください。
- 3つのシステムは `ReplicatedStorage.CollectibleRemotes` 以下の共通の RemoteEvent/RemoteFunction を共有しています（`Remotes.lua` が自動生成します）。
