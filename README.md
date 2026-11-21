# Combat System

Server-authoritative melee and ability combat for Roblox: weapons with M1 combos and abilities, blocking with a breakable shield, dash, run, double jump, unlimited sky jumps, wall climbing, fall ragdoll, a cooldown HUD and stationary training NPCs. Every player number comes from per-player stats saved in a DataStore.

## Features

- **Weapons**: every weapon has an M1 combo plus its own abilities. With no tool equipped you fight with your fists. Three come with the project: `Fists`, `Sword` and `Fire`.
- **Abilities**: three kinds: `melee` (a hitbox in front of you), `area` (a radius around you) and `projectile` (simulated on the server, drawn on the clients).
- **Block**: hold the block key to raise a shield. Hits from the front drain the shield instead of your health. When it reaches zero the guard breaks and you are stunned. Hits from behind ignore the shield and go straight to your health, without draining the shield. While blocking, the character holds a boxing guard (one arm flat across the chest, the other raised on top of it), and the shield icon follows the replicated `CombatState`, so every client sees it, even for NPCs that were already blocking when the client joined.
- **Movement**: dash, run (double tap), double jump, unlimited sky jumps with a short cooldown, and wall climbing with a stamina ring. Falling from a wall from high enough ragdolls you until you land, unless you air jump out of it.
- **HUD**: on the left of the screen, `[KEY] Name` for M1, Block, Dash, Sky Jump (once unlocked) and the abilities of the equipped weapon, with the cooldown shown in red.
- **Stats**: damage, shield, stun time, speeds, climb time and more are formulas of the player's stats, saved per player with session locking.
- **NPCs**: stationary training NPCs that idle, block or attack in place with any weapon, in random or fixed order, using the same cooldowns as players.
- **Procedural animations**: basic attack animations made from joint keyframes, so the project works without uploading animation assets. Works with Motor6D rigs and with the newer AnimationConstraint rigs.
- **Server authority**: the client only sends intents. The server checks state, cooldowns, unlocks, distances, line of sight and hit side, and validates the movement of every player.

## Getting started

### Option 1: open the place

Open [`build/CombatSystemTest.rbxlx`](build/CombatSystemTest.rbxlx) in Roblox Studio and press Play. It has a small arena, four training NPCs and the `Sword` and `Fire` tools.

To save stats while testing in Studio, turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it the system prints one warning and keeps stats for the session only.

### Option 2: add it to your game

The folders tell you where each file goes:

```
<Studio location>/<client, server or shared>/<Name>.<luau or rbxmx>
```

- The first folders are the place in Studio (for example `ServerScriptService`, `StarterPlayer/StarterPlayerScripts`).
- `server` runs on the server, `client` runs on the player's device, `shared` is read by both.
- A folder with the same name as a script holds that script's children. `ServerScriptService/server/CombatSystem/` holds the modules that go inside the `CombatSystem` ModuleScript.
- `.luau` files are code. Copy the text into a new script of the type shown below.
- `.rbxmx` files are ready-made Studio objects. Select the location in Studio, right-click → **Insert from File...** and pick the file.

Required:

