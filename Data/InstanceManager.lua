--[[
    Light Damage - InstanceManager.lua
    副本生命周期:SmartTrimHistory + MergeAndCleanInstance
    方法挂载到 ns.CombatTracker (CT) 上

    ★ 改造说明 (虚拟段架构):
    - 合并段创建时分配 _localID
    - viewIndex 改用 ViewArchived helper
    - SmartTrimHistory 后调 GCHiddenLocalIDs 清理孤儿黑名单
]]

local addonName, ns = ...
local L = ns.L

local function getInstanceScene(mythicLevel, instanceType)
    if mythicLevel and mythicLevel > 0 then return "mplus" end
    if instanceType == "raid" then return "raid" end
    return "dungeon"
end

local function shouldGenOverall(scene)
    if not ns.db.mythicPlus.enabled then return false end
    if scene == "mplus"   then return ns.db.mythicPlus.genOverallMPlus end
    if scene == "raid"    then return ns.db.mythicPlus.genOverallRaid end
    return ns.db.mythicPlus.genOverallDungeon
end

local function shouldCleanTrash(scene)
    if not ns.db.mythicPlus.autoCleanTrash then return false end
    if scene == "mplus"   then return ns.db.mythicPlus.cleanTrashMPlus end
    if scene == "raid"    then return ns.db.mythicPlus.cleanTrashRaid end
    return ns.db.mythicPlus.cleanTrashDungeon
end

