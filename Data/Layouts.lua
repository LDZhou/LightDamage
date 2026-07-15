--[[
    Light Damage 2.0 - layout definitions, scene workspaces and migration.

    Layout coordinates are 1-based inclusive.  A definition owns only its
    topology and track ratios; each scene workspace owns the outer window
    geometry and the selected layout.
]]
local addonName, ns = ...

local Layouts = {}
ns.Layouts = Layouts

Layouts.SCHEMA = 3
Layouts.PRESET_1 = "preset1"
Layouts.PRESET_2 = "preset2"
Layouts.PRESET_3 = "preset3"
Layouts.DEFAULT_LAYOUT = Layouts.PRESET_2
Layouts.MIN_COL_W = 72
Layouts.MIN_ROW_H = 36
Layouts.GAP = 2

Layouts.SCENES = { "mplus", "raid", "dungeon", "arena", "battleground", "outdoor" }
Layouts.STATS = { "damage", "healing", "damageTaken", "deaths", "enemyDamageTaken", "interrupts", "dispels" }
Layouts.RANGES = { "follow", "total" }
local SCENE_NAME_KEYS={mplus="SCENE_MPLUS",raid="SCENE_RAID",dungeon="SCENE_DUNGEON",arena="SCENE_ARENA",battleground="SCENE_BATTLEGROUND",outdoor="SCENE_OUTDOOR"}

local VALID_SCENE, VALID_STAT, VALID_RANGE = {}, {}, {}
local SCENE_ORDER = {}
for i, v in ipairs(Layouts.SCENES) do VALID_SCENE[v] = true; SCENE_ORDER[v] = i end
for _, v in ipairs(Layouts.STATS) do VALID_STAT[v] = true end
for _, v in ipairs(Layouts.RANGES) do VALID_RANGE[v] = true end

local function copy(v)
    return type(v) == "table" and CopyTable(v) or v
end

local function normalizeRatios(values, count)
    local out, sum = {}, 0
    for i = 1, count do
        local v = type(values) == "table" and tonumber(values[i]) or nil
        if not v or v ~= v or v <= 0 then v = 1 / count end
        out[i], sum = v, sum + v
    end
    if sum <= 0 then sum = count end
    for i = 1, count do out[i] = out[i] / sum end
    return out
end

local function singleCell(stat, range)
    return { r0=1, c0=1, r1=1, c1=1, stat=stat or "damage", range=range or "follow" }
end

-- Old layout maps had no stable iteration order.  Recover their creation
-- order once, persist it on each definition, and never derive it from names.
local function creationFallback(id, def)
    local scene = type(id)=="string" and id:match("^migrated_(.+)$")
    if SCENE_ORDER[scene] then return 1,SCENE_ORDER[scene],id end
    local stamp = tonumber(def and def._created)
        or tonumber(type(id)=="string" and id:match("^custom_(%d+)_"))
    if stamp then return 2,stamp,id end
    return 3,0,tostring(id or "")
end

