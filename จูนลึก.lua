--// ECU Hub (WindUI)
--// จูน ECU (AIR / FUEL / TPS / IGN) + ไล่รถ (Free Tune) ให้อัตโนมัติ
--// กด RightShift = ซ่อน/แสดงเมนู
--//
--// โครงสร้างไฟล์
--//   1) ตั้งต้น          2) ECU (Link + Auto Tune)
--//   3) ไล่รถ (Free Tune: โหมด + ค้นหา + บันทึก)
--//   4) UI: แท็บ "จูน" / "เทียบโหมด" / "เบื้องลึก"
--// หมายเหตุ: ตัวเลข "แรง/ปลาย" เป็นค่าประมาณจากระบบจูนของเกม ไม่ใช่ค่าไดโน่จริง

----------------------------------------------------------------
-- 1) ตั้งต้น
----------------------------------------------------------------
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lplr = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if env.__ECUHubWindCleanup then
	pcall(env.__ECUHubWindCleanup)
end

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

local cfg = { ecuLink = true } -- Link AIR+FUEL (ปรับได้ในแท็บเบื้องลึก)
local alive = true

----------------------------------------------------------------
-- 2) ECU · Link: จูน AIR หรือ FUEL อันเดียว ส่งค่าเดียวกันทั้งสองอัน
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
-- 3) ไล่รถ (Free Tune)
----------------------------------------------------------------
-- โหมดไล่รถ: p = น้ำหนักกำลัง, s = น้ำหนักความเร็วปลาย, w(t) = น้ำหนักตามย่าน (t 0 = ต้น, 1 = ปลาย)
local function uniform()
	return 1
end
local FT_MODES = { "สมดุล", "แรงสุด", "เต็มเร็ว", "เต็มช้า", "ไหลปลาย" }
local FT_PRESETS = {
	["สมดุล"] = { p = 1, s = 0.5, w = uniform },
	["แรงสุด"] = { p = 1, s = 0, w = uniform },
	["เต็มเร็ว"] = { p = 0.5, s = 1, w = uniform },
	["เต็มช้า"] = { p = 1, s = 0, w = function(t) return (1 - t) ^ 2 + 0.05 end },
	["ไหลปลาย"] = { p = 1, s = 0.5, w = function(t) return t ^ 2 + 0.05 end },
}
FT_PRESETS["ดีที่สุดรวม"] = { p = 1, s = 1, w = uniform } -- ใช้กับปุ่มหาค่าดีที่สุด
local ftMode = "เต็มเร็ว"