| File | Create in Studio | Type |
|---|---|---|
| `ReplicatedStorage/shared/CombatConfig.luau` | `ReplicatedStorage` → `CombatConfig` | ModuleScript |
| `ReplicatedStorage/shared/CombatConfig/Weapons.luau` | inside `CombatConfig` → `Weapons` | ModuleScript |
| `ReplicatedStorage/shared/CombatConfig/Weapons/*.luau` | inside `Weapons`, one per file | ModuleScript |
| `ReplicatedStorage/shared/CombatShared.luau` | `ReplicatedStorage` → `CombatShared` | ModuleScript |
| `ReplicatedStorage/shared/CombatTemplates.rbxmx` | `ReplicatedStorage` | Folder of effect and physics templates |
| `ReplicatedStorage/server/CombatRemotes.rbxmx` | `ReplicatedStorage` | Folder with the `CombatAction` and `CombatState` RemoteEvents |
| `ReplicatedStorage/client/ClimbIndicator.rbxmx` | `ReplicatedStorage` | BillboardGui (climb stamina ring) |
| `ReplicatedStorage/client/ShieldIndicator.rbxmx` | `ReplicatedStorage` | BillboardGui (shield icon) |
| `ServerScriptService/server/CombatSystem.luau` | `ServerScriptService` → `CombatSystem` | ModuleScript |
| `ServerScriptService/server/CombatSystem/*.luau` | inside `CombatSystem`, one per file | ModuleScript |
| `ServerScriptService/server/CombatBootstrap.luau` | `ServerScriptService` → `CombatBootstrap` | Script |
| `StarterPlayer/StarterPlayerScripts/client/CombatClient.luau` | `StarterPlayer` → `StarterPlayerScripts` → `CombatClient` | LocalScript |
| `StarterPlayer/StarterPlayerScripts/client/CombatClient/*.luau` | inside `CombatClient`, one per file | ModuleScript |
| `StarterGui/client/CombatHud.rbxmx` | `StarterGui` | ScreenGui (ability HUD) |
| `StarterGui/client/CombatDebug.rbxmx` | `StarterGui` | ScreenGui (debug toggle and live panel) |

Optional (used by the test place):

| File | Insert into | What it is |
|---|---|---|
| `StarterPack/server/Sword.rbxmx` | `StarterPack` | The `Sword` tool (a `Handle` plus welded pommel, guard, blade, fuller and tip parts; the Grip turns it so the blade stands up when held, flat faces to the sides) |
| `StarterPack/server/Fire.rbxmx` | `StarterPack` | The `Fire` tool (a power, nothing in the hand) |
| `Workspace/server/CombatArena.rbxmx` | `Workspace` | Floor, spawn, a climbing wall, a tower, a ledge, a pillar and a block |
| `Workspace/server/TrainingDummies.rbxmx` | `Workspace` | Four training NPCs, one per behavior |

The system never creates its objects in code. If one of them is missing it prints a warning and disables only the part that needs it (for example the HUD, the stamina ring or an effect).

## Controls

| Input | Action |
|---|---|
| Left mouse button | M1 (hold to keep attacking) |
| Hold `F` | Block |
| `Q` | Dash in the move direction (forward when standing still) |
| Double tap `W` | Run while `W` is held |
| `Space` on the ground | Jump |
| `Space` in the air | First press: double jump. Every press after that: sky jump, if unlocked |
| `Left Ctrl` facing a wall | Grab the wall / let go. While climbing: `W`/`S` up and down, `A`/`D` sideways, `Space` jumps off the wall |
| Weapon keys (`Z`, `X`, ...) | Abilities of the equipped weapon |

While climbing, a procedural animation holds the hands and feet against the wall and alternates them as you move up, down or sideways (every client plays it for every climbing player; it stops moving when you stop).

Moving sideways around a corner keeps the climb going: at an outside corner the character swings around to the next face, and at an inside corner it turns to the wall it runs into, with a short turn of about 0.2 s. Changing direction quickly at a corner does not drop you while stamina is left. The server checks the new face with its own raycast.

Leaving a wall counts as the first jump, so the next `Space` is the double jump. If the climb stamina runs out more than `climb.ragdollFallHeight` studs above the ground you ragdoll until you land. A double or sky jump during that fall gets you out of the ragdoll.

## Configuration

Everything is in [`CombatConfig.luau`](ReplicatedStorage/shared/CombatConfig.luau).

- **Units:** distances in studs, times in seconds, angles in degrees, speeds in studs per second.
- **Formulas:** every value marked *stat* below can be a number or a function `function(stats) return ... end`. `stats` holds the player's stats (`config.stats.defaults` lists them). For example `damage = function(s) return 8 + s.sword * 0.1 end` turns 100 sword into 10 extra damage.
- **Validation:** when the system starts it checks every value and calls every formula once with the default stats. An invalid global value stops `Start()` with an error that lists every problem. An invalid weapon or NPC profile is only disabled, with a warning.

