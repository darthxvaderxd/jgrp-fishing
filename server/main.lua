local QBCore = exports['qb-core']:GetCoreObject()

--- [source] = ms of the last accepted cast, the floor a client cannot get
--- under however it talks to us.
local lastCast = {}

--- [source] = { rod, bait, fish, expires } while a cast is in the air. The fish
--- is decided **when the line goes in**, not when it is reeled in, so the
--- client cannot retry a bad catch by dropping the strike.
local casts = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function notify(src, message, type)
    TriggerClientEvent('QBCore:Notify', src, message, type or 'primary')
end

local function getLevel(src)
    if GetResourceState('jgrp-skills') ~= 'started' then return nil end

    local ok, level = pcall(function()
        return exports['jgrp-skills']:GetLevel(src, Config.Skill)
    end)

    if not ok or type(level) ~= 'number' then return nil end
    return level
end

local function countItem(src, item)
    local ok, count = pcall(function()
        return exports.ox_inventory:GetItem(src, item, nil, true)
    end)

    if not ok or type(count) ~= 'number' then return 0 end
    return count
end

--- What the player is carrying out of a list of item names.
local function countAll(src, names)
    local counts = {}
    for i = 1, #names do counts[names[i]] = countItem(src, names[i]) end
    return counts
end

local function awardXp(src, xp)
    if not xp or xp <= 0 then return 0 end
    if GetResourceState('jgrp-skills') ~= 'started' then return 0 end

    pcall(function()
        exports['jgrp-skills']:AddXP(src, Config.Skill, xp)
    end)

    return xp
end

-- ---------------------------------------------------------------------------
-- Casting
-- ---------------------------------------------------------------------------

--- Check the gear, take the bait, decide the fish.
---
--- Everything that matters happens here. The client is told how long to wait
--- and how hard the strike is, and nothing else -- not what is on the line.
lib.callback.register('jgrp-fishing:server:cast', function(source)
    local src = source

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return { ok = false, reason = 'error' } end

    local now = GetGameTimer()

    if lastCast[src] and now - lastCast[src] < Config.MinCastInterval then
        return { ok = false, reason = 'too_fast' }
    end

    -- No level, no fishing: without one we cannot tell which bait is allowed,
    -- and guessing hands out the illegal bait for free.
    local level = getLevel(src)
    if not level then return { ok = false, reason = 'no_skill' } end

    local rodName, rod, rodProblem = Config.BestOf(
        countAll(src, Config.RodOrder), Config.RodOrder, Config.Rods, level)

    if not rodName then
        return {
            ok = false,
            reason = rodProblem == 'level' and 'rod_level' or 'no_rod',
            level = rod and rod.minLevel,
            label = rod and rod.label,
        }
    end

    local baitName, bait, baitProblem = Config.BestOf(
        countAll(src, Config.BaitOrder), Config.BaitOrder, Config.Baits, level)

    if not baitName then
        return {
            ok = false,
            reason = baitProblem == 'level' and 'bait_level' or 'no_bait',
            level = bait and bait.minLevel,
            label = bait and bait.label,
        }
    end

    -- The rod sometimes saves the bait. Rolled before it is taken, so a saved
    -- bait is never removed and added back.
    local keeps = math.random() < (rod.keeps or 0.0)

    if not keeps and not exports.ox_inventory:RemoveItem(src, baitName, 1) then
        return { ok = false, reason = 'no_bait' }
    end

    local hooked = Config.PickWeighted(bait.pool)

    if not hooked or not Config.Fish[hooked.item] then
        print(('^1[jgrp-fishing]^7 bait "%s" has a pool entry with no matching Config.Fish'):format(baitName))
        return { ok = false, reason = 'error' }
    end

    lastCast[src] = now

    casts[src] = {
        rod = rodName,
        bait = baitName,
        fish = hooked.item,
        expires = now + (rod.castTime or 9000) + 30000,
    }

    return {
        ok = true,
        rod = rod.label or rodName,
        bait = bait.label or baitName,
        castTime = rod.castTime or 9000,
        difficulty = rod.difficulty or 'medium',
        keptBait = keeps,
    }
end)

