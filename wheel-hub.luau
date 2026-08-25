-- Wheel & Code Hub - auto redeem codes + auto spin (Wheel of Luck / Glory / Odyssey Wish) + auto claim update log rewards
-- Prologue version: auto select Heavy Weapon (retries until server registers) + auto Skip Tutorial (retries until Roblox teleport starts)
-- Config auto-saves to disk (bound to your machine, not your account). All features default ON.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local session = (getgenv().WHEEL_HUB_SESSION or 0) + 1
getgenv().WHEEL_HUB_SESSION = session

local CONFIG_FILE = "wheel_hub_config.json"

local function loadConfig()
	if writefile and readfile and isfile and isfile(CONFIG_FILE) then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(CONFIG_FILE))
		end)
		if ok and type(data) == "table" then
			return data
		end
	end
	return nil
end

local cfg = loadConfig() or { codes = true, luck = true, glory = true, odyssey = true }

getgenv().WHEEL_HUB_FLAGS = {}
local running = getgenv().WHEEL_HUB_FLAGS
running.codes, running.luck, running.glory, running.odyssey = cfg.codes == true, cfg.luck == true, cfg.glory == true, cfg.odyssey == true
running.updatelog = true
running.heavy = cfg.heavy ~= false
running.skip = cfg.skip ~= false

local function mine()
	return getgenv().WHEEL_HUB_SESSION == session
end

local function saveConfig()
	if writefile then
		pcall(function()
			writefile(CONFIG_FILE, HttpService:JSONEncode({
				codes = running.codes and true or false,
				luck = running.luck and true or false,
				glory = running.glory and true or false,
				odyssey = running.odyssey and true or false,
				heavy = running.heavy and true or false,
				skip = running.skip and true or false,
			}))
		end)
	end
end

--------------------------------------------------------------------
-- PLACE DETECTION: the Prologue is its own place inside this universe
--------------------------------------------------------------------
local PLACE_IDS = nil
pcall(function()
	PLACE_IDS = require(ReplicatedStorage.Utility.GamePlaceUtil.PlaceConfig).LIVE.PLACE_IDS
end)
local PROLOGUE_ID = PLACE_IDS and PLACE_IDS.Prologue or 76701861705540
local IS_PROLOGUE = game.PlaceId == PROLOGUE_ID

local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function sweepOldGuis()
	local roots = {}
	local ok, hui = pcall(function() return gethui() end)
	if ok and hui then table.insert(roots, hui) end
	table.insert(roots, game:GetService("CoreGui"))
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if pg then table.insert(roots, pg) end
	for _, parent in ipairs(roots) do
		for _, g in ipairs(parent:GetChildren()) do
			if (g:IsA("ScreenGui") or g:IsA("Folder")) and (g.Name:find("WindUI") or g.Name:find("ftgs")) then
				g:Destroy()
			end
		end
	end
end
sweepOldGuis()

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local function notify(title, content)
	pcall(function()
		WindUI:Notify({ Title = title, Content = content, Duration = 4, Icon = "info" })
	end)
end

