-- Independent mock-data model used by the real renderer during preview.
local addonName, ns = ...

local PreviewModel={}
PreviewModel.__index=PreviewModel
ns.PreviewModel=PreviewModel

local NORMAL={
 {"Arcsmith","MAGE",14200000,320000,2800000,0,8,3}, {"Ironhide","WARRIOR",12800000,180000,3200000,1,5,1},
 {"Thornwood","DRUID",11500000,9800000,1200000,0,2,4}, {"Voidweaver","WARLOCK",10900000,420000,1900000,0,3,1},
 {"Swiftbolt","HUNTER",9800000,280000,2100000,2,3,0}, {"Dawnstrike","PALADIN",8600000,8200000,1800000,0,6,5},
 {"Frostmantle","DEATHKNIGHT",7900000,150000,4100000,1,2,0}, {"Embercrest","ROGUE",7200000,200000,1600000,0,9,0},
 {"Silvermist","PRIEST",5100000,12400000,900000,4,1,8}, {"Stonehowl","SHAMAN",5800000,6800000,1500000,0,4,2},
}

local LONG_NAMES={
 "ExtraordinarilyLongArcaneCharacterName", "UnbreakableTitaniumVanguardChampion",
 "AncientEvergreenRestorationSpecialist", "TransdimensionalVoidweavingSorcerer",
 "LegendaryBeastmasterOfTheWildFrontier", "RadiantDawnforgedCrusaderCommander",
 "DeathlessRuneboundFrostWarden", "UncatchableShadowbladeAssassinationExpert",
 "CelestialLightweavingHighPriest", "StormcallingElementalBattleSage",
}

local function rowsFor(kind)
 if kind=="empty" then return {} end
 if kind=="single" then return {{"Solo Player","MAGE",2850000,420000,510000,0,2,1}} end
 if kind=="long" then
  local out=CopyTable(NORMAL)
  for i,name in ipairs(LONG_NAMES) do out[i][1]=name end
  return out
 end
 return NORMAL
end

local function makeSpell(id,name,amount,hits,avoidable)
 local sp=ns.Segments:NewSpellData(id,name,1); sp.damage=amount; sp.healing=amount; sp.hits=hits; sp.crits=math.floor(hits/3); sp.isAvoidable=avoidable
 return sp
end

