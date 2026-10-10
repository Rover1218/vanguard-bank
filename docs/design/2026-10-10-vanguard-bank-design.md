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
| Not in v1 | Cards / PIN, savings interest, loans, opening fees, phone app, daily ATM limit. |

## What players see

### Branch (8 bank counters from qb-banking's list, map icon "Bank", press E)

1. **Loader** — "Connecting to Vanguard Bank" with the logo animating while accounts load (at least 600 ms so it never flickers).
2. **Dashboard** — account cards (type icon, name, number, animated balance). Personal first, then owned, shared, business, job.
3. **Account view** — balance, quick actions (Deposit, Withdraw, Transfer), history list (newest first, 50 rows, "load more"), and for owners: Members, Rename, Close.
4. **Deposit / Withdraw** — amount field with quick chips (100, 500, 1 000, 5 000, All). Cash ↔ account.
5. **Transfer** — from this account to an account number. On typing a valid number the server returns the receiver's name ("Mia Tanaka — Savings"); the player confirms. Optional note (max 60 chars).
6. **Open account** — step flow: choose type (Savings / Shared) → name it → confirm → loader "Opening your account…" → success card with the new number (`VB-4821-0397`) and a copy button.
7. **Members (Shared, owner only)** — add a player by server ID (they must be online), pick role, change role, remove.
8. **Close** — only when the balance is 0. Personal, Business and Job accounts cannot be closed here.

### ATM (props `prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm`, press E)

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
  server/main.lua        start-up, hello
  client/main.lua        requests, NUI open/close
  client/places.lua      branch blips + E prompts, ATM detection + E prompt
  html/                  index.html, style.css, app.js (bank + ATM modes, preview data)
```

### Data (tables created automatically)

- `vbank_accounts` — `id`, `number` (unique), `type` (savings, shared, business, job, gang), `name`, `owner` (citizenid, null for business/job/gang), `ref` (business id / job / gang name), `balance` BIGINT ≥ 0, `created_at`.
- `vbank_personal` — `citizenid` (PK), `number` (unique). Balance stays in QBCore.
- `vbank_members` — `account_id`, `citizenid`, `name`, `role`.
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

### Places

- Branches: the 8 qb-banking locations (vanilla Fleeca + Pacific counters), interact distance 2 m; server re-checks the player is within 5 m of a branch for every branch action.
- ATMs: the client finds an ATM prop within 1.5 m and shows the prompt. The server cannot see map props, so ATM actions are limited to deposit / withdraw (which branches allow too); every other action requires a branch. Same limitation as every FiveM bank script; rate limit and `MaxAmount` still apply.

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
- In-game test list for the user: deposit/withdraw at branch and ATM, transfer to another account, open Savings, open Shared + add member, business account visible to Owner, police fine still lands in the police job account.

## Install on this server

1. Back up `server.cfg`; move `[qb]/qb-banking` to `backups/disabled-resources/`.
2. Copy to `[local]/vanguard-bank`; it must start after qb-core and oxmysql and before scripts that call qb-banking while starting (exact server.cfg line chosen in the plan after reading the current start order).
3. Update Vanguard Business (project + server) with the money adapter.
4. Full server restart (not a single-resource restart).
