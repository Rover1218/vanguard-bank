-- Vanguard Bank - admin placement mode for branches and ATMs (/bankadmin).

Placement = { active = false, index = 1, heading = 0.0 }

local REACH, REMOVE_RADIUS, ROTATE_STEP = 20.0, 1.5, 15.0
local KINDS = { { id = 'branch', label = 'Branch counter' }, { id = 'atm', label = 'ATM' } }
local KEY = { place = 24, wheelDown = 14, wheelUp = 15, previous = 174, next = 175, remove = 178, exit = 194, pause = 200 }
local ATM = {}
for _, model in ipairs(Config.AtmModels) do ATM[GetHashKey(model)] = true end

local function direction(rotation)
    local z, x = math.rad(rotation.z), math.rad(rotation.x)
    local horizontal = math.abs(math.cos(x))
    return vector3(-math.sin(z) * horizontal, math.cos(z) * horizontal, math.sin(x))
end

--- What the camera is looking at: hit (bool), position, entity.
local function aim()
    local from = GetGameplayCamCoord()
    local to = from + direction(GetGameplayCamRot(2)) * REACH
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, PlayerPedId(), 7)
    local _, hit, position, _, entity = GetShapeTestResult(handle)
    return hit == 1, position, entity
end

local function kind() return KINDS[Placement.index] end

local function bar(hint)
    SendNUIMessage({ action = 'placement', kind = kind().label, index = Placement.index, total = #KINDS, hint = hint })
end

local function highlight(entity)
    if Placement.outlined and Placement.outlined ~= entity then SetEntityDrawOutline(Placement.outlined, false) end
    Placement.outlined = entity
    if entity then
        SetEntityDrawOutlineColor(99, 102, 241, 255)
        SetEntityDrawOutline(entity, true)
    end
end

local function report(result)
    ClientBridge.notify(result.message, result.ok and 'success' or 'error')
end

local function save(kindId, position, heading)
    local label = nil
    if kindId == 'branch' then
        label = Client.askLabel()
        if not label then return end
    end
    report(Client.request('placeAdd', {
        kind = kindId, label = label, heading = heading,
        coords = { x = position.x, y = position.y, z = position.z },
    }))
end

local function removeNear(position)
    local best, bestDistance = nil, REMOVE_RADIUS
    for _, place in ipairs(Places.list) do
        local distance = #(position - vector3(place.x, place.y, place.z))
        if distance < bestDistance then best, bestDistance = place, distance end
    end
    if not best then return ClientBridge.notify('Aim at a placed branch or ATM to remove it', 'error') end
    report(Client.request('placeRemove', { id = best.id }))
end

local function drawPlaced()
    for _, place in ipairs(Places.list) do
        DrawMarker(28, place.x, place.y, place.z, 0, 0, 0, 0, 0, 0, 0.15, 0.15, 0.15, 99, 102, 241, 170, false, false, 2, false, nil, nil, false)
        ClientBridge.drawText3d(vector3(place.x, place.y, place.z + 0.3), place.kind == 'atm' and 'ATM' or place.label)
    end
end

local function tick()
    DisablePlayerFiring(PlayerId(), true)
    for _, control in ipairs({ 24, 25, 14, 15, 16, 17, 140, 141, 142, 200 }) do DisableControlAction(0, control, true) end
    drawPlaced()

    local hit, position, entity = aim()
    if kind().id == 'atm' then
        local isAtm = hit and entity ~= 0 and GetEntityType(entity) == 3 and ATM[GetEntityModel(entity)] == true
        highlight(isAtm and entity or nil)
        if isAtm and IsDisabledControlJustReleased(0, KEY.place) then
            save('atm', GetEntityCoords(entity), GetEntityHeading(entity))
        end
    else
        highlight(nil)
        if hit then
            DrawMarker(25, position.x, position.y, position.z + 0.02, 0, 0, 0, 0, 0, 0, 0.7, 0.7, 0.7, 99, 102, 241, 170, false, false, 2, false, nil, nil, false)
            if IsDisabledControlJustReleased(0, KEY.place) then save('branch', position, Placement.heading) end
        end
    end

    if IsDisabledControlJustReleased(0, KEY.wheelUp) then Placement.heading = (Placement.heading + ROTATE_STEP) % 360 end
    if IsDisabledControlJustReleased(0, KEY.wheelDown) then Placement.heading = (Placement.heading - ROTATE_STEP) % 360 end
    if IsControlJustReleased(0, KEY.next) then Placement.index = Placement.index % #KINDS + 1; bar() end
    if IsControlJustReleased(0, KEY.previous) then Placement.index = (Placement.index - 2) % #KINDS + 1; bar() end
    if IsControlJustReleased(0, KEY.remove) and hit then removeNear(position) end
    if IsControlJustReleased(0, KEY.exit) or IsDisabledControlJustReleased(0, KEY.pause) then Placement.stop() end
end

function Placement.start()
    if Placement.active then return end
    Placement.active, Placement.index, Placement.heading = true, 1, GetEntityHeading(PlayerPedId())
    bar()
    CreateThread(function()
        while Placement.active do
            tick()
            Wait(0)
        end
    end)
end

function Placement.stop()
    Placement.active = false
    highlight(nil)
    SendNUIMessage({ action = 'placementEnd' })
end

RegisterNetEvent('vanguard-bank:placement', function()
    if Placement.active then Placement.stop() else Placement.start() end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and Placement.active then highlight(nil) end
end)
