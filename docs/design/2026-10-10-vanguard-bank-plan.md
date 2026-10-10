# Vanguard Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone FiveM QBCore bank (`vanguard-bank`) with placed branches and ATMs, five account types, transfers, an account-opening flow and a modern NUI, replacing qb-banking and holding Vanguard Business money.

**Architecture:** Server-authoritative Lua resource. Pure rules in `shared/rules.lua` (unit tested with fengari); MySQL stores accounts, members, history, places and pending credits; one request router; QBCore isolated in `bridge/`. Personal money stays in QBCore `bank`. `provide 'qb-banking'` + same-named exports keep old callers working. Vanguard Business talks to the bank through exports and falls back to its own balance when the bank is not running.

**Tech Stack:** Lua 5.4 (FiveM, lua54), oxmysql, qb-core, vanilla JS/CSS NUI, Node + fengari + luaparse for tests.

**Spec:** `docs/design/2026-10-10-vanguard-bank-design.md` (read it first).

## Global Constraints

- Resource name `vanguard-bank`; events prefixed `vanguard-bank:`; MIT © 2026 Rover; author `Rover`.
- Account numbers `VB-1234-5678`; amounts whole dollars `1 … Config.MaxAmount` (10 000 000).
- `Config.MaxOwnedAccounts = 3`; `Config.BusinessMinRank = 3` (Manager, Owner); `Config.ServerReach = 4.0`; `Config.InteractDistance = 2.0`.
- Admin ACE `vanguard.bank.admin`, command `/bankadmin`.
- Shared roles: `member` (deposit, withdraw, transfer) and `viewer` (view, deposit). Account names 1–24 chars; notes ≤ 60 chars; branch labels ≤ 30 chars.
- ATM: open, deposit, withdraw only. Everything else needs a placed branch within 4 m.
- Money reasons written by the bank start with `vanguard-bank` (the Personal history hook skips them).
- No secrets in `config.lua` (clients download it). No `console.log` in shipped JS.
- Tooling copied from `projects/vanguard-jobs` (fengari tests, luaparse lint). Git commits without attribution lines, no double quotes in messages.

## Review Focus

1. **Personal overdraw** — QBCore lets `bank` go negative; withdrawing / transferring more than the Personal balance must fail with "Not enough money". (Task 2 `Bridge.removeMoney` guard; Task 11 in-game check.)
2. **Messy amount input** — `"500"`, `12.5`, `-5`, `1e300`, `NaN`, empty must be refused, not rounded. (Task 1 `Rules.wholeAmount` tests.)
3. **Account numbers typed loosely** — `vb12345678`, `1234 5678`, ` VB-1234-5678 ` must resolve; `VB-123-45678`, letters, 9 digits must not. (Task 1 `Rules.parseNumber` tests.)
4. **Walking away with the panel open** — every action re-checks the player is at a placed branch / ATM; an ATM never allows transfer / open / members. (Task 1 `Rules.allowedAt` + `Rules.nearestPlace` tests; Task 6 `Places.require` used by every handler.)
5. **Access that changes** — a fired manager, a demoted police boss or a removed shared member loses access at the next request (no cached roles). (Task 3 `Access.roleOf` computes per request; Task 11 review.)

---

## File structure

```
projects/vanguard-bank/
  fxmanifest.lua           manifest, provide 'qb-banking'
  config.lua               brand, limits, ATM models, default branches
  shared/rules.lua         pure rules (amounts, numbers, permissions, places, coords, money text)
  bridge/server.lua        QBCore server access
  bridge/client.lua        notify, 3D text
  server/db.lua            schema + meta flags
  server/router.lua        request/response channel
  server/accounts.lua      account store (numbers, rows, members, atomic adjust)
  server/ledger.lua        history rows
  server/places.lua        placed branches / ATMs, defaults, admin
  server/access.lua        roles per account type, account list
  server/money.lua         credit / debit, deposit, withdraw, pending credits, Personal history hook
  server/branch.lua        open (panel data), lookup, transfer, open account, rename, close, members, history
  server/compat.lua        qb-banking exports
  server/business.lua      exports for Vanguard Business
  server/migrate.lua       one-time qb-banking copy
  server/main.lua          start-up order, hello, self-test
  client/main.lua          requests, NUI open/close, callbacks
  client/places.lua        blips, E prompts
  client/placement.lua     admin placement mode
  html/index.html, html/style.css, html/app.js   bank + ATM + placement bar + label prompt
  tests/rules_spec.lua, tests/run.js, tests/lib/t.lua, tests/syntax.js, tools/lua.js, package.json
  README.md, CHANGELOG.md, LICENSE
projects/vanguard-business/ (Task 9)
  server/banklink.lua (new), server/businesses.lua, server/boss.lua, server/admin.lua,
  server/payroll.lua, server/supplier.lua, server/register.lua, server/main.lua, fxmanifest.lua
```

---

### Task 1: Project tooling, config, manifest and rules

**Files:**
- Create: `package.json`, `tools/lua.js`, `tests/run.js`, `tests/lib/t.lua`, `tests/syntax.js` (copied from `projects/vanguard-jobs`, name changed), `config.lua`, `fxmanifest.lua`, `shared/rules.lua`, `tests/rules_spec.lua`, `data/.gitkeep`

**Interfaces:**
- Produces: `Rules.wholeAmount(value, max) -> integer|nil`, `Rules.cleanText(value, maxChars) -> string|nil`, `Rules.newNumber(random) -> string`, `Rules.parseNumber(text) -> string|nil`, `Rules.can(type, role, action) -> boolean`, `Rules.MEMBER_ROLES`, `Rules.OPENABLE`, `Rules.canClose(type, balance) -> boolean`, `Rules.allowedAt(placeKind, action) -> boolean`, `Rules.nearestPlace(pos, places, kinds, reach) -> place|nil`, `Rules.transferProblem(fromNumber, toNumber) -> string|nil`, `Rules.coords(value) -> {x,y,z}|nil`, `Rules.heading(value) -> number`, `Rules.money(n) -> '$1,234'`.

- [ ] **Step 1: Copy tooling**

```powershell
Set-Location F:\FiveMServer\projects
Copy-Item vanguard-jobs\tools -Destination vanguard-bank\tools -Recurse
New-Item -ItemType Directory -Force vanguard-bank\tests\lib, vanguard-bank\data | Out-Null
Copy-Item vanguard-jobs\tests\run.js, vanguard-jobs\tests\syntax.js vanguard-bank\tests\
Copy-Item vanguard-jobs\tests\lib\t.lua vanguard-bank\tests\lib\
[IO.File]::WriteAllText("$PWD\vanguard-bank\package.json", '{"name":"vanguard-bank-dev","private":true,"scripts":{"test":"node tests/run.js","lint":"node tests/syntax.js"},"devDependencies":{"fengari":"^0.1.5","luaparse":"^0.3.1"}}')
[IO.File]::WriteAllText("$PWD\vanguard-bank\data\.gitkeep", '')
Set-Location vanguard-bank; npm install --silent
```

- [ ] **Step 2: Write the failing tests** — `tests/rules_spec.lua`

```lua
local T = require('tests.lib.t')
dofile(ROOT .. '/shared/rules.lua')

T.describe('Rules.wholeAmount', function()
    T.it('accepts whole dollars in range', function()
        T.eq(Rules.wholeAmount(500, 1000), 500)
        T.eq(Rules.wholeAmount(1, 1000), 1)
        T.eq(Rules.wholeAmount(1000, 1000), 1000)
        T.eq(Rules.wholeAmount(40.0, 1000), 40)
    end)
    T.it('refuses everything else', function()
        T.eq(Rules.wholeAmount(0, 1000), nil, 'zero')
        T.eq(Rules.wholeAmount(-5, 1000), nil, 'negative')
        T.eq(Rules.wholeAmount(12.5, 1000), nil, 'cents')
        T.eq(Rules.wholeAmount(1001, 1000), nil, 'over max')
        T.eq(Rules.wholeAmount('500', 1000), nil, 'string')
        T.eq(Rules.wholeAmount(0 / 0, 1000), nil, 'NaN')
        T.eq(Rules.wholeAmount(1e300, math.huge), nil, 'huge')
        T.eq(Rules.wholeAmount(nil, 1000), nil, 'nil')
    end)
end)

T.describe('Rules.cleanText', function()
    T.it('trims and squashes spaces', function()
        T.eq(Rules.cleanText('  Holiday   fund ', 24), 'Holiday fund')
        T.eq(Rules.cleanText('a\nb', 24), 'a b')
    end)
    T.it('refuses empty, too long and non-text', function()
        T.eq(Rules.cleanText('   ', 24), nil)
        T.eq(Rules.cleanText(('x'):rep(25), 24), nil)
        T.eq(Rules.cleanText(5, 24), nil)
    end)
end)

T.describe('account numbers', function()
    T.it('makes VB-1234-5678 numbers', function()
        local calls = 0
        local function random() calls = calls + 1; return calls == 1 and 42 or 7 end
        T.eq(Rules.newNumber(random), 'VB-0042-0007')
    end)
    T.it('parses loose input', function()
        T.eq(Rules.parseNumber('VB-1234-5678'), 'VB-1234-5678')
        T.eq(Rules.parseNumber('vb12345678'), 'VB-1234-5678')
        T.eq(Rules.parseNumber(' 1234 5678 '), 'VB-1234-5678')
        T.eq(Rules.parseNumber('VB 1234-5678'), 'VB-1234-5678')
    end)
    T.it('refuses wrong numbers', function()
        T.eq(Rules.parseNumber('VB-123-4567'), nil, '7 digits')
        T.eq(Rules.parseNumber('123456789'), nil, '9 digits')
        T.eq(Rules.parseNumber('VB-12a4-5678'), nil, 'letter')
        T.eq(Rules.parseNumber(12345678), nil, 'number type')
        T.eq(Rules.parseNumber(('1'):rep(30)), nil, 'too long')
    end)
end)

T.describe('Rules.can', function()
    T.it('gives holders and owners everything they should have', function()
        T.eq(Rules.can('personal', 'holder', 'transfer'), true)
        T.eq(Rules.can('personal', 'holder', 'manage'), false)
        T.eq(Rules.can('savings', 'owner', 'manage'), true)
        T.eq(Rules.can('shared', 'owner', 'manage'), true)
    end)
    T.it('limits shared members and viewers', function()
        T.eq(Rules.can('shared', 'member', 'withdraw'), true)
        T.eq(Rules.can('shared', 'member', 'manage'), false)
        T.eq(Rules.can('shared', 'viewer', 'deposit'), true)
        T.eq(Rules.can('shared', 'viewer', 'withdraw'), false)
        T.eq(Rules.can('shared', 'viewer', 'transfer'), false)
    end)
    T.it('lets bosses use business, job and gang accounts but not manage them', function()
        for _, accountType in ipairs({ 'business', 'job', 'gang' }) do
            T.eq(Rules.can(accountType, 'boss', 'withdraw'), true, accountType)
            T.eq(Rules.can(accountType, 'boss', 'manage'), false, accountType)
        end
    end)
    T.it('refuses unknown types, roles and actions', function()
        T.eq(Rules.can('savings', 'member', 'view'), false)
        T.eq(Rules.can('loan', 'owner', 'view'), false)
        T.eq(Rules.can('savings', 'owner', 'fly'), false)
    end)
end)

T.describe('closing and opening', function()
    T.it('closes only empty savings / shared accounts', function()
        T.eq(Rules.canClose('savings', 0), true)
        T.eq(Rules.canClose('shared', 0), true)
        T.eq(Rules.canClose('savings', 1), false)
        T.eq(Rules.canClose('business', 0), false)
        T.eq(Rules.canClose('personal', 0), false)
    end)
    T.it('opens only savings and shared', function()
        T.eq(Rules.OPENABLE.savings, true)
        T.eq(Rules.OPENABLE.shared, true)
        T.eq(Rules.OPENABLE.business, nil)
    end)
end)

T.describe('places', function()
    local PLACES = {
        { id = 1, kind = 'branch', x = 0, y = 0, z = 0 },
        { id = 2, kind = 'atm', x = 3, y = 0, z = 0 },
        { id = 3, kind = 'atm', x = 100, y = 0, z = 0 },
    }
    T.it('finds the closest place of the wanted kinds in reach', function()
        T.eq(Rules.nearestPlace({ x = 2.5, y = 0, z = 0 }, PLACES, { branch = true, atm = true }, 4).id, 2)
        T.eq(Rules.nearestPlace({ x = 2.5, y = 0, z = 0 }, PLACES, { branch = true }, 4).id, 1)
        T.eq(Rules.nearestPlace({ x = 50, y = 0, z = 0 }, PLACES, { branch = true, atm = true }, 4), nil)
    end)
    T.it('lets ATMs only open, deposit and withdraw', function()
        T.eq(Rules.allowedAt('atm', 'withdraw'), true)
        T.eq(Rules.allowedAt('atm', 'deposit'), true)
        T.eq(Rules.allowedAt('atm', 'open'), true)
        T.eq(Rules.allowedAt('atm', 'transfer'), false)
        T.eq(Rules.allowedAt('atm', 'openAccount'), false)
        T.eq(Rules.allowedAt('branch', 'transfer'), true)
        T.eq(Rules.allowedAt(nil, 'withdraw'), false)
    end)
end)

T.describe('transfers, coords, money text', function()
    T.it('spots bad transfers', function()
        T.eq(Rules.transferProblem('VB-0000-0001', nil), 'Enter a valid account number (VB-1234-5678)')
        T.eq(Rules.transferProblem('VB-0000-0001', 'VB-0000-0001'), 'Pick a different account to send to')
        T.eq(Rules.transferProblem('VB-0000-0001', 'VB-0000-0002'), nil)
    end)
    T.it('accepts sane coords only', function()
        T.eq(Rules.coords({ x = 1, y = 2, z = 3 }), { x = 1, y = 2, z = 3 })
        T.eq(Rules.coords({ x = 1, y = 2 }), nil)
        T.eq(Rules.coords({ x = 0 / 0, y = 2, z = 3 }), nil)
        T.eq(Rules.coords({ x = 1e7, y = 2, z = 3 }), nil)
        T.eq(Rules.coords('here'), nil)
    end)
    T.it('normalises headings', function()
        T.eq(Rules.heading(370), 10)
        T.eq(Rules.heading(-90), 270)
        T.eq(Rules.heading('x'), 0)
    end)
    T.it('formats money', function()
        T.eq(Rules.money(0), '$0')
        T.eq(Rules.money(1234567), '$1,234,567')
        T.eq(Rules.money(-2500), '-$2,500')
    end)
end)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `node tests/run.js` — Expected: FAIL (`cannot open .../shared/rules.lua`).

- [ ] **Step 4: Write `shared/rules.lua`**

```lua
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
```

- [ ] **Step 5: Run tests** — `node tests/run.js` → Expected: all pass, `0 failed`.

- [ ] **Step 6: Write `config.lua`**

```lua
Config = {}

