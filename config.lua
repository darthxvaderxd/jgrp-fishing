Config = {}

--- The jgrp-skills skill this resource reads and awards. Must exist in
--- jgrp-skills' own Config.Skills or every cast is refused.
Config.Skill = 'fishing'

-- ---------------------------------------------------------------------------
-- The trade-off this whole resource is built around
--
-- Better bait needs a higher level, and lands bigger fish. Bigger fish are
-- worth more -- and weigh more, which is the cost. A turtle is 3kg against a
-- perch's 600g, so a boat full of good catches fills your pockets long before
-- a boat full of poor ones, and you walk back to the fishmonger sooner.
--
-- Nothing here enforces that: it falls out of ox_inventory's own item weights,
-- which the fish already carry. The job of this config is only to make sure
-- the better bait reaches the heavier fish.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Rods
-- ---------------------------------------------------------------------------

--- You need one of these in your pockets to cast. The best rod you are
--- carrying is the one used -- there is no picking.
---
--- minLevel : fishing level needed to use it at all.
--- castTime : milliseconds before the fish bites. Better rods are quicker.
--- difficulty : ox_lib skill check for the strike. Better rods make it easier.
---
---              **Explicit numbers, not the presets.** ox_lib's are
---              easy = 50 area / 1.0 speed, medium = 40 / 1.5 and
---              hard = 25 / 1.75 -- so the first pass here, which put the
---              starter rod on 'hard', handed a brand new fisherman the
---              smallest target at nearly double speed. Every rod below is
---              slower than ox_lib's *easiest* preset, and the ladder runs the
---              right way: a better rod is a bigger target moving slower.
---
---              areaSize: width of the hit zone, bigger is easier.
---              speedMultiplier: 1.0 is ox_lib's baseline; lower is slower.
--- keeps    : chance (0.0 - 1.0) the bait survives the cast. A better rod
---            wastes less bait, which matters more than it sounds at the top
---            of the ladder where bait is expensive.
---
--- These four items already exist in ox_inventory as rod_1..rod_4, left behind
--- by a fishing script that was never started. Weights, labels and images are
--- all in place -- see the README for the one edit items.lua still needs.
Config.Rods = {
    ['rod_1'] = {
        label = 'Fishing Rod I',   minLevel = 0,  castTime = 9000, keeps = 0.00,
        difficulty = { areaSize = 45, speedMultiplier = 0.9 },
    },
    ['rod_2'] = {
        label = 'Fishing Rod II',  minLevel = 2,  castTime = 8000, keeps = 0.10,
        difficulty = { areaSize = 55, speedMultiplier = 0.8 },
    },
    ['rod_3'] = {
        label = 'Fishing Rod III', minLevel = 5,  castTime = 7000, keeps = 0.20,
        difficulty = { areaSize = 65, speedMultiplier = 0.7 },
    },
    ['rod_4'] = {
        label = 'Fishing Rod IV',  minLevel = 10, castTime = 6000, keeps = 0.30,
        difficulty = { areaSize = 75, speedMultiplier = 0.6 },
    },
}

--- Order the rods are tried in, best first. A player carrying three rods fishes
--- with the best one they are allowed to use.
Config.RodOrder = { 'rod_4', 'rod_3', 'rod_2', 'rod_1' }

-- ---------------------------------------------------------------------------
-- Bait
-- ---------------------------------------------------------------------------

