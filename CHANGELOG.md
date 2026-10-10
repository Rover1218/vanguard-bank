# Changelog

## 1.0.0 — 2026-10-10

- Branches and ATMs placed in game (`/bankadmin`); the 8 standard bank counters are added on first start. Only placed ATMs work; the server checks the player is at one for every action.
- Branch: accounts dashboard, deposit, withdraw, transfer by account number with the receiver's name shown first, history, open account (Savings / Shared) in three steps, rename, close (when empty), shared-account members with Member / Viewer roles.
- ATM: withdraw and deposit only.
- Account types: Personal (QBCore bank money), Savings, Shared, Business (Vanguard Business), Job and Gang (boss grade).
- Personal history includes bank money moved by other scripts; transfers to offline players are paid when they next log in.
- Replaces qb-banking: `provide 'qb-banking'` with the same exports; qb-banking accounts copied once.