### keys

| Key | Default | Meaning |
|---|---|---|
| `dash` | `"Q"` | Dash key (an `Enum.KeyCode` name). |
| `block` | `"F"` | Block key. |
| `climb` | `"LeftControl"` | Climb key. |
| `jump` | `"Space"` | Jump key, used for air jumps and wall jumps. |

Ability keys are set per ability in the weapon files and can't repeat these keys.

### stats

| Key | Default | Meaning |
|---|---|---|
| `dataStoreName` | `"CombatStats_v1"` | DataStore used in live servers. |
| `studioDataStoreName` | `"CombatStats_Dev"` | DataStore used in Studio. Must be different from `dataStoreName`, so Studio never touches live data. |
| `saveInStudio` | `true` | `false` keeps stats for the session only in Studio. |
| `autosaveInterval` | `120` | Seconds between saves of players whose stats changed. |
| `sessionLockTimeout` | `600` | A lock left by another server older than this is taken over. |
| `loadAttempts` | `5` | Tries to load a player's data before using defaults for the session (without saving, so real data is never overwritten). |
| `retryDelay` | `2` | Seconds between tries. |
| `defaults` | `strength, sword, fire, endurance, agility, resistance = 0` | The stats every player starts with. Add your own keys here and use them in any formula. |
| `unlocks` | `skyJump = false` | Things a player can unlock. `skyJump` enables sky jumps. |

### network

| Key | Default | Meaning |
|---|---|---|
| `maxActionsPerSecond` | `20` | Messages a client may send per second. Extra ones are ignored. |
| `animationRange` | `250` | Only players this close receive animations and effects of a character. |

### health, run, dash, jump

| Key | Default | Meaning |
|---|---|---|
| `health.max` | `100 + endurance` (stat) | Max health. |
| `run.walkSpeed` | `16` (stat) | Walking speed. |
| `run.speed` | `26 + agility * 0.05` (stat) | Running speed. |
| `run.cancelOnAction` | `true` | Attacking slows you to walking speed. |
| `run.doubleTapWindow` | `0.3` | Seconds between two taps of `W` to start running. |
| `dash.distance` | `18 + agility * 0.02` (stat) | Dash distance. |
| `dash.duration` | `0.22` (stat) | Dash time. |
| `dash.cooldown` | `max(0.8, 2 - agility * 0.005)` (stat) | Dash cooldown. |
| `dash.iFrames` | `false` | `true` makes you immune to hits during the dash. |
| `jump.doubleJumpPower` | `55` (stat) | Upward speed of the double jump. |
| `jump.skyJump.power` | `50` (stat) | Upward speed of a sky jump. |
| `jump.skyJump.horizontalSpeed` | `30` (stat) | Speed of a sky jump in the move direction. |
| `jump.skyJump.cooldown` | `0.15` (stat) | Time between two sky jumps. There is no limit on how many. |

### block

| Key | Default | Meaning |
|---|---|---|
| `arc` | `120` | Front angle the shield covers. Hits from outside it count as hits from behind. |
| `max` | `100 + endurance * 0.5` (stat) | Shield points. Blocking a hit removes points equal to its damage. |
| `regenDelay` | `2` | Seconds after the last blocked hit before the shield refills. |
| `regenRate` | `15 + endurance * 0.1` (stat) | Shield points refilled per second while not blocking. |
| `walkSpeed` | `8` (stat) | Walking speed while blocking. |
| `guardBreakStun` | `max(0.6, 2.5 - resistance * 0.01)` (stat) | Stun when the shield breaks. Uses the **defender's** stats. |
| `minRaiseFraction` | `0.15` | Fraction of the shield needed to raise it again. |
| `showToOthers` | `true` | `false` shows the shield drawing only to its owner. |

### hit

