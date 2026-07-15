--[[
    LD Combat Stats - Analysis.lua
    数据分析: 排序、技能细分、汇总计算
]]

local addonName, ns = ...
local L = ns.L

local Analysis = {}
ns.Analysis = Analysis

function Analysis:Init() end

-- ============================================================
-- 获取排序后的玩家列表
-- ============================================================
function Analysis:GetSorted(segment, mode)
    if not segment then return {} end

    self._sortedCacheMap = self._sortedCacheMap or setmetatable({}, {__mode="k"})
    local byMode = self._sortedCacheMap[segment]
    if not byMode then byMode = {}; self._sortedCacheMap[segment] = byMode end
    local modeKey = mode
    if byMode[modeKey] then return byMode[modeKey] end

    -- 敌人承伤走独立数据结构
    if mode == "enemyDamageTaken" then
        local list = segment.enemyDamageTakenList or {}
        local result = {}
        local totalValue = 0
        for _, entry in ipairs(list) do totalValue = totalValue + entry.total end
        for i, entry in ipairs(list) do
            table.insert(result, {
                guid     = "creature_" .. (entry.creatureID or i),
                name     = entry.name,
                class    = "NPC",
                value    = entry.total,
                perSec   = entry.perSec,
                percent  = totalValue > 0 and (entry.total / totalValue * 100) or 0,
                deaths   = 0, interrupts = 0, dispels = 0,
                _isEnemy = true,
                _sources = entry.sources,
            })
        end
        byMode[modeKey] = result
        return result
    end

    local result     = {}
    local totalValue = 0

    for guid, pd in pairs(segment.players) do
        local value = self:GetPlayerValue(pd, mode, segment)
        if value > 0 then
            -- ★ 读取暴雪存储的每秒值（活跃时间口径，与官方面板一致）
            local perSec
            if mode == "damage"         then perSec = pd.damagePerSec
            elseif mode == "healing"    then perSec = pd.healingPerSec
            elseif mode == "damageTaken" then perSec = pd.damageTakenPerSec
            end

            table.insert(result, {
                guid        = guid,
                name        = pd.name,
                class       = pd.class,
                specID      = pd.specID,
                specIconID  = pd.specIconID, 
                ilvl        = pd.ilvl,
                score       = pd.score,
                value       = value,
                perSec      = perSec,   -- ★ 新增
                deaths      = pd.deaths,
                interrupts  = pd.interrupts,
                dispels     = pd.dispels,
                overhealing = pd.overhealing,
                activeTime  = pd.activeTime,
                petDamage   = self:GetPetTotal(pd, mode),
            })
            totalValue = totalValue + value
        end
    end

    table.sort(result, function(a, b) return a.value > b.value end)

    for _, d in ipairs(result) do
        d.percent = totalValue > 0 and (d.value / totalValue * 100) or 0
    end

    byMode[modeKey] = result
    return result
end

function Analysis:InvalidateCache()
    self._sortedCacheMap = setmetatable({}, {__mode="k"})
    self._sortedCache     = nil
    self._sortedCacheKey  = nil
    self._sortedCache2    = nil
    self._sortedCacheKey2 = nil
end


function Analysis:GetPlayerValue(pd, mode, segment)
    if mode == "damage" then
        return pd.damage
    elseif mode == "healing" then
        return pd.healing
    elseif mode == "damageTaken" then
        return pd.damageTaken
    elseif mode == "deaths" then
        return pd.deaths
    elseif mode == "interrupts" then
        return pd.interrupts
    elseif mode == "dispels" then
        return pd.dispels
    end
    return 0
end

function Analysis:GetPetTotal(pd, mode)
    local total = 0
    for _, pet in pairs(pd.pets or {}) do
        if mode == "damage" then
            total = total + (pet.damage or 0)
        elseif mode == "healing" then
            total = total + (pet.healing or 0)
        elseif mode == "damageTaken" then
            total = total + (pet.damageTaken or 0)
        elseif mode == "interrupts" then
            total = total + (pet.interrupts or 0)
        elseif mode == "dispels" then
            total = total + (pet.dispels or 0)
        end
    end
    return total
