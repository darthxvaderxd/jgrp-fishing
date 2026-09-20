# jgrp-fishing

Fishing for **qb-core**, gated and levelled by [jgrp-skills](../jgrp-skills).
Better bait needs a higher level and lands bigger fish. Bigger fish are worth
more — and weigh more, which is the cost.

Inventory is **ox_inventory**, prompts and the strike are **ox_lib**.

## How it plays

1. Stand facing water with a rod and bait on you. `/fish`, or use the rod once
   `ox_inventory` has restarted (see **Install**).
2. The line goes in. **The fish is decided at that moment**, server-side, from
   the bait's pool — the wait is the line sitting in the water, not a roll in
   progress.
3. A bite, then an ox_lib skill check. Your rod decides how hard it is.
4. Land it and it is yours, with XP. Miss it and the fish and the bait are
   both gone.
5. **It casts again by itself.** Fishing is a session, not a cast: `[X]` stops
   it, and that prompt stays on screen the whole time.
6. Sell at the fishmonger on Paleto pier — one kind at a time, or the whole
   bucket.

**A rod appears in your hands** for the length of the session — from the first
cast to the last, not per cast. Bone `60309` is the left hand, which is where
the fishing animation holds it, with the right hand on the reel. If the prop
will not load it is a note in the console and fishing carries on without it —
losing the prop should never cost you a cast.

### Getting the rod to sit right

Attachment offsets cannot be worked out from outside the game, and guessing at
them one push at a time is slow. Three commands do it while you watch:

| | |
| --- | --- |
| `/rodtune` | puts the rod in your hands where you stand, and takes it away again |
| `/rodrot [pitch] [roll] [yaw]` | turns it, live |
| `/rodoff [x] [y] [z]` | moves it, live |

Every change prints the finished `offset = ... , rotation = ...` line to F8,
ready to paste into `Config.RodProp`.

The shipped `rotation = vector3(-180.0, 180.0, 200.0)` was found this way. The
two values before it — `80` and `-100` pitch — were guesses from outside the
game, and both were wrong: one pointed the rod at the ground, the other left it
askew. Use the commands.

### What ends a session

Losing a fish does not — it just casts again. These do:

| | |
| --- | --- |
| **X** | you asked it to |
| Out of bait | nothing left to cast with |
| Pockets full | every further cast would land a fish and drop it |
| Reeled in early | cancelling the bar is a decision, not an accident |
| Not facing water, or in a car | checked before every cast |
| No rod, or not the level for it | checked before every cast |

`Config.RecastDelay` (1.5s) is the pause between casts — long enough to read
what you caught before the line goes back out.

`/sellfish` opens the same menu without ox_target.

## The trade-off

**Bigger fish weigh more.** Nothing in this resource enforces that: it falls
out of ox_inventory's own weights, which the fish already carry.

| | Weight | Price | XP |
| --- | --- | --- | --- |
| Perch | 600g | $45–70 | 10 |
| Mullet | 800g | $55–85 | 12 |
| Trout | 850g | $70–110 | 14 |
| Bass | 900g | $80–125 | 16 |
| Carp | 1.0kg | $90–140 | 18 |
| Crab | 1.2kg | $130–190 | 26 |
| Lobster | 1.5kg | $180–260 | 32 |
| Octopus | 1.8kg | $220–320 | 38 |
| Tuna | 2.0kg | $240–350 | 40 |
| Turtle | 3.0kg | $320–460 | 55 |
| *Toaster* | *5.0kg* | *$5–20* | *2* |
| *Small TV* | *100g* | *$15–40* | *2* |

A bucket of turtles pays five times what a bucket of perch does and fills your
pockets three times faster, so the better you fish the sooner you have to walk
back. The toaster is the joke at the bottom: heavier than anything that swims,
worth almost nothing.

## The ladder

| Bait | Level | Lands |
| --- | --- | --- |
| Worm | 0 | perch, mullet, trout, bass, carp — and rubbish |
| Shrimp Lure | 3 | bass, trout, carp, crab, tuna, lobster |
| Illegal Bait | 8 | tuna, lobster, octopus, turtle, crab |

| Rod | Level | Cast | Strike (area / speed) | Saves bait |
| --- | --- | --- | --- | --- |
| Rod I | 0 | 9s | 45 / 0.9 | never |
| Rod II | 2 | 8s | 55 / 0.8 | 10% |
| Rod III | 5 | 7s | 65 / 0.7 | 20% |
| Rod IV | 10 | 6s | 75 / 0.6 | 30% |

**The strike uses explicit numbers, not ox_lib's presets.** Those are
`easy` = 50 area / 1.0 speed, `medium` = 40 / 1.5, `hard` = 25 / 1.75 — and the
first version of this file put the *starter* rod on `hard`, which handed a brand
new fisherman the smallest target at nearly double speed. Every rod here is now
slower than ox_lib's easiest preset, and a better rod means a bigger target
moving slower.

