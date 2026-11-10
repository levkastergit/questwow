-- QuestWow: Data — названия, линки, цепочки (C_QuestLine клиента + Questie, если установлен)
local _, QW = ...

-------------------------------------------------------------------------------
-- Questie (необязательно). Используем его внутреннюю БД через pcall —
-- если API Questie другое или аддон не установлен, просто пропускаем.
-------------------------------------------------------------------------------
local questieDB
local function GetQuestieDB()
    if questieDB ~= nil then return questieDB or nil end
    if not QuestieLoader or not QuestieLoader.ImportModule then return nil end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if ok and type(db) == "table" and type(db.GetQuest) == "function" then
        questieDB = db
        return db
    end
    return nil
end

local function QuestieQuest(id)
    local db = GetQuestieDB()
    if not db then return nil end
    local ok, q = pcall(db.GetQuest, id)
    if ok and type(q) == "table" then return q end
    return nil
end

function QW.HasQuestie()
    return GetQuestieDB() ~= nil
end

-------------------------------------------------------------------------------
-- Названия квестов
-------------------------------------------------------------------------------
local pendingLoad, failedLoad = {}, {}
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
local refreshTimer
loadFrame:SetScript("OnEvent", function(_, _, questID, success)
    if not questID or not pendingLoad[questID] then return end
    pendingLoad[questID] = nil
    if not success then
        failedLoad[questID] = true   -- служебный/скрытый квест — больше не запрашиваем
    else
        local t = C_QuestLog.GetTitleForQuestID(questID)
        if t and t ~= "" then
            QW.db.titles[questID] = t
            if not refreshTimer then
                refreshTimer = C_Timer.NewTimer(0.3, function()
                    refreshTimer = nil
                    QW.Fire("TITLES_LOADED")
                end)
            end
        end
    end
end)

-- Возвращает название или nil (и запрашивает загрузку у клиента)
function QW.GetTitle(id, noRequest)
    if not id then return nil end
    local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if t and t ~= "" then
        if QW.db then QW.db.titles[id] = t end
        return t
    end
    if QW.db and QW.db.titles[id] then return QW.db.titles[id] end
    local q = QuestieQuest(id)
    if q and type(q.name) == "string" and q.name ~= "" then return q.name end
    if not noRequest and C_QuestLog and C_QuestLog.RequestLoadQuestByID
        and not pendingLoad[id] and not failedLoad[id] then
        pendingLoad[id] = true
        C_QuestLog.RequestLoadQuestByID(id)
    end
    return nil
end

-- Фоновая подгрузка названий для большого списка ID (по 25 за тик)
local titleQueue, titleQueued, titleTicker = {}, {}, nil
function QW.RequestTitles(ids)
    for _, id in ipairs(ids) do
        if not QW.db.titles[id] and not titleQueued[id] and not failedLoad[id] and not pendingLoad[id] then
            titleQueued[id] = true
            titleQueue[#titleQueue + 1] = id
        end
    end
    if titleTicker or #titleQueue == 0 then return end
    titleTicker = C_Timer.NewTicker(0.15, function()
        for _ = 1, 25 do
            local id = table.remove(titleQueue)
            if not id then break end
            titleQueued[id] = nil
            QW.GetTitle(id)
        end
        if #titleQueue == 0 then
            titleTicker:Cancel()
            titleTicker = nil
        end
    end)
end

function QW.KnownTitle(id)
    return QW.GetTitle(id, true)
end

function QW.TitleOrID(id)
    return QW.GetTitle(id) or ("Квест #" .. id)
end

function QW.GetQuestLevel(id)
    local q = QuestieQuest(id)
    if q and tonumber(q.questLevel or q.level) then return tonumber(q.questLevel or q.level) end
    return nil
end

-------------------------------------------------------------------------------
-- Линки
-------------------------------------------------------------------------------
function QW.GetLink(id)
    local link
    if GetQuestLink then
        local ok, l = pcall(GetQuestLink, id)
        if ok and l and l ~= "" then link = l end
    end
    if not link then
        local title = QW.GetTitle(id)
        if not title then return nil end
        link = string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, QW.GetQuestLevel(id) or -1, title)
    end
    return link
end

local function InsertIntoChat(text)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        local ok, res = pcall(ChatFrameUtil.InsertLink, text)
        if ok and res then return true end
    end
    if ChatEdit_InsertLink then
        local ok, res = pcall(ChatEdit_InsertLink, text)
        if ok and res then return true end
    end
    -- Поле ввода закрыто — открываем чат с текстом
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
        return true
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
        return true
    end
    return false
end
QW.InsertIntoChat = InsertIntoChat

function QW.LinkQuest(id)
    local link = QW.GetLink(id)
    if not link then
        QW.Print("Данные квеста #" .. id .. " ещё загружаются, попробуй ещё раз через секунду.")
        return false
    end
    return InsertIntoChat(link)
end

