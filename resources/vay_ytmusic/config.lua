Config = {}

-- 音楽を再生するコマンド名 (例: /ytmusic https://youtu.be/xxxxx でURLを直接指定 / 引数なしなら入力欄が開きます)
Config.Command = 'ytmusic'

-- 自分が流している音楽を止めるコマンド名 (例: /stopmusic)
Config.StopCommand = 'stopmusic'

-- 音楽が聞こえる半径(メートル)。この数値を変えると聞こえる範囲が変わります (現在: 3.0m)
Config.Radius = 3.0

-- 音量を更新する間隔(ミリ秒)。小さくするほど滑らかに減衰しますが負荷が上がります (現在: 250ms)
Config.UpdateInterval = 250

-- 一番近い時(距離0m)の最大音量。0〜100で指定します (現在: 100)
Config.MaxVolume = 100