| Key | Default | Meaning |
|---|---|---|
| `hitStun` | `max(0.15, 0.35 - resistance * 0.001)` (stat) | Stun after taking a hit. Uses the defender's stats. |
| `reachTolerance` | `3` | Extra size added to hitboxes to make up for network delay. |
| `maxTargets` | `8` | Most targets one attack can hit. |
| `pvp` | `true` | Players can hit players. |
| `npcFriendlyFire` | `false` | NPCs can hit NPCs. |
| `lineOfSight` | `true` | A wall between the attacker and the target blocks the hit. |
| `knockbackTime` | `0.35` | How long knockback pushes a player. |

### climb, ragdoll

| Key | Default | Meaning |
|---|---|---|
| `climb.reach` | `2.5` | How close a wall has to be to grab it. |
| `climb.time` | `9 + endurance * 0.05` (stat) | Seconds you can stay on a wall (the stamina ring). |
| `climb.speed` | `10 + agility * 0.03` (stat) | Climbing speed. |
| `climb.ragdollFallHeight` | `10` | Height above the ground at which running out of stamina ragdolls you. |
| `climb.cooldown` | `0.5` | Seconds before you can grab a wall again. |
| `climb.jumpPower` | `45` (stat) | Upward speed of a jump off a wall. |
| `climb.jumpAwaySpeed` | `25` (stat) | Speed away from the wall of that jump. |
| `climb.wallCheckInterval` | `0.2` | How often the server checks that you are still on a wall. |
| `climb.wallMisses` | `3` | Failed checks in a row before the server ends the climb. |
| `ragdoll.minTime` | `0.6` | Shortest ragdoll. |
| `ragdoll.maxTime` | `8` | Longest ragdoll, even if you never land. |

### anticheat

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Movement validation for players. |
| `speedTolerance` | `1.35` | Multiplier on the allowed speed. |
| `horizontalSlack` | `8` | Studs of movement over the allowed path forgiven before a correction (absorbs network bursts). |
| `teleportDistance` | `40` | A move this long in one server frame is always rejected. |
| `verticalTolerance` | `1.4` | Multiplier on the allowed jump heights. |
| `verticalSlack` | `4` | Extra studs of height allowed. |
| `spawnGrace` | `1.5` | Seconds after spawning or `ResetMovementGuard` with no checks. |

### debug

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Allows the debug panel at all. |
| `studioOnly` | `true` | Only players in Roblox Studio may turn the panel on. |
| `userIds` | `{}` | Extra user ids allowed to use the panel in live servers. |
| `showHitboxes` | `false` | Draws every hitbox and hit radius for everybody. The panel button does it only for you. |

The **DEBUG** button (top right) asks the server for permission, then opens a live panel: state, weapon, health, shield, speed, jumps, stats, cooldowns and every NPC (profile, state, health, distance, `TILTED` when it is not upright). The **Hitboxes** button inside shows the server's real hitboxes and radii, sent only to you. The **Sky Jump** button turns that unlock on or off for you (the server only accepts it from players who have the panel on).

### hud

| Key | Default | Meaning |
|---|---|---|
| `indicatorDistance` | `45` | Studs from the camera after which the shield icon and the climb ring disappear. Both have a fixed size on screen. |
| `shieldWidthStuds` | `1.7` | Width of the shield icon in studs. It is sized in the world, so it stays inside the character's torso at any camera distance and screen size. |

## Weapons

Each weapon is a ModuleScript inside `CombatConfig/Weapons`. Every ModuleScript there is loaded automatically: add a file to add a weapon. The key in `config.weapons` is the module's name. `defaultWeapon` (`"Fists"`) is used when no weapon tool is held.

A tool becomes a weapon when it has the attribute `Weapon` set to the weapon's name, or when the tool itself has the weapon's name.

```lua
return {
	displayName = "Sword",
	effect = nil, -- optional: "fire" colors the effects
	m1 = {
		comboResetTime = 1.2, -- the combo starts over after this long without M1
		comboEndCooldown = 0.9, -- extra cooldown after the last hit
		hits = { attack, attack, ... }, -- one attack per hit of the combo
	},
	abilities = {
		{ id = "SpinSlash", key = "Z", name = "Spin Slash", cooldown = 6, ...attack fields },
	},
}
```

