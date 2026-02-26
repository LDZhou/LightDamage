--[[
    LD Combat Stats v2.0 - DetailView.lua
    详情面板：技能细分 + 死亡事件详情
]]

local addonName, ns = ...
local L = ns.L

ns.FONT_MAIN = ns.FONT_MAIN or STANDARD_TEXT_FONT

local DV = {}
ns.DetailView = DV


local ROW_H  = 20
local ICON_W = 18

local ROW_BG = {
    {0.07, 0.07, 0.09, 0.92},
    {0.12, 0.12, 0.15, 0.92},
}
local BG_HEADER  = {0.04, 0.04, 0.08, 0.96}
local BG_SECTION = {0.05, 0.08, 0.13, 0.92}
local BG_FATAL   = {0.22, 0.03, 0.03, 0.96}

-- ============================================================
-- 面板创建
-- ============================================================
function DV:EnsureCreated()
    if self.frame then return end

    local f = CreateFrame("Frame", "LDStatsDetail", UIParent, "BackdropTemplate")
    f:SetSize(380, 420)
    f:SetFrameStrata("HIGH"); f:SetFrameLevel(20)
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    f:SetBackdropBorderColor(0.25, 0.25, 0.32, 0.9)

    if ns.UI and ns.UI.frame then
        f:SetPoint("BOTTOMLEFT", ns.UI.frame, "BOTTOMRIGHT", 4, 0)
    else
        f:SetPoint("CENTER")
    end

    -- 标题栏
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(24)
    tb:SetPoint("TOPLEFT", 1, -1); tb:SetPoint("TOPRIGHT", -1, -1)
    tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    local tbg = tb:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints()
    tbg:SetColorTexture(0.06, 0.06, 0.10, 1)
    self.titleBg = tbg  -- ★ 新增

    -- 返回按钮
    local back = CreateFrame("Button", nil, tb)
    back:SetSize(24, 24); back:SetPoint("LEFT", 2, 0)
    local bt = back:CreateFontString(nil, "OVERLAY")
    bt:SetFont(ns.FONT_MAIN, 14, "OUTLINE")
    bt:SetPoint("CENTER"); bt:SetText("←"); bt:SetTextColor(0.6, 0.6, 0.6)
    self.backText = bt  -- ★ 新增

    back:SetScript("OnClick", function() f:Hide() end)
    back:SetScript("OnEnter", function() bt:SetTextColor(1, 1, 1) end)
    back:SetScript("OnLeave", function() bt:SetTextColor(0.6, 0.6, 0.6) end)

    self.titleText = tb:CreateFontString(nil, "OVERLAY")
    self.titleText:SetFont(ns.FONT_MAIN, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", back, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", -28, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)
    self.titleText:SetTextColor(1, 1, 1)

    -- ★ 修复：✕ 在 ARHei.TTF 里没有字形会渲染成方块，改用 X
    local cb = CreateFrame("Button", nil, tb); cb:SetSize(20, 24); cb:SetPoint("RIGHT", -2, 0)
    local ct = cb:CreateFontString(nil, "OVERLAY")
    ct:SetFont(ns.FONT_MAIN, 12, "OUTLINE")
    ct:SetPoint("CENTER"); ct:SetText("X"); ct:SetTextColor(0.5, 0.5, 0.5)
    self.closeText = ct -- ★ 新增

    cb:SetScript("OnClick", function() f:Hide() end)
    cb:SetScript("OnEnter", function() ct:SetTextColor(1, 0.3, 0.3) end)
    cb:SetScript("OnLeave", function() ct:SetTextColor(0.5, 0.5, 0.5) end)

    -- ★ 修复：替换 UIPanelScrollFrameTemplate，改用自定义细滚动条
    local sc = CreateFrame("ScrollFrame", nil, f)
    sc:SetPoint("TOPLEFT",     tb,  "BOTTOMLEFT",  2,  -2)
    sc:SetPoint("BOTTOMRIGHT", f,   "BOTTOMRIGHT", -8,  4)

    local inner = CreateFrame("Frame", nil, sc)
    inner:SetSize(340, 1000)
    sc:SetScrollChild(inner)

    -- 自定义细滚动条（和主 UI 一致）
    local sb = CreateFrame("Slider", nil, sc)
    sb:SetWidth(3)
    sb:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",    0,  0)
    sb:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0,  0)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 0); sb:SetValue(0)

    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)

    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture()
    thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)

    sc:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * ROW_H * 3)))
    end)
    sb:SetScript("OnValueChanged", function(_, val)
        sc:SetVerticalScroll(val)
    end)

    self.frame      = f
    self.content    = inner
    self.scrollFrame = sc
    self.scrollBar  = sb
    self.rows       = {}
    tinsert(UISpecialFrames, "LDStatsDetail")
    f:Hide()