Config.Brand = { Title = 'VANGUARD', Subtitle = 'BANK', Accent = '#6366f1' }

Config.AdminAce = 'vanguard.bank.admin'   -- server.cfg: add_ace group.admin vanguard.bank.admin allow
Config.AdminCommand = 'bankadmin'         -- placement tool for branches and ATMs

Config.InteractDistance = 2.0   -- [E] prompt at a placed branch / ATM
Config.ServerReach = 4.0        -- the server's check: player within this many metres of a placed spot
Config.MaxOwnedAccounts = 3     -- savings + shared accounts one character may own
Config.MaxAmount = 10000000     -- largest single deposit / withdraw / transfer
Config.BusinessMinRank = 3      -- Vanguard Business ranks that see the business account (3 Manager, 4 Owner)
Config.HistoryPage = 50
Config.QuickAmounts = { 100, 500, 1000, 5000 }

Config.Blip = { sprite = 108, colour = 2, scale = 0.7, label = 'Bank' }
Config.AtmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }

-- Added once, the first time the bank starts with no places (admins can move / delete them).
Config.DefaultBranches = {
    { label = 'Fleeca Legion Square', coords = { x = 149.05, y = -1041.3, z = 29.37 } },
    { label = 'Fleeca Hawick', coords = { x = 313.32, y = -280.03, z = 54.17 } },
    { label = 'Fleeca Burton', coords = { x = -351.94, y = -50.72, z = 49.04 } },
    { label = 'Fleeca Rockford Hills', coords = { x = -1212.68, y = -331.83, z = 37.78 } },
    { label = 'Fleeca Great Ocean', coords = { x = -2961.67, y = 482.31, z = 15.7 } },
    { label = 'Fleeca Harmony', coords = { x = 1175.64, y = 2707.71, z = 38.09 } },
    { label = 'Pacific Standard', coords = { x = 247.65, y = 223.87, z = 106.29 } },
    { label = 'Blaine County Savings', coords = { x = -111.98, y = 6470.56, z = 31.63 } },
}
```

- [ ] **Step 7: Write `fxmanifest.lua`**

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vanguard-bank'
author 'Rover'
description 'Vanguard Bank - branches, ATMs, personal / savings / shared / business / job accounts'
version '1.0.0'

provide 'qb-banking' -- answers exports['qb-banking'] for scripts written for qb-banking

ui_page 'html/index.html'

shared_scripts { 'config.lua', 'shared/rules.lua' }
client_scripts { 'bridge/client.lua', 'client/main.lua', 'client/places.lua', 'client/placement.lua' }
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua', 'server/db.lua', 'server/router.lua', 'server/accounts.lua', 'server/ledger.lua',
    'server/places.lua', 'server/access.lua', 'server/money.lua', 'server/branch.lua',
    'server/compat.lua', 'server/business.lua', 'server/migrate.lua', 'server/main.lua',
}
files { 'html/index.html', 'html/style.css', 'html/app.js' }
dependencies { 'oxmysql', 'qb-core' }
```

- [ ] **Step 8: Commit** — `git add -A; git commit -m 'feat: rules, config, manifest and test tooling'`

---

### Task 2: Server foundation — bridge, schema, router, accounts, ledger

**Files:** Create `bridge/server.lua`, `server/db.lua`, `server/router.lua`, `server/accounts.lua`, `server/ledger.lua`

**Interfaces:**
- Consumes: `Rules.*` (Task 1).
- Produces: `Bridge.loaded(src)`, `Bridge.citizenid(src)`, `Bridge.name(src)`, `Bridge.nameOf(citizenid) -> string|nil`, `Bridge.money(src, account) -> number`, `Bridge.addMoney(src, account, amount, reason) -> bool`, `Bridge.removeMoney(src, account, amount, reason) -> bool` (refuses when balance < amount), `Bridge.sourceOf(citizenid) -> src|nil`, `Bridge.job(src)/Bridge.gang(src) -> {name,label,isBoss}|nil`, `Bridge.isJob(name)/Bridge.isGang(name) -> bool`, `Bridge.jobLabel(name)/Bridge.gangLabel(name) -> string|nil`, `Bridge.notify(src, msg, kind)`; `Db.init()`, `Db.meta(key) -> string|nil`, `Db.setMeta(key, value)`; `Router.on(action, fn(src, data))`, `Router.ok(message, data)`, `Router.fail(message)`, `Router.log(src, message)`; `Accounts.newNumber()`, `Accounts.personalNumber(cid)`, `Accounts.byNumber(number)`, `Accounts.byRef(type, ref)`, `Accounts.create(type, name, owner, ref, balance)`, `Accounts.ensureRef(type, ref, name)`, `Accounts.adjust(id, delta) -> bool`, `Accounts.ownedCount(cid)`, `Accounts.owned(cid)`, `Accounts.memberships(cid)`, `Accounts.roleOf(id, cid)`, `Accounts.members(id)`, `Accounts.setMember(id, cid, name, role)`, `Accounts.removeMember(id, cid)`, `Accounts.rename(id, name)`, `Accounts.close(id) -> bool`; `Ledger.add(number, kind, amount, actor, note)`, `Ledger.page(number, beforeId, limit) -> rows`.

- [ ] **Step 1: `bridge/server.lua`**

```lua
-- Vanguard Bank - server bridge (QBCore). The only server file that knows the framework.

Bridge = { ready = false }

local QBCore = exports['qb-core']:GetCoreObject()

local function player(src) return QBCore.Functions.GetPlayer(src) end

function Bridge.loaded(src) return player(src) ~= nil end

function Bridge.citizenid(src)
    local p = player(src)
    return p and p.PlayerData.citizenid or nil
end

local function fullName(info)
    if type(info) ~= 'table' then return nil end
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
    return name ~= '' and name or nil
end

function Bridge.name(src)
    local p = player(src)
    return (p and fullName(p.PlayerData.charinfo)) or GetPlayerName(src) or 'Unknown'
end

--- Character name for a citizenid, online or not (shown before a transfer is confirmed).
function Bridge.nameOf(citizenid)
    local online = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if online then return fullName(online.PlayerData.charinfo) end
    local raw = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
    local ok, info = pcall(json.decode, raw or '')
    return ok and fullName(info) or nil
end

function Bridge.money(src, account)
    local p = player(src)
    return p and (p.PlayerData.money[account] or 0) or 0
end

function Bridge.addMoney(src, account, amount, reason)
    local p = player(src)
    if not p then return false end
    return p.Functions.AddMoney(account, amount, reason) ~= false
end

--- QBCore lets 'bank' go below zero; the bank never does. Check and remove happen in one tick.
function Bridge.removeMoney(src, account, amount, reason)
    local p = player(src)
    if not p or (p.PlayerData.money[account] or 0) < amount then return false end
    return p.Functions.RemoveMoney(account, amount, reason) ~= false
end

function Bridge.sourceOf(citizenid)
    local p = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    return p and p.PlayerData.source or nil
end

local function group(src, key)
    local p = player(src)
    local data = p and p.PlayerData[key]
    if not data then return nil end
    return { name = data.name, label = data.label, isBoss = data.isboss == true }
end

function Bridge.job(src) return group(src, 'job') end
function Bridge.gang(src) return group(src, 'gang') end
function Bridge.isJob(name) return QBCore.Shared.Jobs[name] ~= nil end
function Bridge.isGang(name) return QBCore.Shared.Gangs[name] ~= nil end
function Bridge.jobLabel(name) return QBCore.Shared.Jobs[name] and QBCore.Shared.Jobs[name].label or nil end
function Bridge.gangLabel(name) return QBCore.Shared.Gangs[name] and QBCore.Shared.Gangs[name].label or nil end

function Bridge.notify(src, message, kind)
    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary', 5000)
end

function Bridge.onPlayerLoaded(handler)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(p) handler(p.PlayerData.source) end)
end
```