-- ระดับการค้นหา: restarts = จำนวนรอบสุ่มเริ่มใหม่, ils = รอบสะกิดค่าที่ดีสุดแล้วไต่ใหม่, cap = เพดานเวลา (วินาที)
local FT_DEPTHS = {
	["ปกติ"] = { restarts = 10, ils = 0, cap = 15 },
	["ลึก"] = { restarts = 30, ils = 40, cap = 25 },
	["สุดๆ"] = { restarts = 60, ils = 150, cap = 50 },
}
local ftDepth = "ลึก"

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
	local depth = FT_DEPTHS[ftDepth] or FT_DEPTHS["ปกติ"]
	local t0 = os.clock()
	local function timeUp()
		return os.clock() - t0 > depth.cap
	end
	local bestX, bestS
	local function try(x)
		local s = climb(x)
		if not bestS or s > bestS then
			bestS, bestX = s, table.clone(x)
		end
		task.wait()
	end

	-- เติมแต้มที่เหลือ: เพิ่มสไลเดอร์ทีละ +1 ตราบที่คะแนนไม่ลดลง
	local function fill(x)
		local s0 = ftScore(FT, seed, x)
		while true do
			local rem = budget - posCost(x)
			local bi, bsc
			for i = 1, 10 do
				if x[i] >= 0 and x[i] < 10 and cost[i] <= rem + 1e-9 then
					x[i] = x[i] + 1
					local sc = ftScore(FT, seed, x)
					x[i] = x[i] - 1
					if sc >= s0 - 1e-9 and (not bsc or sc > bsc) then
						bi, bsc = i, sc
					end
				end
			end
			if not bi then
				break
			end
			x[bi] = x[bi] + 1
			s0 = bsc
		end
		return x
	end

	try({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
	try(table.clone(start))
	for _ = 1, depth.restarts do
		if timeUp() then
			break
		end
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
	-- สะกิดค่าที่ดีที่สุดเล็กน้อยแล้วไต่ใหม่ (ช่วยหลุดจากจุดตัน)
	for _ = 1, depth.ils do
		if timeUp() then
			break
		end
		local x = table.clone(bestX)
		for _ = 1, rng:NextInteger(2, 4) do
			local i = rng:NextInteger(1, 10)
			x[i] = clamp(x[i] + rng:NextInteger(-5, 5), -10, 10)
		end
		while posCost(x) > budget do
			local i = rng:NextInteger(1, 10)
			if x[i] > 0 then
				x[i] = x[i] - 1
			end
		end
		try(x)
	end
	return fill(bestX)
end

local function ftPrepare()
	local pg = lplr:FindFirstChild("PlayerGui")
	local itf = pg and pg:FindFirstChild("Interface")
	local bike = itf and itf:FindFirstChild("Bike")
	local car = bike and bike.Value
	if not car then
		return nil, "ไม่ได้นั่งรถ"
	end
	local get, set = RS:FindFirstChild("FreeTune_Get"), RS:FindFirstChild("FreeTune_Set")
	if not (get and set) then
		return nil, "ไม่พบระบบไล่รถ"
	end
	local tuner = car:FindFirstChild("Tuner")
	local modS = tuner and tuner:FindFirstChild("FreeTuneMods")
	local okM, FT = pcall(require, modS)
	if not (okM and type(FT) == "table" and FT.Effects) then
		return nil, "ไม่พบ FreeTuneMods"
	end

	local carId = car:GetAttribute("CarId") or car.Name
	local okG, res = pcall(function()
		return get:InvokeServer(carId, car)
	end)
	if not okG or type(res) ~= "table" then
		return nil, "โหลดค่าจูนไม่สำเร็จ"
	end
	if res.canEdit ~= true then
		return nil, "ไม่ใช่เจ้าของรถ แก้ไม่ได้"
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
	return {
		car = car, carId = carId, FT = FT, set = set, get = get,
		seed = tonumber(car:GetAttribute("FT_Seed")) or 1,
		budget = math.max(tonumber(res.budget) or 25, saved),
		cr = cr, cs = cs,
		start = { rev[1], rev[2], rev[3], rev[4], rev[5], spd[1], spd[2], spd[3], spd[4], spd[5] },
	}
end

-- คำนวณสรุปตามโหมดปัจจุบัน แล้วบันทึก (ถ้าไม่ใช่ dry)
local function ftFinish(c, x, dry)
	local _, Pm, V = ftScore(c.FT, c.seed, x) -- Pm = กำลังถ่วงตามย่านที่โหมดเน้น
	local prevMode = ftMode
	ftMode = "ดีที่สุดรวม" -- ถ่วงเท่ากันทุกย่าน เทียบข้ามโหมดได้
	local _, P = ftScore(c.FT, c.seed, x)
	local _, P0, V0 = ftScore(c.FT, c.seed, c.start)
	ftMode = prevMode
	local used = 0
	for i = 1, 10 do
		used = used + math.max(x[i], 0) * (i <= 5 and c.cr or c.cs)
	end
	local focus = ""
	if math.abs(Pm - P) > 1e-6 then
		focus = string.format(" (ช่วงที่เน้น %+.1f%%)", (Pm - 1) * 100)
	end
	local summary = string.format("[%s] แรงประมาณ %+.1f%% (เดิม %+.1f%%)%s · ปลายประมาณ %+.0f km/h · แต้ม %s/%s",
		ftMode, (P - 1) * 100, (P0 - 1) * 100, focus, V, tostring(used), tostring(c.budget))
	if dry then
		return true, summary, { P = P, V = V, P0 = P0, V0 = V0 }
	end
	local newT = {
		rev = { x[1], x[2], x[3], x[4], x[5] },
		spd = { x[6], x[7], x[8], x[9], x[10] },
	}
	local okS, r1, r2 = pcall(function()
		return c.set:InvokeServer(c.carId, c.car, newT)
	end)
	if not okS or r1 ~= true then
		return false, tostring(okS and r2 or r1 or "บันทึกไม่สำเร็จ")
	end
	-- ยืนยัน: อ่านค่ากลับจากเซิร์ฟเวอร์ว่าตรงกับที่ตั้งจริง
	local verified = false
	local okV, back = pcall(function()
		return c.get:InvokeServer(c.carId, c.car)
	end)
	if okV and type(back) == "table" and type(back.rev) == "table" and type(back.spd) == "table" then
		verified = true
		for i = 1, 5 do
			if tonumber(back.rev[i]) ~= x[i] or tonumber(back.spd[i]) ~= x[5 + i] then
				verified = false
				break
			end
		end
	end
	summary = summary .. (verified and " · ✔ ยืนยันค่าในเซิร์ฟเวอร์แล้ว" or " · ⚠ ยืนยันค่าไม่ได้")
	return true, summary, { P = P, V = V, P0 = P0, V0 = V0 }
end

local function ftRun(dry)
	local c, err = ftPrepare()
	if not c then
		return false, err
	end
	local x = ftSearch(c.FT, c.seed, c.budget, c.cr, c.cs, c.start)
	return ftFinish(c, x, dry)
end

-- dry = true: คำนวณอย่างเดียว ไม่บันทึก / mode = ใช้โหมดนั้นชั่วคราว
local function ftAutoTune(dry, mode)
	local prev = ftMode
	if mode and FT_PRESETS[mode] then
		ftMode = mode
	end
	local okc, ok, msg, data = pcall(ftRun, dry == true)
	ftMode = prev
	if not okc then
		return false, tostring(ok)
	end
	return ok, msg, data
end

-- หาค่าดีที่สุด: ค้นหาทุกโหมด (ระดับปกติ) เป็นจุดเริ่ม เลือกชุดที่ได้ "กำลังเฉลี่ย + ความเร็วปลาย" รวมสูงสุด
-- แล้วขัดต่อด้วยระดับการค้นหาที่เลือก
local function ftBest(dry)
	local c, err = ftPrepare()
	if not c then
		return false, err
	end
	local prevDepth = ftDepth
	ftDepth = "ปกติ"
	local pool = { table.clone(c.start) }
	for _, m in ipairs(FT_MODES) do
		ftMode = m
		pool[#pool + 1] = ftSearch(c.FT, c.seed, c.budget, c.cr, c.cs, c.start)
	end
	ftMode = "ดีที่สุดรวม"
	local bestX, bestS
	for _, x in ipairs(pool) do
		local sc = ftScore(c.FT, c.seed, x)
		if not bestS or sc > bestS then
			bestS, bestX = sc, x
		end
	end
	ftDepth = prevDepth
	local x = ftSearch(c.FT, c.seed, c.budget, c.cr, c.cs, bestX)
	if (ftScore(c.FT, c.seed, bestX)) > (ftScore(c.FT, c.seed, x)) then
		x = bestX
	end
	return ftFinish(c, x, dry)
end

local function ftAutoBest(dry)
	local prevMode, prevDepth = ftMode, ftDepth
	local okc, ok, msg = pcall(ftBest, dry == true)
	ftMode, ftDepth = prevMode, prevDepth
	if not okc then
		return false, tostring(ok)
	end
	return ok, msg
end

----------------------------------------------------------------
-- 4) UI
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

local busy = false

local function notify(title, content, duration)
	pcall(function()
		WindUI:Notify({ Title = title, Content = tostring(content), Duration = duration or 10 })
	end)
end

-- ปุ่มที่รัน fn โดยไม่ให้กดซ้อน ถ้า fn error ปุ่มจะไม่ค้าง
-- fn ต้องคืนค่า (สำเร็จ?, ข้อความ)
local function action(tab, title, desc, fn)
	local btn
	btn = tab:Button({
		Title = title,
		Desc = desc,
		Callback = function()
			if busy then
				notify("รอสักครู่", "กำลังทำงานอยู่ รอให้เสร็จก่อน", 3)
				return
			end
			busy = true
			btn:SetDesc("กำลังคำนวณ... รอสักครู่")
			task.spawn(function()
				local okc, ok, msg = pcall(fn)
				if not okc then
					ok, msg = false, ok
				end
				busy = false
				btn:SetDesc(ok and ("เสร็จแล้ว · " .. desc) or ("ไม่สำเร็จ · " .. tostring(msg)))
				notify(ok and "เสร็จแล้ว" or "ไม่สำเร็จ", msg)
				if not ok then
					warn("[ECUHub] " .. tostring(msg))
				end
			end)
		end,
	})
end

local function dropdown(tab, title, desc, values, current, onPick)
	tab:Dropdown({
		Title = title,
		Desc = desc,
		Values = values,
		Value = current,
		Callback = function(v)
			if type(v) == "table" then
				v = v.Title or v[1]
			end
			onPick(v)
		end,
	})
end

--// ---------- แท็บ 1: จูน (ใช้งานทั่วไป) ----------
local TabMain = Window:Tab({ Title = "จูน", Icon = "cpu" })

action(TabMain, "1. จูนเลย (แนะนำ)", "จูน ECU + ไล่รถให้ดีที่สุดรอบด้าน อัตโนมัติ", function()
	local ok1, m1 = ecuAutoTune("all")
	task.wait(1.5)
	local ok2, m2 = ftAutoBest()
	return ok1 and ok2, "ECU: " .. tostring(m1) .. "\nไล่รถ: " .. tostring(m2)
end)

action(TabMain, "2. จูน ECU อย่างเดียว", "ตั้ง AIR / FUEL / TPS / IGN ให้เขียว", function()
	return ecuAutoTune("all")
end)

action(TabMain, "3. ไล่รถ เน้นแรง", "ไล่รถให้กำลังเฉลี่ยสูงสุด", function()
	return ftAutoTune(false, "แรงสุด")
end)

action(TabMain, "4. ไล่รถ เน้นความเร็วปลาย", "ไล่รถให้ความเร็วปลายสูงสุด", function()
	return ftAutoTune(false, "เต็มเร็ว")
end)

--// ---------- แท็บ 2: เทียบโหมด (ไม่บันทึก) ----------
local TabCmp = Window:Tab({ Title = "เทียบโหมด", Icon = "bar-chart" })
local recMode -- โหมดที่แนะนำจากการเทียบล่าสุด

action(TabCmp, "เทียบทุกโหมด + แนะนำ (ไม่บันทึก)", "คำนวณทุกโหมดแล้วโชว์ผลเทียบกัน ไม่แก้ค่าในรถ", function()
	local rows = {}
	local prevDepth = ftDepth
	ftDepth = "ปกติ" -- เทียบหลายโหมดใช้ระดับเร็ว ไม่ให้นานเกิน
	local failMsg
	for _, m in ipairs(FT_MODES) do
		local ok, msg, d = ftAutoTune(true, m)
		if not ok then
			failMsg = "[" .. m .. "] ล้มเหลว " .. tostring(msg)
			break
		end
		rows[#rows + 1] = { mode = m, P = d.P, V = d.V, P0 = d.P0, V0 = d.V0, detail = msg }
	end
	ftDepth = prevDepth
	if failMsg then
		return false, failMsg
	end

	local maxG, maxV = 1e-9, 1e-9
	for _, r in ipairs(rows) do
		maxG = math.max(maxG, r.P - 1)
		maxV = math.max(maxV, r.V)
	end
	local bestAll, bestP, bestV
	for _, r in ipairs(rows) do
		r.score = math.max(r.P - 1, 0) / maxG + math.max(r.V, 0) / maxV
		if not bestAll or r.score > bestAll.score then bestAll = r end
		if not bestP or r.P > bestP.P then bestP = r end
		if not bestV or r.V > bestV.V then bestV = r end
	end
	recMode = bestAll.mode

	local first = rows[1]
	local lines = {
		"(ตัวเลขเป็นค่าประมาณจากระบบจูนของเกม ไม่ใช่ค่าไดโน่)",
		string.format("ตอนนี้ในรถ: แรง %+.0f%% · ปลาย %+.0f", (first.P0 - 1) * 100, first.V0),
		"",
	}
	for _, r in ipairs(rows) do
		lines[#lines + 1] = string.format("%s%s: แรง %+.0f%% · ปลาย %+.0f",
			r == bestAll and "★ " or "", r.mode, (r.P - 1) * 100, r.V)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "★ = แนะนำ (แรงและปลายรวมดีสุด)"
	lines[#lines + 1] = string.format("เน้นแรง → %s · เน้นความเร็วปลาย → %s", bestP.mode, bestV.mode)
	if bestAll.P <= first.P0 + 0.002 and bestAll.V <= first.V0 + 0.5 then
		lines[#lines + 1] = "ค่าในรถตอนนี้ดีอยู่แล้ว ไม่ต้องเปลี่ยนก็ได้"
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "— รายละเอียดแต่ละโหมด —"
	for _, r in ipairs(rows) do
		lines[#lines + 1] = r.detail
	end
	lines[#lines + 1] = "(แรงประมาณ = ถ่วงเท่ากันทุกย่าน · ช่วงที่เน้น = เฉพาะย่านที่โหมดนั้นเน้น · แต้ม = ใช้/มี)"
	return true, table.concat(lines, "\n")
end)

action(TabCmp, "ใช้โหมดที่แนะนำ (บันทึก)", "ไล่รถด้วยโหมดที่ ★ แนะนำจากการเทียบรอบล่าสุด แล้วบันทึกเข้ารถ", function()
	if not recMode then
		return false, "กดปุ่มเทียบทุกโหมดก่อน"
	end
	return ftAutoTune(false, recMode)
end)

--// ---------- แท็บ 3: เบื้องลึก (ปรับเอง) ----------
local TabDeep = Window:Tab({ Title = "เบื้องลึก", Icon = "settings" })

TabDeep:Toggle({
	Title = "Link AIR + FUEL",
	Desc = hookmetamethod and "ตอนจูนกราฟเองในเกม แก้ AIR หรือ FUEL อันเดียว อีกอันตามให้"
		or "executor นี้ไม่รองรับ hookmetamethod",
	Value = cfg.ecuLink,
	Callback = function(state)
		cfg.ecuLink = state
	end,
})

dropdown(TabDeep, "โหมดไล่รถ", "ใช้กับปุ่ม 'ไล่รถ (ตามโหมด)' ด้านล่าง", FT_MODES, ftMode, function(v)
	if FT_PRESETS[v] then
		ftMode = v
	end
end)

dropdown(TabDeep, "ความละเอียดการค้นหา", "ปกติ = เร็ว · ลึก = หาค่าดีขึ้น (~25 วิ) · สุดๆ = ละเอียดสุด (~50 วิ)",
	{ "ปกติ", "ลึก", "สุดๆ" }, ftDepth, function(v)
		if FT_DEPTHS[v] then
			ftDepth = v
		end
	end)

action(TabDeep, "Auto Tune AIR + FUEL", "ตั้งให้เกรดสูงสุดทุกจุด แล้วส่งเข้า ECU", function()
	return ecuAutoTune("af")
end)

action(TabDeep, "Auto Tune TPS + IGN", "ตั้งให้เขียวเข้มทุกจุด แล้วส่งเข้า ECU", function()
	return ecuAutoTune("ti")
end)

action(TabDeep, "ไล่รถ (ตามโหมด)", "ไล่รถตามโหมดและความละเอียดที่เลือกด้านบน แล้วบันทึก", function()
	return ftAutoTune()
end)

action(TabDeep, "ไล่รถ: หาค่าดีที่สุด", "ลองทุกโหมดเป็นจุดเริ่ม เลือกชุดที่ดีรอบด้านสุด แล้วบันทึก", function()
	return ftAutoBest()
end)

action(TabDeep, "ดูข้อมูลรถ (ก๊อปส่งให้ผม)", "เก็บค่าของรถและระบบจูนลงคลิปบอร์ด + คอนโซล (F9)", function()
	local pg = lplr:FindFirstChild("PlayerGui")
	local itf = pg and pg:FindFirstChild("Interface")
	local bike = itf and itf:FindFirstChild("Bike")
	local car = bike and bike.Value
	if not car then
		return false, "ไม่ได้นั่งรถ"
	end
	local out = {}
	local function add(t)
		out[#out + 1] = t
	end
	local function dumpTable(name, t)
		add("== " .. name .. " ==")
		local keys = {}
		for k in pairs(t) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local v = t[k]
			if v == nil then
				v = t[tonumber(k)]
			end
			local tv = type(v)
			if tv == "table" or tv == "function" or tv == "userdata" then
				add(k .. " : " .. tv)
			else
				add(k .. " = " .. tostring(v))
			end
		end
	end

	add("CarId: " .. tostring(car:GetAttribute("CarId") or car.Name))
	dumpTable("Car attributes", car:GetAttributes())

	local tuner = car:FindFirstChild("Tuner")
	if tuner then
		local kids = {}
		for _, ch in ipairs(tuner:GetChildren()) do
			kids[#kids + 1] = ch.Name .. " (" .. ch.ClassName .. ")"
		end
		add("== Tuner children ==")
		add(table.concat(kids, ", "))
		local ftS = tuner:FindFirstChild("FreeTuneMods")
		if ftS then
			local ok, FT = pcall(require, ftS)
			if ok and type(FT) == "table" then
				dumpTable("FreeTuneMods", FT)
			end
		end
	end

	local a = ecuGetActive()
	if a then
		dumpTable("EngineMods.Active", a)
		if type(a.Config) == "table" then
			dumpTable("EngineMods.Active.Config", a.Config)
		end
	end

	local text = table.concat(out, "\n")
	print("[ECUHub] ===== ข้อมูลรถ =====\n" .. text)
	local copied = false
	if setclipboard then
		copied = pcall(setclipboard, text)
	end
	return true, (copied and "ก๊อปลงคลิปบอร์ดแล้ว วางส่งให้ผมได้เลย" or "พิมพ์ลงคอนโซล (F9) แล้ว ก๊อปส่งให้ผม")
		.. " · " .. #out .. " บรรทัด"
end)

TabMain:Select()

----------------------------------------------------------------
-- ปิดสคริปต์ / รันซ้ำ
----------------------------------------------------------------
local function cleanup()
	alive = false
	env.__ECUHubWindFn = nil
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