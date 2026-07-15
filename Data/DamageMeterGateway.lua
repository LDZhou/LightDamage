--[[
    Light Damage - DamageMeterGateway.lua

    C_DamageMeter is the only statistics source.  This module deliberately
    exposes two different channels:

      raw    - values may be secret and may only be passed to secret-capable
               widgets.  No comparison, arithmetic, table-key use or saving.
      archive - an immutable snapshot whose authoritative totals and source
                amounts are complete. A genuinely missing optional child is
                marked unavailable; secret or errored data is retried and is
                never committed by a timeout.
]]
local addonName, ns = ...

local G = {}
ns.DamageMeterGateway = G

G.ACCESSIBLE = "accessible"
G.SECRET = "secret"
G.MISSING = "missing"
G.ERROR = "error"
G._dirty = {}
G._rawGeneration = 0

local function enum(name)
    return Enum and Enum.DamageMeterType and Enum.DamageMeterType[name]
end

local STAT_DEFS = {
    { enumName = "DamageDone",      field = "damage",     spellField = "spells" },
    { enumName = "HealingDone",     field = "healing",    spellField = "spells" },
    { enumName = "DamageTaken",     field = "damageTaken",spellField = "damageTakenSpells" },
    { enumName = "Interrupts",      field = "interrupts", spellField = "interruptSpells", count = true },
    { enumName = "Dispels",         field = "dispels",    spellField = "dispelSpells", count = true },
}

function G:IsAccessible(value)
    -- type() is safe for secret values; equality/boolean coercion is not.
    if type(value) == "nil" then return true end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible == true
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and not secret
    end
    return true
end

function G:IsTableAccessible(value)
    if type(value) == "nil" then return true end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, value)
        if ok then return accessible == true end
    end
    return self:IsAccessible(value)
end

function G:GetValueState(value)
    if not self:IsAccessible(value) then return self.SECRET end
    if type(value) == "nil" then return self.MISSING end
    return self.ACCESSIBLE
end

-- Every archive/table consumer uses these helpers. A protected container is
-- never indexed, and a protected scalar is never compared or coerced by Lua.
function G:ReadField(container, key)
    if type(container) == "nil" then return nil, self.MISSING end
    if type(container) ~= "table" then return nil, self.ERROR end
    if not self:IsTableAccessible(container) then return nil, self.SECRET end
    local ok, value = pcall(function() return container[key] end)
    if not ok then return nil, self.ERROR end
    if type(value) == "table" then
        return value, self:IsTableAccessible(value) and self.ACCESSIBLE or self.SECRET
    end
    return value, self:GetValueState(value)
end

function G:ReadTableField(container, key)
    local value, state = self:ReadField(container, key)
    if state ~= self.ACCESSIBLE then return value, state end
    if type(value) ~= "table" then return nil, self.ERROR end
    return value, self.ACCESSIBLE
end

local function numberValue(value, default)
    if not G:IsAccessible(value) then return nil, G.SECRET end
    if type(value) == "nil" then return default end
    if type(value) ~= "number" then return nil, G.ERROR end
    return value
end

local function stringValue(value, default)
    if not G:IsAccessible(value) then return nil, G.SECRET end
    if type(value) == "nil" then return default end
    if type(value) ~= "string" then return nil, G.ERROR end
    return value
end

local function boolValue(value, default)
    if not G:IsAccessible(value) then return nil, G.SECRET end
    if type(value) == "nil" then return default and true or false end
    if type(value) ~= "boolean" then return nil, G.ERROR end
    return value
end

local function numberField(container, key, default)
    local value, state = G:ReadField(container, key)
    if state == G.MISSING then return default end
    if state ~= G.ACCESSIBLE then return nil, state end
    return numberValue(value, default)
end

local function stringField(container, key, default)
    local value, state = G:ReadField(container, key)
    if state == G.MISSING then return default end
    if state ~= G.ACCESSIBLE then return nil, state end
    return stringValue(value, default)
