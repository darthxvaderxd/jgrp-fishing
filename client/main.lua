local QBCore = exports['qb-core']:GetCoreObject()

local TARGET_OPTION = 'jgrp_fishing_sell'

local casting = false
local stopRequested = false
local rodProp
local monger, mongerZone, mongerBlip

local function notify(message, type)
    QBCore.Functions.Notify(message, type or 'primary')
end

local function hasTarget()
    return GetResourceState('ox_target') == 'started'
end

-- ---------------------------------------------------------------------------
-- Water
-- ---------------------------------------------------------------------------

--- Is there water where the line would land?
---
--- Probed in front of the player rather than under them, so a pier, a jetty or
--- a boat deck all work -- you fish *at* water, you do not stand in it.
local function waterAhead()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local ahead = coords + (GetEntityForwardVector(ped) * (Config.CastDistance or 12.0))

    -- Two goes: the surface directly, then a probe from above for water that
    -- the first test misses under a pier.
    local found, height = GetWaterHeight(ahead.x, ahead.y, ahead.z)

    if not found then
        found, height = GetWaterHeightNoWaves(ahead.x, ahead.y, ahead.z)
    end

    if not found then return false end

    -- Water that is far below or above the line is not water you can fish.
    return math.abs(coords.z - height) <= (Config.WaterDistance or 25.0)
end

-- ---------------------------------------------------------------------------
-- Casting
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- The rod in hand
-- ---------------------------------------------------------------------------

--- The attachment being tuned. Seeded from the config and moved by /rodrot and
--- /rodoff, so the numbers can be found in game rather than guessed at.
local rodOffset = Config.RodProp and Config.RodProp.offset or vector3(0.1, 0.05, 0.0)
local rodRotation = Config.RodProp and Config.RodProp.rotation or vector3(-100.0, 120.0, 160.0)

local function detachRod()
    if not rodProp then return end

    if DoesEntityExist(rodProp) then DeleteEntity(rodProp) end
    rodProp = nil
end

--- Put a rod in the player's hands for the length of the session.
---
--- Failure here is cosmetic, so it never stops a cast: a rod that will not
--- load is a note in the console and fishing carries on without the prop.
local function attachRod()
    if rodProp and DoesEntityExist(rodProp) then return end

    local prop = Config.RodProp
    if not prop or not prop.model then return end

    local loaded, model = pcall(lib.requestModel, prop.model, 10000)

    if not loaded or not model then
        print(('^3[jgrp-fishing]^7 rod prop "%s" would not load -- fishing without it')
            :format(tostring(prop.model)))
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    rodProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(rodProp) then
        rodProp = nil
        return
    end

    AttachEntityToEntity(
        rodProp, ped, GetPedBoneIndex(ped, prop.bone or 60309),
        rodOffset.x, rodOffset.y, rodOffset.z,
        rodRotation.x, rodRotation.y, rodRotation.z,
        true, true, false, true, 1, true
    )
end

--- Put it back on with whatever the numbers are now.
---
--- Spawns one if there is not a rod in hand, so /rodrot and /rodoff work on
--- their own. They used to return quietly when nothing was attached, which is
--- how the commands looked broken: they stored the numbers, printed them to a
--- console nobody was watching, and moved nothing.
local function reattachRod()
    detachRod()
    attachRod()

    return rodProp ~= nil
end

--- The line to paste into Config.RodProp.
local function printRodLine()
    print(('^2[jgrp-fishing]^7 offset = vector3(%.2f, %.2f, %.2f), rotation = vector3(%.1f, %.1f, %.1f)')
        :format(rodOffset.x, rodOffset.y, rodOffset.z, rodRotation.x, rodRotation.y, rodRotation.z))
end

local function playCastAnim(seconds)
    lib.requestAnimDict(Config.AnimDict, 5000)

    local ped = PlayerPedId()
    TaskPlayAnim(ped, Config.AnimDict, Config.AnimClip, 3.0, 3.0, seconds, 49, 0, false, false, false)
end

local function stopCastAnim()
    local ped = PlayerPedId()
    if IsEntityPlayingAnim(ped, Config.AnimDict, Config.AnimClip, 3) then
        StopAnimTask(ped, Config.AnimDict, Config.AnimClip, 3.0)
    end