- [ ] **Step 2: `server/db.lua`**

```lua
-- Vanguard Bank - tables (created automatically) and one-time flags.

Db = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS vbank_accounts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        number VARCHAR(12) NOT NULL UNIQUE,
        type VARCHAR(10) NOT NULL,
        name VARCHAR(40) NOT NULL,
        owner VARCHAR(60) NULL,
        ref VARCHAR(60) NULL,
        balance BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_owner (owner),
        UNIQUE KEY uniq_ref (type, ref)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_personal (
        citizenid VARCHAR(60) PRIMARY KEY,
        number VARCHAR(12) NOT NULL UNIQUE
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_members (
        account_id INT NOT NULL,
        citizenid VARCHAR(60) NOT NULL,
        name VARCHAR(60) NOT NULL,
        role VARCHAR(10) NOT NULL,
        PRIMARY KEY (account_id, citizenid),
        INDEX idx_member (citizenid),
        CONSTRAINT fk_vbank_members FOREIGN KEY (account_id) REFERENCES vbank_accounts (id) ON DELETE CASCADE
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_transactions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        account VARCHAR(12) NOT NULL,
        kind VARCHAR(16) NOT NULL,
        amount BIGINT NOT NULL,
        actor VARCHAR(60) NULL,
        note VARCHAR(80) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_account (account, id)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_pending (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(60) NOT NULL,
        amount BIGINT NOT NULL,
        note VARCHAR(80) NULL,
        INDEX idx_pending (citizenid)
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_places (
        id INT AUTO_INCREMENT PRIMARY KEY,
        kind VARCHAR(8) NOT NULL,
        label VARCHAR(40) NOT NULL,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
        heading DOUBLE NOT NULL DEFAULT 0
    )]],
    [[CREATE TABLE IF NOT EXISTS vbank_meta (
        k VARCHAR(40) PRIMARY KEY,
        v VARCHAR(80) NOT NULL
    )]],
}

function Db.init()
    for _, statement in ipairs(SCHEMA) do MySQL.query.await(statement) end
end

function Db.meta(key)
    return MySQL.scalar.await('SELECT v FROM vbank_meta WHERE k = ?', { key })
end

function Db.setMeta(key, value)
    MySQL.query.await('INSERT INTO vbank_meta (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { key, value })
end
```

- [ ] **Step 3: `server/router.lua`** — copy `projects/vanguard-jobs/server/router.lua`, then change: header comment to `-- Vanguard Bank - one request/response channel. Handlers validate their own input.`; `RATE_LIMIT` 15 → 10; event names `vanguard-jobs:request` → `vanguard-bank:request` and `vanguard-jobs:response` → `vanguard-bank:response`; and before the handler lookup add `if not Bridge.ready then return reply(Router.fail('The bank is starting, try again in a moment')) end` (tables and places load first). Everything else identical (rate limit, unknown action, `Bridge.loaded` check, pcall, `playerDropped` cleanup).

- [ ] **Step 4: `server/accounts.lua`**

```lua
-- Vanguard Bank - account store. Balances change only through Accounts.adjust (atomic, never below zero).

Accounts = {}

local RESOURCE = GetCurrentResourceName()
local NUMBER_TRIES = 20

local function normalise(row)
    if row then row.balance = tonumber(row.balance) or 0 end
    return row
end

function Accounts.newNumber()
    for _ = 1, NUMBER_TRIES do
        local number = Rules.newNumber(math.random)
        local taken = MySQL.scalar.await(
            'SELECT 1 FROM vbank_accounts WHERE number = ? UNION SELECT 1 FROM vbank_personal WHERE number = ?',
            { number, number })
        if not taken then return number end
    end
    error('no free account number found')
end

--- The Personal account number of a character (made on first use).
function Accounts.personalNumber(citizenid)
    local number = MySQL.scalar.await('SELECT number FROM vbank_personal WHERE citizenid = ?', { citizenid })
    if number then return number end
    MySQL.insert.await('INSERT IGNORE INTO vbank_personal (citizenid, number) VALUES (?, ?)', { citizenid, Accounts.newNumber() })
    return MySQL.scalar.await('SELECT number FROM vbank_personal WHERE citizenid = ?', { citizenid })
end

--- Any account by its number. Personal accounts come back as { type = 'personal', number, owner, name }.
function Accounts.byNumber(number)
    local row = MySQL.single.await('SELECT * FROM vbank_accounts WHERE number = ?', { number })
    if row then return normalise(row) end
    local citizenid = MySQL.scalar.await('SELECT citizenid FROM vbank_personal WHERE number = ?', { number })
    if citizenid then return { type = 'personal', number = number, owner = citizenid, name = 'Personal' } end
    return nil
end

function Accounts.byRef(accountType, ref)
    return normalise(MySQL.single.await('SELECT * FROM vbank_accounts WHERE type = ? AND ref = ?', { accountType, tostring(ref) }))
end

function Accounts.create(accountType, name, owner, ref, balance)
    local number = Accounts.newNumber()
    local id = MySQL.insert.await(
        'INSERT INTO vbank_accounts (number, type, name, owner, ref, balance) VALUES (?, ?, ?, ?, ?, ?)',
        { number, accountType, name, owner, ref ~= nil and tostring(ref) or nil, balance or 0 })
    return id and Accounts.byNumber(number) or nil
end

--- The business / job / gang account for ref, created when missing; a changed name is saved.
function Accounts.ensureRef(accountType, ref, name)
    local existing = Accounts.byRef(accountType, ref)
    if existing then
        if name and existing.name ~= name then
            MySQL.update.await('UPDATE vbank_accounts SET name = ? WHERE id = ?', { name, existing.id })
            existing.name = name
        end
        return existing
    end
    local ok, created = pcall(Accounts.create, accountType, name or tostring(ref), nil, ref, 0)
    return (ok and created) or Accounts.byRef(accountType, ref) -- made by someone else at the same moment
end

--- Adds delta (negative to take) unless the balance would go below zero. Never throws.
function Accounts.adjust(id, delta)
    local ok, changed = pcall(MySQL.update.await,
        'UPDATE vbank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? >= 0', { delta, id, delta })
    if not ok then
        print(('[%s] balance change of %d on account %s failed: %s'):format(RESOURCE, delta, tostring(id), tostring(changed)))
        return false
    end
    return changed == 1
end

function Accounts.ownedCount(citizenid)
    return MySQL.scalar.await("SELECT COUNT(*) FROM vbank_accounts WHERE owner = ? AND type IN ('savings', 'shared')", { citizenid }) or 0
end

function Accounts.owned(citizenid)
    local rows = MySQL.query.await("SELECT * FROM vbank_accounts WHERE owner = ? AND type IN ('savings', 'shared') ORDER BY id", { citizenid }) or {}
    for _, row in ipairs(rows) do normalise(row) end
    return rows
end

--- Shared accounts this character is a member of (not owner), each with .role.
function Accounts.memberships(citizenid)
    local rows = MySQL.query.await(
        'SELECT a.*, m.role FROM vbank_members m JOIN vbank_accounts a ON a.id = m.account_id WHERE m.citizenid = ? ORDER BY a.id',
        { citizenid }) or {}
    for _, row in ipairs(rows) do normalise(row) end
    return rows
end

function Accounts.roleOf(accountId, citizenid)
    return MySQL.scalar.await('SELECT role FROM vbank_members WHERE account_id = ? AND citizenid = ?', { accountId, citizenid })
end

function Accounts.members(accountId)
    return MySQL.query.await('SELECT citizenid, name, role FROM vbank_members WHERE account_id = ? ORDER BY name', { accountId }) or {}
end

function Accounts.setMember(accountId, citizenid, name, role)
    MySQL.query.await(
        'INSERT INTO vbank_members (account_id, citizenid, name, role) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role), name = VALUES(name)',
        { accountId, citizenid, name, role })
end

function Accounts.removeMember(accountId, citizenid)
    return MySQL.update.await('DELETE FROM vbank_members WHERE account_id = ? AND citizenid = ?', { accountId, citizenid }) == 1
end

function Accounts.rename(id, name)
    MySQL.update.await('UPDATE vbank_accounts SET name = ? WHERE id = ?', { name, id })
end

--- Deletes the account only while it is empty (members go with it). True when it was closed.
function Accounts.close(id)
    return MySQL.update.await('DELETE FROM vbank_accounts WHERE id = ? AND balance = 0', { id }) == 1
end
```

- [ ] **Step 5: `server/ledger.lua`**

```lua
-- Vanguard Bank - account history. kinds: deposit, withdraw, transfer_in, transfer_out,
-- income, payment, refund, system.

Ledger = {}

local function clip(text, size)
    if type(text) ~= 'string' then return nil end
    return text:sub(1, size)
end

function Ledger.add(number, kind, amount, actor, note)
    MySQL.insert('INSERT INTO vbank_transactions (account, kind, amount, actor, note) VALUES (?, ?, ?, ?, ?)',
        { number, kind, amount, clip(actor, 60), clip(note, 80) })
end

--- Newest first; beforeId pages further back.
function Ledger.page(number, beforeId, limit)
    if beforeId then
        return MySQL.query.await(
            'SELECT id, kind, amount, actor, note, UNIX_TIMESTAMP(created_at) AS time FROM vbank_transactions WHERE account = ? AND id < ? ORDER BY id DESC LIMIT ?',
            { number, beforeId, limit }) or {}
    end
    return MySQL.query.await(
        'SELECT id, kind, amount, actor, note, UNIX_TIMESTAMP(created_at) AS time FROM vbank_transactions WHERE account = ? ORDER BY id DESC LIMIT ?',
        { number, limit }) or {}
end
```

- [ ] **Step 6: Lint** — `node tests/syntax.js` → Expected: `syntax ok` (app.js missing makes it fail: create an empty `html/app.js` placeholder file now; Task 10 fills it).

- [ ] **Step 7: Commit** — `git add -A; git commit -m 'feat: server foundation (bridge, schema, router, accounts, ledger)'`

---

### Task 3: Access — roles for every account type and the account list

**Files:** Create `server/access.lua`

**Interfaces:**
- Consumes: `Bridge.*`, `Accounts.*`, `Rules.can`, `Rules.parseNumber`, `Config.BusinessMinRank`; Vanguard Business export `bankRoles(citizenid) -> { {id=number, name=string, rank=number}, ... }` (Task 9).
- Produces: `Access.roleOf(src, account) -> role|nil`, `Access.check(src, number, action) -> account, role | nil, message`, `Access.list(src) -> { {account, role}, ... }`, `Access.view(entry) -> table` (what the UI gets).

- [ ] **Step 1: `server/access.lua`**

