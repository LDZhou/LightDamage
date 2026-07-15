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
        bgColor    = {0.02, 0.02, 0.025, 0.58},
        ovrBgColor = {0.025, 0.035, 0.05, 0.62},
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
        headerFontColor   = {0.55, 0.55, 0.55, 0.9},
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
            enemyDamageTaken = {0.78, 0.08, 0.10, 1},
            deaths           = {0.0, 0.65, 1.0, 1},
            interrupts       = {0.0, 0.65, 1.0, 1},
            dispels          = {0.0, 0.65, 1.0, 1},
        },
        alwaysShowSelf = false,
        useShortTabs   = false,
        tabLabelStyle  = "full",
        bottomBarModes = {
            damage = true,
            healing = true,
            damageTaken = false,
            deaths = true,
            enemyDamageTaken = true,
            interrupts = false,
            dispels = false,
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
        combatInterval = 0.3,
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
local refreshTimer
local refreshDirty = true

local function RefreshInterval()
    local settings = ns.db and ns.db.smartRefresh or ns.defaults.smartRefresh
    local value = ns.state.inCombat and settings.combatInterval or settings.idleInterval
    return math.max(0.1, tonumber(value) or (ns.state.inCombat and 0.3 or 2.0))
end

local function CancelRefreshTimer()
    if refreshTimer then
        refreshTimer:Cancel()
        refreshTimer = nil
    end
end

local function RunScheduledRefresh()
    refreshTimer = nil
    if not ns.UI or not ns.UI.frame or not ns.UI.frame:IsShown() then return end

    refreshDirty = false
    if ns.CombatTracker then ns.CombatTracker:PullCurrentData() end
    if ns.DetailView and ns.DetailView:IsVisible() then
        pcall(function() ns.DetailView:Refresh() end)
    end

    -- Live combat data has no reliable public dirty event.  Preserve the
    -- configured cadence while visible, but keep no high-frequency ticker
    -- alive for a hidden window.
    refreshTimer = C_Timer.NewTimer(RefreshInterval(), RunScheduledRefresh)
end

function ns:RequestRefresh(reason, immediate)
    refreshDirty = true
    if ns.DamageMeterGateway and ns.DamageMeterGateway.MarkDirty then
        ns.DamageMeterGateway:MarkDirty(reason or "ui")
    end
    if not ns.UI or not ns.UI.frame or not ns.UI.frame:IsShown() then
        CancelRefreshTimer()
        return
    end
    if immediate then
        CancelRefreshTimer()
        refreshTimer = C_Timer.NewTimer(0, RunScheduledRefresh)
    elseif not refreshTimer then
        refreshTimer = C_Timer.NewTimer(RefreshInterval(), RunScheduledRefresh)
    end
end

-- Alias used by data gateway/history-store style modules.
ns.MarkRefreshDirty = ns.RequestRefresh

function ns:AttachRefreshVisibilityHooks()
    local frame = ns.UI and ns.UI.frame
    if not frame or frame._lightDamageRefreshHooks then return false end
    frame._lightDamageRefreshHooks = true
    frame:HookScript("OnShow", function() ns:RequestRefresh("window-show", true) end)
    frame:HookScript("OnHide", function() CancelRefreshTimer() end)
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
