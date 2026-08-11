-- src(発信者のサーバーID) -> { videoId = string } の形で、現在再生中の音楽を保持します
local activeRadios = {}

--- YouTubeのURLから動画IDだけを取り出します
--- 対応形式: youtu.be/xxxx, youtube.com/watch?v=xxxx, /embed/xxxx, /shorts/xxxx, /live/xxxx
---@param url string
---@return string|nil
local function ExtractYoutubeId(url)
    if type(url) ~= 'string' then return nil end

    local patterns = {
        'youtu%.be/([%w_%-]+)',
        'youtube%.com/watch%?v=([%w_%-]+)',
        'youtube%.com/embed/([%w_%-]+)',
        'youtube%.com/shorts/([%w_%-]+)',
        'youtube%.com/live/([%w_%-]+)',
    }

    for _, pattern in ipairs(patterns) do
        local id = url:match(pattern)
        if id then return id end
    end

    return nil
end

--- 動画IDを検証してサーバーに再生開始を依頼します
---@param url string
local function StartRadio(url)
    local videoId = ExtractYoutubeId(url)

    if not videoId then
        lib.notify({
            title = 'YouTube音楽プレイヤー',
            description = '有効なYouTubeのURLを入力してください',
            type = 'error'
        })
        return
    end

    TriggerServerEvent('vay_ytmusic:start', videoId)
end

-- /ytmusic <URL> のようにURLを直接指定することもできますし、
-- 引数なしで実行するとox_libの入力欄が開きます
RegisterCommand(Config.Command, function(_, args)
    if args[1] then
        StartRadio(args[1])
        return
    end

    local input = lib.inputDialog('YouTube 音楽プレイヤー', {
        {
            type = 'input',
            label = 'YouTube URL',
            description = '再生したい動画のURLを貼り付けてください',
            required = true
        }
    })

    if not input or not input[1] then return end

    StartRadio(input[1])
end, false)

RegisterCommand(Config.StopCommand, function()
    TriggerServerEvent('vay_ytmusic:stop')
end, false)

-- サーバーから「誰かが音楽を再生開始した」通知が来た時の処理
RegisterNetEvent('vay_ytmusic:play', function(src, videoId)
    activeRadios[src] = { videoId = videoId }
    SendNUIMessage({ action = 'create', src = src, videoId = videoId })
end)

-- サーバーから「誰かが音楽を停止した」通知が来た時の処理
RegisterNetEvent('vay_ytmusic:stopClient', function(src)
    if not activeRadios[src] then return end

    activeRadios[src] = nil
    SendNUIMessage({ action = 'destroy', src = src })
end)

-- 一定間隔ごとに、発信者との距離を測って音量を計算するループです
-- Config.Radius(現在: 3.0m)以内なら音が聞こえ、離れるほど小さくなります
CreateThread(function()
    while true do
        Wait(Config.UpdateInterval)

        if next(activeRadios) ~= nil then
            local myCoords = GetEntityCoords(PlayerPedId())

            for src in pairs(activeRadios) do
                local volume = 0.0
                local targetPlayer = GetPlayerFromServerId(src)

                if targetPlayer ~= -1 then
                    local targetPed = GetPlayerPed(targetPlayer)

                    if targetPed ~= 0 and DoesEntityExist(targetPed) then
                        local dist = #(myCoords - GetEntityCoords(targetPed))

                        if dist <= Config.Radius then
                            -- 距離0mで最大音量、Config.Radiusで音量0になるように減衰させます
                            volume = Config.MaxVolume * (1.0 - (dist / Config.Radius))
                        end
                    end
                end

                SendNUIMessage({ action = 'setVolume', src = src, volume = math.floor(volume) })
            end
        end
    end
end)

-- プロジェクトルール: NUIが誤ってフォーカスを奪ったままにならないよう、リソース起動時に必ず初期化します
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    SetNuiFocus(false, false)
end)
