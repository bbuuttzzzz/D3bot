D3bot.Handlers.Undead_Fallback = D3bot.Handlers.Undead_Fallback or {}
local HANDLER = D3bot.Handlers.Undead_Fallback

HANDLER.AngOffshoot = 45
HANDLER.BotTgtFixationDistMin = 250
HANDLER.BotClasses = {
	"Zombie", "Fresh Dead", "Bloated Zombie", "Skeletal Walker",
	"Poison Zombie", "Bot Hunter"
}
HANDLER.BotMiniBosses = {
	"Nightmare", "Butcher", "Fast Zombie"
}

HANDLER.Fallback = true
function HANDLER.SelectorFunction(zombieClassName, team)
	return team == TEAM_UNDEAD
end

function HANDLER.UpdateBotCmdFunction(bot, cmd)
	cmd:ClearButtons()
	cmd:ClearMovement()

	-- Fix knocked down bots from sliding around. (Workaround for the NoxiousNet codebase, as ply:Freeze() got removed from status_knockdown, status_revive, ...)
	if bot.KnockedDown and IsValid(bot.KnockedDown) or bot.Revive and IsValid(bot.Revive) then
		return
	end

	if not bot:Alive() then
		-- Get back into the game
		cmd:SetButtons(IN_ATTACK)
		return
	end

	bot:D3bot_UpdatePathProgress()
	D3bot.Basics.SuicideOrRetarget(bot)

	local result, actions, forwardSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.PounceAuto(bot)
	if not result then
		result, actions, forwardSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
		if not result then
			return
		end
	end

	local buttons
	if actions then
		buttons = bit.bor(actions.Forward and IN_FORWARD or 0, actions.Backward and IN_BACKWARD or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0)
	end

	if majorStuck and GAMEMODE:GetWaveActive() then bot:Kill() end

	bot:SetEyeAngles(aimAngle)
	cmd:SetViewAngles(aimAngle)
	cmd:SetForwardMove(forwardSpeed)
	cmd:SetButtons(buttons)
end

function HANDLER.ThinkFunction(bot)
	local mem = bot.D3bot_Mem

	local botPos = bot:GetPos()

	if mem.nextUpdateSurroundingPlayers and mem.nextUpdateSurroundingPlayers < CurTime() or not mem.nextUpdateSurroundingPlayers then
		if not mem.TgtOrNil or IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(botPos) > HANDLER.BotTgtFixationDistMin then
			mem.nextUpdateSurroundingPlayers = CurTime() + 1
			local targets = player.GetAll() -- TODO: Filter targets before sorting
			table.sort(targets, function(a, b) return botPos:Distance(a:GetPos()) < botPos:Distance(b:GetPos()) end)
			for k, v in ipairs(targets) do
				if IsValid(v) and botPos:Distance(v:GetPos()) < 500 and HANDLER.CanBeTgt(bot, v) and bot:D3bot_CanSeeTarget(nil, v) then
					bot:D3bot_SetTgtOrNil(v, false, nil)
					mem.nextUpdateSurroundingPlayers = CurTime() + 5
					break
				end
				if k > 3 then break end
			end
		end
	end

	if mem.nextCheckTarget and mem.nextCheckTarget < CurTime() or not mem.nextCheckTarget then
		mem.nextCheckTarget = CurTime() + 1
		if not HANDLER.CanBeTgt(bot, mem.TgtOrNil) then
			HANDLER.RerollTarget(bot)
		end
	end

	if mem.nextUpdateOffshoot and mem.nextUpdateOffshoot < CurTime() or not mem.nextUpdateOffshoot then
		mem.nextUpdateOffshoot = CurTime() + 0.4 + math.random() * 0.2
		bot:D3bot_UpdateAngsOffshoot(HANDLER.AngOffshoot)
	end

	local function pathCostFunction(node, linkedNode, link)
		local linkMetadata = D3bot.LinkMetadata[link]
		local linkPenalty = linkMetadata and linkMetadata.ZombieDeathCost or 0
		return linkPenalty * (mem.ConsidersPathLethality and 1 or 0)
	end
	if mem.nextUpdatePath and mem.nextUpdatePath < CurTime() or not mem.nextUpdatePath then
		mem.nextUpdatePath = CurTime() + 0.9 + math.random() * 0.2
		bot:D3bot_UpdatePath(pathCostFunction, nil)
	end
end

function HANDLER.OnTakeDamageFunction(bot, dmg)
	local attacker = dmg:GetAttacker()
	if not HANDLER.CanBeTgt(bot, attacker) then return end
	local mem = bot.D3bot_Mem
	if IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(bot:GetPos()) <= HANDLER.BotTgtFixationDistMin then return end
	mem.TgtOrNil = attacker
	--bot:Say("Ouch! Fuck you "..attacker:GetName().."! I'm gonna kill you!")
end

function HANDLER.OnDoDamageFunction(bot, dmg)
	local mem = bot.D3bot_Mem
	--bot:Say("Gotcha!")
end

function HANDLER.OnDeathFunction(bot)
	--bot:Say("rip me!")
	bot:D3bot_RerollClass(HANDLER.BotClasses)

	bot:D3bot_RerollMiniboss(HANDLER.BotMiniBosses)

	HANDLER.RerollTarget(bot)
end

-----------------------------------
-- Custom functions and settings --
-----------------------------------

local potTargetEntClasses = {"prop_*turret", "prop_arsenalcrate", "prop_manhack*"}
local potEntTargets = nil
function HANDLER.CanBeTgt(bot, target)
	if not target or not IsValid(target) then return end
	if IsValid(target) and target:IsPlayer() and target ~= bot and target:Team() ~= TEAM_UNDEAD and target:GetObserverMode() == OBS_MODE_NONE and target:Alive() then return true end
	if potEntTargets and table.HasValue(potEntTargets, target) then return true end
end

function HANDLER.RerollTarget(bot)
	-- Get humans or non zombie players or any players in this order
	local players = D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_HUMAN))
	if #players == 0 and TEAM_UNDEAD then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
		players = D3bot.From(players):Where(function(k, v) return v:Team() ~= TEAM_UNDEAD end).R
	end
	if #players == 0 then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
	end
	potEntTargets = D3bot.GetEntsOfClss(potTargetEntClasses)
	local potTargets = table.Add(players, potEntTargets)
	bot:D3bot_SetTgtOrNil(table.Random(potTargets), false, nil)
end
