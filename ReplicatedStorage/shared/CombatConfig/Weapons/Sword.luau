--!nonstrict

local HITBOX = { size = Vector3.new(6, 5, 6), offset = CFrame.new(0, 0, -3.5) }

local STANCE = { leftLeg = { 20, 0, 0 }, rightLeg = { -14, 0, 0 } }

local function withStance(pose)
	for joint, angles in pairs(STANCE) do
		pose[joint] = angles
	end
	return pose
end

local OVERHEAD = {
	duration = 0.46,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.09, pose = withStance({ rightArm = { 165, 0, -12 }, leftArm = { 35, 0, -25 }, torso = { 12, -22, 0 } }) },
		{ t = 0.15, pose = withStance({ rightArm = { 70, 0, 4 }, leftArm = { 40, 0, -20 }, torso = { -14, 24, 0 } }) },
		{ t = 0.26, pose = withStance({ rightArm = { 70, 0, 4 }, leftArm = { 40, 0, -20 }, torso = { -14, 24, 0 } }) },
		{ t = 0.46, pose = {} },
	},
}

local SIDE_RIGHT = {
	duration = 0.46,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.09, pose = withStance({ rightArm = { 0, -35, 95 }, leftArm = { 30, 0, -25 }, torso = { 0, -38, 0 } }) },
		{ t = 0.15, pose = withStance({ rightArm = { 0, 115, 95 }, leftArm = { 30, 0, -30 }, torso = { -4, 42, 0 } }) },
		{ t = 0.26, pose = withStance({ rightArm = { 0, 115, 95 }, leftArm = { 30, 0, -30 }, torso = { -4, 42, 0 } }) },
		{ t = 0.46, pose = {} },
	},
}

local SIDE_LEFT = {
	duration = 0.46,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.09, pose = withStance({ rightArm = { 0, 130, 95 }, leftArm = { 30, 0, -25 }, torso = { 0, 40, 0 } }) },
		{ t = 0.15, pose = withStance({ rightArm = { 0, -30, 95 }, leftArm = { 30, 0, -25 }, torso = { -4, -40, 0 } }) },
		{ t = 0.26, pose = withStance({ rightArm = { 0, -30, 95 }, leftArm = { 30, 0, -25 }, torso = { -4, -40, 0 } }) },
		{ t = 0.46, pose = {} },
	},
}

local FINISHER = {
	duration = 0.6,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.12, pose = withStance({ rightArm = { 150, 0, -10 }, leftArm = { 150, 0, 10 }, torso = { 16, -30, 0 } }) },
		{ t = 0.19, pose = withStance({ rightArm = { 60, 0, 0 }, leftArm = { 60, 0, 0 }, torso = { -22, 14, 0 } }) },
		{ t = 0.34, pose = withStance({ rightArm = { 60, 0, 0 }, leftArm = { 60, 0, 0 }, torso = { -22, 14, 0 } }) },
		{ t = 0.6, pose = {} },
	},
}

local function damage(base: number, scale: number)
	return function(s)
		return base + s.sword * scale
	end
end

return {
	displayName = "Sword",
	m1 = {
		comboResetTime = 1.2,
		comboEndCooldown = 0.9,
		hits = {
			{ windup = 0.15, recovery = 0.22, hitbox = HITBOX, damage = damage(8, 0.1), animation = SIDE_RIGHT },
			{ windup = 0.15, recovery = 0.22, hitbox = HITBOX, damage = damage(8, 0.1), animation = SIDE_LEFT },
			{ windup = 0.15, recovery = 0.24, hitbox = HITBOX, damage = damage(9, 0.1), animation = OVERHEAD },
			{
				windup = 0.19,
				recovery = 0.32,
				hitbox = { size = Vector3.new(7, 5, 7), offset = CFrame.new(0, 0, -3.5) },
				damage = damage(11, 0.15),
				knockback = 40,
				animation = FINISHER,
			},
		},
	},
	abilities = {
		{
			id = "SpinSlash",
			key = "Z",
			name = "Spin Slash",
			kind = "melee",
			cooldown = 6,
			windup = 0.25,
			recovery = 0.35,
			hitbox = { size = Vector3.new(14, 5, 14), offset = CFrame.new() },
			damage = damage(18, 0.2),
			knockback = 30,
			animation = {
				duration = 0.6,
				keyframes = {
					{ t = 0, pose = {} },
					{ t = 0.08, pose = withStance({ rightArm = { 0, 0, 95 }, leftArm = { 0, 0, -95 }, torso = { 0, -30, 0 } }) },
					{ t = 0.32, pose = withStance({ rightArm = { 0, 0, 95 }, leftArm = { 0, 0, -95 }, torso = { 0, 330, 0 } }) },
					{ t = 0.36, pose = withStance({ rightArm = { 0, 0, 95 }, leftArm = { 0, 0, -95 }, torso = { 0, 330, 0 } }) },
					{ t = 0.6, pose = {} },
				},
			},
		},
		{
			id = "RisingSlash",
			key = "X",
			name = "Rising Slash",
			kind = "melee",
			cooldown = 8,
			windup = 0.3,
			recovery = 0.35,
			hitbox = { size = Vector3.new(6, 8, 6), offset = CFrame.new(0, 1, -3.5) },
			damage = damage(15, 0.2),
			knockback = 25,
			launch = 45,
			breaksBlock = true,
			animation = {
				duration = 0.65,
				keyframes = {
					{ t = 0, pose = {} },
					{ t = 0.24, pose = withStance({ rightArm = { -25, 0, 18 }, leftArm = { 40, 0, -20 }, torso = { -20, -14, 0 } }) },
					{ t = 0.32, pose = withStance({ rightArm = { 172, 0, 0 }, leftArm = { 60, 0, -20 }, torso = { 18, 14, 0 } }) },
					{ t = 0.42, pose = withStance({ rightArm = { 172, 0, 0 }, leftArm = { 60, 0, -20 }, torso = { 18, 14, 0 } }) },
					{ t = 0.65, pose = {} },
				},
			},
		},
	},
}
