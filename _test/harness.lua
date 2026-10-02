-- Test harness: stubs the 1.12 API *plus* SuperWoW's GUID unit tokens and
-- UNIT_CASTEVENT, then runs a fake fight through the tracker and the UI.
-- Not loaded by the game.

local frames, now = {}, 100
function GetTime() return now end
UIParent = {}

--------------------------------------------------------------------------
-- frame stub
--------------------------------------------------------------------------
local mt = {}
local function newFrame(name)
  return setmetatable({ scripts = {}, name = name, shown = false, w = 0, h = 0 }, mt)
end
mt.__index = {
  SetScript = function(s, k, f) s.scripts[k] = f end,
  GetScript = function(s, k) return s.scripts[k] end,
  RegisterEvent = function() end, UnregisterEvent = function() end,
  RegisterForClicks = function() end,
  SetWidth = function(s, v) s.w = v end, SetHeight = function(s, v) s.h = v end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetPoint = function() end, ClearAllPoints = function() end, SetAllPoints = function() end,
  GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
  SetFrameStrata = function() end, SetScale = function() end,
  SetMovable = function() end, EnableMouse = function() end, SetClampedToScreen = function() end,
  StartMoving = function() end, StopMovingOrSizing = function() end,
  SetBackdrop = function() end, SetBackdropColor = function() end, SetBackdropBorderColor = function() end,
  SetStatusBarTexture = function() end, SetStatusBarColor = function() end,
  SetMinMaxValues = function() end, SetValue = function(s, v) s.value = v end,
  SetTexture = function() end, SetJustifyH = function() end, SetFont = function() end,
  SetTextColor = function() end, GetStringWidth = function() return 40 end,
  SetText = function(s, t) s.text = t end, GetText = function(s) return s.text end,
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end,
  CreateFontString = function() return newFrame() end,
  CreateTexture = function() return newFrame() end,
  SetOwner = function() end, SetUnit = function() end,
}
function CreateFrame(kind, name, parent)
  local f = newFrame(name)
  if name then frames[name] = f end
  return f
end

strfind, strsub, strlen, strlower = string.find, string.sub, string.len, string.lower
gsub, format = string.gsub, string.format
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  |chat| " .. m) end }
SlashCmdList = {}
GameTooltip = newFrame("GameTooltip")
RAID_CLASS_COLORS = {
  WARRIOR = { r = .78, g = .61, b = .43 }, MAGE = { r = .41, g = .8, b = .94 },
}
function IsShiftKeyDown() return nil end
SUPERWOW_VERSION = "1.5"

--------------------------------------------------------------------------
-- fake world with GUIDs
--------------------------------------------------------------------------
local UNITS = {
  ["0xP1"] = { name = "Henry",  class = "MAGE",    player = true, hp = 100, max = 100, level = 20, combat = true },
  ["0xF1"] = { name = "Thrall", class = "WARRIOR", player = true, hp = 90,  max = 100, level = 21, combat = true },
  ["0xM1"] = { name = "Kobold Miner",    hp = 64, max = 100, level = 10, combat = true, hostile = true, target = "0xP1", cls = "normal" },
  ["0xM2"] = { name = "Kobold Miner",    hp = 31, max = 100, level = 10, combat = true, hostile = true, target = "0xF1", cls = "normal" },
  ["0xM3"] = { name = "Kobold Overseer", hp = 98, max = 120, level = 12, combat = true, hostile = true, target = "0xF1", cls = "elite" },
}
local TOKENS = {
  player = "0xP1", party1 = "0xF1",
  target = "0xM1", party1target = "0xM2",
}

local function resolve(u)
  if not u then return nil end
  if TOKENS[u] then return TOKENS[u] end
  if UNITS[u] then return u end
  if string.len(u) > 6 and string.sub(u, -6) == "target" then
    local base = resolve(string.sub(u, 1, string.len(u) - 6))
    if base and UNITS[base] then return UNITS[base].target end
  end
  return nil
end

function UnitExists(u)
  local g = resolve(u)
  if g then return 1, g end
  return nil
end
local function U(u) local g = resolve(u); return g and UNITS[g] or nil end
function UnitName(u) local d = U(u); return d and d.name end
function UnitLevel(u) local d = U(u); return d and d.level or 0 end
function UnitHealth(u) local d = U(u); return d and d.hp or 0 end
function UnitHealthMax(u) local d = U(u); return d and d.max or 0 end
function UnitClass(u) local d = U(u); return d and d.class, d and d.class end
function UnitClassification(u) local d = U(u); return d and d.cls or "normal" end
function UnitIsPlayer(u) local d = U(u); return d and d.player end
function UnitIsDeadOrGhost(u) local d = U(u); return d and d.dead end
function UnitAffectingCombat(u) local d = U(u); return d and d.combat end
function UnitCanAttack(a, b) local d = U(b); return d and d.hostile end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 1 end
function TargetUnit(u) TARGETED = u end
function TargetByName(n) TARGETED = n end

