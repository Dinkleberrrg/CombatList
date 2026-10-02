--[[ CombatList -- tracker
     Finds the mobs your group is fighting and keeps their live data fresh.

     Two discovery sources:

     1) UNIT_CASTEVENT (SuperWoW). Every cast and swing reports
        caster GUID and target GUID. A hostile caster goes into the list;
        so does a hostile *target* of one of our own casts. This is what
        catches mobs nobody has selected.

     2) Unit token scan. target / targettarget / pettarget / mouseover and
        every party or raid member's target. Cheap, and the only source
        that works at all without SuperWoW.

     Entries are keyed by GUID when SuperWoW is present and by name
     otherwise -- the name fallback cannot tell two "Kobold Miner" apart,
     which is exactly why the GUID path exists.
]]--

local CL = CombatList

local STALE_SECONDS    = 8    -- no sighting at all for this long -> drop
local OUTOFCOMBAT_GRACE = 3   -- alive but no longer fighting -> drop after
local SCAN_INTERVAL    = 0.15
local RAID_INTERVAL    = 1.0

--------------------------------------------------------------------------
-- Unit tokens we can legally ask about in 1.12
--------------------------------------------------------------------------
local baseUnits = { "target", "targettarget", "pettarget", "mouseover" }

local scanUnits, scanCount = {}, 0

local function BuildScanUnits(includeRaid)
  scanCount = 0
  for i = 1, table.getn(baseUnits) do
    scanCount = scanCount + 1
    scanUnits[scanCount] = baseUnits[i]
  end

  local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
  if raid > 0 then
    if includeRaid then
      for i = 1, raid do
        scanCount = scanCount + 1; scanUnits[scanCount] = "raid" .. i .. "target"
        scanCount = scanCount + 1; scanUnits[scanCount] = "raidpet" .. i .. "target"
      end
    end
  else
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, party do
      scanCount = scanCount + 1; scanUnits[scanCount] = "party" .. i .. "target"
      scanCount = scanCount + 1; scanUnits[scanCount] = "partypet" .. i .. "target"
    end
  end

  for i = scanCount + 1, table.getn(scanUnits) do scanUnits[i] = nil end
end

--------------------------------------------------------------------------
-- Resolve an entry back to something we can query
--------------------------------------------------------------------------
-- With SuperWoW the GUID is itself a valid unit token, so this is a single
-- existence check. Without it we have to go looking for a unit token that
-- currently points at a mob with the same name.
function CL.ResolveUnit(entry)
  if not entry then return nil end

  if entry.guid then
    if UnitExists(entry.guid) then return entry.guid end
    return nil
  end

  for i = 1, scanCount do
    local unit = scanUnits[i]
    if UnitExists(unit) and UnitName(unit) == entry.name and UnitCanAttack("player", unit) then
      return unit
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- Adding
--------------------------------------------------------------------------
local function EntryID(guid, name)
  if guid then return guid end
  return name
end

-- unit may be a token or a GUID; both work as long as it resolves.
function CL.AddMob(unit)
  if not CL.IsHostileTarget(unit) then return nil end

  local name = UnitName(unit)
  if not name or name == "" then return nil end

  local guid = CL.GUID(unit)
  -- never list ourselves or a group member (PvP mirror case)
  if guid and CL.friends[guid] then return nil end

  local id = EntryID(guid, name)
  local entry = CL.mobs[id]

  if not entry then
    entry = { id = id, guid = guid, name = name, added = CL.orderNext }
    CL.orderNext = CL.orderNext + 1
    CL.mobs[id] = entry
    CL.order[table.getn(CL.order) + 1] = id
    CL.dirty = true
    CL.Debug("added " .. name .. " (" .. (guid or "byname") .. ")")
  end

  entry.seen = GetTime()
  return entry
end