```lua
-- Vanguard Bank - who may do what with which account. Roles are worked out on every request, so a
-- fired manager, a demoted boss or a removed member loses access straight away.

Access = {}

local BUSINESS = 'vanguard-business'
local ACTIONS = { 'deposit', 'withdraw', 'transfer', 'manage' }

--- { [businessId] = { id, name, rank } } for businesses whose account this character may use.
local function businessRoles(citizenid)
    if GetResourceState(BUSINESS) ~= 'started' then return {} end
    local ok, roles = pcall(function() return exports[BUSINESS]:bankRoles(citizenid) end)
    if not ok or type(roles) ~= 'table' then return {} end
    local result = {}
    for _, entry in ipairs(roles) do
        if type(entry) == 'table' and type(entry.id) == 'number' and type(entry.rank) == 'number'
            and entry.rank >= Config.BusinessMinRank then
            result[entry.id] = entry
        end
    end
    return result
end

local function isBossOf(group, name)
    return group ~= nil and group.isBoss and group.name == name
end

function Access.roleOf(src, account)
    local citizenid = Bridge.citizenid(src)
    if not citizenid or not account then return nil end
    local accountType = account.type
    if accountType == 'personal' then return account.owner == citizenid and 'holder' or nil end
    if accountType == 'savings' or accountType == 'shared' then
        if account.owner == citizenid then return 'owner' end
        if accountType == 'shared' then return Accounts.roleOf(account.id, citizenid) end
        return nil
    end
    if accountType == 'business' then return businessRoles(citizenid)[tonumber(account.ref)] and 'boss' or nil end
    if accountType == 'job' then return isBossOf(Bridge.job(src), account.ref) and 'boss' or nil end
    if accountType == 'gang' then return isBossOf(Bridge.gang(src), account.ref) and 'boss' or nil end
    return nil
end

--- The account behind number if the caller may do action on it: account, role or nil, message.
function Access.check(src, number, action)
    local parsed = Rules.parseNumber(number)
    local account = parsed and Accounts.byNumber(parsed)
    if not account then return nil, 'That account does not exist' end
    local role = Access.roleOf(src, account)
    if not role then return nil, 'You do not have access to that account' end
    if not Rules.can(account.type, role, action) then return nil, 'Your role on this account does not allow that' end
    return account, role
end

--- Every account the character can see: Personal, owned, shared, business, job, gang.
function Access.list(src)
    local citizenid = Bridge.citizenid(src)
    local list = {}
    local function add(account, role) if account then list[#list + 1] = { account = account, role = role } end end

    add({ type = 'personal', number = Accounts.personalNumber(citizenid), owner = citizenid, name = 'Personal',
        balance = Bridge.money(src, 'bank') }, 'holder')
    for _, account in ipairs(Accounts.owned(citizenid)) do add(account, 'owner') end
    for _, account in ipairs(Accounts.memberships(citizenid)) do add(account, account.role) end

    local businesses = {}
    for id, entry in pairs(businessRoles(citizenid)) do businesses[#businesses + 1] = { id = id, name = entry.name } end
    table.sort(businesses, function(a, b) return a.id < b.id end)
    for _, business in ipairs(businesses) do add(Accounts.ensureRef('business', business.id, business.name), 'boss') end

    local job = Bridge.job(src)
    if job and job.isBoss then add(Accounts.ensureRef('job', job.name, job.label), 'boss') end
    local gang = Bridge.gang(src)
    if gang and gang.isBoss and gang.name ~= 'none' then add(Accounts.ensureRef('gang', gang.name, gang.label), 'boss') end
    return list
end

--- What the UI shows for one account (the server still re-checks every action).
function Access.view(entry)
    local account = entry.account
    local can = {}
    for _, action in ipairs(ACTIONS) do can[action] = Rules.can(account.type, entry.role, action) end
    return {
        number = account.number, type = account.type, name = account.name,
        balance = account.balance or 0, role = entry.role, can = can,
    }
end
```

- [ ] **Step 2: Lint** — `node tests/syntax.js` → `syntax ok`.
- [ ] **Step 3: Commit** — `git commit -am 'feat: access rules per account type and account list'` (use `git add -A` first).

---

### Task 4: Places — placed branches / ATMs (server)

**Files:** Create `server/places.lua`

**Interfaces:**
- Consumes: `Rules.nearestPlace`, `Rules.allowedAt`, `Rules.coords`, `Rules.heading`, `Rules.cleanText`, `Db.meta/setMeta`, `Router.*`, `Config.*`.
- Produces: `Places.load()`, `Places.list()`, `Places.add(kind, label, coords, heading) -> place`, `Places.remove(id)`, `Places.at(src, kinds?) -> place|nil`, `Places.require(src, action) -> place | nil, message`, `Places.broadcast(target?)`; client event `vanguard-bank:places(list)`; client event `vanguard-bank:placement()`; router actions `placeAdd {kind, label, coords, heading}`, `placeRemove {id}` (admins).

- [ ] **Step 1: `server/places.lua`**

```lua
-- Vanguard Bank - placed branches and ATMs. Every money action is checked against these.

Places = {}

local ANY = { branch = true, atm = true }
local KINDS = { branch = true, atm = true }
local PLACE_REACH = 25.0 -- an admin places within this distance of themselves
local places = {}       -- id -> { id, kind, label, x, y, z, heading }

function Places.list()
    local list = {}
    for _, place in pairs(places) do list[#list + 1] = place end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function Places.add(kind, label, coords, heading)
    local id = MySQL.insert.await('INSERT INTO vbank_places (kind, label, x, y, z, heading) VALUES (?, ?, ?, ?, ?, ?)',
        { kind, label, coords.x, coords.y, coords.z, heading or 0.0 })
    if not id then return nil end
    places[id] = { id = id, kind = kind, label = label, x = coords.x, y = coords.y, z = coords.z, heading = heading or 0.0 }
    return places[id]
end

function Places.remove(id)
    MySQL.update.await('DELETE FROM vbank_places WHERE id = ?', { id })
    places[id] = nil
end

--- Loads places; the very first time (no places, never seeded) adds Config.DefaultBranches.
function Places.load()
    places = {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM vbank_places') or {}) do places[row.id] = row end
    if next(places) == nil and not Db.meta('defaults_added') then
        for _, branch in ipairs(Config.DefaultBranches) do Places.add('branch', branch.label, branch.coords, 0.0) end
    end
    Db.setMeta('defaults_added', '1')
end

local function position(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

function Places.at(src, kinds)
    local pos = position(src)
    return pos and Rules.nearestPlace(pos, Places.list(), kinds or ANY, Config.ServerReach) or nil
end

--- The branch / ATM the player stands at, if it allows action; else nil + message.
function Places.require(src, action)
    local place = Places.at(src)
    if not place then return nil, 'Go to a bank branch or ATM' end
    if not Rules.allowedAt(place.kind, action) then return nil, 'Go to a bank branch for that' end
    return place
end

function Places.broadcast(target)
    TriggerClientEvent('vanguard-bank:places', target or -1, Places.list())
end

local function isAdmin(src)
    return IsPlayerAceAllowed(src, Config.AdminAce)
end

RegisterCommand(Config.AdminCommand, function(src)
    if src == 0 or not isAdmin(src) then return end
    TriggerClientEvent('vanguard-bank:placement', src)
end, false)

Router.on('placeAdd', function(src, data)
    if not isAdmin(src) then return Router.fail('Admins only') end
    local kind = KINDS[data.kind] and data.kind or nil
    local coords = Rules.coords(data.coords)
    if not kind or not coords then return Router.fail('Aim at a spot first') end
    local here = position(src)
    if not here or #(vector3(here.x, here.y, here.z) - vector3(coords.x, coords.y, coords.z)) > PLACE_REACH then
        return Router.fail('Stand closer to the spot')
    end
    local label = kind == 'atm' and 'ATM' or Rules.cleanText(data.label, 30)
    if not label then return Router.fail('Give the branch a name (up to 30 characters)') end
    local place = Places.add(kind, label, coords, Rules.heading(data.heading))
    if not place then return Router.fail('Could not save that spot') end
    Places.broadcast()
    Router.log(src, ('placed %s "%s" (#%d)'):format(kind, label, place.id))
    return Router.ok(('%s placed'):format(kind == 'atm' and 'ATM' or label))
end)

Router.on('placeRemove', function(src, data)
    if not isAdmin(src) then return Router.fail('Admins only') end
    local place = type(data.id) == 'number' and places[data.id] or nil
    if not place then return Router.fail('Nothing to remove there') end
    Places.remove(place.id)
    Places.broadcast()
    Router.log(src, ('removed %s "%s" (#%d)'):format(place.kind, place.label, place.id))
    return Router.ok(('%s removed'):format(place.kind == 'atm' and 'ATM' or place.label))
end)
```

- [ ] **Step 2: Lint** → `syntax ok`. **Step 3: Commit** — `feat: placed branches and ATMs (server)`.

---

### Task 5: Money — credit / debit, deposit, withdraw, pending credits, Personal history

**Files:** Create `server/money.lua`

**Interfaces:**
- Consumes: `Accounts.adjust`, `Ledger.add`, `Bridge.*`, `Places.require`, `Access.check`, `Rules.wholeAmount`, `Rules.money`; Vanguard Business export `noteBankMovement(businessId, kind, amount, actor, note)` (Task 9).
- Produces: `Money.REASON = 'vanguard-bank'`, `Money.credit(account, amount, actor, note, kind) -> bool`, `Money.debit(src, account, amount, actor, note, kind) -> bool`, `Money.payPending(src)`; router actions `deposit {number, amount}`, `withdraw {number, amount}`.

- [ ] **Step 1: `server/money.lua`**

