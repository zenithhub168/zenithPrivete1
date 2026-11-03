--// ECU Hub (WindUI) : Link AIR+FUEL / Auto Tune AIR+FUEL / TPS+IGN / ไล่รถ / จูนทั้งหมด
--// กดปุ่มซ่อน/แสดงเมนู: RightShift

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local lplr = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.__ECUHubWindCleanup then
	pcall(env.__ECUHubWindCleanup)
end

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

local cfg = { ecuLink = true }
local alive = true
local conns = {}
local function bind(sig, fn)
	local c = sig:Connect(fn)
	conns[#conns + 1] = c
	return c
end

----------------------------------------------------------------
-- ECU Link: จูน AIR หรือ FUEL อันเดียว ส่งค่าเดียวกันทั้งสองอัน
----------------------------------------------------------------
local ecuLastA, ecuLastB
local ecuSeq, ecuBypass = 0, false

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

env.__ECUHubWindFn = function(old, method, self, ...)
	if alive and method == "FireServer" and typeof(self) == "Instance"
		and self.ClassName == "RemoteEvent" and self.Name == "ECUTune_Save" then
		local args = table.pack(...)
		if type(args[5]) == "number" and args[5] > ecuSeq then
			ecuSeq = args[5]
		end
		if cfg.ecuLink and not ecuBypass and pcall(ecuLinkArgs, args) then
			if setnamecallmethod then
				setnamecallmethod(method)
			end
			return old(self, table.unpack(args, 1, args.n))
		end
	end
	return old(self, ...)
end

if hookmetamethod and getnamecallmethod and not env.__ECUHubWindHooked then
	env.__ECUHubWindHooked = true
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local fn = env.__ECUHubWindFn
		if fn then
			return fn(oldNamecall, getnamecallmethod(), self, ...)
		end
		return oldNamecall(self, ...)
	end))
end

----------------------------------------------------------------
-- ECU Auto Tune
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

local function ecuAutoTune(mode)
	local a, car = ecuGetActive()
	if not a then
		return false, car
	end
	local ok, air, fuel, tps, ign, bad = pcall(function()
		local air, fuel, tps, ign, bad = nil, nil, nil, nil, 0
		if mode == "af" then
			air, fuel, bad = ecuBuildAF(a)
			tps, ign = ecuCopy(a.TPSMap), ecuCopy(a.IgnMap)
		elseif mode == "all" then
			local b1, b2
			air, fuel, b1 = ecuBuildAF(a)
			-- ตั้งค่า AIR/FUEL ที่ปรับละเอียดแล้วกลับเข้ารถ ก่อนคำนวณ IGN (IGN คิดจากสถานะ AIR/FUEL)
			a:SetMap("Air", air)
			a:SetMap("Fuel", fuel)
			tps, ign, b2 = ecuBuildTI(a)
			bad = b1 + b2
		else
			air, fuel = ecuCopy(a.Config.Air and a.Config.Air.Map), ecuCopy(a.Config.Fuel and a.Config.Fuel.Map)
			tps, ign, bad = ecuBuildTI(a)
		end
		return air, fuel, tps, ign, bad
	end)
	if not ok then
		return false, air
	end
	local pop = ecuCopy(a.PopMap or a:GenerateInitialPop())
	local remote = RS:FindFirstChild("ECUTune_Save")
	if not remote then
		return false, "ไม่พบ ECUTune_Save"
	end
	ecuSeq = ecuSeq + 1
	ecuBypass = true
	local sent, err = pcall(function()
		remote:FireServer(car:GetAttribute("CarId") or car.Name, air, fuel, false, ecuSeq, tps, pop, ign, car)
	end)
	ecuBypass = false
	if not sent then
		return false, err
	end
	return true, bad == 0 and "เขียวครบ" or ("ไม่เขียว " .. bad .. " จุด")
end

----------------------------------------------------------------
-- Free Tune (ไล่รถ)
----------------------------------------------------------------
-- พรีเซ็ตไล่รถ: p = น้ำหนักกำลัง, s = น้ำหนักความเร็วปลาย, w(t) = น้ำหนักตามตำแหน่งย่าน (t 0 = ต้น, 1 = ปลาย)
local function uniform()
	return 1
end
local FT_PRESETS = {
	["สมดุล"] = { p = 1, s = 0.5, w = uniform }, -- สูตรเดิม แรงเท่าเดิม
	["เต็มเร็ว"] = { p = 0.5, s = 1, w = uniform }, -- เน้นความเร็วปลาย แต่ยังคุมกำลังไว้
	["ไหลปลาย"] = { p = 1, s = 0.5, w = function(t) return t ^ 2 + 0.05 end }, -- เน้นกำลังย่านปลาย
}
local ftMode = "สมดุล"