--- The strike. Landed or lost, the cast is over either way.
lib.callback.register('jgrp-fishing:server:land', function(source, landed)
    local src = source

    local cast = casts[src]
    casts[src] = nil

    if not cast then return { ok = false, reason = 'no_cast' } end
    if GetGameTimer() > cast.expires then return { ok = false, reason = 'no_cast' } end

    -- A lost fish still costs the bait, which was taken when the line went in.
    if not landed then return { ok = false, reason = 'lost' } end

    local fish = Config.Fish[cast.fish]
    if not fish then return { ok = false, reason = 'error' } end

    if not exports.ox_inventory:AddItem(src, cast.fish, 1) then
        return { ok = false, reason = 'no_room', label = fish.label or cast.fish }
    end

    return {
        ok = true,
        item = cast.fish,
        label = fish.label or cast.fish,
        xp = awardXp(src, fish.xp),
    }
end)

-- ---------------------------------------------------------------------------
-- Selling
-- ---------------------------------------------------------------------------

--- What the fishmonger would take off you, and for how much.
lib.callback.register('jgrp-fishing:server:catchOnHand', function(source)
    local src = source
    local held = {}

    for item, fish in pairs(Config.Fish) do
        local count = countItem(src, item)

        if count > 0 then
            held[#held + 1] = {
                item = item,
                label = fish.label or item,
                count = count,
                min = fish.price.min or 0,
                max = fish.price.max or 0,
            }
        end
    end

    table.sort(held, function(a, b) return a.max > b.max end)

    return held
end)

--- Sell one kind of fish, or everything.
---
--- Price is rolled per fish rather than per sale, so a bucket of ten is not a
--- clean multiple of one number.
lib.callback.register('jgrp-fishing:server:sell', function(source, item)
    local src = source

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return { ok = false, reason = 'error' } end

    local coords = GetEntityCoords(GetPlayerPed(src))
    local monger = Config.Fishmonger.coords

    if #(coords - vector3(monger.x, monger.y, monger.z)) > (Config.Fishmonger.targetDistance or 2.5) + 5.0 then
        return { ok = false, reason = 'too_far' }
    end

    local wanted = {}

    if item == nil then
        for name in pairs(Config.Fish) do wanted[#wanted + 1] = name end
    elseif Config.Fish[item] then
        wanted[1] = item
    else
        return { ok = false, reason = 'unknown' }
    end

    local total, sold = 0, 0

    for i = 1, #wanted do
        local name = wanted[i]
        local fish = Config.Fish[name]
        local count = countItem(src, name)

        if count > 0 and exports.ox_inventory:RemoveItem(src, name, count) then
            for _ = 1, count do total = total + Config.Roll(fish.price) end
            sold = sold + count
        end
    end

    if sold < 1 then return { ok = false, reason = 'nothing' } end

    if Config.PayoutType == 'item' then
        if not exports.ox_inventory:AddItem(src, Config.PayoutItem, total) then
            return { ok = false, reason = 'no_room' }
        end
    else
        Player.Functions.AddMoney('cash', total, 'jgrp-fishing:sale')
    end

    return { ok = true, sold = sold, amount = total }
end)

-- ---------------------------------------------------------------------------
-- Item use
--
-- The rods and bait in ox_inventory were left pointing at `dusa_fishing`, a
-- resource that has never run here. Repoint them at these two -- the README has
-- the exact edit -- and using a rod casts, the way the items already say they
-- should. Until then /fish does the same job.
-- ---------------------------------------------------------------------------

exports('useRod', function(event, item, inventory)
    if event ~= 'usingItem' then return end
    TriggerClientEvent('jgrp-fishing:client:cast', inventory.id or inventory)
end)

exports('useBait', function(event, item, inventory)
    if event ~= 'usingItem' then return end
    TriggerClientEvent('jgrp-fishing:client:cast', inventory.id or inventory)
end)

AddEventHandler('playerDropped', function()
    casts[source] = nil
    lastCast[source] = nil
end)