end

-- ============================================================
-- 技能细分 (供DetailView使用)
-- ============================================================
function Analysis:GetSpellBreakdown(segment, guid, mode)
    if not segment or not guid then return {} end

    local pd = segment.players[guid]
    if not pd then return {} end

    local result     = {}
    local totalValue = 0

    local sourceTable = pd.spells
    if mode == "damageTaken" then
        sourceTable = pd.damageTakenSpells or {}
    elseif mode == "interrupts" then
        sourceTable = pd.interruptSpells or {}
    elseif mode == "dispels" then
        sourceTable = pd.dispelSpells or {}
    end

    for spellKey, sd in pairs(sourceTable) do
        local spellID = sd.spellID or sd.id or spellKey
        local value = 0
        if mode == "damage" then
            value = sd.damage or 0
        elseif mode == "healing" then
            value = sd.healing or 0
        elseif mode == "damageTaken" then
            value = sd.damage or 0
        elseif mode == "interrupts" or mode == "dispels" then
            value = sd.hits or sd.damage or 0
        end

        if value > 0 then
            table.insert(result, {
                spellID     = spellID,
                name        = (sd.isPet and sd.petName and sd.petName ~= "")
                    and (sd.petName .. ": " .. (sd.name or ("spell:" .. spellID)))
                    or sd.name,
                school      = sd.school,
                value       = value,
                hits        = sd.hits,
                crits       = sd.crits,
                maxHit      = sd.maxHit,
                minHit      = sd.minHit ~= 999999999 and sd.minHit or 0,
                critPercent = sd.hits > 0 and (sd.crits / sd.hits * 100) or 0,
                overhealing = sd.overhealing,
                isPet       = sd.isPet == true,
                petName     = sd.petName,
                perSec      = sd.amountPerSecond,
                hasRate     = type(sd.amountPerSecond) == "number",
            })
            totalValue = totalValue + value
        end
    end

    -- 宠物技能
    if ns.db.tracking.mergePlayerPets then
        for petGUID, pet in pairs(pd.pets or {}) do
            local petSpellMap = pet.spells or {}
            if mode == "damageTaken" then
                petSpellMap = pet.damageTakenSpells or {}
            elseif mode == "interrupts" then
                petSpellMap = pet.interruptSpells or {}
            elseif mode == "dispels" then
                petSpellMap = pet.dispelSpells or {}
            end
            for spellKey, sd in pairs(petSpellMap) do
                local spellID = sd.spellID or sd.id or spellKey
                local value = 0
                if mode == "damage" then
                    value = sd.damage or 0
                elseif mode == "healing" then
                    value = sd.healing or 0
                elseif mode == "damageTaken" then
                    value = sd.damage or 0
                elseif mode == "interrupts" or mode == "dispels" then
                    value = sd.hits or sd.damage or 0
                end

                if value > 0 then
                    table.insert(result, {
                        spellID     = spellID,
                        name        = (pet.name or "Pet") .. ": " .. sd.name,
                        school      = sd.school,
                        value       = value,
                        hits        = sd.hits,
                        crits       = sd.crits,
                        maxHit      = sd.maxHit,
                        minHit      = sd.minHit ~= 999999999 and sd.minHit or 0,
                        critPercent = sd.hits > 0 and (sd.crits / sd.hits * 100) or 0,
                        isPet       = true,
                        petName     = pet.name,
                    })
                    totalValue = totalValue + value
                end
            end

            -- 宠物无技能细分时，显示总计行
            if not next(petSpellMap) then
                local petVal = 0
                if mode == "damage" then petVal = pet.damage or 0
                elseif mode == "healing" then petVal = pet.healing or 0
                elseif mode == "damageTaken" then petVal = pet.damageTaken or 0
                elseif mode == "interrupts" then petVal = pet.interrupts or 0
                elseif mode == "dispels" then petVal = pet.dispels or 0 end
                if petVal > 0 then
                    table.insert(result, {
                        spellID     = 0,
                        name        = (pet.name or "Pet") .. L.TOTAL_SUFFIX,
                        value       = petVal,
                        hits        = 0, crits = 0, maxHit = 0, minHit = 0, critPercent = 0,
                        isPet       = true,
                    })
                    totalValue = totalValue + petVal
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.value > b.value end)

    for _, d in ipairs(result) do
        d.percent = totalValue > 0 and (d.value / totalValue * 100) or 0
    end

    return result