```lua
-- Vanguard Bank - moving money in and out of accounts.

Money = { REASON = 'vanguard-bank' }

local BUSINESS = 'vanguard-business'

--- Business accounts: Vanguard Business keeps its own money log too.
local function tellBusiness(account, kind, amount, actor, note)
    if account.type ~= 'business' or GetResourceState(BUSINESS) ~= 'started' then return end
    pcall(function() exports[BUSINESS]:noteBankMovement(tonumber(account.ref), kind, amount, actor, note) end)
end

--- Puts money into an account. Personal: online -> QBCore bank; offline -> paid on next login.
function Money.credit(account, amount, actor, note, kind)
    if account.type == 'personal' then
        local target = Bridge.sourceOf(account.owner)
        if target then
            if not Bridge.addMoney(target, 'bank', amount, Money.REASON) then return false end
        else
            local id = MySQL.insert.await('INSERT INTO vbank_pending (citizenid, amount, note) VALUES (?, ?, ?)',
                { account.owner, amount, note })
            if not id then return false end
        end
    elseif not Accounts.adjust(account.id, amount) then
        return false
    end
    Ledger.add(account.number, kind, amount, actor, note)
    tellBusiness(account, kind, amount, actor, note)
    return true
end

--- Takes money from an account the caller (src) may use. Never below zero.
function Money.debit(src, account, amount, actor, note, kind)
    if account.type == 'personal' then
        if not Bridge.removeMoney(src, 'bank', amount, Money.REASON) then return false end
    elseif not Accounts.adjust(account.id, -amount) then
        return false
    end
    Ledger.add(account.number, kind, -amount, actor, note)
    tellBusiness(account, kind, -amount, actor, note)
    return true
end

local function amountFrom(data)
    return Rules.wholeAmount(data.amount, Config.MaxAmount)
end

local function badAmount()
    return Router.fail(('Enter an amount from $1 to %s'):format(Rules.money(Config.MaxAmount)))
end

Router.on('deposit', function(src, data)
    local place, where = Places.require(src, 'deposit')
    if not place then return Router.fail(where) end
    local amount = amountFrom(data)
    if not amount then return badAmount() end
    local account, problem = Access.check(src, data.number, 'deposit')
    if not account then return Router.fail(problem) end
    if not Bridge.removeMoney(src, 'cash', amount, Money.REASON) then return Router.fail('You don\'t have that much cash') end
    if not Money.credit(account, amount, Bridge.name(src), place.label, 'deposit') then
        Bridge.addMoney(src, 'cash', amount, Money.REASON)
        return Router.fail('The deposit failed - your cash was returned')
    end
    return Router.ok(('Deposited %s'):format(Rules.money(amount)))
end)

Router.on('withdraw', function(src, data)
    local place, where = Places.require(src, 'withdraw')
    if not place then return Router.fail(where) end
    local amount = amountFrom(data)
    if not amount then return badAmount() end
    local account, problem = Access.check(src, data.number, 'withdraw')
    if not account then return Router.fail(problem) end
    local actor = Bridge.name(src)
    if not Money.debit(src, account, amount, actor, place.label, 'withdraw') then return Router.fail('Not enough money in that account') end
    if not Bridge.addMoney(src, 'cash', amount, Money.REASON) then
        Money.credit(account, amount, actor, 'Withdrawal failed - returned', 'refund')
        return Router.fail('The withdrawal failed - the money stays in the account')
    end
    return Router.ok(('Withdrew %s'):format(Rules.money(amount)))
end)

--- Transfers sent while this character was offline. Each row is deleted before paying, so it pays once.
function Money.payPending(src)
    local citizenid = Bridge.citizenid(src)
    if not citizenid then return end
    for _, row in ipairs(MySQL.query.await('SELECT id, amount, note FROM vbank_pending WHERE citizenid = ?', { citizenid }) or {}) do
        if MySQL.update.await('DELETE FROM vbank_pending WHERE id = ?', { row.id }) == 1 then
            local amount = tonumber(row.amount) or 0
            if Bridge.addMoney(src, 'bank', amount, Money.REASON) then
                Bridge.notify(src, ('Vanguard Bank: %s arrived while you were away'):format(Rules.money(amount)), 'success')
            else
                MySQL.insert.await('INSERT INTO vbank_pending (citizenid, amount, note) VALUES (?, ?, ?)', { citizenid, amount, row.note })
            end
        end
    end
end

Bridge.onPlayerLoaded(Money.payPending)

-- Personal history also shows bank money that other scripts move (paychecks, jobs, shops).
AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, amount, operation, reason)
    if moneyType ~= 'bank' or (operation ~= 'add' and operation ~= 'remove') then return end
    if type(reason) == 'string' and reason:sub(1, #Money.REASON) == Money.REASON then return end
    local citizenid = Bridge.citizenid(src)
    if not citizenid or type(amount) ~= 'number' then return end
    local signed = operation == 'add' and amount or -amount
    Ledger.add(Accounts.personalNumber(citizenid), operation == 'add' and 'income' or 'payment', signed, nil, reason)
end)
```

- [ ] **Step 2: Lint** → `syntax ok`. **Step 3: Commit** — `feat: deposit, withdraw, pending credits, personal history`.

---

### Task 6: Branch — panel data, lookup, transfer, accounts, members, history

**Files:** Create `server/branch.lua`

**Interfaces:**
- Consumes: everything above.
- Produces router actions:
  - `open {}` → `{ mode = 'branch'|'atm', place = label, name, cash, accounts = [Access.view…], owned, maxOwned, maxAmount, quick }` (ATM: only accounts with deposit or withdraw).
  - `history {number, before?}` → `{ rows }` (branch only).
  - `lookup {number}` → `{ number, label }`.
  - `transfer {from, to, amount, note?}`; `openAccount {type, name}` → `{ number, name, type }`; `rename {number, name}`; `closeAccount {number}`;
  - `members {number}` → `{ members = [{citizenid, name, role}] }`; `addMember {number, target, role}`; `setRole {number, citizenid, role}`; `removeMember {number, citizenid}`; `leave {number}`.

- [ ] **Step 1: `server/branch.lua`**

```lua
-- Vanguard Bank - the panel's data and everything only a branch can do.

local NOTE_CHARS, NAME_CHARS = 60, 24

local function atBranch(src, action)
    local place, where = Places.require(src, action)
    if not place then return nil, where end
    return place
end

Router.on('open', function(src)
    local place, where = Places.require(src, 'open')
    if not place then return Router.fail(where) end
    local accounts = {}
    for _, entry in ipairs(Access.list(src)) do
        local view = Access.view(entry)
        if place.kind == 'branch' or view.can.deposit or view.can.withdraw then accounts[#accounts + 1] = view end
    end
    return Router.ok(nil, {
        mode = place.kind, place = place.label, name = Bridge.name(src), cash = Bridge.money(src, 'cash'),
        accounts = accounts, owned = Accounts.ownedCount(Bridge.citizenid(src)), maxOwned = Config.MaxOwnedAccounts,
        maxAmount = Config.MaxAmount, quick = Config.QuickAmounts,
    })
end)

Router.on('history', function(src, data)
    local _, where = atBranch(src, 'history')
    if where then return Router.fail(where) end
    local account, problem = Access.check(src, data.number, 'view')
    if not account then return Router.fail(problem) end
    local before = type(data.before) == 'number' and data.before or nil
    return Router.ok(nil, { rows = Ledger.page(account.number, before, Config.HistoryPage) })
end)

local function describe(account)
    if account.type == 'personal' then
        return ('%s - Personal'):format(Bridge.nameOf(account.owner) or 'Customer')
    elseif account.type == 'savings' then
        return ('%s - %s'):format(Bridge.nameOf(account.owner) or 'Customer', account.name)
    end
    return account.name
end

Router.on('lookup', function(src, data)
    local _, where = atBranch(src, 'lookup')
    if where then return Router.fail(where) end
    local number = Rules.parseNumber(data.number)
    local account = number and Accounts.byNumber(number)
    if not account then return Router.fail('No account with that number') end
    return Router.ok(nil, { number = account.number, label = describe(account) })
end)

Router.on('transfer', function(src, data)
    local _, where = atBranch(src, 'transfer')
    if where then return Router.fail(where) end
    local amount = Rules.wholeAmount(data.amount, Config.MaxAmount)
    if not amount then return Router.fail(('Enter an amount from $1 to %s'):format(Rules.money(Config.MaxAmount))) end
    local note = nil
    if data.note ~= nil and data.note ~= '' then
        note = Rules.cleanText(data.note, NOTE_CHARS)
        if not note then return Router.fail(('Notes are up to %d characters'):format(NOTE_CHARS)) end
    end
    local from, problem = Access.check(src, data.from, 'transfer')
    if not from then return Router.fail(problem) end
    local toNumber = Rules.parseNumber(data.to)
    local issue = Rules.transferProblem(from.number, toNumber)
    if issue then return Router.fail(issue) end
    local to = Accounts.byNumber(toNumber)
    if not to then return Router.fail('No account with that number') end

    local actor = Bridge.name(src)
    local suffix = note and (' - ' .. note) or ''
    if not Money.debit(src, from, amount, actor, ('To %s%s'):format(to.number, suffix), 'transfer_out') then
        return Router.fail('Not enough money in that account')
    end
    if not Money.credit(to, amount, actor, ('From %s%s'):format(from.number, suffix), 'transfer_in') then
        Money.credit(from, amount, actor, ('Transfer to %s failed - returned'):format(to.number), 'refund')
        return Router.fail('The transfer failed - the money was returned')
    end
    if to.type == 'personal' then
        local receiver = Bridge.sourceOf(to.owner)
        if receiver then Bridge.notify(receiver, ('Vanguard Bank: %s received from %s'):format(Rules.money(amount), actor), 'success') end
    end
    Router.log(src, ('transferred %d from %s to %s'):format(amount, from.number, to.number))
    return Router.ok(('Sent %s to %s'):format(Rules.money(amount), to.number))
end)

Router.on('openAccount', function(src, data)
    local _, where = atBranch(src, 'openAccount')
    if where then return Router.fail(where) end
    local accountType = Rules.OPENABLE[data.type] and data.type or nil
    if not accountType then return Router.fail('Pick Savings or Shared') end
    local name = Rules.cleanText(data.name, NAME_CHARS)
    if not name then return Router.fail(('Give the account a name (up to %d characters)'):format(NAME_CHARS)) end
    local citizenid = Bridge.citizenid(src)
    if Accounts.ownedCount(citizenid) >= Config.MaxOwnedAccounts then
        return Router.fail(('You can own up to %d extra accounts'):format(Config.MaxOwnedAccounts))
    end
    local account = Accounts.create(accountType, name, citizenid, nil, 0)
    if not account then return Router.fail('Could not open the account, try again') end
    Ledger.add(account.number, 'system', 0, Bridge.name(src), 'Account opened')
    Router.log(src, ('opened %s %s'):format(accountType, account.number))
    return Router.ok(('%s opened'):format(name), { number = account.number, name = name, type = accountType })
end)

local function manageable(src, data, action)
    local _, where = atBranch(src, action)
    if where then return nil, where end
    return Access.check(src, data.number, 'manage')
end

Router.on('rename', function(src, data)
    local account, problem = manageable(src, data, 'rename')
    if not account then return Router.fail(problem) end
    local name = Rules.cleanText(data.name, NAME_CHARS)
    if not name then return Router.fail(('Names are 1 to %d characters'):format(NAME_CHARS)) end
    Accounts.rename(account.id, name)
    return Router.ok('Renamed')
end)

Router.on('closeAccount', function(src, data)
    local account, problem = manageable(src, data, 'closeAccount')
    if not account then return Router.fail(problem) end
    if not Rules.canClose(account.type, account.balance) or not Accounts.close(account.id) then
        return Router.fail('Empty the account first (withdraw or transfer the money)')
    end
    Router.log(src, ('closed %s'):format(account.number))
    return Router.ok('Account closed')
end)

local function sharedOnly(account)
    if account.type ~= 'shared' then return 'Only shared accounts have members' end
    return nil
end

Router.on('members', function(src, data)
    local account, problem = manageable(src, data, 'members')
    if not account then return Router.fail(problem) end
    local issue = sharedOnly(account)
    if issue then return Router.fail(issue) end
    return Router.ok(nil, { members = Accounts.members(account.id) })
end)

Router.on('addMember', function(src, data)
    local account, problem = manageable(src, data, 'addMember')
    if not account then return Router.fail(problem) end
    local issue = sharedOnly(account)
    if issue then return Router.fail(issue) end
    local role = Rules.MEMBER_ROLES[data.role] and data.role or nil
    if not role then return Router.fail('Pick Member or Viewer') end
    local target = Rules.wholeAmount(data.target, 100000)
    if not target or not Bridge.loaded(target) then return Router.fail('No player with that ID is online') end
    local citizenid = Bridge.citizenid(target)
    if citizenid == account.owner then return Router.fail('You already own this account') end
    Accounts.setMember(account.id, citizenid, Bridge.name(target), role)
    Bridge.notify(target, ('Vanguard Bank: you were added to "%s"'):format(account.name), 'success')
    return Router.ok(('%s added'):format(Bridge.name(target)))
end)

Router.on('setRole', function(src, data)
    local account, problem = manageable(src, data, 'setRole')
    if not account then return Router.fail(problem) end
    local role = Rules.MEMBER_ROLES[data.role] and data.role or nil
    if not role or type(data.citizenid) ~= 'string' then return Router.fail('Pick Member or Viewer') end
    if not Accounts.roleOf(account.id, data.citizenid) then return Router.fail('That person is not a member') end
    for _, member in ipairs(Accounts.members(account.id)) do
        if member.citizenid == data.citizenid then Accounts.setMember(account.id, member.citizenid, member.name, role) end
    end
    return Router.ok('Role changed')
end)

Router.on('removeMember', function(src, data)
    local account, problem = manageable(src, data, 'removeMember')
    if not account then return Router.fail(problem) end
    if type(data.citizenid) ~= 'string' or not Accounts.removeMember(account.id, data.citizenid) then
        return Router.fail('That person is not a member')
    end
    return Router.ok('Member removed')
end)

Router.on('leave', function(src, data)
    local _, where = atBranch(src, 'leave')
    if where then return Router.fail(where) end
    local number = Rules.parseNumber(data.number)
    local account = number and Accounts.byNumber(number)
    if not account or account.type ~= 'shared' then return Router.fail('That account does not exist') end
    if not Accounts.removeMember(account.id, Bridge.citizenid(src)) then return Router.fail('You are not a member') end
    return Router.ok(('You left "%s"'):format(account.name))
end)
```

