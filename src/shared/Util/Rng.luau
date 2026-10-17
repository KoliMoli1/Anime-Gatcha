--!strict
-- Seeded Park-Miller generator. Same seed, same battle, in Studio and in Lune,
-- which is what lets the simulator and replays reproduce server results.

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	return setmetatable({ state = state }, Rng)
end

-- Uniform float in [0, 1).
function Rng.next(self: Rng): number
	self.state = (self.state * MULTIPLIER) % MODULUS
	return (self.state - 1) / (MODULUS - 1)
end

-- Uniform integer in [low, high].
function Rng.integer(self: Rng, low: number, high: number): number
	return low + math.floor(self:next() * (high - low + 1))
end

function Rng.chance(self: Rng, probability: number): boolean
	return self:next() < probability
end

return Rng
