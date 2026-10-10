fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vanguard-bank'
author 'Rover'
description 'Vanguard Bank - branches, ATMs, personal / savings / shared / business / job accounts'
version '1.0.0'

provide 'qb-banking' -- answers exports['qb-banking'] for scripts written for qb-banking

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/rules.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/places.lua',
    'client/placement.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/router.lua',
    'server/accounts.lua',
    'server/ledger.lua',
    'server/places.lua',
    'server/access.lua',
    'server/money.lua',
    'server/branch.lua',
    'server/compat.lua',
    'server/business.lua',
    'server/migrate.lua',
    'server/main.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/progress.js',
    'html/app.js',
}

dependencies {
    'oxmysql',
    'qb-core',
}