- [ ] **Step 2: Lint** → `syntax ok`. **Step 3: Commit** — `feat: branch actions (transfer, accounts, members, history)`.

---

### Task 7: qb-banking compatibility, business exports, migration, start-up

**Files:** Create `server/compat.lua`, `server/business.lua`, `server/migrate.lua`, `server/main.lua`

**Interfaces:**
- Produces: exports `AddMoney`, `AddGangMoney`, `RemoveMoney`, `RemoveGangMoney`, `GetAccount`, `GetGangAccount`, `GetAccountBalance`, `GetBalance`, `CreateJobAccount`, `CreateGangAccount`, `CreatePlayerAccount`, `CreateBankStatement`; exports `getBusinessBalance(id) -> number`, `adjustBusiness(id, delta, kind, actor, note, name) -> bool`, `businessAccountNumber(id, name) -> string|nil`; console command `vbank_selftest`.

- [ ] **Step 1: `server/compat.lua`**

```lua
-- Vanguard Bank - qb-banking compatibility. fxmanifest says provide 'qb-banking', so scripts written
-- for qb-banking (police fines, EMS, taxi, vehicle shop, houses, ps_lib) reach these exports unchanged.

local function society(name, create)
    if type(name) ~= 'string' or name == '' then return nil end
    local account = Accounts.byRef('job', name) or Accounts.byRef('gang', name)
    if account or not create then return account end
    if Bridge.isJob(name) then return Accounts.ensureRef('job', name, Bridge.jobLabel(name)) end
    if Bridge.isGang(name) then return Accounts.ensureRef('gang', name, Bridge.gangLabel(name)) end
    return nil
end

local function wholeDollars(amount)
    local value = math.floor(tonumber(amount) or 0)
    return Rules.wholeAmount(value, Config.MaxAmount)
end

local function caller() return GetInvokingResource() or 'server' end

local function addMoney(name, amount, reason)
    local value, account = wholeDollars(amount), society(name, true)
    if not value or not account or not Accounts.adjust(account.id, value) then return false end
    Ledger.add(account.number, 'income', value, caller(), reason)
    return true
end

local function removeMoney(name, amount, reason)
    local value, account = wholeDollars(amount), society(name, false)
    if not value or not account or not Accounts.adjust(account.id, -value) then return false end
    Ledger.add(account.number, 'payment', -value, caller(), reason)
    return true
end

local function getAccount(name)
    local account = society(name, false)
    if not account then return nil end
    return { id = account.id, account_name = name, account_balance = account.balance, account_type = account.type, users = '[]' }
end

local function getBalance(name)
    local account = society(name, false)
    return account and account.balance or 0
end

local function createSociety(accountType)
    return function(name, balance)
        if type(name) ~= 'string' or name == '' then return false end
        local existing = Accounts.byRef(accountType, name)
        local label = (accountType == 'job' and Bridge.jobLabel(name) or Bridge.gangLabel(name)) or name
        local account = existing or Accounts.ensureRef(accountType, name, label)
        local value = wholeDollars(balance)
        if not existing and account and value then Accounts.adjust(account.id, value) end
        return account and account.id or false
    end
end

local function createPlayerAccount(playerId, accountName, accountBalance, accountUsers)
    local citizenid = Bridge.citizenid(playerId)
    local name = Rules.cleanText(accountName, 24)
    if not citizenid or not name then return false end
    local account = Accounts.create('shared', name, citizenid, nil, wholeDollars(accountBalance) or 0)
    if not account then return false end
    local ok, users = pcall(json.decode, accountUsers or '[]')
    for _, member in ipairs(ok and type(users) == 'table' and users or {}) do
        if type(member) == 'string' and member ~= citizenid then
            Accounts.setMember(account.id, member, Bridge.nameOf(member) or member, 'member')
        end
    end
    return account.id
end

local function createBankStatement(playerId, accountName, amount, reason, statementType, accountType)
    local value = wholeDollars(amount)
    if not value then return false end
    local number
    if accountType == 'player' or accountName == 'checking' then
        local citizenid = Bridge.citizenid(playerId)
        number = citizenid and Accounts.personalNumber(citizenid)
    else
        local account = society(accountName, false)
        number = account and account.number
    end
    if not number then return false end
    local deposit = statementType == 'deposit'
    Ledger.add(number, deposit and 'income' or 'payment', deposit and value or -value, caller(), reason)
    return true
end

exports('AddMoney', addMoney)
exports('AddGangMoney', addMoney)
exports('RemoveMoney', removeMoney)
exports('RemoveGangMoney', removeMoney)
exports('GetAccount', getAccount)
exports('GetGangAccount', getAccount)
exports('GetAccountBalance', getBalance)
exports('GetBalance', getBalance)
exports('CreateJobAccount', createSociety('job'))
exports('CreateGangAccount', createSociety('gang'))
exports('CreatePlayerAccount', createPlayerAccount)
exports('CreateBankStatement', createBankStatement)
```

- [ ] **Step 2: `server/business.lua`**

```lua
-- Vanguard Bank - exports for Vanguard Business. Its money lives in a Business account here;
-- Vanguard Business logs its own side, so these do not call back into it.

local function businessAccount(id, name)
    if type(id) ~= 'number' then return nil end
    return Accounts.ensureRef('business', id, type(name) == 'string' and name or nil)
end

exports('getBusinessBalance', function(id)
    local account = type(id) == 'number' and Accounts.byRef('business', id) or nil
    return account and account.balance or 0
end)

exports('adjustBusiness', function(id, delta, kind, actor, note, name)
    if type(delta) ~= 'number' or delta == 0 or delta % 1 ~= 0 then return false end
    local account = businessAccount(id, name)
    if not account or not Accounts.adjust(account.id, delta) then return false end
    Ledger.add(account.number, kind or (delta > 0 and 'income' or 'payment'), delta, actor or 'Vanguard Business', note)
    return true
end)

exports('businessAccountNumber', function(id, name)
    local account = businessAccount(id, name)
    return account and account.number or nil
end)
```

- [ ] **Step 3: `server/migrate.lua`**

```lua
-- Vanguard Bank - one-time copy of qb-banking's accounts. The flag is set before copying, so a
-- crash half-way never copies balances twice (check the console line if it ever stops early).

Migrate = {}

local RESOURCE = GetCurrentResourceName()

function Migrate.qbBanking()
    if Db.meta('migrated_qbbanking') then return end
    Db.setMeta('migrated_qbbanking', 'started')
    local exists = MySQL.scalar.await(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'bank_accounts'")
    if (exists or 0) == 0 then return Db.setMeta('migrated_qbbanking', 'no qb-banking table') end

    local copied = 0
    for _, row in ipairs(MySQL.query.await('SELECT citizenid, account_name, account_balance, account_type, users FROM bank_accounts') or {}) do
        local balance = math.max(0, math.floor(tonumber(row.account_balance) or 0))
        if row.account_type == 'job' or row.account_type == 'gang' then
            local label = row.account_type == 'job' and Bridge.jobLabel(row.account_name) or Bridge.gangLabel(row.account_name)
            local account = Accounts.ensureRef(row.account_type, row.account_name, label or row.account_name)
            if account and balance > 0 and Accounts.adjust(account.id, balance) then
                Ledger.add(account.number, 'system', balance, 'qb-banking', 'Moved from qb-banking')
            end
            copied = copied + 1
        elseif row.account_type == 'shared' and row.citizenid then
            local account = Accounts.create('shared', Rules.cleanText(row.account_name, 24) or 'Shared', row.citizenid, nil, balance)
            local ok, users = pcall(json.decode, row.users or '[]')
            for _, member in ipairs(account and ok and type(users) == 'table' and users or {}) do
                if type(member) == 'string' and member ~= row.citizenid then
                    Accounts.setMember(account.id, member, Bridge.nameOf(member) or member, 'member')
                end
            end
            copied = copied + 1
        end
    end
    Db.setMeta('migrated_qbbanking', ('copied %d'):format(copied))
    print(('[%s] copied %d account(s) from qb-banking'):format(RESOURCE, copied))
end
```

- [ ] **Step 4: `server/main.lua`**

```lua
-- Vanguard Bank - start-up and hello.

local RESOURCE = GetCurrentResourceName()
local HELLO_COOLDOWN_MS = 2000
local lastHello = {}

CreateThread(function()
    Db.init()
    Places.load()
    Migrate.qbBanking()
    Bridge.ready = true
    Places.broadcast()
    for _, id in ipairs(GetPlayers()) do Money.payPending(tonumber(id)) end
    print(('[%s] ready: %d branch / ATM spot(s)'):format(RESOURCE, #Places.list()))
end)

RegisterNetEvent('vanguard-bank:hello', function()
    local src = source
    local now = GetGameTimer()
    if not Bridge.ready or (lastHello[src] and now - lastHello[src] < HELLO_COOLDOWN_MS) then return end
    lastHello[src] = now
    Places.broadcast(src)
end)

AddEventHandler('playerDropped', function() lastHello[source] = nil end)

-- Console check that scripts calling exports['qb-banking'] reach this resource (provide).
RegisterCommand('vbank_selftest', function(src)
    if src ~= 0 then return end
    local ok, result = pcall(function() return exports['qb-banking']:GetAccountBalance('police') end)
    print(('[%s] qb-banking exports %s (police balance: %s)'):format(RESOURCE, ok and 'OK' or 'NOT reachable', tostring(result)))
end, true)
```

- [ ] **Step 5: Lint** → `syntax ok`. **Step 6: Commit** — `feat: qb-banking compatibility, business exports, migration, start-up`.

---

### Task 8: Client — requests, places, placement tool

**Files:** Create `bridge/client.lua`, `client/main.lua`, `client/places.lua`, `client/placement.lua`