--- One is consumed per cast, unless the rod saves it.
---
--- `pool` is what that bait can land, weighted. Weights are relative within
--- the pool, so { 40, 30, 10 } and { 4, 3, 1 } behave the same.
---
--- The ladder is the point: a worm lands small fish and rubbish, a shrimp lure
--- reaches the good stuff, and illegal bait is where the turtles and octopus
--- are -- 3kg and 1.8kg apiece.
Config.Baits = {
    ['worm'] = {
        label = 'Worm',
        minLevel = 0,
        pool = {
            { item = 'perch',    weight = 30 },
            { item = 'mullet',   weight = 25 },
            { item = 'trout',    weight = 15 },
            { item = 'bass',     weight = 10 },
            { item = 'carp',     weight = 8 },
            { item = 'small_tv', weight = 7 },
            { item = 'toaster',  weight = 5 },
        },
    },

    ['shrimp_lure'] = {
        label = 'Shrimp Lure',
        minLevel = 3,
        pool = {
            { item = 'bass',    weight = 25 },
            { item = 'trout',   weight = 20 },
            { item = 'carp',    weight = 18 },
            { item = 'crab',    weight = 15 },
            { item = 'tuna',    weight = 12 },
            { item = 'lobster', weight = 7 },
            { item = 'toaster', weight = 3 },
        },
    },

    ['illegalbait'] = {
        label = 'Illegal Bait',
        minLevel = 8,
        pool = {
            { item = 'tuna',    weight = 25 },
            { item = 'lobster', weight = 22 },
            { item = 'octopus', weight = 20 },
            { item = 'crab',    weight = 15 },
            { item = 'turtle',  weight = 18 },
        },
    },
}

--- Order bait is tried in, best first, same idea as the rods.
Config.BaitOrder = { 'illegalbait', 'shrimp_lure', 'worm' }

-- ---------------------------------------------------------------------------
-- The catch
-- ---------------------------------------------------------------------------

--- What each fish is worth and what it teaches you.
---
--- **The XP is tuned against jgrp-skills' curve, not picked by feel.** That
--- curve is `100 + (level - 1) * 75` per level, which climbs hard: level 3
--- costs 275 XP cumulative, level 8 costs 2,275, level 18 costs 11,900. A
--- first pass at this file had a perch worth 4 XP and the illegal bait gated
--- at 18 -- about **2,500 casts**, ten hours of fishing, to reach the third
--- bait. The drug ladder made the same mistake and had to be retuned the same
--- way.
---
--- As it stands: a worm averages about 11 XP a cast, so the shrimp lure (level
--- 3) is roughly 25 casts away, and the lure averages about 21, putting the
--- illegal bait (level 8) about 95 casts after that. Call it two hours to the
--- top of the ladder.
---
--- **Recompute both if you touch either.** `sum(100 + (l-1)*75 for l = 1..gate-1)`
--- against the average XP of the pool that gets you there.
---
--- price : dollars, rolled per fish at the fishmonger.
--- xp    : fishing XP for landing one.
--- weight is deliberately **not** here -- ox_inventory owns that, and the
--- numbers in the comments are its, so a change there does not leave a stale
--- copy in this file.
Config.Fish = {
    ['perch']    = { label = 'Perch',   price = { min = 45,  max = 70 },  xp = 10 },  -- 600g
    ['mullet']   = { label = 'Mullet',  price = { min = 55,  max = 85 },  xp = 12 },  -- 800g
    ['trout']    = { label = 'Trout',   price = { min = 70,  max = 110 }, xp = 14 },  -- 850g
    ['bass']     = { label = 'Bass',    price = { min = 80,  max = 125 }, xp = 16 },  -- 900g
    ['carp']     = { label = 'Carp',    price = { min = 90,  max = 140 }, xp = 18 },  -- 1.0kg
    ['crab']     = { label = 'Crab',    price = { min = 130, max = 190 }, xp = 26 },  -- 1.2kg
    ['lobster']  = { label = 'Lobster', price = { min = 180, max = 260 }, xp = 32 },  -- 1.5kg
    ['octopus']  = { label = 'Octopus', price = { min = 220, max = 320 }, xp = 38 },  -- 1.8kg
    ['tuna']     = { label = 'Tuna',    price = { min = 240, max = 350 }, xp = 40 },  -- 2.0kg
    ['turtle']   = { label = 'Turtle',  price = { min = 320, max = 460 }, xp = 55 },  -- 3.0kg

    -- Rubbish. Worth pennies, weighs a ton, and that is the joke -- a toaster
    -- is 5kg, heavier than anything that swims.
    ['toaster']  = { label = 'Toaster',  price = { min = 5,  max = 20 }, xp = 2 },    -- 5.0kg
    ['small_tv'] = { label = 'Small TV', price = { min = 15, max = 40 }, xp = 2 },    -- 100g
}

