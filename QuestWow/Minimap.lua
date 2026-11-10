-- QuestWow: кнопка у миникарты
-- 1) Если в игре уже загружены LibDataBroker + LibDBIcon (их приносят многие аддоны),
--    регистрируемся через них: кнопку подхватят сборщики кнопок миникарты.
-- 2) Иначе — своя кнопка. Она привязана к UIParent (не к Minimap), поэтому
--    не пропадает, если миникарта обрезает дочерние фреймы или перерисована.
local _, QW = ...
local M = {}
QW.Minimap = M

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local btn, ldbIcon

local function Tooltip(tt)
    tt:AddLine("|cffffd100Quest|r|cff66ccffWow|r")
    local me = QW.me and QW.db.chars[QW.me]
    if me then tt:AddLine("Выполнено: " .. (me.doneCount or 0), 1, 1, 1) end
    for _, p in ipairs(QW.db.settings.partners) do
        local ch = QW.db.chars[p] or {}
        local on = QW.Comm.IsOnline(p) and "|cff5ce673в сети|r" or "|cff888888не в сети|r"
        tt:AddDoubleLine(QW.ColoredName(p) .. "  " .. (ch.doneCount or 0), on)
    end
    tt:AddLine(" ")
    tt:AddLine("ЛКМ - открыть, ПКМ - настройки", 0.7, 0.7, 0.7)
    tt:AddLine("Перетащить - переместить", 0.7, 0.7, 0.7)
end

local function OnClick(button)
    if button == "RightButton" then
        QW.UI.Show()
        QW.UI.SelectTab("settings")
    else
        QW.UI.Toggle()
    end
end

-------------------------------------------------------------------------------
-- Вариант 1: LibDBIcon
-------------------------------------------------------------------------------
local function TryLibDBIcon()
    if not LibStub then return false end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not (ldb and icon) then return false end
    local obj = ldb:NewDataObject("QuestWow", {
        type = "launcher",
        text = "QuestWow",
        icon = ICON,
        OnClick = function(_, button) OnClick(button) end,
        OnTooltipShow = function(tt) Tooltip(tt) end,
    })
    if not obj then return false end
    QW.db.settings.minimap.ldb = QW.db.settings.minimap.ldb or {}
    local ok = pcall(icon.Register, icon, "QuestWow", obj, QW.db.settings.minimap.ldb)
    if not ok then return false end
    ldbIcon = icon
    return true
end

-------------------------------------------------------------------------------
-- Вариант 2: своя кнопка
-------------------------------------------------------------------------------
local function Anchor()
    if Minimap and Minimap.IsShown and Minimap:IsShown() and Minimap:GetWidth() > 10 then
        return Minimap
    end
    return nil
end

local function UpdatePosition()
    local mm = QW.db.settings.minimap
    btn:ClearAllPoints()
    local anchor = Anchor()
    if anchor and not mm.free then
        local angle = math.rad(mm.angle or 215)
        local r = (anchor:GetWidth() / 2) + 8
        btn:SetPoint("CENTER", anchor, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
    elseif mm.x and mm.y then
        btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mm.x, mm.y)
    else
        btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -40)
    end
end

local function CreateOwnButton()
    btn = CreateFrame("Button", "QuestWowMinimapButton", UIParent)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(50)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0, 0, 0, 0.6)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnClick", function(_, button) OnClick(button) end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mm = QW.db.settings.minimap
            local cx, cy = GetCursorPosition()
            local anchor = Anchor()
            if anchor and not IsShiftKeyDown() then
                -- По кругу вокруг миникарты
                local s = anchor:GetEffectiveScale()
                local mx, my = anchor:GetCenter()
                mm.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
                mm.free = nil
            else
                -- Shift + перетаскивание: свободно по экрану
                local s = UIParent:GetEffectiveScale()
                mm.x, mm.y, mm.free = cx / s, cy / s, true
            end
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Tooltip(GameTooltip)
        GameTooltip:AddLine("Shift + перетащить - в любое место экрана", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M.Update()
    local mm = QW.db.settings.minimap
    if ldbIcon then
        if mm.hide then ldbIcon:Hide("QuestWow") else ldbIcon:Show("QuestWow") end
        return
    end
    if not btn then CreateOwnButton() end
    btn:SetShown(not mm.hide)
    UpdatePosition()
end

local function Init()
    if not btn and not ldbIcon then
        local ok, used = pcall(TryLibDBIcon)
        if not (ok and used) then ldbIcon = nil end
    end
    M.Update()
end

-- Создаём после входа, а потом ещё раз проверяем позицию,
-- когда интерфейс (и миникарта) точно построен.
QW.On("LOGIN", function()
    local ok, err = pcall(Init)
    if not ok then geterrorhandler()(err) end
    C_Timer.After(2, function() pcall(M.Update) end)
end)