--------------------------------------------------------------------
-- PROLOGUE MODE: pick Heavy Weapon, then skip straight back to Lobby
--------------------------------------------------------------------
if IS_PROLOGUE then
	local EquipmentRE = ReplicatedStorage.Framework.Gameplay.EquipmentSystem:WaitForChild("EquipmentRE")
	local WorldRemote = ReplicatedStorage.Framework.Gameplay.WorldPlace:WaitForChild("WorldUtil"):WaitForChild("RemoteEvent")
	local PrologueRemote = ReplicatedStorage.Framework.Gameplay.PrologueSysem:WaitForChild("PrologueUtil"):WaitForChild("RemoteEvent")
	local KeyString = require(ReplicatedStorage:WaitForChild("Enum"):WaitForChild("KeyString"))
	local DataUtil = require(ReplicatedStorage:WaitForChild("Framework")).Modules.DataUtil

	local HEAVY_KEY = 2 -- DefaultWeapon[2] = Heavy_Hammer (Damage/Tank); [1] BroadSword light, [3] Staff ancient
	local HEAVY_FLAG = { KeyString.EquipmentUtil.Equipment, KeyString.EquipmentUtil.GetDefaultWeapon }

	local Window = WindUI:CreateWindow({
		Title = "Wheel & Code Hub [Prologue]",
		Icon = "dices",
		Author = "auto heavy weapon + skip tutorial",
		Size = UDim2.fromOffset(520, 340),
		Theme = "Dark",
		ToggleKey = Enum.KeyCode.RightShift,
	})

	local Tab = Window:Tab({ Title = "Prologue", Icon = "zap" })

	local taskState = {
		heavy = running.heavy and "starting..." or "off",
		skip = running.skip and "waiting for weapon..." or "off",
	}

	local Status = Tab:Paragraph({ Title = "Tasks", Desc = "..." })
	local function renderStatus()
		pcall(function()
			Status:SetDesc(table.concat({
				("Heavy Weapon: %s"):format(taskState.heavy),
				("Skip Tutorial: %s"):format(taskState.skip),
			}, "\n"))
		end)
	end
	local function setTask(key, text)
		taskState[key] = text
		renderStatus()
	end
	renderStatus()

	local teleportStarted = false
	if getgenv().WHEEL_HUB_TPCONN then
		pcall(function() getgenv().WHEEL_HUB_TPCONN:Disconnect() end)
	end
	getgenv().WHEEL_HUB_TPCONN = LocalPlayer.OnTeleport:Connect(function(state)
		local s = tostring(state) -- avoid Enum.PlayerTeleportState: not resolvable in some executor sandboxes
		if s:find("Started", 1, true) or s == "0" or tonumber(s) == 0 then
			teleportStarted = true
		end
	end)

	local function heavyRegistered()
		local v = false
		pcall(function()
			v = DataUtil:GetValue(LocalPlayer, HEAVY_FLAG) == true
		end)
		return v
	end

	local function heavyLoop()
		local attempts = 0
		while running.heavy and mine() do
			if heavyRegistered() then
				setTask("heavy", "registered - Heavy Hammer equipped")
				notify("Prologue", "Heavy Weapon registered")
				return true
			end
			attempts += 1
			pcall(function()
				EquipmentRE:FireServer("SelectDefaultWeapon", HEAVY_KEY)
			end)
			setTask("heavy", ("selecting Heavy Weapon (%d)..."):format(attempts))
			task.wait(0.45) -- server cooldown on EquipmentCmd is 0.2s, stay above it
		end
		return heavyRegistered()
	end

	local function prologueOver()
		local ok, v = pcall(function()
			return LocalPlayer:GetAttribute("PrologueOver")
		end)
		return ok and v == true
	end

	-- The game only registers the prologue as complete when the server receives
	-- "PrologueAnimEnd" (sets Prologue.AllOver -> PrologueOver attribute). Skipping
	-- without this makes the lobby bounce you straight back into the prologue.
	local function markPrologueDone()
		local attempts = 0
		while running.skip and mine() do
			if prologueOver() then
				setTask("skip", "prologue registered complete")
				return true
			end
			attempts += 1
			pcall(function()
				PrologueRemote:FireServer("PrologueAnimEnd")
			end)
			setTask("skip", ("registering prologue completion (%d)..."):format(attempts))
			task.wait(1)
			if attempts >= 30 and not prologueOver() then
				setTask("skip", "server not confirming - skip aborted (no teleport)")
				notify("Prologue", "Could not register completion - skip aborted")
				return false
			end
		end
		return prologueOver()
	end

	local function skipLoop()
		-- step 1: register completion FIRST, otherwise the game bounces you back
		if not markPrologueDone() then
			return
		end
		local attempts = 0
		while running.skip and mine() and not teleportStarted and attempts < 10 do
			attempts += 1
			pcall(function()
				WorldRemote:FireServer("BackLobby")
			end)
			setTask("skip", ("BackLobby sent (%d), waiting for teleport..."):format(attempts))
			local t0 = os.clock()
			while os.clock() - t0 < 3 do
				if teleportStarted or not mine() then break end
				task.wait(0.15)
			end
		end
		if teleportStarted or game.PlaceId ~= PROLOGUE_ID then
			setTask("skip", "teleport to Lobby started - done")
			notify("Prologue", "Teleporting to Lobby")
		else
			setTask("skip", "stopped")
		end
	end

	Tab:Toggle({
		Title = "Auto Select Heavy Weapon",
		Desc = "Damage/Tank - retries until server confirms",
		Value = running.heavy,
		Callback = function(state)
			running.heavy = state
			saveConfig()
			if state then task.spawn(heavyLoop) end
		end,
	})

	Tab:Toggle({
		Title = "Auto Skip Tutorial",
		Desc = "Registers completion first, then BackLobby",
		Value = running.skip,
		Callback = function(state)
			running.skip = state
			saveConfig()
			if state then task.spawn(skipLoop) end
		end,
	})

	if running.heavy then task.spawn(heavyLoop) end
	if running.skip then
		task.spawn(function()
			-- gate the skip on the weapon being registered first (per flow),
			-- unless the weapon task was turned off entirely
			while running.heavy and mine() and not heavyRegistered() do
				task.wait(0.3)
			end
			if mine() then skipLoop() end
		end)
	end

	notify("Hub loaded [Prologue]", "RightShift to toggle menu")
	return