end

-- ============================================================
-- 段落时长计算
-- ============================================================
function Analysis:GetSegmentDuration(segment)
    if not segment then return 0 end
    if segment.isActive then
        local gateway = ns.DamageMeterGateway
        local duration, status
        if gateway then
            duration, status = gateway:GetSessionDurationRaw(
                Enum.DamageMeterSessionType.Current)
        end
        if gateway and status == gateway.ACCESSIBLE and type(duration) == "number" then return duration end
        return 0
    end

    return segment.duration or 0
end

-- ============================================================
-- 综合战斗报告数据
-- ============================================================
function Analysis:GetFightSummary(segment)
    if not segment then return nil end

    local dur           = self:GetSegmentDuration(segment)
    local playerCount   = 0
    local totalDeaths   = 0
    local totalInts     = 0
    local totalDisp     = 0
    local groupDPS, groupHPS, groupDTPS = 0, 0, 0
    local hasDPS, hasHPS, hasDTPS = false, false, false

    for _, pd in pairs(segment.players) do
        playerCount = playerCount + 1
        totalDeaths = totalDeaths + pd.deaths
        totalInts   = totalInts   + pd.interrupts
        totalDisp   = totalDisp   + pd.dispels
        if type(pd.damagePerSec) == "number" then groupDPS = groupDPS + pd.damagePerSec; hasDPS = true end
        if type(pd.healingPerSec) == "number" then groupHPS = groupHPS + pd.healingPerSec; hasHPS = true end
        if type(pd.damageTakenPerSec) == "number" then groupDTPS = groupDTPS + pd.damageTakenPerSec; hasDTPS = true end
    end

    return {
        duration         = dur,
        playerCount      = playerCount,
        totalDamage      = segment.totalDamage,
        totalHealing     = segment.totalHealing,
        totalDamageTaken = segment.totalDamageTaken,
        groupDPS         = hasDPS and groupDPS or nil,
        groupHPS         = hasHPS and groupHPS or nil,
        groupDTPS        = hasDTPS and groupDTPS or nil,
        totalDeaths      = totalDeaths,
        totalInterrupts  = totalInts,
        totalDispels     = totalDisp,
        encounterName    = segment.encounterName,
        success          = segment.success,
    }
end

-- ============================================================
-- M+ 全程：获取某玩家在 overall 段的数据（供UI双列显示）
-- 返回 { value, perSec, percent } 或 nil
-- ============================================================
function Analysis:GetOverallPlayerData(guid, mode)
    -- ★ 战斗中 overall 数据可能含 Secret Value，禁止做除法运算
    if ns.state.inCombat then return nil end

    local ovr = ns.Segments and ns.Segments:GetOverallSegment()
    if not ovr then return nil end

    local pd = ovr.players[guid]
    if not pd then return nil end

    local value = self:GetPlayerValue(pd, mode, ovr)
    if value <= 0 then return nil end

    local total = 0
    for _, opd in pairs(ovr.players) do
        total = total + self:GetPlayerValue(opd, mode, ovr)
    end

    local perSec
    if mode == "damage" then perSec = pd.damagePerSec
    elseif mode == "healing" then perSec = pd.healingPerSec
    elseif mode == "damageTaken" then perSec = pd.damageTakenPerSec end
    return {
        value   = value,
        perSec  = perSec,
        percent = total > 0 and (value / total * 100) or 0,
        dur     = self:GetSegmentDuration(ovr),
    }
end