Attack fields, used by combo hits and abilities:

| Field | Meaning |
|---|---|
| `kind` | `"melee"` (default), `"area"` or `"projectile"`. |
| `windup` | Seconds from the start of the attack to the hit. Getting stunned before it cancels the attack. |
| `recovery` | Seconds after the hit before you can act again. |
| `damage` | Damage (stat). Uses the **attacker's** stats. |
| `knockback` | Horizontal push (stat, optional). |
| `launch` | Upward push (stat, optional). |
| `breaksBlock` | `true` breaks the guard of a blocking target right away. |
| `hitbox` | `melee`: `{ size = Vector3, offset = CFrame }`, relative to the attacker's root. |
| `area` | `area`: `{ radius = number }` around the attacker. |
| `projectile` | `projectile`: `{ speed, range, radius, explosionRadius }`. `explosionRadius = 0` hits only what it touches. |
| `animation` | See below. |

Ability fields: `id` (unique in the weapon; `M1`, `Block`, `Dash`, `SkyJump` and `Climb` are reserved), `key` (an `Enum.KeyCode` name), `name` (shown in the HUD) and `cooldown` (stat).

**Animations** are either a Roblox animation (`{ id = "rbxassetid://..." }`, which must belong to you or your group) or procedural keyframes:

```lua
animation = {
	duration = 0.38,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.06, pose = { rightArm = { 130, 0, -40 }, torso = { 0, 25, 0 } } },
		{ t = 0.38, pose = {} },
	},
}
```

A pose rotates joints, in degrees `{ x, y, z }`, relative to the torso: `x` raises a limb forward, `y` twists, `z` swings sideways. Joints: `torso`, `head`, `rightArm`, `leftArm`, `rightLeg`, `leftLeg`. The pose is blended on top of the walking animations and works on R6 and R15 rigs.

## NPCs

An NPC is any Model in `Workspace` with a `Humanoid`, a `HumanoidRootPart` and the attribute `CombatProfile` set to a key of `config.npcs`. NPCs stand still and use the same combat code, cooldowns and formulas as players. Stats come from the profile, not from a DataStore.

| Field | Meaning |
|---|---|
| `weapon` | Weapon name. |
| `behavior` | `"idle"` (does nothing), `"block"` (keeps its shield up) or `"attack"` (attacks in place). |
| `abilityMode` | `attack` only: `"random"` or `"sequence"`. |
| `weights` | `random`: chance of each action, for example `{ M1 = 3, SpinSlash = 2 }`. Without it every action is equally likely. Only actions off cooldown are picked. |
| `sequence` | `sequence`: actions in order, for example `{ "Fireball", "M1", "M1" }`. The NPC waits for each one's cooldown. |
| `range` | `attack` only: players inside this distance are faced and targeted. |
| `attackWithoutTarget` | `attack` only: `true` keeps attacking with nobody in range. |
| `interval` | `{ min, max }` seconds between two decisions. |
| `stats` | Stats of the NPC; missing keys use `config.stats.defaults`. |
| `respawnTime` | Seconds before a dead NPC comes back where it was. `0` or missing: no respawn. |

The four test profiles: `passive` (idle), `blocker` (blocks, with more shield and resistance), `swordsman` (attacks in place with the Sword, random abilities, only when a player is within 10 studs) and `caster` (Fire, a fixed sequence, only when a player is within 30 studs).

## Server authority

The client never decides anything. It only sends intents through `CombatAction`: `"M1"`, `"Block", true/false`, `"Ability", id` (projectile abilities add `yaw, pitch`), `"Debug", true/false`, `"Dash"`, `"AirJump"`, `"Climb", true/false`, `"ClimbJump"`, `"Run", true/false` and `"Sync"`. Each message is type checked, limited to four short text, boolean or finite number arguments, rate limited, and only accepted for the sender's own living character.

