--!nonstrict

local Weapons = require(script:WaitForChild("Weapons"))

local config = {
	keys = {
		dash = "Q",
		block = "F",
		climb = "LeftControl",
		jump = "Space",
	},

	defaultWeapon = "Fists",
	weapons = Weapons,

	stats = {
		dataStoreName = "CombatStats_v1",
		studioDataStoreName = "CombatStats_Dev",
		saveInStudio = true,
		autosaveInterval = 120,
		sessionLockTimeout = 600,
		loadAttempts = 5,
		retryDelay = 2,
		defaults = {
			strength = 0,
			sword = 0,
			fire = 0,
			endurance = 0,
			agility = 0,
			resistance = 0,
		},
		unlocks = {
			skyJump = false,
		},
	},

	network = {
		maxActionsPerSecond = 20,
		animationRange = 250,
	},

	health = {
		max = function(s)
			return 100 + s.endurance * 1
		end,
	},

	run = {
		walkSpeed = 16,
		speed = function(s)
			return 26 + s.agility * 0.05
		end,
		cancelOnAction = true,
		doubleTapWindow = 0.3,
	},

	dash = {
		distance = function(s)
			return 18 + s.agility * 0.02
		end,
		duration = 0.22,
		cooldown = function(s)
			return math.max(0.8, 2 - s.agility * 0.005)
		end,
		iFrames = false,
	},

	jump = {
		doubleJumpPower = 55,
		skyJump = {
			power = 50,
			horizontalSpeed = 30,
			cooldown = 0.15,
		},
	},

	block = {
		arc = 120,
		max = function(s)
			return 100 + s.endurance * 0.5
		end,
		regenDelay = 2,
		regenRate = function(s)
			return 15 + s.endurance * 0.1
		end,
		walkSpeed = 8,
		guardBreakStun = function(s)
			return math.max(0.6, 2.5 - s.resistance * 0.01)
		end,
		minRaiseFraction = 0.15,
		showToOthers = true,
	},

	hit = {
		hitStun = function(s)
			return math.max(0.15, 0.35 - s.resistance * 0.001)
		end,
		reachTolerance = 3,
		maxTargets = 8,
		pvp = true,
		npcFriendlyFire = false,
		lineOfSight = true,
		knockbackTime = 0.35,
	},

	debug = {
		enabled = true,
		studioOnly = true,
		userIds = {},
		showHitboxes = false,
	},

	hud = {
		indicatorDistance = 45,
		shieldWidthStuds = 1.7,
	},

	climb = {
		reach = 2.5,
		time = function(s)
			return 9 + s.endurance * 0.05
		end,
		speed = function(s)
			return 10 + s.agility * 0.03
		end,
		ragdollFallHeight = 10,
		cooldown = 0.5,
		jumpPower = 45,
		jumpAwaySpeed = 25,
		wallCheckInterval = 0.2,
		wallMisses = 3,
	},

	ragdoll = {
		minTime = 0.6,
		maxTime = 8,
	},

	anticheat = {
		enabled = true,
		speedTolerance = 1.35,
		horizontalSlack = 8,
		teleportDistance = 40,
		verticalTolerance = 1.4,
		verticalSlack = 4,
		spawnGrace = 1.5,
	},

	npcs = {
		["passive"] = {
			weapon = "Fists",
			behavior = "idle",
			respawnTime = 3,
		},

		["blocker"] = {
			weapon = "Fists",
			behavior = "block",
			interval = { 0.2, 0.4 },
			respawnTime = 3,
			stats = { endurance = 20, resistance = 20 },
		},

		["swordsman"] = {
			weapon = "Sword",
			behavior = "attack",
			abilityMode = "random",
			weights = { M1 = 3, SpinSlash = 2, RisingSlash = 2 },
			range = 10,
			attackWithoutTarget = false,
			interval = { 0.1, 0.3 },
			respawnTime = 3,
			stats = { sword = 30 },
		},

		["caster"] = {
			weapon = "Fire",
			behavior = "attack",
			abilityMode = "sequence",
			sequence = { "Fireball", "M1", "M1", "FlameBurst", "Fireball" },
			range = 30,
			attackWithoutTarget = false,
			interval = { 0.4, 0.8 },
			respawnTime = 3,
			stats = { fire = 20 },
		},
	},
}

return config
