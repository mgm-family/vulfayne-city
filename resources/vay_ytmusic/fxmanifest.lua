fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'VAY City'
description 'YouTubeのURLを入力すると、その場所の周囲だけで音楽が聞こえるスクリプト (vay_ytmusic)'
version '1.0.0'

-- ox_libのlib.inputDialog / lib.notifyを使うため、共通スクリプトとして読み込みます
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

-- YouTube動画を裏側で再生させるための非表示NUI
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js'
}

dependencies {
    'ox_lib'
}