--- Sold to the fishmonger in one go, or one at a time. Cash, like the corner.
Config.PayoutType = 'cash'
Config.PayoutItem = 'black_money'

-- ---------------------------------------------------------------------------
-- Casting
-- ---------------------------------------------------------------------------

--- How close to water you have to be. The check is a probe straight down from
--- in front of you, so you can fish off a pier without standing in the sea.
Config.WaterDistance = 25.0

--- How far in front of you the line is thrown, in metres. Where the probe
--- looks for water.
Config.CastDistance = 12.0

--- Floor between two casts from one player, in milliseconds. The cast itself
--- paces this; the floor is what a client talking straight to the server
--- cannot get under.
Config.MinCastInterval = 4000

--- The animation while waiting on a bite.
Config.AnimDict = 'amb@world_human_stand_fishing@idle_a'
Config.AnimClip = 'idle_c'

--- Once you start, you keep casting until you stop -- fishing is not something
--- you do one cast at a time.
---
--- The loop ends on its own when it has to: out of bait, out of pockets, no
--- longer facing water, in a car, or dead. Losing a fish is not a reason to
--- stop, so a miss just casts again.
Config.StopKey = 73            -- X. Control indices, not key codes.
Config.StopLabel = '[X] Stop fishing'

--- Pause between one cast finishing and the next going out, in milliseconds.
--- Long enough to read what you caught.
Config.RecastDelay = 1500

-- ---------------------------------------------------------------------------
-- The fishmonger
-- ---------------------------------------------------------------------------

Config.Fishmonger = {
    --- Where they stand. Paleto Bay pier, near the water.
    coords = vector4(-1817.35, -1219.55, 13.02, 132.0),

    model = 'a_m_m_fishing_01',

    label = 'Sell fish',
    icon = 'fa-solid fa-fish',
    targetDistance = 2.5,

    --- false, or { sprite, colour, scale } for a blip.
    blip = { sprite = 68, colour = 3, scale = 0.7 },

    --- Prints a coordinate line to the F8 console. Only your own position.
    coordCommand = true,
}

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

--- Pick one entry from a weighted list, or nil if it is empty.
function Config.PickWeighted(list)
    if type(list) ~= 'table' or #list == 0 then return nil end

    local total = 0
    for i = 1, #list do total = total + math.max(0, list[i].weight or 0) end
    if total <= 0 then return nil end

    local roll = math.random() * total

    for i = 1, #list do
        roll = roll - math.max(0, list[i].weight or 0)
        if roll <= 0 then return list[i] end
    end

    return list[#list]
end

--- Inclusive random integer, tolerating a plain number.
function Config.Roll(range)
    if type(range) == 'number' then return math.floor(range) end
    if type(range) ~= 'table' then return 0 end

    local min = math.floor(range.min or 0)
    local max = math.floor(range.max or min)
    if max <= min then return min end

    return math.random(min, max)
end

--- The best rod or bait a player may use, given what they carry and their
--- level. Shared so the client can say *why* a cast is refused and the server
--- can enforce the same answer.
---
--- @param counts table<string, number> item name -> how many are held
--- @param order string[] Config.RodOrder or Config.BaitOrder
--- @param set table Config.Rods or Config.Baits
--- @return string|nil name, table|nil entry, string|nil reason
function Config.BestOf(counts, order, set, level)
    local held, gated = false, nil

    for i = 1, #order do
        local name = order[i]
        local entry = set[name]

        if entry and (counts[name] or 0) > 0 then
            held = true

            if level >= (entry.minLevel or 0) then
                return name, entry, nil
            end

            -- Remember the closest thing they own but cannot use yet, so the
            -- message can name the level rather than just saying no.
            if not gated or (entry.minLevel or 0) < (gated.minLevel or 0) then
                gated = entry
            end
        end
    end

    if not held then return nil, nil, 'none' end

    return nil, gated, 'level'
end
