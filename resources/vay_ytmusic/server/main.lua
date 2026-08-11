-- serverId -> videoId の形で、現在誰がどの動画を再生しているかを保持します
local ActiveRadios = {}

--- クライアントから届いた動画IDが不正な文字列でないか検証します(なりすまし対策)
---@param videoId any
---@return boolean
local function IsValidVideoId(videoId)
    return type(videoId) == 'string'
        and #videoId >= 6
        and #videoId <= 32
        and videoId:match('^[%w_%-]+$') ~= nil
end

RegisterNetEvent('vay_ytmusic:start', function(videoId)
    local src = source
    if not IsValidVideoId(videoId) then return end

    ActiveRadios[src] = videoId
    -- 全プレイヤーに再生開始を通知します(実際に聞こえるかどうかはクライアント側で距離判定します)
    TriggerClientEvent('vay_ytmusic:play', -1, src, videoId)
end)

RegisterNetEvent('vay_ytmusic:stop', function()
    local src = source
    if not ActiveRadios[src] then return end

    ActiveRadios[src] = nil
    TriggerClientEvent('vay_ytmusic:stopClient', -1, src)
end)

-- 再生中のプレイヤーが切断した場合は、他プレイヤー側の再生も止めます
AddEventHandler('playerDropped', function()
    local src = source
    if not ActiveRadios[src] then return end

    ActiveRadios[src] = nil
    TriggerClientEvent('vay_ytmusic:stopClient', -1, src)
end)