--------------------------------------------------------------------------
-- Refresh one entry's live data
--------------------------------------------------------------------------
local function RefreshEntry(entry, now)
  local unit = CL.ResolveUnit(entry)

  if not unit then
    -- out of range / despawned: keep briefly, then let the pruner drop it
    entry.visible = nil
    return
  end

  entry.visible = true
  entry.name           = UnitName(unit) or entry.name
  entry.level          = UnitLevel(unit)
  entry.classification = UnitClassification and UnitClassification(unit) or "normal"
  entry.player         = UnitIsPlayer and UnitIsPlayer(unit) or nil
  entry.dead           = UnitIsDeadOrGhost(unit) and true or nil
  entry.incombat       = UnitAffectingCombat(unit) and true or nil

  local _, class = UnitClass(unit)
  entry.class = class

  local maxhp = UnitHealthMax(unit) or 0
  local hp    = UnitHealth(unit) or 0
  entry.hp    = hp
  entry.maxhp = maxhp
  entry.pct   = (maxhp > 0) and (hp / maxhp) or 0

  -- Who is it attacking? GUID.."target" is a real unit token under
  -- SuperWoW; in fallback mode "<token>target" only works for the few
  -- tokens that support the suffix, so it is guarded.
  local tunit = nil
  if entry.guid then
    tunit = entry.guid .. "target"
  elseif unit == "target" then
    tunit = "targettarget"
  end

  entry.targetName, entry.targetGUID, entry.targetsMe = nil, nil, nil
  if tunit and UnitExists(tunit) then
    local _, tguid = UnitExists(tunit)
    entry.targetName = UnitName(tunit)
    entry.targetGUID = tguid
    local text, isMe = CL.DescribeTarget(tguid, entry.targetName)
    entry.targetText = text
    entry.targetsMe  = isMe
  else
    entry.targetText = CL.C.grey .. "--" .. CL.C.off
  end

  if entry.incombat or entry.targetName then
    entry.seen = now
  end
end

--------------------------------------------------------------------------
-- Pruning
--------------------------------------------------------------------------
local function Prune(now)
  local keep, kn = {}, 0
  local total = table.getn(CL.order)

  for i = 1, total do
    local id = CL.order[i]
    local entry = CL.mobs[id]
    local drop = nil

    if not entry then
      drop = true
    elseif entry.dead then
      drop = true
    elseif now - (entry.seen or 0) > STALE_SECONDS then
      drop = true
    elseif entry.visible and not entry.incombat and now - (entry.seen or 0) > OUTOFCOMBAT_GRACE then
      drop = true
    end

    if drop then
      if entry then CL.Debug("dropped " .. (entry.name or "?")) end
      CL.mobs[id] = nil
      CL.dirty = true
    else
      kn = kn + 1
      keep[kn] = id
    end
  end

  for i = 1, total do CL.order[i] = nil end
  for i = 1, kn do CL.order[i] = keep[i] end
end

--------------------------------------------------------------------------
-- Sorted view for the UI: mobs attacking you first, then insertion order
--------------------------------------------------------------------------
function CL.GetSorted()
  local list, n = {}, 0
  local onlyMine = CL.db and CL.db.onlymine == "1"

  for i = 1, table.getn(CL.order) do
    local entry = CL.mobs[CL.order[i]]
    if entry and (not onlyMine or entry.targetsMe) then
      n = n + 1
      list[n] = entry
    end
  end

  table.sort(list, function(a, b)
    local am = a.targetsMe and 1 or 0
    local bm = b.targetsMe and 1 or 0
    if am ~= bm then return am > bm end
    return (a.added or 0) < (b.added or 0)
  end)

  return list, n
end

--------------------------------------------------------------------------
-- Event source: UNIT_CASTEVENT
--------------------------------------------------------------------------
local events = CreateFrame("Frame", "CombatListEvents", UIParent)
events:RegisterEvent("UNIT_CASTEVENT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")

events:SetScript("OnEvent", function()
  if event == "UNIT_CASTEVENT" then
    -- arg1 caster GUID, arg2 target GUID, arg3 type, arg4 spellID, arg5 time
    local caster, target = arg1, arg2

    if caster and caster ~= "" and not CL.friends[caster] then
      CL.AddMob(caster)
    end
    if target and target ~= "" and not CL.friends[target] then
      CL.AddMob(target)
    end

  elseif event == "PLAYER_TARGET_CHANGED" then
    CL.AddMob("target")

  elseif event == "PLAYER_REGEN_DISABLED" then
    CL.UpdateFriends()
    CL.AddMob("target")
  end
end)

--------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------
local loop = CreateFrame("Frame", "CombatListLoop", UIParent)
loop.nextScan = 0
loop.nextRaid = 0

loop:SetScript("OnUpdate", function()
  if not CL.db then return end
  local now = GetTime()
  if now < loop.nextScan then return end
  loop.nextScan = now + SCAN_INTERVAL

  local includeRaid = nil
  if now >= loop.nextRaid then
    loop.nextRaid = now + RAID_INTERVAL
    includeRaid = true
  end

  BuildScanUnits(includeRaid)

  -- discovery pass
  for i = 1, scanCount do
    CL.AddMob(scanUnits[i])
  end

  -- refresh pass
  for i = 1, table.getn(CL.order) do
    local entry = CL.mobs[CL.order[i]]
    if entry then RefreshEntry(entry, now) end
  end

  Prune(now)

  if CL.RefreshUI then CL.RefreshUI() end
end)

CL.BuildScanUnits = BuildScanUnits