end

--- One cast, start to finish.
---
--- @return boolean keepFishing false when the loop should stop -- out of gear,
---         out of room, out of water, or the player reeled in on purpose. A
---         fish getting away is not one of them.
local function doCast()
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        notify('Not from in a car.', 'error')
        return false
    end

    if not waterAhead() then
        notify('You need to be facing water.', 'error')
        return false
    end

    local answered, start = pcall(lib.callback.await, 'jgrp-fishing:server:cast', false)

    if not answered or type(start) ~= 'table' then
        notify('Something went wrong casting.', 'error')
        return false
    end

    if not start.ok then
        local reason = start.reason

        if reason == 'no_rod' then
            notify('You have no rod.', 'error')
        elseif reason == 'rod_level' then
            notify(('Your %s needs fishing level %d.'):format(start.label or 'rod', start.level or 0), 'error')
        elseif reason == 'no_bait' then
            notify('You are out of bait.', 'error')
        elseif reason == 'bait_level' then
            notify(('%s needs fishing level %d.'):format(start.label or 'That bait', start.level or 0), 'error')
        elseif reason == 'no_skill' then
            notify('Your record is unreachable right now.', 'error')
        elseif reason ~= 'too_fast' then
            notify('You cannot cast right now.', 'error')
        end

        return false
    end

    -- The wait. The fish is already decided server-side -- this is the line
    -- sitting in the water, not a roll in progress.
    playCastAnim(start.castTime + 5000)

    local waiting = lib.progressBar({
        duration = start.castTime,
        label = ('Fishing with %s'):format(start.bait),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    if not waiting then
        stopCastAnim()

        -- The bait is already gone: it went in the water when the line did.
        pcall(lib.callback.await, 'jgrp-fishing:server:land', false, false)
        notify('You reeled in early.', 'error')

        -- Reeling in by hand is a decision, so it ends the session too.
        return false
    end

    -- The strike. Miss it and the fish is gone, bait with it.
    local landed = lib.skillCheck(start.difficulty, { 'w', 'a', 's', 'd' })

    stopCastAnim()

    local ok, result = pcall(lib.callback.await, 'jgrp-fishing:server:land', false, landed and true or false)

    if not ok or type(result) ~= 'table' then
        notify('Something went wrong landing it.', 'error')
        return false
    end

    if result.ok then
        notify(('You landed a %s.'):format(result.label), 'success')

        if result.xp and result.xp > 0 then
            notify(('+%d XP'):format(result.xp), 'primary')
        end

        if start.keptBait then
            notify('Your bait survived.', 'primary')
        end

        return true
    end

    -- Full pockets is the one failure worth stopping for: every further cast
    -- would land a fish and then drop it.
    if result.reason == 'no_room' then
        notify(('You landed a %s but have no room for it.'):format(result.label or 'fish'), 'error')
        return false
    end

    -- Not the player's fault and not fixable by them: the catch is configured
    -- but no such item exists.
    if result.reason == 'unknown_item' then
        notify(('Something is wrong with %s -- tell an admin.'):format(result.label or 'that catch'), 'error')
        return false
    end

    if result.reason ~= 'no_cast' then
        notify('It got away.', 'error')
    end

    return true
end

--- Fish until told to stop.
local function cast()
    if casting then return end

    casting = true
    stopRequested = false

    attachRod()
    lib.showTextUI(Config.StopLabel)

    -- Watches for the stop key for as long as the session runs. A thread of its
    -- own because the cast spends most of its time inside progress bars and
    -- skill checks, which do not yield the frame back to us.
    CreateThread(function()
        while casting do
            if IsControlJustReleased(0, Config.StopKey) then
                stopRequested = true
            end

            Wait(0)
        end
    end)

    repeat
        local keepFishing = doCast()

        if not keepFishing then break end
        if stopRequested then break end

        -- Long enough to read what you caught before the line goes back out.
        local resume = GetGameTimer() + (Config.RecastDelay or 1500)

        while GetGameTimer() < resume and not stopRequested do Wait(50) end
    until stopRequested

    casting = false
    stopRequested = false

    stopCastAnim()
    detachRod()
    lib.hideTextUI()
end

RegisterNetEvent('jgrp-fishing:client:cast', cast)

-- ---------------------------------------------------------------------------
-- Selling
-- ---------------------------------------------------------------------------

local function sell(item)
    local ok, result = pcall(lib.callback.await, 'jgrp-fishing:server:sell', false, item)

    if not ok or type(result) ~= 'table' then
        return notify('Something went wrong selling.', 'error')
    end

    if result.ok then
        return notify(('Sold %d for $%d.'):format(result.sold, result.amount), 'success')
    end

    if result.reason == 'nothing' then
        notify('You have nothing to sell.', 'error')
    elseif result.reason == 'too_far' then
        notify('You are not at the fishmonger.', 'error')
    elseif result.reason == 'no_room' then
        notify('You have no room for the payment.', 'error')
    else
        notify('He is not buying that.', 'error')
    end
end

local function openFishmonger()
    local held = lib.callback.await('jgrp-fishing:server:catchOnHand', false)

    if type(held) ~= 'table' or #held == 0 then
        return notify('You have nothing to sell.', 'error')
    end

    local options = {}
    local total = 0

    for i = 1, #held do
        local row = held[i]
        total = total + row.count

        options[#options + 1] = {
            title = ('%s  x%d'):format(row.label, row.count),
            description = ('$%d-%d each'):format(row.min, row.max),
            icon = 'fish',
            onSelect = function() sell(row.item) end,
        }
    end

    table.insert(options, 1, {
        title = ('Sell everything  (%d)'):format(total),
        description = 'The whole bucket, priced fish by fish',
        icon = 'sack-dollar',
        onSelect = function() sell(nil) end,
    })

    lib.registerContext({
        id = 'jgrp_fishing_monger',
        title = 'Fishmonger',
        options = options,
    })

    lib.showContext('jgrp_fishing_monger')
end

-- ---------------------------------------------------------------------------
-- The fishmonger himself
-- ---------------------------------------------------------------------------

--- Models tried in order. The configured one first, then one that is known to
--- load on this server -- `a_m_m_fishing_01` was never verified, and a model
--- that does not exist makes `lib.requestModel` raise, which used to leave no
--- ped and no explanation.
local function mongerModels()
    local models = {}

    if Config.Fishmonger.model then models[#models + 1] = Config.Fishmonger.model end
    models[#models + 1] = 'a_m_m_genfat_01'

    return models
end

--- The eye, wherever it ends up -- on the ped if there is one, on the spot if
--- there is not. Selling should not depend on a model existing.
local function addSellTarget(entity)
    if not hasTarget() then return end

    local option = {
        name = TARGET_OPTION,
        icon = Config.Fishmonger.icon,
        label = Config.Fishmonger.label,
        distance = Config.Fishmonger.targetDistance,
        onSelect = openFishmonger,
    }

    if entity then
        exports.ox_target:addLocalEntity(entity, { option })
        return
    end

    local spot = Config.Fishmonger.coords

    local ok, zone = pcall(function()
        return exports.ox_target:addSphereZone({
            coords = vector3(spot.x, spot.y, spot.z),
            radius = math.max(1.5, Config.Fishmonger.targetDistance or 2.5),
            options = { option },
        })
    end)

    if ok and zone then mongerZone = zone end
end

local function spawnMonger()
    if monger and DoesEntityExist(monger) then return end
    if mongerZone then return end

    local spot = Config.Fishmonger.coords
    local model

    for _, candidate in ipairs(mongerModels()) do
        local loaded, hash = pcall(lib.requestModel, candidate, 10000)

        if loaded and hash then
            model = hash
            break
        end

        print(('^3[jgrp-fishing]^7 fishmonger model "%s" would not load'):format(tostring(candidate)))
    end

    if not model then
        -- No ped at all: put the eye on the spot so the shop still works.
        print('^1[jgrp-fishing]^7 no fishmonger model loaded -- selling from a zone instead')
        addSellTarget(nil)
        return
    end

    -- **At spot.z, not below it.** /fishcoord prints GetEntityCoords of the
    -- player, which is already where the feet are; spawning a metre under that
    -- buried him in the pier, which looks exactly like the ped never spawning.
    monger = CreatePed(4, model, spot.x, spot.y, spot.z, spot.w, false, false)

    if not DoesEntityExist(monger) then
        SetModelAsNoLongerNeeded(model)
        monger = nil
        addSellTarget(nil)
        return
    end

    SetEntityHeading(monger, spot.w or 0.0)
    FreezeEntityPosition(monger, true)
    SetEntityInvincible(monger, true)
    SetBlockingOfNonTemporaryEvents(monger, true)
    SetModelAsNoLongerNeeded(model)

    addSellTarget(monger)
end

local function removeMonger()
    if mongerZone then
        if hasTarget() then
            pcall(function() exports.ox_target:removeZone(mongerZone) end)
        end
        mongerZone = nil
    end

    if not monger then return end

    if hasTarget() then
        pcall(function() exports.ox_target:removeLocalEntity(monger, TARGET_OPTION) end)
    end

    if DoesEntityExist(monger) then DeleteEntity(monger) end
    monger = nil
end

CreateThread(function()
    local spot = Config.Fishmonger.coords
    local blip = Config.Fishmonger.blip

    if blip then
        mongerBlip = AddBlipForCoord(spot.x, spot.y, spot.z)
        SetBlipSprite(mongerBlip, blip.sprite or 68)
        SetBlipColour(mongerBlip, blip.colour or 3)
        SetBlipScale(mongerBlip, blip.scale or 0.7)
        SetBlipAsShortRange(mongerBlip, true)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Fishmonger')
        EndTextCommandSetBlipName(mongerBlip)
    end

    while true do
        local wait = 2000

        if LocalPlayer.state.isLoggedIn then
            local distance = #(GetEntityCoords(PlayerPedId()) - vector3(spot.x, spot.y, spot.z))

            if distance <= 100.0 then
                spawnMonger()
            else
                removeMonger()
                wait = 4000
            end
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

RegisterCommand('fish', cast, false)

RegisterCommand('sellfish', function()
    openFishmonger()
end, false)

CreateThread(function()
    if not Config.Fishmonger.coordCommand then return end

    RegisterCommand('fishcoord', function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        print(('^2[jgrp-fishing]^7 vector4(%.2f, %.2f, %.2f, %.1f),')
            :format(coords.x, coords.y, coords.z, GetEntityHeading(ped)))

        notify('Coordinate printed to the F8 console.', 'primary')
    end, false)
end)

-- ---------------------------------------------------------------------------
-- Finding the rod's attachment
--
-- Offsets cannot be worked out from outside the game, so rather than guess and
-- push, guess and push again, these move the rod while you watch it and print
-- the line to paste back into the config.
-- ---------------------------------------------------------------------------

CreateThread(function()
    if not (Config.RodProp and Config.RodProp.tuneCommand) then return end

    --- Rod in hand, standing still, without fishing.
    RegisterCommand('rodtune', function()
        if rodProp then
            detachRod()
            return notify('Rod put away.', 'primary')
        end

        attachRod()

        if not rodProp then
            return notify('The rod prop would not load.', 'error')
        end

        notify('Rod in hand. /rodrot x y z and /rodoff x y z to move it.', 'primary')
        printRodLine()
    end, false)

    RegisterCommand('rodrot', function(_, args)
        local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])

        if not x or not y or not z then
            return notify('Usage: /rodrot [pitch] [roll] [yaw]', 'error')
        end

        rodRotation = vector3(x, y, z)

        if not reattachRod() then
            return notify('The rod prop would not load.', 'error')
        end

        notify(('Rotation %.0f, %.0f, %.0f'):format(x, y, z), 'primary')
        printRodLine()
    end, false)

    RegisterCommand('rodoff', function(_, args)
        local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])

        if not x or not y or not z then
            return notify('Usage: /rodoff [x] [y] [z]', 'error')
        end

        rodOffset = vector3(x, y, z)

        if not reattachRod() then
            return notify('The rod prop would not load.', 'error')
        end

        notify(('Offset %.2f, %.2f, %.2f'):format(x, y, z), 'primary')
        printRodLine()
    end, false)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- A session left running would hold a text UI on screen with nothing behind
    -- it.
    casting = false
    stopRequested = true
    detachRod()
    lib.hideTextUI()

    removeMonger()
    if mongerBlip and DoesBlipExist(mongerBlip) then RemoveBlip(mongerBlip) end
end)
