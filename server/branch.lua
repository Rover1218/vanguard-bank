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
