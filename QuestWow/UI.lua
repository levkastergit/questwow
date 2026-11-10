-- QuestWow: UI — главное окно
local _, QW = ...
local UI = { cols = {} }
QW.UI = UI

-------------------------------------------------------------------------------
-- Палитра
-------------------------------------------------------------------------------
local C = {
    bg       = { 0.055, 0.06, 0.075, 0.97 },
    panel    = { 0.085, 0.09, 0.11, 1 },
    panel2   = { 0.11, 0.115, 0.14, 1 },
    border   = { 0.22, 0.20, 0.15, 1 },
    line     = { 1, 1, 1, 0.06 },
    gold     = { 1, 0.82, 0.25 },
    blue     = { 0.40, 0.80, 1.00 },
    text     = { 0.92, 0.92, 0.94 },
    dim      = { 0.55, 0.57, 0.62 },
    green    = { 0.35, 0.90, 0.45 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_ACTIVE = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ICON_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_ONLINE = "Interface\\FriendsFrame\\StatusIcon-Online"
local ICON_OFFLINE = "Interface\\FriendsFrame\\StatusIcon-Offline"

local COL_W = 54          -- ширина колонки персонажа
local MAX_COLS = 4

local function Hex(c) return string.format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function SetBD(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg or C.panel))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

local function Text(parent, font, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if size then
        local path, _, flags = fs:GetFont()
        if path then fs:SetFont(path, size, flags) end
    end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function FlatButton(parent, label, w, h, accent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 120, h or 24)
    SetBD(b, C.panel2, accent and { 0.55, 0.45, 0.15, 1 } or C.border)
    b.text = Text(b, "GameFontNormalSmall", 11, accent and C.gold or C.text, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.20, 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(C.panel2))
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

local function Checkbox(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(260, 22)
    local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    SetBD(box, C.panel2)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    local t = Text(b, "GameFontHighlightSmall", 12, C.text)
    t:SetPoint("LEFT", box, "RIGHT", 8, 0)
    t:SetText(label)
    function b:Update() mark:SetShown(get() and true or false) end
    b:SetScript("OnClick", function(self) set(not get()); self:Update() end)
    b:Update()
    return b
end

-------------------------------------------------------------------------------
-- Виртуальный список с прокруткой
-------------------------------------------------------------------------------
local function CreateList(parent, rowHeight, createRow, updateRow)
    local f = CreateFrame("Frame", nil, parent)
    f.rows, f.data, f.offset, f.visibleRows = {}, {}, 0, 0
    f:SetClipsChildren(true)

    local sb = CreateFrame("Slider", nil, f)
    sb:SetOrientation("VERTICAL")
    sb:SetWidth(5)
    sb:SetPoint("TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", 0, 0)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)
    sb:SetThumbTexture(WHITE)
    local thumb = sb:GetThumbTexture()
    thumb:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.6)
    thumb:SetSize(5, 40)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetValue(0)
    f.scroll = sb

    sb:SetScript("OnValueChanged", function(_, v)
        local o = math.floor(v + 0.5)
        if o ~= f.offset then f.offset = o; f:Refresh() end
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        sb:SetValue(sb:GetValue() - d * 3)
    end)

    function f:UpdateRange()
        local maxOff = math.max(0, #self.data - self.visibleRows)
        sb:SetMinMaxValues(0, maxOff)
        if self.offset > maxOff then self.offset = maxOff; sb:SetValue(maxOff) end
        sb:SetShown(maxOff > 0)
        local h = self:GetHeight()
        if #self.data > 0 then
            thumb:SetHeight(math.max(24, h * math.min(1, self.visibleRows / #self.data)))
        end
    end

    function f:Layout()
        local n = math.floor((self:GetHeight() or 0) / rowHeight)
        for i = 1, n do
            if not self.rows[i] then
                local row = createRow(self)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("RIGHT", -8, 0)
                if row.zebra then row.zebra:SetShown(i % 2 == 0) end
                self.rows[i] = row
            end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
        self.visibleRows = n
        self:UpdateRange()
        self:Refresh()
    end

    function f:SetData(d, keepOffset)
        self.data = d or {}
        if not keepOffset then self.offset = 0; sb:SetValue(0) end
        self:UpdateRange()
        self:Refresh()
    end

    function f:Refresh()
        for i = 1, self.visibleRows do
            local row = self.rows[i]
            local item = self.data[i + self.offset]
            if item then
                row.item = item
                updateRow(row, item, i + self.offset)
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
    end

    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    f:SetScript("OnShow", function(self) self:Layout() end)
    return f
end

local function BaseRow(list, clickable)
    local row = CreateFrame("Button", nil, list)
    row.zebra = row:CreateTexture(nil, "BACKGROUND")
    row.zebra:SetAllPoints()
    row.zebra:SetColorTexture(1, 1, 1, 0.025)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.08)
    if clickable then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    return row
end

-- Колонки статусов персонажей справа в строке
local function AddStatusCols(row)
    row.cols = {}
    for i = 1, MAX_COLS do
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(14, 14)
        tex:SetPoint("RIGHT", row, "RIGHT", -((MAX_COLS - i) * COL_W) - (COL_W - 14) / 2, 0)
        local dash = Text(row, "GameFontDisableSmall", 11, C.dim, "CENTER")
        dash:SetPoint("CENTER", tex, "CENTER")
        dash:SetText("-")
        row.cols[i] = { tex = tex, dash = dash }
    end
end

local function UpdateStatusCols(row, chars, questID)
    for i = 1, MAX_COLS do
        local col = row.cols[i]
        local full = chars[i]
        if full then
            local st = QW.QuestStatus(full, questID)
            if st == "done" then
                col.tex:SetTexture(ICON_DONE); col.tex:Show(); col.dash:Hide()
            elseif st == "active" then
                col.tex:SetTexture(ICON_ACTIVE); col.tex:Show(); col.dash:Hide()
            else
                col.tex:Hide(); col.dash:Show()
            end
        else
            col.tex:Hide(); col.dash:Hide()
        end
    end
end

-- Шапка с именами персонажей над колонками
local function CreateColHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(20)
    h.labels = {}
    for i = 1, MAX_COLS do
        local t = Text(h, "GameFontNormalSmall", 10, C.dim, "CENTER")
        t:SetWidth(COL_W)
        t:SetPoint("RIGHT", h, "RIGHT", -((MAX_COLS - i) * COL_W) - 8, 0)
        h.labels[i] = t
    end
    function h:SetChars(chars)
        for i = 1, MAX_COLS do
            if chars[i] then
                self.labels[i]:SetText(QW.ColoredName(chars[i], true))
                self.labels[i]:Show()
            else
                self.labels[i]:Hide()
            end
        end
    end
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetColorTexture(unpack(C.line))
    return h
end

-- "[10-14] " для списка квестов (цепочки) или пустая строка
function UI.LevelRange(quests)
    local lo, hi
    for _, q in ipairs(quests) do
        local l = QW.GetQuestLevel(q)
        if l then
            lo = (not lo or l < lo) and l or lo
            hi = (not hi or l > hi) and l or hi
        end
    end
    if not lo then return "" end
    return "|cff999999[" .. (lo == hi and lo or (lo .. "-" .. hi)) .. "]|r "
end

-------------------------------------------------------------------------------
-- Подсказка по квесту
-------------------------------------------------------------------------------
local function ShowQuestTooltip(owner, questID, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. questID)
    if not ok or GameTooltip:NumLines() == 0 then
        GameTooltip:SetText(QW.TitleOrID(questID), 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("ID: " .. questID, 0.6, 0.6, 0.6)
    local q = QW.QuestieInfo(questID)
    if q then
        local lvl, req = tonumber(q.questLevel or q.level), tonumber(q.requiredLevel)
        if lvl or req then
            GameTooltip:AddLine("Уровень квеста: " .. (lvl or "?") .. (req and ("  (взять можно с " .. req .. ")") or ""), 0.8, 0.8, 0.8)
        end
    end
    if QW.QuestStatus(QW.me, questID) == nil then
        local doable = QW.IsDoable(questID)
        if doable == true then
            GameTooltip:AddLine("Можно взять сейчас", 0.35, 0.9, 0.45)
        elseif doable == false then
            local why = QW.DoableText(questID)
            GameTooltip:AddLine("Сейчас взять нельзя" .. (why and (": " .. why) or ""), 1, 0.45, 0.45, true)
        end
    end
    for _, full in ipairs(UI.VisibleChars()) do
        local st = QW.QuestStatus(full, questID)
        local s = st == "done" and "|cff5ce673выполнен|r" or st == "active" and "|cffffd100в процессе|r" or "|cff888888нет|r"
        GameTooltip:AddDoubleLine(QW.ColoredName(full), s)
    end
    if extra then extra(GameTooltip) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100ЛКМ|r — линк в чат   |cffffd100ПКМ|r — цепочка", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Видимые персонажи (колонки)
-------------------------------------------------------------------------------
function UI.IsCharShown(full)
    local vis = QW.db.settings.visible
    if vis and vis[full] ~= nil then return vis[full] end
    return full == QW.me or QW.IsPartner(full)
end

function UI.SetCharShown(full, v)
    QW.db.settings.visible = QW.db.settings.visible or {}
    QW.db.settings.visible[full] = v
end

-- Все известные персонажи: я, друзья, мои альты
function UI.AllChars()
    local out, seen = {}, {}
    local function add(f) if f and not seen[f] then seen[f] = true; out[#out + 1] = f end end
    add(QW.me)
    for _, p in ipairs(QW.db.settings.partners) do add(p) end
    local alts = {}
    for full, ch in pairs(QW.db.chars) do
        if ch.own and full ~= QW.me then alts[#alts + 1] = full end
    end
    table.sort(alts)
    for _, a in ipairs(alts) do add(a) end
    return out
end

function UI.VisibleChars()
    local out = {}
    for _, full in ipairs(UI.AllChars()) do
        if UI.IsCharShown(full) and #out < MAX_COLS then out[#out + 1] = full end
    end
    return out
end

-------------------------------------------------------------------------------
-- Главное окно
-------------------------------------------------------------------------------
local frame
local tabs, pages = {}, {}
local currentTab

local function MapName(mapID)
    if not mapID or mapID == 0 then return "" end
    UI.mapCache = UI.mapCache or {}
    if UI.mapCache[mapID] == nil then
        local info = C_Map.GetMapInfo(mapID)
        UI.mapCache[mapID] = info and info.name or ""
    end
    return UI.mapCache[mapID]
end

local ULower = QW.ULower

local function MatchSearch(text, ...)
    if not text or text == "" then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and ULower(tostring(v)):find(text, 1, true) then return true end
    end
    return false
end

local function OnQuestRowClick(row, button)
    local id = row.item and row.item.id
    if not id then return end
    if button == "RightButton" then
        UI.ShowChainFor(id)
    else
        QW.LinkQuest(id)
    end
end

---------------------------------------------------------------------------
-- Боковая панель: персонажи
---------------------------------------------------------------------------
local sidebarRows = {}

local function UpdateSidebar()
    if not frame then return end
    local chars = UI.AllChars()
    local sb = frame.sidebar
    for i, full in ipairs(chars) do
        local r = sidebarRows[i]
        if not r then
            r = CreateFrame("Button", nil, sb, "BackdropTemplate")
            r:SetHeight(44)
            r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 48)
            r:SetPoint("RIGHT", -8, 0)
            SetBD(r, C.panel2, C.panel2)
            r.bar = r:CreateTexture(nil, "ARTWORK")
            r.bar:SetPoint("TOPLEFT", 1, -1); r.bar:SetPoint("BOTTOMLEFT", 1, 1); r.bar:SetWidth(3)
            r.bar:SetTexture(WHITE)
            r.name = Text(r, "GameFontNormal", 13, C.text)
            r.name:SetPoint("TOPLEFT", 12, -7)
            r.name:SetPoint("RIGHT", -24, 0)
            r.info = Text(r, "GameFontDisableSmall", 10, C.dim)
            r.info:SetPoint("BOTTOMLEFT", 12, 7)
            r.info:SetPoint("RIGHT", -6, 0)
            r.dot = r:CreateTexture(nil, "OVERLAY")
            r.dot:SetSize(14, 14)
            r.dot:SetPoint("TOPRIGHT", -6, -6)
            r:SetScript("OnClick", function(self)
                UI.SetCharShown(self.full, not UI.IsCharShown(self.full))
                UI.RefreshAll()
            end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(QW.ColoredName(self.full))
                local ch = QW.db.chars[self.full] or {}
                GameTooltip:AddLine(self.full, 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Выполнено квестов: " .. (ch.doneCount or 0), 1, 1, 1)
                GameTooltip:AddLine("В ленте (с аддоном): " .. #(ch.history or {}), 1, 1, 1)
                if ch.updated and ch.updated > 0 then
                    GameTooltip:AddLine("Обновлено: " .. date("%d.%m %H:%M", ch.updated), 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Клик — показать/скрыть колонку", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            sidebarRows[i] = r
        end
        r.full = full
        local ch = QW.db.chars[full] or {}
        local cr, cg, cb = QW.ClassRGB(ch.class)
        r.bar:SetVertexColor(cr, cg, cb)
        local tag = ""
        if full == QW.me then tag = " |cff888888(я)|r"
        elseif ch.own then tag = " |cff888888(альт)|r"
        else tag = " |cff66ccff(друг)|r" end
        r.name:SetText(QW.ColoredName(full) .. tag)
        local prog = QW.Comm.progress[full]
        local info = (ch.level and ch.level > 0 and ("ур. " .. ch.level .. "  /  ") or "") .. (ch.doneCount or 0) .. " квестов"
        if prog and prog.total and prog.got < prog.total then
            info = string.format("синхронизация %d/%d...", prog.got, prog.total)
        end
        r.info:SetText(info)
        if full == QW.me or ch.own then
            r.dot:Hide()
        else
            r.dot:SetTexture(QW.Comm.IsOnline(full) and ICON_ONLINE or ICON_OFFLINE)
            r.dot:Show()
        end
        local shown = UI.IsCharShown(full)
        r:SetAlpha(shown and 1 or 0.45)
        r:SetBackdropBorderColor(unpack(shown and { cr * 0.6, cg * 0.6, cb * 0.6, 1 } or C.panel2))
        r:Show()
    end
    for i = #chars + 1, #sidebarRows do sidebarRows[i]:Hide() end
    frame.addHint:SetShown(#QW.db.settings.partners == 0)
end

---------------------------------------------------------------------------
-- Вкладка "Лента"
---------------------------------------------------------------------------
local function BuildFeedPage(page)
    page.header = CreateColHeader(page)
    page.header:SetPoint("TOPLEFT", 0, 0)
    page.header:SetPoint("TOPRIGHT", 0, 0)
    local hTitle = Text(page.header, "GameFontNormalSmall", 10, C.dim)
    hTitle:SetPoint("LEFT", 8, 0)
    hTitle:SetText("КОГДА  /  КТО  /  КВЕСТ")

    page.list = CreateList(page, 30, function(list)
        local row = BaseRow(list, true)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT", 0, -4); row.bar:SetPoint("BOTTOMLEFT", 0, 4); row.bar:SetWidth(3)
        row.bar:SetTexture(WHITE)
        row.when = Text(row, "GameFontDisableSmall", 10, C.dim)
        row.when:SetPoint("LEFT", 10, 0); row.when:SetWidth(70)
        row.who = Text(row, "GameFontNormalSmall", 11)
        row.who:SetPoint("LEFT", 80, 0); row.who:SetWidth(90)
        row.title = Text(row, "GameFontNormal", 12, C.gold)
        row.title:SetPoint("LEFT", 172, 5)
        row.title:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 4, 5)
        row.sub = Text(row, "GameFontDisableSmall", 10, C.dim)
        row.sub:SetPoint("LEFT", 172, -8)
        row.sub:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 4, -8)
        AddStatusCols(row)
        row:SetScript("OnClick", OnQuestRowClick)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            local it = self.item
            ShowQuestTooltip(self, it.id, function(tt)
                tt:AddLine(" ")
                tt:AddLine(QW.ColoredName(it.who) .. "  /  " .. date("%d.%m.%Y %H:%M", it.t), 1, 1, 1)
            end)
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, it)
        local ch = QW.db.chars[it.who] or {}
        row.bar:SetVertexColor(QW.ClassRGB(ch.class))
        row.when:SetText(date("%d.%m  %H:%M", it.t))
        row.who:SetText(QW.ColoredName(it.who, true))
        row.title:SetText(QW.LevelTag(it.id) .. QW.TitleOrID(it.id))
        local sub = MapName(it.map)
        if it.lvl and it.lvl > 0 then sub = (sub ~= "" and (sub .. "  /  ") or "") .. "твой ур. " .. it.lvl end
        row.sub:SetText(sub)
        UpdateStatusCols(row, UI.cols, it.id)
    end)
    page.list:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -2)
    page.list:SetPoint("BOTTOMRIGHT", 0, 0)

    page.empty = Text(page, "GameFontDisable", 13, C.dim, "CENTER")
    page.empty:SetPoint("CENTER")
    page.empty:SetWidth(420)
    page.empty:SetWordWrap(true)
    page.empty:SetText("Лента пуста.\nСдавай квесты — каждый будет записан сюда со временем и зоной.\nКвесты друга появятся после синхронизации.")

    function page:Refresh()
        local search = UI.search
        local data = {}
        for _, full in ipairs(UI.cols) do
            local ch = QW.db.chars[full]
            if ch then
                for _, e in ipairs(ch.history) do
                    local id = e[1]
                    if MatchSearch(search, id, QW.GetTitle(id, true), MapName(e[3])) then
                        data[#data + 1] = { id = id, t = e[2], map = e[3], lvl = e[4], who = full }
                    end
                end
            end
        end
        table.sort(data, function(a, b) return a.t > b.t end)
        self.header:SetChars(UI.cols)
        self.list:SetData(data, true)
        self.empty:SetShown(#data == 0)
        UI.SetStatus(#data .. " записей в ленте")
    end
end

---------------------------------------------------------------------------
-- Вкладка "Цепочки"
---------------------------------------------------------------------------
local function BuildChainsPage(page)
    -- Левая колонка: список цепочек
    local left = CreateFrame("Frame", nil, page, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(270)
    SetBD(left, C.panel, C.panel)
    page.left = left

    local lt = Text(left, "GameFontNormalSmall", 10, C.dim)
    lt:SetPoint("TOPLEFT", 10, -8)
    lt:SetText("ЦЕПОЧКИ")
    page.leftCount = Text(left, "GameFontDisableSmall", 10, C.dim, "RIGHT")
    page.leftCount:SetPoint("TOPRIGHT", -12, -8)

    -- Фильтр пройденных цепочек: все -> скрыть пройденные мной -> скрыть пройденные всеми
    local FILTERS = {
        { key = "all",      label = "Пройденные: показаны" },
        { key = "mine",     label = "Скрыты пройденные мной" },
        { key = "everyone", label = "Скрыты пройденные всеми" },
    }
    page.filterBtn = FlatButton(left, "", 250, 22)
    page.filterBtn:SetPoint("TOPLEFT", 10, -26)
    page.filterBtn.tip = "Клик - переключить, какие завершённые цепочки скрывать.\n"
        .. "\"Всеми\" - скрыть, только если цепочку прошли все показанные игроки."
    function page.filterBtn:UpdateLabel()
        local cur = QW.db.settings.chainFilter or "all"
        for _, f in ipairs(FILTERS) do
            if f.key == cur then
                self:SetLabel(f.label)
                self.text:SetTextColor(cur == "all" and C.text[1] or C.gold[1],
                    cur == "all" and C.text[2] or C.gold[2], cur == "all" and C.text[3] or C.gold[3])
            end
        end
    end
    page.filterBtn:SetScript("OnClick", function(self)
        local cur = QW.db.settings.chainFilter or "all"
        local idx = 1
        for i, f in ipairs(FILTERS) do if f.key == cur then idx = i end end
        QW.db.settings.chainFilter = FILTERS[idx % #FILTERS + 1].key
        self:UpdateLabel()
        page:ApplyFilter()
    end)

    page.chainList = CreateList(left, 40, function(list)
        local row = BaseRow(list, true)
        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.12)
        row.name = Text(row, "GameFontNormal", 12, C.text)
        row.name:SetPoint("TOPLEFT", 10, -5)
        row.name:SetPoint("RIGHT", -40, 0)
        row.count = Text(row, "GameFontDisableSmall", 10, C.dim, "RIGHT")
        row.count:SetPoint("TOPRIGHT", -6, -6)
        row.bars = {}
        for i = 1, MAX_COLS do
            local bg = row:CreateTexture(nil, "ARTWORK")
            bg:SetHeight(4)
            bg:SetColorTexture(1, 1, 1, 0.07)
            local fg = row:CreateTexture(nil, "OVERLAY")
            fg:SetHeight(4)
            fg:SetTexture(WHITE)
            fg:SetPoint("LEFT", bg, "LEFT")
            row.bars[i] = { bg = bg, fg = fg }
        end
        row:SetScript("OnSizeChanged", function(self, w)
            local n = self.nBars or 1
            local avail = (w or self:GetWidth()) - 20
            local bw = (avail - (n - 1) * 6) / n
            for i = 1, MAX_COLS do
                local b = self.bars[i]
                b.bg:ClearAllPoints()
                b.bg:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (bw + 6), 7)
                b.bg:SetWidth(math.max(1, bw))
                b.bw = bw
            end
        end)
        row:SetScript("OnClick", function(self, button)
            if not self.item then return end
            if button == "RightButton" then
                QW.LinkQuest(self.item.quests[1])
            else
                UI.SelectChain(self.item)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.item.name, 1, 0.82, 0)
            GameTooltip:AddLine(#self.item.quests .. " квестов  /  источник: " ..
                (self.item.source == "questline" and "клиент игры" or "Questie"), 0.7, 0.7, 0.7)
            for _, full in ipairs(UI.cols) do
                local d, n = QW.ChainProgress(full, self.item)
                GameTooltip:AddDoubleLine(QW.ColoredName(full), d .. " / " .. n, 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100ЛКМ|r — открыть   |cffffd100ПКМ|r — линк первого квеста", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, chain)
        row.name:SetText(UI.LevelRange(chain.quests) .. chain.name)
        row.count:SetText(#chain.quests)
        row.sel:SetShown(UI.selectedChain and UI.selectedChain.key == chain.key)
        local n = math.max(1, #UI.cols)
        if row.nBars ~= n then
            row.nBars = n
            row:GetScript("OnSizeChanged")(row, row:GetWidth())
        end
        for i = 1, MAX_COLS do
            local b, full = row.bars[i], UI.cols[i]
            if full then
                local d, total = QW.ChainProgress(full, chain)
                local ch = QW.db.chars[full] or {}
                b.fg:SetVertexColor(QW.ClassRGB(ch.class))
                b.fg:SetWidth(math.max(0.01, (b.bw or 50) * d / math.max(1, total)))
                b.fg:SetShown(d > 0)
                b.bg:Show()
            else
                b.bg:Hide(); b.fg:Hide()
            end
        end
    end)
    page.chainList:SetPoint("TOPLEFT", 4, -58)
    page.chainList:SetPoint("BOTTOMRIGHT", -2, 4)

    page.leftEmpty = Text(left, "GameFontDisableSmall", 11, C.dim, "CENTER")
    page.leftEmpty:SetPoint("CENTER")
    page.leftEmpty:SetWidth(230)
    page.leftEmpty:SetWordWrap(true)

    -- Правая часть: шаги выбранной цепочки
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    page.right = right

    page.chainTitle = Text(right, "GameFontNormalLarge", 17, C.gold)
    page.chainTitle:SetPoint("TOPLEFT", 4, -2)
    page.chainTitle:SetPoint("RIGHT", -4, 0)
    page.chainSub = Text(right, "GameFontDisableSmall", 11, C.dim)
    page.chainSub:SetPoint("TOPLEFT", page.chainTitle, "BOTTOMLEFT", 0, -4)
    page.chainSub:SetPoint("RIGHT", -4, 0)

    page.btnLinkAll = FlatButton(right, "Линк цепочки в чат", 150, 24, true)
    page.btnLinkAll:SetPoint("TOPLEFT", page.chainSub, "BOTTOMLEFT", 0, -10)
    page.btnLinkAll.tip = "Вставляет линки квестов цепочки в поле чата.\nЕсли не влезает в одно сообщение — жми ещё раз для следующей части."
    page.btnLinkAll:SetScript("OnClick", function(self)
        local chain = UI.selectedChain
        if not chain then return end
        local nxt = QW.LinkMany(chain.quests, self.nextIndex or 1)
        self.nextIndex = nxt
        if nxt then
            self:SetLabel(string.format("Дальше (с %d из %d)", nxt, #chain.quests))
        else
            self:SetLabel("Линк цепочки в чат")
        end
    end)

    page.btnLinkNext = FlatButton(right, "Мой следующий квест", 150, 24)
    page.btnLinkNext:SetPoint("LEFT", page.btnLinkAll, "RIGHT", 8, 0)
    page.btnLinkNext.tip = "Линк первого квеста цепочки, который ты ещё не сдал."
    page.btnLinkNext:SetScript("OnClick", function()
        local chain = UI.selectedChain
        if not chain then return end
        for _, q in ipairs(chain.quests) do
            if QW.QuestStatus(QW.me, q) ~= "done" then QW.LinkQuest(q) return end
        end
        QW.Print("Цепочка полностью пройдена!")
    end)

    page.btnLinkFriend = FlatButton(right, "Где друг?", 110, 24)
    page.btnLinkFriend:SetPoint("LEFT", page.btnLinkNext, "RIGHT", 8, 0)
    page.btnLinkFriend.tip = "Вставляет в чат, на каком шаге цепочки каждый игрок."
    page.btnLinkFriend:SetScript("OnClick", function()
        local chain = UI.selectedChain
        if not chain then return end
        local parts = {}
        for _, full in ipairs(UI.cols) do
            local d, n = QW.ChainProgress(full, chain)
            parts[#parts + 1] = QW.ShortName(full) .. " " .. d .. "/" .. n
        end
        QW.InsertIntoChat(table.concat(parts, ", ") .. " ")
    end)

    page.stepHeader = CreateColHeader(right)
    page.stepHeader:SetPoint("TOPLEFT", page.btnLinkAll, "BOTTOMLEFT", 0, -12)
    page.stepHeader:SetPoint("RIGHT", 0, 0)
    local sh = Text(page.stepHeader, "GameFontNormalSmall", 10, C.dim)
    sh:SetPoint("LEFT", 8, 0)
    sh:SetText("ШАГ  /  КВЕСТ")

    page.stepList = CreateList(right, 28, function(list)
        local row = BaseRow(list, true)
        row.num = Text(row, "GameFontNormalSmall", 11, C.dim, "RIGHT")
        row.num:SetPoint("LEFT", 2, 0); row.num:SetWidth(24)
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetWidth(2)
        row.line:SetPoint("TOP", row, "TOPLEFT", 36, 0)
        row.line:SetPoint("BOTTOM", row, "BOTTOMLEFT", 36, 0)
        row.line:SetColorTexture(1, 1, 1, 0.08)
        row.node = row:CreateTexture(nil, "OVERLAY")
        row.node:SetSize(8, 8)
        row.node:SetPoint("CENTER", row, "LEFT", 36, 0)
        row.node:SetTexture(WHITE)
        row.title = Text(row, "GameFontNormal", 12, C.gold)
        row.title:SetPoint("LEFT", 48, 0)
        row.title:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 4, 0)
        AddStatusCols(row)
        row:SetScript("OnClick", function(self, button)
            if self.item and button == "LeftButton" then QW.LinkQuest(self.item.id) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.item then ShowQuestTooltip(self, self.item.id) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, it, index)
        row.num:SetText(index)
        row.title:SetText(QW.LevelTag(it.id) .. QW.TitleOrID(it.id))
        local st = QW.QuestStatus(QW.me, it.id)
        if st == "done" then
            row.node:SetVertexColor(C.green[1], C.green[2], C.green[3])
            row.title:SetTextColor(0.75, 0.75, 0.75)
        elseif st == "active" then
            row.node:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
            row.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        else
            row.node:SetVertexColor(0.35, 0.35, 0.4)
            row.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        end
        row.title:SetText(QW.LevelTag(it.id) .. QW.TitleOrID(it.id) .. (it.id == UI.focusQuest and "  |cff66ccff<<|r" or ""))
        UpdateStatusCols(row, UI.cols, it.id)
    end)
    page.stepList:SetPoint("TOPLEFT", page.stepHeader, "BOTTOMLEFT", 0, -2)
    page.stepList:SetPoint("BOTTOMRIGHT", 0, 0)

    page.rightEmpty = Text(right, "GameFontDisable", 13, C.dim, "CENTER")
    page.rightEmpty:SetPoint("CENTER")
    page.rightEmpty:SetWidth(380)
    page.rightEmpty:SetWordWrap(true)
    page.rightEmpty:SetText("Выбери цепочку слева\nили нажми ПКМ на квест в 'Ленте'.")

    function page:ShowChain(chain)
        local has = chain ~= nil
        for _, w in ipairs({ self.chainTitle, self.chainSub, self.btnLinkAll, self.btnLinkNext,
            self.btnLinkFriend, self.stepHeader, self.stepList }) do
            w:SetShown(has)
        end
        self.rightEmpty:SetShown(not has)
        if not has then self.shownKey = nil return end
        local same = self.shownKey == chain.key
        self.shownKey = chain.key
        if not same then
            self.btnLinkAll.nextIndex = nil
            self.btnLinkAll:SetLabel("Линк цепочки в чат")
        end
        self.chainTitle:SetText(UI.LevelRange(chain.quests) .. chain.name)
        local src = chain.source == "questline" and "клиент игры (C_QuestLine)"
            or chain.source == "questie" and "база Questie" or "одиночный квест — цепочка не найдена"
        local prog = {}
        for _, full in ipairs(UI.cols) do
            local d, n = QW.ChainProgress(full, chain)
            prog[#prog + 1] = QW.ColoredName(full) .. " |cffffffff" .. d .. "/" .. n .. "|r"
        end
        self.chainSub:SetText(#chain.quests .. " квестов  /  " .. src .. "     " .. table.concat(prog, "   "))
        self.stepHeader:SetChars(UI.cols)
        local data = {}
        for _, q in ipairs(chain.quests) do data[#data + 1] = { id = q } end
        QW.RequestTitles(chain.quests)
        self.stepList:SetData(data, same)
    end

    function page:Refresh()
        self.stepHeader:SetChars(UI.cols)
        if not self.chains or self.dirty then
            self.dirty = false
            self.leftEmpty:SetText("Собираю цепочки...")
            self.leftEmpty:Show()
            QW.BuildChains(UI.cols, function(found)
                table.sort(found, function(a, b)
                    -- Сначала незаконченные (у меня), потом по названию
                    local da, na = QW.ChainProgress(QW.me, a)
                    local db, nb = QW.ChainProgress(QW.me, b)
                    local fa, fb = da >= na, db >= nb
                    if fa ~= fb then return not fa end
                    return (a.name or "") < (b.name or "")
                end)
                self.chains = found
                self:ApplyFilter()
            end)
        else
            self:ApplyFilter()
        end
        self:ShowChain(UI.selectedChain)
    end

    -- Пройдена ли цепочка с учётом фильтра
    local function IsHiddenByFilter(chain)
        local mode = QW.db.settings.chainFilter or "all"
        if mode == "mine" then
            local d, n = QW.ChainProgress(QW.me, chain)
            return d >= n
        elseif mode == "everyone" then
            for _, full in ipairs(UI.cols) do
                local d, n = QW.ChainProgress(full, chain)
                if d < n then return false end
            end
            return #UI.cols > 0
        end
        return false
    end

    function page:ApplyFilter()
        self.filterBtn:UpdateLabel()
        local list, hidden = {}, 0
        for _, ch in ipairs(self.chains or {}) do
            local match = MatchSearch(UI.search, ch.name)
            if not match and UI.search and UI.search ~= "" then
                for _, q in ipairs(ch.quests) do
                    if MatchSearch(UI.search, q, QW.GetTitle(q, true)) then match = true break end
                end
            end
            if match and IsHiddenByFilter(ch) then
                hidden = hidden + 1
            elseif match then
                list[#list + 1] = ch
            end
        end
        self.chainList:SetData(list, true)
        self.leftCount:SetText(#list .. (hidden > 0 and (" |cff666666(+" .. hidden .. " скрыто)|r") or ""))
        if #list == 0 and hidden > 0 then
            self.leftEmpty:SetText("Все цепочки пройдены и скрыты фильтром.\nНажми на кнопку фильтра сверху, чтобы показать их.")
            self.leftEmpty:Show()
        elseif #list == 0 then
            self.leftEmpty:SetText(QW.HasQuestie()
                and "Цепочек пока нет.\nОни появятся, когда вы начнёте сдавать квесты из цепочек."
                or "Цепочки не найдены.\n\nИнформацию о цепочках даёт клиент игры, а для классических квестов — аддон |cffffd100Questie|r (если установлен).")
            self.leftEmpty:Show()
        else
            self.leftEmpty:Hide()
        end
        UI.SetStatus(#list .. " цепочек" .. (hidden > 0 and ("  /  скрыто пройденных: " .. hidden) or ""))
    end
end

---------------------------------------------------------------------------
-- Вкладка "Зоны": континент -> зона -> квесты / цепочки
---------------------------------------------------------------------------
local OTHER_CONT = "Другое"
local ZONE_MODES = {
    { key = "all",    label = "Все квесты" },
    { key = "notme",  label = "Не сделано мной" },
    { key = "avail",  label = "Можно взять" },
    { key = "chains", label = "Цепочки зоны" },
}

local function ProgressBars(row)
    row.bars = {}
    for i = 1, MAX_COLS do
        local bg = row:CreateTexture(nil, "ARTWORK")
        bg:SetHeight(3)
        bg:SetColorTexture(1, 1, 1, 0.07)
        local fg = row:CreateTexture(nil, "OVERLAY")
        fg:SetHeight(3)
        fg:SetTexture(WHITE)
        fg:SetPoint("LEFT", bg, "LEFT")
        row.bars[i] = { bg = bg, fg = fg }
    end
    function row:LayoutBars(n)
        local avail = self:GetWidth() - 24
        local bw = math.max(1, (avail - (n - 1) * 5) / n)
        for i = 1, MAX_COLS do
            local b = self.bars[i]
            b.bg:ClearAllPoints()
            b.bg:SetPoint("BOTTOMLEFT", 14 + (i - 1) * (bw + 5), 4)
            b.bg:SetWidth(bw)
            b.bw = bw
        end
    end
    function row:SetBars(values, total)
        local n = math.max(1, #UI.cols)
        if self.nBars ~= n or self.lastW ~= self:GetWidth() then
            self.nBars, self.lastW = n, self:GetWidth()
            self:LayoutBars(n)
        end
        for i = 1, MAX_COLS do
            local b, full = self.bars[i], UI.cols[i]
            if full and values then
                local ch = QW.db.chars[full] or {}
                b.fg:SetVertexColor(QW.ClassRGB(ch.class))
                b.fg:SetWidth(math.max(0.01, b.bw * (values[i] or 0) / math.max(1, total)))
                b.fg:SetShown((values[i] or 0) > 0)
                b.bg:Show()
            else
                b.bg:Hide(); b.fg:Hide()
            end
        end
    end
end

local function BuildZonesPage(page)
    local left = CreateFrame("Frame", nil, page, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(250)
    SetBD(left, C.panel, C.panel)

    local lt = Text(left, "GameFontNormalSmall", 10, C.dim)
    lt:SetPoint("TOPLEFT", 10, -8)
    lt:SetText("КОНТИНЕНТЫ И ЗОНЫ")
    page.leftCount = Text(left, "GameFontDisableSmall", 10, C.dim, "RIGHT")
    page.leftCount:SetPoint("TOPRIGHT", -12, -8)

    local here = FlatButton(left, "Моя текущая зона", 230, 22, true)
    here:SetPoint("TOPLEFT", 10, -26)
    here:SetScript("OnClick", function()
        local z = QW.CurrentZoneName()
        if z then UI.selectedZone = z; page:Refresh() end
    end)

    page.zoneList = CreateList(left, 30, function(list)
        local row = BaseRow(list, true)
        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.12)
        row.name = Text(row, "GameFontNormal", 12, C.text)
        row.name:SetPoint("LEFT", 14, 3)
        row.name:SetPoint("RIGHT", -40, 3)
        row.count = Text(row, "GameFontDisableSmall", 10, C.dim, "RIGHT")
        row.count:SetPoint("RIGHT", -8, 3)
        ProgressBars(row)
        row:SetScript("OnClick", function(self)
            if self.item and not self.item.header then
                UI.selectedZone = self.item.name
                page:ShowZone()
                page.zoneList:Refresh()
            end
        end)
        return row
    end, function(row, it)
        if it.header then
            row.name:SetText(it.name)
            row.name:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            row.name:SetPoint("LEFT", 6, 0)
            row.count:SetText("")
            row.sel:Hide()
            row.zebra:SetAlpha(0)
            row:EnableMouse(false)
            row:SetBars(nil, 1)
        else
            row.name:SetText(it.name)
            row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
            row.name:SetPoint("LEFT", 14, 3)
            row.count:SetText(#it.quests)
            row.sel:SetShown(UI.selectedZone == it.name)
            row.zebra:SetAlpha(1)
            row:EnableMouse(true)
            local vals = {}
            for i, full in ipairs(UI.cols) do
                local n = 0
                for _, q in ipairs(it.quests) do
                    if QW.QuestStatus(full, q) == "done" then n = n + 1 end
                end
                vals[i] = n
            end
            row:SetBars(vals, #it.quests)
        end
    end)
    page.zoneList:SetPoint("TOPLEFT", 4, -54)
    page.zoneList:SetPoint("BOTTOMRIGHT", -2, 4)

    page.leftEmpty = Text(left, "GameFontDisableSmall", 11, C.dim, "CENTER")
    page.leftEmpty:SetPoint("CENTER")
    page.leftEmpty:SetWidth(220)
    page.leftEmpty:SetWordWrap(true)

    -- Правая часть
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    page.title = Text(right, "GameFontNormalLarge", 17, C.gold)
    page.title:SetPoint("TOPLEFT", 4, -2)
    page.title:SetPoint("RIGHT", -4, 0)
    page.sub = Text(right, "GameFontDisableSmall", 11, C.dim)
    page.sub:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
    page.sub:SetPoint("RIGHT", -4, 0)

    page.mode = "all"
    page.modeButtons = {}
    local prev
    for _, m in ipairs(ZONE_MODES) do
        local b = FlatButton(right, m.label, 112, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", page.sub, "BOTTOMLEFT", 0, -10) end
        b.key = m.key
        b:SetScript("OnClick", function() page.mode = m.key; page:ShowZone() end)
        page.modeButtons[#page.modeButtons + 1] = b
        prev = b
    end

    page.header = CreateColHeader(right)
    page.header:SetPoint("TOPLEFT", page.modeButtons[1], "BOTTOMLEFT", 0, -10)
    page.header:SetPoint("RIGHT", 0, 0)
    page.headerText = Text(page.header, "GameFontNormalSmall", 10, C.dim)
    page.headerText:SetPoint("LEFT", 8, 0)

    page.list = CreateList(right, 26, function(list)
        local row = BaseRow(list, true)
        row.avail = row:CreateTexture(nil, "OVERLAY")
        row.avail:SetSize(14, 14)
        row.avail:SetPoint("LEFT", 6, 0)
        row.avail:SetTexture(ICON_AVAILABLE)
        row.title = Text(row, "GameFontNormal", 12, C.gold)
        row.title:SetPoint("LEFT", 24, 0)
        row.title:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 70, 0)
        row.id = Text(row, "GameFontDisableSmall", 10, C.dim, "RIGHT")
        row.id:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 6, 0)
        row.id:SetWidth(60)
        AddStatusCols(row)
        row.prog = {}
        for i = 1, MAX_COLS do
            local t = Text(row, "GameFontHighlightSmall", 11, C.text, "CENTER")
            t:SetWidth(COL_W)
            t:SetPoint("RIGHT", row, "RIGHT", -((MAX_COLS - i) * COL_W), 0)
            row.prog[i] = t
        end
        row:SetScript("OnClick", function(self, button)
            local it = self.item
            if not it then return end
            if it.chain then
                if button == "RightButton" then
                    QW.LinkQuest(it.chain.quests[1])
                else
                    UI.focusQuest = nil
                    UI.selectedChain = it.chain
                    UI.SelectTab("chains")
                end
            else
                OnQuestRowClick(self, button)
            end
        end)
        row:SetScript("OnEnter", function(self)
            local it = self.item
            if not it then return end
            if it.chain then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(it.chain.name, 1, 0.82, 0)
                GameTooltip:AddLine(#it.chain.quests .. " квестов", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("|cffffd100ЛКМ|r — открыть цепочку   |cffffd100ПКМ|r — линк первого квеста", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            else
                ShowQuestTooltip(self, it.id)
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, it)
        if it.chain then
            row.avail:Hide()
            row.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            row.title:SetText(UI.LevelRange(it.chain.quests) .. it.chain.name)
            row.id:SetText(#it.chain.quests .. " кв.")
            for i = 1, MAX_COLS do
                local col, full = row.cols[i], UI.cols[i]
                col.tex:Hide(); col.dash:Hide()
                if full then
                    local d, n = QW.ChainProgress(full, it.chain)
                    row.prog[i]:SetText((d >= n and "|cff5ce673" or "|cffffffff") .. d .. "/" .. n .. "|r")
                    row.prog[i]:Show()
                else
                    row.prog[i]:Hide()
                end
            end
        else
            row.title:SetText(QW.LevelTag(it.id) .. QW.TitleOrID(it.id))
            local st = QW.QuestStatus(QW.me, it.id)
            if st == "done" then
                row.title:SetTextColor(0.6, 0.6, 0.6)
            elseif it.fromDB and not st then
                row.title:SetTextColor(0.85, 0.85, 0.85)   -- никто из вас не брал
            else
                row.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            end
            row.avail:SetShown(it.doable == true and st == nil)
            row.id:SetText(it.id)
            for i = 1, MAX_COLS do row.prog[i]:Hide() end
            UpdateStatusCols(row, UI.cols, it.id)
        end
    end)
    page.list:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -2)
    page.list:SetPoint("BOTTOMRIGHT", 0, 0)

    page.rightEmpty = Text(right, "GameFontDisable", 13, C.dim, "CENTER")
    page.rightEmpty:SetPoint("CENTER", 0, -30)
    page.rightEmpty:SetWidth(400)
    page.rightEmpty:SetWordWrap(true)

    local function FindZone(name)
        for _, z in ipairs(page.zones or {}) do
            if z.name == name then return z end
        end
    end

    function page:ShowZone()
        for _, b in ipairs(self.modeButtons) do
            local on = b.key == self.mode
            b.text:SetTextColor(on and C.gold[1] or C.text[1], on and C.gold[2] or C.text[2], on and C.gold[3] or C.text[3])
            b:SetBackdropBorderColor(unpack(on and { 0.55, 0.45, 0.15, 1 } or C.border))
        end
        self.header:SetChars(UI.cols)
        local z = UI.selectedZone and FindZone(UI.selectedZone)
        if not z then
            self.title:SetText(UI.selectedZone or "Выбери зону")
            self.sub:SetText(UI.selectedZone and "Здесь пока нет квестов, которые вы брали или сдавали." or "")
            self.list:SetData({})
            self.rightEmpty:SetText(UI.selectedZone and "" or "Выбери зону слева\nили нажми \"Моя текущая зона\".")
            self.rightEmpty:SetShown(not UI.selectedZone)
            return
        end
        self.title:SetText(z.name)
        local parts = {}
        for _, full in ipairs(UI.cols) do
            local n = 0
            for _, q in ipairs(z.quests) do
                if QW.QuestStatus(full, q) == "done" then n = n + 1 end
            end
            parts[#parts + 1] = QW.ColoredName(full, true) .. " |cffffffff" .. n .. "|r"
        end
        local nDB = 0
        for _ in pairs(z.fromDB or {}) do nDB = nDB + 1 end
        self.sub:SetText((z.cont or OTHER_CONT) .. "  /  " .. #z.quests .. " квестов"
            .. (nDB > 0 and (" |cff888888(" .. nDB .. " из базы Questie)|r") or "")
            .. "  /  " .. table.concat(parts, "   "))

        local data = {}
        if self.mode == "chains" then
            self.headerText:SetText("ЦЕПОЧКА")
            local seen = {}
            for _, q in ipairs(z.quests) do
                local chain = QW.GetChain(q)
                if chain.source ~= "single" and not seen[chain.key] then
                    seen[chain.key] = true
                    if MatchSearch(UI.search, chain.name) then data[#data + 1] = { chain = chain } end
                end
            end
            table.sort(data, function(a, b) return (a.chain.name or "") < (b.chain.name or "") end)
            self.rightEmpty:SetText("В этой зоне цепочки не найдены.")
        else
            self.headerText:SetText("[УР.] КВЕСТ  /  ID")
            QW.RequestTitles(z.quests)
            local hide = QW.db.settings.hideUntitled
            for _, q in ipairs(z.quests) do
                local title = QW.GetTitle(q, true)
                local ok = (title or not hide) and MatchSearch(UI.search, q, title)
                local st = ok and QW.QuestStatus(QW.me, q)
                if ok and self.mode == "notme" and st == "done" then ok = false end
                local doable
                if ok and st == nil then doable = QW.IsDoable(q) end
                if ok and self.mode == "avail" and doable ~= true then ok = false end
                if ok then
                    data[#data + 1] = { id = q, title = title or "", lvl = QW.GetQuestLevel(q),
                        fromDB = z.fromDB[q], doable = doable }
                end
            end
            table.sort(data, function(a, b)
                local la, lb = a.lvl or 999, b.lvl or 999
                if la ~= lb then return la < lb end
                if a.title ~= b.title then return a.title < b.title end
                return a.id < b.id
            end)
            local hasDB = QW.GetQuestieZones() ~= nil
            if self.mode == "notme" then
                self.rightEmpty:SetText(hasDB and "Ты сделал все квесты этой зоны (по базе Questie и вашим данным)."
                    or "Из квестов, которые вы брали, ты сделал всё.\n\nПолного списка квестов зоны нет: база Questie ещё не загрузилась или не найдена.")
            elseif self.mode == "avail" then
                self.rightEmpty:SetText(hasDB and "Сейчас в этой зоне нечего взять.\nКвесты могут требовать уровень или предыдущий квест."
                    or "Список доступных квестов берётся из базы Questie, а она ещё не загрузилась или не найдена.")
            else
                self.rightEmpty:SetText("Здесь пусто.")
            end
        end
        self.list:SetData(data, self.shownZone == z.name and self.shownMode == self.mode)
        self.shownZone, self.shownMode = z.name, self.mode
        self.rightEmpty:SetShown(#data == 0)
    end

    function page:ApplyFilter()
        -- Группируем по континентам
        local byCont, conts = {}, {}
        for _, z in ipairs(self.zones or {}) do
            local c = z.cont or OTHER_CONT
            if MatchSearch(UI.search, z.name, c) or z.name == UI.selectedZone then
                if not byCont[c] then byCont[c] = {}; conts[#conts + 1] = c end
                table.insert(byCont[c], z)
            end
        end
        table.sort(conts, function(a, b)
            if a == OTHER_CONT then return false end
            if b == OTHER_CONT then return true end
            return a < b
        end)
        local list, nz = {}, 0
        for _, c in ipairs(conts) do
            list[#list + 1] = { header = true, name = c }
            table.sort(byCont[c], function(a, b) return a.name < b.name end)
            for _, z in ipairs(byCont[c]) do list[#list + 1] = z; nz = nz + 1 end
        end
        self.zoneList:SetData(list, true)
        self.leftCount:SetText(nz)
        if nz == 0 then
            self.leftEmpty:SetText("Зон пока нет.\nОни появятся, когда вы будете брать и сдавать квесты.")
            self.leftEmpty:Show()
        else
            self.leftEmpty:Hide()
        end
        UI.SetStatus(nz .. " зон")
    end

    function page:Refresh()
        if not self.zones or self.dirty then
            self.dirty = false
            if not self.zones then
                self.leftEmpty:SetText("Собираю зоны...")
                self.leftEmpty:Show()
            end
            QW.BuildZones(UI.cols, function(zones)
                self.zones = zones
                self:ApplyFilter()
                self:ShowZone()
            end)
        else
            self:ApplyFilter()
        end
        self:ShowZone()
    end
end

---------------------------------------------------------------------------
-- Вкладка "Сравнение"
---------------------------------------------------------------------------
local COMPARE_MODES = {
    { key = "onlyA", label = "Есть только у меня" },
    { key = "onlyB", label = "Есть только у друга" },
    { key = "both",  label = "У обоих" },
    { key = "all",   label = "Все" },
}

local function BuildComparePage(page)
    page.mode = "onlyB"
    page.modeButtons = {}
    local prev
    for _, m in ipairs(COMPARE_MODES) do
        local b = FlatButton(page, m.label, 140, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 0, 0) end
        b:SetScript("OnClick", function() page.mode = m.key; page:Refresh() end)
        b.key = m.key
        page.modeButtons[#page.modeButtons + 1] = b
        prev = b
    end

    page.withBtn = FlatButton(page, "С кем: —", 150, 22, true)
    page.withBtn:SetPoint("TOPRIGHT", -2, 0)
    page.withBtn.tip = "Клик — выбрать другого игрока для сравнения"
    page.withBtn:SetScript("OnClick", function()
        local all = UI.AllChars()
        local others = {}
        for _, f in ipairs(all) do if f ~= QW.me then others[#others + 1] = f end end
        if #others == 0 then return end
        local idx = 1
        for i, f in ipairs(others) do if f == page.with then idx = i % #others + 1 end end
        page.with = others[idx]
        page:Refresh()
    end)

    page.header = CreateColHeader(page)
    page.header:SetPoint("TOPLEFT", 0, -30)
    page.header:SetPoint("TOPRIGHT", 0, -30)
    local ht = Text(page.header, "GameFontNormalSmall", 10, C.dim)
    ht:SetPoint("LEFT", 8, 0)
    ht:SetText("КВЕСТ  /  ID")

    page.list = CreateList(page, 26, function(list)
        local row = BaseRow(list, true)
        row.title = Text(row, "GameFontNormal", 12, C.gold)
        row.title:SetPoint("LEFT", 10, 0)
        row.title:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 70, 0)
        row.id = Text(row, "GameFontDisableSmall", 10, C.dim, "RIGHT")
        row.id:SetPoint("RIGHT", -(MAX_COLS * COL_W) - 6, 0)
        row.id:SetWidth(60)
        AddStatusCols(row)
        row:SetScript("OnClick", OnQuestRowClick)
        row:SetScript("OnEnter", function(self) if self.item then ShowQuestTooltip(self, self.item.id) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, it)
        row.title:SetText(QW.LevelTag(it.id) .. QW.TitleOrID(it.id))
        row.id:SetText(it.id)
        UpdateStatusCols(row, page.cols, it.id)
    end)
    page.list:SetPoint("TOPLEFT", page.header, "BOTTOMLEFT", 0, -2)
    page.list:SetPoint("BOTTOMRIGHT", 0, 0)

    page.empty = Text(page, "GameFontDisable", 13, C.dim, "CENTER")
    page.empty:SetPoint("CENTER")
    page.empty:SetWidth(420)
    page.empty:SetWordWrap(true)

    function page:Refresh()
        if not self.with or not QW.db.chars[self.with] then
            self.with = QW.db.settings.partners[1]
        end
        for _, b in ipairs(self.modeButtons) do
            local on = b.key == self.mode
            b.text:SetTextColor(on and C.gold[1] or C.text[1], on and C.gold[2] or C.text[2], on and C.gold[3] or C.text[3])
            b:SetBackdropBorderColor(unpack(on and { 0.55, 0.45, 0.15, 1 } or C.border))
        end
        if not self.with then
            self.withBtn:SetLabel("С кем: —")
            self.cols = { QW.me }
            self.header:SetChars(self.cols)
            self.list:SetData({})
            self.empty:SetText("Добавь друга во вкладке 'Настройки', чтобы сравнивать квесты.")
            self.empty:Show()
            return
        end
        self.withBtn:SetLabel("С кем: " .. QW.ColoredName(self.with))
        self.cols = { QW.me, self.with }
        self.header:SetChars(self.cols)

        local A = (QW.db.chars[QW.me] or {}).done or {}
        local B = (QW.db.chars[self.with] or {}).done or {}
        local ids = {}
        local function consider(id)
            local a, b = A[id], B[id]
            local ok = (self.mode == "onlyA" and a and not b) or (self.mode == "onlyB" and b and not a)
                or (self.mode == "both" and a and b) or self.mode == "all"
            if ok then ids[#ids + 1] = id end
        end
        local seen = {}
        for id in pairs(A) do seen[id] = true; consider(id) end
        for id in pairs(B) do if not seen[id] then consider(id) end end

        QW.RequestTitles(ids)
        local hide = QW.db.settings.hideUntitled
        local data, hidden = {}, 0
        for _, id in ipairs(ids) do
            local title = QW.GetTitle(id, true)
            if (title or not hide) and MatchSearch(UI.search, id, title) then
                data[#data + 1] = { id = id, title = title or "" }
            elseif not title then
                hidden = hidden + 1
            end
        end
        table.sort(data, function(a, b)
            if a.title ~= b.title then return a.title < b.title end
            return a.id < b.id
        end)
        self.list:SetData(data, true)
        self.empty:SetText("Здесь пусто.")
        self.empty:SetShown(#data == 0)
        UI.SetStatus(#data .. " квестов" .. (hidden > 0 and ("  /  скрыто служебных/незагруженных: " .. hidden) or ""))
    end
end

---------------------------------------------------------------------------
-- Выбор друга: группа / рейд, цель, друзья в сети
---------------------------------------------------------------------------
local picker

local function GatherCandidates()
    local out, seen = {}, {}
    local function add(full, class, source)
        if not full or QW.IsMe(full) then return end
        local key = QW.NameKey(full)
        if not key or seen[key] then return end
        seen[key] = true
        out[#out + 1] = { full = full, class = class, source = source, partner = QW.IsPartner(full) }
    end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n > 0 then
        local prefix, count = "party", n - 1
        if IsInRaid() then prefix, count = "raid", n end
        for i = 1, count do
            local u = prefix .. i
            local ok, full = pcall(QW.UnitId, u)
            if ok and full then add(full, select(2, UnitClass(u)), "группа") end
        end
    end
    local ok, tfull = pcall(QW.UnitId, "target")
    if ok and tfull then add(tfull, select(2, UnitClass("target")), "цель") end
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected and type(info.name) == "string" and not QW.IsSecret(info.name) then
                add(QW.FullName(info.name), nil, "друзья")
            end
        end
    end
    return out
end

local function ShowPicker(anchor)
    if not picker then
        picker = CreateFrame("Frame", "QuestWowPicker", UIParent, "BackdropTemplate")
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true)
        picker:SetWidth(280)
        picker:EnableMouse(true)
        SetBD(picker, C.bg, { 0.55, 0.45, 0.15, 1 })
        local t = Text(picker, "GameFontNormalSmall", 10, C.dim)
        t:SetPoint("TOPLEFT", 10, -9)
        t:SetText("ДОБАВИТЬ ДРУГА")
        local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
        close:SetScale(0.75)
        close:SetPoint("TOPRIGHT", 0, 0)
        picker.empty = Text(picker, "GameFontDisableSmall", 11, C.dim, "CENTER")
        picker.empty:SetPoint("TOP", 0, -34)
        picker.empty:SetWidth(250)
        picker.empty:SetWordWrap(true)
        picker.empty:SetText("Рядом никого нет.\nВступи в группу с другом, возьми его в цель или впиши имя и фамилию вручную в 'Настройках'.")
        picker.rows = {}
        tinsert(UISpecialFrames, "QuestWowPicker")
    end
    local list = GatherCandidates()
    for i = 1, math.max(#list, #picker.rows) do
        local c, r = list[i], picker.rows[i]
        if c and i <= 15 then
            if not r then
                r = FlatButton(picker, "", 260, 24)
                r:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 28)
                r.text:ClearAllPoints()
                r.text:SetPoint("LEFT", 10, 0)
                r.text:SetPoint("RIGHT", -70, 0)
                r.text:SetJustifyH("LEFT")
                r:SetScript("OnMouseDown", nil)
                r:SetScript("OnMouseUp", nil)
                r.src = Text(r, "GameFontDisableSmall", 10, C.dim, "RIGHT")
                r.src:SetPoint("RIGHT", -8, 0)
                r:SetScript("OnClick", function(self)
                    local cand = self.cand
                    if not cand or cand.partner then return end
                    local full = QW.AddPartner(cand.full)
                    if full then
                        if cand.class then QW.GetChar(full, true).class = cand.class end
                        QW.Print("Друг добавлен:", full)
                        QW.Comm.Hello(full, false)
                    end
                    picker:Hide()
                    UI.RefreshAll()
                end)
                picker.rows[i] = r
            end
            r.cand = c
            r:SetLabel("|c" .. QW.ClassColorHex(c.class) .. QW.DisplayName(c.full) .. "|r")
            r.src:SetText(c.partner and "|cff5ce673уже друг|r" or c.source)
            r:SetAlpha(c.partner and 0.55 or 1)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    local shown = math.min(#list, 15)
    picker.empty:SetShown(shown == 0)
    picker:SetHeight(shown == 0 and 100 or (36 + shown * 28))
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    picker:Show()
end
UI.ShowPicker = ShowPicker

---------------------------------------------------------------------------
-- Вкладка "Настройки"
---------------------------------------------------------------------------
local function BuildSettingsPage(page)
    local t = Text(page, "GameFontNormalLarge", 16, C.gold)
    t:SetPoint("TOPLEFT", 4, -2)
    t:SetText("Друзья")

    local hint = Text(page, "GameFontDisableSmall", 11, C.dim)
    hint:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(560)
    hint:SetWordWrap(true)
    page.hint = hint

    local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    eb:SetSize(200, 24)
    eb:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 6, -10)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    local add = FlatButton(page, "Добавить", 100, 24, true)
    add:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    local function DoAdd()
        local txt = strtrim(eb:GetText() or "")
        if txt == "" then
            -- Подставим цель, если она игрок
            txt = QW.UnitId("target")
        end
        if txt and txt ~= "" then
            local full = QW.AddPartner(txt)
            if full then
                QW.Print("Друг добавлен:", full)
                QW.Comm.Hello(full, false)
            end
        end
        eb:SetText("")
        eb:ClearFocus()
        UI.RefreshAll()
    end
    add:SetScript("OnClick", DoAdd)
    add.tip = "Пустое поле — добавить игрока из цели"
    eb:SetScript("OnEnterPressed", DoAdd)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local pick = FlatButton(page, "Из группы / цели...", 150, 24, true)
    pick:SetPoint("LEFT", add, "RIGHT", 8, 0)
    pick.tip = "Выбрать друга из группы, рейда, цели или списка друзей в сети"
    pick:SetScript("OnClick", function(self) ShowPicker(self) end)

    local sync = FlatButton(page, "Синхронизировать", 140, 24)
    sync:SetPoint("LEFT", pick, "RIGHT", 8, 0)
    sync:SetScript("OnClick", function()
        QW.RefreshDone(); QW.RefreshActive()
        QW.Comm.HelloAll()
        QW.Print("Синхронизация запущена.")
    end)

    page.partnerRows = {}
    page.partnerAnchor = CreateFrame("Frame", nil, page)
    page.partnerAnchor:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -6, -12)
    page.partnerAnchor:SetSize(560, 1)

    local opts = Text(page, "GameFontNormalLarge", 16, C.gold)
    opts:SetText("Параметры")
    page.optsTitle = opts

    page.checks = {
        Checkbox(page, "Синхронизировать при входе в игру",
            function() return QW.db.settings.autoSync end, function(v) QW.db.settings.autoSync = v end),
        Checkbox(page, "Писать в чат, когда друг сдаёт квест",
            function() return QW.db.settings.notify end, function(v) QW.db.settings.notify = v end),
        Checkbox(page, "Скрывать служебные квесты без названия ('Сравнение', 'Зоны')",
            function() return QW.db.settings.hideUntitled end, function(v) QW.db.settings.hideUntitled = v end),
        Checkbox(page, "Кнопка у миникарты",
            function() return not QW.db.settings.minimap.hide end,
            function(v) QW.db.settings.minimap.hide = not v; if QW.Minimap then QW.Minimap.Update() end end),
    }

    page.sources = Text(page, "GameFontDisableSmall", 11, C.dim)
    page.sources:SetWidth(560)
    page.sources:SetWordWrap(true)

    function page:Refresh()
        if QW.surnames then
            self.hint:SetText("Впиши имя и фамилию персонажа друга (например: Артас Менетил) или нажми 'Из группы / цели...'. "
                .. "Друг должен добавить тебя: |cffffffff" .. (QW.me or "") .. "|r. Пока вы оба в сети, данные синхронизируются автоматически.")
        else
            self.hint:SetText("Впиши имя персонажа друга (Имя или Имя-Сервер) или нажми 'Из группы / цели...'. "
                .. "Друг должен добавить тебя: |cffffffff" .. (QW.me or "") .. "|r. Пока вы оба в сети, данные синхронизируются автоматически.")
        end
        local partners = QW.db.settings.partners
        for i, full in ipairs(partners) do
            local r = self.partnerRows[i]
            if not r then
                r = CreateFrame("Frame", nil, page, "BackdropTemplate")
                r:SetSize(560, 28)
                SetBD(r, C.panel2, C.panel2)
                r.dot = r:CreateTexture(nil, "OVERLAY")
                r.dot:SetSize(14, 14); r.dot:SetPoint("LEFT", 8, 0)
                r.name = Text(r, "GameFontNormal", 12, C.text)
                r.name:SetPoint("LEFT", 28, 0)
                r.del = FlatButton(r, "Удалить", 70, 20)
                r.del:SetPoint("RIGHT", -4, 0)
                r.del:SetScript("OnClick", function(self)
                    QW.RemovePartner(self:GetParent().full)
                    UI.RefreshAll()
                end)
                self.partnerRows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.partnerAnchor, "TOPLEFT", 0, -(i - 1) * 32)
            r.full = full
            if QW.IsCompleteName(full) then
                r.name:SetText(QW.ColoredName(full))
            else
                r.name:SetText(QW.ColoredName(full) .. "  |cffff6060нужна фамилия: /qw add " .. full .. " Фамилия|r")
            end
            r.dot:SetTexture(QW.Comm.IsOnline(full) and ICON_ONLINE or ICON_OFFLINE)
            r:Show()
        end
        for i = #partners + 1, #self.partnerRows do self.partnerRows[i]:Hide() end

        local y = -(math.max(1, #partners) * 32) - 16
        self.optsTitle:ClearAllPoints()
        self.optsTitle:SetPoint("TOPLEFT", self.partnerAnchor, "TOPLEFT", 4, y)
        for i, cb in ipairs(self.checks) do
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", self.optsTitle, "BOTTOMLEFT", 0, -8 - (i - 1) * 26)
            cb:Update()
        end
        self.sources:ClearAllPoints()
        self.sources:SetPoint("TOPLEFT", self.checks[#self.checks], "BOTTOMLEFT", 0, -16)
        local ql = C_QuestLine and C_QuestLine.GetQuestLineInfo and "|cff5ce673есть|r" or "|cffff5555нет|r"
        local qz = QW.HasQuestie() and "|cff5ce673найден|r" or "|cff888888не установлен|r"
        self.sources:SetText("Откуда берутся цепочки:\n- API клиента C_QuestLine: " .. ql
            .. "\n- База Questie: " .. qz
            .. "\n\nКоманды: |cffffd100/qw|r, |cffffd100/qw add Имя|r, |cffffd100/qw sync|r, |cffffd100/qw link ID|r, |cffffd100/qw chain ID|r")
        UI.SetStatus("Версия " .. QW.VERSION)
    end
end

-------------------------------------------------------------------------------
-- Сборка окна
-------------------------------------------------------------------------------
local TAB_DEFS = {
    { key = "feed",     label = "Лента",      build = BuildFeedPage },
    { key = "chains",   label = "Цепочки",    build = BuildChainsPage },
    { key = "zones",    label = "Зоны",       build = BuildZonesPage },
    { key = "compare",  label = "Сравнение",  build = BuildComparePage },
    { key = "settings", label = "Настройки",  build = BuildSettingsPage },
}

local function SelectTab(key)
    currentTab = key
    for _, t in ipairs(tabs) do
        local on = t.key == key
        t.text:SetTextColor(on and C.gold[1] or C.dim[1], on and C.gold[2] or C.dim[2], on and C.gold[3] or C.dim[3])
        t.underline:SetShown(on)
        pages[t.key]:SetShown(on)
    end
    frame.search:SetShown(key ~= "settings")
    UI.Refresh()
end
UI.SelectTab = SelectTab

local function CreateMainFrame()
    frame = CreateFrame("Frame", "QuestWowFrame", UIParent, "BackdropTemplate")
    frame:SetSize(980, 580)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(940, 440, 1600, 1100) end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    SetBD(frame, C.bg, C.border)
    frame:SetScale(QW.db.settings.scale or 1)
    tinsert(UISpecialFrames, "QuestWowFrame")
    frame:Hide()

    -- Тонкая золотая полоска сверху
    local glow = frame:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("TOPRIGHT", -1, -1); glow:SetHeight(2)
    glow:SetTexture(WHITE)
    if glow.SetGradient and CreateColor then
        glow:SetGradient("HORIZONTAL", CreateColor(1, 0.82, 0.25, 0.9), CreateColor(0.4, 0.8, 1, 0.9))
    else
        glow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    end

    -- Шапка
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(52)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", 14, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = Text(header, "GameFontNormalLarge", 18)
    title:SetPoint("LEFT", icon, "RIGHT", 10, 6)
    title:SetText("|c" .. Hex(C.gold) .. "Quest|r|c" .. Hex(C.blue) .. "Wow|r")
    local subtitle = Text(header, "GameFontDisableSmall", 10, C.dim)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("цепочки квестов  /  ты и друзья")

    -- Вкладки
    local prev
    for _, def in ipairs(TAB_DEFS) do
        local b = CreateFrame("Button", nil, header)
        b:SetHeight(52)
        b.key = def.key
        b.text = Text(b, "GameFontNormal", 13, C.dim, "CENTER")
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetText(def.label)
        b:SetWidth(b.text:GetStringWidth() + 24)
        b.underline = b:CreateTexture(nil, "OVERLAY")
        b.underline:SetPoint("BOTTOMLEFT", 10, 0); b.underline:SetPoint("BOTTOMRIGHT", -10, 0)
        b.underline:SetHeight(2)
        b.underline:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        b:SetScript("OnClick", function() SelectTab(def.key) end)
        b:SetScript("OnEnter", function(self) if currentTab ~= self.key then self.text:SetTextColor(1, 1, 1) end end)
        b:SetScript("OnLeave", function(self) if currentTab ~= self.key then self.text:SetTextColor(unpack(C.dim)) end end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("LEFT", 215, 0) end
        tabs[#tabs + 1] = b
        prev = b
    end

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -8, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    local search = CreateFrame("EditBox", nil, header, "SearchBoxTemplate")
    search:SetSize(190, 22)
    search:SetPoint("RIGHT", close, "LEFT", -10, 0)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        local t = ULower(strtrim(self:GetText() or ""))
        if t == UI.search then return end
        UI.search = t
        if UI.searchTimer then UI.searchTimer:Cancel() end
        UI.searchTimer = C_Timer.NewTimer(0.25, function() UI.Refresh() end)
    end)
    frame.search = search

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 1, 0)
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(C.border))

    -- Боковая панель
    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 1, -1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 25)
    sidebar:SetWidth(200)
    SetBD(sidebar, C.panel, C.panel)
    frame.sidebar = sidebar
    local st = Text(sidebar, "GameFontNormalSmall", 10, C.dim)
    st:SetPoint("TOPLEFT", 12, -12)
    st:SetText("ИГРОКИ")
    frame.addHint = FlatButton(sidebar, "+ Добавить друга", 176, 26, true)
    frame.addHint:SetPoint("BOTTOM", 0, 12)
    frame.addHint:SetScript("OnClick", function(self) ShowPicker(self) end)

    -- Контент
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, -10)
    content:SetPoint("BOTTOMRIGHT", -12, 32)
    for _, def in ipairs(TAB_DEFS) do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints()
        p:Hide()
        def.build(p)
        pages[def.key] = p
    end

    -- Строка состояния
    local status = Text(frame, "GameFontDisableSmall", 10, C.dim)
    status:SetPoint("BOTTOMLEFT", 14, 8)
    frame.status = status

    local legend = Text(frame, "GameFontDisableSmall", 10, C.dim, "RIGHT")
    legend:SetPoint("BOTTOMRIGHT", -30, 8)
    legend:SetText("|T" .. ICON_DONE .. ":12|t выполнен   |T" .. ICON_ACTIVE .. ":12|t в журнале   - нет")

    -- Уголок для изменения размера
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    frame:SetScript("OnShow", function() UI.RefreshAll() end)
    frame:SetScript("OnHide", function() if picker then picker:Hide() end end)

    SelectTab("feed")
end

-------------------------------------------------------------------------------
-- Публичное API
-------------------------------------------------------------------------------
function UI.SetStatus(t)
    if frame then frame.status:SetText(t or "") end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    UI.cols = UI.VisibleChars()
    local p = pages[currentTab]
    if p and p.Refresh then p:Refresh() end
end

function UI.RefreshAll()
    if not frame or not frame:IsShown() then return end
    if pages.chains then pages.chains.dirty = true end
    if pages.zones then pages.zones.dirty = true end
    UpdateSidebar()
    UI.Refresh()
end

function UI.SelectChain(chain)
    UI.selectedChain = chain
    if pages.chains then
        pages.chains:ShowChain(chain)
        pages.chains.chainList:Refresh()
    end
end

function UI.ShowZone(name)
    UI.Show()
    if name then
        -- Поиск зоны по части названия без учёта регистра
        local key = QW.ULower(name)
        local p = pages.zones
        local best
        for _, z in ipairs((p and p.zones) or {}) do
            local zl = QW.ULower(z.name)
            if zl == key then best = z.name break end
            if not best and zl:find(key, 1, true) then best = z.name end
        end
        UI.selectedZone = best or name
    else
        UI.selectedZone = QW.CurrentZoneName() or UI.selectedZone
    end
    SelectTab("zones")
end

function UI.ShowChainFor(questID)
    UI.Show()
    UI.focusQuest = questID
    local chain = QW.GetChain(questID)
    UI.selectedChain = chain
    SelectTab("chains")
end

function UI.Show()
    if not frame then CreateMainFrame() end
    frame:Show()
end

function UI.Toggle()
    if not frame then CreateMainFrame() end
    frame:SetShown(not frame:IsShown())
end

-- Обновления данных -> перерисовка (с задержкой, чтобы не дёргать на каждом сообщении)
local pending
local function Debounced()
    if pending then return end
    pending = C_Timer.NewTimer(0.4, function()
        pending = nil
        UI.RefreshAll()
    end)
end
QW.On("DATA_CHANGED", Debounced)
QW.On("SYNC_PROGRESS", function() if frame and frame:IsShown() then UpdateSidebar() end end)
-- Questie догрузил базу — пересобираем зоны и цепочки
QW.On("QUESTIE_READY", function() UI.RefreshAll() end)
QW.On("TITLES_LOADED", function()
    if not frame or not frame:IsShown() then return end
    -- Названия подгрузились — перерисовываем без пересборки цепочек
    UI.Refresh()
end)
QW.On("ZONES_PROGRESS", function(done, total)
    if frame and frame:IsShown() and currentTab == "zones" then
        UI.SetStatus(string.format("Собираю зоны... %d / %d", done or 0, total or 0))
    end
end)
QW.On("CHAINS_PROGRESS", function(done, total)
    if frame and frame:IsShown() and currentTab == "chains" then
        UI.SetStatus(string.format("Собираю цепочки... %d / %d", done or 0, total or 0))
    end
end)