end

-- ============================================================
-- 应用动态外观主题
-- ============================================================
function DV:ApplyTheme()
    if not self.frame then return end
    local dbW = ns.db and ns.db.window or {}
    local dbD = ns.db and ns.db.display or {}
    
    -- 1. 同步背景颜色
    local bg = dbW.bgColor or {0.04, 0.04, 0.05, 0.90}
    self.frame:SetBackdropColor(unpack(bg))
    
    -- 2. 同步标题栏颜色 (ThemeColor)
    local tc = dbW.themeColor or {0.08, 0.08, 0.12, 1}
    self.titleBg:SetColorTexture(unpack(tc))
    
    -- 3. 同步字体与字号
    local font = dbD.font or ns.FONT_MAIN
    local fSize = dbD.fontSizeBase or 10
    local outline = dbD.fontOutline or "OUTLINE"
    
    if self.titleText then self.titleText:SetFont(font, fSize + 1, outline) end
    if self.backText then self.backText:SetFont(font, fSize + 4, outline) end
    if self.closeText then self.closeText:SetFont(font, fSize + 2, outline) end
    
    for _, r in ipairs(self.rows) do
        r.name:SetFont(font, fSize, outline)
        r.value:SetFont(font, fSize, outline)
    end
end
-- ============================================================
-- 滚动条高度更新
-- ============================================================
function DV:UpdateScroll(rowCount)
    local totalH = rowCount * (ROW_H + 1)
    self.content:SetHeight(math.max(10, totalH))

    local viewH    = self.scrollFrame:GetHeight()
    local maxScroll = math.max(0, totalH - viewH)
    self.scrollBar:SetMinMaxValues(0, maxScroll)

    if maxScroll > 0 then
        self.scrollBar:Show()
        self.content:SetWidth(self.scrollFrame:GetWidth() - 5)
    else
        self.scrollBar:Hide()
        self.scrollBar:SetValue(0)
        self.content:SetWidth(self.scrollFrame:GetWidth())
    end
end

-- ============================================================
-- 行管理
-- ============================================================
function DV:GetRow(idx)
    if self.rows[idx] then return self.rows[idx] end
    local r = {}

    r.frame = CreateFrame("Button", nil, self.content)
    r.frame:EnableMouse(true)
    r.frame:Hide()

    r.bg = r.frame:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(unpack(ROW_BG[(idx % 2) + 1]))

    r.fill = CreateFrame("StatusBar", nil, r.frame)
    r.fill:SetPoint("TOPLEFT"); r.fill:SetPoint("BOTTOMLEFT")
    r.fill:SetPoint("RIGHT")
    r.fill:SetMinMaxValues(0, 1); r.fill:SetValue(0)

    -- ★ 核心修复：创建一个专门用于放图标和文字的子框架，并强行拔高它的渲染层级
    r.textFrame = CreateFrame("Frame", nil, r.frame)
    r.textFrame:SetAllPoints()
    r.textFrame:SetFrameLevel(r.fill:GetFrameLevel() + 2)

    -- ★ 以下的 icon, name, value 统统挂载到新创建的 textFrame 上
    r.icon = r.textFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_W - 2, ICON_W - 2)
    r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:Hide()

    r.name = r.textFrame:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(ns.FONT_MAIN, 9, "OUTLINE")
    r.name:SetWidth(200)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.name:SetTextColor(1, 1, 1)

    r.value = r.textFrame:CreateFontString(nil, "OVERLAY")
    r.value:SetFont(ns.FONT_MAIN, 9, "OUTLINE")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.value:SetTextColor(1, 1, 1)

    -- 悬停的高亮材质可以留在原底板上
    r.hl = r.frame:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)

    self.rows[idx] = r
    return r
