--[[
    Light Damage - Core.lua
    核心初始化、事件路由、状态管理
]]

local addonName, ns = ...
local L = ns.L

-- 动态获取 .toc 文件中的版本号
local currentVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
if currentVersion == "@project-version@" then
    currentVersion = "Dev"
end

ns.version   = currentVersion
ns.addonName = addonName

local Core = CreateFrame("Frame")
ns.Core = Core

-- ============================================================
-- 默认配置
-- ============================================================
ns.defaults = {
    collapse = {
        autoCollapse    = false,
        neverInInstance = true,
        delay           = 1.5,
        enableAnim      = true,
        animDuration    = 0.4,
    },
    fade = {
        unfadeOnHover       = true,
        fadeBars            = false,
        barsWhen            = "ooc",
        barsNeverInInstance = false,
        barsAlpha           = 0.3,
        fadeBody            = false,
        bodyWhen            = "ooc",
        bodyNeverInInstance = false,
        bodyAlpha           = 0.15,
        delay               = 1.5,
        enableAnim          = true,
        animDuration        = 0.5,
    },
    window = {
        width = 400, height = 280,
        point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -20, y = 180,
        alpha = 0.92, scale = 1.0, configScale = 1.0, locked = false, visible = true,
        rememberSceneSize = false,
        sceneAnchor = "TOPLEFT",
        sceneSizes = {},
        themeColor = {0, 0, 0, 1},
        bgColor    = {0.02, 0.02, 0.025, 0.80},
        ovrBgColor = {0.025, 0.035, 0.05, 0.82},
    },
    detailWindow = {
        width = 380, height = 420,
    },
    detailDisplay = {
        barHeight     = 20,
        barThickness  = 20,
        barVOffset    = 0,
        barGap        = 1,
        barAlpha      = 0.92,
        barTexture    = "Interface\\Buttons\\WHITE8X8",
        font          = STANDARD_TEXT_FONT,
        fontSizeBase  = 10,
        fontOutline   = "OUTLINE",
        fontShadow    = false,
        fontColor     = {1, 1, 1, 1},
        barColorMode  = "default",
        barColor      = {0.0, 0.65, 1.0, 0.92},
    },
    display = {
        mode          = "overview",
        language      = "auto",
        showPerSecond = true,
        showPercent   = true,
        showRank      = true,
        showSpecIcon  = true,
        iconPack      = "default",
        showRealm     = false,
        classColors   = true,
        barHeight     = 19,
        barThickness  = 19,
        barVOffset    = 0,
        barGap        = 1,
        barAlpha      = 0.85,
        barTexture    = "Interface\\Buttons\\WHITE8X8",
        font          = STANDARD_TEXT_FONT,
        fontSizeBase  = 13,
        fontOutline   = "OUTLINE",
        fontShadow    = false,
        fontColor     = {1, 1, 1, 0.93},
        titleFont     = STANDARD_TEXT_FONT,
        titleFontSize = 10,
        titleFontOutline = "OUTLINE",
        titleFontShadow  = false,
        titleFontColor   = {1, 1, 1, 0.93},
        headerFont     = STANDARD_TEXT_FONT,
        headerFontSize = 9,
        headerFontOutline = "OUTLINE",
        headerFontShadow  = false,
        headerFontColor   = {0.66, 0.66, 0.66, 0.95},
        nameFont     = STANDARD_TEXT_FONT,
        nameFontSize = 13,
        nameFontOutline = "OUTLINE",
        nameFontShadow  = false,
        nameColorMode   = "class",
        nameFontColor   = {1, 1, 1, 1},
        tabFont     = STANDARD_TEXT_FONT,
        tabFontSize = 9,
        tabFontOutline = "OUTLINE",
        tabFontShadow  = false,
        tabActiveFontColor   = {1, 1, 1, 1},
        tabInactiveFontColor = {0.55, 0.55, 0.55, 0.9},
        dataTitleColors = {
            damage           = {1.0, 0.82, 0.0, 1},
            healing          = {0.4, 1.0, 0.4, 1},
            damageTaken      = {1.0, 0.3, 0.3, 1},
            avoidableDamageTaken = {1.0, 0.65, 0.1, 1},
            enemyDamageTaken = {0.92, 0.22, 0.18, 1},
            deaths           = {0.0, 0.65, 1.0, 1},
            interrupts       = {0.0, 0.65, 1.0, 1},
            dispels          = {0.0, 0.65, 1.0, 1},
        },
        alwaysShowSelf = false,
        useShortTabs   = false,
        tabLabelStyle  = "full",
        -- Which statistics get their own bottom-bar button; the rest are
        -- reachable through the More menu.  Order comes from ns.MODE_ORDER.
        bottomBarModes = {
            damage = true,
            healing = true,
            interrupts = false,
            dispels = false,
            deaths = true,
            damageTaken = false,
            avoidableDamageTaken = false,
            enemyDamageTaken = true,
        },
        bottomBarSchema = 1,
    },
    split = {
        enabled           = true,
        splitDir          = "TB",
        primaryMode       = "damage",
        secondaryMode     = "healing",
        primaryPos        = 1,
        splitShowMPlus    = true,
        splitShowRaid     = true,
        splitShowDungeon  = true,
        splitShowOutdoor  = false,
        showOverall       = true,
        overallDir        = "LR",
        currentPos        = 1,
        overallShowMPlus  = true,
        overallShowRaid   = true,
        overallShowDungeon= true,
        overallShowOutdoor= false,
        tbRatio           = 0.55,
        lrRatio           = 0.50,
    },
    mythicPlus = {
        enabled           = true,
        autoSegment       = true,
        autoCleanTrash    = true,
        genOverallMPlus   = true,
        genOverallRaid    = false,
        genOverallDungeon = true,
        cleanTrashMPlus   = false,
        cleanTrashRaid    = true,
        cleanTrashDungeon = false,
    },
    tracking = {
        mergePlayerPets = true,
        autoReset       = false,
        deathLogSize    = 15,
        maxSegments     = 20,
        historyDisplayLimit = 20,
    },
    smartRefresh = {
        combatInterval = 0.6,
        idleInterval   = 2.0,
    },
    layoutSchema = 3,
    layoutDefs = {},
    sceneWorkspaces = {
        mplus={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
        raid={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
        dungeon={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
        arena={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
        battleground={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
        outdoor={layoutId="preset2",windowWidth=420,windowHeight=300,point="CENTER",relPoint="CENTER",x=320,y=-170},
    },
    fullRunSettings = {
        mplus=true, raid=false, dungeon=true,
        arena=false, battleground=false, outdoor=false,
    },
    cleanTrashSettings = {
        mplus=false, raid=true, dungeon=false,
        arena=false, battleground=false, outdoor=false,
    },
    profileSchema = 2,
    useBlizzMeter = true,
}

-- Profile-owned keys are declared once so migration, the ns.db proxy and
-- profile switching cannot silently disagree about where a setting lives.
local PROFILE_CONFIG_KEYS = {
    window=true, display=true, split=true, mythicPlus=true, tracking=true,
    smartRefresh=true, useBlizzMeter=true, detailWindow=true,
    detailDisplay=true, collapse=true, fade=true, profileSchema=true,
    layoutSchema=true, layoutDefs=true, sceneWorkspaces=true,
    fullRunSettings=true, cleanTrashSettings=true,
}

-- ============================================================
-- 运行时状态
-- ============================================================
ns.state = {
    inCombat         = false,
    combatStartTime  = 0,
    combatEndTime    = 0,
    isInInstance     = false,
    wasInInstance    = false,
    instanceType     = nil,
    inMythicPlus     = false,
    mythicPlusLevel  = 0,
    mythicPlusMapID  = nil,
    mythicPlusMapName= nil,
    mplusRuntimeLatch= false,
    mplusResetLatch  = false,
    sceneKey         = "outdoor",
    playerGUID       = nil,
    playerName       = nil,
    playerClass      = nil,
}



-- ============================================================
-- 初始化
-- ============================================================
function Core:OnInitialize()
    if not self._initialized then
        self._initialized = true

        -- ★ SavedVariables 迁移 (LDCombatStats → LightDamage)
        --   桥接插件 (AddOns/LDCombatStats) 负责让 WoW 加载旧 SavedVariables，
        --   此处在 PLAYER_LOGIN 时执行实际迁移，对用户完全无感。
        if LDCombatStatsGlobal and type(LDCombatStatsGlobal) == "table" and next(LDCombatStatsGlobal) then
            if not LightDamageGlobal or not next(LightDamageGlobal) or not LightDamageGlobal.profiles then
                LightDamageGlobal = LDCombatStatsGlobal
            end
            LDCombatStatsGlobal = nil
        end
        if LDCombatStatsDB and type(LDCombatStatsDB) == "table" and next(LDCombatStatsDB) then
            if not LightDamageDB or not next(LightDamageDB) then
                LightDamageDB = LDCombatStatsDB
            end
            LDCombatStatsDB = nil
        end

        -- 1. 初始化全局配置库。旧角色级配置按 key additive 搬入，任何
        -- 新版未知字段都原样保留，迁移失败也绝不清空玩家布局。
        if not LightDamageGlobal then LightDamageGlobal = { profiles = {} } end
        LightDamageGlobal.profiles = type(LightDamageGlobal.profiles) == "table" and LightDamageGlobal.profiles or {}
        if not LightDamageGlobal.profiles["默认"] then
            local migrated = {}
            for key in pairs(PROFILE_CONFIG_KEYS) do
                local value = LightDamageDB and LightDamageDB[key]
                if value ~= nil then
                    migrated[key] = type(value) == "table" and CopyTable(value) or value
                end
            end
            LightDamageGlobal.profiles["默认"] = next(migrated) and migrated or CopyTable(ns.defaults)
        end

        -- 版本配置自动平滑迁移 (旧版 -> 四宫格新版)
        for pName, profile in pairs(LightDamageGlobal.profiles) do
            profile.display = type(profile.display) == "table" and profile.display or {}
            if profile.display.tabLabelStyle ~= "full" and profile.display.tabLabelStyle ~= "short" then
                profile.display.tabLabelStyle = profile.display.useShortTabs == true and "short" or "full"
            end
            -- Bottom-bar schema 1 intentionally gives every upgrading player
            -- the new curated arrangement once.  The marker prevents future
            -- logins from overwriting changes made afterwards.
            if (tonumber(profile.display.bottomBarSchema) or 0) < 1 then
                profile.display.bottomBarModes = CopyTable(ns.defaults.display.bottomBarModes)
                profile.display.bottomBarSchema = 1
            end
            local sp = profile.split
            local mp = profile.mythicPlus
            if sp and mp then
                if mp.overallColumnMode ~= nil then
                    sp.showOverall = (mp.overallColumnMode ~= "off")
                    sp.overallShowMode = mp.overallColumnMode
                    mp.overallColumnMode = nil
                    sp.splitDir = "TB"
                    sp.overallDir = "LR"
                    sp.primaryPos = 1
                    sp.currentPos = 1
                    if sp.priRatio then
                        sp.tbRatio = sp.priRatio
                        sp.priRatio = nil
                    end
                    if sp.ovrRatio then
                        sp.lrRatio = 1 - sp.ovrRatio
                        sp.ovrRatio = nil
                    end
                end
            end
            profile.tracking = type(profile.tracking) == "table" and profile.tracking or {}
            if profile.tracking.historyDisplayLimit == nil then
                profile.tracking.historyDisplayLimit = tonumber(profile.tracking.maxSegments) or 20
            end
            profile.profileSchema = math.max(tonumber(profile.profileSchema) or 0, 2)
        end

        -- 2. 初始化角色数据
        if not LightDamageDB then LightDamageDB = {} end
        if not LightDamageDB.activeProfile or not LightDamageGlobal.profiles[LightDamageDB.activeProfile] then
            LightDamageDB.activeProfile = "默认"
        end

        -- 3. 将尚未迁移的角色级设置补入当前 profile 后再清理旧副本。
        local activeProfile = LightDamageGlobal.profiles[LightDamageDB.activeProfile]
        for k in pairs(PROFILE_CONFIG_KEYS) do
            local value = LightDamageDB[k]
            if value ~= nil then
                if activeProfile[k] == nil then
                    activeProfile[k] = type(value) == "table" and CopyTable(value) or value
                elseif type(value) == "table" and type(activeProfile[k]) == "table" then
                    ns:MergeDefaults(activeProfile[k], value)
                end
            end
        end
        for k in pairs(PROFILE_CONFIG_KEYS) do
            if LightDamageDB[k] ~= nil then LightDamageDB[k] = nil end
        end
        activeProfile.tracking = type(activeProfile.tracking) == "table" and activeProfile.tracking or {}
        if activeProfile.tracking.historyDisplayLimit == nil then
            activeProfile.tracking.historyDisplayLimit = tonumber(activeProfile.tracking.maxSegments) or 20
        end

        -- 4. 建立智能代理数据指针 ns.db
        ns.db = setmetatable({}, {
            __index = function(t, k)
                if PROFILE_CONFIG_KEYS[k] then
                    return LightDamageGlobal.profiles[LightDamageDB.activeProfile][k]
                else
                    return LightDamageDB[k]
                end
            end,
            __newindex = function(t, k, v)
                if PROFILE_CONFIG_KEYS[k] then
                    LightDamageGlobal.profiles[LightDamageDB.activeProfile][k] = v
                else
                    LightDamageDB[k] = v
                end
            end
        })

        if ns.Layouts then
            ns.Layouts:MigrateAllProfiles()
            local active=LightDamageGlobal.profiles[LightDamageDB.activeProfile]
            pcall(ns.Layouts.MigrateProfile,ns.Layouts,active)
        end
        ns:MergeDefaults(LightDamageGlobal.profiles[LightDamageDB.activeProfile], ns.defaults)

        ns.state.playerGUID = UnitGUID("player")
        ns.state.playerName = UnitName("player")
        local _, classEng   = UnitClass("player")
        ns.state.playerClass = classEng
        ns.state.mplusResetLatch = ns.db.mplusResetLatch == true

        ns:BuildIconToSpecIDMap()

        if ns.Segments then
            ns.Segments:Init()
            ns:LoadSessionHistory()
        else
            print(L.MSG_LIGHT_DAMAGE_ERROR_SEGMENTS_NOT_LOADED)
            return
        end

        if ns.MythicPlus   then ns.MythicPlus:Init()   end
        if ns.DeathTracker then ns.DeathTracker:Init()  end
        if ns.Analysis     then ns.Analysis:Init()     end

        ns:StartSmartRefresh()
        
        -- 自动关闭暴雪原生统计
        C_Timer.After(2, function()
            local possibleCVars = { "damageMeterResetOnNewInstance", "damageMeterEnabled" }
            local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
            for _, cvar in ipairs(possibleCVars) do
                pcall(setter, cvar, "0")
            end
        end)

        -- 注册事件
        local events = {
            "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START", "ENCOUNTER_END",
            "GROUP_ROSTER_UPDATE", "CHALLENGE_MODE_START",
            "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
            "PLAYER_DEAD", "PLAYER_LOGOUT",
        }
        for _, ev in ipairs(events) do self:RegisterEvent(ev) end
        if ns.CombatTracker then ns.CombatTracker:RegisterEvents() end
    end

    -- 无论是不是第一次进世界，都要执行的常规操作
    SLASH_LDCS1 = "/ldcs"
    SLASH_LDCS2 = "/ldstats"
    SLASH_LD1 = "/ld"
    SLASH_LD2 = "/lightdamage"
    SlashCmdList["LDCS"] = function(msg) ns:HandleSlashCommand(msg) end
    SlashCmdList["LD"] = function(msg) ns:HandleSlashCommand(msg) end

    ns:UpdateInstanceStatus()
    ns:InvalidateGUIDCache()

    C_Timer.After(0.1, function()
        if ns.UI then
            ns.UI:EnsureCreated()
            ns:AttachRefreshVisibilityHooks()
            ns:RequestRefresh("ui-created", true)
        end
    end)
end

-- ============================================================
-- 事件路由
-- ============================================================
function Core:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Core:OnInitialize()
        if event == "PLAYER_LOGIN" then return end
    end

    if event == "ENCOUNTER_START" then
        ns:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        ns:OnEncounterEnd(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns:InvalidateGUIDCache()
        C_Timer.After(0.3, function()
            ns:UpdateInstanceStatus("PLAYER_ENTERING_WORLD")
            ns:InvalidateGUIDCache()
            if ns.UI and ns.UI:IsVisible() then
                if ns.UI.CheckAutoCollapse then
                    ns.UI:CheckAutoCollapse(true)
                end
            end
        end)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local wasInInstance = ns.state.isInInstance
        ns:UpdateInstanceStatus("ZONE_CHANGED_NEW_AREA")
        ns:InvalidateGUIDCache()

        if wasInInstance and not ns.state.isInInstance then
            if ns.MythicPlus and ns.MythicPlus:IsActive() then
                ns.MythicPlus:OnLeaveInstance()
            end
        end

        -- CombatTracker is the single owner of instance-edge archive/reset.
        -- Core only updates scene/UI state here.
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns:InvalidateGUIDCache()
    elseif event == "CHALLENGE_MODE_START" then
        -- The event itself is authoritative even when map metadata is one or
        -- more frames late.  This makes the first scene frame Mythic+.
        ns.state.mplusRuntimeLatch = true
        ns.state.mplusResetLatch = false
        ns.db.mplusResetLatch = nil
        ns:UpdateInstanceStatus("CHALLENGE_MODE_START", true)
        ns:ScheduleMythicMetadataRetry("CHALLENGE_MODE_START")
        if ns.MythicPlus then ns.MythicPlus:OnStart(...) end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Keep the runtime latch until leaving or an explicit reset; Blizzard
        -- can report the challenge inactive immediately after completion.
        ns.state.mplusRuntimeLatch = true
        ns.state.mplusResetLatch = false
        ns.db.mplusResetLatch = nil
        if ns.MythicPlus then ns.MythicPlus:OnCompleted(...) end
        ns:UpdateInstanceStatus("CHALLENGE_MODE_COMPLETED", true)
    elseif event == "CHALLENGE_MODE_RESET" then
        if ns.MythicPlus then ns.MythicPlus:OnReset() end
        ns.state.mplusRuntimeLatch = false
        ns.state.mplusResetLatch = true
        ns.db.mplusResetLatch = true
        ns.state._mythicMetadataToken = (ns.state._mythicMetadataToken or 0) + 1
        ns:UpdateInstanceStatus("CHALLENGE_MODE_RESET", true)
    elseif event == "PLAYER_DEAD" then
        if ns.DeathTracker then ns.DeathTracker:OnPlayerDead() end
    elseif event == "PLAYER_LOGOUT" then
        local saved = ns:SaveSessionHistory()
        if saved ~= false and ns.db then ns.db.savedHistorySchema = 2 end
    end
end

Core:SetScript("OnEvent", Core.OnEvent)
Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ============================================================
-- 战斗状态管理
-- ============================================================
function ns:EnterCombat()
    ns.state.inCombat        = true
    ns.state.combatStartTime = GetTime()
    if ns.Segments then ns.Segments:OnCombatStart() end
    if ns.Config and ns.Config._previewActive then ns.Config:ClosePreview(true) end
    if ns.UI       then ns.UI:OnCombatStateChanged(true) end
    ns:RequestRefresh("combat-start", true)
end

function ns:LeaveCombat()
    ns.state.inCombat        = false
    ns.state.combatStartTime = 0
    ns.state.combatEndTime   = GetTime()
    if ns.Segments then ns.Segments:OnCombatEnd() end
    if ns.UI       then ns.UI:OnCombatStateChanged(false) end
    ns:RequestRefresh("combat-end", true)
end

function ns:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    -- LoggingCombat(true)
    if ns.Segments then
        ns.Segments:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    end
end

function ns:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    if ns.Segments then
        ns.Segments:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    end
end

-- ============================================================
-- 智能刷新系统
-- ============================================================
-- A single explicit repeating ticker drives live refresh.  It runs only while
-- the window is shown AND there is something to refresh (in combat, or a
-- pending dirty mark), and is cancelled outright when idle-and-clean or hidden.
-- Events (combat edges, DAMAGE_METER_*, view changes) call RequestRefresh,
-- which re-arms the ticker on demand.  Using NewTicker+Cancel instead of a
-- self-rescheduling NewTimer chain makes a leaked/duplicated refresh loop
-- structurally impossible, and stopping when idle removes the steady-state
-- out-of-combat poll.
local refreshTicker
local refreshTickerInterval
local immediateTimer
local refreshDirty = true
local refreshing = false

local function RefreshInterval()
    local settings = ns.db and ns.db.smartRefresh or ns.defaults.smartRefresh
    local value = ns.state.inCombat and settings.combatInterval or settings.idleInterval
    return math.max(0.1, tonumber(value) or (ns.state.inCombat and 0.3 or 2.0))
end

local function WindowShown()
    return (ns.UI and ns.UI.frame and ns.UI.frame:IsShown()) and true or false
end

local function StopRefreshTicker()
    if refreshTicker then refreshTicker:Cancel(); refreshTicker = nil end
    refreshTickerInterval = nil
end

local RunScheduledRefresh

-- Arm the repeating ticker iff there is a reason to.  Idempotent: never creates
-- a second ticker, and re-creates it only when the combat/idle cadence changed
-- (a NewTicker's interval is fixed at creation).
local function EnsureRefreshTicker()
    if not WindowShown() then StopRefreshTicker(); return end
    if not ns.state.inCombat and not refreshDirty then return end
    local interval = RefreshInterval()
    if refreshTicker and refreshTickerInterval == interval then return end
    StopRefreshTicker()
    refreshTickerInterval = interval
    refreshTicker = C_Timer.NewTicker(interval, function() RunScheduledRefresh() end)
end

RunScheduledRefresh = function()
    -- A combat-edge sync inside PullCurrentData can call RequestRefresh, which
    -- may re-enter here via the immediate one-shot; never overlap a refresh.
    if refreshing then return end
    if not WindowShown() then StopRefreshTicker(); return end
    refreshing = true
    refreshDirty = false
    local _tRefresh = debugprofilestop and debugprofilestop() or nil
    if ns.CombatTracker then ns.CombatTracker:PullCurrentData() end
    if ns.DetailView and ns.DetailView:IsVisible() then
        pcall(function() ns.DetailView:Refresh() end)
    end
    if _tRefresh then
        ns._refreshMs = (ns._refreshMs or 0) + (debugprofilestop() - _tRefresh)
        ns._refreshCount = (ns._refreshCount or 0) + 1
    end
    refreshing = false

    if not WindowShown() then StopRefreshTicker(); return end
    -- Idle and nothing dirty: stop entirely; an event will re-arm us.
    if not ns.state.inCombat and not refreshDirty then StopRefreshTicker(); return end
    -- Adopt a changed combat/idle cadence.
    EnsureRefreshTicker()
end

function ns:RequestRefresh(reason, immediate)
    refreshDirty = true
    if ns.UI then ns.UI._barsDirty = true end
    if ns.DamageMeterGateway and ns.DamageMeterGateway.MarkDirty then
        ns.DamageMeterGateway:MarkDirty(reason or "ui")
    end
    if not WindowShown() then
        StopRefreshTicker()
        if immediateTimer then immediateTimer:Cancel(); immediateTimer = nil end
        return
    end
    if immediate then
        -- Run one refresh on the next frame (never synchronously: an edge sync
        -- inside a refresh calls RequestRefresh, which would otherwise recurse),
        -- then make sure the repeating ticker is running.
        if immediateTimer then immediateTimer:Cancel() end
        immediateTimer = C_Timer.NewTimer(0, function()
            immediateTimer = nil
            RunScheduledRefresh()
        end)
    end
    EnsureRefreshTicker()
end

-- Alias used by data gateway/history-store style modules.
ns.MarkRefreshDirty = ns.RequestRefresh

function ns:AttachRefreshVisibilityHooks()
    local frame = ns.UI and ns.UI.frame
    if not frame or frame._lightDamageRefreshHooks then return false end
    frame._lightDamageRefreshHooks = true
    frame:HookScript("OnShow", function() ns:RequestRefresh("window-show", true) end)
    frame:HookScript("OnHide", function()
        StopRefreshTicker()
        if immediateTimer then immediateTimer:Cancel(); immediateTimer = nil end
    end)
    return true
end

function ns:StartSmartRefresh()
    C_Timer.After(0.2, function()
        ns:AttachRefreshVisibilityHooks()
        ns:RequestRefresh("startup", true)
    end)
end

-- ============================================================
-- 副本状态检测
-- ============================================================
local function GetChallengeMetadata()
    local mapID, level, mapName
    if C_ChallengeMode then
        if C_ChallengeMode.GetActiveChallengeMapID then
            local ok, value = pcall(C_ChallengeMode.GetActiveChallengeMapID)
            if ok then mapID = value end
        end
        if C_ChallengeMode.GetActiveKeystoneInfo then
            local ok, value = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
            if ok and type(value) == "number" then level = value end
        end
        if mapID and C_ChallengeMode.GetMapUIInfo then
            local ok, value = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if ok then mapName = value end
        end
    end
    return mapID, level or 0, mapName
end

function ns:ResolveSceneKey(inInstance, instanceType, difficultyID)
    local mapID = GetChallengeMetadata()
    local apiActive = false
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, value = pcall(C_ChallengeMode.IsChallengeModeActive)
        apiActive = ok and value == true
    end

    local isMPlus = not ns.state.mplusResetLatch and
        (ns.state.mplusRuntimeLatch or apiActive or mapID ~= nil or difficultyID == 8)
    if isMPlus then return "mplus", true end
    if inInstance and instanceType == "arena" then return "arena", false end
    if inInstance and instanceType == "pvp" then return "battleground", false end
    if inInstance and instanceType == "raid" then return "raid", false end
    -- Blizzard can introduce new PvE instanceType values (followers, delves,
    -- scenarios, etc.).  Once PvP and raids have been handled explicitly,
    -- every remaining real instance shares the normal-dungeon workspace.
    if inInstance then return "dungeon", false end
    return "outdoor", false
end

function ns:ApplySceneWorkspace(scene, reason, force)
    scene = scene or "outdoor"
    local oldScene = ns.state.sceneKey
    if oldScene == scene and not force then return false end

    if oldScene and oldScene ~= scene and ns.UI and ns.UI.frame
        and ns.UI.PersistWorkspaceGeometry and not ns.UI._previewContext then
        ns.UI:PersistWorkspaceGeometry()
    end
    ns.state.sceneKey = scene

    if ns.UI and ns.UI.frame and not ns.UI._previewContext then
        if ns.UI.ApplySceneWorkspace then ns.UI:ApplySceneWorkspace(scene)
        elseif ns.UI.Layout then ns.UI:Layout() end
    end
    ns:RequestRefresh("scene:" .. tostring(reason or scene), true)
    return true
end

function ns:ScheduleMythicMetadataRetry(reason)
    ns.state._mythicMetadataToken = (ns.state._mythicMetadataToken or 0) + 1
    local token = ns.state._mythicMetadataToken
    local delays = { 0, 0.15, 0.35, 0.7, 1.2, 2.0, 3.0 }

    local function probe(index)
        if token ~= ns.state._mythicMetadataToken then return end
        if not ns.state.mplusRuntimeLatch and ns.state.sceneKey ~= "mplus" then return end
        local mapID, level, mapName = GetChallengeMetadata()
        if mapID then
            ns.state.mythicPlusMapID = mapID
            ns.state.mythicPlusMapName = mapName
            ns.state.mythicPlusLevel = level or 0
            if ns.MythicPlus then
                ns.MythicPlus._mapID = mapID
                ns.MythicPlus._mapName = mapName or ns.MythicPlus._mapName
                ns.MythicPlus._level = (level and level > 0) and level or ns.MythicPlus._level
            end
            if ns.CombatTracker then
                ns.CombatTracker._currentMythicLevel = level or 0
                ns.CombatTracker._currentMythicMapName = mapName
            end
            ns:RequestRefresh("mplus-metadata", true)
            return
        end
        index = index + 1
        if index <= #delays then C_Timer.After(delays[index], function() probe(index) end) end
    end
    probe(1)
end

function ns:UpdateInstanceStatus(reason, skipMPlusEnter)
    local inInstance, instanceType = IsInInstance()

    if instanceType == "scenario" or instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp" then
        inInstance = true
    end
    if instanceType == "neighborhood" or instanceType == "interior" then
        inInstance = false
    end

    ns.state.wasInInstance = ns.state.isInInstance
    ns.state.isInInstance = inInstance
    ns.state.instanceType = instanceType
    local _, _, difficultyID = GetInstanceInfo()

    if not inInstance and not ns.state.mplusRuntimeLatch then
        ns.state.mplusResetLatch = false
        ns.db.mplusResetLatch = nil
    elseif not inInstance and ns.state.mplusRuntimeLatch and reason ~= "CHALLENGE_MODE_START" then
        ns.state.mplusRuntimeLatch = false
        ns.state.mplusResetLatch = false
        ns.db.mplusResetLatch = nil
        ns.state._mythicMetadataToken = (ns.state._mythicMetadataToken or 0) + 1
    end

    local wasInMPlus = ns.state.inMythicPlus
    local scene, isMPlus = ns:ResolveSceneKey(inInstance, instanceType, difficultyID)
    ns.state.inMythicPlus = isMPlus

    -- 兼容旧代码的四场景分类器
    local cat = "outdoor"
    if inInstance then
        if instanceType == "raid" then
            cat = "raid"
        elseif instanceType == "party" or instanceType == "scenario" or instanceType == "arena" or instanceType == "pvp" then
            cat = "dungeon"
        end
    end
    if isMPlus then
        cat = "mplus"
    end

    local oldCat = ns.state.instanceCategory
    ns.state.instanceCategory = cat

    ns:ApplySceneWorkspace(scene, reason)

    if isMPlus and not wasInMPlus and not skipMPlusEnter
        and reason ~= nil and reason ~= "PLAYER_ENTERING_WORLD" then
        if ns.MythicPlus then ns.MythicPlus:OnEnterDungeon() end
    end

    -- 进出副本时刷新渐隐状态（修复"副本中永不隐藏"不即时生效）
    if oldCat ~= cat and ns.UI and ns.UI.CheckAutoFade then
        ns.UI:CheckAutoFade(true)
    end
end

-- ============================================================
-- 斜杠命令
-- ============================================================
function ns:HandleSlashCommand(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" then
        if ns.Config then ns.Config:Toggle() end

    elseif msg == "help" then
        print(L.MSG_LIGHT_DAMAGE_COMMANDS)
        print(L.SLASH_HELP_SHOW)
        print(L.SLASH_HELP_RESET)
        print(L.SLASH_HELP_CONFIG)
        print(L.SLASH_HELP_LOCK)

    elseif msg == "show" or msg == "toggle" then
        if ns.UI then ns.UI:Toggle() end

    elseif msg == "reset" then
        if ns.Segments then
            local _, status = ns.Segments:ResetAll(function()
                print(L.MSG_LIGHT_DAMAGE_DATA_RESET)
            end)
            if status == "queued" and ns.state.inCombat then
                print(L.MSG_LIGHT_DAMAGE_RESET_QUEUED)
            end
        end

    elseif msg == "config" then
        if ns.Config then ns.Config:Toggle() end

    elseif msg == "lock" then
        ns.db.window.locked = not ns.db.window.locked
        if ns.UI then ns.UI:UpdateLock() end
        if ns.db.window.locked then
            print(L.MSG_LIGHT_DAMAGE_LOCKED)
        else
            print("|cff00ccff[Light Damage]|r " .. L.CONFIG_UNLOCKED)
        end

    elseif msg:match("^lang") then
        local langInput = msg:match("^lang%s+(%w+)$")
        if not langInput then
            print("|cff00ccff[Light Damage]|r lang: enUS / zhCN / zhTW")
            return
        end

        langInput = langInput:lower()
        local targetLang = "zhCN"
        if langInput == "enus" then
            targetLang = "enUS"
        elseif langInput == "zhtw" then
            targetLang = "zhTW"
        elseif langInput == "zhcn" then
            targetLang = "zhCN"
        else
            print("|cff00ccff[Light Damage]|r lang: enUS / zhCN / zhTW")
            return
        end

        if ns.SwitchLanguage then
            ns:SwitchLanguage(targetLang)
            if ns.Config and ns.Config.RefreshUI then ns.Config:RefreshUI() end
        end

    elseif msg == "baseline" then
        if ns.CombatTracker then
            ns.CombatTracker:ResetBaselineToCurrentCount()
            if ns.Segments then
                ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL)
            end
            print(L.MSG_LIGHT_DAMAGE_BASELINE_MANUALLY_RESET)
        end
    elseif msg == "resetlog" then
        ns._resetLog = not ns._resetLog and true or false
        if ns._resetLog then
            print("|cffff8800[resetlog]|r ON — now do 团本->野外->普通副本->大秘境. Watch the "
                .. "REQUEST / BEFORE / AFTER / DEFERRED lines; send them to me.")
        else
            print("|cffff8800[resetlog]|r OFF")
        end
    elseif msg == "shadow" then
        -- Two independent questions, answered in one command:
        --  1. Did LightDamage's shadow actually reach the live FontStrings?
        --     (dump GetShadowColor/GetShadowOffset straight off the bars)
        --  2. Does this client render a FontString shadow at all here?
        --     (an A/B swatch built OUTSIDE the addon's font pipeline, so no
        --      refresh, cache or config path can influence it)
        local db = ns.db.display or {}
        print(string.format("|cff33ccffshadow diag|r  fontShadow=%s nameFontShadow=%s outline=%s (drop is fixed: X 0.5, Y 0.5, black 50%%)",
            tostring(db.fontShadow), tostring(db.nameFontShadow), tostring(db.fontOutline)))
        local cells = ns.UI and ns.UI._activeGridCells
        local bar = (cells and cells[1] and cells[1].bars and cells[1].bars[1])
            or (ns.UI and ns.UI.priBars and ns.UI.priBars[1])
        if bar then
            for _, fsName in ipairs({"rawValue", "rawTotalValue", "value", "name", "rawName"}) do
                local fs = bar[fsName]
                if fs and fs.GetShadowColor then
                    local _, fsz, fl = fs:GetFont()
                    local twin = fs._ldShadowFS
                    local twinText = twin and twin:GetText()
                    print(string.format("  %-14s shown=%s font(%s,%s) drawnShadow=%s offset=%s twinShown=%s text=%s",
                        fsName, tostring(fs:IsShown()), tostring(fsz), tostring(fl),
                        tostring(fs._ldShadowActive == true),
                        tostring(fs._ldShadowOffset),
                        tostring(twin and twin:IsShown()),
                        twinText ~= nil and tostring(twinText) or "<none>"))
                end
            end
        else
            print("  (no visible bar -- open the meter with combat data first)")
        end

        local swatch = ns._shadowSwatch
        if swatch then
            swatch:Hide(); ns._shadowSwatch = nil
            print("|cff33ccffshadow diag|r  A/B swatch hidden")
        else
            swatch = CreateFrame("Frame", nil, UIParent)
            swatch:SetSize(380, 196); swatch:SetPoint("CENTER", 0, 200)
            swatch:SetFrameStrata("FULLSCREEN_DIALOG")
            local bg = swatch:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(0.35, 0.35, 0.40, 1)
            local font = db.font or STANDARD_TEXT_FONT
            local size = db.fontSizeBase or 13
            local outline = ns.NormalizeFontOutline and ns:NormalizeFontOutline(db.fontOutline)
                or db.fontOutline or ""
            local scale = swatch:GetEffectiveScale()
            if type(scale) ~= "number" or scale <= 0 then scale = 1 end
            local offset = 8 / scale
            -- Row A is the isolated client test: Blizzard's own font, no flags
            -- at all.  Row B adds only the player's font+outline flags, so if A
            -- has a shadow and B does not, the flags (MONOCHROME in particular)
            -- are what suppress it.  Row C is the no-shadow control.
            local rows = {
                {label = "A  native API, default font", font = STANDARD_TEXT_FONT, outline = "", offset = offset},
                {label = "B  native API, your font", font = font, outline = outline, offset = offset},
                {label = "C  no shadow (control)", font = font, outline = outline, offset = 0},
            }
            for index, row in ipairs(rows) do
                local fs = swatch:CreateFontString(nil, "OVERLAY")
                local applied = fs:SetFont(row.font, size + 6, row.outline)
                fs:SetPoint("TOP", swatch, "TOP", 0, -16 - (index - 1) * 42)
                fs:SetTextColor(1, 1, 1, 1)
                fs:SetText(row.label)
                if row.offset > 0 then
                    fs:SetShadowColor(1, 0, 0, 1)
                    fs:SetShadowOffset(row.offset, -row.offset)
                else
                    fs:SetShadowColor(0, 0, 0, 0)
                    fs:SetShadowOffset(0, 0)
                end
                local livePath, liveSize, liveFlags = fs:GetFont()
                local sr, sg, sb, sa = fs:GetShadowColor()
                local sx, sy = fs:GetShadowOffset()
                print(string.format("  row %s setFont=%s flags=%q size=%s shadow=(%s,%s,%s,%s) offset=(%.2f,%.2f) path=%s",
                    row.label:sub(1, 1), tostring(applied), tostring(liveFlags), tostring(liveSize),
                    tostring(sr), tostring(sg), tostring(sb), tostring(sa),
                    tonumber(sx) or 0, tonumber(sy) or 0, tostring(livePath)))
            end
            -- Row D is exactly what LightDamage now ships: a second FontString
            -- drawn underneath at the design spec (X 0.5, Y 0.5, black 50%),
            -- with no outline, which needs no client shadow support at all.
            local drop = 0.5 / scale
            local drawn = swatch:CreateFontString(nil, "ARTWORK")
            drawn:SetFont(font, size + 6, "")
            drawn:SetPoint("TOP", swatch, "TOP", drop, -(16 + 3 * 42) - drop)
            drawn:SetTextColor(0, 0, 0, 0.5)
            drawn:SetText("D  drawn shadow, shipping look")
            local real = swatch:CreateFontString(nil, "OVERLAY")
            real:SetFont(font, size + 6, outline)
            real:SetPoint("TOP", swatch, "TOP", 0, -(16 + 3 * 42))
            real:SetTextColor(1, 1, 1, 1)
            real:SetText("D  drawn shadow, shipping look")
            print(string.format("|cff33ccffshadow diag|r  swatch scale=%.3f: rows A/B use 8 real px (%.2f local), row D uses 0.5 real px (%.2f local)",
                scale, offset, drop))
            print("  rows A/B use the native API (dead on this client); row D is the drawn shadow.")
            swatch:Show()
            ns._shadowSwatch = swatch
            print("|cff33ccffshadow diag|r  A/B/C swatch shown above the screen centre. "
                .. "Run /ld shadow again to hide it.")
        end
    elseif msg == "cpu" or msg == "diag" then
        -- Read-only snapshot of everything that can accumulate during a run.
        -- Run it during the climb and again right after /reload; whichever
        -- number is large during play but small after reload is the leak.
        local function countKeys(t)
            local n = 0
            if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
            return n
        end
        local CT, segs = ns.CombatTracker, ns.Segments
        local count = 0
        local G = ns.DamageMeterGateway
        if G then
            local s, st = G:GetAvailableSessionsRaw()
            if st == G.ACCESSIBLE and type(s) == "table" then count = #s end
        end
        print("|cff33ccffLightDamage diag|r  inCombat=" .. tostring(ns.state.inCombat)
            .. "  scene=" .. tostring(ns.state.sceneKey))
        print(string.format("  Blizzard sessions=%d  cursor=%s  history=%d",
            count, tostring(CT and CT._lastProcessedCount), segs and #(segs.history or {}) or 0))
        if CT then
            print(string.format("  completedContexts=%d  sessionContextByID=%d  completedSessionIDs=%d",
                #(CT._completedContexts or {}), countKeys(CT._sessionContextByID), countKeys(CT._completedSessionIDs)))
            print(string.format("  sessionGenByID=%d  primaryByGen=%d  observedGen=%d",
                countKeys(CT._sessionGenerationByID), countKeys(CT._primarySessionByGeneration),
                countKeys(CT._meterObservedGenerations)))
            print(string.format("  synthetic=%d  supplemental=%d  archiveFirstSeen=%d  pendingActions=%d",
                countKeys(CT._syntheticSessionIDs), countKeys(CT._supplementalSessionIDs),
                countKeys(CT._archiveFirstSeenAt), #(CT._actions or {})))
            print(string.format("  watchdog=%s  edgeWatcher=%s  mythicBoundary=%s  pendingMythic=%s",
                tostring(CT._watchdog ~= nil), tostring(CT._combatEdgeWatcher ~= nil),
                tostring(CT._mythicRunBoundary ~= nil),
                tostring(ns.MythicPlus and ns.MythicPlus._pendingMythicSeg ~= nil)))
        end
        print(string.format("  playerCache=%d", countKeys(ns.PlayerInfoCache)))
        local ev = CT and CT._evCounts or {}
        print(string.format("  events cur=%d combat=%d flushes=%d regen=%d  |  GetAvailableSessions realcalls=%s",
            ev.DAMAGE_METER_CURRENT_SESSION_UPDATED or 0, ev.DAMAGE_METER_COMBAT_SESSION_UPDATED or 0,
            CT and CT._combatFlushCount or 0,
            (ev.PLAYER_REGEN_DISABLED or 0) + (ev.PLAYER_REGEN_ENABLED or 0),
            tostring(G and G._sessionsRealCalls or 0)))
        print(string.format("  timing flushMs=%.0f (n=%d)  refreshMs=%.0f (n=%d)",
            CT and CT._flushMs or 0, CT and CT._combatFlushCount or 0,
            ns._refreshMs or 0, ns._refreshCount or 0))
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            print(string.format("  memory=%.0f KB", GetAddOnMemoryUsage("LightDamage") or 0))
        end
        if GetCVar and GetCVar("scriptProfile") == "1" and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
            UpdateAddOnCPUUsage()
            print(string.format("  cpu(cumulative)=%.1f ms", GetAddOnCPUUsage("LightDamage") or 0))
        else
            print("  cpu: run '/console scriptProfile 1' then /reload to enable CPU numbers")
        end
    elseif msg == "debug" then
        ns:PrintDebugInfo()
    elseif msg == "api" then
        if ns.CombatTracker then ns.CombatTracker:DebugAPI() end
    elseif msg == "sessions" then
        if ns.CombatTracker then ns.CombatTracker:DebugSessions() end
    elseif msg == "recap" then
        ns:DebugRecapFields()
    elseif msg == "deathdebug" then
        ns:DebugDeathRecapIDs()
    elseif msg == "avoidable" then
        ns:DebugAvoidableDamageTaken()
    elseif msg == "overheal" then
        local gateway = ns.DamageMeterGateway
        if not gateway or ns.state.inCombat then print(L.COMBAT_DATA_LOCKED); return end
        local sessions, sessionState = gateway:GetAvailableSessionsRaw()
        if sessionState ~= gateway.ACCESSIBLE then print(L.COMBAT_DATA_LOCKED); return end
        local s, sState = gateway:ReadField(sessions, sessions and #sessions or 0)
        if sState ~= gateway.ACCESSIBLE then print(L.DEBUG_NO_HISTORY_SESSION); return end
        local sessionID, idState = gateway:ReadField(s, "sessionID")
        if idState ~= gateway.ACCESSIBLE or type(sessionID) ~= "number" then print(L.COMBAT_DATA_LOCKED); return end
        local src, sourceState = gateway:GetRawSource(nil, sessionID,
            Enum.DamageMeterType.HealingDone, UnitGUID("player"))
        local spells, spellsState = gateway:ReadTableField(src, "combatSpells")
        if sourceState ~= gateway.ACCESSIBLE or spellsState ~= gateway.ACCESSIBLE then
            print(L.NO_HEALING_DATA); return
        end
        local totalOH = 0
        for _, sp in ipairs(spells) do
            local spellID, spellState = gateway:ReadField(sp, "spellID")
            local amount, amountState = gateway:ReadField(sp, "totalAmount")
            local overkill, overkillState = gateway:ReadField(sp, "overkillAmount")
            if spellState == gateway.ACCESSIBLE and amountState == gateway.ACCESSIBLE
                and (overkillState == gateway.ACCESSIBLE or overkillState == gateway.MISSING) then
                local name = C_Spell and C_Spell.GetSpellName(spellID) or spellID
                overkill = type(overkill) == "number" and overkill or 0
                amount = type(amount) == "number" and amount or 0
                print(string.format("  [%s] heal=%d  overkill=%d", tostring(name), amount, overkill))
                totalOH = totalOH + overkill
            end
        end
        print(string.format(L.DEBUG_TOTAL_OVERKILL_FORMAT, totalOH))
    end
end

-- ============================================================
-- 调试信息
-- ============================================================
function ns:PrintDebugInfo()
    print("|cff00ccff[Light Damage Debug]|r")
    print("  initialized:", Core._initialized)
    print("  inCombat:", ns.state.inCombat)
    print("  UnitAffectingCombat:", UnitAffectingCombat("player"))
    print("  playerGUID:", ns.state.playerGUID)
    print("  isInInstance:", ns.state.isInInstance)
    print("  inMythicPlus:", ns.state.inMythicPlus)
    print("  Segments:", ns.Segments ~= nil)
    if ns.Segments then
        print("  Segments.overall:", ns.Segments.overall ~= nil)
        print("  Segments.current:", ns.Segments.current ~= nil)
        if ns.Segments.overall then
            local count = 0
            for _ in pairs(ns.Segments.overall.players) do count = count + 1 end
            print("  overall players:", count)
            print("  overall totalDamage:", ns.Segments.overall.totalDamage)
            print("  overall totalHealing:", ns.Segments.overall.totalHealing)
        end
        if ns.Segments.current then
            local count = 0
            for _ in pairs(ns.Segments.current.players) do count = count + 1 end
            print("  current players:", count)
            print("  current totalDamage:", ns.Segments.current.totalDamage)
            print("  current totalHealing:", ns.Segments.current.totalHealing)
        end
        print("  history count:", #ns.Segments.history)
        print("  viewIndex:", tostring(ns.Segments.viewIndex))
    end
    print("  CombatTracker baseline:", ns.CombatTracker and ns.CombatTracker._baselineSessionCount or "N/A")
    print("  CombatTracker lastProcessed:", ns.CombatTracker and ns.CombatTracker._lastProcessedCount or "N/A")
    print("  UI:", ns.UI ~= nil)
    if ns.UI then print("  UI visible:", ns.UI:IsVisible()) end
end

function ns:DebugDeathRecapIDs()
    print(L.DEBUG_LIGHT_DAMAGE_DEATH_RECAPID_DIAGNOSTICS)
    local gateway = ns.DamageMeterGateway
    if not gateway or ns.state.inCombat then print(L.COMBAT_DATA_LOCKED); return end
    local sessions, sessionState = gateway:GetAvailableSessionsRaw()
    if sessionState ~= gateway.ACCESSIBLE then print(L.COMBAT_DATA_LOCKED); return end
    local n = sessions and #sessions or 0
    print(string.format(L.DEBUG_TOTAL_SESSIONS_FORMAT, n))

    for i, s in ipairs(sessions or {}) do
        local sessionID, idState = gateway:ReadField(s, "sessionID")
        local duration, durationState = gateway:ReadField(s, "durationSeconds")
        local sessionName, nameState = gateway:ReadField(s, "name")
        if idState == gateway.ACCESSIBLE and type(sessionID) == "number"
            and (durationState == gateway.ACCESSIBLE or durationState == gateway.MISSING)
            and (nameState == gateway.ACCESSIBLE or nameState == gateway.MISSING) then
            local deathSess, state = gateway:GetRawSession(nil, sessionID, Enum.DamageMeterType.Deaths)
            local sources, sourcesState = gateway:ReadTableField(deathSess, "combatSources")
            if state == gateway.ACCESSIBLE and sourcesState == gateway.ACCESSIBLE and #sources > 0 then
                print(string.format("  [Session %d] dur=%.0fs name=%s",
                    i, duration or 0, tostring(sessionName)))
                for _, src in ipairs(sources) do
                    local sourceName, sourceNameState = gateway:ReadField(src, "name")
                    local totalAmount, totalState = gateway:ReadField(src, "totalAmount")
                    local recapID, recapState = gateway:ReadField(src, "deathRecapID")
                    if sourceNameState == gateway.ACCESSIBLE and totalState == gateway.ACCESSIBLE
                        and (recapState == gateway.ACCESSIBLE or recapState == gateway.MISSING) then
                        print(string.format("    name=%-20s deaths=%s recapID=%s",
                            tostring(sourceName), tostring(totalAmount), tostring(recapID)))
                    end
                end
            end
        end
    end
    print(L.DEBUG_END)
end

-- /ld avoidable -- read-only probe for the golden "[Avoidable]" marker in the
-- damage-taken breakdown.  The marker is driven by the official per-spell
-- isAvoidable flag on DamageTaken rows, but 12.1 also publishes a dedicated
-- Enum.DamageMeterType.AvoidableDamageTaken meter type.  This prints both so it
-- is unambiguous which one the live client actually populates: the state column
-- distinguishes an absent field from a protected one, which no amount of
-- reading the addon's own code can decide.
function ns:DebugAvoidableDamageTaken()
    print("|cff00ccff[Light Damage] avoidable damage-taken probe|r")
    local gateway = ns.DamageMeterGateway
    if not gateway then print("  gateway missing"); return end
    if ns.state.inCombat then print("  " .. tostring(L.COMBAT_DATA_LOCKED)); return end

    local dmTaken = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken
    local dmAvoidable = Enum and Enum.DamageMeterType and Enum.DamageMeterType.AvoidableDamageTaken
    print(string.format("  Enum.DamageMeterType.DamageTaken=%s  AvoidableDamageTaken=%s",
        tostring(dmTaken), tostring(dmAvoidable)))

    local sessions, sessionsState = gateway:GetAvailableSessionsRaw()
    if sessionsState ~= gateway.ACCESSIBLE or type(sessions) ~= "table" or #sessions == 0 then
        print("  no readable session list (state=" .. tostring(sessionsState) .. ")")
        return
    end
    local last, lastState = gateway:ReadField(sessions, #sessions)
    local sessionID, idState = gateway:ReadField(last, "sessionID")
    if lastState ~= gateway.ACCESSIBLE or idState ~= gateway.ACCESSIBLE
        or type(sessionID) ~= "number" then
        print("  newest session id unreadable (state=" .. tostring(idState) .. ")")
        return
    end
    local sessionName, nameState = gateway:ReadField(last, "name")
    print(string.format("  newest session #%d name=%s", sessionID,
        (nameState == gateway.ACCESSIBLE and type(sessionName) == "string")
            and sessionName or ("<" .. tostring(nameState) .. ">")))

    local playerGUID = ns.state.playerGUID or (UnitGUID and UnitGUID("player"))

    local function dumpSpells(label, dmType)
        if type(dmType) == "nil" then
            print("  " .. label .. ": meter type not present on this client")
            return
        end
        local source, sourceState = gateway:GetRawSource(nil, sessionID, dmType, playerGUID)
        if sourceState ~= gateway.ACCESSIBLE then
            print(string.format("  %s: no readable source for the local player (state=%s)",
                label, tostring(sourceState)))
            return
        end
        local spells, spellsState = gateway:ReadTableField(source, "combatSpells")
        if spellsState ~= gateway.ACCESSIBLE then
            print(string.format("  %s: combatSpells state=%s", label, tostring(spellsState)))
            return
        end
        print(string.format("  %s: %d spell row(s)", label, #spells))
        -- Every value below is printed only once the gateway says it is public,
        -- so the probe itself can never taint a frame or format a secret.
        local flagged = 0
        for index, sp in ipairs(spells) do
            local spellID, spellIDState = gateway:ReadField(sp, "spellID")
            local amount, amountState = gateway:ReadField(sp, "totalAmount")
            local avoidable, avoidableState = gateway:ReadField(sp, "isAvoidable")
            if avoidableState == gateway.ACCESSIBLE and avoidable == true then
                flagged = flagged + 1
            end
            if index <= 12 then
                local label = "<" .. tostring(spellIDState) .. ">"
                if spellIDState == gateway.ACCESSIBLE and type(spellID) == "number" then
                    label = "spell:" .. spellID
                    if C_Spell and C_Spell.GetSpellName then
                        local name = C_Spell.GetSpellName(spellID)
                        if gateway:IsAccessible(name) and type(name) == "string" and name ~= "" then
                            label = name
                        end
                    end
                end
                local amountText = "<" .. tostring(amountState) .. ">"
                if amountState == gateway.ACCESSIBLE and type(amount) == "number" then
                    amountText = string.format("%.0f", amount)
                end
                local flagText = avoidableState == gateway.ACCESSIBLE
                    and tostring(avoidable) or "<" .. tostring(avoidableState) .. ">"
                print(string.format("    %-28s amount=%-12s isAvoidable=%s",
                    label, amountText, flagText))
            end
        end
        print(string.format("    -> %d row(s) with isAvoidable == true", flagged))
    end

    dumpSpells("DamageTaken", dmTaken)
    dumpSpells("AvoidableDamageTaken", dmAvoidable)
    print("|cff00ccff[Light Damage] probe end|r")
end

function ns:DebugRecapFields()
    if not C_DeathRecap then print(L.DEBUG_LIGHT_DAMAGE_C_DEATHRECAP_MISSING); return end
    if not C_DeathRecap.HasRecapEvents or not C_DeathRecap.HasRecapEvents() then
        print(L.MSG_LIGHT_DAMAGE_NO_DEATHS_RECORDED_DIE_FIRST); return
    end
    local events = C_DeathRecap.GetRecapEvents and C_DeathRecap.GetRecapEvents()
    if not events or #events == 0 then print(L.MSG_LIGHT_DAMAGE_RETURNED_EMPTY); return end
    local maxHP = C_DeathRecap.GetRecapMaxHealth and C_DeathRecap.GetRecapMaxHealth()
    print(string.format(L.DEBUG_LIGHT_DAMAGE_MAXHEALTH_FORMAT_TOTAL_FORMAT_FIRST_3_FORMAT, tostring(maxHP), #events))
    for i = 1, math.min(3, #events) do
        local ev = events[i]
        print(string.format("  [%d]:", i))
        for k, v in pairs(ev) do
            print(string.format("    .%s = %s (%s)", tostring(k), tostring(v), type(v)))
        end
    end
end

function ns:SwitchMode(mode)
    ns.db.display.mode = mode
    if ns.UI then ns.UI:Refresh() end
end

function ns:GetDisplayData()
    local seg = ns.Segments and ns.Segments:GetViewSegment()
    if not seg then return {} end
    return ns.Analysis and ns.Analysis:GetSorted(seg, ns.db.display.mode) or {}
end

function ns:GetOverallData()
    local seg = ns.Segments and ns.Segments:GetOverallSegment()
    if not seg then return {} end
    return ns.Analysis and ns.Analysis:GetSorted(seg, ns.db.display.mode) or {}
end
