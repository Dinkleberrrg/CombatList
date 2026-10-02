--[[ CombatList -- slash commands ]]--

local CL = CombatList

-- Splits "width 240" into "width", "240" without strsplit (not in 1.12).
local function Args(msg)
  msg = msg or ""
  local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.-)%s*$")
  return string.lower(cmd or ""), rest or ""
end

local function Toggle(key, label)
  CL.db[key] = (CL.db[key] == "1") and "0" or "1"
  CL.Print(label .. ": " .. (CL.db[key] == "1" and CL.C.green .. "on" or CL.C.red .. "off") .. CL.C.off)
  if CL.RefreshUI then CL.RefreshUI() end
end

local function SetNumber(key, value, label, min, max)
  local n = tonumber(value)
  if not n then
    CL.Print(label .. " is " .. CL.C.gold .. tostring(CL.db[key]) .. CL.C.off
      .. " (usable range " .. min .. "-" .. max .. ")")
    return
  end
  if n < min then n = min end
  if n > max then n = max end
  CL.db[key] = tostring(n)
  CL.Print(label .. " set to " .. CL.C.gold .. n .. CL.C.off)
  if CL.RefreshUI then CL.RefreshUI() end
end

local function Status()
  CL.Print("Status:")
  DEFAULT_CHAT_FRAME:AddMessage("  SuperWoW: " ..
    (CL.superwow and (CL.C.green .. "active " .. tostring(SUPERWOW_VERSION)) or
     (CL.C.red .. "not detected -- reduced mode")) .. CL.C.off)
  DEFAULT_CHAT_FRAME:AddMessage("  tracked mobs: " .. CL.Count(CL.mobs))
  DEFAULT_CHAT_FRAME:AddMessage("  group members known: " .. CL.Count(CL.friendsByName))
  local list, n = CL.GetSorted()
  for i = 1, n do
    local e = list[i]
    DEFAULT_CHAT_FRAME:AddMessage("   - " .. (e.name or "?")
      .. " (" .. math.floor((e.pct or 0) * 100 + 0.5) .. "%) > "
      .. (e.targetName or "--"))
  end
end

local function Help()
  CL.Print("Commands:")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl lock         - lock/unlock the window")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl width <n>    - window width (120-500)")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl height <n>   - row height (10-40)")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl rows <n>     - maximum rows (1-40)")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl scale <n>    - scale (0.5-2.0)")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl level        - show mob level on/off")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl hp           - show health percent on/off")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl target       - show attack target on/off")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl mine         - only mobs attacking me on/off")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl clear        - empty the list")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl status       - what is being tracked right now")
  DEFAULT_CHAT_FRAME:AddMessage("  /cl debug        - debug output on/off")
  DEFAULT_CHAT_FRAME:AddMessage(CL.C.grey
    .. "  row: left click targets, shift+left targets its victim, right click dismisses"
    .. CL.C.off)
end

SLASH_COMBATLIST1 = "/cl"
SLASH_COMBATLIST2 = "/combatlist"

SlashCmdList["COMBATLIST"] = function(msg)
  local cmd, rest = Args(msg)

  if cmd == "" or cmd == "help" then
    Help()
  elseif cmd == "lock" then
    Toggle("locked", "Window locked")
  elseif cmd == "width" then
    SetNumber("width", rest, "Width", 120, 500)
  elseif cmd == "height" then
    SetNumber("rowheight", rest, "Row height", 10, 40)
  elseif cmd == "rows" then
    SetNumber("maxrows", rest, "Maximum rows", 1, 40)
  elseif cmd == "scale" then
    SetNumber("scale", rest, "Scale", 0.5, 2.0)
  elseif cmd == "level" then
    Toggle("showlevel", "Mob level")
  elseif cmd == "hp" then
    Toggle("showhp", "Health percent")
  elseif cmd == "target" then
    Toggle("showtarget", "Attack target")
  elseif cmd == "mine" then
    Toggle("onlymine", "Only mobs attacking me")
  elseif cmd == "clear" then
    for k in pairs(CL.mobs) do CL.mobs[k] = nil end
    for i = 1, table.getn(CL.order) do CL.order[i] = nil end
    CL.Print("List cleared.")
    if CL.RefreshUI then CL.RefreshUI() end
  elseif cmd == "status" then
    Status()
  elseif cmd == "debug" then
    Toggle("debug", "Debug")
  else
    Help()
  end
end