- **Combat:** the server picks the combo hit, checks state and cooldowns, aims projectile abilities with the mouse direction the client reports (a full 3D direction, so shots can aim up and down) (only a yaw and a pitch, clamped, ignored for every other attack, so M1 and melee abilities use the character's own facing; the hitbox is placed from the server-side character position, so reach and damage can't be changed by the client), finds targets in the hitbox, checks line of sight, decides front or back against the block arc, applies the attacker's damage formula and the defender's stun formula, and pushes the target.
- **Projectiles** are simulated on the server every frame. Clients only draw them.
- **Movement:** player characters move on their own device, so every player is watched by a movement guard:
  - It tracks horizontal speed with a small allowance for network bursts, a height ceiling from the last ground contact and the jumps the server approved, and teleports.
  - A move outside those limits puts the character back at its last safe position on the ground.
  - Dash, air jumps, climbing and knockback only widen the limits within what the server's own rules allow: cooldowns, state, unlocks, and a wall found by a server raycast.

If you move players from your own server code (teleports, moving platforms), call `CombatSystem.ResetMovementGuard(character)` or `CombatSystem.GrantMovement(...)` first, or the guard will put them back.

## API

```lua
local CombatSystem = require(game.ServerScriptService.CombatSystem)

CombatSystem.Start()
CombatSystem.Stop()

CombatSystem.GetStats(player) -- read-only table of the player's stats
CombatSystem.SetStat(player, "sword", 100)
CombatSystem.AddStat(player, "resistance", 5)
CombatSystem.GetUnlock(player, "skyJump")
CombatSystem.SetUnlock(player, "skyJump", true)
CombatSystem.IsStatsLoaded(player)

CombatSystem.StatsChanged:Connect(function(player, kind, key, value) end)
CombatSystem.Damaged:Connect(function(attacker, target, damage, result) end)

CombatSystem.ResetMovementGuard(character, graceSeconds)
CombatSystem.GrantMovement(character, horizontalSpeed, riseStuds, durationSeconds)

CombatSystem.RegisterNPC(model, profileName)
CombatSystem.GetCombatant(model)
CombatSystem.GetCombatants()
CombatSystem.GetWeapon(name)
```

`Damaged` reports `result` as `"hit"`, `"backstab"` (hit from behind a raised shield), `"blocked"` (damage `0`) or `"guardBreak"`. Hits dodged with `dash.iFrames` don't fire it. Stats are replicated as `Stat_<name>` and `Unlock_<name>` attributes on the Player for your own UI.

## Objects the code uses

| Object | Where | Used for |
|---|---|---|
| `CombatRemotes` (`CombatAction`, `CombatState`) | `ReplicatedStorage` | Client intents and server messages |
| `CombatTemplates/Effects` (`Ring`, `Sphere`, `Projectile`, `Hitbox`, `Flash`) | `ReplicatedStorage` | Jump rings, fire blasts, projectiles, debug hitboxes, hit flashes |
| `CombatTemplates/Physics` (`CombatMovement`, `PlaneVelocity`, `VectorVelocity`, `ClimbOrientation`, `RagdollAttachment`, `RagdollSocket`, `Animation`) | `ReplicatedStorage` | Dash, knockback, climbing, ragdoll joints, animation assets |
| `ClimbIndicator` | `ReplicatedStorage` | Climb stamina ring: two clipped half circles (`LeftHalf`, `RightHalf`) with a `UIStroke` and a `UIGradient` that sweeps clockwise |
| `ShieldIndicator` | `ReplicatedStorage` | Shield icon: `Holder` (centered, with the `UIScale`) > `Back` outline, `Slot` > `Fill` (clipped from the bottom) with `Paint` frames; no text |
| `CombatDebug` with `Toggle`, `Panel` (`HitboxButton`, `SkyJumpButton`, `Info`) | `StarterGui` | Debug button and live panel |
| `CombatHud` with `AbilityList` / `AbilityRow` (`Key`, `KeyLabel`, `Cooldown`, `Timer`, `Title`) | `StarterGui` | Ability list; `AbilityRow` is cloned once per entry |

Change sizes, colors and fonts freely in Studio. Keep the names, since the code looks them up.
