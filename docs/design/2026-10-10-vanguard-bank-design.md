# Vanguard Bank — design

Date: 2026-10-10 · Status: approved in chat, awaiting written-spec review · MIT © Rover

## Goal

A modern bank for the Rover Development QBCore server, built as a standalone resource like Vanguard Business and Vanguard Jobs. Players manage money at bank branches (full banking) and use ATMs for cash only. It replaces qb-banking without breaking the scripts that use it, and becomes the home of Vanguard Business money.

## Decisions (from the brainstorm)

| Topic | Decision |
|---|---|
| qb-banking | Replaced. Moved to `backups/disabled-resources/`. Vanguard Bank `provide`s `qb-banking` and implements its exports, so callers keep working unchanged. |
| Account types | Personal, Savings, Shared, Business, Job (plus Gang, compat only — see below). |
| Personal account | Is QBCore's `bank` money. No second copy of the balance. |
| Business money | Lives in Vanguard Bank as a Business account. Vanguard Business uses the bank when it is running and falls back to its own balance when it is not (it stays standalone). |
| Identification | No bank card, no PIN. Interact with a branch or ATM; the character (citizenid) decides which accounts appear. |
| Branch | Everything: deposit, withdraw, transfer, history, open account, members, rename, close. |
| ATM | Withdraw and deposit only, on any account the player may use. No managing. |
| Places | Branch counters and ATMs are placed in game by admins with a placement tool (like Vanguard Business stations) and stored in the database. Only placed ATMs work; the server checks the player is at a placed branch / ATM for every action. The 8 standard bank counters are filled in on first start. |
| Not in v1 | Cards / PIN, savings interest, loans, opening fees, phone app, daily ATM limit. |

## What players see

### Branch (placed bank counters, map icon "Bank", press E)

1. **Loader** — "Connecting to Vanguard Bank" with the logo animating while accounts load (at least 600 ms so it never flickers).
2. **Dashboard** — account cards (type icon, name, number, animated balance). Personal first, then owned, shared, business, job.
3. **Account view** — balance, quick actions (Deposit, Withdraw, Transfer), history list (newest first, 50 rows, "load more"), and for owners: Members, Rename, Close.
4. **Deposit / Withdraw** — amount field with quick chips (100, 500, 1 000, 5 000, All). Cash ↔ account.
5. **Transfer** — from this account to an account number. On typing a valid number the server returns the receiver's name ("Mia Tanaka — Savings"); the player confirms. Optional note (max 60 chars).
6. **Open account** — step flow: choose type (Savings / Shared) → name it → confirm → loader "Opening your account…" → success card with the new number (`VB-4821-0397`) and a copy button.
7. **Members (Shared, owner only)** — add a player by server ID (they must be online), pick role, change role, remove.
8. **Close** — only when the balance is 0. Personal, Business and Job accounts cannot be closed here.

### ATM (placed ATMs only, press E)

A compact ATM screen: account picker (every account the player may withdraw from or deposit to), amount keypad with quick amounts, Withdraw / Deposit. Same loader style, shorter.

## Accounts and roles

| Type | Created | Visible to | Deposit | Withdraw / transfer | Manage |
|---|---|---|---|---|---|
| Personal | Automatically (number on first visit) | Holder | Holder | Holder | — |
| Savings | Player opens it | Owner | Owner | Owner | Owner (rename, close) |
| Shared | Player opens it | Owner + members | Everyone with access | Owner + role `member` | Owner (members, rename, close) |
| Business | Automatically per Vanguard Business | Business ranks Owner, Manager | Owner, Manager | Owner, Manager | — (managed in Vanguard Business) |
| Job | Migrated from qb-banking / created on demand | That job's boss grade (`isboss`) | Boss | Boss | — |
| Gang | Compat exports only | That gang's boss | Boss | Boss | — |

- Shared roles: `member` (deposit, withdraw, transfer) and `viewer` (see history, deposit).
- Account numbers: `VB-` + 4 + 4 digits, random, unique (DB unique index, retry on clash). Personal accounts also get one so other players can transfer to them.
- `Config.MaxOwnedAccounts = 3` (Savings + Shared owned by one character).
- Amounts are whole dollars, `1 … Config.MaxAmount` (default 10 000 000).

## Architecture

```
vanguard-bank/
  config.lua             branches, ATM models, limits, brand
  shared/rules.lua       pure logic: amounts, account numbers, role permissions (unit tested)
  bridge/server.lua      QBCore: player, citizenid, name, cash/bank, offline credit, job/gang boss
  bridge/client.lua      notify, 3D text / help text
  server/db.lua          schema (auto-created), queries
  server/accounts.lua    account store: get by number, list for character, atomic adjust
  server/access.lua      "what can this character do with this account" (all types in one place)
  server/ledger.lua      history rows; Personal history also from QBCore:Server:OnMoneyChange
                         (bank-money changes from other scripts: paychecks, jobs, shops; changes the
                         bank makes itself carry a "vanguard-bank" reason and are skipped there, so
                         nothing is logged twice)
  server/router.lua      request/response events, rate limit, pcall, loaded-character check
  server/branch.lua      branch-only actions (transfer, open, members, rename, close)
  server/money.lua       deposit / withdraw (branch or ATM)
  server/compat.lua      qb-banking exports
  server/business.lua    exports used by Vanguard Business
  server/migrate.lua     one-time copy of qb-banking job/gang/shared accounts
  server/places.lua      placed branches / ATMs: load, add, remove, "is this player at one", admin command
  server/main.lua        start-up, hello
  client/main.lua        requests, NUI open/close
  client/places.lua      branch blips, E prompts at placed branches and ATMs
  client/placement.lua   admin placement mode (aim + click, snaps to ATM props)
  html/                  index.html, style.css, app.js (bank + ATM modes, preview data)
```