-- ============================================================
-- 智能裁剪历史记录
-- ★ 改造:裁剪后清理孤儿黑名单
-- ============================================================
function ns.CombatTracker:SmartTrimHistory()
    local segs = ns.Segments
    if not segs or not segs.history then return end
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30

    while #segs.history > maxSeg do
        table.remove(segs.history, #segs.history)
    end

    -- ★ 清理孤儿 localID 黑名单
    if segs.GCHiddenLocalIDs then
        segs:GCHiddenLocalIDs()
    end
end

-- ============================================================
-- 退出副本时:合并该副本所有 seg → 一条汇总
-- ============================================================
function ns.CombatTracker:MergeAndCleanInstance(instanceTag, mythicLevel, mythicMapName, instanceName)
    local CT = ns.CombatTracker
    local segs = ns.Segments
    if not segs then return end

    mythicLevel = mythicLevel or 0
    local isRaid = (CT._currentInstanceType == "raid")

    local scene = getInstanceScene(mythicLevel, CT._currentInstanceType)
    local doGenOverall = shouldGenOverall(scene)
    local doCleanTrash = shouldCleanTrash(scene)

    local instSegs = {}
    for i, seg in ipairs(segs.history) do
        if seg._instanceTag == instanceTag and not seg._isMerged then
            table.insert(instSegs, {idx = i, seg = seg})
        end
    end
    if #instSegs == 0 then return end

    local zoneName
    if mythicLevel > 0 and mythicMapName and mythicMapName ~= "" then zoneName = mythicMapName
    elseif instanceName and instanceName ~= "" then zoneName = instanceName
    elseif instSegs[1].seg._instanceDisplayName and instSegs[1].seg._instanceDisplayName ~= "" then zoneName = instSegs[1].seg._instanceDisplayName
    else zoneName = instanceTag:match("^([^|]+)") or L.INSTANCE end

    local function normalizeSessionName(name)
        if not name or name == "" then return "" end
        name = tostring(name)
        name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
        name = name:gsub("|r", "")
        name = name:gsub("%s+", "")
        return name:lower()
    end

    local function findBlizzardOverallSessionID()
        -- ★ 只有启用“自动生成全程段”时，才隐藏暴雪官方汇总段
        if not doGenOverall then return nil end

        if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then
            return nil
        end

        local wantedName = normalizeSessionName(zoneName)
        if wantedName == "" then return nil end

        local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if not ok or not sessions then return nil end

        local foundSID = nil

        for _, s in ipairs(sessions) do
            local rawName = s and s.name
            if rawName and s.sessionID then
                local compact = normalizeSessionName(rawName)

                -- ★ 只检测当前副本名，不检测层数
                if compact:find(wantedName, 1, true) then
                    foundSID = s.sessionID
                end
            end
        end

        return foundSID
    end

    local function hideBlizzardOverallSession(sessionID)
        if not doGenOverall then return end
        if not sessionID or not ns.db then return end
        ns.db.hiddenSessionIDs = ns.db.hiddenSessionIDs or {}
        ns.db.hiddenSessionIDs[sessionID] = true

        if ns.HistoryList and ns.HistoryList.Refresh then
            ns.HistoryList:Refresh()
        end
    end

    local blizzardOverallSID = findBlizzardOverallSessionID()

    local function cloneOverallToMerged(merged)
        -- ★ 直接从暴雪 Overall session 拉数据,避开手动累加导致的"全程汇总 session 被重复计入"问题
        local function getAmount(val)
            if issecretvalue and issecretvalue(val) then return 0 end
            if type(val) == "number" then return val end
            return 0
        end

        local sType = Enum.DamageMeterSessionType.Overall

        local function getSession(dmType)
            local ok, sess = pcall(C_DamageMeter.GetCombatSessionFromType, sType, dmType)
            if ok and sess then return sess end
            return nil
        end

        local function getSourceData(dmType, guid, creatureID)
            local ok, srcData = pcall(
                C_DamageMeter.GetCombatSessionSourceFromType,
                sType, dmType, guid, creatureID
            )
            if ok and srcData then return srcData end
            return nil
        end

        local function fetchTotal(dmType)
            local sess = getSession(dmType)
            if sess and sess.totalAmount then return getAmount(sess.totalAmount) end
            return 0
        end

        merged.totalDamage      = fetchTotal(Enum.DamageMeterType.DamageDone)
        merged.totalHealing     = fetchTotal(Enum.DamageMeterType.HealingDone)
        merged.totalDamageTaken = fetchTotal(Enum.DamageMeterType.DamageTaken)

        local apiDur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0
        merged.duration = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0)
                        and CT._overallDurationSnapshot
                        or (apiDur > 0 and apiDur or 0)

        -- 玩家数据：从暴雪 Overall session 的 combatSources 重建
        merged.players = {}
        for dmType, field in pairs({
            [Enum.DamageMeterType.DamageDone]  = "damage",
            [Enum.DamageMeterType.HealingDone] = "healing",
            [Enum.DamageMeterType.DamageTaken] = "damageTaken",
        }) do
            local spellField = field == "damageTaken" and "damageTakenSpells" or "spells"
            local sess = getSession(dmType)

            if sess and sess.combatSources then
                for _, src in ipairs(sess.combatSources) do
                    local guid = src.sourceGUID
                    local total = getAmount(src.totalAmount)

                    if guid and total > 0 then
                        local hasValidClass = src.classFilename and src.classFilename ~= ""
                        local creatureID = src.sourceCreatureID
                        local isPet = (creatureID ~= nil and creatureID > 0) and not hasValidClass

                        if not isPet then
                            local pd = merged.players[guid]
                            if not pd then
                                pd = segs:NewPlayerData(guid, src.name, src.classFilename or "WARRIOR")
                                merged.players[guid] = pd
                            end

                            pd.class = src.classFilename or pd.class
                            if src.specIconID and src.specIconID > 0 then
                                pd.specIconID = src.specIconID
                            end

                            pd[field] = (pd[field] or 0) + total

                            -- ★ 补齐技能细分：伤害 / 治疗 / 友方承伤
                            local srcData = getSourceData(dmType, guid, creatureID)
                            if srcData and srcData.combatSpells then
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID)
                                    local amt = getAmount(sp.totalAmount)

                                    if spellID > 0 and amt > 0 then
                                        if not pd[spellField][spellID] then
                                            local spellName =
                                                (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
                                                or ("spell:" .. spellID)
                                            pd[spellField][spellID] = segs:NewSpellData(spellID, spellName, nil)
                                        end

                                        local sd = pd[spellField][spellID]
                                        if dmType == Enum.DamageMeterType.HealingDone then
                                            sd.healing = (sd.healing or 0) + amt
                                        else
                                            sd.damage = (sd.damage or 0) + amt
                                        end

                                        sd.hits = (sd.hits or 0) + 1
                                        if sp.isAvoidable then sd.isAvoidable = true end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- ★ 补齐打断 / 驱散：总数 + 技能细分
        for dmType, field in pairs({
            [Enum.DamageMeterType.Interrupts] = "interrupts",
            [Enum.DamageMeterType.Dispels]    = "dispels",
        }) do
            local spellField = field == "interrupts" and "interruptSpells" or "dispelSpells"
            local sess = getSession(dmType)

            if sess and sess.combatSources then
                for _, src in ipairs(sess.combatSources) do
                    local guid = src.sourceGUID
                    local creatureID = src.sourceCreatureID
                    local total = getAmount(src.totalAmount)

                    if guid and total > 0 then
                        local hasValidClass = src.classFilename and src.classFilename ~= ""
                        local isPet = (creatureID ~= nil and creatureID > 0) and not hasValidClass

                        if not isPet then
                            local pd = merged.players[guid]
                            if not pd then
                                pd = segs:NewPlayerData(guid, src.name, src.classFilename or "WARRIOR")
                                merged.players[guid] = pd
                            end

                            pd.class = src.classFilename or pd.class
                            if src.specIconID and src.specIconID > 0 then
                                pd.specIconID = src.specIconID
                            end

                            pd[field] = (pd[field] or 0) + total

                            local srcData = getSourceData(dmType, guid, creatureID)
                            if srcData and srcData.combatSpells then
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID)

                                    if spellID > 0 then
                                        local amt = getAmount(sp.totalAmount)
                                        if amt == 0 then amt = getAmount(sp.casts) end
                                        if amt == 0 then amt = 1 end

                                        if amt > 0 then
                                            if not pd[spellField][spellID] then
                                                local spellName =
                                                    (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
                                                    or ("spell:" .. spellID)
                                                pd[spellField][spellID] = segs:NewSpellData(spellID, spellName, nil)
                                            end

                                            local sd = pd[spellField][spellID]
                                            sd.hits = (sd.hits or 0) + amt
                                            sd.damage = (sd.damage or 0) + amt
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local function rebuildEnemyDamageTakenList()
            merged.enemyDamageTakenList = {}

            local sess = getSession(Enum.DamageMeterType.EnemyDamageTaken)
            if not sess or not sess.combatSources then return end

            for _, enemy in ipairs(sess.combatSources) do
                local creatureID = enemy.sourceCreatureID
                local enemyName = "?"
                local hasName = false

                if type(enemy.name) == "string" then
                    enemyName = enemy.name
                    hasName = true
                end

                if creatureID or hasName then
                    local total = getAmount(enemy.totalAmount)
                    if total > 0 then
                        local perSec = getAmount(enemy.amountPerSecond)
                        local entry = {
                            creatureID = creatureID,
                            name = enemyName,
                            total = total,
                            perSec = perSec,
                            sources = {},
                        }

                        local srcData = getSourceData(Enum.DamageMeterType.EnemyDamageTaken, nil, creatureID)
                        if srcData and srcData.combatSpells then
                            pcall(function()
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local details = sp.combatSpellDetails
                                    if details then
                                        local playerName = details.unitName
                                        local playerClass = details.unitClassFilename
                                        if not playerClass or playerClass == "" then playerClass = "NPC" end

                                        local amt = getAmount(details.amount)
                                        if amt == 0 then amt = getAmount(sp.totalAmount) end

                                        if playerName and type(playerName) == "string" and amt > 0
                                        and not (issecretvalue and issecretvalue(playerName)) then
                                            local found = false
                                            for _, s in ipairs(entry.sources) do
                                                if s.name == playerName then
                                                    s.amount = s.amount + amt
                                                    found = true
                                                    break
                                                end
                                            end
                                            if not found then
                                                table.insert(entry.sources, {
                                                    name = playerName,
                                                    class = playerClass,
                                                    amount = amt,
                                                })
                                            end
                                        end
                                    end
                                end
                            end)
                        end

                        table.sort(entry.sources, function(a, b) return a.amount > b.amount end)
                        table.insert(merged.enemyDamageTakenList, entry)
                    end
                end
            end

            table.sort(merged.enemyDamageTakenList, function(a, b) return a.total > b.total end)
        end

        -- deathLog 和 enemyDamageTakenList 仍从 segs.overall 拷贝（这两个手动维护的）
        local ovr = segs.overall
        merged.deathLog              = CopyTable((ovr and ovr.deathLog) or {})

        rebuildEnemyDamageTakenList()
        if #merged.enemyDamageTakenList == 0 then
            merged.enemyDamageTakenList = CopyTable((ovr and ovr.enemyDamageTakenList) or {})
        end

        table.sort(merged.deathLog, function(a, b)
            if a.isSelf ~= b.isSelf then return a.isSelf end
            return (a.gameTime or 0) < (b.gameTime or 0)
        end)
        while #merged.deathLog > 50 do
            local removed = false
            for i = 1, #merged.deathLog do
                if not merged.deathLog[i].isSelf then table.remove(merged.deathLog, i); removed = true; break end
            end
            if not removed then table.remove(merged.deathLog, 2) end
        end
    end

    -- ================= 分支1:M+ 正常通关 =================
    if mythicLevel > 0 then
        local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
        if pending then
            ns.MythicPlus._pendingMythicSeg = nil
            local mergedName = string.format("|cff4cb8e8+%d|r %s", pending.level, pending.mapName)
            local merged = segs:NewSegment("mythicplus", mergedName)
            merged.isActive = false; merged._instanceTag = nil; merged._isBoss = false; merged._isMerged = true
            merged._builtByMythicPlus = true; merged.success = pending.success
            merged._mythicLevel = pending.level; merged._mapName = pending.mapName
            merged.mythicLevel = pending.level; merged.mapName = pending.mapName
            merged.mapID = pending.mapID; merged._keystoneTime = (pending.elapsed or 0) / 1000
            merged._localID = segs:GenLocalID("mp")        -- ★ 分配本地 ID
            merged._dataLoaded = true                      -- ★ 合并段数据已就位

            cloneOverallToMerged(merged)

            

            local indicesToRemove, bossCount = {}, 0
            if doCleanTrash then
                for _, entry in ipairs(instSegs) do
                    if entry.seg._isBoss then
                        bossCount = bossCount + 1
                    else
                        table.insert(indicesToRemove, entry.idx)
                    end
                end
                table.sort(indicesToRemove, function(a, b) return a > b end)
                for _, idx in ipairs(indicesToRemove) do table.remove(segs.history, idx) end
            end

            if doGenOverall and (merged.totalDamage > 0 or merged.totalHealing > 0) then
                table.insert(segs.history, 1, merged)
                segs:ViewArchived(merged._localID)         -- ★ key-based view
                hideBlizzardOverallSession(blizzardOverallSID)
            end
            CT:SmartTrimHistory()
            CT:ResetBaselineToCurrentCount()
            if ns.Segments then
                ns.Segments._preReloadOverallData = nil
                if not ns.state.isInInstance then ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL) end
            end
            CT._overallDurationSnapshot = nil; CT._exitingInstanceTag = nil
            if ns.SaveSessionHistory then ns:SaveSessionHistory() end
            if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end
            local bossStr = bossCount > 0 and string.format(L.KEPT_BOSSES_FORMAT, bossCount) or ""
            print(string.format(L.MSG_LIGHT_DAMAGE_INST_FORMAT_ORGANIZED_FORMAT_PLUS_1_SUMMARY_FORMAT, pending.mapName, bossStr))
            return
        end
    end

    -- ================= 分支2:非M+ 或 M+中途放弃 =================
    local mergedName
    if mythicLevel > 0 then mergedName = string.format(L.COLORED_MYTHIC_OVERALL_NAME_FORMAT, mythicLevel, zoneName)
    else mergedName = string.format(L.OVERALL_SEGMENT_NAME_FORMAT, zoneName) end

    local merged = segs:NewSegment("history", mergedName)
    merged.isActive = false; merged._instanceTag = nil; merged._isBoss = false; merged._isMerged = true
    if mythicLevel > 0 then merged._mythicLevel = mythicLevel; merged._mapName = zoneName end
    merged._localID = segs:GenLocalID("merged")            -- ★ 分配本地 ID
    merged._dataLoaded = true

    if not isRaid then
        cloneOverallToMerged(merged)
    else
        local totalDur = 0
        for i = #instSegs, 1, -1 do
            local entry = instSegs[i]; local src = entry.seg
            src._dataLoaded = false; CT:LoadSegmentData(src)
            if src._isBoss then
                totalDur = totalDur + (src.duration or 0)
                for guid, pd in pairs(src.players) do
                    local mp = segs:GetPlayer(merged, guid, pd.name, nil)
                    if mp then
                        mp.class = pd.class or mp.class
                        mp.damage = (mp.damage or 0) + (pd.damage or 0); mp.healing = (mp.healing or 0) + (pd.healing or 0)
                        mp.damageTaken = (mp.damageTaken or 0) + (pd.damageTaken or 0)
                        mp.interrupts = (mp.interrupts or 0) + (pd.interrupts or 0); mp.dispels = (mp.dispels or 0) + (pd.dispels or 0)
                        mp.deaths = (mp.deaths or 0) + (pd.deaths or 0)
                        for spellID, sd in pairs(pd.spells or {}) do
                            if not mp.spells[spellID] then mp.spells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.spells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.healing = (msd.healing or 0) + (sd.healing or 0)
                            msd.hits = (msd.hits or 0) + (sd.hits or 0); msd.crits = (msd.crits or 0) + (sd.crits or 0)
                        end
                        for spellID, sd in pairs(pd.damageTakenSpells or {}) do
                            if not mp.damageTakenSpells[spellID] then mp.damageTakenSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.damageTakenSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.interruptSpells or {}) do
                            if not mp.interruptSpells[spellID] then mp.interruptSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.interruptSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.dispelSpells or {}) do
                            if not mp.dispelSpells[spellID] then mp.dispelSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.dispelSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                    end
                end
                merged.totalDamage = merged.totalDamage + (src.totalDamage or 0)
                merged.totalHealing = merged.totalHealing + (src.totalHealing or 0)
                merged.totalDamageTaken = merged.totalDamageTaken + (src.totalDamageTaken or 0)
                for _, dr in ipairs(src.deathLog or {}) do table.insert(merged.deathLog, dr) end
                for _, edt in ipairs(src.enemyDamageTakenList or {}) do
                    local found = false
                    for _, existing in ipairs(merged.enemyDamageTakenList) do
                        if existing.creatureID == edt.creatureID then
                            existing.total = existing.total + edt.total
                            for _, s in ipairs(edt.sources or {}) do
                                local sf = false
                                for _, es in ipairs(existing.sources) do
                                    if es.name == s.name then es.amount = es.amount + s.amount; sf = true; break end
                                end
                                if not sf then table.insert(existing.sources, CopyTable(s)) end
                            end
                            found = true; break
                        end
                    end
                    if not found then table.insert(merged.enemyDamageTakenList, CopyTable(edt)) end
                end
            end
        end
        merged.duration = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0) and CT._overallDurationSnapshot or totalDur
    end

    -- 收尾:删掉小怪,保留 Boss
    local indicesToRemove, bossCount = {}, 0
    if doCleanTrash then
        for _, entry in ipairs(instSegs) do
            if entry.seg._isBoss then
                bossCount = bossCount + 1
            else
                table.insert(indicesToRemove, entry.idx)
            end
        end
        table.sort(indicesToRemove, function(a, b) return a > b end)
        for _, idx in ipairs(indicesToRemove) do table.remove(segs.history, idx) end
    end

    if doGenOverall and (merged.totalDamage > 0 or merged.totalHealing > 0) then
        table.insert(segs.history, 1, merged)
        segs:ViewArchived(merged._localID)             -- ★ key-based view
        hideBlizzardOverallSession(blizzardOverallSID)
    end
    CT:SmartTrimHistory()
    CT:ResetBaselineToCurrentCount()

    if ns.Segments then
        ns.Segments._preReloadOverallData = nil
        if not ns.state.isInInstance then
            if C_DamageMeter.ResetAllCombatSessions then
                if ns.Segments.history then
                    for _, s in ipairs(ns.Segments.history) do
                        if s._sessionID and not s._dataLoaded then CT:LoadSegmentData(s) end
                    end
                end
                CT:ClearLoadedSessionIDs()
                CT._internalReset = true; C_DamageMeter.ResetAllCombatSessions()
                if ns.Segments.ClearHiddenSessionIDs then ns.Segments:ClearHiddenSessionIDs() end  -- ★
            end
            CT._baselineSessionCount = 0; CT._lastProcessedCount = 0; CT._initialBaselineSet = false
            ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL)
        end
    end
    CT._overallDurationSnapshot = nil; CT._exitingInstanceTag = nil
    if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end
    local bossStr = bossCount > 0 and string.format(L.KEPT_BOSSES_FORMAT, bossCount) or ""
    print(string.format(L.MSG_LIGHT_DAMAGE_INST_FORMAT_ORGANIZED_FORMAT_PLUS_1_SUMMARY_FORMAT, zoneName, bossStr))
end