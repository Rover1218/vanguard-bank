-- Tiny test helper for the specs (describe / it / eq).
local T = { passed = 0, failed = 0, group = '' }

local function show(value, depth)
    depth = depth or 0
    if type(value) ~= 'table' then return type(value) == 'string' and ('%q'):format(value) or tostring(value) end
    if depth > 3 then return '{...}' end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = ('%s=%s'):format(tostring(key), show(value[key], depth + 1)) end
    return '{' .. table.concat(parts, ', ') .. '}'
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function T.describe(name, fn)
    T.group = name
    fn()
end

function T.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        print(('FAIL  %s > %s\n      %s'):format(T.group, name, tostring(err)))
    end
end

function T.eq(actual, expected, label)
    if not same(actual, expected) then
        error(('%sexpected %s, got %s'):format(label and (label .. ': ') or '', show(expected), show(actual)), 2)
    end
end

function T.summary()
    return ('%d passed, %d failed'):format(T.passed, T.failed)
end

return T
