local QBCore = exports['qb-core']:GetCoreObject()

local TARGET_OPTION = 'jgrp_fishing_sell'

local casting = false
local stopRequested = false
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

local function spawnMonger()
    if monger and DoesEntityExist(monger) then return end

    local spot = Config.Fishmonger.coords

    local loaded, model = pcall(lib.requestModel, Config.Fishmonger.model, 10000)

    if not loaded or not model then
        print(('^1[jgrp-fishing]^7 fishmonger model "%s" would not load'):format(tostring(Config.Fishmonger.model)))
        return
    end

    monger = CreatePed(4, model, spot.x, spot.y, spot.z - 1.0, spot.w, false, false)

    if not DoesEntityExist(monger) then
        SetModelAsNoLongerNeeded(model)
        monger = nil
        return
    end

    FreezeEntityPosition(monger, true)
    SetEntityInvincible(monger, true)
    SetBlockingOfNonTemporaryEvents(monger, true)
    SetModelAsNoLongerNeeded(model)

    if hasTarget() then
        exports.ox_target:addLocalEntity(monger, {
            {
                name = TARGET_OPTION,
                icon = Config.Fishmonger.icon,
                label = Config.Fishmonger.label,
                distance = Config.Fishmonger.targetDistance,
                onSelect = openFishmonger,
            },
        })
    end
end

local function removeMonger()
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

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- A session left running would hold a text UI on screen with nothing behind
    -- it.
    casting = false
    stopRequested = true
    lib.hideTextUI()

    removeMonger()
    if mongerBlip and DoesBlipExist(mongerBlip) then RemoveBlip(mongerBlip) end
end)
