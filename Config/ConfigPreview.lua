-- Full-screen, hard-isolated preview controller.
local addonName,ns=...
local L=ns.L
local Config=ns.Config

local SCENES={
 {id="mplus",key="SCENE_MPLUS"},{id="raid",key="SCENE_RAID"},{id="dungeon",key="SCENE_DUNGEON"},
 {id="arena",key="SCENE_ARENA"},{id="battleground",key="SCENE_BATTLEGROUND"},{id="outdoor",key="SCENE_OUTDOOR"},
}
local DATASETS={{id="normal",key="PREVIEW_NORMAL"},{id="empty",key="PREVIEW_EMPTY"},{id="single",key="PREVIEW_SINGLE"},{id="long",key="PREVIEW_LONG"}}

local function button(self,parent,w,text,click)
 local b=CreateFrame("Button",nil,parent); b:SetSize(w,24); self:FillBg(b,.08,.12,.18,1); self:CreateBorder(b,.2,.45,.7,1)
 local t=b:CreateFontString(nil,"OVERLAY"); t:SetFont(STANDARD_TEXT_FONT,10,"OUTLINE"); t:SetPoint("LEFT",3,0); t:SetPoint("RIGHT",-3,0); t:SetJustifyH("CENTER"); t:SetWordWrap(false); t:SetText(text); b._text=t
 b:SetScript("OnClick",click); return b
end