**Interfaces:**
- Consumes: server events/actions above.
- Produces (NUI contract, used by Task 10):
  - Lua → NUI: `{action='loading'}`, `{action='open', state, brand}`, `{action='state', state}`, `{action='close'}`, `{action='placement', kind, label, hint}`, `{action='placementEnd'}`, `{action='askLabel'}`.
  - NUI → Lua callbacks: `close`, `request {action, data}` → result, `label {text|null}`.
  - `Client.request(action, data)`, `Client.open()`, `Client.close()`, `Client.isOpen`, `Client.askLabel() -> string|nil`.

- [ ] **Step 1: `bridge/client.lua`** — same as `projects/vanguard-jobs/bridge/client.lua` minus `fillFuel` and the `QBCore:Client:OnPlayerLoaded` line replaced by `TriggerServerEvent('vanguard-bank:hello')`; keep `ClientBridge.notify(message, kind)` and `ClientBridge.drawText3d(coords, text)` exactly.

- [ ] **Step 2: `client/main.lua`**

```lua
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
        if pending[id] then pending[id] = nil; answer:resolve({ ok = false, message = 'The bank did not answer' }) end
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

RegisterNUICallback('close', function(_, cb) Client.close(); cb({}) end)

RegisterNUICallback('request', function(body, cb)
    if type(body) ~= 'table' or type(body.action) ~= 'string' then return cb({ ok = false }) end
    cb(Client.request(body.action, body.data))
end)

RegisterNUICallback('label', function(body, cb)
    if labelPromise then labelPromise:resolve(type(body) == 'table' and type(body.text) == 'string' and body.text or nil) end
    cb({})
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('vanguard-bank:hello')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and Client.isOpen then SetNuiFocus(false, false) end
end)
```

- [ ] **Step 3: `client/places.lua`**

```lua
-- Vanguard Bank - map icons for branches and [E] prompts at placed branches / ATMs.

Places = { list = {}, blips = {} }

local PROMPT_KEY = 38
local NEAR = 15.0

local function clearBlips()
    for _, blip in ipairs(Places.blips) do RemoveBlip(blip) end
    Places.blips = {}
end

local function makeBlips()
    clearBlips()
    for _, place in ipairs(Places.list) do
        if place.kind == 'branch' then
            local blip = AddBlipForCoord(place.x, place.y, place.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.colour)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.Blip.label)
            EndTextCommandSetBlipName(blip)
            Places.blips[#Places.blips + 1] = blip
        end
    end
end

RegisterNetEvent('vanguard-bank:places', function(list)
    Places.list = type(list) == 'table' and list or {}
    makeBlips()
end)

CreateThread(function()
    while true do
        local sleep = 750
        if not Client.isOpen and not Placement.active then
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestDistance
            for _, place in ipairs(Places.list) do
                local distance = #(pos - vector3(place.x, place.y, place.z))
                if distance < NEAR then sleep = 0 end
                if distance <= Config.InteractDistance and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = place, distance
                end
            end
            if best then
                local label = best.kind == 'atm' and '[E] ATM' or ('[E] %s'):format(best.label)
                ClientBridge.drawText3d(vector3(best.x, best.y, best.z + (best.kind == 'atm' and 1.2 or 0.5)), label)
                if IsControlJustReleased(0, PROMPT_KEY) then Client.open() end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then clearBlips() end
end)
```

- [ ] **Step 4: `client/placement.lua`** — adapted from `projects/vanguard-business/client/placement.lua` (same `direction`, `aim`, `highlight`, `disableControls`, KEY table minus `link`), kinds `{ branch, atm }`:

```lua
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
    if entity then SetEntityDrawOutlineColor(99, 102, 241, 255); SetEntityDrawOutline(entity, true) end
end

local function report(result) ClientBridge.notify(result.message, result.ok and 'success' or 'error') end

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
        while Placement.active do tick(); Wait(0) end
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
```

- [ ] **Step 5: Lint** → `syntax ok`. **Step 6: Commit** — `feat: client requests, places, placement tool`.

---

### Task 9: Vanguard Business money adapter (repo `projects/vanguard-business`)

**Files:**
- Create: `server/banklink.lua`
- Modify: `server/businesses.lua` (`Businesses.adjust` + new `Businesses.balance`), `server/boss.lua:36` and deposit / withdraw notes, `server/admin.lua:14`, `server/payroll.lua:30,36`, `server/supplier.lua:10,24`, `server/register.lua:93,98`, `server/main.lua` (move balances on start + when the bank starts), `fxmanifest.lua` (banklink before businesses; version 1.4.0), `CHANGELOG.md`, `README.md`

**Interfaces:**
- Consumes: Vanguard Bank exports `getBusinessBalance(id)`, `adjustBusiness(id, delta, kind, actor, note, name)`.
- Produces: exports `bankRoles(citizenid) -> { {id, name, rank} }`, `noteBankMovement(businessId, kind, amount, actor, note)`; `Businesses.adjust(id, delta, note) -> bool`, `Businesses.balance(id) -> number`.

- [ ] **Step 1: `server/banklink.lua`**

```lua
-- Vanguard Business - where business money lives. With Vanguard Bank running it is the business's
-- Business account in the bank; without it, the balance column in vbiz_businesses (as before).

BankLink = {}

local BANK = 'vanguard-bank'
local RESOURCE = GetCurrentResourceName()

function BankLink.active()
    return GetResourceState(BANK) == 'started'
end

function BankLink.balance(business)
    local ok, value = pcall(function() return exports[BANK]:getBusinessBalance(business.id) end)
    return ok and tonumber(value) or 0
end

function BankLink.adjust(business, delta, note)
    local ok, changed = pcall(function()
        return exports[BANK]:adjustBusiness(business.id, delta, nil, 'Vanguard Business', note, business.name)
    end)
    if not ok then print(('[%s] bank adjust failed: %s'):format(RESOURCE, tostring(changed))) end
    return ok and changed == true
end

--- Moves money still in the balance column into the bank account (first start with Vanguard Bank).
function BankLink.moveBalances()
    if not BankLink.active() then return end
    for _, business in ipairs(Businesses.all()) do
        local amount = business.balance or 0
        if amount > 0 and MySQL.update.await('UPDATE vbiz_businesses SET balance = 0 WHERE id = ? AND balance = ?', { business.id, amount }) == 1 then
            if BankLink.adjust(business, amount, 'Moved from Vanguard Business') then
                business.balance = 0
                Businesses.log(business.id, 'bank', 0, 'Vanguard Bank', ('$%d moved to the bank account'):format(amount))
            else
                MySQL.update.await('UPDATE vbiz_businesses SET balance = balance + ? WHERE id = ?', { amount, business.id })
            end
        end
    end
end

exports('bankRoles', function(citizenid)
    local list = {}
    for businessId, rank in pairs(StaffList.jobsOf(citizenid)) do
        local business = Businesses.get(businessId)
        if business then list[#list + 1] = { id = businessId, name = business.name, rank = rank } end
    end
    return list
end)

exports('noteBankMovement', function(businessId, kind, amount, actor, note)
    if Businesses.get(businessId) then Businesses.log(businessId, 'bank', amount, actor, note or kind) end
end)
```

- [ ] **Step 2: `server/businesses.lua`** — replace `Businesses.adjust` and add `Businesses.balance`:

```lua
--- Adds delta (negative to spend) unless the balance would drop below zero. In the bank when
--- Vanguard Bank runs, else atomic SQL here. Never throws: an error counts as "not changed".
function Businesses.adjust(id, delta, note)
    local business = cache[id]
    if business and BankLink.active() then return BankLink.adjust(business, delta, note) end
    local ok, changed = pcall(MySQL.update.await,
        'UPDATE vbiz_businesses SET balance = balance + ? WHERE id = ? AND balance + ? >= 0',
        { delta, id, delta })
    if not ok then
        print(('[vanguard-business] balance change of %d for business %d failed: %s'):format(delta, id, tostring(changed)))
        return false
    end
    if changed ~= 1 then return false end
    if business then business.balance = business.balance + delta end
    return true
end

--- The business's money: its bank account balance with Vanguard Bank, else the column.
function Businesses.balance(id)
    local business = cache[id]
    if not business then return 0 end
    if BankLink.active() then return BankLink.balance(business) end
    return business.balance
end
```

- [ ] **Step 3: Call sites** — `boss.lua:36` `balance = permissions.log and Businesses.balance(business.id) or nil,`; `admin.lua:14` `balance = Businesses.balance(business.id),`; notes: boss deposit `Businesses.adjust(ctx.business.id, amount, 'Boss desk deposit')`, withdraw `Businesses.adjust(ctx.business.id, -amount, 'Boss desk withdrawal')` (refund lines get `'Refund'`); payroll `Businesses.adjust(businessId, -amount, ('Paycheck: %s'):format(name))` (refund `'Paycheck refund'`); supplier `Businesses.adjust(business.id, -total, 'Supplier order')` / `Businesses.adjust(business.id, refund, 'Supplier refund')`; register `Businesses.adjust(bill.businessId, share, ('Sale: %s'):format(bill.note or 'bill'))` / commission refund `'Commission returned'`.

- [ ] **Step 3b: Money log label** — the boss desk log gets a new kind `bank` (movements made at the bank). In `html/` find where log kinds are turned into labels / icons and add `bank` → "Bank" with the existing deposit icon, so it never shows a raw key.

- [ ] **Step 4: `server/main.lua`** — after the existing start-up `Businesses.load()` sequence call `BankLink.moveBalances()`, and add:

```lua
AddEventHandler('onResourceStart', function(name)
    if name == 'vanguard-bank' then SetTimeout(2000, BankLink.moveBalances) end
end)
```

- [ ] **Step 5: `fxmanifest.lua`** — add `'server/banklink.lua'` right before `'server/businesses.lua'`; version `'1.4.0'`. CHANGELOG 1.4.0 entry: "With Vanguard Bank running, business money lives in a Business account in the bank (moved over once on first start); the boss desk, paychecks, supplier orders and sales use it. Without the bank nothing changes." README: one bullet under Features.

- [ ] **Step 6: Tests + lint** — `node tests/run.js` → `45 passed, 0 failed`; `npm run lint` → `syntax ok`.
- [ ] **Step 7: Commit (vanguard-business)** — `feat: business money in Vanguard Bank when it runs (1.4.0)`.

---

### Task 10: NUI — bank, ATM, placement bar, label prompt

**Files:** Create `html/index.html`, `html/style.css`, `html/app.js`

**Interfaces:**
- Consumes: the NUI contract from Task 8; server `open` payload `{ mode, place, name, cash, accounts[{number,type,name,balance,role,can{deposit,withdraw,transfer,manage}}], owned, maxOwned, maxAmount, quick }`; `history → {rows[{id,kind,amount,actor,note,time}]}`; `lookup → {number,label}`; `openAccount → {number,name,type}`; `members → {members[{citizenid,name,role}]}`.
- Produces: preview hashes `#loading`, `#bank`, `#account`, `#transfer`, `#open`, `#opened`, `#members`, `#atm`, `#placement` (sample data, no-op in game).

