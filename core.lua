--[[ CombatList -- core
     Target client: WoW 1.12 (Octo WoW), Lua 5.0.
     No modern APIs: no C_*, no hooksecurefunc, no #tbl, no string.gmatch,
     no select(), no strsplit().

     SuperWoW (SuperWoWhook.dll) is what makes this addon possible:
       * UnitExists(unit) returns a second value, the unit's GUID
       * that GUID works as a unit token anywhere ("0xF130..." )
       * and so does GUID.."target", which is how we learn who a mob attacks
       * UNIT_CASTEVENT(casterGUID, targetGUID, type, spellID, castTime)
     Without SuperWoW the addon still runs, but degrades to the handful of
     mobs reachable through plain unit tokens (see tracker.lua).
]]--

CombatList = CreateFrame("Frame", "CombatListCore", UIParent)
local CL = CombatList

CL.addonName  = "CombatList"
CL.versionStr = "1.0.0"

CL.defaults = {
  locked    = "0",
  width     = "210",
  rowheight = "18",
  maxrows   = "20",
  scale     = "1.0",
  showlevel = "1",
  showhp    = "1",
  showtarget= "1",
  onlymine  = "0",   -- 1 = only mobs attacking me
  debug     = "0",
  pos       = nil,   -- { point, x, y }
}

-- Runtime state
CL.mobs      = {}    -- [id] = entry     (id = GUID, or name in fallback mode)
CL.order     = {}    -- insertion order of ids
CL.orderNext = 1
CL.friends   = {}    -- [guid] = { name, class }   own group, for target coloring
CL.friendsByName = {}
CL.playerGUID = nil
CL.superwow  = nil
CL.dirty     = true

CL.C = {
  head  = "|cff33ffcc",
  white = "|cffffffff",
  grey  = "|cff888888",
  red   = "|cffff4040",
  green = "|cff40dd40",
  gold  = "|cffffcc00",
  off   = "|r",
}

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------

function CL.Count(t)
  local n = 0
  if not t then return 0 end
  for _ in pairs(t) do n = n + 1 end
  return n
end

function CL.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(CL.C.head .. "Combat" .. CL.C.white .. "List" .. CL.C.off .. ": " .. (msg or ""))
end

function CL.Debug(msg)
  if CL.db and CL.db.debug == "1" then
    DEFAULT_CHAT_FRAME:AddMessage(CL.C.grey .. "[CL] " .. (msg or "") .. CL.C.off)
  end
end

-- Health bar color: green -> yellow -> red.
function CL.HealthColor(pct)
  if not pct then return 0.4, 0.4, 0.4 end
  if pct > 0.5 then
    local t = (pct - 0.5) * 2
    return 1 - t * 0.8, 0.8, 0.15
  end
  local t = pct * 2
  return 0.9, 0.15 + t * 0.65, 0.15
end

function CL.ClassColorString(class)
  if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
    local c = RAID_CLASS_COLORS[class]
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
  end
  return "|cffcccccc"
end

--------------------------------------------------------------------------
-- GUID access (SuperWoW)
--------------------------------------------------------------------------

-- Returns the GUID for a unit token, or nil without SuperWoW.
function CL.GUID(unit)
  if not unit then return nil end
  local exists, guid = UnitExists(unit)
  if exists and guid then return guid end
  return nil
end

-- Is this unit something we would list? Attackable, alive, not us.
function CL.IsHostileTarget(unit)
  if not unit or not UnitExists(unit) then return nil end
  if UnitIsDeadOrGhost(unit) then return nil end
  if not UnitCanAttack("player", unit) then return nil end
  return true
end

--------------------------------------------------------------------------
-- Friendly roster (so we can color "who is it attacking")
--------------------------------------------------------------------------

function CL.UpdateFriends()
  for k in pairs(CL.friends) do CL.friends[k] = nil end
  for k in pairs(CL.friendsByName) do CL.friendsByName[k] = nil end

  local function add(unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    if not name then return end
    local _, class = UnitClass(unit)
    local entry = { name = name, class = class, unit = unit }
    local guid = CL.GUID(unit)
    if guid then CL.friends[guid] = entry end
    CL.friendsByName[name] = entry
  end

  add("player")
  add("pet")
  CL.playerGUID = CL.GUID("player")

  local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
  if raid > 0 then
    for i = 1, raid do
      add("raid" .. i)
      add("raidpet" .. i)
    end
  else
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, party do
      add("party" .. i)
      add("partypet" .. i)
    end
  end
end

-- Describes a mob's current target: display text plus "is that me?".
function CL.DescribeTarget(guid, name)
  local friend = (guid and CL.friends[guid]) or (name and CL.friendsByName[name])

  if guid and CL.playerGUID and guid == CL.playerGUID then
    return CL.C.red .. "YOU" .. CL.C.off, true
  end
  if not guid and name and name == UnitName("player") then
    return CL.C.red .. "YOU" .. CL.C.off, true
  end
  if friend then
    return CL.ClassColorString(friend.class) .. friend.name .. CL.C.off, nil
  end
  if name then
    return CL.C.grey .. name .. CL.C.off, nil
  end
  return CL.C.grey .. "--" .. CL.C.off, nil
end

--------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------

CL:RegisterEvent("ADDON_LOADED")
CL:RegisterEvent("PLAYER_ENTERING_WORLD")
CL:RegisterEvent("PARTY_MEMBERS_CHANGED")
CL:RegisterEvent("RAID_ROSTER_UPDATE")
CL:RegisterEvent("UNIT_PET")

CL:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "CombatList" then
    CombatList_config = CombatList_config or {}
    for k, v in pairs(CL.defaults) do
      if CombatList_config[k] == nil and v ~= nil then CombatList_config[k] = v end
    end
    CL.db = CombatList_config

  elseif event == "PLAYER_ENTERING_WORLD" then
    CL.db = CombatList_config or CL.defaults
    CL.superwow = (SUPERWOW_VERSION and true) or nil
    CL.UpdateFriends()
    if not CL.greeted then
      CL.greeted = true
      if CL.superwow then
        CL.Print("v" .. CL.versionStr .. " loaded (SuperWoW " .. tostring(SUPERWOW_VERSION)
          .. "). Type " .. CL.C.head .. "/cl" .. CL.C.off .. " for options.")
      else
        CL.Print("v" .. CL.versionStr .. " loaded. " .. CL.C.gold
          .. "SuperWoW not detected -- running in reduced mode." .. CL.C.off)
      end
    end

  else
    CL.UpdateFriends()
  end
end)
