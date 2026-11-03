--// Vehicle Hub (Vehicle Mods + ESP + ECU + Status Vehicle + Teleport + Settings + Config) -- UI: WindUI
--// กดปุ่มซ่อน/แสดงเมนู (ค่าเริ่มต้น RightShift) ตั้งใหม่ได้ในหน้า Settings
--// คอนฟิกเก็บที่ VehicleHub/<PlaceId>/ชื่อ.json (แยกตามเกม)

local KEY_STACK = 2 -- กด Auto Boost (W) พร้อมปุ่มกระตุ้นบูสต์ = แรงคูณเท่านี้

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService = game:GetService("HttpService")
local lplr = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.__VehicleHubCleanup then
	pcall(env.__VehicleHubCleanup)
end

local WindUI
do
	local okLib, lib = pcall(function()
		return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
	end)
	if not okLib or not lib then
		warn("[VehicleHub] โหลด WindUI ไม่ได้: " .. tostring(lib))
		return
	end
	WindUI = lib
end

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

--// ค่าตั้งต้น (power 20 = แรงเท่าสคริปต์เดิม)
local cfg = {
	maxSpeed = 280,
	autoBoost = false,
	key = Enum.KeyCode.X,
	power = 100,
	drift = 0,
	grip = 0,
	control = 0,
	smooth = 20,
	stable = 0,
	brakeOn = false,
	brake = 200, -- 10 ถึง 1000 (ลดความเร็ว = ค่า x 0.5 studs/s ต่อวินาที)
	uiKey = Enum.KeyCode.RightShift,
	fastMenu = false,
	autoSave = false,
	statusOn = false,
	espName = false,
	espChams = false,
	espHP = false,
	espMoney = false,
	speedOn = false,
	espSpeed = false,
	ecuLink = false,
	antiPause = false,
	nameHide = false, -- ไม่เซฟลงไฟล์ เริ่มต้นปิดทุกครั้ง
}