--------------------------------------------------------------------------
dofile("core.lua")
dofile("tracker.lua")
dofile("ui.lua")
dofile("slash.lua")

local CL = CombatList
local core = frames["CombatListCore"]

-- boot
CombatList_config = nil
event, arg1 = "ADDON_LOADED", "CombatList"
core.scripts.OnEvent()
event, arg1 = "PLAYER_ENTERING_WORLD", nil
core.scripts.OnEvent()
frames["CombatListRestore"].scripts.OnEvent()

local loop = frames["CombatListLoop"]
local events = frames["CombatListEvents"]
local function tick(n)
  for i = 1, (n or 1) do
    now = now + 0.2
    loop.scripts.OnUpdate()
  end
end

local function dump(tag)
  local list, n = CL.GetSorted()
  print("  " .. tag .. " -> " .. n .. " mob(s)")
  for i = 1, n do
    local e = list[i]
    print(string.format("    %-18s lvl %-3s %3d%%  attacking %-8s%s",
      e.name, tostring(e.level), math.floor((e.pct or 0) * 100 + .5),
      tostring(e.targetName), e.targetsMe and "   <-- YOU" or ""))
  end
  return n
end

print("== discovery via unit tokens ==")
tick(2)
local n = dump("after scan")
assert(n == 2, "expected M1 (target) and M2 (party1target), got " .. n)

print("== discovery via UNIT_CASTEVENT ==")
event, arg1, arg2, arg3, arg4, arg5 = "UNIT_CASTEVENT", "0xM3", "0xF1", "CAST", 133, 1.5
events.scripts.OnEvent()
tick(2)
n = dump("after castevent")
assert(n == 3, "the overseer nobody targeted should now be listed, got " .. n)

print("== who is attacking whom (guid..target) ==")
local list = CL.GetSorted()
assert(list[1].targetsMe, "the mob on the player must sort first")
assert(list[1].name == "Kobold Miner", "wrong mob first: " .. list[1].name)
assert(list[2].targetName == "Thrall" or list[3].targetName == "Thrall", "party target not resolved")
print("  ok: sorted with the mob attacking you on top")

print("== two mobs with the same name stay separate ==")
local sameName = 0
for _, e in ipairs(CL.GetSorted()) do
  if e.name == "Kobold Miner" then sameName = sameName + 1 end
end
assert(sameName == 2, "GUID keying failed, both Kobold Miners collapsed into one")
print("  ok: 2 distinct 'Kobold Miner' entries")

print("== UI renders without error ==")
CL.RefreshUI()
local f = frames["CombatListFrame"]
assert(f.shown, "frame should be visible with mobs present")
print("  header: " .. tostring(f.header and f.header.text))
for i = 1, 3 do
  local row = frames["CombatListRow" .. i]
  if row then print("  row " .. i .. ": " .. tostring(row.name.text) .. "   " .. tostring(row.target.text)) end
end

print("== click targets the right mob ==")
local row1 = frames["CombatListRow1"]
arg1 = "LeftButton"
this = row1
row1.scripts.OnClick()
assert(TARGETED == "0xM1", "click targeted " .. tostring(TARGETED) .. " instead of the GUID")
print("  ok: TargetUnit(" .. TARGETED .. ")")

print("== dead mob is pruned ==")
UNITS["0xM1"].dead = true
tick(2)
n = dump("after death")
assert(n == 2, "dead mob still listed")

print("== mob leaving combat is pruned after the grace period ==")
UNITS["0xM2"].combat = nil
UNITS["0xM2"].target = nil
TOKENS.party1target = nil
tick(30)
n = dump("after disengage")
assert(n == 1, "expected only the overseer, got " .. n)

print("== 'only mobs attacking me' filter ==")
CL.db.onlymine = "1"
n = dump("onlymine")
assert(n == 0, "overseer attacks Thrall, so the filter should hide it")
CL.db.onlymine = "0"

print("== empty list hides the window ==")
for k in pairs(CL.mobs) do CL.mobs[k] = nil end
for i = 1, table.getn(CL.order) do CL.order[i] = nil end
CL.RefreshUI()
assert(not f.shown, "frame should hide when the list is empty")
print("  ok: hidden")

print("\nAll tests passed.")
