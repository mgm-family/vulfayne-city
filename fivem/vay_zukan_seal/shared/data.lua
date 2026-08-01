-- shared/data.lua
-- シール集め: 10 sheets x 9 items. Registration happens directly at the
-- target (no item, no NPC hand-in) -- the NPC here only hands out the
-- per-sheet completion reward. `Coords` is left unset on purpose; see
-- README.md / /vay_zukan_seal_getcoord. Drop matching images at
-- html/images/<ItemId>.png for the album UI.

Zukan = {}
Zukan.CategoryId = 'Seal'
Zukan.CategoryName = 'シール'
Zukan.ThemeColor = '#4b6a8a'      -- --blue on the Vulfayne City site
Zukan.ThemeColorBright = '#6f93b6' -- --blue-bright
Zukan.ZukanItem = 'vay_zukan_seal'

local function I(name, desc)
	return { Name = name, Description = desc }
end

local function S(name, amount, rewardName, rewardDesc, items)
	return {
		Name = name,
		Reward = { Kind = 'Money', Account = 'bank', Amount = amount, DisplayName = rewardName, Description = rewardDesc },
		Items = items,
	}
end

Zukan.Sheets = {
	S('PD（警察）記章シール', 300000, 'PD特別記章「盾の誉れ」', 'PD本部長からVulfayne市民の模範として贈られる名誉の盾章。', {
		I('巡査シール', '新人巡査に配られる基本記章。'),
		I('巡査部長シール', '現場を束ねる巡査部長の証。'),
		I('警部補シール', '捜査指揮を任される警部補の記章。'),
		I('警部シール', 'ライオット運用が許可される警部の証。'),
		I('警視シール', 'PD上層部、警視の記章。'),
		I('PDパトカー記章', '白黒に塗られた警邏車両のエンブレム。'),
		I('PDヘリコプター記章', '上空から街を見守るPDヘリの意匠。'),
		I('PD特殊部隊記章', '重大事件にのみ出動する特殊部隊の紋章。'),
		I('PD創設記念シール', 'Vulfayne市警察創設を記念した限定デザイン。'),
		I('PD訓練生シール', '警察学校で訓練中の訓練生に配られる記章。'),
	}),

	S('EMS（救急隊）記章シール', 400000, 'EMS特別記章「命の灯火」', '現場と病院、双方で功績を認められた救急隊員のみに贈られる記章。', {
		I('救急隊員シール', '白い制服を象徴するEMS基本記章。'),
		I('主任救命士シール', '現場指揮を担う主任救命士の証。'),
		I('救急車記章', '赤色灯とサイレンをかたどった意匠。'),
		I('救急ヘリ記章', '遠方の現場へ急行するEMSヘリの紋章。'),
		I('病院連携記章', '院内治療チームとの連携功労を示す記章。'),
		I('蘇生功労記章', '現場蘇生に成功した隊員へ贈られる記章。'),
		I('夜間救助記章', '深夜の救助活動に従事した証。'),
		I('現場対応記章', '犯罪シーンでの人命救助に携わった記章。'),
		I('EMS創設記念シール', '救急隊発足を記念した限定デザイン。'),
		I('EMS研修生シール', '救急救命士を目指す研修生に配られる記章。'),
	}),

	S('白メカニック 記章シール', 500000, 'メカニック特別記章「熟練の証」', '熟練整備士のみが受け取れる、店舗運営を許された証。', {
		I('見習い整備士シール', '工具を握り始めたばかりの見習いの証。'),
		I('整備士シール', '基本整備を任される整備士の記章。'),
		I('熟練整備士シール', '個人店設立資格を持つ熟練整備士の証。'),
		I('塗装師シール', '外装カスタムを手掛ける塗装師の紋章。'),
		I('性能チューナーシール', '性能カスタムを請け負う職人の証。'),
		I('出張修理シール', 'ファーム先まで駆けつける出張修理の記章。'),
		I('開店祝いシール（メカニック）', '新規メカニック店舗の開店を祝う限定デザイン。'),
		I('歪み対応シール', '無償対応が許された歪み修理専門の記章。'),
		I('白メカニック創設記念シール', '直営メカニック創設を記念した限定デザイン。'),
		I('板金職人シール', '凹んだ車体を元通りに直す板金職人の証。'),
	}),

	S('ディーラー 記章シール', 600000, 'ディーラー特別記章「一台の縁」', '大口の商談を成立させたディーラーに贈られる記章。', {
		I('高級車ディーラーシール', '高級車展示場の看板記章。'),
		I('ヘリディーラーシール', '空の移動手段を扱う証。'),
		I('普通車ディーラーシール', '市民の足を支える普通車販売の記章。'),
		I('ボートディーラーシール', '水上の移動手段を扱う証。'),
		I('試乗会記念シール', '限定試乗イベントの記念デザイン。'),
		I('納車式シール', '納車セレモニーで配られる記章。'),
		I('限定モデル記念シール', '数量限定モデル発表を記念した意匠。'),
		I('商談成立シール', '大口商談成立を祝う記章。'),
		I('ディーラー創設記念シール', '街のディーラー事業発足を記念したデザイン。'),
		I('バイクディーラーシール', '二輪車を専門に扱うディーラーの証。'),
	}),

	S('飲食店 記章シール', 800000, 'フードショップ特別記章「満腹の証」', '看板メニューの開発に貢献した店員に贈られる記章。', {
		I('看板メニューシール', '行列のできる看板メニューの意匠。'),
		I('開店祝いシール（飲食店）', '飲食店①の開店を祝う限定デザイン。'),
		I('常連客シール（飲食店）', '毎日通う常連客に配られる記章。'),
		I('空腹回復シール', '空腹を満たす人気商品の証。'),
		I('水分補給シール', '水分補給メニューをかたどった意匠。'),
		I('出張販売シール', '屋台形式の出張販売を記念した記章。'),
		I('季節限定シール', '季節ごとに変わる限定メニューの証。'),
		I('深夜営業シール（飲食店）', '夜通し営業する店舗の記章。'),
		I('フードショップ創設記念シール', '飲食店①創業を記念した限定デザイン。'),
		I('厨房スタッフシール', '笑顔で腕を振るう厨房スタッフの証。'),
	}),

	S('ジョイントショップ 記章シール', 1000000, 'ジョイントショップ特別記章「安らぎの証」', 'ストレス回復の名店として名高い店に贈られる特別な記章。', {
		I('くつろぎ空間シール', '落ち着いた内装をかたどった意匠。'),
		I('ストレス回復シール', '看板商品であるリラックスメニューの証。'),
		I('隠れ家シール', '知る人ぞ知る隠れ家的な店構えの記章。'),
		I('音楽演出シール', '店内BGMをテーマにした限定デザイン。'),
		I('深夜営業シール（ジョイント）', '夜遅くまで営業する店舗の証。'),
		I('限定メニューシール（ジョイント）', '月替わりの限定メニューをかたどった意匠。'),
		I('常連客シール（ジョイント）', '常連客だけに配られる特別な記章。'),
		I('開店祝いシール（ジョイント）', 'ジョイントショップ開店を祝う限定デザイン。'),
		I('ジョイントショップ創設記念シール', 'ストレス回復店創業を記念したデザイン。'),
		I('接客スタッフシール（ジョイント）', '客をもてなす接客スタッフの証。'),
	}),

	S('闇医者・闇メカニック 記章シール', 1200000, '裏社会特別記章「影の信頼」', '表には出せない裏稼業で信頼を勝ち得た者だけの記章。', {
		I('闇医者シール', '非合法治療を請け負う闇医者の証。'),
		I('裏取引記章', '闇市場での取引成立を示す記章。'),
		I('闇メカニックシール', '違法改造を請け負う闇メカニックの証。'),
		I('隠し工房記章', '人目を避けた作業場をかたどった意匠。'),
		I('応急処置記章', '現場での応急手当を行った証。'),
		I('裏路地記章', '裏路地での密会を象徴する記章。'),
		I('信頼の証シール', '裏社会で信頼を得た者に渡される記章。'),
		I('深夜対応シール（裏稼業）', '深夜のみ稼働する裏稼業の証。'),
		I('闇稼業創設記念シール', '裏社会サービス発足を記念した限定デザイン。'),
		I('闇の運び屋シール', '裏稼業の品を密かに運ぶ運び屋の証。'),
	}),

	S('ギャング 記章シール', 1500000, 'ギャング特別記章「縄張りの誉れ」', '組織内での功績が認められた幹部にのみ贈られる記章。', {
		I('下っ端シール', '組織に加入したばかりの証。'),
		I('幹部候補シール', '組織内で頭角を現し始めた者の記章。'),
		I('アンダーボスシール', '組織の中枢を担う地位を示す記章。'),
		I('ボスシール', '組織の頂点に立つ者だけの記章。'),
		I('縄張り記章', '組織の縄張りを象徴する紋章。'),
		I('抗争勝利シール', '抗争を制した際に配られる記章。'),
		I('密輸記章', '密輸ルート開拓の功績を示す証。'),
		I('潜伏記章', '潜伏生活を耐え抜いた者の証。'),
		I('ギャング創設記念シール', '組織設立を記念した限定デザイン。'),
		I('見張り役シール', '縄張りを見張る見張り役の証。'),
	}),

	S('月詠一族 記章シール', 2000000, '月詠特別記章「見えざる盾」', '表舞台には出ない月詠一族が、密かに認めた者へ贈る記章。', {
		I('月詠見習いシール', '一族の末端に連なる者の証。'),
		I('夜路地シール', '夜の裏路地を行き来する者の記章。'),
		I('行政協力記章', '表向き行政に協力する月詠の証。'),
		I('治安協力記章', '治安維持に協力した月詠の記章。'),
		I('満月の夜記章', '満月の夜だけ現れる意匠。'),
		I('影の書記章', '誰も読めない書物をかたどった記章。'),
		I('善き守り手記章', '表の顔である守り手の証。'),
		I('理を書き換える記章', '街の理を密かに動かす者の証。'),
		I('月詠一族創設記念シール', '月詠一族の由来を伝える限定デザイン。'),
		I('月詠の使者シール', '一族の意を伝える使者の証。'),
	}),

	S('街のシンボル 記章シール', 3000000, 'Vulfayne特別記章「双つの月」', '街そのものを象徴する、最も希少な記念記章。', {
		I('双つの月シール', '街の空に浮かぶ、割れた月をかたどった意匠。'),
		I('Vulfayne市章シール', '街の正式な紋章をかたどったシール。'),
		I('招待制記念シール', '招待制ロールプレイシティ開設を記念したデザイン。'),
		I('街開設記念シール', 'Vulfayne City開設初日を記念した限定デザイン。'),
		I('真神一族シール', '光を司る真神一族を象徴する意匠。'),
		I('黒影一族シール', '影を操る黒影一族を象徴する意匠。'),
		I('四英雄シール', '牙琉・叶月・隼士・ムノウをかたどった記章。'),
		I('月割れの夜シール', '千年前、月が割れた夜を描いた意匠。'),
		I('Vulfayne City周年記念シール', '街の周年を祝う、最も希少な記章。'),
		I('月詠一族シール', '表と裏、両方を見守る月詠一族を象徴する意匠。'),
	}),
}