### Data (tables created automatically)

- `vbank_accounts` — `id`, `number` (unique), `type` (savings, shared, business, job, gang), `name`, `owner` (citizenid, null for business/job/gang), `ref` (business id / job / gang name), `balance` BIGINT ≥ 0, `created_at`.
- `vbank_personal` — `citizenid` (PK), `number` (unique). Balance stays in QBCore.
- `vbank_members` — `account_id`, `citizenid`, `name`, `role`.
- `vbank_places` — `id`, `kind` (branch, atm), `x`, `y`, `z`, `heading`, `label` (branch name, e.g. "Fleeca Legion Square"). Filled with the 8 standard counters when empty on first start.
- `vbank_transactions` — `id`, `account` (number), `kind` (deposit, withdraw, transfer_in, transfer_out, payment, fee, system), `amount` (signed), `actor` (name), `note`, `created_at`. Index on (`account`, `id`).

Balances change only through one atomic statement: `UPDATE … SET balance = balance + ? WHERE id = ? AND balance + ? >= 0` (same pattern as Vanguard Business), so two players spending at once can never overdraw. Personal money goes through QBCore's `AddMoney` / `RemoveMoney`.

### Transfers

1. Validate amount, sender access (`withdraw` permission), receiver exists and differs from sender.
2. Take the money from the sender (atomic). If that fails → "Not enough money".
3. Credit the receiver: account row (atomic), online player's Personal (QBCore `AddMoney`), or offline player's Personal (one atomic `JSON_SET` update on `players.money`).
4. If the credit fails, refund the sender and report the failure. Both sides get a history row.

### qb-banking compatibility (`provide 'qb-banking'`)

Exports with the same names and arguments: `AddMoney`, `RemoveMoney`, `GetAccount`, `GetAccountBalance`, `GetBalance`, `CreatePlayerAccount`, `CreateJobAccount`, `CreateGangAccount`, `CreateBankStatement`, `AddGangMoney`, `RemoveGangMoney`, `GetGangAccount`. `accountName` maps to the job / gang account of that name (created on first use). Used today by qb-policejob, qb-ambulancejob, qb-taxijob, qb-vehicleshop, qb-houses, ps_lib (MDT) and qb-core (only with `PayCheckSociety = true`, off here).

If `provide` does not route exports on this FXServer build (checked in the plan's first task), fallback: a tiny bridge resource named `qb-banking` that forwards each export to Vanguard Bank (same approach as our qb-phone bridge).

### Vanguard Business link

- Vanguard Bank exports: `getBusinessBalance(id)`, `adjustBusiness(id, delta, kind, actor, note)` (atomic, never negative), `businessAccountNumber(id)`.
- Vanguard Business gets a small money adapter: `Businesses.adjust` and the balance it shows go to Vanguard Bank when `vanguard-bank` is started, otherwise to its own `balance` column (unchanged behaviour).
- First start with the bank: each business's existing balance is moved into its new bank account once (column set to 0, logged).
- Bank access to Business accounts uses Vanguard Business ranks through an export it provides (`rankOf(businessId, citizenid)`); Owner and Manager get access.

### Places (placed in game)

- Admin command `/bankadmin` (ACE `vanguard.bank.admin`) toggles placement mode, same controls as Vanguard Business: ← → switch Branch / ATM, Click place, mouse wheel rotate, Delete removes the branch / ATM you aim at, Backspace done. Aiming at an ATM prop (`prop_atm_01/02/03`, `prop_fleeca_atm`) snaps to it. A new branch asks for its label.
- Every placed spot shows an E prompt within 2 m; branches also get a map icon.
- The server checks every request against the placed spots: branch actions need the player within 4 m of a placed branch; withdraw / deposit need a placed branch or ATM within 4 m. Nothing works away from them, ATMs included.
- First start with an empty `vbank_places`: the 8 standard counters from qb-banking (vanilla Fleeca + Pacific Standard) are added so the bank works straight away; admins can move or delete them.

## Safety

- Every request goes through the router: loaded character, rate limit (10/s), pcall, typed input checks (`Rules.wholeAmount`, account number format, role names, name length 1–24, note ≤ 60).
- Access is decided on the server per request (`access.lua`); the UI only hides what the server would refuse anyway.
- Balances never negative (atomic SQL); refunds on any failed second step.
- No secrets in config (clients download it).

## Testing

- Unit tests (fengari, like the other Vanguard projects): amounts, account number format / parsing, role permissions matrix per account type, transfer validation.
- Lua syntax check of every file; `node --check` for the UI.
- Browser previews of bank (dashboard, account, transfer, open-account flow) and ATM screens with sample data; headless screenshots checked before install.
- Code / security review agent before installing.
- In-game test list for the user: `/bankadmin` → place an ATM (snaps to the prop) and a branch, deposit/withdraw at branch and ATM, an unplaced ATM does nothing, transfer to another account, open Savings, open Shared + add member, business account visible to Owner, police fine still lands in the police job account.

## Install on this server

1. Back up `server.cfg`; move `[qb]/qb-banking` to `backups/disabled-resources/`.
2. Copy to `[local]/vanguard-bank`; it must start after qb-core and oxmysql and before scripts that call qb-banking while starting (exact server.cfg line chosen in the plan after reading the current start order).
3. server.cfg: `add_ace group.admin vanguard.bank.admin allow` (placement tool).
4. Update Vanguard Business (project + server) with the money adapter.
5. Full server restart (not a single-resource restart).
