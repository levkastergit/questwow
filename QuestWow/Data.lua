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

local function QuestieModule(name)
    if not QuestieLoader or not QuestieLoader.ImportModule then return nil end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok and type(m) == "table" then return m end
    return nil
end

-- База Questie загружена (QuestPointers появляется после инициализации Questie)
function QW.QuestieReady()
    local db = GetQuestieDB()
    if not db then return false end
    if Questie and Questie.API and Questie.API.isReady ~= nil then
        return Questie.API.isReady == true
    end
    return db.QuestPointers ~= nil
end

-- Можно ли взять квест прямо сейчас (по данным Questie: раса, класс, уровень,
-- предыдущие квесты). nil — Questie недоступен.
function QW.IsDoable(id)
    local db = GetQuestieDB()
    if not db or type(db.IsDoable) ~= "function" or not QW.QuestieReady() then return nil end
    local ok, r = pcall(db.IsDoable, id)
    if not ok then return nil end
    return r and true or false
end

-- Пояснение Questie, почему квест доступен/недоступен
function QW.DoableText(id)
    local db = GetQuestieDB()
    if not db or type(db.IsDoableVerbose) ~= "function" or not QW.QuestieReady() then return nil end
    local ok, text = pcall(db.IsDoableVerbose, id, false, true, true)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

function QW.QuestieInfo(id)
    return QuestieQuest(id)
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

-- Уровень квеста: база Questie, иначе клиент (работает для известных клиенту квестов)
local levelCache = {}
function QW.GetQuestLevel(id)
    if levelCache[id] then return levelCache[id] end
    local lvl
    local q = QuestieQuest(id)
    if q then lvl = tonumber(q.questLevel or q.level) end
    if (not lvl or lvl <= 0) and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local ok, l = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
        if ok and tonumber(l) and l > 0 then lvl = l end
    end
    if lvl and lvl > 0 then
        levelCache[id] = lvl
        return lvl
    end
    return nil
end

-- "[12] " цветом сложности (как в журнале квестов) или пустая строка
function QW.LevelTag(id)
    local lvl = QW.GetQuestLevel(id)
    if not lvl then return "" end
    local hex = "ff999999"
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, lvl)
        if ok and type(c) == "table" and c.r then
            hex = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
    end
    return "|c" .. hex .. "[" .. lvl .. "]|r "
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

-------------------------------------------------------------------------------
-- Работа по частям (чтобы не было фриза на тысячах квестов)
-------------------------------------------------------------------------------
local runners = {}
local function RunSliced(key, work, onDone, progressEvent)
    if runners[key] then runners[key]:Cancel() end
    local co = coroutine.create(work)
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local ok, a, b = coroutine.resume(co)
        if not ok then
            ticker:Cancel(); runners[key] = nil
            geterrorhandler()(a)
            return
        end
        if coroutine.status(co) == "dead" then
            ticker:Cancel(); runners[key] = nil
            onDone(a or {})
        elseif progressEvent then
            QW.Fire(progressEvent, a, b)
        end
    end)
    runners[key] = ticker
end

-- Все квесты выбранных персонажей + карта, где квест сдан (из ленты)
local function CollectQuests(chars)
    local ids, seen, histMap = {}, {}, {}
    local function add(id)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, full in ipairs(chars) do
        local ch = QW.db.chars[full]
        if ch then
            for _, e in ipairs(ch.history or {}) do
                add(e[1])
                if e[3] and e[3] > 0 then histMap[e[1]] = e[3] end
            end
            for id in pairs(ch.active or {}) do add(id) end
            for id in pairs(ch.done or {}) do add(id) end
        end
    end
    return ids, histMap
end

-------------------------------------------------------------------------------
-- Построение списка цепочек
-------------------------------------------------------------------------------
function QW.BuildChains(chars, onDone)
    local ids = CollectQuests(chars)
    RunSliced("chains", function()
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
    end, onDone, "CHAINS_PROGRESS")
end

-------------------------------------------------------------------------------
-- Зоны
-- Откуда берём зону квеста (по порядку):
--   1) заголовок журнала квестов, под которым квест был (QW.db.questZones)
--   2) база Questie (zoneOrSort -> C_Map.GetAreaInfo)
--   3) карта, на которой квест сдан (лента)
-------------------------------------------------------------------------------
local UIMAP = (Enum and Enum.UIMapType) or {}
local ZONE_TYPE = UIMAP.Zone or 3
local CONT_TYPE = UIMAP.Continent or 2
local DUNGEON_TYPE = UIMAP.Dungeon or 4

local mapInfoCache = {}
local function MapInfo(id)
    if not id or id == 0 then return nil end
    local v = mapInfoCache[id]
    if v == nil then
        v = (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)) or false
        mapInfoCache[id] = v
    end
    return v or nil
end

-- Карта (подземелье, микрозона...) -> название зоны и континента
function QW.ZoneOfMap(mapID)
    local zone, cont
    local id, guard = mapID, 0
    while id and id > 0 and guard < 12 do
        guard = guard + 1
        local info = MapInfo(id)
        if not info then break end
        -- Подземелье считаем отдельной "зоной", микрозоны поднимаем до зоны
        if not zone and (info.mapType == ZONE_TYPE or info.mapType == DUNGEON_TYPE) then zone = info end
        if info.mapType == CONT_TYPE then cont = info break end
        id = info.parentMapID
    end
    if not zone then
        local info = MapInfo(mapID)
        if info and info.mapType and info.mapType > ZONE_TYPE then zone = info end
    end
    return zone and zone.name, cont and cont.name
end