end

function DV:ClearRows()
    for _, r in ipairs(self.rows) do
        r.frame:Hide()
        r.icon:Hide()
        r.fill:SetMinMaxValues(0, 1)
        r.fill:SetValue(0)
        r.frame:SetScript("OnEnter", nil)
        r.frame:SetScript("OnLeave", nil)
    end
end

function DV:PlaceRow(idx, yOff, h, bgOverride)
    local r = self:GetRow(idx)
    r.frame:ClearAllPoints()
    r.frame:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0,  yOff)
    r.frame:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -2, yOff)
    r.frame:SetHeight(h or ROW_H)
    r.icon:Hide()
    r.fill:SetMinMaxValues(0, 1)
    r.fill:SetValue(0)

    local bgc = bgOverride or ROW_BG[(idx % 2) + 1]
    r.bg:SetColorTexture(unpack(bgc))

    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", 6, 0)

    r.frame:Show()
    return r
end

local function setNameWithIcon(r, iconTex, text)
    if iconTex then
        r.icon:SetTexture(iconTex)
        r.icon:Show()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", ICON_W + 4, 0)
    else
        r.icon:Hide()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", 6, 0)
    end
    r.name:SetText(text)
end

local function GetSpellIcon(spellID)
    if not spellID or spellID == 0 then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local t = C_Spell.GetSpellTexture(spellID); if t then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, spellID)
        if ok and t then return t end
    end
    return nil
end

-- ============================================================
-- ★ 从设置里获取条的材质和透明度（跟主界面统一）
-- ============================================================
local function getBarStyle()
    local db = ns.db and ns.db.display or {}
    return db.barTexture or "Interface\\TargetingFrame\\UI-StatusBar",
           db.barAlpha   or 0.85
end