-- Несколько линков: вставляет, сколько влезает в одно сообщение (255 байт).
-- Возвращает индекс следующего не вставленного квеста или nil.
function QW.LinkMany(ids, startIndex)
    startIndex = startIndex or 1
    local parts, len = {}, 0
    local i = startIndex
    while i <= #ids do
        local link = QW.GetLink(ids[i])
        if link then
            local add = #link + (#parts > 0 and 1 or 0)
            if len + add > 250 then break end
            parts[#parts + 1] = link
            len = len + add
        end
        i = i + 1
    end
    if #parts > 0 then InsertIntoChat(table.concat(parts, " ")) end
    if i <= #ids then return i end
    return nil
end

-------------------------------------------------------------------------------
-- Цепочки
-- chain = { key, name, source = "questline"|"questie"|"single", quests = {id,...} }
-------------------------------------------------------------------------------
local chainCache = {}   -- [questID] = chain
local chainsByKey = {}

function QW.ClearChainCache()
    wipe(chainCache)
    wipe(chainsByKey)
end

local function FromQuestLine(id)
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then return nil end
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, id)
    if not ok or not info or not info.questLineID or info.questLineID == 0 then
        -- Некоторые версии API требуют uiMapID
        local mapID = QW.CurrentMapID()
        if mapID and mapID > 0 then
            ok, info = pcall(C_QuestLine.GetQuestLineInfo, id, mapID)
        end
    end
    if not ok or not info or not info.questLineID or info.questLineID == 0 then return nil end
    local ok2, quests = pcall(C_QuestLine.GetQuestLineQuests, info.questLineID)
    if not ok2 or type(quests) ~= "table" or #quests < 2 then return nil end
    local list = {}
    for i, q in ipairs(quests) do list[i] = q end
    return {
        key = "L" .. info.questLineID,
        name = info.questLineName or QW.TitleOrID(list[1]),
        source = "questline",
        quests = list,
    }
end

local function FirstPre(q)
    local p = q and q.preQuestSingle
    if type(p) == "table" and #p > 0 then return p[1] end
    if type(p) == "number" and p > 0 then return p end
    -- preQuestGroup = все нужны; для линейной цепочки берём последний
    p = q and q.preQuestGroup
    if type(p) == "table" and #p > 0 then return p[#p] end
    return nil
end

local function FromQuestie(id)
    local q = QuestieQuest(id)
    if not q then return nil end
    -- Назад к началу
    local seen, back = { [id] = true }, {}
    local cur = q
    for _ = 1, 40 do
        local pre = FirstPre(cur)
        if not pre or seen[pre] then break end
        seen[pre] = true
        table.insert(back, 1, pre)
        cur = QuestieQuest(pre)
        if not cur then break end
    end
    -- Вперёд
    local fwd = {}
    cur = q
    for _ = 1, 40 do
        local nxt = cur and tonumber(cur.nextQuestInChain)
        if not nxt or nxt == 0 or seen[nxt] then break end
        seen[nxt] = true
        fwd[#fwd + 1] = nxt
        cur = QuestieQuest(nxt)
    end
    if #back + #fwd == 0 then return nil end
    local list = {}
    for _, v in ipairs(back) do list[#list + 1] = v end
    list[#list + 1] = id
    for _, v in ipairs(fwd) do list[#list + 1] = v end
    return {
        key = "Q" .. list[1],
        name = QW.TitleOrID(list[1]),
        source = "questie",
        quests = list,
    }
end

-- Цепочка, к которой относится квест (всегда возвращает таблицу)
function QW.GetChain(id)
    if chainCache[id] then return chainCache[id] end
    local chain = FromQuestLine(id) or FromQuestie(id)
    if chain then
        -- Одна и та же цепочка для всех её квестов
        local existing = chainsByKey[chain.key]
        if existing and #existing.quests >= #chain.quests then
            chain = existing
        else
            chainsByKey[chain.key] = chain
        end
        for _, q in ipairs(chain.quests) do chainCache[q] = chain end
        chainCache[id] = chain
    else
        chain = { key = "S" .. id, name = QW.TitleOrID(id), source = "single", quests = { id } }
        chainCache[id] = chain
    end
    return chain
end

-- Статус квеста у персонажа: "done" | "active" | nil
function QW.QuestStatus(full, id)
    local ch = QW.db.chars[full]
    if not ch then return nil end
    if ch.done and ch.done[id] then return "done" end
    if ch.active and ch.active[id] then return "active" end
    return nil
end

function QW.ChainProgress(full, chain)
    local n = 0
    for _, q in ipairs(chain.quests) do
        if QW.QuestStatus(full, q) == "done" then n = n + 1 end
    end
    return n, #chain.quests
end

-- Персонажи, которых показываем (свой текущий + друзья + выбранные альты)
function QW.ViewedChars()
    local out = { QW.me }
    for _, p in ipairs(QW.db.settings.partners) do
        if p ~= QW.me then out[#out + 1] = p end
    end
    return out
end

-------------------------------------------------------------------------------
-- Построение списка цепочек (по частям, чтобы не было фриза)
-------------------------------------------------------------------------------
local buildTicker
function QW.BuildChains(chars, onDone)
    local ids, seen = {}, {}
    local function add(id)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, full in ipairs(chars) do
        local ch = QW.db.chars[full]
        if ch then
            for _, e in ipairs(ch.history or {}) do add(e[1]) end
            for id in pairs(ch.active or {}) do add(id) end
            for id in pairs(ch.done or {}) do add(id) end
        end
    end

    if buildTicker then buildTicker:Cancel() end
    local co = coroutine.create(function()
        local found, byKey = {}, {}
        for i, id in ipairs(ids) do
            local chain = QW.GetChain(id)
            if chain.source ~= "single" and not byKey[chain.key] then
                byKey[chain.key] = true
                found[#found + 1] = chain
            end
            if i % 150 == 0 then coroutine.yield(i, #ids) end
        end
        return found
    end)

    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local ok, a, b = coroutine.resume(co)
        if not ok then
            ticker:Cancel()
            geterrorhandler()(a)
            return
        end
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            onDone(a or {})
        else
            QW.Fire("CHAINS_PROGRESS", a, b)
        end
    end)
    buildTicker = ticker
end
