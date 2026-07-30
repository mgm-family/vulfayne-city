fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Vulfayne City'
description 'Seal / Oopart / Antique collection minigame (QBCore + ox_target + oxmysql)'
version '1.0.0'

shared_scripts {
	'@ox_lib/init.lua',
	'shared/data_helpers.lua',
	'shared/seal_data.lua',
	'shared/oopart_data.lua',
	'shared/antique_data.lua',
}

client_scripts {
	'client/main.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/main.lua',
}

ui_page 'html/index.html'

files {
	'html/index.html',
	'html/style.css',
	'html/script.js',
	'html/images/*.png',
}

dependencies {
	'qb-core',
	'ox_target',
	'ox_lib',
	'oxmysql',
	'ox_inventory',
}