-- ============================================================
-- 技能列表渲染
-- ============================================================
function DV:RenderSpellList(name, class, mode, spells, dur, titleSuffix)
    self:EnsureCreated()
    self:ApplyTheme()
    self:ClearRows()

    local ch = ns:GetClassHex(class)
    local mn = ns.MODE_NAMES[mode] or mode
    local suffix = titleSuffix or ""
    self.titleText:SetFormattedText(L["%s%s|r 的%s细分%s"], ch, ns:DisplayName(name), mn, suffix) -- ★ 添加DisplayName

    if #spells == 0 then
        local r = self:PlaceRow(1, 0, ROW_H)
        r.name:SetText(L["|cff555555暂无技能数据|r"])
        r.value:SetText("")
        self:UpdateScroll(2)
        self.frame:Show()
        return
    end

    local maxV = spells[1] and (spells[1].secretAmt or spells[1].value) or 0
    local cw      = self.content:GetWidth()
    local texPath, alpha = getBarStyle()

    for i, sp in ipairs(spells) do
        local y = -((i - 1) * (ROW_H + 1))
        local r = self:PlaceRow(i, y)

        r.fill:SetStatusBarTexture(texPath)
        r.fill:SetMinMaxValues(0, maxV)
        r.fill:SetValue(sp.secretAmt or sp.value)

        -- ★ 颜色：魔法学派颜色，透明度跟主界面统一
        local sc2 = ns.SCHOOL_COLORS and ns.SCHOOL_COLORS[sp.school] or {0.5, 0.5, 0.7}
        if sp.isPet then sc2 = {0.28, 0.65, 0.28} end
        r.fill:SetStatusBarColor(sc2[1], sc2[2], sc2[3], alpha)

        local sn = sp.name or "?"
        if #sn > 26 then sn = sn:sub(1, 25) .. "…" end
        local nc = sp.isPet and "|cff55bb55" or "|cffffffff"
        
        -- ▼▼▼ 新增：可规避伤害高亮逻辑 ▼▼▼
        if sp.isAvoidable then
            -- 把背景板改成明显的暗黄色 / 警示色
            r.bg:SetColorTexture(0.35, 0.25, 0.05, 0.85)
            -- 名字前面加上醒目的 [规避] 标签，并把字体标黄
            nc = "|cffffcc00[规避] "
        end
        -- ▲▲▲ 新增结束 ▲▲▲
        
        setNameWithIcon(r, GetSpellIcon(sp.spellID), nc .. sn .. "|r")

        local isCount = (mode == "interrupts" or mode == "dispels")
        local valStr
        if sp.secretAmt then
            -- 使用暴雪指定的 AbbreviateNumbers 解析 Secret Value
            valStr = AbbreviateNumbers(sp.secretAmt)
        elseif isCount then
            valStr = string.format(L["|cffffff00%d次|r"], sp.value)
        elseif dur and dur > 0 and ns.MODE_UNITS[mode] then
            valStr = string.format("%s(%s)", ns:FormatNumber(sp.value / dur), ns:FormatNumber(sp.value))
        else
            valStr = ns:FormatNumber(sp.value)
        end
        
        -- Secret Value 无法计算占比，显示为 --%
        local pctStr = sp.secretAmt and "--%" or string.format("%.0f%%", sp.percent or 0)
        r.value:SetText(valStr .. " |cffaaaaaa" .. pctStr .. "|r")

        local sp_c = sp
        r.frame:SetScript("OnEnter", function(fw)
            GameTooltip:SetOwner(fw, "ANCHOR_RIGHT")
            if sp_c.spellID and sp_c.spellID > 0 then
                pcall(function() GameTooltip:SetSpellByID(sp_c.spellID) end)
            else
                GameTooltip:AddLine(sp_c.name or "?")
            end
            GameTooltip:AddLine(" ")
            
            -- Tooltip 内的安全渲染
            local amtStr = sp_c.secretAmt and AbbreviateNumbers(sp_c.secretAmt) or ns:FormatNumber(sp_c.value)
            GameTooltip:AddDoubleLine(L["总量"], amtStr, 0.7, 0.7, 0.7, 1, 1, 1)
            
            if not sp_c.secretAmt and dur and dur > 0 and ns.MODE_UNITS[mode] then
                GameTooltip:AddDoubleLine(L["每秒"], string.format("%.1f", sp_c.value / dur), 0.7, 0.7, 0.7, 1, 0.85, 0)
            end

            if (sp_c.overhealing or 0) > 0 then
                GameTooltip:AddDoubleLine(L["过量治疗"], ns:FormatNumber(sp_c.overhealing), 0.7, 0.7, 0.7, 0.8, 0.4, 0.4)
            end
            GameTooltip:Show()
        end)
        r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    self:UpdateScroll(#spells)
    self.frame:Show()
end

-- ============================================================
-- 技能细分（脱战后）
-- ============================================================
function DV:ShowSpellBreakdown(guid, name, class, mode, seg)
    local displayMode = (mode == "deaths") and "damage" or mode
    local seg = seg or (ns.Segments and ns.Segments:GetViewSegment())
    local dur    = ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or 0
    local spells = self:GetSpellBreakdownExt(seg, guid, displayMode)
    self:RenderSpellList(name, class, displayMode, spells, dur, "")
end

-- ============================================================
-- 技能细分（战斗中实时 API）
-- ============================================================
function DV:ShowSpellBreakdownFromAPI(guid, name, class, mode, sessionType)
    if mode ~= "damage" and mode ~= "healing" then return end

    local dmType = (mode == "healing") and Enum.DamageMeterType.HealingDone or Enum.DamageMeterType.DamageDone

    -- 1. 确认是否为玩家自身
    local isSelf = false
    pcall(function()
        if guid == UnitGUID("player") or (type(name)=="string" and string.find(name, UnitName("player"), 1, true)) then
            isSelf = true
        end
    end)

    -- 2. 直接使用官方 API 获取
    local queryGuid = isSelf and UnitGUID("player") or guid
    local srcData
    local ok, data = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType or Enum.DamageMeterSessionType.Current, dmType, queryGuid)
    if ok and data and data.combatSpells then srcData = data end

    -- 3. 数据为空，走保护提示
    if not srcData or not srcData.combatSpells or #srcData.combatSpells == 0 then
        if ns.state.inCombat then
            self:ShowCombatLocked(name)
        else
            self:ShowSpellBreakdown(guid, name, class, mode)
        end
        return
    end

    -- 4. 无需排序，原样渲染暴雪提供的数据
    local spells = {}
    local isSecret = false

    for _, sp in ipairs(srcData.combatSpells) do
        local amt = sp.totalAmount
        if amt then
            local isSec = issecretvalue and issecretvalue(amt)
            if isSec then isSecret = true end
            
            local spellName = ""
            if C_Spell and C_Spell.GetSpellName then spellName = C_Spell.GetSpellName(sp.spellID) or "" end
            if spellName == "" then spellName = "spell:" .. sp.spellID end

            table.insert(spells, {
                spellID     = sp.spellID,
                name        = spellName,
                school      = sp.school or 1,
                value       = isSec and 0 or amt,
                secretAmt   = amt,  -- 秘密数值交由底层 StatusBar 处理
                percent     = 0,
                isPet       = false,
                isAvoidable = sp.isAvoidable,
            })
        end
    end

    local dur = 0
    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        dur = GetTime() - ns.state.combatStartTime
    end

    local suffix = isSecret and " |cffaaaaaa[实时加密]|r" or " |cff00ccff[实时]|r"
    self:RenderSpellList(name, class, mode, spells, dur, suffix)
