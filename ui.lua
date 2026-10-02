--[[ CombatList -- UI
     A movable list. One row per mob: health bar as the background, name and
     level on the left, who it is currently attacking on the right.

     Left click  -> target the mob
     Shift+Left  -> target whoever the mob is attacking
     Right click -> dismiss this row (it returns if the mob is still active)
]]--

local CL = CombatList

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local HEADER_H    = 16

--------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------
local frame = CreateFrame("Frame", "CombatListFrame", UIParent)
frame:SetWidth(210)
frame:SetHeight(HEADER_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:Hide()

frame:SetBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  tile = false, edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
frame:SetBackdropColor(0, 0, 0, 0.55)
frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)

frame:SetScript("OnMouseDown", function()
  if CL.db and CL.db.locked ~= "1" then this:StartMoving() end
end)

frame:SetScript("OnMouseUp", function()
  this:StopMovingOrSizing()
  local point, _, _, x, y = this:GetPoint()
  if CL.db then CL.db.pos = { point, x, y } end
end)

frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -3)
frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -3)
frame.header:SetJustifyH("LEFT")
frame.header:SetText(CL.C.head .. "Combat" .. CL.C.off)

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------
frame.rows = {}

local function RowClick()
  local entry = this.entry
  if not entry then return end

  if arg1 == "RightButton" then
    CL.mobs[entry.id] = nil
    CL.dirty = true
    return
  end

  if IsShiftKeyDown() then
    -- jump to whoever this mob is beating on
    if entry.targetGUID and UnitExists(entry.targetGUID) then
      TargetUnit(entry.targetGUID)
    elseif entry.targetName then
      TargetByName(entry.targetName, true)
    end
    return
  end

  local unit = CL.ResolveUnit(entry)
  if unit then
    TargetUnit(unit)
  elseif entry.name and TargetByName then
    TargetByName(entry.name, true)
  end
end

local function RowEnter()
  local entry = this.entry
  this.hover = true
  if not entry then return end
  local unit = CL.ResolveUnit(entry)
  if unit then
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
  end
end

local function RowLeave()
  this.hover = nil
  GameTooltip:Hide()
end

local function GetRow(i)
  if frame.rows[i] then return frame.rows[i] end

  local row = CreateFrame("Button", "CombatListRow" .. i, frame)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints(row)
  row.bar:SetStatusBarTexture(BAR_TEXTURE)
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(1)

  row.bg = row.bar:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(row.bar)
  row.bg:SetTexture(0.1, 0.1, 0.1, 0.8)

  -- red edge marker for "this one is on you"
  row.mark = row.bar:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT", row.bar, "TOPLEFT", 0, 0)
  row.mark:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMLEFT", 0, 0)
  row.mark:SetWidth(3)
  row.mark:SetTexture(1, 0.2, 0.2, 1)
  row.mark:Hide()

  row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("LEFT", row.bar, "LEFT", 6, 0)
  row.name:SetJustifyH("LEFT")

  row.target = row.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.target:SetPoint("RIGHT", row.bar, "RIGHT", -5, 0)
  row.target:SetJustifyH("RIGHT")

  row:SetScript("OnClick", RowClick)
  row:SetScript("OnEnter", RowEnter)
  row:SetScript("OnLeave", RowLeave)

  frame.rows[i] = row
  return row
end

--------------------------------------------------------------------------
-- Classification prefix
--------------------------------------------------------------------------
local function Prefix(entry)
  local c = entry.classification
  if c == "worldboss" then return CL.C.red .. "B " .. CL.C.off end
  if c == "rareelite" then return CL.C.gold .. "R+ " .. CL.C.off end
  if c == "elite"     then return CL.C.gold .. "+ " .. CL.C.off end
  if c == "rare"      then return CL.C.gold .. "R " .. CL.C.off end
  return ""
end

--------------------------------------------------------------------------
-- Redraw
--------------------------------------------------------------------------
function CL.RefreshUI()
  if not CL.db then return end

  local width  = tonumber(CL.db.width) or 210
  local rowH   = tonumber(CL.db.rowheight) or 18
  local maxRow = tonumber(CL.db.maxrows) or 20
  local scale  = tonumber(CL.db.scale) or 1

  local list, count = CL.GetSorted()
  if count > maxRow then count = maxRow end

  if count == 0 then
    frame:Hide()
    return
  end

  frame:SetScale(scale)
  frame:SetWidth(width)
  frame:SetHeight(HEADER_H + count * (rowH + 1) + 3)
  frame.header:SetText(CL.C.head .. "Combat" .. CL.C.off .. "  "
    .. CL.C.grey .. count .. CL.C.off)

  for i = 1, count do
    local entry = list[i]
    local row = GetRow(i)

    row:SetWidth(width - 4)
    row:SetHeight(rowH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -(HEADER_H + (i - 1) * (rowH + 1)))
    row.entry = entry

    -- health bar
    local pct = entry.pct or 0
    row.bar:SetValue(pct)
    local r, g, b = CL.HealthColor(pct)
    if not entry.visible then
      -- out of range: desaturate so it is obvious the data is stale
      r, g, b = 0.35, 0.35, 0.4
    end
    row.bar:SetStatusBarColor(r, g, b, 0.85)

    -- left label
    local label = Prefix(entry) .. (entry.name or "?")
    if CL.db.showlevel == "1" and entry.level and entry.level > 0 then
      label = label .. CL.C.grey .. " " .. entry.level .. CL.C.off
    end
    if CL.db.showhp == "1" and entry.visible then
      label = label .. CL.C.grey .. "  " .. math.floor(pct * 100 + 0.5) .. "%" .. CL.C.off
    end
    row.name:SetText(label)

    -- right label
    if CL.db.showtarget == "1" then
      row.target:SetText((entry.targetText or "") ~= "" and
        (CL.C.grey .. "> " .. CL.C.off .. entry.targetText) or "")
      row.target:Show()
    else
      row.target:Hide()
    end

    if entry.targetsMe then row.mark:Show() else row.mark:Hide() end

    row:Show()
  end

  for i = count + 1, table.getn(frame.rows) do
    frame.rows[i].entry = nil
    frame.rows[i]:Hide()
  end

  frame:Show()
end

--------------------------------------------------------------------------
-- Restore position
--------------------------------------------------------------------------
local restore = CreateFrame("Frame", "CombatListRestore", UIParent)
restore:RegisterEvent("PLAYER_ENTERING_WORLD")
restore:SetScript("OnEvent", function()
  if not CL.db or not CL.db.pos then return end
  local point, x, y = CL.db.pos[1], CL.db.pos[2], CL.db.pos[3]
  if point and x and y then
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
  end
end)

CL.frame = frame