end

local function boolField(container, key, default)
    local value, state = G:ReadField(container, key)
    if state == G.MISSING then return default and true or false end
    if state ~= G.ACCESSIBLE then return nil, state end
    return boolValue(value, default)
end

function G:MarkDirty(kind, sessionID)
    self._dirty[kind or "all"] = sessionID or true
end

function G:ConsumeDirty()
    local dirty = self._dirty
    self._dirty = {}
    return dirty
end

function G:InvalidateRaw(reason)
    self._rawGeneration = self._rawGeneration + 1
    self._lastInvalidationReason = reason
    self._dirty = {}
end

function G:GetRawGeneration()
    return self._rawGeneration
end

function G:GetAvailableSessionsRaw()
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then
        return nil, self.ERROR
    end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok then return nil, self.ERROR end
    if type(sessions) == "nil" then return nil, self.MISSING end
    if not self:IsTableAccessible(sessions) then return sessions, self.SECRET end
    return sessions, self.ACCESSIBLE
end

-- GetAvailableCombatSessions keeps the live combat as its final entry while
-- combat is active.  Unlike the source rows returned by the Current-session
-- APIs, this lightweight metadata (including the session name) is public.
-- Keep the access checks here so UI code never has to inspect a protected
-- value just to render the current combat title.
function G:GetLiveSessionName()
    local sessions, state = self:GetAvailableSessionsRaw()
    if state ~= self.ACCESSIBLE or type(sessions) ~= "table" then
        return nil, state
    end

    local okLast, session = pcall(function() return sessions[#sessions] end)
    if not okLast then return nil, self.ERROR end
    if type(session) == "nil" then return nil, self.MISSING end
    if type(session) ~= "table" or not self:IsTableAccessible(session) then return nil, self.SECRET end

    local name, nameState = self:ReadField(session, "name")
    if nameState == self.SECRET then return nil, self.SECRET end
    if nameState ~= self.ACCESSIBLE then return nil, nameState end
    if type(name) ~= "string" or name == "" then return nil, self.MISSING end
    return name, self.ACCESSIBLE
end

function G:GetSessionDurationRaw(sessionType)
    if not C_DamageMeter or not C_DamageMeter.GetSessionDurationSeconds then
        return nil, self.MISSING
    end
    local ok, duration = pcall(C_DamageMeter.GetSessionDurationSeconds,
        sessionType or Enum.DamageMeterSessionType.Current)
    if not ok then return nil, self.ERROR end
    if not self:IsAccessible(duration) then return duration, self.SECRET end
    if type(duration) == "nil" then return nil, self.MISSING end
    if type(duration) ~= "number" then return nil, self.ERROR end
    return duration, self.ACCESSIBLE
end

function G:GetRawSession(sessionType, sessionID, dmType)
    if not C_DamageMeter then return nil, self.ERROR end
    if not self:IsAccessible(sessionID) then return nil, self.SECRET end
    local ok, session
    if type(sessionID) ~= "nil" then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
    else
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
    end
    if not ok then return nil, self.ERROR end
    if type(session) == "nil" then return nil, self.MISSING end
    if type(session) ~= "table" or not self:IsTableAccessible(session) then
        return session, self.SECRET
    end
    local _, state = self:ReadField(session, "totalAmount")
    return session, state
end

function G:GetRawSource(sessionType, sessionID, dmType, sourceGUID, sourceCreatureID)
    if not C_DamageMeter then return nil, self.ERROR end
    if not self:IsAccessible(sessionID) or not self:IsAccessible(sourceGUID)
        or not self:IsAccessible(sourceCreatureID) then
        return nil, self.SECRET
    end
    local ok, source
    if type(sessionID) ~= "nil" then
        ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, dmType, sourceGUID, sourceCreatureID)
    else
        ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            sessionType, dmType, sourceGUID, sourceCreatureID)
    end
    if not ok then return nil, self.ERROR end
    if type(source) == "nil" then return nil, self.MISSING end
    if not self:IsTableAccessible(source) then return source, self.SECRET end
    local _, state = self:ReadField(source, "totalAmount")
    return source, state