end

--------------------------------------------------------------------
-- MAIN PLACE MODE: codes, wheels, update log
--------------------------------------------------------------------
local Framework = require(ReplicatedStorage:WaitForChild("Framework"))
local Modules = Framework.Modules

local CodesRF = ReplicatedStorage.Framework.Systems.CodesSystem:WaitForChild("CodesRF")
local SeasonRemote = ReplicatedStorage.Framework.Features.SeasonSystem:WaitForChild("SeasonUtil"):WaitForChild("RemoteEvent")
local HonorRemote = ReplicatedStorage.Framework.Features.HonorSystem:WaitForChild("RemoteEvent")
local EventHallRE = ReplicatedStorage.Framework.Gameplay.EventHallSystem:WaitForChild("EventHallRE")
local HonorConfig = require(ReplicatedStorage.Framework.Features.HonorSystem:WaitForChild("HonorConfig"))

local UpdateLogRemote = ReplicatedStorage.Framework.Features.UpdateLogSystem:WaitForChild("RemoteEvent")
local UpdateLogConfig = require(ReplicatedStorage.Configs:WaitForChild("ResUpdateLog"))
local KeyString = require(ReplicatedStorage.Enum:WaitForChild("KeyString"))

local DataUtil = Modules.DataUtil
local CurrencyUtil = Modules.CurrencyUtil
local SeasonLotteryUtil = Modules.SeasonLotteryUtil

local CODES = {
	"AAM",
	"Uzi",
	"TT_Mentally_ill_K.N",
	"luknojo",
	"Zeny",
	"Maple",
	"Fujiesane",
	"T3nsei",
	"Ghifa",
	"runekify",
	"Ahjughh",
	"ROYALCIRCUS",
	"SCYTHEANDNEWMAP",
}

local RESPONSES = {
	Success = "Code Redeemed!",
	AlreadyUsed = "Already Used",
	AlreadyDiscord = "Discord code already used",
	Nonexistent = "Code Not Found",
	Failed = "Code Failed",
	LimitReached = "Code Limit Reached",
	Unavailable = "Main place only",
	NotStarted = "Not active yet",
	Expired = "Expired",
	InvalidTimeConfig = "Unavailable",
	InvalidInput = "Invalid code",
	Cooldown = "Cooldown",
	Busy = "Server busy",
}