-- Индекс "название зоны -> континент" по всем картам клиента
local zoneCont, zoneIndexOK = {}, false
local function BuildZoneIndex()
    if zoneIndexOK or not (C_Map and C_Map.GetMapChildrenInfo) then return end
    local id, root, guard = QW.CurrentMapID(), nil, 0
    while id and id > 0 and guard < 12 do
        guard = guard + 1
        local info = MapInfo(id)
        if not info then break end
        root = id
        id = info.parentMapID
    end
    if not root then return end
    local ok, list = pcall(C_Map.GetMapChildrenInfo, root, ZONE_TYPE, true)
    if not ok or type(list) ~= "table" or #list == 0 then return end
    for _, z in ipairs(list) do
        if z.name and z.name ~= "" and zoneCont[z.name] == nil then
            local _, cont = QW.ZoneOfMap(z.mapID)
            zoneCont[z.name] = cont or false
        end
    end
    zoneIndexOK = true
end

function QW.CurrentZoneName()
    local zone = QW.ZoneOfMap(QW.CurrentMapID())
    return zone
end

-- areaId Questie -> название зоны и континента (через uiMapID, как у остальных зон)
local areaCache = {}
local function AreaToZone(areaId)
    local c = areaCache[areaId]
    if c then return c[1] or nil, c[2] end
    local zone, cont
    local zdb = QuestieModule("ZoneDB")
    if zdb and type(zdb.GetUiMapIdByAreaId) == "function" then
        local ok, ui = pcall(zdb.GetUiMapIdByAreaId, zdb, areaId)
        if ok and tonumber(ui) and ui > 0 then zone, cont = QW.ZoneOfMap(ui) end
    end
    if not zone and C_Map and C_Map.GetAreaInfo then
        local ok, n = pcall(C_Map.GetAreaInfo, areaId)
        if ok and type(n) == "string" and n ~= "" then
            zone = n
            BuildZoneIndex()
            cont = zoneCont[n] or nil
        end
    end
    areaCache[areaId] = { zone or false, cont }
    return zone, cont
end

local questZoneCache = {}
function QW.QuestZone(id, histMap)
    local zone = QW.db.questZones[id]
    local cont
    if not zone then
        local c = questZoneCache[id]
        if c then return c[1], c[2] end
        local q = QuestieQuest(id)
        local area = q and tonumber(q.zoneOrSort)
        if area and area > 0 then zone, cont = AreaToZone(area) end
    end
    if zone and not cont then
        BuildZoneIndex()
        cont = zoneCont[zone] or nil
        if not cont and histMap then
            local _, c2 = QW.ZoneOfMap(histMap)
            cont = c2
        end
    elseif not zone and histMap then
        zone, cont = QW.ZoneOfMap(histMap)
    end
    if zone and not QW.db.questZones[id] then questZoneCache[id] = { zone, cont } end
    return zone, cont
end

-------------------------------------------------------------------------------
-- Все квесты по зонам из базы Questie (с учётом расы и класса — так делает
-- сам Questie в ZoneDB.GetZonesWithQuests). Строится один раз за сессию.
-------------------------------------------------------------------------------
local questieZones
function QW.GetQuestieZones()
    if questieZones ~= nil then return questieZones or nil end
    if not QW.QuestieReady() then return nil end
    local zdb = QuestieModule("ZoneDB")
    if not (zdb and type(zdb.GetZonesWithQuests) == "function") then
        questieZones = false
        return nil
    end
    local ok, res = pcall(zdb.GetZonesWithQuests, false)
    questieZones = (ok and type(res) == "table") and res or false
    return questieZones or nil
end

-- Questie закончил загрузку — сбрасываем кэши, построенные без него
local function OnQuestieReady()
    questieZones = nil
    wipe(areaCache)
    wipe(questZoneCache)
    QW.ClearChainCache()
    QW.Fire("QUESTIE_READY")
end

QW.On("LOGIN", function()
    if Questie and Questie.API and type(Questie.API.RegisterOnReady) == "function" then
        pcall(Questie.API.RegisterOnReady, OnQuestieReady)
    end
end)

-- zones = { { name, cont, quests = {id,...}, fromDB = {[id]=true} }, ... }
-- fromDB — квест есть только в базе Questie: никто из показанных игроков его не брал
function QW.BuildZones(chars, onDone)
    local ids, histMap = CollectQuests(chars)
    RunSliced("zones", function()
        local byName, list, placed = {}, {}, {}
        local function zoneFor(name, cont)
            local z = byName[name]
            if not z then
                z = { name = name, cont = cont, quests = {}, fromDB = {} }
                byName[name] = z
                list[#list + 1] = z
            end
            if cont and not z.cont then z.cont = cont end
            return z
        end
        for i, id in ipairs(ids) do
            local zone, cont = QW.QuestZone(id, histMap[id])
            if zone then
                local z = zoneFor(zone, cont)
                z.quests[#z.quests + 1] = id
                placed[id] = true
            end
            if i % 150 == 0 then coroutine.yield(i, #ids) end
        end
        -- Квесты из базы Questie, которые ещё никто не брал
        local qz = QW.GetQuestieZones()
        if qz then
            local n = 0
            for areaId, set in pairs(qz) do
                if type(areaId) == "number" and areaId > 0 and type(set) == "table" then
                    local zone, cont = AreaToZone(areaId)
                    if zone then
                        local z = zoneFor(zone, cont)
                        for qid in pairs(set) do
                            if type(qid) == "number" and not placed[qid] then
                                placed[qid] = true
                                z.quests[#z.quests + 1] = qid
                                z.fromDB[qid] = true
                            end
                        end
                    end
                end
                n = n + 1
                if n % 15 == 0 then coroutine.yield(#ids, #ids) end
            end
        end
        return list
    end, onDone, "ZONES_PROGRESS")
end