**The best rod and bait you are carrying and are allowed to use** is what you
fish with. There is no picking, and no way to hold back the good bait.

### Those numbers are tuned against the XP curve

jgrp-skills charges `100 + (level - 1) * 75` per level, which climbs hard:
level 3 is 275 XP cumulative, level 8 is 2,275, level 18 is 11,900.

A first pass at this had a perch worth 4 XP and the illegal bait gated at
level 18 — **about 2,500 casts**, ten hours, to reach the third bait. The drug
ladder made the same mistake and was retuned the same way.

As it stands a worm averages ~11 XP a cast, putting the shrimp lure ~25 casts
out; the lure averages ~21, putting the illegal bait ~95 casts after that.
**Recompute both if you touch either** — `sum(100 + (l-1)*75)` up to the gate,
against the average XP of the pool that gets you there.

## Install

1. `ensure jgrp-fishing`, **after** `qb-core`, `ox_lib`, `ox_inventory` and
   `jgrp-skills`.
2. `jgrp-skills` needs a `fishing` skill in its `Config.Skills` — **already
   added**.
3. No SQL. Progress lives in `jgrp-skills`' `player_skills` table.

### The one items.lua edit

Every item this resource needs **already exists** in
`ox_inventory/data/items.lua` — `rod_1`–`rod_4`, `worm`, `shrimp_lure`,
`illegalbait`, all ten fish and the junk. They were left behind by
**`dusa_fishing`**, a script that has never run on this server.

Their `server.export` lines have been repointed at this resource — **but
ox_inventory caches item definitions at start**, so using a rod does nothing
until `ox_inventory` is restarted. `/fish` works regardless.

They originally read:

```lua
['rod_1'] = { ..., server = { export = 'dusa_fishing.useRod' } },
['worm']  = { ..., server = { export = 'dusa_fishing.useBait' } },
```

Using one today calls a resource that does not exist. Repoint the five lines to
`jgrp-fishing.useRod` / `jgrp-fishing.useBait` and using a rod casts, the way
the items already claim. **Until then `/fish` is the only way in** — everything
else works regardless.

`tackle_box` points at `dusa_fishing.useTackleBox`, which this resource does not
implement. Leave it, or take the item out.

## Trust model

The client owns the water check and the strike; everything that decides an
outcome is server-side:

- **The fish is chosen when the line goes in**, not when it is landed, so a
  client cannot re-roll a poor catch by dropping the strike.
- **The bait is taken at the same moment**, so a cancelled cast still costs it.
- Rod and bait are read from the player's inventory and checked against their
  level, and the **best allowed** is chosen server-side — the client never says
  what it is using.
- `Config.MinCastInterval` (4s) is the floor between casts a client talking
  straight to the server cannot get under.
- Prices are rolled per fish, server-side, at the moment of sale, and selling
  checks you are actually stood at the fishmonger.

## Config reference

| Option | Default | Effect |
| --- | --- | --- |
| `Config.Skill` | `'fishing'` | jgrp-skills skill read and awarded. |
| `Config.Rods` | 4 | Rod ladder: level, cast time, strike difficulty, bait saving. |
| `Config.Baits` | 3 | Bait ladder: level and what each can land. |
| `Config.Fish` | 12 | Price and XP per catch. Weight belongs to ox_inventory. |
| `Config.WaterDistance` | `25.0` | How far above or below the water you may stand. |
| `Config.CastDistance` | `12.0` | How far ahead the line is thrown. |
| `Config.MinCastInterval` | `4000` | Server-side floor between casts. |
| `Config.RodProp` | `prop_fishing_rod_01` | The rod in your hands. `model = false` to fish empty-handed. |
| `Config.RodProp.tuneCommand` | `true` | Registers `/rodtune`, `/rodrot`, `/rodoff`. |
| `Config.StopKey` | `73` (X) | Ends the session. Control index, not a key code. |
| `Config.RecastDelay` | `1500` | Pause between one cast and the next. |
| `Config.Fishmonger` | Paleto pier | Where the ped stands, and the blip. |
| `Config.PayoutType` | `'cash'` | `'cash'` or `'item'`. |

## Known gaps

- The fishmonger falls back through two models and then to a bare zone, so
  selling works even if no ped loads — but a missing ped is worth chasing: the
  reason is printed to F8 at start.
- No boats, no depth, no time of day: where you cast changes nothing, only what
  you cast with. Pools are per bait, so per-location pools would be the natural
  next step.
- `tackle_box` is unimplemented, as above.
- Selling is a flat price per fish. Nothing rewards bringing in a haul of one
  kind, and nothing moves the price as the market fills.