end

-- ============================================================
-- 战斗中队友数据受保护提示
-- ============================================================
function DV:ShowCombatLocked(safeName)
    self:EnsureCreated()
    self:ClearRows()
    self.titleText:SetFormattedText(L["%s 的技能细分"], ns:DisplayName(safeName) or L["未知"]) -- ★ 添加DisplayName
    local r = self:PlaceRow(1, 0, ROW_H * 2)
    
    r.name:SetText("|cffaaaaaa[API限制，请脱战后查看")
    
    r.name:SetWidth(300)
    r.value:SetText("")
    self:UpdateScroll(3)
    self.frame:Show()
end

-- ============================================================
-- 获取技能细分数据（从数据结构）
-- ============================================================
function DV:GetSpellBreakdownExt(seg, guid, mode)
    if not seg or not guid then return {} end
    local pd = seg.players[guid]
    if not pd then return {} end

    if mode == "damage" or mode == "healing" then
        return ns.Analysis and ns.Analysis:GetSpellBreakdown(seg, guid, mode) or {}
    end

    if mode == "damageTaken" then
        if pd.damageTakenSpells and next(pd.damageTakenSpells) then
            local result = {}
            for spellID, sd in pairs(pd.damageTakenSpells) do
                if (sd.damage or 0) > 0 then
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sd.name or ("spell:" .. spellID),
                        school      = sd.school or 1,
                        value       = sd.damage,
                        hits        = sd.hits or 1,
                        crits       = sd.crits or 0,
                        maxHit      = sd.maxHit or 0,
                        minHit      = (sd.minHit and sd.minHit ~= 999999999) and sd.minHit or 0,
                        critPercent = (sd.hits and sd.hits > 0) and (sd.crits / sd.hits * 100) or 0,
                        isAvoidable = sd.isAvoidable,
                    })
                end
            end
            table.sort(result, function(a, b) return a.value > b.value end)
            local tot = pd.damageTaken or 0
            for _, r2 in ipairs(result) do
                r2.percent = tot > 0 and (r2.value / tot * 100) or 0
            end
            return result
        else
            if (pd.damageTaken or 0) > 0 then
                return {{ spellID=0, name=L["承伤合计"], school=1, value=pd.damageTaken,
                    hits=0, crits=0, maxHit=0, minHit=0, critPercent=0, percent=100 }}
            end
        end
    end

    if mode == "interrupts" or mode == "dispels" then
        local spellTable = (mode == "interrupts") and pd.interruptSpells or pd.dispelSpells
        local totalVal   = (mode == "interrupts") and pd.interrupts or pd.dispels
        
        -- 如果有具体的技能明细记录，则遍历显示
        if spellTable and next(spellTable) then
            local result = {}
            for spellID, sd in pairs(spellTable) do
                local amt = sd.damage or sd.hits or 0
                if amt > 0 then
                    local sName = sd.name or ("spell:" .. spellID)
                    
                    -- ★ 核心修改：CC 触发的通用打断
                    if mode == "interrupts" and spellID == 32747 then
                        sName = L["控制技能打断"]
                    end
                    
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sName,
                        school      = sd.school or 1,
                        value       = amt,
                        hits        = amt,
                        crits       = 0,
                        maxHit      = 0,
                        minHit      = 0,
                        critPercent = 0,
                    })
                end
            end
            
            table.sort(result, function(a, b) return a.value > b.value end)
            local tot = totalVal or 0
            for _, r2 in ipairs(result) do
                r2.percent = tot > 0 and (r2.value / tot * 100) or 0
            end
            return result
        else
            -- 兜底逻辑：如果底层没有拿到技能明细，但总次数大于0，回退显示合计
            if (totalVal or 0) > 0 then
                local fallbackName = (mode == "interrupts") and L["打断合计"] or L["驱散合计"]
                return {{ spellID=0, name=fallbackName, school=1, value=totalVal,
                    hits=0, crits=0, maxHit=0, minHit=0, critPercent=0, percent=100 }}
            end
        end
    end

    return {}
