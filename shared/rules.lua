-- Vanguard Bank - pure rules (no FiveM natives). Unit tested in tests/rules_spec.lua.

Rules = {}

local function isFinite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

--- Whole dollars from 1 to max, or nil.
function Rules.wholeAmount(value, max)
    if not isFinite(value) or value < 1 or value > max or value % 1 ~= 0 then return nil end
    return math.tointeger(value) -- nil for numbers too big to be exact whole dollars
end

--- Trimmed single-line text of 1..maxChars characters, or nil.
function Rules.cleanText(value, maxChars)
    if type(value) ~= 'string' then return nil end
    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)
    if text == '' or not length or length > maxChars then return nil end
    return text
end

function Rules.newNumber(random)
    return ('VB-%04d-%04d'):format(random(0, 9999), random(0, 9999))
end

--- "VB-1234-5678", "vb12345678", "1234 5678" ... -> "VB-1234-5678"; anything else -> nil.
function Rules.parseNumber(text)
    if type(text) ~= 'string' or #text > 20 then return nil end
    local digits = text:upper():gsub('^%s*VB', ''):gsub('[%s%-]', '')
    if not digits:match('^%d%d%d%d%d%d%d%d$') then return nil end
    return ('VB-%s-%s'):format(digits:sub(1, 4), digits:sub(5, 8))
end

local USE = { view = true, deposit = true, withdraw = true, transfer = true }
local OWN = { view = true, deposit = true, withdraw = true, transfer = true, manage = true }

Rules.PERMISSIONS = {
    personal = { holder = USE },
    savings = { owner = OWN },
    shared = { owner = OWN, member = USE, viewer = { view = true, deposit = true } },
    business = { boss = USE },
    job = { boss = USE },
    gang = { boss = USE },
}

function Rules.can(accountType, role, action)
    local roles = Rules.PERMISSIONS[accountType]
    local allowed = roles and roles[role]
    return allowed ~= nil and allowed[action] == true
end

Rules.MEMBER_ROLES = { member = true, viewer = true }
Rules.OPENABLE = { savings = true, shared = true }

function Rules.canClose(accountType, balance)
    return Rules.OPENABLE[accountType] == true and balance == 0
end

local ATM_ACTIONS = { open = true, deposit = true, withdraw = true }

function Rules.allowedAt(placeKind, action)
    if placeKind == 'branch' then return true end
    return placeKind == 'atm' and ATM_ACTIONS[action] == true
end

--- The closest place whose kind is in the kinds set, within reach of pos; nil when none.
function Rules.nearestPlace(pos, places, kinds, reach)
    local best, bestDistance
    for _, place in ipairs(places) do
        if kinds[place.kind] then
            local dx, dy, dz = place.x - pos.x, place.y - pos.y, place.z - pos.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance <= reach and (not bestDistance or distance < bestDistance) then
                best, bestDistance = place, distance
            end
        end
    end
    return best
end

function Rules.transferProblem(fromNumber, toNumber)
    if not toNumber then return 'Enter a valid account number (VB-1234-5678)' end
    if fromNumber == toNumber then return 'Pick a different account to send to' end
    return nil
end

local MAP_LIMIT = 20000

function Rules.coords(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = value.x, value.y, value.z
    if not (isFinite(x) and isFinite(y) and isFinite(z)) then return nil end
    if math.abs(x) > MAP_LIMIT or math.abs(y) > MAP_LIMIT or math.abs(z) > MAP_LIMIT then return nil end
    return { x = x, y = y, z = z }
end

function Rules.heading(value)
    if not isFinite(value) then return 0 end
    return value % 360
end

function Rules.money(n)
    local text = tostring(math.floor(math.abs(n)))
    local grouped = text:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-$' or '$') .. grouped
end