local Window = WindUI:CreateWindow({
	Title = "Wheel & Code Hub",
	Icon = "dices",
	Author = "auto codes + auto spins",
	Size = UDim2.fromOffset(520, 420),
	Theme = "Dark",
	ToggleKey = Enum.KeyCode.RightShift,
})

local Tab = Window:Tab({ Title = "Auto", Icon = "zap" })

local taskState = {
	codes = running.codes and "starting..." or "off",
	luck = running.luck and "starting..." or "off",
	glory = running.glory and "starting..." or "off",
	odyssey = running.odyssey and "starting..." or "off",
	updatelog = "starting...",
}

local Status = Tab:Paragraph({ Title = "Tasks", Desc = "..." })
local function renderStatus()
	pcall(function()
		Status:SetDesc(table.concat({
			("Codes: %s"):format(taskState.codes),
			("Wheel of Luck: %s"):format(taskState.luck),
			("Wheel of Glory: %s"):format(taskState.glory),
			("Odyssey Wish: %s"):format(taskState.odyssey),
			("Update Log: %s"):format(taskState.updatelog),
		}, "\n"))
	end)
end
local function setTask(key, text)
	taskState[key] = text
	renderStatus()
end
renderStatus()

local codesToggle, luckToggle, gloryToggle, odysseyToggle, updatelogToggle