local function ftScore(FT, seed, x)
	local pr = FT_PRESETS[ftMode] or FT_PRESETS["สมดุล"]
	local eR, eS = FT.Effects(seed, { x[1], x[2], x[3], x[4], x[5] }, { x[6], x[7], x[8], x[9], x[10] })
	local sr, ss, sw = 0, 0, 0
	for k = 0, 10 do
		local t = k / 10
		local w = pr.w(t)
		sr = sr + w * (1 + FT.LevelAt(eR, t))
		ss = ss + w * (1 + FT.LevelAt(eS, t))
		sw = sw + w
	end
	local P = (sr / sw) * (ss / sw)
	local V = FT.SpeedDelta(eR, eS)
	return pr.p * (P - 1) + pr.s * (V / 60), P, V
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
	return true, string.format("[%s] กำลัง %+.1f%% (เดิม %+.1f%%) · ปลาย %+.0f km/h", ftMode, (P - 1) * 100, (P0 - 1) * 100, V)
end

----------------------------------------------------------------
-- UI (WindUI)
----------------------------------------------------------------
local okLib, WindUI = pcall(function()
	return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not okLib or type(WindUI) ~= "table" then
	alive = false
	env.__ECUHubWindFn = nil
	warn("[ECUHub] โหลด WindUI ไม่สำเร็จ: " .. tostring(WindUI))
	return
end

local Window = WindUI:CreateWindow({
	Title = "ECU Hub",
	Icon = "wrench",
	Author = "จูนเครื่อง · ไล่รถ",
	Folder = "ECUHub",
	Size = UDim2.fromOffset(580, 460),
	ToggleKey = Enum.KeyCode.RightShift,
	Theme = "Dark",
	Resizable = true,
})

local Tab = Window:Tab({ Title = "ECU", Icon = "cpu" })

Tab:Toggle({
	Title = "Link AIR + FUEL",
	Desc = hookmetamethod and "แก้ AIR หรือ FUEL อันเดียว ส่งเข้า ECU ได้ทั้งสองอัน"
		or "executor นี้ไม่รองรับ hookmetamethod",
	Value = cfg.ecuLink,
	Callback = function(state)
		cfg.ecuLink = state
	end,
})

Tab:Dropdown({
	Title = "โหมดไล่รถ",
	Desc = "สมดุล = ค่าเดิม · เต็มเร็ว = ความเร็วปลายสูงสุด · ไหลปลาย = ลากแรงถึงปลาย",
	Values = { "สมดุล", "เต็มเร็ว", "ไหลปลาย" },
	Value = "สมดุล",
	Callback = function(v)
		if type(v) == "table" then
			v = v.Title or v[1]
		end
		if FT_PRESETS[v] then
			ftMode = v
		end
	end,
})

local busy = false
local function tuneButton(title, desc, fn)
	local btn
	btn = Tab:Button({
		Title = title,
		Desc = desc,
		Callback = function()
			if busy then
				return
			end
			busy = true
			btn:SetDesc("กำลังคำนวณ...")
			task.spawn(function()
				local okc, ok, msg = pcall(fn)
				if not okc then
					ok, msg = false, ok -- fn error: ok ตัวแรกคือข้อความ error
				end
				busy = false
				btn:SetDesc((ok and "สำเร็จ · " or "ล้มเหลว · ") .. tostring(msg))
				pcall(function()
					WindUI:Notify({
						Title = ok and "จูนสำเร็จ" or "จูนไม่สำเร็จ",
						Content = tostring(msg),
						Duration = 6,
					})
				end)
				if not ok then
					warn("[ECUHub] " .. tostring(msg))
				end
			end)
		end,
	})
end

tuneButton("Auto Tune ทั้งหมด", "AIR/FUEL + TPS/IGN (ส่งครั้งเดียว) แล้วไล่รถ", function()
	local parts, allOk = {}, true
	local function run(name, fn)
		local ok, msg = fn()
		allOk = allOk and ok
		parts[#parts + 1] = name .. ": " .. (ok and "" or "ล้มเหลว ") .. tostring(msg)
		if not ok then
			warn("[ECUHub] " .. name .. ": " .. tostring(msg))
		end
	end
	run("ECU", function() return ecuAutoTune("all") end)
	task.wait(1.5) -- รอเซิร์ฟเวอร์บันทึกก่อนไล่รถ
	run("ไล่รถ", ftAutoTune)
	return allOk, table.concat(parts, " · ")
end)

tuneButton("Auto Tune AIR + FUEL", "ตั้งให้เกรดสูงสุดทุกจุด แล้วส่งเข้า ECU", function()
	return ecuAutoTune("af")
end)

tuneButton("Auto Tune TPS + IGN", "ตั้งให้เขียวเข้มทุกจุด แล้วส่งเข้า ECU", function()
	return ecuAutoTune("ti")
end)

tuneButton("Auto Tune ไล่รถ", "หาค่า A/B ที่ดีที่สุดภายในแต้มที่มี แล้วบันทึก", ftAutoTune)

Tab:Select()

local function cleanup()
	alive = false
	env.__ECUHubWindFn = nil
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		Window:Destroy()
	end)
	env.__ECUHubWindCleanup = nil
end
env.__ECUHubWindCleanup = cleanup
pcall(function()
	Window:OnDestroy(function()
		alive = false
		env.__ECUHubWindFn = nil
	end)
end)