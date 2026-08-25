-- Wheel & Code Hub - auto redeem codes + auto spin (Wheel of Luck / Glory / Odyssey Wish)
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

local function saveConfig()
	if writefile then
		pcall(function()
			writefile(CONFIG_FILE, HttpService:JSONEncode({
				codes = running.codes and true or false,
				luck = running.luck and true or false,
				glory = running.glory and true or false,
				odyssey = running.odyssey and true or false,
			}))
		end)
	end
end

local cfg = loadConfig() or { codes = true, luck = true, glory = true, odyssey = true }

getgenv().WHEEL_HUB_FLAGS = {}
local running = getgenv().WHEEL_HUB_FLAGS
running.codes, running.luck, running.glory, running.odyssey = cfg.codes == true, cfg.luck == true, cfg.glory == true, cfg.odyssey == true

local function mine()
	return getgenv().WHEEL_HUB_SESSION == session
end

local Framework = require(ReplicatedStorage:WaitForChild("Framework"))
local Modules = Framework.Modules

local CodesRF = ReplicatedStorage.Framework.Systems.CodesSystem:WaitForChild("CodesRF")
local SeasonRemote = ReplicatedStorage.Framework.Features.SeasonSystem:WaitForChild("SeasonUtil"):WaitForChild("RemoteEvent")
local HonorRemote = ReplicatedStorage.Framework.Features.HonorSystem:WaitForChild("RemoteEvent")
local EventHallRE = ReplicatedStorage.Framework.Gameplay.EventHallSystem:WaitForChild("EventHallRE")
local HonorConfig = require(ReplicatedStorage.Framework.Features.HonorSystem:WaitForChild("HonorConfig"))

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
}

local Status = Tab:Paragraph({ Title = "Tasks", Desc = "..." })
local function renderStatus()
	pcall(function()
		Status:SetDesc(table.concat({
			("Codes: %s"):format(taskState.codes),
			("Wheel of Luck: %s"):format(taskState.luck),
			("Wheel of Glory: %s"):format(taskState.glory),
			("Odyssey Wish: %s"):format(taskState.odyssey),
		}, "\n"))
	end)
end
local function setTask(key, text)
	taskState[key] = text
	renderStatus()
end
renderStatus()

local codesToggle, luckToggle, gloryToggle, odysseyToggle

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

if running.codes then task.spawn(redeemLoop) end
if running.luck then task.spawn(luckLoop) end
if running.glory then task.spawn(gloryLoop) end
if running.odyssey then task.spawn(odysseyLoop) end

notify("Hub loaded", "RightShift to toggle menu - config auto-saves")