-- Npc = { Coords = vector4(x, y, z, heading), Model = 'a_m_y_business_01' },
-- ^ uncomment and fill in once you've picked a spot for the reward NPC.

--------------------------------------------------------------------------
-- finalize: stamp Id/SheetIndex/ItemIndex, fill in a fallback Coords for
-- anything left unset. IMPORTANT: unlike a flat Roblox baseplate, GTA's
-- map has real buildings and terrain height, so this fallback can't
-- reliably avoid placing an item inside a wall or underground -- it only
-- exists so the resource is testable out of the box. Give every item a
-- real Coords before going live (stand at the spot in-game and run
-- /vay_zukan_seal_getcoord, see client/main.lua).
--------------------------------------------------------------------------

local REGION_CENTER = vector3(0.0, 0.0, 30.0)
local REGION_RADIUS = 400.0

local function hashString(str)
	local hash = 0
	for i = 1, #str do
		hash = (hash * 31 + string.byte(str, i)) % 2147483647
	end
	return hash
end

local function fallbackCoords(itemId)
	local rng = hashString(itemId)
	local angle = (rng % 3600) / 3600.0 * (2 * math.pi)
	local distance = REGION_RADIUS * (0.1 + ((rng // 7) % 1000) / 1000.0 * 0.9)
	local height = 2.0 + ((rng // 13) % 400) / 10.0
	return vector3(
		REGION_CENTER.x + math.cos(angle) * distance,
		REGION_CENTER.y + math.sin(angle) * distance,
		REGION_CENTER.z + height
	)
end

Zukan.ItemsById = {}
local unplaced = 0
for sheetIndex, sheet in ipairs(Zukan.Sheets) do
	for itemIndex, item in ipairs(sheet.Items) do
		item.Id = ('%s_S%d_I%d'):format(Zukan.CategoryId, sheetIndex, itemIndex)
		item.SheetIndex = sheetIndex
		item.ItemIndex = itemIndex
		if not item.Coords then
			item.Coords = fallbackCoords(item.Id)
			unplaced += 1
		end
		Zukan.ItemsById[item.Id] = item
	end
end
if unplaced > 0 then
	print(('^3[%s] %d/%d items still use a temporary fallback position. Place real Coords before launch (see README).^0')
		:format(Zukan.CategoryId, unplaced, #Zukan.Sheets * 10))
end

Zukan.Npc = Zukan.Npc or {}
Zukan.Npc.Model = Zukan.Npc.Model or 'a_m_y_business_01'
if not Zukan.Npc.Coords then
	Zukan.Npc.Coords = vector4(REGION_CENTER.x, REGION_CENTER.y, REGION_CENTER.z, 0.0)
	print(('^3[%s] NPC has no real Coords yet, using a temporary fallback. Set Zukan.Npc.Coords in shared/data.lua before launch.^0')
		:format(Zukan.CategoryId))
end