end

-- ============================================================
-- 死亡事件详情
-- ============================================================
function DV:ShowDeathDetail(death)
    self:EnsureCreated()
    self:ApplyTheme()
    self:ClearRows()
    if not death then return end

    local ch      = ns:GetClassHex(death.playerClass)
    local selfTag = death.isSelf and " |cffff8888[自己]|r" or ""
    self.titleText:SetText(ch .. ns:DisplayName(death.playerName or "?") .. "|r" .. selfTag .. L[" 的死亡详情"]) -- ★ 玩家名

    local events     = death.events or {}
    local evReversed = {}
    for i = #events, 1, -1 do
        table.insert(evReversed, events[i])
    end

    local texPath, alpha = getBarStyle()
    local cw        = self.content:GetWidth()
    local ri        = 0
    local deathTime = events[#events] and events[#events].time or GetTime()

    -- 致命一击行
    ri = ri + 1
    local hr = self:PlaceRow(ri, 0, ROW_H + 4, BG_FATAL)
    hr.fill:SetStatusBarTexture(texPath)
    hr.fill:SetMinMaxValues(0, 1)
    hr.fill:SetValue(1)
    hr.fill:SetStatusBarColor(0.70, 0.04, 0.04, 0.55)
    setNameWithIcon(hr,
        death.killingAbility ~= "?" and GetSpellIcon(
            (evReversed[1] and not evReversed[1].isHeal) and evReversed[1].spellID or 0
        ) or nil,
        L["|cffff3333[致命]: |r"] .. (death.killingAbility or "?")
    )
    hr.value:SetText(L["|cffaaaaaa击杀者: |r"] .. (death.killerName ~= "" and ns:DisplayName(death.killerName) or L["未知"])) -- ★ 击杀者名

    -- 分割线
    ri = ri + 1
    local sep = self:PlaceRow(ri, -((ri - 1) * (ROW_H + 1)), 15, BG_SECTION)
    sep.fill:SetMinMaxValues(0, 1)
    sep.fill:SetValue(0)
    sep.name:SetText(L["|cff4499cc— 死亡前事件（近 → 远）|r"])
    sep.value:SetText(string.format(L["|cff666666%d条|r"], #evReversed))

    if #evReversed == 0 then
        ri = ri + 1
        local er = self:PlaceRow(ri, -((ri - 1) * (ROW_H + 1)), ROW_H)
        er.name:SetText(L["|cff444444暂无事件数据（12.0副本内CLEU受限）|r"])
        er.value:SetText("")
    end

    for idx, ev in ipairs(evReversed) do
        ri = ri + 1
        local yOff = -((ri - 1) * (ROW_H + 1))
        local r    = self:PlaceRow(ri, yOff)
        local isFatal = (idx == 1 and not ev.isHeal)

        local hpPct = math.min(1, math.max(0, (ev.hpPercent or 0) / 100))
        r.fill:SetStatusBarTexture(texPath)
        r.fill:SetMinMaxValues(0, 1)
        r.fill:SetValue(hpPct)

        if ev.isHeal then
            r.fill:SetStatusBarColor(0.10, 0.50, 0.10, alpha)
            r.bg:SetColorTexture(unpack(ROW_BG[(ri % 2) + 1]))
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cff44ee44+%s|r %s",
                    ns:FormatNumber(math.abs(ev.amount)), ev.spellName or L["治疗"]))
        elseif isFatal then
            r.bg:SetColorTexture(0.20, 0.03, 0.03, 0.96)
            r.fill:SetStatusBarColor(0.80, 0.04, 0.04, alpha)
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cffff1111-%s|r |cffff7755%s|r",
                    ns:FormatNumber(ev.amount), ev.spellName or "?"))
        else
            r.fill:SetStatusBarColor(0.60, 0.08, 0.08, alpha)
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cffff9977-%s|r %s",
                    ns:FormatNumber(ev.amount), ev.spellName or "?"))
        end

        local td = deathTime - (ev.time or deathTime)
        local timeStr
        if td < 0.05 then
            timeStr = L["|cffff3333死亡|r"]
        else
            timeStr = string.format(L["|cff888888%.1fs前|r"], td)
        end
        local hpColor = ev.isHeal and "44ee44" or (hpPct < 0.15 and "ff4444" or "bbbbbb")
        r.value:SetText(string.format("|cff%s%.0f%%|r %s", hpColor, ev.hpPercent or 0, timeStr))

        local ev_c    = ev
        local td_c    = td
        local maxHP_c = death.maxHP or 0
        r.frame:SetScript("OnEnter", function(fw)
            GameTooltip:SetOwner(fw, "ANCHOR_RIGHT")
            if ev_c.spellID and ev_c.spellID > 0 then
                pcall(function() GameTooltip:SetSpellByID(ev_c.spellID) end)
            else
                GameTooltip:AddLine(ev_c.spellName or "?")
            end
            GameTooltip:AddLine(" ")
            if ev_c.isHeal then
                GameTooltip:AddDoubleLine(L["治疗量"],
                    ns:FormatNumber(math.abs(ev_c.amount)), 0.7, 0.7, 0.7, 0.3, 1, 0.3)
            else
                GameTooltip:AddDoubleLine(L["伤害量"],
                    ns:FormatNumber(ev_c.amount), 0.7, 0.7, 0.7, 1, 0.3, 0.3)
                if (ev_c.overkill or 0) > 0 then
                    GameTooltip:AddDoubleLine(L["过量击杀"],
                        ns:FormatNumber(ev_c.overkill), 0.7, 0.7, 0.7, 1, 0.5, 0)
                end
            end
            if ev_c.srcName and ev_c.srcName ~= "" then
                GameTooltip:AddDoubleLine(L["来源"], ns:DisplayName(ev_c.srcName), 0.7, 0.7, 0.7, 1, 1, 1) -- ★ 来源名
            end
            GameTooltip:AddDoubleLine(L["剩余生命"],
                string.format("%s / %s (%.0f%%)",
                    ns:FormatNumber(ev_c.hp or 0),
                    ns:FormatNumber(maxHP_c),
                    ev_c.hpPercent or 0),
                0.7, 0.7, 0.7, 1, 1, 1)
            if td_c >= 0.05 then
                GameTooltip:AddDoubleLine(L["距死亡"], string.format(L["%.1f 秒"], td_c), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- 底部汇总行
    ri = ri + 1
    local yBot = -((ri - 1) * (ROW_H + 1))
    local tr   = self:PlaceRow(ri, yBot, ROW_H + 4, BG_HEADER)
    tr.fill:SetStatusBarTexture(texPath)
    tr.fill:SetMinMaxValues(0, 1)
    tr.fill:SetValue(1)
    tr.fill:SetStatusBarColor(0.04, 0.04, 0.08, 0.90)
    tr.name:SetText(string.format(
        L["受伤: |cffff9966%s|r"],
        ns:FormatNumber(death.totalDamageTaken or 0)))
    local spanStr = (death.timeSpan and death.timeSpan > 0)
        and string.format(L["|cff888888跨度 %.1fs|r"], death.timeSpan) or ""
    tr.value:SetText(spanStr)

    self:UpdateScroll(ri + 1)
    self.frame:Show()
end

-- ============================================================
-- 接口
-- ============================================================
function DV:IsVisible() return self.frame and self.frame:IsShown() end
function DV:Refresh()
    if self.frame and self.frame:IsShown() then
        self:ApplyTheme()
    end
end