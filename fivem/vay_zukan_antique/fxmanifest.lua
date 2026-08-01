fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Vulfayne City'
description 'Antique collection album (QBCore + ox_target + ox_inventory + oxmysql)'
version '1.0.0'

shared_scripts {
	'@ox_lib/init.lua',
	'shared/data.lua',
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
	'html/backgrounds/*.jpg',
}

dependencies {
	'qb-core',
	'ox_target',
	'ox_lib',
	'oxmysql',
	'ox_inventory',
}
