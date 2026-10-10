-- Vanguard Bank - one request/response channel. Handlers validate their own input.

Router = {}

local RESOURCE = GetCurrentResourceName()
local RATE_WINDOW_MS, RATE_LIMIT = 1000, 10

local handlers = {}
local rate = {} -- server id -> { start, count }

function Router.on(action, handler)
    handlers[action] = handler
end

function Router.ok(message, data)
    return { ok = true, message = message, data = data }
end

function Router.fail(message)
    return { ok = false, message = message }
end

function Router.log(src, message)
    print(('[%s] %s (%s): %s'):format(RESOURCE, GetPlayerName(src) or 'unknown', src, message))
end

local function withinRate(src)
    local now = GetGameTimer()
    local entry = rate[src]
    if not entry or now - entry.start > RATE_WINDOW_MS then
        rate[src] = { start = now, count = 1 }
        return true
    end
    entry.count = entry.count + 1
    return entry.count <= RATE_LIMIT
end

RegisterNetEvent('vanguard-bank:request', function(requestId, action, data)
    local src = source
    if type(requestId) ~= 'number' or type(action) ~= 'string' then return end

    local function reply(result)
        TriggerClientEvent('vanguard-bank:response', src, requestId, result)
    end

    if not withinRate(src) then return reply(Router.fail('Slow down')) end
    if not Bridge.ready then return reply(Router.fail('The bank is starting, try again in a moment')) end
    local handler = handlers[action]
    if not handler then return reply(Router.fail('Unknown action')) end
    if not Bridge.loaded(src) then return reply(Router.fail('Load your character first')) end

    local ok, result = pcall(handler, src, type(data) == 'table' and data or {})
    if not ok then
        print(('[%s] %s failed for %s: %s'):format(RESOURCE, action, src, tostring(result)))
        return reply(Router.fail('Something went wrong, try again'))
    end
    reply(result or Router.ok())
end)

AddEventHandler('playerDropped', function()
    rate[source] = nil
end)
