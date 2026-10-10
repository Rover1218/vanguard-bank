-- Vanguard Bank - client core: server requests and the bank / ATM panel.

Client = { isOpen = false }

local REQUEST_TIMEOUT_MS = 10000
local pending, nextId, labelPromise = {}, 0, nil

function Client.request(action, data)
    nextId = nextId + 1
    local id, answer = nextId, promise.new()
    pending[id] = answer
    TriggerServerEvent('vanguard-bank:request', id, action, data or {})
    SetTimeout(REQUEST_TIMEOUT_MS, function()
        if pending[id] then
            pending[id] = nil
            answer:resolve({ ok = false, message = 'The bank did not answer' })
        end
    end)
    return Citizen.Await(answer)
end

RegisterNetEvent('vanguard-bank:response', function(id, result)
    local answer = pending[id]
    if not answer then return end
    pending[id] = nil
    answer:resolve(type(result) == 'table' and result or { ok = false })
end)

function Client.open()
    if Client.isOpen then return end
    Client.isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'loading' })
    local result = Client.request('open')
    if not result.ok then
        Client.close()
        return ClientBridge.notify(result.message, 'error')
    end
    SendNUIMessage({ action = 'open', state = result.data, brand = Config.Brand })
end

function Client.close()
    Client.isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

--- Asks the admin for a branch name in the panel. Returns the text or nil.
function Client.askLabel()
    labelPromise = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'askLabel' })
    local text = Citizen.Await(labelPromise)
    labelPromise = nil
    SetNuiFocus(false, false)
    return text
end

RegisterNUICallback('close', function(_, cb)
    Client.close()
    cb({})
end)

RegisterNUICallback('request', function(body, cb)
    if type(body) ~= 'table' or type(body.action) ~= 'string' then return cb({ ok = false }) end
    cb(Client.request(body.action, body.data))
end)

RegisterNUICallback('label', function(body, cb)
    if labelPromise then
        labelPromise:resolve(type(body) == 'table' and type(body.text) == 'string' and body.text or nil)
    end
    cb({})
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('vanguard-bank:hello')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and Client.isOpen then SetNuiFocus(false, false) end
end)
