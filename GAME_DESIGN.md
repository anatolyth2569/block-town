# Block-Town — Game Design Goals

> Reference: modeled after **Townstar** (Gala Games).
> Read this before touching any system to stay on target.

---

## Core Vision

A city-builder where players design a **self-sustaining production town**.
Every building, road, and worker placement matters.
The fun is in optimizing the layout — not clicking every action manually.

---

## Logic 1: Production Chain

Resources flow through tiers. Selling raw materials is always wasteful.

```
Tier 0 — Raw           Tier 1 — Processed      Tier 2 — Finished
Wheat (farm)     →     Flour (mill)       →     Bread (bakery)
Sugarcane        →     Sugar (sugar mill)  →     Cake (cake bakery)
Cotton           →     Cotton Yarn        →     Uniform (factory)
Tree / Wood      →     Planks (lumberyard) →     Tools (factory)
Crude Oil        →     Petroleum          →     Gasoline (refinery)
```

**Rule:** every processing step must multiply the value significantly.
**Goal:** always push production toward the highest-tier item possible.

---

## Logic 2: Placement & Proximity

Every building placement has consequences. Nothing is free.

### Roads
- Workers walk on roads. Road = 2× speed, off-road = 1× (slow).
- A factory with no road access will bottleneck the whole chain.
- Design road topology first, then place buildings around it.

### Pollution
- Industrial buildings (Refinery, Power Plant, Factory) emit pollution in a radius.
- Pollution **reduces crop growth speed** for farms inside the radius.
- Keep industrial zones physically separated from farm zones.

### Natural Resources
- Farms placed near **rivers/ponds** get free water → crops grow faster without wells.
- Tree Farms need green terrain cells (Forest biome) to function.
- Wind Pumps cover a 3-cell water radius — place centrally between multiple fields.

### Proximity Design Rule
> Plan the town in zones:
> [Farm Zone] — far from industrial, near water
> [Ranch Zone] — near feed mill, near water
> [Industrial Zone] — near roads, away from farms
> [Trade Zone] — Trade Depot near roads, near fuel storage

---

## Logic 3: Workers & Fuel

These are the two binding constraints of the game.

### Fuel (Gasoline)
- Every Trade Depot sale **consumes Gasoline**.
- No gasoline = cannot sell = no income = workers go on strike.
- Gasoline chain: Oil Pump → Refinery → Gasoline → Fuel Tank
- **Gasoline production must be established before aggressive selling.**
- This is the mid-game pivot point — everything before it is bootstrapping.

### Workers
- Every active production building needs a worker.
- Workers come from Housing buildings (Farm House, Ranch House, etc.).
- Each worker costs wages every 30 seconds (1 Gold/worker).
- **Too many workers with no income = bankruptcy.**
- **Too few workers = production stops.**
- Balance: add workers only when new income can cover their wages.

### Worker Scope (Domain System — planned)
Each worker type has a defined scope. Workers only act within their domain.

| Worker Type | Spawns From | Works On |
|-------------|------------|----------|
| Farmer | Farm House | All CROP domain fields |
| Rancher | Ranch House | All LIVESTOCK domain buildings |
| Woodcutter | Woodcutter House | Forest terrain + Tree Farms |
| Builder | Builder House | Construction queue (any building) |
| Production Worker | Any factory building | That building only |
| Carrier | Auto-spawned | Fetches inputs for factory buildings |
| Driver/Merchant | Garage / Market | Trade runs |

---

## Logic 4: Economy Loop

```
Wages drain Gold every 30s
     ↓
Must sell goods to refill Gold
     ↓
Selling costs Gasoline
     ↓
Must produce Gasoline (complex chain)
     ↓
Need workers to produce Gasoline
     ↓
Workers cost wages → loop back
```

**The game is about managing this loop.** Build too fast = wages kill you.
Build too slow = competitors win. Find the optimal expansion rate.

---

## Current Implementation Status

| System | Status | Notes |
|--------|--------|-------|
| Production chain (.tres data) | ✅ Done | 39 buildings, 30+ resources |
| Worker system (generic) | ✅ Working | mill, bakery, factory etc. |
| Woodcutter logic | ✅ Working | |
| Farmer logic | ✅ Fixed | domain-based scan, produce read directly from .tres |
| Rancher logic | ✅ Done | Livestock = factory style (carrier fetches Feed, worker produces); LIVESTOCK domain on .tres |
| Worker Domain system | ✅ Done | WorkerDomain enum in BuildingData; CROP_FIELD on 7 farm .tres, LIVESTOCK on 3 animal .tres |
| Pollution effect on crops | ✅ Done | get_production_modifier() applied to grow_time in all start_field_growth calls |
| River/water proximity bonus | ⚠️ Removed | River +20 bonus removed (was over-filling water past max); ponds still work |
| Gasoline gating trade | ✅ Done | Fuel Tank + trade cost |
| Save / Load | ✅ Done | SaveManager autoload, auto-save 60s, user://save.json, New Game button |
| Proximity speed effect (road) | ⚠️ Partial | road speed bonus exists |

---

## Next Priority

1. **Full playtest** — test all systems end-to-end, fix bugs found
2. **Rancher NPC** (optional) — currently livestock uses factory pattern; if walking rancher NPC is wanted, model after farmer