end

-- UI compatibility: callers can decide whether to render raw values directly,
-- show an archived snapshot, or display a protected-data message.
function G:GetDetailAccessState(sessionType, sessionID, dmType, sourceGUID, sourceCreatureID)
    local source, state = self:GetRawSource(sessionType, sessionID, dmType, sourceGUID, sourceCreatureID)
    if type(source) == "nil" then return state, nil end
    if state == self.SECRET then return "raw", source end
    local _, spellState = self:ReadTableField(source, "combatSpells")
    if spellState == self.SECRET then return "raw", source end
    return "archive", source
end

local function newSpell(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, result = pcall(C_Spell.GetSpellName, spellID)
        if ok and G:IsAccessible(result) and type(result) == "string" and result ~= "" then
            name = result
        end
    end
    if type(name) ~= "string" or name == "" then name = "spell:" .. tostring(spellID) end
    return {
        spellID = spellID, name = name, school = nil,
        damage = 0, healing = 0, absorbed = 0,
        hits = 0, crits = 0, maxHit = 0, maxCrit = 0,
        amountPerSecond = nil,
        isPet = false, petName = nil,
    }
end

local function newPlayer(guid, name, class)
    return {
        guid = guid, name = name or "?", class = class,
        specID = nil, specIconID = nil, ilvl = 0, score = 0,
        damage = 0, healing = 0, overhealing = 0, absorbed = 0,
        damageTaken = 0, deaths = 0, interrupts = 0, dispels = 0,
        spells = {}, damageTakenSpells = {}, interruptSpells = {}, dispelSpells = {},
        pets = {}, activeTime = 0, lastActionTime = 0,
    }
end

local function addSpell(target, spellID, amount, field, count, avoidable, isPet, petName, perSecond)
    local storageKey = spellID
    if isPet then
        storageKey = "pet:" .. (petName or "") .. ":" .. tostring(spellID)
    end
    local spell = target[storageKey]
    if not spell then spell = newSpell(spellID); target[storageKey] = spell end
    if count then
        spell.hits = spell.hits + amount
        spell.damage = spell.damage + amount
    elseif field == "healing" then
        spell.healing = spell.healing + amount
    else
        spell.damage = spell.damage + amount
    end
    if avoidable then spell.isAvoidable = true end
    if type(perSecond) == "number" then
        spell.amountPerSecond = (spell.amountPerSecond or 0) + perSecond
    end
    if isPet then
        spell.isPet = true
        if petName and petName ~= "" then spell.petName = petName end
    end
end

local function ensurePlayer(candidate, guid, name, class, specIconID)
    local player = candidate.players[guid]
    if not player then
        player = newPlayer(guid, name, class)
        candidate.players[guid] = player
    end
    if name and name ~= "" then player.name = name end
    if class and class ~= "" then player.class = class end
    if specIconID and specIconID > 0 then player.specIconID = specIconID end
    -- Freeze enrichment into the archive candidate.  History must not depend
    -- on later cache refreshes or a unit no longer being inspectable.
    local cached = type(ns.PlayerInfoCache) == "table" and ns.PlayerInfoCache[guid]
    if type(cached) == "table" then
        local specID = type(cached.specID) == "number" and cached.specID or nil
        local ilvl = type(cached.ilvl) == "number" and cached.ilvl or 0
        local score = type(cached.score) == "number" and cached.score or 0
        if specID and specID > 0 then player.specID = specID end
        if ilvl > 0 then player.ilvl = ilvl end
        if score > 0 then player.score = score end
    end
    return player
end

local function getSource(selector, dmType, guid, creatureID)
    return G:GetRawSource(selector.sessionType, selector.sessionID, dmType, guid, creatureID)
end

local INCOMPLETE_FLAGS = {
    spell = "_spellDetailsIncomplete",
    death = "_deathDetailsIncomplete",
    enemySource = "_enemySourceDetailsIncomplete",
    attribution = "_playerAttributionIncomplete",
    rate = "_rateDetailsIncomplete",
}

local function markIncomplete(candidate, kind, target)
    candidate._detailsIncomplete = true
    local flag = INCOMPLETE_FLAGS[kind]
    if flag then candidate[flag] = true end
    if target then target._detailsIncomplete = true end
end

-- Spell breakdowns, death recaps, per-second enrichment and enemy-source
-- details are optional archive enrichment.  Their absence (including a field
-- that remains protected or errors independently) must never hold the core
-- totals/player rows or a boundary reset forever.  Preserve an explicit
-- incomplete marker instead of guessing data.
local function acceptOptionalFailure(candidate, status, kind, target, allowIncomplete)
    markIncomplete(candidate, kind, target)
    return true
end

local function readSourceIdentity(candidate, src, allowIncomplete, target)
    local identity = {}
    local status
    identity.isLocal, status = boolField(src, "isLocalPlayer", false)
    if status then
        markIncomplete(candidate, "attribution", target)
        identity.isLocal = false
    end
    identity.guid, status = stringField(src, "sourceGUID", nil)
    if status then
        identity._guidStatus = status
        markIncomplete(candidate, "attribution", target)
    end
    identity.creatureID, status = numberField(src, "sourceCreatureID", nil)
    if status then
        identity._creatureStatus = status
        markIncomplete(candidate, "attribution", target)
    end
    identity.name, status = stringField(src, "name", nil)
    if status then
        identity._nameStatus = status
        markIncomplete(candidate, "attribution", target)
    end
    identity.class, status = stringField(src, "classFilename", nil)
    if status then
        markIncomplete(candidate, "attribution", target)
    end
    identity.specIconID, status = numberField(src, "specIconID", 0)
    if status then
        markIncomplete(candidate, "attribution", target)
        identity.specIconID = 0
    end
    identity.perSec, status = numberField(src, "amountPerSecond", nil)
    if status then
        markIncomplete(candidate, "rate", target)
        identity.perSec = nil
    end
    identity.hasPerSec = type(identity.perSec) == "number"
    if identity.isLocal then
        identity.guid = ns.state.playerGUID or (UnitGUID and UnitGUID("player")) or identity.guid
        identity.name = identity.name or ns.state.playerName or (UnitName and UnitName("player"))
        if not identity.class and UnitClass then
            local _, class = UnitClass("player")
            identity.class = class
        end
    end
    -- Core player rows need a stable, public identity.  GUID is preferred, but
    -- the 12.1 API can legitimately omit it while exposing a public name or
    -- creature ID.  Use only those public values as deterministic local keys;
    -- if none is available, keep the whole candidate pending.
    identity.key = identity.guid
        or (identity.creatureID and ("creature:" .. tostring(identity.creatureID)))
        or (identity.name and identity.name ~= "" and ("name:" .. identity.name))
    if not identity.key then
        return nil, identity._guidStatus or identity._creatureStatus
            or identity._nameStatus or G.MISSING
    end
    return identity
end

local function archiveSpells(candidate, selector, def, dmType, identity, player, allowIncomplete)
    local sourceData, status = getSource(selector, dmType, identity.guid, identity.creatureID)
    if type(sourceData) == "nil" then
        return acceptOptionalFailure(candidate, status or G.MISSING, "spell", player, allowIncomplete)
    end
    local spells; spells, status = G:ReadTableField(sourceData, "combatSpells")
    if status ~= G.ACCESSIBLE then
        return acceptOptionalFailure(candidate, status, "spell", player, allowIncomplete)
    end

    local target = player[def.spellField]

    for _, sp in ipairs(spells) do
        if type(sp) ~= "table" or not G:IsTableAccessible(sp) then
            local inaccessible = type(sp) == "table" and G.SECRET or G.ERROR
            local ok; ok, status = acceptOptionalFailure(candidate, inaccessible, "spell", player, allowIncomplete)
            if not ok then return nil, status end
        else
            local spellID; spellID, status = numberField(sp, "spellID", 0)
            if status then
                local ok; ok, status = acceptOptionalFailure(candidate, status, "spell", player, allowIncomplete)
                if not ok then return nil, status end
            else
                local amount; amount, status = numberField(sp, "totalAmount", 0)
                if status then
                    local ok; ok, status = acceptOptionalFailure(candidate, status, "spell", player, allowIncomplete)
                    if not ok then return nil, status end
                else
                    local avoidable; avoidable, status = boolField(sp, "isAvoidable", false)
                    if status then
                        local ok; ok, status = acceptOptionalFailure(candidate, status, "spell", player, allowIncomplete)
                        if not ok then return nil, status end
                        avoidable = false
                    end
                    local spellIsPet, petName = false, nil
                    local details, detailsStatus = G:ReadTableField(sp, "combatSpellDetails")
                    if detailsStatus == G.ACCESSIBLE then
                        local detailStatus
                        spellIsPet, detailStatus = boolField(details, "isPet", false)
                        if detailStatus then
                            markIncomplete(candidate, "spell", player)
                            spellIsPet = false
                        end
                        petName, detailStatus = stringField(details, "unitName", nil)
                        if detailStatus then
                            markIncomplete(candidate, "spell", player)
                            petName = nil
                        end
                    elseif detailsStatus ~= G.MISSING then
                        markIncomplete(candidate, "spell", player)
                    end
                    if spellIsPet and not petName then
                        local creatureName, creatureStatus = stringField(sp, "creatureName", nil)
                        if creatureStatus then
                            markIncomplete(candidate, "spell", player)
                        else
                            petName = creatureName
                        end
                    end
                    local perSecond, rateStatus = numberField(sp, "amountPerSecond", nil)
                    if rateStatus then
                        markIncomplete(candidate, "rate", player)
                        perSecond = nil
                    end
                    if spellID > 0 and amount > 0 then
                        addSpell(target, spellID, amount, def.field, def.count,
                            avoidable, spellIsPet, petName, perSecond)
                    end
                end
            end
        end
    end
    return true
end

local function archiveStat(candidate, selector, def, allowIncomplete)
    local dmType = enum(def.enumName)
    if type(dmType) == "nil" then return true end
    local session, sessionStatus = G:GetRawSession(selector.sessionType, selector.sessionID, dmType)
    if type(session) == "nil" then
        -- Blizzard may omit any statistic session whose authoritative value is
        -- exactly zero.  Missing means zero for every mode; secret/error still
        -- keeps the core candidate pending.
        if sessionStatus == G.MISSING then return true end
        return nil, sessionStatus or G.ERROR
    end
    local total, status = numberField(session, "totalAmount", 0)
    if status then return nil, status end
    if def.field == "damage" then candidate.totalDamage = total
    elseif def.field == "healing" then candidate.totalHealing = total
    elseif def.field == "damageTaken" then candidate.totalDamageTaken = total end

    local sources; sources, status = G:ReadTableField(session, "combatSources")
    if status ~= G.ACCESSIBLE then
        if total == 0 then return true end
        return nil, status
    end
    local sawPositiveSource = false
    for _, src in ipairs(sources) do
        if type(src) ~= "table" or not G:IsTableAccessible(src) then
            return nil, type(src) == "table" and G.SECRET or G.ERROR
        end
        local amount; amount, status = numberField(src, "totalAmount", 0)
        if status then return nil, status end
        if amount > 0 then
            sawPositiveSource = true
            local identity; identity, status = readSourceIdentity(candidate, src, allowIncomplete)
            if not identity then return nil, status end
            -- Every combatSources row is an authoritative Blizzard source.  A
            -- creature ID, absent class, or differing spell creatureName does
            -- not prove pet ownership, so no owner relationship is invented.
            local player = ensurePlayer(candidate, identity.key, identity.name,
                identity.class, identity.specIconID)
            player[def.field] = (player[def.field] or 0) + amount
            if identity.hasPerSec then
                player[def.field .. "PerSec"] = identity.perSec
            end
            local ok; ok, status = archiveSpells(candidate, selector, def, dmType,
                identity, player, allowIncomplete)
            if not ok then return nil, status end
        end
    end
    if total > 0 and not sawPositiveSource then return nil, G.MISSING end
    return true
end

local function incompleteDeathRecord(identity, recapID, reason)
    return {
        timestamp = nil, gameTime = nil, playerName = identity.name,
        playerGUID = identity.guid, playerClass = identity.class,
        isSelf = identity.isLocal and true or false,
        killingAbility = nil, killerName = nil, events = {},
        lastHP = nil, maxHP = nil, totalDamageTaken = nil,
        totalHealingReceived = nil, timeSpan = nil, _incomplete = true,
        _incompleteReason = reason or G.MISSING, _recapID = recapID,
    }
end

local function archiveDeaths(candidate, selector, allowIncomplete)
    local dmType = enum("Deaths")
    if type(dmType) == "nil" then return true end
    local session, sessionStatus = G:GetRawSession(selector.sessionType, selector.sessionID, dmType)
    if type(session) == "nil" then
        if sessionStatus == G.MISSING then candidate.totalDeaths = 0; return true end
        return nil, sessionStatus or G.ERROR
    end
    local totalDeaths, status = numberField(session, "totalAmount", 0)
    if status then return nil, status end
    candidate.totalDeaths = totalDeaths
    local sources; sources, status = G:ReadTableField(session, "combatSources")
    if status ~= G.ACCESSIBLE then
        if totalDeaths == 0 then return true end
        return nil, status
    end
    local sawPositiveSource = false
    for _, src in ipairs(sources) do
        if type(src) ~= "table" or not G:IsTableAccessible(src) then
            return nil, type(src) == "table" and G.SECRET or G.ERROR
        end
        local count; count, status = numberField(src, "totalAmount", 0)
        if status then return nil, status end
        if count > 0 then
            sawPositiveSource = true
            local identity; identity, status = readSourceIdentity(candidate, src, allowIncomplete)
            if not identity then return nil, status end
            if not identity.creatureID then
                local player = ensurePlayer(candidate, identity.key, identity.name,
                    identity.class, identity.specIconID)
                player.deaths = player.deaths + count

                local recapID; recapID, status = numberField(src, "deathRecapID", 0)
                if status then
                    local ok; ok, status = acceptOptionalFailure(candidate, status, "death", nil, allowIncomplete)
                    if not ok then return nil, status end
                    recapID = 0
                end
                local record, recapStatus
                if recapID > 0 and ns.DeathTracker and ns.DeathTracker.BuildDeathRecordForArchive then
                    record, recapStatus = ns.DeathTracker:BuildDeathRecordForArchive(recapID, src)
                end
                if not record then
                    local ok; ok, status = acceptOptionalFailure(candidate,
                        recapStatus or G.MISSING, "death", nil, allowIncomplete)
                    if not ok then return nil, status end
                    record = incompleteDeathRecord(identity, recapID, recapStatus)
                elseif recapStatus ~= G.ACCESSIBLE then
                    local ok; ok, status = acceptOptionalFailure(candidate, recapStatus,
                        "death", record, allowIncomplete)
                    if not ok then return nil, status end
                elseif record._incomplete then
                    markIncomplete(candidate, "death", record)
                end
                record.playerGUID = identity.key or record.playerGUID
                record.playerName = identity.name or record.playerName
                record.playerClass = identity.class or record.playerClass
                record.isSelf = identity.isLocal and true or false
                record._deathCount = count
                table.insert(candidate.deathLog, record)
            end
        end
    end
    if totalDeaths > 0 and not sawPositiveSource then return nil, G.MISSING end
    return true
end

local function archiveEnemySources(candidate, selector, dmType, identity, entry, allowIncomplete)
    local sourceData, status = getSource(selector, dmType, identity.guid, identity.creatureID)
    if type(sourceData) == "nil" then
        return acceptOptionalFailure(candidate, status or G.MISSING, "enemySource", entry, allowIncomplete)
    end
    local spells; spells, status = G:ReadTableField(sourceData, "combatSpells")
    if status ~= G.ACCESSIBLE then
        return acceptOptionalFailure(candidate, status, "enemySource", entry, allowIncomplete)
    end
    local sourceMap = {}
    for _, sp in ipairs(spells) do
        if type(sp) ~= "table" or not G:IsTableAccessible(sp) then
            local inaccessible = type(sp) == "table" and G.SECRET or G.ERROR
            local ok; ok, status = acceptOptionalFailure(candidate, inaccessible,
                "enemySource", entry, allowIncomplete)
            if not ok then return nil, status end
        else
            local details; details, status = G:ReadTableField(sp, "combatSpellDetails")
            if status == G.ACCESSIBLE then
                local unitName; unitName, status = stringField(details, "unitName", nil)
                if status then
                    local ok; ok, status = acceptOptionalFailure(candidate, status,
                        "enemySource", entry, allowIncomplete)
                    if not ok then return nil, status end
                end
                local unitClass; unitClass, status = stringField(details, "unitClassFilename", nil)
                if status then
                    local ok; ok, status = acceptOptionalFailure(candidate, status,
                        "enemySource", entry, allowIncomplete)
                    if not ok then return nil, status end
                    unitClass = nil
                end
                local amount; amount, status = numberField(details, "amount", nil)
                if status then
                    local ok; ok, status = acceptOptionalFailure(candidate, status,
                        "enemySource", entry, allowIncomplete)
                    if not ok then return nil, status end
                end
                -- combatSpellDetails.amount is the only official attribution
                -- for this unitName.  Never assign the spell-wide totalAmount
                -- to a single source when Blizzard omitted the detail amount.
                if unitName and type(amount) == "number" and amount > 0 then
                    local row = sourceMap[unitName]
                    if not row then
                        row = {name = unitName, class = unitClass, amount = 0}
                        sourceMap[unitName] = row
                    end
                    row.amount = row.amount + amount
                end
            elseif status ~= G.MISSING then
                local ok; ok, status = acceptOptionalFailure(candidate, status,
                    "enemySource", entry, allowIncomplete)
                if not ok then return nil, status end
            else
                markIncomplete(candidate, "enemySource", entry)
            end
        end
    end
    for _, row in pairs(sourceMap) do table.insert(entry.sources, row) end
    table.sort(entry.sources, function(a, b) return a.amount > b.amount end)
    return true
end

local function archiveEnemyDamage(candidate, selector, allowIncomplete)
    local dmType = enum("EnemyDamageTaken")
    if type(dmType) == "nil" then return true end
    local session, sessionStatus = G:GetRawSession(selector.sessionType, selector.sessionID, dmType)
    if type(session) == "nil" then
        if sessionStatus == G.MISSING then candidate.totalEnemyDamageTaken = 0; return true end
        return nil, sessionStatus or G.ERROR
    end
    local sessionTotal, status = numberField(session, "totalAmount", 0)
    if status then return nil, status end
    candidate.totalEnemyDamageTaken = sessionTotal
    local sources; sources, status = G:ReadTableField(session, "combatSources")
    if status ~= G.ACCESSIBLE then
        if sessionTotal == 0 then return true end
        return nil, status
    end

    local sawPositiveSource = false
    for _, src in ipairs(sources) do
        if type(src) ~= "table" or not G:IsTableAccessible(src) then
            return nil, type(src) == "table" and G.SECRET or G.ERROR
        end
        local total; total, status = numberField(src, "totalAmount", 0)
        if status then return nil, status end
        if total > 0 then
            sawPositiveSource = true
            local identity; identity, status = readSourceIdentity(candidate, src, allowIncomplete)
            if not identity then return nil, status end
            if not identity.creatureID and not identity.name then
                return nil, identity._creatureStatus or identity._nameStatus or G.MISSING
            else
                local entry = {
                    creatureID = identity.creatureID, name = identity.name or "?",
                    total = total, perSec = identity.hasPerSec and identity.perSec or nil, sources = {},
                }
                local ok; ok, status = archiveEnemySources(candidate, selector, dmType,
                    identity, entry, allowIncomplete)
                if not ok then return nil, status end
                table.insert(candidate.enemyDamageTakenList, entry)
            end
        end
    end
    if sessionTotal > 0 and not sawPositiveSource then return nil, G.MISSING end
    table.sort(candidate.enemyDamageTakenList, function(a, b) return a.total > b.total end)
    return true
end

local function buildCandidate(selector, meta)
    meta = meta or {}
    local allowIncomplete = false
    local name, status = stringValue(meta.name, ns.L.COMBAT)
    if status then return nil, status end
    local duration; duration, status = numberValue(meta.duration, 0)
    if status then return nil, status end
    local candidate = {
        type = meta.type or "history", name = name or ns.L.COMBAT,
        duration = duration, startTime = meta.startTime or GetTime(), endTime = meta.endTime or GetTime(),
        isActive = false, players = {}, totalDamage = 0, totalHealing = 0,
        totalDamageTaken = 0, deathLog = {}, enemyDamageTakenList = {},
        _sessionID = selector.sessionID, _sessionIdx = meta.sessionIdx,
        _instanceTag = meta.instanceTag, _instanceDisplayName = meta.instanceDisplayName,
        _isBoss = meta.isBoss and true or false, encounterName = meta.encounterName,
        encounterID = meta.encounterID, difficultyID = meta.difficultyID, success = meta.success,
        _combatGeneration = meta.combatGeneration,
        _completedWallTime = meta.completedWallTime,
        _dataLoaded = true, _archiveGeneration = G._rawGeneration,
        _wasOutdoor = meta.wasOutdoor and true or false,
    }
    if status or meta._durationStatus then
        candidate._durationIncomplete = true
        candidate._durationUnknown = true
        candidate._detailsIncomplete = true
    end
    for _, def in ipairs(STAT_DEFS) do
        local ok, fieldStatus = archiveStat(candidate, selector, def, allowIncomplete)
        if not ok then return nil, fieldStatus end
    end
    local ok; ok, status = archiveDeaths(candidate, selector, allowIncomplete)
    if not ok then return nil, status end
    ok, status = archiveEnemyDamage(candidate, selector, allowIncomplete)
    if not ok then return nil, status end
    return candidate, G.ACCESSIBLE
end

function G:BuildSessionCandidate(sessionID, meta)
    if not self:IsAccessible(sessionID) then return nil, self.SECRET end
    if type(sessionID) == "nil" then return nil, self.MISSING end
    return buildCandidate({sessionID = sessionID}, meta)
end

function G:BuildOverallCandidate(meta)
    local st = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
    if st == nil then return nil, self.ERROR end
    meta = meta or {}
    if type(meta.duration) == "nil" then
        local duration, durationStatus = self:GetSessionDurationRaw(st)
        if durationStatus == self.ACCESSIBLE then
            meta.duration = duration
        else
            meta._durationStatus = durationStatus
            if durationStatus == self.SECRET or durationStatus == self.ERROR then
                return nil, durationStatus
            end
        end
    end
    return buildCandidate({sessionType = st}, meta)
end

function G:ApplyCandidateToSegment(candidate, segment)
    if not candidate or not segment then return false end
    local localID = segment._localID
    for key in pairs(segment) do segment[key] = nil end
    for key, value in pairs(candidate) do segment[key] = value end
    segment._localID = localID or (ns.Segments and ns.Segments:GenLocalID("arch"))
    return true
end

return G