function Config:BuildSceneSwitcher()
 if self._previewOverlay then return end
 local mask=CreateFrame("Frame","LightDamagePreviewOverlay",UIParent,"BackdropTemplate")
 mask:SetAllPoints(); mask:SetFrameStrata("FULLSCREEN"); mask:SetFrameLevel(500); mask:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); mask:SetBackdropColor(0,0,0,.55); mask:EnableMouse(true); mask:EnableKeyboard(true); mask:SetPropagateKeyboardInput(true); mask:Hide()
 mask:SetScript("OnKeyDown",function(frame,key) if key=="ESCAPE" then frame:SetPropagateKeyboardInput(false); self:ClosePreview(); C_Timer.After(0,function() frame:SetPropagateKeyboardInput(true) end) end end); self._previewOverlay=mask
 local bar=CreateFrame("Frame",nil,mask,"BackdropTemplate"); bar:SetSize(730,60); bar:SetPoint("TOP",UIParent,"TOP",0,-24); bar:SetFrameStrata("FULLSCREEN_DIALOG"); bar:SetFrameLevel(900); bar:SetScale(ns.db and ns.db.window and ns.db.window.configScale or 1); bar:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); bar:SetBackdropColor(.04,.04,.06,.98); self:CreateBorder(bar,.2,.5,.8,1); self._pvSwitcher=bar
 local title=bar:CreateFontString(nil,"OVERLAY"); title:SetFont(STANDARD_TEXT_FONT,11,"OUTLINE"); title:SetPoint("LEFT",10,0); title:SetWidth(112); title:SetJustifyH("LEFT"); self._pvTitle=title
 self._pvSceneBtns={}; local x=124
 for _,s in ipairs(SCENES) do local sceneId=s.id; local b=button(self,bar,66,L[s.key],function() self:ApplyPreviewScene(sceneId) end); b:SetPoint("LEFT",bar,"LEFT",x,0); b._scene=sceneId; b._sceneKey=s.key; self._pvSceneBtns[#self._pvSceneBtns+1]=b; x=x+69 end
 local sceneNote=bar:CreateFontString(nil,"OVERLAY"); sceneNote:SetFont(STANDARD_TEXT_FONT,9); sceneNote:SetPoint("BOTTOMLEFT",bar,"BOTTOMLEFT",124,5); sceneNote:SetWidth(414); sceneNote:SetJustifyH("CENTER"); sceneNote:SetWordWrap(false); sceneNote:SetText(L.PREVIEW_SCENE_GEOMETRY_DESC); sceneNote:SetTextColor(.58,.65,.72); self._pvSceneNote=sceneNote
 self._pvDataBtn=button(self,bar,84,L.PREVIEW_NORMAL,function() self:CyclePreviewDataset() end); self._pvDataBtn:SetPoint("RIGHT",bar,"RIGHT",-76,0)
 local exit=button(self,bar,62,L.EXIT_PREVIEW,function() self:ClosePreview() end); exit:SetPoint("RIGHT",bar,"RIGHT",-8,0)
end

function Config:SetPreviewAuxiliaryLayers(active)
 if ns.DetailView and ns.DetailView.SetPreviewLayer then ns.DetailView:SetPreviewLayer(active) end
 if ns.HistoryList and ns.HistoryList.SetPreviewLayer then ns.HistoryList:SetPreviewLayer(active) end
end

function Config:TogglePreview()
 if self._previewActive then self:ClosePreview() else self:OpenPreview() end
end

function Config:OpenPreview()
 if self._previewActive then return end
 if ns.state.inCombat or InCombatLockdown() then print("|cff00ccff[Light Damage]|r "..(L.PREVIEW_DISABLED_IN_COMBAT or "Preview is unavailable during combat.")); return end
 if not ns.UI then return end; ns.UI:EnsureCreated(); self:BuildSceneSwitcher()
 self._previewActive=true; self._previewDataset="normal"; self._previewModel=ns.PreviewModel:New("normal")
 self._previewActualScene=ns.state.sceneKey or "outdoor"; self._previewWasConfigShown=self.panel and self.panel:IsShown(); self._previewWasUIShown=ns.UI.frame:IsShown(); self._previewWasCollapsed=ns.UI._collapsed
 self._previewOldStrata=ns.UI.frame:GetFrameStrata(); self._previewOldLevel=ns.UI.frame:GetFrameLevel()
 self._previewOldResizeLevel=ns.UI.resizeHandle and ns.UI.resizeHandle:GetFrameLevel() or nil
 if self.panel then self._previewOldConfigStrata=self.panel:GetFrameStrata(); self._previewOldConfigLevel=self.panel:GetFrameLevel() end
 if ns.HistoryList then ns.HistoryList:Hide() end
 if ns.DetailView and ns.DetailView.frame then ns.DetailView.frame:Hide(); ns.DetailView._lastRenderArgs=nil end
 if ns.UI._collapsed then ns.UI:ToggleCollapse(false,true) end
 ns.UI.frame:SetFrameStrata("FULLSCREEN"); ns.UI.frame:SetFrameLevel(650); ns.UI.frame:SetAlpha(ns.db.window.alpha or .92); ns.UI.frame:Show()
 if ns.UI.resizeHandle then ns.UI.resizeHandle:SetFrameLevel(665) end
 ns.UI._previewNoFade=true
 self._previewOverlay:Show()
 -- Keep settings usable above the preview mask so every change can be
 -- observed immediately without entering or leaving preview again.
 if self.panel then self.panel:SetFrameStrata("FULLSCREEN_DIALOG"); self.panel:SetFrameLevel(800); self.panel:Show() end
 self:SetPreviewAuxiliaryLayers(true)
    ns.UI._previewContext={sceneKey=self._previewActualScene,model=self._previewModel,displayMode="overview"}
 self._pvTitle:SetWidth(112)
 self._pvTitle:SetText(L.PREVIEW)
 for _,b in ipairs(self._pvSceneBtns) do b._text:SetText(L[b._sceneKey]); b:Show() end
 self:ApplyPreviewScene(self._previewActualScene)
 self:RefreshPreviewDatasetButton(); ns.UI:ApplyFadeAlpha(false,false)
end

function Config:ClosePreview(fromCombat)
 if not self._previewActive then return end
 if ns.UI and ns.UI.CloseOtherTabMenu then ns.UI:CloseOtherTabMenu() end
 if ns.HistoryList then ns.HistoryList:Hide() end
 if ns.DetailView and ns.DetailView.frame then ns.DetailView.frame:Hide(); ns.DetailView._lastRenderArgs=nil end
 self:SetPreviewAuxiliaryLayers(false)
 ns.UI._previewContext=nil; ns.UI._previewNoFade=nil; self._previewActive=false
 self._previewOverlay:Hide(); ns.UI.frame:SetFrameStrata(self._previewOldStrata or "MEDIUM"); ns.UI.frame:SetFrameLevel(self._previewOldLevel or 10); ns.UI.frame:SetAlpha(ns.db.window.alpha or .92)
 if self.panel then self.panel:SetFrameStrata(self._previewOldConfigStrata or "DIALOG"); self.panel:SetFrameLevel(self._previewOldConfigLevel or 100) end
 if ns.UI.resizeHandle then ns.UI.resizeHandle:SetFrameLevel(self._previewOldResizeLevel or ((self._previewOldLevel or 10)+15)) end
 ns.UI:ApplySceneWorkspace(ns.state.sceneKey or self._previewActualScene or "outdoor")
 if not self._previewWasUIShown then ns.UI.frame:Hide() end
 if self._previewWasCollapsed and not fromCombat then ns.UI:ToggleCollapse(true,true) end
 if not self._previewWasConfigShown and self.panel and self.panel:IsShown() then self.panel:Hide() end
 self._previewModel=nil
 if ns.Analysis then ns.Analysis:InvalidateCache() end
 ns.UI:CheckAutoFade(true)
 if fromCombat then print("|cff00ccff[Light Damage]|r "..(L.PREVIEW_EXITED_FOR_COMBAT or "Preview closed because combat started.")) end
end

function Config:ApplyPreviewScene(scene)
 if not self._previewActive then return end
 ns.UI._previewContext.sceneKey=scene
 for _,b in ipairs(self._pvSceneBtns) do b._text:SetTextColor(b._scene==scene and 0 or .7,b._scene==scene and .85 or .7,b._scene==scene and 1 or .7) end
 ns.UI:ApplySceneWorkspace(scene)
end

function Config:CyclePreviewDataset()
 local order={"normal","empty","single","long"}; local i=1; for n,v in ipairs(order) do if v==self._previewDataset then i=n break end end
 self._previewDataset=order[(i%#order)+1]; self._previewModel:SetDataset(self._previewDataset); if ns.DetailView and ns.DetailView.frame then ns.DetailView.frame:Hide() end
 self:RefreshPreviewDatasetButton(); ns.UI:Refresh()
end

function Config:RefreshPreviewDatasetButton()
 if not self._pvDataBtn then return end
 for _,d in ipairs(DATASETS) do if d.id==self._previewDataset then self._pvDataBtn._text:SetText(L[d.key]); break end end
end

function Config:RefreshPreviewTheme() if ns.UI then ns.UI:ApplyTheme() end end
function Config:UpdatePreviewScene(scene) self:ApplyPreviewScene(scene) end
