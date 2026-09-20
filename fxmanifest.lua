fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'jgrp-fishing'
author 'jgrp'
description 'Fishing gated by jgrp-skills: better bait needs a higher level and lands bigger fish, which are worth more and weigh more'
version '1.0.0'

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

-- ox_target is checked at runtime rather than declared: without it the
-- fishmonger falls back to /sellfish, and casting never needed it.
dependencies {
    'qb-core',
    'ox_lib',
    'ox_inventory',
    'jgrp-skills'
}