local conns = {}
local function bind(sig, fn)
	local c = sig:Connect(fn)
	conns[#conns + 1] = c
	return c
end

----------------------------------------------------------------
-- Config: บันทึก / โหลด / ลบ / Autoload / Auto Save
----------------------------------------------------------------
local function has(f)
	return typeof(f) == "function"
end
local FS = has(writefile) and has(readfile) and has(isfile) and has(isfolder) and has(makefolder) and has(listfiles)

local ROOT = "VehicleHub"
local DIR = ROOT .. "/" .. tostring(game.PlaceId)
local AUTO_PATH = DIR .. "/_autoload.txt"

--// ค่าที่เซฟลงไฟล์ (t: num / bool / key)
local SCHEMA = {
	{ k = "maxSpeed", t = "num", min = 10, max = 5000 },
	{ k = "autoBoost", t = "bool" },
	{ k = "key", t = "key" },
	{ k = "power", t = "num", min = 1, max = 1000 },
	{ k = "drift", t = "num", min = 0, max = 10 },
	{ k = "grip", t = "num", min = 0, max = 10 },
	{ k = "control", t = "num", min = 0, max = 10 },
	{ k = "smooth", t = "num", min = 1, max = 1000 },
	{ k = "stable", t = "num", min = 0, max = 10 },
	{ k = "brakeOn", t = "bool" },
	{ k = "brake", t = "num", min = 10, max = 1000 },
	{ k = "uiKey", t = "key" },
	{ k = "fastMenu", t = "bool" },
	{ k = "autoSave", t = "bool" },
	{ k = "statusOn", t = "bool" },
	{ k = "espName", t = "bool" },
	{ k = "espChams", t = "bool" },
	{ k = "espHP", t = "bool" },
	{ k = "espMoney", t = "bool" },
	{ k = "speedOn", t = "bool" },
	{ k = "espSpeed", t = "bool" },
	{ k = "ecuLink", t = "bool" },
	{ k = "antiPause", t = "bool" },
}

local alive = true
local selected = nil -- ชื่อคอนฟิกที่ Select อยู่
local autoloadName = nil -- ชื่อคอนฟิกที่ตั้ง Autoload (1 อันต่อเกม)
local painters = {} -- ฟังก์ชันวาด UI ใหม่ตามค่า cfg (ใช้ตอน Load)
local ui = { sync = function() end }
local painting = false
local function repaintAll()
	painting = true
	for _, p in ipairs(painters) do
		pcall(p)
	end
	painting = false
end

local function setStatus(text)
	pcall(function()
		WindUI:Notify({ Title = "Vehicle Hub", Content = tostring(text), Duration = 3 })
	end)
end

local function sanitize(s)
	s = tostring(s or ""):gsub('[\\/:*?"<>|%c]', "")
	s = s:match("^[%s_%.]*(.-)%s*$") or ""
	local n = utf8.len(s)
	if n and n > 32 then
		s = s:sub(1, (utf8.offset(s, 33) or (#s + 1)) - 1)
	end
	return s
end

local function cfgPath(name)
	return DIR .. "/" .. name .. ".json"
end

local function fileExists(p)
	local ok, ex = pcall(isfile, p)
	return ok and ex == true
end

local function ensureDir()
	pcall(function()
		if not isfolder(ROOT) then
			makefolder(ROOT)
		end
	end)
	pcall(function()
		if not isfolder(DIR) then
			makefolder(DIR)
		end
	end)
end

local function encodeCfg()
	local t = {}
	for _, s in ipairs(SCHEMA) do
		local v = cfg[s.k]
		if s.t == "key" then
			v = v.Name
		end
		t[s.k] = v
	end
	return HttpService:JSONEncode(t)
end

local function applyData(t)
	for _, s in ipairs(SCHEMA) do
		local v = t[s.k]
		if s.t == "num" then
			if type(v) == "number" and v == v then
				cfg[s.k] = clamp(math.floor(v + 0.5), s.min, s.max)
			end
		elseif s.t == "bool" then
			if type(v) == "boolean" then
				cfg[s.k] = v
			end
		elseif s.t == "key" then
			if type(v) == "string" then
				local ok, kc = pcall(function()
					return Enum.KeyCode[v]
				end)
				if ok and kc then
					cfg[s.k] = kc
				end
			end
		end
	end
end

local function saveConfig(name)
	if not FS then
		return false
	end
	ensureDir()
	local ok = pcall(writefile, cfgPath(name), encodeCfg())
	return ok
end

local function loadConfig(name)
	if not FS then
		return false, "executor ไม่รองรับ"
	end
	local p = cfgPath(name)
	if not fileExists(p) then
		return false, "ไม่พบไฟล์"
	end
	local okR, raw = pcall(readfile, p)
	if not okR then
		return false, "อ่านไฟล์ไม่ได้"
	end
	local okJ, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not okJ or type(data) ~= "table" then
		return false, "ไฟล์เสีย"
	end
	applyData(data)
	repaintAll()
	return true
end

local function deleteConfig(name)
	if not (FS and has(delfile)) then
		return false
	end
	return (pcall(delfile, cfgPath(name)))
end

local function listConfigs()
	local out = {}
	if not FS then
		return out
	end
	ensureDir()
	local ok, files = pcall(listfiles, DIR)
	if not ok or type(files) ~= "table" then
		return out
	end
	for _, f in ipairs(files) do
		local n = tostring(f):match("([^/\\]+)%.json$")
		if n and n:sub(1, 1) ~= "_" then
			out[#out + 1] = n
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

local function readAutoload()
	if not FS or not fileExists(AUTO_PATH) then
		return nil
	end
	local ok, s = pcall(readfile, AUTO_PATH)
	if not ok or type(s) ~= "string" then
		return nil
	end
	s = s:match("^%s*(.-)%s*$")
	if s == "" then
		return nil
	end
	return s
end

--// name = nil -> ล้าง Autoload
local function writeAutoload(name)
	if not FS then
		return false
	end
	ensureDir()
	if name then
		return (pcall(writefile, AUTO_PATH, name))
	end
	if has(delfile) then
		return (pcall(delfile, AUTO_PATH))
	end
	return (pcall(writefile, AUTO_PATH, ""))
end

--// Auto Save: เซฟลงคอนฟิกที่ Select อยู่ (ไม่มี = default) หลังหยุดแก้ 1 วินาที
local saveToken = 0
local function changed()
	if not (cfg.autoSave and FS) then
		return
	end
	saveToken = saveToken + 1
	local t = saveToken
	task.delay(1, function()
		if alive and t == saveToken then
			local name = selected or "default"
			if saveConfig(name) then
				selected = name
				ui.sync()
			end
		end
	end)
end

----------------------------------------------------------------
-- Fast Menu: กดค้างปุ่มโต้ตอบ (ProximityPrompt) แล้วทำงานทันที
----------------------------------------------------------------
bind(ProximityPromptService.PromptButtonHoldBegan, function(prompt)
	if cfg.fastMenu and fireproximityprompt then
		pcall(fireproximityprompt, prompt)
	end
end)

----------------------------------------------------------------
-- ECU Link: จูนกราฟ AIR หรือ FUEL อันเดียว ให้ส่งค่าเดียวกันทั้งสองอัน
-- ดักตอนเกมยิง ECUTune_Save (arg 2 = AIR, arg 3 = FUEL) แล้วคัดลอกกราฟที่ถูกแก้ไปอีกอัน
----------------------------------------------------------------
local ecuLastA, ecuLastB
local ecuSeq, ecuBypass = 0, false -- ecuSeq = เลขลำดับล่าสุดที่เกมส่ง (arg 5), ecuBypass = ข้าม Link ตอน Auto Tune

local function ecuSame(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		local p, q = a[i], b[i]
		if type(p) ~= "table" or type(q) ~= "table" or p[1] ~= q[1] or p[2] ~= q[2] then
			return false
		end
	end
	return true
end

local function ecuClone(t)
	local c = {}
	for i, p in ipairs(t) do
		c[i] = { p[1], p[2] }
	end
	return c
end

local function ecuLinkArgs(args)
	local a, b = args[2], args[3]
	if type(a) ~= "table" or type(b) ~= "table" then
		return
	end
	if not ecuSame(a, b) then
		-- ดูว่าอันไหนถูกแก้เทียบกับครั้งก่อน (ครั้งแรก/ไม่แน่ใจ = ใช้ AIR เป็นหลัก)
		local changedA = ecuLastA ~= nil and not ecuSame(a, ecuLastA)
		local changedB = ecuLastB ~= nil and not ecuSame(b, ecuLastB)
		if changedB and not changedA then
			args[2] = ecuClone(b)
		else
			args[3] = ecuClone(a)
		end
	end
	ecuLastA, ecuLastB = ecuClone(args[2]), ecuClone(args[3])
end

env.__VehicleHubEcuFn = function(old, method, self, ...)
	if alive and method == "FireServer" and typeof(self) == "Instance"
		and self.ClassName == "RemoteEvent" and self.Name == "ECUTune_Save" then
		local args = table.pack(...)
		if type(args[5]) == "number" and args[5] > ecuSeq then
			ecuSeq = args[5]
		end
		if cfg.ecuLink and not ecuBypass and type(args[10]) ~= "table" and pcall(ecuLinkArgs, args) then
			if setnamecallmethod then
				setnamecallmethod(method)
			end
			return old(self, table.unpack(args, 1, args.n))
		end
	end
	return old(self, ...)
end

-- ติดตั้ง hook ครั้งเดียวต่อเซสชัน (รันสคริปต์ซ้ำจะใช้ฟังก์ชันใหม่ ไม่ซ้อน hook)
if hookmetamethod and getnamecallmethod and not env.__VehicleHubEcuHooked then
	env.__VehicleHubEcuHooked = true
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local fn = env.__VehicleHubEcuFn
		if fn then
			return fn(oldNamecall, getnamecallmethod(), self, ...)
		end
		return oldNamecall(self, ...)
	end))
end

----------------------------------------------------------------
-- ECU Auto Tune: คำนวณค่าเขียวเข้ม (เกรดสูงสุด) จาก EngineMods.Active ของเกมเอง
-- AIR/FUEL: เกรด 5 (คะแนน >= 0.965, AFR ผิด <= 0.05)  TPS: ผิด <= 0.03  IGN: ผิด <= 0.6 องศา
----------------------------------------------------------------
local function ecuR2(x)
	return math.floor(x * 100 + 0.5) / 100
end

local function ecuGetActive()
	local pg = lplr:FindFirstChild("PlayerGui")
	local itf = pg and pg:FindFirstChild("Interface")
	local bike = itf and itf:FindFirstChild("Bike")
	local car = bike and bike.Value
	if not car then
		return nil, "ไม่ได้นั่งรถ"
	end
	local tuner = car:FindFirstChild("Tuner")
	local modS = tuner and tuner:FindFirstChild("EngineMods")
	if not modS then
		return nil, "ไม่พบ EngineMods"
	end
	local ok, mods = pcall(require, modS)
	if not ok or type(mods) ~= "table" then
		return nil, "require ไม่ได้"
	end
	local a = mods.Active
	if not a or a.Owner ~= itf or not a.IdealFn then
		return nil, "ECU ยังไม่พร้อม (ไม่มี seed)"
	end
	return a, car
end

local function ecuCopy(t)
	local c = {}
	for i, p in ipairs(t or {}) do
		c[i] = { p[1], p[2] }
	end
	return c
end

--// AIR + FUEL
local function ecuBuildAF(a)
	local rpm = a:GetRPMPoints(1000)
	local best = a.Config.AFR.Best
	local air, fuel = {}, {}
	for i, r in ipairs(rpm) do
		local ia, iafr = a.IdealFn(r)
		local av = clamp(math.floor(ia * 100) / 100, 0.6, 1.6)
		air[i] = { r, av }
		fuel[i] = { r, clamp(ecuR2(best * av / iafr), 0.6, 1.6) }
	end
	a:SetMap("Air", air)
	a:SetMap("Fuel", fuel)

	-- ลองค่าใกล้เคียงทีละจุด เลือกอันที่เกรดของเกมสูงสุด
	local function rank(r)
		local g, sc, smp = a:GetTuneGrade(r)
		return g * 100 + sc * 10 - math.abs((smp.AFR or 0) - (smp.BestAFR or 0))
	end
	local DA, DF = { 0, -1, 1, 2 }, { 0, -1, 1 }
	local bad = 0
	for i, r in ipairs(rpm) do
		local ia, iafr = a.IdealFn(r)
		local base = math.floor(ia * 100) / 100
		local bestRank, bestA, bestF = -math.huge, air[i][2], fuel[i][2]
		for _, da in ipairs(DA) do
			local av = clamp(ecuR2(base + da * 0.01), 0.6, 1.6)
			local fx = best * av / iafr
			for _, df in ipairs(DF) do
				local fv = clamp(ecuR2(fx + df * 0.01), 0.6, 1.6)
				air[i][2], fuel[i][2] = av, fv
				local k = rank(r)
				if k > bestRank then
					bestRank, bestA, bestF = k, av, fv
				end
			end
		end
		air[i][2], fuel[i][2] = bestA, bestF
		if (a:GetTuneGrade(r)) < 5 then
			bad = bad + 1
		end
	end
	return air, fuel, bad
end

--// TPS + IGN (IGN คิดจากสถานะ AIR/FUEL ปัจจุบันของรถ)
local function ecuBuildTI(a)
	local rpm = a:GetRPMPoints(1000)
	local tps = {}
	for i, x in ipairs(a:GetTPSPoints()) do
		tps[i] = { x, clamp(ecuR2(a:GetTPSIdealAt(x)), 0.6, 1.6) }
	end
	a:SetTPSMap(tps)

	local bad = 0
	local ign = {}
	for i, r in ipairs(rpm) do
		local s = a:Sample(r, 1)
		local ad = (s.Air or 1) - (s.IdealAir or (s.Air or 1))
		local v = a:GetIgnIdealAt(r, s.AFR, s.BestAFR, nil, ad)
		ign[i] = { r, clamp(ecuR2(v), a.IGN_LO, a.IGN_HI) }
		if math.abs(ign[i][2] - v) > a.IGN_TOL * 0.5 then
			bad = bad + 1
		end
	end
	a:SetIgnMap(ign)
	return tps, ign, bad
end

--// ส่งเข้า ECU แล้วรอผลจากเซิร์ฟเวอร์ (เซิร์ฟเวอร์มีคูลดาวน์ "ส่งถี่เกินไป" ถ้าส่งซ้ำเร็วจะถูกทิ้ง)
local ECU_ERR = {
	rejected = "เจ้าของรถปฏิเสธการจูน",
	expired = "หมดเวลา เจ้าของรถไม่ตอบ",
	gone = "ผู้เล่นหรือรถหายไป",
	ownergone = "เจ้าของรถออกจากเกมแล้ว",
	nomechanic = "เฉพาะช่างในอู่เท่านั้นที่จูนรถผู้อื่นได้",
	notseated = "ต้องนั่งที่นั่งคนขับก่อน",
}

local function ecuSend(car, air, fuel, tps, pop, ign, grid)
	local RS = game:GetService("ReplicatedStorage")
	local remote = RS:FindFirstChild("ECUTune_Save")
	if not remote then
		return false, "ไม่พบ ECUTune_Save"
	end
	local resEv = RS:FindFirstChild("ECUTune_Result")
	local carId = car:GetAttribute("CarId") or car.Name

	for _ = 1, 3 do
		ecuSeq = ecuSeq + 1
		local seq, reason, done = ecuSeq, nil, false
		local cs = {}
		if resEv then
			cs[#cs + 1] = resEv.OnClientEvent:Connect(function(_, sq, why)
				if sq == seq then
					reason = why or "unknown"
				end
			end)
		end
		cs[#cs + 1] = remote.OnClientEvent:Connect(function(_, _, sq)
			if sq == seq then
				done = true
			end
		end)

		ecuBypass = true
		local sent, err = pcall(function()
			if grid then
				remote:FireServer(carId, air, fuel, false, seq, tps, pop, ign, car, grid)
			else
				remote:FireServer(carId, air, fuel, false, seq, tps, pop, ign, car)
			end
		end)
		ecuBypass = false
		if not sent then
			for _, c in ipairs(cs) do
				c:Disconnect()
			end
			return false, err
		end

		local t0 = os.clock()
		while not done and (reason == nil or reason == "waiting") and os.clock() - t0 < 2.5 do
			task.wait(0.1)
		end
		for _, c in ipairs(cs) do
			c:Disconnect()
		end

		if done then
			return true
		elseif reason == nil then
			return true, "ส่งแล้ว (ไม่มีการยืนยัน)"
		elseif reason == "waiting" then
			return true, "รอเจ้าของรถตอบ"
		elseif reason == "cooldown" or reason == "busy" then
			task.wait(3)
		else
			return false, ECU_ERR[reason] or "เซิร์ฟเวอร์ปฏิเสธ"
		end
	end
	return false, "ส่งถี่เกินไป ลองใหม่อีกครั้ง"
end

--// mode: "af" = AIR+FUEL, "ti" = TPS+IGN, "all" = ทั้งสี่กราฟส่งครั้งเดียว
--// (กราฟที่ไม่ได้จูนส่งค่าปัจจุบันของรถไปตามเดิม)
local function ecuAutoTune(mode)
	local a, car = ecuGetActive()
	if not a then
		return false, car
	end
	local ok, air, fuel, tps, ign, bad = pcall(function()
		local air, fuel, tps, ign = nil, nil, nil, nil
		local b1, b2 = 0, 0
		if mode == "af" then
			air, fuel, b1 = ecuBuildAF(a)
			tps, ign = ecuCopy(a.TPSMap), ecuCopy(a.IgnMap)
		elseif mode == "ti" then
			air, fuel = ecuCopy(a.Config.Air and a.Config.Air.Map), ecuCopy(a.Config.Fuel and a.Config.Fuel.Map)
			tps, ign, b2 = ecuBuildTI(a)
		else
			air, fuel, b1 = ecuBuildAF(a)
			tps, ign, b2 = ecuBuildTI(a) -- IGN คิดจาก AIR/FUEL ที่เพิ่งตั้ง
		end
		return air, fuel, tps, ign, b1 + b2
	end)
	if not ok then
		return false, air
	end
	local pop = ecuCopy(a.PopMap or a:GenerateInitialPop())
	local sent, note = ecuSend(car, air, fuel, tps, pop, ign)
	if not sent then
		return false, note
	end
	local msg = bad == 0 and "เขียวครบ" or ("ไม่เขียว " .. bad .. " จุด")
	return true, note and (msg .. " · " .. note) or msg
end

----------------------------------------------------------------
-- Free Tune (ไล่รถ): หาสไลเดอร์ 5 จุด x ย่านรอบ A/B ที่ดีที่สุดภายในแต้มที่มี
-- ผลของสไลเดอร์มาจากเมทริกซ์ของ seed รถ (FT_Seed) ใช้ฟังก์ชันของเกมคำนวณตรง ๆ
-- เป้าหมาย = กำลังเฉลี่ยทั้งย่านรอบ/ความเร็ว x FT_W_POWER + ความเร็วปลาย (หาร 60 km/h) x FT_W_SPEED
-- อยากเน้นความเร็วปลายให้เพิ่ม FT_W_SPEED  อยากเน้นความแรงให้ลดลง
----------------------------------------------------------------
local FT_W_POWER, FT_W_SPEED = 1.0, 0.5

local function ftScore(FT, seed, x)
	local eR, eS = FT.Effects(seed, { x[1], x[2], x[3], x[4], x[5] }, { x[6], x[7], x[8], x[9], x[10] })
	local sr, ss = 0, 0
	for k = 0, 10 do
		local t = k / 10
		sr = sr + 1 + FT.LevelAt(eR, t)
		ss = ss + 1 + FT.LevelAt(eS, t)
	end
	local P = (sr / 11) * (ss / 11)
	local V = FT.SpeedDelta(eR, eS)
	return FT_W_POWER * (P - 1) + FT_W_SPEED * (V / 60), P, V
end

local function ftSearch(FT, seed, budget, cr, cs, start)
	local cost = { cr, cr, cr, cr, cr, cs, cs, cs, cs, cs }
	local function posCost(x)
		local s = 0
		for i = 1, 10 do
			if x[i] > 0 then
				s = s + x[i] * cost[i]
			end
		end
		return s
	end

	local function climb(x)
		local s = ftScore(FT, seed, x)
		local improved = true
		while improved do
			improved = false
			-- ตั้งค่าทีละสไลเดอร์ให้ดีที่สุด
			for i = 1, 10 do
				local old = x[i]
				local rest = posCost(x) - math.max(old, 0) * cost[i]
				local bv, bs = old, s
				for v = -10, 10 do
					if v ~= old and rest + math.max(v, 0) * cost[i] <= budget then
						x[i] = v
						local sc = ftScore(FT, seed, x)
						if sc > bs + 1e-9 then
							bv, bs = v, sc
						end
					end
				end
				x[i] = bv
				if bv ~= old then
					s, improved = bs, true
				end
			end
			-- ย้ายแต้มจากสไลเดอร์ j ไป i
			for i = 1, 10 do
				for j = 1, 10 do
					if i ~= j then
						for _, d in ipairs({ 1, 2, 4 }) do
							local oi, oj = x[i], x[j]
							if oi + d <= 10 and oj - d >= -10 then
								x[i], x[j] = oi + d, oj - d
								local keep = false
								if posCost(x) <= budget then
									local sc = ftScore(FT, seed, x)
									if sc > s + 1e-9 then
										s, improved, keep = sc, true, true
									end
								end
								if not keep then
									x[i], x[j] = oi, oj
								end
							end
						end
					end
				end
			end
		end
		return s
	end

	local rng = Random.new(math.floor(seed) % 2147483647)
	local bestX, bestS
	local function try(x)
		local s = climb(x)
		if not bestS or s > bestS then
			bestS, bestX = s, table.clone(x)
		end
		task.wait()
	end

	try({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
	try(table.clone(start))
	for _ = 1, 10 do
		local x = {}
		for i = 1, 10 do
			x[i] = rng:NextInteger(-10, 10)
		end
		while posCost(x) > budget do
			local i = rng:NextInteger(1, 10)
			if x[i] > 0 then
				x[i] = x[i] - 1
			end
		end
		try(x)
	end
	return bestX
end

local function ftAutoTune()
	local pg = lplr:FindFirstChild("PlayerGui")
	local itf = pg and pg:FindFirstChild("Interface")
	local bike = itf and itf:FindFirstChild("Bike")
	local car = bike and bike.Value
	if not car then
		return false, "ไม่ได้นั่งรถ"
	end
	local RS = game:GetService("ReplicatedStorage")
	local get, set = RS:FindFirstChild("FreeTune_Get"), RS:FindFirstChild("FreeTune_Set")
	if not (get and set) then
		return false, "ไม่พบระบบไล่รถ"
	end
	local tuner = car:FindFirstChild("Tuner")
	local modS = tuner and tuner:FindFirstChild("FreeTuneMods")
	local okM, FT = pcall(require, modS)
	if not (okM and type(FT) == "table" and FT.Effects) then
		return false, "ไม่พบ FreeTuneMods"
	end

	local carId = car:GetAttribute("CarId") or car.Name
	local okG, res = pcall(function()
		return get:InvokeServer(carId, car)
	end)
	if not okG or type(res) ~= "table" then
		return false, "โหลดค่าจูนไม่สำเร็จ"
	end
	if res.canEdit ~= true then
		return false, "ไม่ใช่เจ้าของรถ แก้ไม่ได้"
	end

	local function norm(t)
		local o = {}
		for i = 1, 5 do
			local v = type(t) == "table" and tonumber(t[i]) or 0
			o[i] = clamp(math.floor((v or 0) + 0.5), -10, 10)
		end
		return o
	end
	local rev, spd = norm(res.rev), norm(res.spd)
	local cst = type(res.cost) == "table" and res.cost or {}
	local cr, cs = cst.rev or 1, cst.spd or 1
	local saved = 0
	for i = 1, 5 do
		saved = saved + math.max(rev[i], 0) * cr + math.max(spd[i], 0) * cs
	end
	local budget = math.max(tonumber(res.budget) or 25, saved)
	local seed = tonumber(car:GetAttribute("FT_Seed")) or 1
	local start = { rev[1], rev[2], rev[3], rev[4], rev[5], spd[1], spd[2], spd[3], spd[4], spd[5] }

	local x = ftSearch(FT, seed, budget, cr, cs, start)
	local _, P, V = ftScore(FT, seed, x)
	local _, P0 = ftScore(FT, seed, start)
	local newT = {
		rev = { x[1], x[2], x[3], x[4], x[5] },
		spd = { x[6], x[7], x[8], x[9], x[10] },
	}
	local okS, r1, r2 = pcall(function()
		return set:InvokeServer(carId, car, newT)
	end)
	if not okS or r1 ~= true then
		return false, tostring(okS and r2 or r1 or "บันทึกไม่สำเร็จ")
	end
	return true, string.format("กำลังเฉลี่ย %+.1f%% (เดิม %+.1f%%) · ปลาย %+.0f km/h", (P - 1) * 100, (P0 - 1) * 100, V)
end

----------------------------------------------------------------
-- ส่วนระบบรถ
----------------------------------------------------------------
local state = {
	seat = nil,
	ramp = 0,
	hb = nil,
	failed = {},
}
local ctx = { vel = Vector3.zero, av = Vector3.zero }

local function readInputs(seat)
	local free = UIS:GetFocusedTextBox() == nil
	local isVeh = seat:IsA("VehicleSeat")
	local steer, accel, brakeIn = 0, false, false
	if isVeh then
		steer = seat.SteerFloat
		accel = seat.ThrottleFloat > 0.1
		brakeIn = seat.ThrottleFloat < -0.1
	end
	if free then
		if not accel then
			accel = UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up)
		end
		if not brakeIn then
			brakeIn = UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down)
		end
		if not isVeh then
			steer = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
		end
	end
	return steer, accel, free and UIS:IsKeyDown(cfg.key), brakeIn
end

local function doBoost(dt, accel, keyHeld, braking, dirPart)
	if braking then
		-- กำลังเบรก: ตัดบูสต์ทันที (เบรกมาก่อนเสมอ)
		state.ramp = 0
		return
	end
	local auto = cfg.autoBoost and accel
	local target = 0
	if auto and keyHeld then
		target = KEY_STACK
	elseif auto or keyHeld then
		target = 1
	end
	local rate = cfg.smooth * 0.8
	local r = state.ramp
	if r < target then
		r = math.min(target, r + rate * dt)
	elseif r > target then
		r = math.max(target, r - rate * dt)
	end
	state.ramp = r
	if r <= 0.001 then
		return
	end
	local speed = ctx.vel.Magnitude
	local room = clamp((cfg.maxSpeed - speed) / math.max(cfg.maxSpeed * 0.1, 1), 0, 1)
	local dir = dirPart.CFrame.LookVector
	if cfg.stable > 0 then
		-- ความเร็วสูง: ดันตามทิศที่รถวิ่งจริง ไม่ดันตามหน้ารถที่กำลังส่าย
		local hv = Vector3.new(ctx.vel.X, 0, ctx.vel.Z)
		local hs = hv.Magnitude
		if hs > 40 then
			local d = hv.Unit
			if d:Dot(dir) > 0.5 then
				local blend = (cfg.stable / 10) * clamp((hs - 40) / 100, 0, 1)
				dir = (dir * (1 - blend) + d * blend).Unit
			end
		end
	end
	ctx.vel = ctx.vel + dir * (cfg.power * 0.5 * r * room * dt)
end

local function doGrip(dt, steer, dirPart)
	local look = dirPart.CFrame.LookVector
	local f = Vector3.new(look.X, 0, look.Z)
	if f.Magnitude < 0.1 then
		return
	end
	f = f.Unit
	local hv = Vector3.new(ctx.vel.X, 0, ctx.vel.Z)
	local spd = hv.Magnitude
	if spd < 8 then
		return
	end
	local lat = hv - f * hv:Dot(f)
	local g = cfg.grip * 0.6
	if cfg.drift > 0 and math.abs(steer) > 0.1 then
		g = g - cfg.drift * 0.6
	end
	if g > 0 then
		ctx.vel = ctx.vel - lat * math.min(g * dt, 0.5)
	elseif g < 0 and lat.Magnitude < spd * 0.6 then
		-- ดริฟต์ = เปลี่ยนทิศของโมเมนตัม ไม่เพิ่มความเร็วรวม (ไม่ทะลุเพดาน)
		local nh = hv + lat * math.min(-g * dt, 0.5)
		if nh.Magnitude > spd then
			nh = nh.Unit * spd
		end
		ctx.vel = Vector3.new(nh.X, ctx.vel.Y, nh.Z)
	end
end

local function doControl(dt, steer, dirPart)
	if cfg.control <= 0 or math.abs(steer) < 0.1 then
		return
	end
	local hv = Vector3.new(ctx.vel.X, 0, ctx.vel.Z).Magnitude
	if hv < 5 then
		return
	end
	if math.abs(ctx.av.Y) >= 3 then
		return
	end
	local dir = (ctx.vel:Dot(dirPart.CFrame.LookVector) >= 0) and 1 or -1
	ctx.av = ctx.av + Vector3.new(0, -steer * dir * cfg.control * clamp(hv / 30, 0, 1) * dt, 0)
end

--// เบรก: กด S ตอนรถวิ่งไปข้างหน้า -> ลดความเร็วตามทิศที่รถวิ่งจริง (ไม่ลดจนติดลบ)
--// พร้อมหน่วงการหมุนของตัวรถให้ "หนึบ" ไม่ส่าย/ไม่กระดก
local function doBrake(dt, braking, steer, dirPart)
	if not braking then
		return
	end
	local v = ctx.vel
	local hv = Vector3.new(v.X, 0, v.Z)
	local hs = hv.Magnitude
	if hs < 2 then
		return
	end
	local look = dirPart.CFrame.LookVector
	local f = Vector3.new(look.X, 0, look.Z)
	if f.Magnitude < 0.1 or hv:Dot(f) <= 0 then
		return -- กำลังถอยหลังอยู่ ไม่เบรก (ให้ S ถอยได้ตามปกติ)
	end
	local d = math.min(cfg.brake * 0.5 * dt, hs)
	local nh = hv * ((hs - d) / hs)
	ctx.vel = Vector3.new(nh.X, v.Y, nh.Z)

	local av = ctx.av
	local k = math.min(4 * dt, 0.5)
	local nav = av - Vector3.new(av.X, 0, av.Z) * k
	if math.abs(steer) < 0.1 then
		nav = nav - Vector3.new(0, av.Y, 0) * k
	end
	ctx.av = nav
end

local function doStability(dt, steer)
	local st = cfg.stable
	if st <= 0 then
		return
	end
	local v = ctx.vel
	local hs = Vector3.new(v.X, 0, v.Z).Magnitude
	if hs < 20 then
		return
	end
	local av = ctx.av
	local sf = clamp((hs - 20) / 100, 0, 1)
	-- กันเอียง/กระดกหน้า-หลัง (หมุนรอบแกนนอน)
	local flat = Vector3.new(av.X, 0, av.Z)
	local nav = av - flat * math.min(st * 0.5 * sf * dt, 0.5)
	-- ถ้าไม่ได้เลี้ยว ลดการส่าย (หมุนรอบแกนตั้ง)
	if math.abs(steer) < 0.1 then
		nav = nav - Vector3.new(0, av.Y, 0) * math.min(st * 0.8 * sf * dt, 0.5)
	end
	ctx.av = nav
end

local function runFeature(name, fn, ...)
	if state.failed[name] then
		return
	end
	local ok = pcall(fn, ...)
	if not ok then
		state.failed[name] = true
	end
end

local function step(dt)
	local seat = state.seat
	if not seat or not seat.Parent then
		return
	end
	local dirPart = seat
	if not seat:IsA("VehicleSeat") then
		dirPart = seat.AssemblyRootPart or seat
	end
	local steer, accel, keyHeld, brakeIn = readInputs(seat)
	local braking = cfg.brakeOn and brakeIn
	local v0, a0 = seat.AssemblyLinearVelocity, seat.AssemblyAngularVelocity
	ctx.vel, ctx.av = v0, a0

	runFeature("boost", doBoost, dt, accel, keyHeld, braking, dirPart)
	runFeature("brake", doBrake, dt, braking, steer, dirPart)
	runFeature("grip", doGrip, dt, steer, dirPart)
	runFeature("control", doControl, dt, steer, dirPart)
	runFeature("stability", doStability, dt, steer)

	if ctx.vel ~= v0 then
		seat.AssemblyLinearVelocity = ctx.vel
	end
	if ctx.av ~= a0 then
		seat.AssemblyAngularVelocity = ctx.av
	end
end

local function setSeat(seat)
	if state.hb then
		state.hb:Disconnect()
		state.hb = nil
	end
	state.seat = seat
	state.ramp = 0
	state.failed = {}
	if seat then
		state.hb = RunService.Heartbeat:Connect(step)
	end
end

----------------------------------------------------------------
-- Teleport
----------------------------------------------------------------
local WAYPOINTS = {
	{ "ห้องไดโน่", Vector3.new(-13607.99, -259.96, -655.19) },
	{ "ขายอะไหล่", Vector3.new(-14607.84, -259.97, 6066.72) },
	{ "แข่งหลังถนน", Vector3.new(-13672.55, -260.50, -460.69) },
	{ "เขื่อนขุนด่านปราการชล", Vector3.new(-13936.83, -98.13, -2952.20) },
	{ "ร้านขาย ECU", Vector3.new(-16178.04, -259.59, -184.53) },
}

local function carModel(seat)
	local m = seat:FindFirstAncestorOfClass("Model")
	while m and m.Parent and m.Parent:IsA("Model") and m.Parent ~= workspace do
		m = m.Parent
	end
	return m
end

--// นั่งรถอยู่ = วาร์ปทั้งคัน (เบาะไปที่จุดหมาย) / ไม่ได้นั่ง = วาร์ปตัวละคร
local function teleportTo(pos)
	pcall(function()
		local seat = state.seat
		if seat and seat.Parent then
			local m = carModel(seat)
			if m then
				local delta = pos + Vector3.new(0, 2, 0) - seat.Position
				m:PivotTo(m:GetPivot() + delta)
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d.AssemblyLinearVelocity = Vector3.zero
						d.AssemblyAngularVelocity = Vector3.zero
					end
				end
				return
			end
		end
		local char = lplr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.CFrame.Position)
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

local seatConn
local espCleanup -- ประกาศไว้ก่อน (ฟังก์ชันจริงอยู่ในส่วน ESP ด้านล่าง)
local function bindChar(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	if seatConn then
		seatConn:Disconnect()
	end
	seatConn = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		setSeat(hum.SeatPart)
	end)
	setSeat(hum.SeatPart)
end

bind(lplr.CharacterAdded, function(ch)
	task.spawn(bindChar, ch)
end)
if lplr.Character then
	task.spawn(bindChar, lplr.Character)
end

----------------------------------------------------------------
-- ส่วน UI (สไตล์ขาว-ดำ มุมโค้ง)
----------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(16, 16, 18),
	winLine = Color3.fromRGB(40, 40, 45),
	line = Color3.fromRGB(34, 34, 38),
	row = Color3.fromRGB(26, 26, 30),
	rowLine = Color3.fromRGB(40, 40, 45),
	field = Color3.fromRGB(35, 35, 40),
	fieldLine = Color3.fromRGB(52, 52, 58),
	off = Color3.fromRGB(58, 58, 65),
	accent = Color3.fromRGB(244, 244, 246),
	accentText = Color3.fromRGB(20, 20, 22),
	text = Color3.fromRGB(244, 244, 246),
	muted = Color3.fromRGB(172, 172, 180),
}

--// ฟอนต์ทั้งหมดอยู่ตรงนี้ที่เดียว (ลองเปลี่ยนเป็น Enum.Font.BuilderSans / Enum.Font.SourceSans ได้)
local F = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

--// สัญลักษณ์ (ถ้าฟอนต์ไม่แสดง เปลี่ยนตรงนี้ได้)
local SYM = {
	star = "★",
	starOff = "☆",
	arrow = "▾",
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function round(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, color, thickness)
	return new("UIStroke", {
		Color = color, Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function label(parent, text, size, color, font, pos, sz)
	return new("TextLabel", {
		Text = text, TextSize = size, TextColor3 = color, Font = font,
		BackgroundTransparency = 1, Position = pos, Size = sz,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local isPress = function(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local isMove = function(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local Window = WindUI:CreateWindow({
	Title = "Vehicle Hub",
	Icon = "car",
	Author = "Vehicle Mods · ESP · ECU",
	Folder = "VehicleHubUI",
	Size = UDim2.fromOffset(640, 500),
	Theme = "Dark",
	ToggleKey = cfg.uiKey,
	SideBarWidth = 190,
})

local function make(tab, kind, props)
	local ok, el = pcall(function()
		return tab[kind](tab, props)
	end)
	if not ok then
		warn("[VehicleHub] สร้าง " .. kind .. " ไม่ได้: " .. tostring(el))
		return {}
	end
	return el
end

local function newPage(title, icon)
	return { tab = Window:Tab({ Title = title, Icon = icon }) }
end

local function section(pg, text)
	return make(pg.tab, "Section", { Title = text })
end

local function parseKey(v)
	if typeof(v) == "EnumItem" then
		return v
	end
	if type(v) == "string" then
		local ok, kc = pcall(function()
			return Enum.KeyCode[v]
		end)
		if ok and kc then
			return kc
		end
	end
	return nil
end

local function toggleRow(pg, titleText, descText, key, onChange)
	local el
	el = make(pg.tab, "Toggle", {
		Title = titleText, Desc = descText, Value = cfg[key], Default = cfg[key],
		Callback = function(v)
			if painting or type(v) ~= "boolean" or cfg[key] == v then
				return
			end
			cfg[key] = v
			changed()
			if onChange then
				onChange()
			end
		end,
	})
	painters[#painters + 1] = function()
		pcall(el.Set, el, cfg[key])
	end
	return el
end

local function keyRow(pg, titleText, descText, key)
	local el
	el = make(pg.tab, "Keybind", {
		Title = titleText, Desc = descText, Value = cfg[key].Name,
		Callback = function(v)
			local kc = parseKey(v)
			if painting or not kc or cfg[key] == kc then
				return
			end
			cfg[key] = kc
			changed()
			if key == "uiKey" then
				pcall(function()
					Window:SetToggleKey(kc)
				end)
			end
		end,
	})
	painters[#painters + 1] = function()
		pcall(el.Set, el, cfg[key].Name)
		if key == "uiKey" then
			pcall(function()
				Window:SetToggleKey(cfg[key])
			end)
		end
	end
	return el
end

local function sliderRow(pg, titleText, descText, key, min, max)
	local el
	el = make(pg.tab, "Slider", {
		Title = titleText, Desc = descText, Step = 1,
		Value = { Min = min, Max = max, Default = cfg[key] },
		Callback = function(v)
			v = tonumber(v)
			if painting or not v then
				return
			end
			v = clamp(math.floor(v + 0.5), min, max)
			if cfg[key] == v then
				return
			end
			cfg[key] = v
			changed()
		end,
	})
	painters[#painters + 1] = function()
		pcall(el.Set, el, cfg[key])
	end
	return el
end

--// ช่องพิมพ์ตัวเลขตรง ๆ (ใช้กับความเร็วสูงสุดที่ช่วงกว้างมาก)
local function numberRow(pg, titleText, descText, key, min, max)
	local el
	el = make(pg.tab, "Input", {
		Title = titleText, Desc = descText, Value = tostring(cfg[key]), Placeholder = tostring(cfg[key]),
		Callback = function(text)
			if painting then
				return
			end
			local n = tonumber(text)
			if n then
				n = clamp(math.floor(n), min, max)
				if n ~= cfg[key] then
					cfg[key] = n
					changed()
				end
			end
			if text ~= tostring(cfg[key]) then
				pcall(el.Set, el, tostring(cfg[key]))
			end
		end,
	})
	painters[#painters + 1] = function()
		pcall(el.Set, el, tostring(cfg[key]))
	end
	return el
end

--// ปุ่ม: คืนค่า (btn, desc) ที่ตั้ง .Text ได้เหมือนเดิม -> ไปอัปเดตชื่อ/คำอธิบายของปุ่ม WindUI
local function buttonRow(pg, titleText, descText, btnText, onClick)
	local el
	local st = { btn = btnText, desc = descText }
	local function render()
		pcall(function()
			el:SetTitle(st.btn ~= btnText and (titleText .. " · " .. st.btn) or titleText)
			el:SetDesc(st.desc)
		end)
	end
	el = make(pg.tab, "Button", {
		Title = titleText, Desc = descText,
		Callback = function()
			onClick()
		end,
	})
	local function proxy(field)
		return setmetatable({}, {
			__index = function(_, k)
				if k == "Text" then
					return st[field]
				elseif k == "Parent" then
					return alive and true or nil
				end
				return nil
			end,
			__newindex = function(_, k, v)
				if k == "Text" then
					st[field] = tostring(v)
					render()
				end
			end,
		})
	end
	return proxy("btn"), proxy("desc")
end

----------------------------------------------------------------
-- หน้า Vehicle Mods
----------------------------------------------------------------
local pgVehicle = newPage("Vehicle Mods", "car")
section(pgVehicle, "Vehicle Settings")

numberRow(pgVehicle, "ความเร็วสูงสุดที่ต้องการ", "เพดานความเร็ว (หน่วย studs/s)", "maxSpeed", 10, 5000)

toggleRow(pgVehicle, "Auto Boost", "บูสต์ตอนกดเดินหน้า (W) ไม่ต้องกดปุ่มอื่น", "autoBoost")
keyRow(pgVehicle, "ปุ่มกระตุ้นบูสต์", "กดค้างเพื่อบูสต์ ซ้อน Auto Boost = คูณ x" .. KEY_STACK, "key")
sliderRow(pgVehicle, "ความแรงของการบูส", "ตัวคูณแรงบูสต์ (20 = เท่าสคริปต์เดิม)", "power", 1, 1000)
sliderRow(pgVehicle, "แรงดริฟต์", "ปล่อยให้ท้ายรถไถลตอนเลี้ยว (0 = ปิด)", "drift", 0, 10)
sliderRow(pgVehicle, "เพิ่มการยึดเกาะ", "ลดการไถลด้านข้างของรถ (0 = ปิด)", "grip", 0, 10)
sliderRow(pgVehicle, "เพิ่มการควบคุม", "ช่วยให้หักเลี้ยวไวและคมขึ้น (0 = ปิด)", "control", 0, 10)
sliderRow(pgVehicle, "ความสมูทของการบูส", "ต่ำ = ค่อย ๆ ไต่ สูง = พุ่งทันที", "smooth", 1, 1000)

section(pgVehicle, "Brake (เบรก)")
toggleRow(pgVehicle, "เบรก (กด S)", "เบรกหนึบเมื่อกด S ตอนรถวิ่งไปข้างหน้า", "brakeOn")
sliderRow(pgVehicle, "ความแรงของเบรก", "ยิ่งสูงยิ่งหยุดไว (10 ถึง 1000)", "brake", 10, 1000)

section(pgVehicle, "Stability & Physics (ความนิ่ง)")
sliderRow(pgVehicle, "ความนิ่งตอนวิ่งเร็ว", "ลดการส่าย/เอียง/เด้งตอนวิ่งเร็ว (0 = ปิด)", "stable", 0, 10)

----------------------------------------------------------------
-- หน้า ESP
----------------------------------------------------------------
local pgESP = newPage("ESP", "eye")
section(pgESP, "ESP")

local espData = {}
local ESP_DEFAULT = Color3.fromRGB(255, 255, 255)
local COL_MONEY = Color3.fromRGB(74, 201, 110)
local STUD_KMH = 0.64 -- ปรับจากภาพจริง: สคริปต์ 203 vs เกม 129 (ค่าเดิม 1.008 สูงเกิน) ถ้ายังไม่ตรงให้ปรับตรงนี้

local function fmtNum(n)
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function espColor(p)
	local t = p.Team
	return t and t.TeamColor.Color or ESP_DEFAULT
end

local function espRefresh()
	for _, d in pairs(espData) do
		if d.nameLabel then
			d.nameLabel.Visible = cfg.espName
		end
		if d.moneyLabel then
			d.moneyLabel.Visible = cfg.espMoney
		end
		if d.hpLabel then
			d.hpLabel.Visible = cfg.espHP
		end
		if d.speedLabel then
			d.speedLabel.Visible = cfg.espSpeed
		end
		if d.gui then
			d.gui.Enabled = cfg.espName or cfg.espHP or cfg.espMoney or cfg.espSpeed
		end
		if d.highlight then
			d.highlight.Enabled = cfg.espChams
		end
	end
end

local function espPaint(d)
	local c = d.color
	if d.nameLabel then
		d.nameLabel.TextColor3 = c
	end
	if d.hpLabel then
		d.hpLabel.TextColor3 = c
	end
	if d.highlight then
		d.highlight.FillColor = c
		d.highlight.OutlineColor = c
	end
end

local function espHealth(d, hum)
	if d.hpLabel then
		d.hpLabel.Text = string.format("HP %d/%d", math.ceil(hum.Health), math.ceil(hum.MaxHealth))
	end
end

local function espLabel(parent, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 16)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.TextStrokeTransparency = 0.4
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Text = ""
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function espEnsure(player, char)
	local d = espData[player]
	if not d or not char.Parent then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local head = char:FindFirstChild("Head")

	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- ชื่อ / เงิน / HP อยู่ใน Billboard เดียว เรียงคนละบรรทัด (ขนาดพิกเซลคงที่ ไม่ซ้อนกันเวลาอยู่ไกล)
	if head and not head:FindFirstChild("ESP_Info") then
		local g = Instance.new("BillboardGui")
		g.Name = "ESP_Info"
		g.AlwaysOnTop = true
		g.Size = UDim2.fromOffset(200, 68)
		g.StudsOffset = Vector3.new(0, 2.6, 0)
		g.LightInfluence = 0
		g.MaxDistance = math.huge
		g.Parent = head
		local lay = Instance.new("UIListLayout")
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.VerticalAlignment = Enum.VerticalAlignment.Bottom
		lay.Parent = g
		d.gui = g
		d.nameLabel = espLabel(g, 1)
		d.moneyLabel = espLabel(g, 2)
		d.hpLabel = espLabel(g, 3)
		d.speedLabel = espLabel(g, 4)
		d.moneyLabel.TextColor3 = COL_MONEY
		d.speedLabel.TextColor3 = Color3.fromRGB(250, 196, 56)
		d.nameLabel.Text = player.DisplayName
	end

	if not char:FindFirstChild("ESP_Chams") then
		local hl = Instance.new("Highlight")
		hl.Name = "ESP_Chams"
		hl.Adornee = char
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.7
		hl.OutlineTransparency = 0
		hl.Parent = char
		d.highlight = hl
	end

	if hum and d.humanoid ~= hum then
		d.humanoid = hum
		for _, c in ipairs(d.humConns) do
			c:Disconnect()
		end
		table.clear(d.humConns)
		d.humConns[#d.humConns + 1] = hum.HealthChanged:Connect(function()
			espHealth(d, hum)
		end)
		d.humConns[#d.humConns + 1] = hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			espHealth(d, hum)
		end)
	end
	if hum then
		espHealth(d, hum)
	end

	d.color = espColor(player)
	espPaint(d)
	espRefresh()
end

local function espHook(player, char)
	local d = espData[player]
	if not d then
		return
	end
	if d.char ~= char then
		d.char = char
		d.humanoid = nil
		for _, c in ipairs(d.modelConns) do
			c:Disconnect()
		end
		table.clear(d.modelConns)
		d.modelConns[#d.modelConns + 1] = char.ChildAdded:Connect(function(ch)
			if ch.Name == "Head" or ch.Name == "HumanoidRootPart" or ch:IsA("Humanoid") then
				espEnsure(player, char)
			end
		end)
	end
	espEnsure(player, char)
end

local function espUntrack(player)
	local d = espData[player]
	if not d then
		return
	end
	for _, list in ipairs({ d.conns, d.modelConns, d.humConns }) do
		for _, c in ipairs(list) do
			c:Disconnect()
		end
	end
	if d.gui then
		d.gui:Destroy()
	end
	if d.highlight then
		d.highlight:Destroy()
	end
	espData[player] = nil
end

local function espTrack(player)
	if player == lplr or espData[player] then
		return
	end
	local d = { color = espColor(player), conns = {}, modelConns = {}, humConns = {} }
	espData[player] = d
	d.conns[#d.conns + 1] = player:GetPropertyChangedSignal("Team"):Connect(function()
		d.color = espColor(player)
		espPaint(d)
	end)
	d.conns[#d.conns + 1] = player.CharacterAdded:Connect(function(ch)
		espHook(player, ch)
	end)
	if player.Character then
		espHook(player, player.Character)
	end
end

espCleanup = function()
	for p in pairs(espData) do
		espUntrack(p)
	end
end

bind(workspace.ChildAdded, function(child)
	if not child:IsA("Model") then
		return
	end
	local p = Players:FindFirstChild(child.Name)
	if p and p:IsA("Player") and espData[p] then
		espHook(p, child)
	end
end)
bind(Players.PlayerAdded, espTrack)
bind(Players.PlayerRemoving, espUntrack)
for _, p in ipairs(Players:GetPlayers()) do
	espTrack(p)
end

toggleRow(pgESP, "Name", "แสดงชื่อเหนือหัวตัวละคร", "espName", espRefresh)
toggleRow(pgESP, "Chams", "ไฮไลต์ตัวละครทะลุกำแพง", "espChams", espRefresh)
toggleRow(pgESP, "HP", "แสดงเลือด ใต้ชื่อ คนละบรรทัด", "espHP", espRefresh)
toggleRow(pgESP, "Money", "แสดงเงิน (Baht) ของผู้เล่นอื่น ใต้ชื่อ สีเขียว", "espMoney", espRefresh)
toggleRow(pgESP, "Speed", "แสดงความเร็วรถ (KM/H) ของผู้เล่นอื่นที่นั่งรถ ใต้ HP", "espSpeed", espRefresh)

local speedAcc = 0
bind(RunService.Heartbeat, function(dt)
	speedAcc = speedAcc + dt
	if speedAcc < 0.1 then
		return
	end
	speedAcc = 0
	for p, d in pairs(espData) do
		if d.speedLabel then
			local txt = ""
			if cfg.espSpeed then
				local ch = p.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				local seat = hum and hum.SeatPart
				if seat then
					txt = math.floor(seat.AssemblyLinearVelocity.Magnitude * STUD_KMH + 0.5) .. " KM/H"
				end
			end
			d.speedLabel.Text = txt
		end
	end
end)

local moneyAcc = 0
bind(RunService.Heartbeat, function(dt)
	moneyAcc = moneyAcc + dt
	if moneyAcc < 0.5 then
		return
	end
	moneyAcc = 0
	for p, d in pairs(espData) do
		if d.moneyLabel then
			local m = p:GetAttribute("Baht")
			if cfg.espMoney and p:GetAttribute("BahtLoaded") == true and type(m) == "number" then
				d.moneyLabel.Text = "฿" .. fmtNum(m)
			else
				d.moneyLabel.Text = ""
			end
		end
	end
end)

painters[#painters + 1] = espRefresh

----------------------------------------------------------------
-- หน้า ECU
----------------------------------------------------------------
local gui2 -- ประกาศไว้ก่อน (สร้างจริงในส่วน Status Vehicle ด้านล่าง ใช้กับแจ้งเตือนของ ECU API)
local pgECU = newPage("ECU", "cpu")
section(pgECU, "ECU STD")
toggleRow(pgECU, "Link AIR + FUEL",
	hookmetamethod and "แก้ AIR หรือ FUEL อันเดียว ส่งเข้า ECU ได้ทั้งสองอัน"
		or "executor นี้ไม่รองรับ hookmetamethod",
	"ecuLink")

-- ปุ่มเดียวจบ: AIR/FUEL -> TPS/IGN -> ไล่รถ (ต้องทำตามลำดับ เพราะ IGN คิดจาก AIR/FUEL)
local ftBusy = false
local allBtn, allDesc
allBtn, allDesc = buttonRow(pgECU, "Auto Tune ทั้งหมด", "AIR/FUEL, TPS/IGN และ A/B (ไล่รถ) ในปุ่มเดียว", "จูนเลย", function()
	if ftBusy then
		return
	end
	ftBusy = true
	allBtn.Text = "คำนวณ..."
	task.spawn(function()
		local parts = {}
		local function run(name, fn)
			local ok, msg = fn()
			parts[#parts + 1] = name .. (ok and " ผ่าน" or (" ไม่ผ่าน: " .. tostring(msg)))
			if not ok then
				warn("[VehicleHub] " .. name .. ": " .. tostring(msg))
			end
		end
		-- AIR/FUEL/TPS/IGN ส่งเข้า ECU ครั้งเดียว (ส่งแยกสองครั้งติดกันจะโดนคูลดาวน์ของเซิร์ฟเวอร์)
		run("AIR/FUEL/TPS/IGN", function()
			return ecuAutoTune("all")
		end)
		run("A/B", ftAutoTune)
		ftBusy = false
		if allBtn.Parent then
			allBtn.Text = "เสร็จ"
			allDesc.Text = table.concat(parts, " · ")
			task.delay(3, function()
				if allBtn.Parent then
					allBtn.Text = "จูนเลย"
				end
			end)
		end
	end)
end)

local function ecuButton(title, desc, mode)
	local btn
	btn = buttonRow(pgECU, title, desc, "จูนเลย", function()
		local ok, msg = ecuAutoTune(mode)
		btn.Text = ok and "สำเร็จ" or "ล้มเหลว"
		setStatus(tostring(msg))
		if not ok then
			warn("[VehicleHub] " .. tostring(msg))
		end
		task.delay(2, function()
			if btn.Parent then
				btn.Text = "จูนเลย"
			end
		end)
	end)
end
ecuButton("Auto Tune AIR + FUEL", "ตั้ง AIR/FUEL ให้เกรดสูงสุดทุกจุด แล้วส่งเข้า ECU", "af")
ecuButton("Auto Tune TPS + IGN", "ตั้ง TPS/IGN ให้เขียวเข้มทุกจุด แล้วส่งเข้า ECU", "ti")

----------------------------------------------------------------
-- ECU API (กล่องใหม่ แบบกริด: 10 แถวคันเร่ง x 11 จุดรอบ)
-- ส่ง ECUTune_Save พร้อมกริดเป็นอาร์กิวเมนต์ที่ 10 (แถวคันเร่ง 100% ส่งเป็นกราฟเส้นเดิมด้วย)
-- เขียวเข้ม: AFR ผิด <= 0.05, IGN ผิด <= 0.6 องศา, TPS ผิด <= 0.03
----------------------------------------------------------------
section(pgECU, "ECU API")
do
	local GRID_KEYS = { "Air", "Fuel", "TPS", "POP", "IGN" }

	--// แจ้งเตือนมุมขวาล่าง (สไตล์เดียวกับแจ้งเตือนของเกม)
	local toast, toastTitle, toastText
	local toastTok = 0
	local function showToast(title, text)
		if not toast then
			toast = new("Frame", {
				Size = UDim2.fromOffset(230, 70), AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -4, 1, -86),
				BackgroundColor3 = Color3.fromRGB(20, 20, 22), BackgroundTransparency = 0.2,
				BorderSizePixel = 0, Visible = false, ZIndex = 20,
			}, gui2)
			round(toast, 4)
			toastTitle = label(toast, "", 15, C.text, F.bold, UDim2.fromOffset(8, 6), UDim2.new(1, -16, 0, 20))
			toastTitle.TextXAlignment = Enum.TextXAlignment.Center
			toastText = label(toast, "", 12, C.muted, F.regular, UDim2.fromOffset(8, 28), UDim2.new(1, -16, 1, -32))
			toastText.TextXAlignment = Enum.TextXAlignment.Center
			toastText.TextYAlignment = Enum.TextYAlignment.Top
			toastText.TextWrapped = true
			toastText.TextTruncate = Enum.TextTruncate.None
		end
		toastTok = toastTok + 1
		local k = toastTok
		toastTitle.Text = title
		toastText.Text = text
		toast.Visible = true
		task.delay(5, function()
			if k == toastTok and toast and toast.Parent then
				toast.Visible = false
			end
		end)
	end

	local function apiGetActive()
		local a, car = ecuGetActive()
		if not a then
			return nil, car
		end
		if not (a.Grid and a.GShape and a.EvalNode and a.SetGridAll) then
			return nil, "รถคันนี้ไม่ได้ใช้กล่อง ECU API"
		end
		return a, car
	end

	local function gridCopy(g)
		local out = {}
		for _, k in ipairs(GRID_KEYS) do
			out[k] = {}
			for r, rowT in ipairs(g[k]) do
				out[k][r] = table.clone(rowT)
			end
		end
		return out
	end

	--// แถวคันเร่งสูงสุด -> กราฟเส้น { {rpm, ค่า}, ... }
	local function topLine(g, key, rpm)
		local last = g[key][#g[key]]
		local o = {}
		for i, r in ipairs(rpm) do
			o[i] = { r, last[i] }
		end
		return o
	end

	--// mode: "af" = AIR+FUEL, "ti" = TPS+IGN, "all" = ทั้งหมด (IGN คิดจาก AIR/FUEL ที่เพิ่งตั้งในแต่ละช่อง)
	local function apiBuild(a, mode)
		local rpm = a:GetRPMPoints(1000)
		local rows, cols = #a.THR_ROWS, #rpm
		local lo, hi = a.GRID_LO, a.GRID_HI
		local best = a.Config.AFR.Best
		local kk = a.GShape.k
		local g = gridCopy(a.Grid)
		local doAF, doTI = mode ~= "ti", mode ~= "af"

		for r = 1, rows do
			for c = 1, cols do
				if doTI then
					local x = a:EvalNode(g, r, c)
					g.TPS[r][c] = clamp(ecuR2(x.itps), lo.TPS, hi.TPS)
				end
				if doAF then
					local x = a:EvalNode(g, r, c)
					local base = math.floor(x.ia * 100) / 100
					local bestKey, bestA, bestF = math.huge, g.Air[r][c], g.Fuel[r][c]
					-- ขั้น 0.01 ของ AIR/FUEL หยาบเมื่อค่าเล็ก (AFR กระโดดทีละ ~0.1) จึงลองคู่ AIR/FUEL หลายแบบ
					-- เรียงจากใกล้ค่าอุดมคติก่อน เจอคู่ที่ AFR เขียวเข้มและ AIR คลาดไม่เกิน 0.04 ก็หยุด
					local done = false
					for _, da in ipairs({ 0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8 }) do
						local av = clamp(ecuR2(base + da * 0.01), lo.Air, hi.Air)
						local fx = best * av * kk[r][c] / x.iafr
						for _, df in ipairs({ 0, -1, 1 }) do
							local fv = clamp(ecuR2(fx + df * 0.01), lo.Fuel, hi.Fuel)
							g.Air[r][c], g.Fuel[r][c] = av, fv
							local y = a:EvalNode(g, r, c)
							local afrErr = math.abs(y.afr - y.iafr)
							local airErr = math.abs(av - y.ia)
							local key = (afrErr > 0.05 and 100 or 0) + math.max(airErr - 0.04, 0) * 10 + afrErr + airErr * 0.01
							if key < bestKey then
								bestKey, bestA, bestF = key, av, fv
							end
							if afrErr <= 0.05 and airErr <= 0.04 then
								done = true
								break
							end
						end
						if done then
							break
						end
					end
					g.Air[r][c], g.Fuel[r][c] = bestA, bestF
				end
				if doTI then
					local x = a:EvalNode(g, r, c)
					g.IGN[r][c] = clamp(ecuR2(x.iign), lo.IGN, hi.IGN)
				end
			end
		end

		local bad = 0
		local sumQ, minQ = 0, 1
		for r = 1, rows do
			for c = 1, cols do
				local x = a:EvalNode(g, r, c)
				sumQ = sumQ + x.q
				minQ = math.min(minQ, x.q)
				local off = (doAF and math.abs(x.afr - x.iafr) > 0.05)
					or (doTI and (math.abs(x.ie) > a.IGN_TOL * 0.5 or math.abs(x.tps - x.itps) > 0.03))
				if off then
					bad = bad + 1
				end
			end
		end
		--// โบนัสของกล่อง API = API_EDGE_MIN + (MAX - MIN) x q  (เป็นเปอร์เซ็นต์)
		local eMin, eMax = a.API_EDGE_MIN or 0.03, a.API_EDGE_MAX or 0.05
		local avg = (eMin + (eMax - eMin) * (sumQ / (rows * cols))) * 100
		local low = (eMin + (eMax - eMin) * minQ) * 100
		return g, bad, avg, low
	end

	local function apiTune(mode)
		local a, car = apiGetActive()
		if not a then
			return false, car
		end
		local legacy = a.LegacyTPS
		if type(legacy) ~= "function" then
			return false, "ไม่พบ LegacyTPS"
		end
		local ok, g, bad, avg, low = pcall(apiBuild, a, mode)
		if not ok then
			showToast("ECU API", "จูนไม่สำเร็จ: " .. tostring(g))
			return false, g
		end
		pcall(function()
			a:SetGridAll(g)
		end)
		local rpm = a:GetRPMPoints(1000)
		local okL, tpsLine = pcall(legacy, g.TPS)
		if not okL then
			return false, tpsLine
		end
		local sent, note = ecuSend(car, topLine(g, "Air", rpm), topLine(g, "Fuel", rpm), tpsLine,
			topLine(g, "POP", rpm), topLine(g, "IGN", rpm), g)
		if not sent then
			showToast("ECU API", "ส่งไม่สำเร็จ: " .. tostring(note))
			return false, note
		end
		local msg = bad == 0 and "เขียวครบ" or ("ไม่เขียว " .. bad .. " ช่อง")
		local bonus = string.format("โบนัส +%.1f%% (ต่ำสุด +%.1f%%)", avg, low)
		showToast("ECU API", msg .. " · " .. bonus)
		msg = msg .. " · " .. bonus
		return true, note and (msg .. " · " .. note) or msg
	end

	local apiAllBtn, apiAllDesc
	apiAllBtn, apiAllDesc = buttonRow(pgECU, "Auto Tune ทั้งหมด", "AIR/FUEL, TPS/IGN และ A/B (ไล่รถ) ในปุ่มเดียว", "จูนเลย", function()
		if ftBusy then
			return
		end
		ftBusy = true
		apiAllBtn.Text = "คำนวณ..."
		task.spawn(function()
			local parts = {}
			local function run(name, fn)
				local ok, msg = fn()
				parts[#parts + 1] = name .. (ok and " ผ่าน" or (" ไม่ผ่าน: " .. tostring(msg)))
				if not ok then
					warn("[VehicleHub] " .. name .. ": " .. tostring(msg))
				end
			end
			run("AIR/FUEL/TPS/IGN", function()
				return apiTune("all")
			end)
			run("A/B", ftAutoTune)
			ftBusy = false
			if apiAllBtn.Parent then
				apiAllBtn.Text = "เสร็จ"
				apiAllDesc.Text = table.concat(parts, " · ")
				task.delay(3, function()
					if apiAllBtn.Parent then
						apiAllBtn.Text = "จูนเลย"
					end
				end)
			end
		end)
	end)

	local function apiButton(title, desc, mode)
		local btn
		btn = buttonRow(pgECU, title, desc, "จูนเลย", function()
			local ok, msg = apiTune(mode)
			btn.Text = ok and "สำเร็จ" or "ล้มเหลว"
			setStatus(tostring(msg))
			if not ok then
				warn("[VehicleHub] " .. tostring(msg))
			end
			task.delay(2, function()
				if btn.Parent then
					btn.Text = "จูนเลย"
				end
			end)
		end)
	end
	apiButton("Auto Tune AIR + FUEL", "ตั้ง AIR/FUEL ให้เขียวเข้มทุกช่องของกริด แล้วส่งเข้า ECU", "af")
	apiButton("Auto Tune TPS + IGN", "ตั้ง TPS/IGN ให้เขียวเข้มทุกช่องของกริด แล้วส่งเข้า ECU", "ti")
end

section(pgECU, "Free Tune (ไล่รถ)")
local ftBtn, ftDesc
ftBtn, ftDesc = buttonRow(pgECU, "Auto Tune ไล่รถ", "หาค่า A/B ที่ดีที่สุดภายในแต้มที่มี แล้วบันทึก", "จูนเลย", function()
	if ftBusy then
		return
	end
	ftBusy = true
	ftBtn.Text = "คำนวณ..."
	task.spawn(function()
		local ok, msg = ftAutoTune()
		ftBusy = false
		if ftBtn.Parent then
			ftBtn.Text = ok and "สำเร็จ" or "ล้มเหลว"
			ftDesc.Text = tostring(msg)
			task.delay(3, function()
				if ftBtn.Parent then
					ftBtn.Text = "จูนเลย"
				end
			end)
		end
		if not ok then
			warn("[VehicleHub] " .. tostring(msg))
		end
	end)
end)

----------------------------------------------------------------
-- หน้า Status Vehicle
----------------------------------------------------------------
local pgStatus = newPage("Status Vehicle", "gauge")
section(pgStatus, "Status Vehicle")

do
----------------------------------------------------------------
-- หน้าต่าง Engine Status (ลอย ลากได้ ปรับขนาดได้) อ่านจาก Attribute ของรถ
----------------------------------------------------------------
local PARTS = {
	{ "ลูกสูบ", "Eng_Piston" },
	{ "เสื้อสูบ", "Eng_Block" },
	{ "ฝาสูบ", "Eng_Head" },
	{ "วาล์ว", "Eng_Valves" },
	{ "ข้อเหวี่ยง", "Eng_Crankshaft" },
	{ "ก้านสูบ", "Eng_ConRod" },
	{ "หัวเทียน", "Eng_SparkPlug" },
	{ "น้ำมันเครื่อง", "Eng_Oil" },
}
local SW_W, SW_H = 280, 340
local SW_MIN_W, SW_MIN_H = 240, 300
local SW_MAX_W, SW_MAX_H = 700, 900
local COL_GOOD = Color3.fromRGB(74, 201, 110)
local COL_MID = Color3.fromRGB(250, 196, 56)
local COL_BAD = Color3.fromRGB(232, 84, 84)

local function colorFor(v)
	if v >= 60 then
		return COL_GOOD
	elseif v >= 30 then
		return COL_MID
	end
	return COL_BAD
end

gui2 = new("ScreenGui", {
	Name = "VehicleHubStatus", ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 998,
})

local function swDefaultPos()
	return UDim2.new(1, -SW_W - 24, 0.5, -SW_H / 2)
end

local sw = new("Frame", {
	Size = UDim2.fromOffset(SW_W, SW_H), Position = swDefaultPos(),
	BackgroundColor3 = C.bg, BorderSizePixel = 0, Visible = false,
}, gui2)
round(sw, 14)
stroke(sw, C.winLine, 1)

local swHead = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, sw)
local swTitle = label(swHead, "สถานะเครื่องยนต์", 16, C.text, F.bold, UDim2.fromOffset(14, 0), UDim2.new(1, -84, 1, 0))
local swTotal = label(swHead, "--%", 16, C.muted, F.bold, UDim2.new(1, -74, 0, 0), UDim2.fromOffset(60, 44))
swTotal.TextXAlignment = Enum.TextXAlignment.Right

local swDot = new("Frame", {
	Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(14, 51),
	BackgroundColor3 = C.muted, BorderSizePixel = 0, Visible = false,
}, sw)
round(swDot, 5)
local swInfo = label(sw, "", 12, C.muted, F.regular, UDim2.fromOffset(14, 44), UDim2.new(1, -28, 0, 24))

local swList = new("Frame", {
	Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 1, -98),
	BackgroundTransparency = 1,
}, sw)

local swRows = {}
for i, p in ipairs(PARTS) do
	local r = new("Frame", {
		Position = UDim2.new(0, 0, (i - 1) / #PARTS, 0), Size = UDim2.new(1, 0, 1 / #PARTS, 0),
		BackgroundTransparency = 1,
	}, swList)
	label(r, p[1], 14, C.text, F.regular, UDim2.new(), UDim2.new(0.36, 0, 1, 0))
	local track = new("Frame", {
		Position = UDim2.new(0.37, 0, 0.5, -4), Size = UDim2.new(0.43, 0, 0, 8),
		BackgroundColor3 = C.field, BorderSizePixel = 0,
	}, r)
	round(track, 4)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.off, BorderSizePixel = 0 }, track)
	round(fill, 4)
	local val = label(r, "--", 14, C.muted, F.medium, UDim2.new(0.82, 0, 0, 0), UDim2.new(0.18, 0, 1, 0))
	val.TextXAlignment = Enum.TextXAlignment.Right
	swRows[i] = { fill = fill, val = val, attr = p[2] }
end

-- มุมปรับขนาด (ล่างขวา)
local grip = new("TextButton", {
	Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
	Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
}, sw)
for _, g in ipairs({ { 5, 6 }, { 10, 12 } }) do
	new("Frame", {
		Size = UDim2.fromOffset(g[2], 2), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22 - g[1], 22 - g[1]), Rotation = -45,
		BackgroundColor3 = C.muted, BorderSizePixel = 0,
	}, grip)
end

local function dragger(handle, begin)
	bind(handle.InputBegan, function(i)
		if not isPress(i) then
			return
		end
		local apply = begin()
		local start = i.Position
		local mv, en
		mv = UIS.InputChanged:Connect(function(m)
			if isMove(m) then
				apply(m.Position - start)
			end
		end)
		en = UIS.InputEnded:Connect(function(e)
			if isPress(e) then
				mv:Disconnect()
				en:Disconnect()
			end
		end)
	end)
end

dragger(swHead, function()
	local p = sw.Position
	return function(d)
		sw.Position = UDim2.new(p.X.Scale, p.X.Offset + d.X, p.Y.Scale, p.Y.Offset + d.Y)
	end
end)

dragger(grip, function()
	local s = sw.AbsoluteSize
	return function(d)
		sw.Size = UDim2.fromOffset(
			clamp(s.X + d.X, SW_MIN_W, SW_MAX_W),
			clamp(s.Y + d.Y, SW_MIN_H, SW_MAX_H)
		)
	end
end)

local function swIdle()
	swTitle.Text = "สถานะเครื่องยนต์"
	swTotal.Text = "--%"
	swTotal.TextColor3 = C.muted
	swDot.Visible = false
	swInfo.Position = UDim2.fromOffset(14, 44)
	swInfo.Text = "✕  ไม่ได้นั่งอยู่ในรถ"
	swInfo.TextColor3 = COL_BAD
	for _, r in ipairs(swRows) do
		r.fill.Size = UDim2.new(0, 0, 1, 0)
		r.fill.BackgroundColor3 = C.off
		r.val.Text = "--"
		r.val.TextColor3 = C.muted
	end
end

local function swRefresh()
	local seat = state.seat
	local car = seat and seat.Parent and carModel(seat)
	if not (car and car:GetAttribute("Eng_Block") ~= nil) then
		swIdle()
		return
	end
	local sum, n = 0, 0
	for _, r in ipairs(swRows) do
		local v = tonumber(car:GetAttribute(r.attr))
		if v then
			v = clamp(v, 0, 100)
			sum = sum + v
			n = n + 1
			local c = colorFor(v)
			r.fill.Size = UDim2.new(v / 100, 0, 1, 0)
			r.fill.BackgroundColor3 = c
			r.val.Text = math.floor(v + 0.5) .. "%"
			r.val.TextColor3 = c
		else
			r.fill.Size = UDim2.new(0, 0, 1, 0)
			r.val.Text = "--"
			r.val.TextColor3 = C.muted
		end
	end
	local avg = n > 0 and sum / n or 0
	local dead = car:GetAttribute("Eng_Dead") == true
	local txt = "แย่"
	if dead then
		txt = "เครื่องพัง"
	elseif avg >= 80 then
		txt = "ดี"
	elseif avg >= 50 then
		txt = "ปานกลาง"
	end
	local c = dead and COL_BAD or colorFor(avg)
	local name = car:GetAttribute("CarId")
	swTitle.Text = (type(name) == "string" and name ~= "") and name or car.Name
	swTotal.Text = math.floor(avg + 0.5) .. "%"
	swTotal.TextColor3 = c
	swDot.BackgroundColor3 = c
	swDot.Visible = true
	swInfo.Position = UDim2.fromOffset(32, 44)
	swInfo.Text = "สภาพรถโดยรวม: " .. txt
	swInfo.TextColor3 = C.muted
end

local swAcc = 0
bind(RunService.Heartbeat, function(dt)
	sw.Visible = cfg.statusOn
	if not cfg.statusOn then
		return
	end
	swAcc = swAcc + dt
	if swAcc < 0.2 then
		return
	end
	swAcc = 0
	pcall(swRefresh)
end)

----------------------------------------------------------------
-- Speedometer (KM/H): หน้าต่างลอยเล็ก ลากย้ายได้ แสดงตอนนั่งรถ
-- 1 stud = 0.28 m (ค่ามาตรฐาน Roblox) -> 1 stud/s = 1.008 km/h
-- ถ้าไม่ตรงกับมาตรวัดของเกม ปรับ STUD_KMH ตรงนี้
----------------------------------------------------------------
local spW = new("Frame", {
	Size = UDim2.fromOffset(150, 56), Position = UDim2.new(0.5, -75, 1, -110),
	BackgroundColor3 = C.bg, BorderSizePixel = 0, Visible = false,
}, gui2)
round(spW, 12)
stroke(spW, C.winLine, 1)
local spNum = new("TextLabel", {
	Text = "0", TextSize = 26, TextColor3 = C.text, Font = F.bold,
	BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 32),
}, spW)
new("TextLabel", {
	Text = "KM/H", TextSize = 11, TextColor3 = C.muted, Font = F.medium,
	BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 16),
}, spW)

dragger(spW, function()
	local p = spW.Position
	return function(d)
		spW.Position = UDim2.new(p.X.Scale, p.X.Offset + d.X, p.Y.Scale, p.Y.Offset + d.Y)
	end
end)

--// ดึงเลขจาก UI ของเกม: หา TextLabel ที่เขียนว่า SPEED KM/H แล้วเอาเลขที่อยู่ใกล้ที่สุด
local gameSpd = nil
local function numText(o)
	return o:IsA("TextLabel") and o.Text:match("^%s*[%d%.]+%s*$") ~= nil
end
local function findGameSpeed()
	local pg = lplr:FindFirstChild("PlayerGui")
	if not pg then
		return nil
	end
	for _, o in ipairs(pg:GetDescendants()) do
		if o:IsA("TextLabel") then
			local t = o.Text:upper()
			if t:find("SPEED", 1, true) and t:find("KM", 1, true) then
				local scope = o.Parent
				for _ = 1, 2 do
					local best, bd
					if scope then
						for _, c in ipairs(scope:GetDescendants()) do
							if c ~= o and numText(c) then
								local d = (c.AbsolutePosition - o.AbsolutePosition).Magnitude
								if not bd or d < bd then
									best, bd = c, d
								end
							end
						end
					end
					if best then
						return best
					end
					scope = scope and scope.Parent
				end
			end
		end
	end
	return nil
end

local spScan = 1
bind(RunService.Heartbeat, function(dt)
	local seat = state.seat
	local show = cfg.speedOn and seat ~= nil and seat.Parent ~= nil
	spW.Visible = show
	if not show then
		return
	end
	local calc = seat.AssemblyLinearVelocity.Magnitude
	if not (gameSpd and gameSpd.Parent) then
		gameSpd = nil
		spScan = spScan + dt
		if spScan >= 3 then
			spScan = 0
			gameSpd = findGameSpeed()
		end
	end
	local gv = gameSpd and tonumber(gameSpd.Text:match("[%d%.]+"))
	if gv then
		spNum.Text = tostring(math.floor(gv + 0.5))
		-- ปรับค่าคูณให้ตรงเกมอัตโนมัติ (ใช้กับความเร็วรถผู้เล่นอื่นใน ESP)
		if calc > 20 and gv > 5 then
			STUD_KMH = clamp(STUD_KMH * 0.95 + (gv / calc) * 0.05, 0.3, 2)
		end
	else
		spNum.Text = tostring(math.floor(calc * STUD_KMH + 0.5))
	end
end)

local function mountGui(g)
	if gethui then
		local ok = pcall(function()
			g.Parent = gethui()
		end)
		if ok and g.Parent then
			return
		end
	end
	local ok = pcall(function()
		g.Parent = game:GetService("CoreGui")
	end)
	if ok and g.Parent then
		return
	end
	g.Parent = lplr:WaitForChild("PlayerGui")
end
mountGui(gui2)

toggleRow(pgStatus, "แสดงหน้าต่างสถานะ", "เปิดหน้าต่างลอย ลากที่หัวเพื่อย้าย ลากมุมล่างขวาเพื่อปรับขนาด", "statusOn")
toggleRow(pgStatus, "มาตรวัดความเร็ว (KM/H)", "แสดงความเร็วรถตอนนั่งรถ ลากย้ายตำแหน่งได้", "speedOn")
buttonRow(pgStatus, "รีเซ็ตหน้าต่าง", "คืนตำแหน่งและขนาดเริ่มต้น", "รีเซ็ต", function()
	sw.Size = UDim2.fromOffset(SW_W, SW_H)
	sw.Position = swDefaultPos()
end)
end

----------------------------------------------------------------
-- Streamer Mode: เปลี่ยนชื่อเราเป็นชื่อมั่วในหน้า Tab / Esc (CoreGui) เห็นเฉพาะบนจอเรา
----------------------------------------------------------------
local nh = { orig = {}, hooked = {}, fake = nil, add = nil }

local function nhRandom()
	local chars = "abcdefghijklmnopqrstuvwxyz"
	local s = ""
	for _ = 1, 7 do
		local i = math.random(1, #chars)
		s = s .. chars:sub(i, i)
	end
	return s:sub(1, 1):upper() .. s:sub(2) .. math.random(10, 99)
end

local function nhEsc(s)
	return (s:gsub("%p", "%%%0"))
end

local function nhApply(o)
	local t = o.Text
	if t == "" or not nh.fake then
		return
	end
	local a, b = lplr.DisplayName, lplr.Name
	if #b > #a then
		a, b = b, a
	end
	local nt = t
	if a ~= "" and nt:find(a, 1, true) then
		nt = nt:gsub(nhEsc(a), nh.fake)
	end
	if b ~= "" and nt:find(b, 1, true) then
		nt = nt:gsub(nhEsc(b), nh.fake)
	end
	if nt ~= t then
		nh.orig[o] = t
		o.Text = nt
	end
end

local function isOwnUI(o)
	local sg = o:FindFirstAncestorOfClass("ScreenGui")
	return sg ~= nil and sg.Name == "WindUI"
end

local function nhHook(o)
	if nh.hooked[o] or not (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then
		return
	end
	if o:IsDescendantOf(gui2) or isOwnUI(o) then
		return
	end
	nh.hooked[o] = o:GetPropertyChangedSignal("Text"):Connect(function()
		nhApply(o)
	end)
	nhApply(o)
end

local function nhSet(on)
	for _, c in pairs(nh.hooked) do
		c:Disconnect()
	end
	table.clear(nh.hooked)
	if nh.add then
		nh.add:Disconnect()
		nh.add = nil
	end
	for o, t in pairs(nh.orig) do
		if o.Parent then
			pcall(function()
				o.Text = t
			end)
		end
	end
	table.clear(nh.orig)
	if not on then
		return
	end
	nh.fake = nh.fake or nhRandom()
	pcall(function()
		local cg = game:GetService("CoreGui")
		for _, o in ipairs(cg:GetDescendants()) do
			nhHook(o)
		end
		nh.add = cg.DescendantAdded:Connect(nhHook)
	end)
end

local function antiPause()
	pcall(function()
		game:GetService("CoreGui").RobloxGui["CoreScripts/NetworkPause"]:Destroy()
	end)
end

----------------------------------------------------------------
-- หน้า Teleport
----------------------------------------------------------------
local pgTeleport = newPage("Teleport", "map-pin")
section(pgTeleport, "Teleport (วาร์ป)")
for _, w in ipairs(WAYPOINTS) do
	local p = w[2]
	buttonRow(pgTeleport, w[1], string.format("X %.0f   Y %.0f   Z %.0f", p.X, p.Y, p.Z), "วาร์ป", function()
		teleportTo(p)
	end)
end

----------------------------------------------------------------
-- หน้า Settings (ตั้งค่า)
----------------------------------------------------------------
local pgSettings = newPage("Settings", "settings")

--// ---------- Config (อยู่บนสุด) ----------
section(pgSettings, "Config")

local nameText = ""
local nameInput = make(pgSettings.tab, "Input", {
	Title = "Config Name",
	Desc = FS and "ชื่อที่ใช้ตอนกด Save (ว่าง = ใช้ชื่อที่ Select)" or "executor นี้ไม่รองรับ writefile/readfile",
	Value = "", Placeholder = "default",
	Callback = function(t)
		nameText = sanitize(t)
	end,
})
local function setNameText(t)
	nameText = t or ""
	pcall(nameInput.Set, nameInput, nameText)
end

local syncing = false
local cfgNames = listConfigs()
if #cfgNames == 0 then
	cfgNames = { "-" }
end
local selectConfig
local cfgDropdown = make(pgSettings.tab, "Dropdown", {
	Title = "Select Config", Desc = "เลือกคอนฟิกที่เซฟไว้ของเกมนี้",
	Values = cfgNames,
	Callback = function(opt)
		if syncing then
			return
		end
		if type(opt) == "table" then
			opt = opt.Title or opt[1]
		end
		if type(opt) == "string" and opt ~= selected and fileExists(cfgPath(opt)) then
			selectConfig(opt)
		end
	end,
})

local function refreshList()
	local names = listConfigs()
	if #names == 0 then
		names = { "-" }
	end
	pcall(function()
		cfgDropdown:Refresh(names)
	end)
end

local autoBtn

selectConfig = function(name)
	selected = name
	setNameText(name)
	ui.sync()
end

make(pgSettings.tab, "Button", {
	Title = "Refresh List", Desc = "โหลดรายชื่อคอนฟิกใหม่",
	Callback = function()
		refreshList()
		ui.sync()
	end,
})

make(pgSettings.tab, "Button", {
	Title = "Save", Desc = "บันทึกค่าตอนนี้ลงคอนฟิก",
	Callback = function()
		if not FS then
			setStatus("executor ไม่รองรับ writefile/readfile")
			return
		end
		local name = sanitize(nameText)
		if name == "" then
			name = selected or "default"
		end
		if saveConfig(name) then
			refreshList()
			selectConfig(name)
			setStatus("Saved: " .. name)
		else
			setStatus("Save ไม่สำเร็จ")
		end
	end,
})

make(pgSettings.tab, "Button", {
	Title = "Load", Desc = "โหลดคอนฟิกที่เลือก",
	Callback = function()
		if not FS then
			setStatus("executor ไม่รองรับ writefile/readfile")
			return
		end
		if not selected then
			setStatus("ยังไม่ได้เลือกคอนฟิก")
			return
		end
		local ok, err = loadConfig(selected)
		if ok then
			setStatus("Loaded: " .. selected)
		else
			setStatus("Load ไม่สำเร็จ: " .. tostring(err))
		end
	end,
})

local delArmed, delTok = false, 0
local delBtn
delBtn = make(pgSettings.tab, "Button", {
	Title = "Delete", Desc = "ลบคอนฟิกที่เลือก (กด 2 ครั้งเพื่อยืนยัน)",
	Callback = function()
		if not FS then
			setStatus("executor ไม่รองรับ writefile/readfile")
			return
		end
		if not has(delfile) then
			setStatus("executor ไม่รองรับ delfile")
			return
		end
		if not selected then
			setStatus("ยังไม่ได้เลือกคอนฟิก")
			return
		end
		if not delArmed then
			-- กดครั้งแรก: รอยืนยัน 3 วินาที
			delArmed = true
			delTok = delTok + 1
			local k = delTok
			pcall(function()
				delBtn:SetTitle("Delete · ยืนยัน?")
			end)
			task.delay(3, function()
				if k == delTok then
					delArmed = false
					pcall(function()
						delBtn:SetTitle("Delete")
					end)
				end
			end)
			return
		end
		delArmed = false
		delTok = delTok + 1
		pcall(function()
			delBtn:SetTitle("Delete")
		end)
		local name = selected
		if deleteConfig(name) then
			saveToken = saveToken + 1 -- ยกเลิก Auto Save ที่ค้างอยู่
			if autoloadName == name and writeAutoload(nil) then
				autoloadName = nil
			end
			refreshList()
			selectConfig(nil)
			setStatus("Deleted: " .. name)
		else
			setStatus("Delete ไม่สำเร็จ")
		end
	end,
})

-- Set as Autoload (กดครั้งแรก = ตั้ง, กดซ้ำ = ปิด)
autoBtn = make(pgSettings.tab, "Button", {
	Title = "Set as Autoload", Desc = "ยังไม่ได้ตั้ง Autoload",
	Callback = function()
		if not FS then
			setStatus("executor ไม่รองรับ writefile/readfile")
			return
		end
		if not selected then
			setStatus("ยังไม่ได้เลือกคอนฟิก")
			return
		end
		if not fileExists(cfgPath(selected)) then
			setStatus("คอนฟิกนี้ยังไม่ถูกเซฟ")
			return
		end
		if autoloadName == selected then
			if writeAutoload(nil) then
				autoloadName = nil
				setStatus("ปิด Autoload")
			end
		else
			if writeAutoload(selected) then
				autoloadName = selected
				setStatus("Autoload: " .. selected)
			end
		end
		ui.sync()
	end,
})

ui.sync = function()
	if selected then
		syncing = true
		pcall(function()
			cfgDropdown:Select(selected)
		end)
		syncing = false
	end
	pcall(function()
		autoBtn:SetDesc(autoloadName and ("Autoload ตอนนี้: " .. autoloadName .. " (กดตอนเลือกอันเดิมเพื่อปิด)")
			or "ยังไม่ได้ตั้ง Autoload")
	end)
end
ui.sync()

-- Auto Save
toggleRow(pgSettings, "Auto Save", "เซฟลงคอนฟิกที่ Select อยู่ หลังหยุดแก้ 1 วินาที และตอนปิดเมนู", "autoSave")

--// ---------- Settings เดิม ----------
section(pgSettings, "Settings (ตั้งค่า)")
keyRow(pgSettings, "ปุ่มซ่อน/แสดงเมนู", "กดช่องนี้แล้วกดปุ่มที่ต้องการ (Esc = ยกเลิก)", "uiKey")

section(pgSettings, "Fast Menu")
toggleRow(pgSettings, "Fast Menu",
	fireproximityprompt and "กดค้างปุ่มโต้ตอบแล้วทำงานทันที ไม่ต้องรอ"
		or "executor นี้ไม่รองรับ fireproximityprompt",
	"fastMenu")
toggleRow(pgSettings, "anti paused Game", "ลบ NetworkPause ไม่ให้เกมค้างหน้าจอตอนเน็ตหน่วง (ย้อนกลับไม่ได้จนกว่าจะเข้าเกมใหม่)", "antiPause", function()
	if cfg.antiPause then
		antiPause()
	end
end)

section(pgSettings, "Streamer Mode")
toggleRow(pgSettings, "Streamer Mode", "เปลี่ยนชื่อคุณเป็นชื่อมั่วในหน้า Tab และ Esc (เห็นเฉพาะบนจอคุณ)", "nameHide", function()
	nhSet(cfg.nameHide)
end)
local _, nhDesc
_, nhDesc = buttonRow(pgSettings, "สุ่มชื่อใหม่", "ชื่อปัจจุบัน: " .. (nh.fake or "ยังไม่สุ่ม"), "สุ่ม", function()
	nh.fake = nhRandom()
	nhDesc.Text = "ชื่อปัจจุบัน: " .. nh.fake
	if cfg.nameHide then
		nhSet(true)
	end
end)

local cleaned = false
local function cleanup()
	if cleaned then
		return
	end
	cleaned = true
	alive = false
	pcall(nhSet, false)
	env.__VehicleHubEcuFn = nil
	if espCleanup then
		pcall(espCleanup)
	end
	if cfg.autoSave and FS then
		pcall(saveConfig, selected or "default")
	end
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	if state.hb then
		state.hb:Disconnect()
		state.hb = nil
	end
	if seatConn then
		seatConn:Disconnect()
		seatConn = nil
	end
	pcall(function()
		gui2:Destroy()
	end)
	pcall(function()
		Window:Destroy()
	end)
	env.__VehicleHubCleanup = nil
end
env.__VehicleHubCleanup = cleanup
pcall(function()
	Window:OnDestroy(cleanup)
end)

refreshList()

-- Autoload: โหลดคอนฟิกที่ตั้งไว้ตอนเปิดสคริปต์
autoloadName = readAutoload()
if autoloadName then
	if loadConfig(autoloadName) then
		selected = autoloadName
		setNameText(autoloadName)
		setStatus("Autoload: " .. autoloadName)
	else
		autoloadName = nil
	end
end
ui.sync()

if cfg.antiPause then
	antiPause()
end