local function ensureCreationOrder(profile)
    local defs=profile.layoutDefs or {}; local counts={}; local pending={}; local maximum=0
    for _,def in pairs(defs) do
        local order=tonumber(def.createdOrder)
        if order and order>0 and order%1==0 then counts[order]=(counts[order] or 0)+1 end
    end
    for id,def in pairs(defs) do
        local order=tonumber(def.createdOrder)
        if order and order>0 and order%1==0 and counts[order]==1 then
            def.createdOrder=order; maximum=math.max(maximum,order)
        else
            def.createdOrder=nil; pending[#pending+1]={id=id,def=def}
        end
    end
    table.sort(pending,function(a,b)
        local ak,av,ai=creationFallback(a.id,a.def); local bk,bv,bi=creationFallback(b.id,b.def)
        if ak~=bk then return ak<bk end
        if av~=bv then return av<bv end
        return ai<bi
    end)
    for _,entry in ipairs(pending) do maximum=maximum+1; entry.def.createdOrder=maximum end
end

Layouts.PRESETS = {
    preset1 = {
        id="preset1", nameKey="LAYOUT_PRESET_1", isPreset=true, rows=3, cols=1,
        rowR={0.38,0.33,0.29}, colR={1},
        cells={
            {r0=1,c0=1,r1=1,c1=1,stat="damage",range="follow"},
            {r0=2,c0=1,r1=2,c1=1,stat="damage",range="total"},
            {r0=3,c0=1,r1=3,c1=1,stat="healing",range="total"},
        },
    },
    preset2 = {
        id="preset2", nameKey="LAYOUT_PRESET_2", isPreset=true, rows=2, cols=2,
        rowR={0.5,0.5}, colR={0.5,0.5},
        cells={
            {r0=1,c0=1,r1=1,c1=1,stat="damage",range="follow"},
            {r0=1,c0=2,r1=1,c1=2,stat="damage",range="total"},
            {r0=2,c0=1,r1=2,c1=1,stat="healing",range="follow"},
            {r0=2,c0=2,r1=2,c1=2,stat="healing",range="total"},
        },
    },
    preset3 = {
        id="preset3", nameKey="LAYOUT_PRESET_3", isPreset=true, rows=3, cols=2,
        rowR={0.36,0.36,0.28}, colR={0.5,0.5},
        cells={
            {r0=1,c0=1,r1=1,c1=2,stat="damage",range="follow"},
            {r0=2,c0=1,r1=2,c1=2,stat="damage",range="total"},
            {r0=3,c0=1,r1=3,c1=1,stat="healing",range="total"},
            {r0=3,c0=2,r1=3,c1=2,stat="interrupts",range="total"},
        },
    },
}

function Layouts:GetPreset(id)
    local def = self.PRESETS[id]
    return def and copy(def) or nil
end

function Layouts:GetLayout(id, profile)
    if self.PRESETS[id] then return self.PRESETS[id] end
    profile = profile or (ns.db and ns.db.layoutDefs and { layoutDefs=ns.db.layoutDefs })
    return profile and profile.layoutDefs and profile.layoutDefs[id] or nil
end

function Layouts:GetLayoutName(def)
    if not def then return "" end
    if VALID_SCENE[def.migratedScene] and ns.L and ns.L.MIGRATED_LAYOUT_NAME then
        return string.format(ns.L.MIGRATED_LAYOUT_NAME,ns.L[SCENE_NAME_KEYS[def.migratedScene]] or def.migratedScene)
    end
    if def.isPreset and def.nameKey and ns.L then return ns.L[def.nameKey] end
    return def.name or def.id or ""
end

function Layouts:Validate(def)
    if type(def) ~= "table" then return false, "definition" end
    local rows, cols = tonumber(def.rows), tonumber(def.cols)
    if not rows or not cols or rows % 1 ~= 0 or cols % 1 ~= 0 or rows < 1 or rows > 5 or cols < 1 or cols > 5 then
        return false, "dimensions"
    end
    if type(def.cells) ~= "table" or #def.cells < 1 or #def.cells > 25 then return false, "cells" end
    if type(def.rowR) ~= "table" or #def.rowR ~= rows or type(def.colR) ~= "table" or #def.colR ~= cols then
        return false, "ratios"
    end
    local cover = {}
    for r = 1, rows do cover[r] = {} end
    for _, cell in ipairs(def.cells) do
        local r0,c0,r1,c1 = tonumber(cell.r0),tonumber(cell.c0),tonumber(cell.r1),tonumber(cell.c1)
        if not r0 or not c0 or not r1 or not c1 or r0%1~=0 or c0%1~=0 or r1%1~=0 or c1%1~=0
            or r0 < 1 or c0 < 1 or r1 > rows or c1 > cols or r1 < r0 or c1 < c0 then
            return false, "rectangle"
        end
        if not VALID_STAT[cell.stat] or not VALID_RANGE[cell.range] then return false, "content" end
        for r=r0,r1 do for c=c0,c1 do
            if cover[r][c] then return false, "overlap" end
            cover[r][c] = cell
        end end
    end
    for r=1,rows do for c=1,cols do if not cover[r][c] then return false, "hole" end end end
    local function ratiosOK(values, count, minimum)
        local sum = 0
        for i=1,count do
            local v=tonumber(values[i]); if not v or v~=v or v<(minimum or .001) then return false end
            sum=sum+v
        end
        return math.abs(sum-1) <= 0.01
    end
    if not ratiosOK(def.rowR, rows, .001) or not ratiosOK(def.colR, cols, .001) then return false, "ratios" end
    return true
end

function Layouts:Repair(def)
    if type(def) ~= "table" then return self:GetPreset(self.DEFAULT_LAYOUT) end
    def.rows = math.max(1, math.min(5, math.floor(tonumber(def.rows) or 1)))
    def.cols = math.max(1, math.min(5, math.floor(tonumber(def.cols) or 1)))
    def.rowR = normalizeRatios(def.rowR, def.rows)
    def.colR = normalizeRatios(def.colR, def.cols)
    local ok = self:Validate(def)
    if ok then return def end
    def.rows, def.cols = 1, 1
    def.rowR, def.colR = {1}, {1}
    def.cells = {singleCell("damage", "follow")}
    return def
end

function Layouts:GetMinimumWindowSize(def)
    def = def or self.PRESETS[self.DEFAULT_LAYOUT]
    local cols, rows = def.cols or 1, def.rows or 1
    local usableW, usableH = 0, 0
    for _,cell in ipairs(def.cells or {}) do
        local spanW,spanH=0,0
        for c=cell.c0,cell.c1 do spanW=spanW+(def.colR[c] or 0) end
        for r=cell.r0,cell.r1 do spanH=spanH+(def.rowR[r] or 0) end
        local insideWGaps=(cell.c1-cell.c0)*self.GAP; local insideHGaps=(cell.r1-cell.r0)*self.GAP
        usableW=math.max(usableW,math.max(1,self.MIN_COL_W-insideWGaps)/math.max(.001,spanW))
        usableH=math.max(usableH,math.max(1,self.MIN_ROW_H-insideHGaps)/math.max(.001,spanH))
    end
    local bodyW=usableW+(cols-1)*self.GAP; local bodyH=usableH+(rows-1)*self.GAP
    local titleH = (ns.UI and ns.UI.TITLE_H) or 22
    local tabH = (ns.UI and ns.UI.TAB_H) or 20
    -- Extremely skewed migrated ratios must never force a window beyond a
    -- practical 1080p workspace; the tiny cell remains visible for editing.
    return math.min(bodyW,960), math.min(bodyH + titleH + tabH,720)
end

local function defaultWorkspace()
    return { layoutId="preset2", windowWidth=420, windowHeight=300,
        point="CENTER", relPoint="CENTER", x=320, y=-170 }
end

local function sceneUses(old, prefix, scene)
    if scene == "mplus" then return old[prefix.."MPlus"] ~= false end
    if scene == "raid" then return old[prefix.."Raid"] ~= false end
    if scene == "dungeon" or scene == "arena" or scene == "battleground" then return old[prefix.."Dungeon"] ~= false end
    return old[prefix.."Outdoor"] == true
end

local function buildLegacyLayout(profile, scene, id)
    local sp = profile.split or {}
    local split = sp.enabled ~= false and sceneUses(sp, "splitShow", scene)
    local overall = sp.showOverall ~= false and sceneUses(sp, "overallShow", scene)
    local pri = VALID_STAT[sp.primaryMode] and sp.primaryMode or "damage"
    local sec = VALID_STAT[sp.secondaryMode] and sp.secondaryMode or "healing"
    local single = profile.display and profile.display.mode
    if not VALID_STAT[single] then single = pri end
    local currentStats = split and {pri,sec} or {single}
    local ranges = overall and {"follow","total"} or {"follow"}
    local innerDir = sp.splitDir == "LR" and "LR" or "TB"
    local outerDir = sp.overallDir == "TB" and "TB" or "LR"
    local rows, cols, cells, rowR, colR

    if #currentStats == 2 and #ranges == 2 then
        if innerDir == "TB" and outerDir == "LR" then
            rows, cols = 2, 2
            rowR = normalizeRatios({sp.tbRatio or .55, 1-(sp.tbRatio or .55)}, 2)
            colR = normalizeRatios({sp.lrRatio or .5, 1-(sp.lrRatio or .5)}, 2)
            cells = {}
            for ri,range in ipairs(ranges) do
                local c = (sp.currentPos or 1)==1 and ri or (3-ri)
                for si,stat in ipairs(currentStats) do
                    local r = (sp.primaryPos or 1)==1 and si or (3-si)
                    cells[#cells+1]={r0=r,c0=c,r1=r,c1=c,stat=stat,range=range}
                end
            end
        elseif innerDir == "LR" and outerDir == "TB" then
            rows, cols = 2, 2
            rowR = normalizeRatios({sp.tbRatio or .55, 1-(sp.tbRatio or .55)}, 2)
            colR = normalizeRatios({sp.lrRatio or .5, 1-(sp.lrRatio or .5)}, 2)
            cells = {}
            for ri,range in ipairs(ranges) do
                local r = (sp.currentPos or 1)==1 and ri or (3-ri)
                for si,stat in ipairs(currentStats) do
                    local c = (sp.primaryPos or 1)==1 and si or (3-si)
                    cells[#cells+1]={r0=r,c0=c,r1=r,c1=c,stat=stat,range=range}
                end
            end
        elseif innerDir == "TB" then
            rows, cols, cells = 4, 1, {}
            local p=math.max(.05,math.min(.95,tonumber(sp.tbRatio) or .55)); rowR, colR = {p*p,p*(1-p),(1-p)*p,(1-p)*(1-p)}, {1}
            for ri,range in ipairs(ranges) do for si,stat in ipairs(currentStats) do
                local outer=(sp.currentPos or 1)==1 and ri or (3-ri)
                local inner=(sp.primaryPos or 1)==1 and si or (3-si)
                local r=(outer-1)*2+inner; cells[#cells+1]={r0=r,c0=1,r1=r,c1=1,stat=stat,range=range}
            end end
        else
            rows, cols, cells = 1, 4, {}
            local p=math.max(.075,math.min(.925,tonumber(sp.lrRatio) or .5)); rowR, colR = {1}, {p*p,p*(1-p),(1-p)*p,(1-p)*(1-p)}
            for ri,range in ipairs(ranges) do for si,stat in ipairs(currentStats) do
                local outer=(sp.currentPos or 1)==1 and ri or (3-ri)
                local inner=(sp.primaryPos or 1)==1 and si or (3-si)
                local c=(outer-1)*2+inner; cells[#cells+1]={r0=1,c0=c,r1=1,c1=c,stat=stat,range=range}
            end end
        end
    elseif #currentStats == 2 then
        if innerDir == "TB" then rows,cols,rowR,colR=2,1,normalizeRatios({sp.tbRatio or .55,1-(sp.tbRatio or .55)},2),{1}
        else rows,cols,rowR,colR=1,2,{1},normalizeRatios({sp.lrRatio or .5,1-(sp.lrRatio or .5)},2) end
        cells={}
        for i,stat in ipairs(currentStats) do
            local pos=(sp.primaryPos or 1)==1 and i or (3-i)
            cells[#cells+1]={r0=innerDir=="TB" and pos or 1,c0=innerDir=="LR" and pos or 1,r1=innerDir=="TB" and pos or 1,c1=innerDir=="LR" and pos or 1,stat=stat,range="follow"}
        end
    elseif #ranges == 2 then
        if outerDir == "TB" then rows,cols,rowR,colR=2,1,normalizeRatios({sp.tbRatio or .5,1-(sp.tbRatio or .5)},2),{1}
        else rows,cols,rowR,colR=1,2,{1},normalizeRatios({sp.lrRatio or .5,1-(sp.lrRatio or .5)},2) end
        cells={}
        for i,range in ipairs(ranges) do
            local pos=(sp.currentPos or 1)==1 and i or (3-i)
            cells[#cells+1]={r0=outerDir=="TB" and pos or 1,c0=outerDir=="LR" and pos or 1,r1=outerDir=="TB" and pos or 1,c1=outerDir=="LR" and pos or 1,stat=single,range=range}
        end
    else
        rows,cols,rowR,colR,cells=1,1,{1},{1},{singleCell(single,"follow")}
    end
    local def={id=id,name="1.x migrated - "..scene,migratedScene=scene,isPreset=false,rows=rows,cols=cols,rowR=rowR,colR=colR,cells=cells}
    return Layouts:Repair(def)
end

function Layouts:MigrateProfile(profile)
    if type(profile) ~= "table" then return false end
    local previousSchema=tonumber(profile.layoutSchema) or 0
    local legacyEnemyView=previousSchema<3 and profile.display and profile.display.damageTakenView=="enemy"
    -- Schema 2 already owns 2.0 layout definitions and scene assignments.
    -- Schema 3 only adds a statistic; never rebuild schema-2 workspaces as
    -- legacy 1.x layouts or the player's assignments would be overwritten.
    if previousSchema >= 2 then
        profile.layoutDefs = type(profile.layoutDefs)=="table" and profile.layoutDefs or {}
        profile.sceneWorkspaces = type(profile.sceneWorkspaces)=="table" and profile.sceneWorkspaces or {}
        profile.fullRunSettings = type(profile.fullRunSettings)=="table" and profile.fullRunSettings or {}
        profile.cleanTrashSettings = type(profile.cleanTrashSettings)=="table" and profile.cleanTrashSettings or {}
    else
        profile.layoutDefs = type(profile.layoutDefs)=="table" and profile.layoutDefs or {}
        profile.sceneWorkspaces = type(profile.sceneWorkspaces)=="table" and profile.sceneWorkspaces or {}
        profile.fullRunSettings = type(profile.fullRunSettings)=="table" and profile.fullRunSettings or {}
        profile.cleanTrashSettings = type(profile.cleanTrashSettings)=="table" and profile.cleanTrashSettings or {}
        local oldWindow, oldSplit, mp = profile.window or {}, profile.split or {}, profile.mythicPlus or {}
        for _,scene in ipairs(self.SCENES) do
            local id="migrated_"..scene
            local def=buildLegacyLayout(profile,scene,id)
            profile.layoutDefs[id]=def
            local ws=defaultWorkspace()
            local oldKey=(scene=="arena" or scene=="battleground") and "dungeon" or scene
            local size=oldWindow.rememberSceneSize == true and oldWindow.sceneSizes and oldWindow.sceneSizes[oldKey]
            ws.layoutId=id
            ws.windowWidth=tonumber(size and size.width) or tonumber(oldWindow.width) or 420
            ws.windowHeight=tonumber(size and size.height) or tonumber(oldWindow.height) or 300
            ws.point=oldWindow.point or "BOTTOMRIGHT"; ws.relPoint=oldWindow.relPoint or ws.point
            ws.x=tonumber(oldWindow.x) or -24; ws.y=tonumber(oldWindow.y) or 190
            profile.sceneWorkspaces[scene]=ws
        end
        -- Preserve the master switch and every child choice independently.
        -- Multiplying them together would permanently erase a player's saved
        -- scene selections merely because the master happened to be off during
        -- migration.
        profile.fullRunSettings.mplus = mp.genOverallMPlus ~= false
        profile.fullRunSettings.raid = mp.genOverallRaid ~= false
        profile.fullRunSettings.dungeon = mp.genOverallDungeon ~= false
        -- 1.x grouped dungeon/scenario/arena/battleground under “other
        -- instances”; preserve that behavior when expanding it into scenes.
        profile.fullRunSettings.arena = profile.fullRunSettings.dungeon
        profile.fullRunSettings.battleground = profile.fullRunSettings.dungeon
        profile.fullRunSettings.outdoor=false
        profile.cleanTrashSettings.mplus = mp.cleanTrashMPlus ~= false
        profile.cleanTrashSettings.raid = mp.cleanTrashRaid ~= false
        profile.cleanTrashSettings.dungeon = mp.cleanTrashDungeon ~= false
        -- PvP scenes never contain trash segments.
        profile.cleanTrashSettings.arena = false
        profile.cleanTrashSettings.battleground = false
        profile.cleanTrashSettings.outdoor=false
        if profile.display and profile.display.mode == "split" then profile.display.mode="overview" end
    end

    -- Schema 3 splits the former global damage-taken header toggle into two
    -- real statistics.  Preserve what an upgrading player was looking at by
    -- converting every affected selection/layout once.
    if legacyEnemyView then
        if profile.display and profile.display.mode=="damageTaken" then profile.display.mode="enemyDamageTaken" end
        local split=profile.split
        if split then
            if split.primaryMode=="damageTaken" then split.primaryMode="enemyDamageTaken" end
            if split.secondaryMode=="damageTaken" then split.secondaryMode="enemyDamageTaken" end
        end
        for _,def in pairs(profile.layoutDefs) do
            for _,cell in ipairs(def.cells or {}) do
                if cell.stat=="damageTaken" then cell.stat="enemyDamageTaken" end
            end
        end
    end
    if profile.display then profile.display.damageTakenView=nil end

    for _,scene in ipairs(self.SCENES) do
        local ws=profile.sceneWorkspaces[scene]
        if type(ws)~="table" then ws=defaultWorkspace(); profile.sceneWorkspaces[scene]=ws end
        if not self:GetLayout(ws.layoutId,profile) then ws.layoutId=self.DEFAULT_LAYOUT end
        ws.windowWidth=tonumber(ws.windowWidth) or 420; ws.windowHeight=tonumber(ws.windowHeight) or 300
        ws.point=ws.point or "CENTER"; ws.relPoint=ws.relPoint or ws.point
        ws.x=tonumber(ws.x) or 320; ws.y=tonumber(ws.y) or -170
        -- Preserve every explicit player choice.  Only a truly missing value
        -- adopts the current product default.
        if profile.fullRunSettings[scene]==nil then
            profile.fullRunSettings[scene]=(scene=="mplus" or scene=="dungeon")
        end
        if profile.cleanTrashSettings[scene]==nil then profile.cleanTrashSettings[scene]=(scene=="raid") end
    end
    -- Enforce the product invariant even for profiles created by older builds.
    profile.cleanTrashSettings.arena=false
    profile.cleanTrashSettings.battleground=false
    profile.cleanTrashSettings.outdoor=false
    if profile.display then
        if profile.display.mode == "split" then profile.display.mode="overview" end
        if profile.display.mode ~= "overview" and not VALID_STAT[profile.display.mode] then profile.display.mode="overview" end
    end
    for id,def in pairs(profile.layoutDefs) do
        local migratedScene=id:match("^migrated_(.+)$")
        if migratedScene and VALID_SCENE[migratedScene] and def.name=="1.x migrated - "..migratedScene then def.migratedScene=migratedScene end
        def.id=id; def.isPreset=false
        local ok=self:Validate(def); if not ok then profile.layoutDefs[id]=self:Repair(def) end
    end
    ensureCreationOrder(profile)
    profile.layoutSchema=self.SCHEMA
    return true
end

function Layouts:MigrateAllProfiles()
    local profiles=LightDamageGlobal and LightDamageGlobal.profiles
    if type(profiles)~="table" then return end
    for _,profile in pairs(profiles) do pcall(function() self:MigrateProfile(profile) end) end
end

function Layouts:GetWorkspace(scene)
    scene=VALID_SCENE[scene] and scene or "outdoor"
    local all=ns.db.sceneWorkspaces
    if type(all)~="table" then ns.db.sceneWorkspaces={}; all=ns.db.sceneWorkspaces end
    if type(all[scene])~="table" then all[scene]=defaultWorkspace() end
    local ws=all[scene]
    if not self:GetLayout(ws.layoutId) then ws.layoutId=self.DEFAULT_LAYOUT end
    return ws
end

function Layouts:GetActiveLayout(scene, mode)
    mode=mode or (ns.db.display and ns.db.display.mode) or "overview"
    if mode ~= "overview" and VALID_STAT[mode] then
        self._singleLayouts=self._singleLayouts or {}
        if not self._singleLayouts[mode] then
            self._singleLayouts[mode]={id="single_"..mode,isRuntime=true,rows=1,cols=1,rowR={1},colR={1},cells={singleCell(mode,"follow")}}
        end
        return self._singleLayouts[mode]
    end
    local ws=self:GetWorkspace(scene)
    return self:GetLayout(ws.layoutId) or self.PRESETS[self.DEFAULT_LAYOUT]
end

function Layouts:ListLayouts()
    local out={self.PRESETS.preset1,self.PRESETS.preset2,self.PRESETS.preset3}
    local custom={}
    for _,def in pairs(ns.db.layoutDefs or {}) do custom[#custom+1]=def end
    table.sort(custom,function(a,b)
        local ao,bo=tonumber(a.createdOrder) or math.huge,tonumber(b.createdOrder) or math.huge
        if ao~=bo then return ao<bo end
        return tostring(a.id or "")<tostring(b.id or "")
    end)
    for _,def in ipairs(custom) do out[#out+1]=def end
    return out
end

function Layouts:NextCreationOrder()
    local maximum=0
    for _,def in pairs(ns.db.layoutDefs or {}) do
        local order=tonumber(def.createdOrder)
        if order and order>maximum then maximum=order end
    end
    return math.floor(maximum)+1
end

function Layouts:NextCustomName()
    local used={}
    for _,def in pairs(ns.db.layoutDefs or {}) do used[def.name]=true end
    local n=1
    while used[((ns.L and ns.L.CUSTOM_LAYOUT) or "Custom Layout").." "..n] do n=n+1 end
    return ((ns.L and ns.L.CUSTOM_LAYOUT) or "Custom Layout").." "..n
end

function Layouts:CreateCustom(source)
    ns.db.layoutDefs=ns.db.layoutDefs or {}
    local id="custom_"..tostring(time()).."_"..tostring(math.random(1000,9999))
    while ns.db.layoutDefs[id] do id=id.."x" end
    local def=source and copy(source) or {rows=1,cols=1,rowR={1},colR={1},cells={singleCell("damage","follow")}}
    def.id=id; def.isPreset=false; def.name=self:NextCustomName(); def.nameKey=nil; def.migratedScene=nil; def.createdOrder=self:NextCreationOrder()
    self:Repair(def); ns.db.layoutDefs[id]=def
    return def
end

function Layouts:DeleteCustom(id)
    if not ns.db.layoutDefs or not ns.db.layoutDefs[id] then return false end
    local currentAffected=false
    local visibleScene=(ns.UI and ns.UI._previewContext and ns.UI._previewContext.sceneKey) or ns.state.sceneKey or "outdoor"
    for _,scene in ipairs(self.SCENES) do
        local ws=self:GetWorkspace(scene); if ws.layoutId==id then ws.layoutId=self.PRESET_1; if scene==visibleScene then currentAffected=true end end
    end
    ns.db.layoutDefs[id]=nil
    if currentAffected and ns.UI and ns.UI.ApplySceneWorkspace then ns.UI:ApplySceneWorkspace(visibleScene) end
    return true
end

function Layouts:GetReferencingScenes(id)
    local out={}
    for _,scene in ipairs(self.SCENES) do if self:GetWorkspace(scene).layoutId==id then out[#out+1]=scene end end
    return out
end

function Layouts:Assign(scene,id)
    if not VALID_SCENE[scene] or not self:GetLayout(id) then return false end
    self:GetWorkspace(scene).layoutId=id
    local visibleScene=(ns.UI and ns.UI._previewContext and ns.UI._previewContext.sceneKey) or ns.state.sceneKey
    if ns.UI and visibleScene==scene then ns.UI:ApplySceneWorkspace(scene) end
    return true
end

function Layouts:Commit(id, mutator)
    local def=ns.db.layoutDefs and ns.db.layoutDefs[id]
    if not def or def.isPreset then return false end
    local candidate=copy(def)
    local ok,err=pcall(mutator,candidate)
    if not ok then return false,err end
    candidate.id=id; candidate.isPreset=false; candidate.rowR=normalizeRatios(candidate.rowR,candidate.rows); candidate.colR=normalizeRatios(candidate.colR,candidate.cols)
    local valid,why=self:Validate(candidate); if not valid then return false,why end
    ns.db.layoutDefs[id]=candidate
    if ns.UI then
        local scene=(ns.UI._previewContext and ns.UI._previewContext.sceneKey) or ns.state.sceneKey or "outdoor"
        if self:GetWorkspace(scene).layoutId==id and ns.UI.ApplySceneWorkspace then ns.UI:ApplySceneWorkspace(scene) end
    end
    return true,candidate
end

function Layouts:FindCell(def,r,c)
    for _,cell in ipairs(def.cells or {}) do if r>=cell.r0 and r<=cell.r1 and c>=cell.c0 and c<=cell.c1 then return cell end end
end

function Layouts:AddTrack(id,axis)
    return self:Commit(id,function(def)
        if axis=="row" then
            assert(def.rows<5); def.rows=def.rows+1
            local keep=(def.rows-1)/def.rows; for i=1,#def.rowR do def.rowR[i]=def.rowR[i]*keep end; def.rowR[#def.rowR+1]=1/def.rows
            for c=1,def.cols do def.cells[#def.cells+1]={r0=def.rows,c0=c,r1=def.rows,c1=c,stat="damage",range="follow"} end
        else
            assert(def.cols<5); def.cols=def.cols+1
            local keep=(def.cols-1)/def.cols; for i=1,#def.colR do def.colR[i]=def.colR[i]*keep end; def.colR[#def.colR+1]=1/def.cols
            for r=1,def.rows do def.cells[#def.cells+1]={r0=r,c0=def.cols,r1=r,c1=def.cols,stat="damage",range="follow"} end
        end
    end)
end

function Layouts:RemoveTrack(id,axis)
    return self:Commit(id,function(def)
        local limit=axis=="row" and def.rows or def.cols; assert(limit>1)
        for _,cell in ipairs(def.cells) do
            local a0=axis=="row" and cell.r0 or cell.c0; local a1=axis=="row" and cell.r1 or cell.c1
            assert(not (a0<limit and a1>=limit),"merged")
        end
        for i=#def.cells,1,-1 do local cell=def.cells[i]; if (axis=="row" and cell.r0==limit) or (axis=="col" and cell.c0==limit) then table.remove(def.cells,i) end end
        if axis=="row" then def.rows=def.rows-1; table.remove(def.rowR) else def.cols=def.cols-1; table.remove(def.colR) end
    end)
end

function Layouts:SelectionValid(def,r0,c0,r1,c1)
    r0,r1=math.min(r0,r1),math.max(r0,r1); c0,c1=math.min(c0,c1),math.max(c0,c1)
    for _,cell in ipairs(def.cells) do
        local hit=not (cell.r1<r0 or cell.r0>r1 or cell.c1<c0 or cell.c0>c1)
        if hit and not (cell.r0>=r0 and cell.r1<=r1 and cell.c0>=c0 and cell.c1<=c1) then return false end
    end
    return true,r0,c0,r1,c1
end

function Layouts:Merge(id,r0,c0,r1,c1,anchorR,anchorC)
    local def=self:GetLayout(id); local valid,a,b,c,d=self:SelectionValid(def,r0,c0,r1,c1); if not valid then return false,"partial" end
    local anchor=self:FindCell(def,anchorR or r0,anchorC or c0) or self:FindCell(def,r0,c0)
    local stat,range=anchor.stat,anchor.range
    return self:Commit(id,function(nextDef)
        for i=#nextDef.cells,1,-1 do local cell=nextDef.cells[i]; if cell.r0>=a and cell.r1<=c and cell.c0>=b and cell.c1<=d then table.remove(nextDef.cells,i) end end
        nextDef.cells[#nextDef.cells+1]={r0=a,c0=b,r1=c,c1=d,stat=stat,range=range}
    end)
end

function Layouts:Split(id,target)
    if not target or (target.r0==target.r1 and target.c0==target.c1) then return false end
    return self:Commit(id,function(def)
        for i=#def.cells,1,-1 do local cell=def.cells[i]; if cell.r0==target.r0 and cell.c0==target.c0 and cell.r1==target.r1 and cell.c1==target.c1 then table.remove(def.cells,i); break end end
        for r=target.r0,target.r1 do for c=target.c0,target.c1 do def.cells[#def.cells+1]={r0=r,c0=c,r1=r,c1=c,stat="damage",range="follow"} end end
    end)
end