local function redeemLoop()
	local redeemed, used, other = 0, 0, 0
	for i, code in ipairs(CODES) do
		if not (running.codes and mine()) then break end
		local attempts = 0
		while running.codes and mine() and attempts < 10 do
			local ok, res = pcall(function()
				return CodesRF:InvokeServer("RedeemCode", code)
			end)
			if not ok then
				other += 1
				setTask("codes", ("[%d/%d] %s: error"):format(i, #CODES, code))
				break
			end
			res = trim(tostring(res or ""))
			if res == "Cooldown" or res == "Busy" then
				attempts += 1
				setTask("codes", ("[%d/%d] %s: %s, retrying (%d)"):format(i, #CODES, code, RESPONSES[res] or res, attempts))
				task.wait(res == "Cooldown" and 5 or 3)
			else
				if res == "Success" then
					redeemed += 1
				elseif res == "AlreadyUsed" or res == "AlreadyDiscord" then
					used += 1
				else
					other += 1
				end
				setTask("codes", ("[%d/%d] %s: %s"):format(i, #CODES, code, RESPONSES[res] or res))
				break
			end
		end
		task.wait(0.4)
	end
	if mine() and running.codes then
		setTask("codes", ("done: %d redeemed, %d already used, %d failed (reruns on rejoin)"):format(redeemed, used, other))
		notify("Codes", ("%d redeemed, %d already used, %d failed"):format(redeemed, used, other))
	end
end

local function luckLoop()
	while running.luck and mine() do
		local can = true
		pcall(function() can = SeasonLotteryUtil:CanBuySeasonLottery(LocalPlayer, 1) end)
		if not can then
			setTask("luck", "waiting for tickets...")
			task.wait(3)
		else
			SeasonRemote:FireServer("TrySeasonLottery", 1)
			setTask("luck", "spinning...")
			task.wait(1.5)
		end
	end
end

local function gloryLoop()
	local cost = tonumber(HonorConfig.SINGLE_SPIN_COST) or 0
	while running.glory and mine() do
		local gem = 0
		pcall(function()
			local pd = DataUtil:GetPlayerData(LocalPlayer)
			gem = (pd and pd.Currency and pd.Currency.Gem) or 0
		end)
		if gem < cost then
			setTask("glory", "waiting for gems...")
			task.wait(3)
		else
			HonorRemote:FireServer("HonorSpin", 1)
			setTask("glory", "spinning...")
			task.wait(1.5)
		end
	end
end

local function odysseyLoop()
	while running.odyssey and mine() do
		local tickets = 0
		pcall(function() tickets = CurrencyUtil:GetCount(LocalPlayer, "GachaTicket") or 0 end)
		if tickets < 1 then
			setTask("odyssey", "waiting for tickets...")
			task.wait(3)
		else
			EventHallRE:FireServer("GachaDraw", "Odyssey", 1)
			setTask("odyssey", "spinning...")
			task.wait(3)
		end
	end
end

local UPDATELOG_IDS = UpdateLogConfig.__index or {}

local function getClaimedTable()
	local claimed = nil
	pcall(function()
		claimed = DataUtil:GetValue(LocalPlayer, {KeyString.UpdateLogUtil.UpdateLog}) or {}
	end)
	return claimed or {}
end

local function countClaimed(claimed)
	local n = 0
	for _, id in ipairs(UPDATELOG_IDS) do
		if claimed[id] then n += 1 end
	end
	return n
end

local function updatelogLoop()
	local total = #UPDATELOG_IDS
	local tried = {}
	while running.updatelog and mine() do
		local claimed = getClaimedTable()
		local done = countClaimed(claimed)
		if done >= total then
			setTask("updatelog", ("%d/%d rewards claimed - all done"):format(done, total))
			break
		end
		local pending
		for _, id in ipairs(UPDATELOG_IDS) do
			if not claimed[id] and (tried[id] or 0) < 3 then
				pending = id
				break
			end
		end
		if not pending then
			setTask("updatelog", ("%d/%d claimed, %d failed"):format(done, total, total - done))
			break
		end
		tried[pending] = (tried[pending] or 0) + 1
		setTask("updatelog", ("claiming %s (%d/%d)..."):format(pending, done, total))
		pcall(function()
			UpdateLogRemote:FireServer("ClaimReward", pending)
		end)
		task.wait(1)
	end
	if mine() and running.updatelog then
		local claimed = getClaimedTable()
		local done = countClaimed(claimed)
		notify("Update Log", ("%d/%d rewards claimed"):format(done, #UPDATELOG_IDS))
	end
end

codesToggle = Tab:Toggle({
	Title = "Auto Redeem Codes",
	Desc = ("%d codes queued"):format(#CODES),
	Value = running.codes,
	Callback = function(state)
		running.codes = state
		saveConfig()
		if state then task.spawn(redeemLoop) end
	end,
})

luckToggle = Tab:Toggle({
	Title = "Auto Spin - Wheel of Luck",
	Desc = "Season Lucky Tickets",
	Value = running.luck,
	Callback = function(state)
		running.luck = state
		saveConfig()
		if state then task.spawn(luckLoop) end
	end,
})

gloryToggle = Tab:Toggle({
	Title = "Auto Spin - Wheel of Glory",
	Desc = "Costs Gems",
	Value = running.glory,
	Callback = function(state)
		running.glory = state
		saveConfig()
		if state then task.spawn(gloryLoop) end
	end,
})

odysseyToggle = Tab:Toggle({
	Title = "Auto Spin - Odyssey Wish",
	Desc = "Costs Gacha Tickets",
	Value = running.odyssey,
	Callback = function(state)
		running.odyssey = state
		saveConfig()
		if state then task.spawn(odysseyLoop) end
	end,
})

updatelogToggle = Tab:Toggle({
	Title = "Auto Claim Update Log Rewards",
	Desc = "Claims every version's rewards once",
	Value = true,
	Callback = function(state)
		running.updatelog = state
		if state then task.spawn(updatelogLoop) end
	end,
})

if running.codes then task.spawn(redeemLoop) end
if running.luck then task.spawn(luckLoop) end
if running.glory then task.spawn(gloryLoop) end
if running.odyssey then task.spawn(odysseyLoop) end
if running.updatelog then task.spawn(updatelogLoop) end

notify("Hub loaded", "RightShift to toggle menu - config auto-saves")