local function makeSegment(name,duration,rows,mult,kind)
 local seg=ns.Segments:NewSegment("history",name); seg.isActive=false; seg.duration=duration; seg._dataLoaded=true; seg._localID="preview_"..name
 local long=kind=="long"
 local strikeName=long and "ExtraordinarilyLongPreviewStrikeAbilityName" or "Preview Strike"
 local burstName=long and "OverwhelminglyLongPreviewBurstAbilityName" or "Preview Burst"
 local avoidableName=long and "UnnecessarilyLongAvoidableFlameAbilityName" or "Avoidable Flame"
 local impactName=long and "CatastrophicallyHeavyImpactAbilityWithLongName" or "Heavy Impact"
 local interruptName=long and "ExceptionallyLongSpellLockInterruptName" or "Spell Lock"
 local dispelName=long and "RemarkablyLongPurificationDispelName" or "Purify"
 local td,th,tt=0,0,0
 for i,r in ipairs(rows) do
  local guid="Preview-"..i; local p=ns.Segments:NewPlayerData(guid,r[1],r[2]); local m=mult or 1
  p.damage=math.floor(r[3]*m); p.healing=math.floor(r[4]*m); p.damageTaken=math.floor(r[5]*m)
  p.deaths=r[6]; p.interrupts=r[7]; p.dispels=r[8]; p.activeTime=duration
  p.spells[1000+i]=makeSpell(1000+i,strikeName,math.floor(p.damage*.62),37,false)
  p.spells[2000+i]=makeSpell(2000+i,burstName,math.floor(p.damage*.38),12,false)
  p.damageTakenSpells[3000+i]=makeSpell(3000+i,avoidableName,math.floor(p.damageTaken*.45),8,true)
  p.damageTakenSpells[4000+i]=makeSpell(4000+i,impactName,math.floor(p.damageTaken*.55),15,false)
  p.interruptSpells[5000+i]=makeSpell(5000+i,interruptName,p.interrupts,p.interrupts,false)
  p.dispelSpells[6000+i]=makeSpell(6000+i,dispelName,p.dispels,p.dispels,false)
  seg.players[guid]=p; td=td+p.damage; th=th+p.healing; tt=tt+p.damageTaken
 end
 seg.totalDamage=td; seg.totalHealing=th; seg.totalDamageTaken=tt
 if #rows>0 then
  seg.deathLog={{playerName=rows[math.min(2,#rows)][1],playerGUID="Preview-2",playerClass=rows[math.min(2,#rows)][2],isSelf=false,killingAbility=long and "CataclysmicallyLongLethalBlastAbilityName" or "Cataclysmic Blast",killerName=long and "AncientTrainingBossWithAnExcessivelyLongName" or "Training Boss",events={},totalDamageTaken=450000,totalHealingReceived=80000,timeSpan=3.2,timestamp=time(),gameTime=GetTime()}}
 end
 if #rows>0 then seg.enemyDamageTakenList={{name=long and "AncientTrainingBossWithAnExcessivelyLongName" or "Training Boss",creatureID=999001,total=math.floor(td*.82),sources={{name=rows[1][1],amount=math.floor(td*.4)}}}} else seg.enemyDamageTakenList={} end
 return seg
end

function PreviewModel:New(kind)
 local o=setmetatable({},self); o:SetDataset(kind or "normal"); return o
end

function PreviewModel:SetDataset(kind)
 self.dataset=kind; local rows=rowsFor(kind)
 local long=kind=="long"
 self.current=makeSegment(long and "ExtremelyLongCurrentPreviewCombatSegmentName" or ((ns.L and ns.L.MOCK_COMBAT) or "Mock Combat"),225,rows,1,kind)
 self.history={makeSegment(long and "ExceptionallyLongEarlierPreviewCombatSegmentName" or "Earlier Combat",148,rows,.62,kind),makeSegment(long and "ExtraordinarilyLongCompleteRunPreviewSegmentName" or "Full Run",640,rows,1.7,kind)}
 self.history[2]._isMerged=true
 self.overall=makeSegment(long and "OverwhelminglyLongOverallPreviewCombatSegmentName" or ((ns.L and ns.L.MOCK_OVERALL) or "Mock Overall"),720,rows,2.1,kind)
 self.viewKind="current"; self.viewIndex=nil
 if ns.Analysis then ns.Analysis:InvalidateCache() end
end

function PreviewModel:GetViewSegment()
 if self.viewKind=="overall" then return self.overall end
 if self.viewKind=="history" then return self.history[self.viewIndex] or self.current end
 return self.current
end

function PreviewModel:GetViewKey()
 if self.viewKind=="history" then return "archived",self.viewIndex end
 return self.viewKind,nil
end

function PreviewModel:GetHistoryList()
 local list={}
 for i=#self.history,1,-1 do local seg=self.history[i]; list[#list+1]={key="archived",localID=i,seg=seg,label=(seg.name or "Combat").." |cffaaaaaa"..ns:FormatTime(seg.duration or 0).."|r"} end
 list[#list+1]={key="current",seg=self.current,label=(ns.L and ns.L.COLORED_CURRENT_COMBAT) or "Current",isCurrent=true}
 list[#list+1]={key="overall",seg=self.overall,label=(ns.L and ns.L.COLORED_TOTAL_MARKER) or "Overall"}
 return list
end

function PreviewModel:SetViewEntry(data)
 if data.key=="current" then self.viewKind="current"; self.viewIndex=nil
 elseif data.key=="overall" then self.viewKind="overall"; self.viewIndex=nil
 elseif data.key=="archived" then self.viewKind="history"; self.viewIndex=data.localID end
end