**Visual direction:** "private banking at night" — deep ink background (`#0a0d1a`), indigo accent from `Config.Brand.Accent` (`#6366f1`) with a soft violet glow, warm gold `#f5c56b` for money highlights. Fonts as the other Vanguard UIs: Chakra Petch (display), Inter (body), JetBrains Mono (numbers / account numbers). Bank = wide glass-free solid panel (1180×720 max, 94vw/90vh) with left rail (brand, nav: Accounts / Transfer / Open account, customer card with cash) and a main stage. ATM = narrow physical-ATM bezel (520×640) with screen, big buttons. Motion: loader ring + logo pulse, cards rise in with stagger, balances count up (600 ms ease-out), panels cross-fade, buttons press; `prefers-reduced-motion` disables all of it. Everything opaque (no backdrop blur — game shows through NUI otherwise).

- [ ] **Step 1: `html/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vanguard Bank</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;600;700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div id="app" class="app" hidden></div>
    <div id="placement" class="placement" hidden></div>
    <div id="toasts" class="toasts" aria-live="polite"></div>
    <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: `html/app.js`** — structure (all DOM built with `el()` + `textContent`; icons from a fixed `ICONS` table of SVG path strings only):

```js
'use strict';
/* Vanguard Bank - NUI: bank (branch), ATM, admin placement bar and label prompt.
   In a normal browser it runs a preview with sample data: #loading #bank #account #transfer #open #opened #members #atm #placement */

const IS_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IS_GAME ? GetParentResourceName() : 'vanguard-bank';
const LOADER_MIN_MS = 600;

const ui = { state: null, view: 'dashboard', account: null, history: [], historyDone: false,
             openedAt: 0, counters: new Map(), wizard: null, busy: false };

function el(tag, props = {}, ...children) { /* same as vanguard-jobs/html/app.js el() */ }
function setChildren(node, ...children) { /* same as vanguard-jobs */ }
const money = (n) => `${n < 0 ? '-' : ''}$${Math.abs(Math.floor(Number(n) || 0)).toLocaleString('en-US')}`;

async function post(endpoint, data = {}) {
    if (!IS_GAME) return Preview.respond(endpoint, data);
    try {
        const response = await fetch(`https://${RESOURCE}/${endpoint}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
        return await response.json();
    } catch { return { ok: false, message: 'The bank did not answer' }; }
}

async function act(action, data, button) {          // server action from a button, toast result
    if (ui.busy) return { ok: false };
    ui.busy = true; button?.classList.add('is-busy');
    const result = await post('request', { action, data });
    ui.busy = false; button?.classList.remove('is-busy');
    toast(result.message, result.ok);
    if (result.ok) await refresh();                  // fresh balances from the server
    return result;
}

async function refresh() {
    const result = await post('request', { action: 'open' });
    if (result.ok) { ui.state = result.data; render(); }
}

/* count-up: animates a number node from its last value to the new one (600 ms ease-out cubic) */
function countUp(node, key, target) { /* requestAnimationFrame loop; reduced-motion -> set instantly */ }

/* screens */
function renderLoader(text) { /* logo shield + spinning ring + text */ }
function renderBank() { /* rail (brand, nav, customer card) + stage(view) */ }
function renderDashboard() { /* total of visible balances (count-up), account cards grid: Personal hero card first,
                               each card: type icon, name, number (mono, copy on click), balance (count-up), role chip */ }
function renderAccount(account) { /* header: name, number, balance; actions: Deposit / Withdraw / Transfer (per account.can);
                                    owner tools: Members (shared), Rename, Close (disabled unless balance 0);
                                    history list grouped by day with kind icons, signed gold/red amounts, Load more */ }
function amountForm(kind, account) { /* input + quick chips (state.quick + All), confirm button -> act('deposit'|'withdraw') */ }
function renderTransfer(account) { /* from select (accounts with can.transfer), to number input -> debounced 'lookup' shows
                                     receiver label, amount + note, confirm sheet "Send $X to <label>?" -> act('transfer') */ }
function renderOpenWizard() { /* step 1 type cards (Savings / Shared, disabled when owned >= maxOwned),
                                 step 2 name input, step 3 confirm; submit -> loader "Opening your account..." (min 900 ms)
                                 -> success card with number + copy button -> back to dashboard */ }
function renderMembers(account) { /* list with role select + remove; add form: server ID + role -> act('addMember') */ }
function renderAtm() { /* ATM bezel: account list (can.withdraw or can.deposit) -> amount keypad (digits, clear, quick)
                         -> Withdraw / Deposit buttons -> processing loader -> receipt line; no other actions */ }
function render() { /* state.mode === 'atm' ? renderAtm() : renderBank() */ }

function toast(message, ok = true) { /* same as vanguard-jobs toast */ }
function placementBar(data) { /* "Placing: Branch counter (1/2)", keys legend ← → Click Wheel Delete Backspace, hint */ }
function askLabel() { /* modal: input (max 30) + Save / Cancel -> post('label', { text }) */ }

window.addEventListener('message', (event) => {
    const data = event.data || {};
    switch (data.action) {
        case 'loading': showApp(); setChildren(appNode, renderLoader('Connecting to Vanguard Bank')); ui.openedAt = performance.now(); break;
        case 'open': applyBrand(data.brand); setTimeout(() => { ui.state = data.state; ui.view = 'dashboard'; render(); },
                     Math.max(0, LOADER_MIN_MS - (performance.now() - ui.openedAt))); break;
        case 'state': ui.state = data.state; render(); break;
        case 'close': hideApp(); break;
        case 'placement': placementBar(data); break;
        case 'placementEnd': hidePlacement(); break;
        case 'askLabel': askLabel(); break;
    }
});
document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !appNode.hidden) post('close'); });
/* Preview: sample state (Personal $48,250, Savings "Rainy day" $12,000, Shared "Crew fund" member $3,400,
   Business "Cat Cafe" $8,900, Job "Los Santos Police" $250,000), sample history, mode toggle via hash. */
```

Fill every function body completely while implementing (no stubs ship); keep each function under ~50 lines by splitting helpers (`accountCard`, `historyRow`, `kindIcon`, `confirmSheet`, `keypad`).

- [ ] **Step 3: `html/style.css`** — tokens on `:root` (`--ink-0 #070912`, `--ink-1 #0d1122`, `--ink-2 #141a30`, `--ink-3 #1d2440`, `--line rgba(255,255,255,.07)`, `--text #eef0fb`, `--text-dim #9aa1c2`, `--accent` from brand, `--accent-soft`, `--gold #f5c56b`, `--red #ff5d73`, `--green #3ddc97`, fonts, `--ease cubic-bezier(.2,.8,.2,1)`), components: `.app` overlay, `.bank` panel, `.rail`, `.stage`, `.card` (Personal hero gets indigo→violet gradient + subtle noise via inline SVG data URI), `.chip`, `.btn` variants, `.sheet` (confirm), `.wizard` steps, `.loader` ring (`@keyframes spin`, `pulse`), `.history` rows, `.atm` bezel + `.keypad`, `.placement` bar (bottom centre), `.modal`, `.toasts`, `@media (prefers-reduced-motion: reduce)`.

- [ ] **Step 4: Previews** — headless Edge screenshots (pattern in CLAUDE.md / scratchpad) of `#loading #bank #account #transfer #open #opened #members #atm #placement` at 1600×900; fix anything cut off, overlapping or unreadable.
- [ ] **Step 5: Lint** → `syntax ok`. **Step 6: Commit** — `feat: bank, ATM and placement UI`.

---

### Task 11: Docs, review, install, verify

**Files:** Create `README.md`, `CHANGELOG.md` (1.0.0), `LICENSE` (copy from `projects/vanguard-business/LICENSE`), `docs/*.png` (preview shots); Modify server: `server.cfg`, move `[qb]/qb-banking`, `F:\FiveMServer\CLAUDE.md`.

- [ ] **Step 1: README / CHANGELOG / LICENSE** — README sections: what it is, features, requirements (oxmysql, qb-core; optional Vanguard Business), installation (folder, `ensure vanguard-bank` right after `ensure qb-core`, ACE line, remove qb-banking), placing branches / ATMs (`/bankadmin` keys table), account types table (from spec), qb-banking compatibility list, development (`npm test`, `npm run lint`, previews).
- [ ] **Step 2: Review** — dispatch a `code-reviewer` agent on `projects/vanguard-bank` + the Vanguard Business diff with the Review Focus list from this plan; fix CRITICAL / HIGH findings; re-run `npm test` + `npm run lint`; commit `fix: review findings`.
- [ ] **Step 3: Install** —

```powershell
$base = 'F:\FiveMServer\txData\QBCore_BBC2AF.base'
$bk = 'F:\FiveMServer\backups\before-vanguard-bank-2026-10-10'
New-Item -ItemType Directory -Force $bk | Out-Null
Copy-Item -LiteralPath "$base\server.cfg" "$bk\server.cfg"
Move-Item -LiteralPath "$base\resources\[qb]\qb-banking" 'F:\FiveMServer\backups\disabled-resources\qb-banking'
robocopy F:\FiveMServer\projects\vanguard-bank "$base\resources\[local]\vanguard-bank" /E /XD .git docs tests tools node_modules /XF package.json package-lock.json .gitignore README.md CHANGELOG.md
# server.cfg: add 'ensure vanguard-bank' on the line after 'ensure qb-core', and
# 'add_ace group.admin vanguard.bank.admin allow # Vanguard Bank: /bankadmin placement' with the other Vanguard ACE lines
robocopy F:\FiveMServer\projects\vanguard-business "$base\resources\[local]\vanguard-business" /E /XD .git docs tests tools node_modules install /XF package.json package-lock.json .gitignore
```

- [ ] **Step 4: Check dependents** — `grep -rl "dependency 'qb-banking'\|'qb-banking'" --include=fxmanifest.lua resources` → each such manifest is satisfied by `provide`; note them in CLAUDE.md.
- [ ] **Step 5: CLAUDE.md** — new `2v.` entry (what, where, sync command, ACE, provide, migration flag, Vanguard Business 1.4.0 link, backup path, "not yet tested in-game").
- [ ] **Step 6: Tell the user** the in-game test list: full server restart → console `vbank_selftest` prints `OK` → `/bankadmin` place an ATM and check a branch → deposit/withdraw at both → transfer to another account → open Savings and Shared, add a member → Business account visible to the Owner → a police fine still reaches the police account.
- [ ] **Step 7: Commit + tag** — `git commit -m 'docs: readme, changelog, license'` in vanguard-bank.

---

## Self-review notes

- Spec coverage: branch / ATM / account types / roles / numbers / limits (Tasks 1, 3, 6), placed places (4, 8), transfers incl. offline pending (5, 6), history incl. other scripts' bank changes (5), qb-banking compat + migration (7), Vanguard Business link (7, 9), UI incl. loader and opening flow (10), safety (router, atomic SQL, Personal overdraw guard: 2, 5), testing + install (1, 10, 11).
- Names used across tasks: `Accounts.ensureRef`, `Access.check`, `Places.require`, `Money.credit/debit`, `Bridge.removeMoney` — defined once each (Tasks 2–5).
- Task 10 specifies the UI by structure, data contract and per-function behaviour rather than full source (it is the largest file and purely presentational); every function body is written in full during implementation and checked with the preview screenshots.
- If `vbank_selftest` prints "NOT reachable" (provide does not route exports on this FXServer build), add the fallback from the spec: a `qb-banking` folder with a manifest and a server file that re-exports each name by calling `exports['vanguard-bank']:<name>(...)`.
