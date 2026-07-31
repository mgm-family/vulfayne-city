# ox_inventory アイテム画像（オーパーツ図鑑）

- `vay_zukan_oopart.png` — 実際に使う画像（300x450、軽量化済み・約100KB）。**これを `ox_inventory` の `web/images/items/vay_zukan_oopart.png` としてコピーしてください。** ox_inventory はアイテムキー名と同じファイル名の画像を自動で拾うので、`data/items.lua` 側に `image = ...` を追記する必要はありません。
- `source_fullres.png` — 元の高解像度版（1024x1536）。将来ポスターや別用途で使う場合はこちらを使ってください。

## 配置手順

1. `vay_zukan_oopart.png` を `resources/ox_inventory/web/images/items/` にコピー
2. ox_inventory（または対象キャラのインベントリ）を開き直せば反映されます
