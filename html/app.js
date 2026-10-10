'use strict';
/* Vanguard Bank - NUI: bank (branch), ATM, admin placement bar and branch-name prompt.
   Opened in a normal browser it runs a preview with sample data:
   #loading #bank #account #deposit #transfer #confirm #open #name #opened #members #atm #atmpick #placement #label */

const IS_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IS_GAME ? GetParentResourceName() : 'vanguard-bank';
const LOADER_MIN_MS = 600;
const COUNT_MS = 650;
const LOOKUP_DELAY_MS = 350;
const CLOSE_MS = 200;
const REDUCED_MOTION = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const SVG_NS = 'http://www.w3.org/2000/svg';

const appNode = document.getElementById('app');
const placementNode = document.getElementById('placement');
const promptNode = document.getElementById('prompt');
const toastsNode = document.getElementById('toasts');

const ui = {
    brand: { Title: 'VANGUARD', Subtitle: 'BANK', Accent: '#6366f1' },
    state: null,
    view: 'dashboard',
    number: null,
    history: [],
    historyMore: false,
    historyLoading: false,
    sheet: null,
    wizard: { step: 1, type: null, name: '' },
    opened: null,
    transfer: { from: null, to: '', amount: '', note: '', receiver: null },
    members: [],
    atm: { number: null, amount: '', loader: null },
    shown: new Map(),
    busy: false,
    loader: null,
    renderedView: null,
    promptFinish: null,
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
        if (value === null || value === undefined || value === false) continue;
        if (key === 'class') node.className = value;
        else if (key === 'text') node.textContent = value;
        else if (key === 'value') node.value = value;
        else if (key === 'dataset') Object.assign(node.dataset, value);
        else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
        else node.setAttribute(key, value === true ? '' : value);
    }
    node.append(...children.flat().filter((child) => child !== null && child !== undefined && child !== false));
    return node;
}

function setChildren(node, ...children) {
    node.replaceChildren(...children.flat().filter((child) => child !== null && child !== undefined && child !== false));
}

const ICONS = {
    wallet: 'M3 7a2 2 0 0 1 2-2h12v4M3 7v10a2 2 0 0 0 2 2h14V9H5a2 2 0 0 1-2-2zM16 14h.01',
    safe: 'M4 5h16v14H4zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 12h.01M6 19v2M18 19v2',
    users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
    store: 'M3 9l1.5-5h15L21 9M4 9v11h16V9M3 9h18M9 20v-6h6v6',
    badge: 'M12 2l7 3v6c0 5-3 9-7 11-4-2-7-6-7-11V5z',
    flag: 'M4 22V4M4 4h13l-2 4 2 4H4',
    grid: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
    send: 'M22 2L11 13M22 2l-7 20-4-9-9-4z',
    plus: 'M12 5v14M5 12h14',
    close: 'M18 6L6 18M6 6l12 12',
    copy: 'M9 9h11v11H9zM5 15H4V4h11v1',
    in: 'M17 7L7 17M7 7v10h10',
    out: 'M7 17L17 7M7 7h10v10',
    check: 'M20 6L9 17l-5-5',
    alert: 'M12 9v4M12 17h.01M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
    back: 'M15 18l-6-6 6-6',
    pin: 'M12 22s-7-7.2-7-12a7 7 0 1 1 14 0c0 4.8-7 12-7 12zM12 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z',
    edit: 'M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z',
    trash: 'M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6',
    leave: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
    refund: 'M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5',
    spark: 'M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6',
    del: 'M21 5H8l-7 7 7 7h13zM18 9l-6 6M12 9l6 6',
};

function icon(name) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', ICONS[name] || ICONS.spark);
    svg.append(path);
    return svg;
}

const TYPES = {
    personal: { label: 'Personal', icon: 'wallet' },
    savings: { label: 'Savings', icon: 'safe' },
    shared: { label: 'Shared', icon: 'users' },
    business: { label: 'Business', icon: 'store' },
    job: { label: 'Job', icon: 'badge' },
    gang: { label: 'Gang', icon: 'flag' },
};
const ROLES = { holder: 'Holder', owner: 'Owner', member: 'Member', viewer: 'Viewer', boss: 'Boss' };
const KINDS = {
    deposit: { label: 'Deposit', icon: 'in' },
    withdraw: { label: 'Withdrawal', icon: 'out' },
    transfer_in: { label: 'Transfer received', icon: 'in' },
    transfer_out: { label: 'Transfer sent', icon: 'out' },
    income: { label: 'Payment received', icon: 'in' },
    payment: { label: 'Payment', icon: 'out' },
    refund: { label: 'Refund', icon: 'refund' },
    system: { label: 'Account', icon: 'spark' },
};
const MY_MONEY = new Set(['personal', 'savings', 'shared']);

const money = (n) => `${n < 0 ? '-' : ''}$${Math.floor(Math.abs(Number(n) || 0)).toLocaleString('en-US')}`;
const findAccount = (number) => (ui.state && number ? ui.state.accounts.find((account) => account.number === number) : null);

function dayLabel(seconds) {
    const date = new Date(seconds * 1000);
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);
    if (date.toDateString() === today.toDateString()) return 'Today';
    if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
    return date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

const timeLabel = (seconds) => new Date(seconds * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

/** Animates a money figure from what this key last showed to its new value. */
function countUp(node, key, value) {
    const from = ui.shown.has(key) ? ui.shown.get(key) : 0;
    ui.shown.set(key, value);
    node.textContent = money(from);
    if (REDUCED_MOTION || from === value) { node.textContent = money(value); return; }
    const start = performance.now();
    const step = (now) => {
        const t = Math.min(1, (now - start) / COUNT_MS);
        node.textContent = money(from + (value - from) * (1 - Math.pow(1 - t, 3)));
        if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

function copyText(text) {
    const area = el('textarea', { style: 'position:fixed;opacity:0' });
    area.value = text;
    document.body.append(area);
    area.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch { copied = false; }
    area.remove();
    toast(copied ? `Copied ${text}` : text, true);
}

function toast(message, ok = true) {
    if (!message) return;
    const node = el('div', { class: `toast${ok ? '' : ' is-error'}`, role: 'status', text: message });
    toastsNode.append(node);
    setTimeout(() => node.classList.add('is-leaving'), 3200);
    setTimeout(() => node.remove(), 3600);
}

// ---------------------------------------------------------------------------
// Talking to the game
// ---------------------------------------------------------------------------

async function post(endpoint, data = {}) {
    if (!IS_GAME) return Preview.respond(endpoint, data);
    try {
        const response = await fetch(`https://${RESOURCE}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        return await response.json();
    } catch {
        return { ok: false, message: 'The bank did not answer' };
    }
}

/** Runs a server action from a button and shows the result. */
async function act(action, data, button) {
    if (ui.busy) return { ok: false };
    ui.busy = true;
    if (button) button.classList.add('is-busy');
    const result = await post('request', { action, data });
    ui.busy = false;
    if (button) button.classList.remove('is-busy');
    toast(result.message, result.ok);
    return result;
}

/** Fresh balances from the server. */
async function refresh() {
    const result = await post('request', { action: 'open' });
    if (!result.ok) { toast(result.message, false); return false; }
    ui.state = result.data;
    if (ui.number && !findAccount(ui.number)) { ui.view = 'dashboard'; ui.number = null; }
    render();
    return true;
}

function close() {
    if (IS_GAME) post('close');
    else hideApp();
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

function brandBlock(subtitle) {
    return el('div', { class: 'brand' },
        el('span', { class: 'logo', text: ui.brand.Title.charAt(0) }),
        el('span', { class: 'brand-text' }, el('strong', { text: ui.brand.Title }), el('small', { text: subtitle || ui.brand.Subtitle })));
}

function ringCircle(svg, cls, radius) {
    const circle = document.createElementNS(SVG_NS, 'circle');
    circle.setAttribute('cx', '50');
    circle.setAttribute('cy', '50');
    circle.setAttribute('r', String(radius));
    circle.setAttribute('class', cls);
    svg.append(circle);
    return circle;
}

/** A loader whose ring spins and fills 0 -> 100%. Driven by JavaScript, so it moves even with
    Windows animations off. finish() runs it to 100% (after LOADER_MIN_MS) and resolves. */
function makeLoader(text) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('viewBox', '0 0 100 100');
    svg.setAttribute('class', 'ring');
    ringCircle(svg, 'ring-track', 42);
    const arc = ringCircle(svg, 'ring-arc', 42);
    const spinner = ringCircle(svg, 'ring-spin', 48);
    const length = 2 * Math.PI * 42;
    arc.setAttribute('stroke-dasharray', String(length));
    arc.setAttribute('stroke-dashoffset', String(length));
    arc.setAttribute('transform', 'rotate(-90 50 50)');
    const percent = el('strong', { class: 'percent', text: '0%' });
    const node = el('div', { class: 'loader' },
        el('div', { class: 'loader-mark' }, svg, el('span', { class: 'logo', text: ui.brand.Title.charAt(0) })),
        percent, el('p', { text }));

    const state = { started: performance.now(), finishedAt: null, from: 0, value: 0, stopped: false };
    let resolveDone;
    const done = new Promise((resolve) => { resolveDone = resolve; });
    const paint = (now) => {
        if (state.stopped) return;
        state.value = state.finishedAt === null ? Progress.waiting(now - state.started) : Progress.finishing(state.from, now - state.finishedAt);
        arc.setAttribute('stroke-dashoffset', String(length * (1 - state.value / 100)));
        spinner.setAttribute('transform', `rotate(${Progress.spin(now - state.started)} 50 50)`);
        percent.textContent = `${Math.floor(state.value)}%`;
        if (state.value >= 100) { state.stopped = true; resolveDone(); return; }
        requestAnimationFrame(paint);
    };
    requestAnimationFrame(paint);

    return {
        node,
        finish() {
            if (state.finishedAt === null && !state.finishing) {
                state.finishing = true;
                setTimeout(() => { state.from = state.value; state.finishedAt = performance.now(); },
                    Math.max(0, LOADER_MIN_MS - (performance.now() - state.started)));
            }
            return done;
        },
        stop() { state.stopped = true; resolveDone(); },
    };
}

function numberLine(number) {
    return el('span', {
        class: 'card-number', title: 'Copy number',
        onclick: (event) => { event.stopPropagation(); copyText(number); },
    }, number, icon('copy'));
}

function pickRow(account, selected, onclick) {
    const meta = TYPES[account.type] || TYPES.personal;
    return el('button', { class: `pick${selected ? ' is-selected' : ''}`, type: 'button', dataset: { type: account.type }, onclick },
        icon(meta.icon),
        el('span', {}, el('strong', { text: account.name }), el('small', { text: account.number })),
        el('b', { text: money(account.balance) }));
}

function summaryLine(label, value, big = false) {
    return el('div', {}, el('span', { text: label }), el('b', { class: big ? 'big' : null, text: value }));
}

function amountInput(target, key) {
    return el('input', {
        class: 'input is-big', type: 'text', inputmode: 'numeric', placeholder: '0', maxlength: '9',
        autocomplete: 'off', value: target[key] || '',
        oninput: (event) => {
            const digits = event.target.value.replace(/\D/g, '');
            event.target.value = digits;
            target[key] = digits;
        },
    });
}

function quickChips(input, target, key, all) {
    const set = (value) => { target[key] = String(value); input.value = target[key]; };
    return el('div', { class: 'chips' },
        (ui.state.quick || []).map((amount) => el('button', { class: 'chip', type: 'button', onclick: () => set(amount) }, money(amount))),
        all > 0 ? el('button', { class: 'chip', type: 'button', onclick: () => set(Math.min(all, ui.state.maxAmount)) }, 'All') : null);
}

const parseAmount = (text) => (/^\d+$/.test(text || '') ? Number(text) : NaN);

function amountProblem(amount, available, what) {
    if (!Number.isInteger(amount) || amount < 1) return 'Enter an amount';
    if (amount > ui.state.maxAmount) return `The most at once is ${money(ui.state.maxAmount)}`;
    if (amount > available) return `Not enough ${what}`;
    return null;
}

function focusFirstInput() {
    setTimeout(() => {
        const input = appNode.querySelector('.sheet input, .form input:not([readonly])');
        if (input) input.focus();
    }, 40);
}

// ---------------------------------------------------------------------------
// Bank: frame
// ---------------------------------------------------------------------------

const NAV = [
    { view: 'dashboard', label: 'Accounts', icon: 'grid', also: ['account', 'members'] },
    { view: 'transfer', label: 'Transfer', icon: 'send', also: [] },
    { view: 'open', label: 'Open account', icon: 'plus', also: [] },
];

const TITLES = {
    dashboard: ['Overview', 'Your accounts'],
    account: ['Account', null],
    transfer: ['Payments', 'Transfer money'],
    open: ['New account', 'Open an account'],
    members: ['Shared account', 'Members'],
};

function go(view, number = null) {
    ui.view = view;
    ui.number = number;
    ui.sheet = null;
    if (view === 'open') { ui.wizard = { step: 1, type: null, name: '' }; ui.opened = null; }
    if (view === 'transfer') ui.transfer = { from: number, to: '', amount: '', note: '', receiver: null };
    if (view === 'account') loadHistory(true);
    if (view === 'members') loadMembers();
    render();
}

function renderRail() {
    const state = ui.state;
    return el('aside', { class: 'rail' },
        brandBlock(),
        el('nav', { class: 'nav' }, NAV.map((item) => el('button', {
            class: `nav-item${item.view === ui.view || item.also.includes(ui.view) ? ' is-active' : ''}`,
            type: 'button', onclick: () => go(item.view),
        }, icon(item.icon), item.label))),
        el('div', { class: 'customer' },
            el('small', { text: 'Customer' }),
            el('strong', { text: state.name }),
            el('div', { class: 'cash' }, el('span', { text: 'Cash on hand' }), el('b', { text: money(state.cash) })),
            el('div', { class: 'place' }, icon('pin'), state.place)));
}

function stageHead() {
    const [kicker, title] = TITLES[ui.view] || TITLES.dashboard;
    const account = findAccount(ui.number);
    return el('header', { class: 'stage-head' },
        el('div', { class: 'stage-title' }, el('small', { text: kicker }), el('h1', { text: title || (account ? account.name : '') })),
        el('button', { class: 'icon-btn', type: 'button', title: 'Close', onclick: close }, icon('close')));
}

function renderView() {
    if (ui.view === 'account') return renderAccount();
    if (ui.view === 'transfer') return renderTransfer();
    if (ui.view === 'open') return renderOpen();
    if (ui.view === 'members') return renderMembers();
    return renderDashboard();
}

function renderBank() {
    const key = `${ui.view}:${ui.number}:${ui.wizard.step}:${ui.opened ? 1 : 0}`;
    const isStatic = ui.renderedView === key; // same screen, new data: no entrance animations
    ui.renderedView = key;
    const stage = el('main', { class: 'stage' }, stageHead(), el('div', { class: 'stage-body' }, renderView()));
    if (ui.sheet) stage.append(renderSheet());
    return el('div', { class: `bank${isStatic ? ' is-static' : ''}` }, renderRail(), stage);
}

function render() {
    if (!ui.state) return;
    setChildren(appNode, ui.state.mode === 'atm' ? renderAtm() : renderBank());
}

// ---------------------------------------------------------------------------
// Bank: dashboard
// ---------------------------------------------------------------------------

function accountCard(account, index) {
    const meta = TYPES[account.type] || TYPES.personal;
    const balance = el('div', { class: 'card-balance' });
    countUp(balance, `card:${account.number}`, account.balance);
    return el('button', {
        class: `card${account.type === 'personal' ? ' is-hero' : ''}`, type: 'button',
        dataset: { type: account.type }, style: `--i:${index}`,
        onclick: () => go('account', account.number),
    },
        el('div', { class: 'card-top' },
            el('span', { class: 'card-type' }, icon(meta.icon), meta.label),
            el('span', { class: 'tag', text: ROLES[account.role] || account.role })),
        el('div', {}, el('div', { class: 'card-name', text: account.name }), numberLine(account.number)),
        balance);
}

function renderDashboard() {
    const list = ui.state.accounts;
    const total = list.filter((account) => MY_MONEY.has(account.type)).reduce((sum, account) => sum + account.balance, 0);
    const totalNode = el('div', { class: 'total' });
    countUp(totalNode, 'total', total);
    const cards = list.map((account, index) => accountCard(account, index));
    if (ui.state.owned < ui.state.maxOwned) {
        cards.push(el('button', { class: 'card is-new', type: 'button', style: `--i:${list.length}`, onclick: () => go('open') },
            icon('plus'), el('strong', { text: 'Open an account' }),
            el('small', { text: `${ui.state.owned} of ${ui.state.maxOwned} extra accounts used` })));
    }
    return el('div', { class: 'view' },
        el('div', { class: 'overview' },
            el('div', {}, el('small', { text: 'Your money (personal, savings, shared)' }), totalNode),
            el('div', { class: 'meta' }, el('span', { class: 'tag', text: `${list.length} account${list.length === 1 ? '' : 's'}` }))),
        el('div', { class: 'cards' }, cards));
}

// ---------------------------------------------------------------------------
// Bank: one account
// ---------------------------------------------------------------------------

async function loadHistory(reset) {
    const number = ui.number;
    const before = !reset && ui.history.length ? ui.history[ui.history.length - 1].id : null;
    if (reset) { ui.history = []; ui.historyMore = false; ui.historyLoading = true; }
    const result = await post('request', { action: 'history', data: { number, before } });
    if (ui.number !== number || ui.view !== 'account') return;
    ui.historyLoading = false;
    if (!result.ok) { toast(result.message, false); render(); return; }
    const rows = result.data.rows || [];
    ui.history = reset ? rows : ui.history.concat(rows);
    ui.historyMore = rows.length >= (ui.state.historyPage || 50);
    render();
}

function historyRow(row, index) {
    const kind = KINDS[row.kind] || KINDS.system;
    const amount = Number(row.amount) || 0;
    const direction = amount > 0 ? 'is-in' : (amount < 0 ? 'is-out' : '');
    const detail = [row.note, row.actor].filter(Boolean).join(' · ');
    return el('div', { class: `row ${direction}`, style: `--i:${Math.min(index, 12)}` },
        el('span', { class: 'row-icon' }, icon(kind.icon)),
        el('div', { class: 'row-text' }, el('strong', { text: kind.label }), detail ? el('small', { text: detail }) : null),
        el('div', { class: 'row-amount' },
            amount === 0 ? '—' : `${amount > 0 ? '+' : '-'}${money(Math.abs(amount))}`,
            el('small', { text: timeLabel(row.time) })));
}

function renderHistory() {
    if (ui.historyLoading) return el('div', { class: 'empty', text: 'Loading history…' });
    if (!ui.history.length) return el('div', { class: 'empty', text: 'No transactions yet. Deposits, transfers and payments show up here.' });
    const nodes = [];
    let lastDay = null;
    ui.history.forEach((row, index) => {
        const day = dayLabel(row.time);
        if (day !== lastDay) { nodes.push(el('div', { class: 'day', text: day })); lastDay = day; }
        nodes.push(historyRow(row, index));
    });
    if (ui.historyMore) {
        nodes.push(el('button', {
            class: 'btn is-ghost is-wide', type: 'button',
            onclick: (event) => { event.currentTarget.classList.add('is-busy'); loadHistory(false); },
        }, 'Load more'));
    }
    return el('div', { class: 'history' }, nodes);
}

function actionButton(iconName, label, onclick, primary = false) {
    return el('button', { class: `btn${primary ? ' is-primary' : ''}`, type: 'button', onclick }, icon(iconName), label);
}

function accountActions(account) {
    const can = account.can || {};
    const buttons = [];
    if (can.deposit) buttons.push(actionButton('in', 'Deposit', () => openSheet('deposit', account), true));
    if (can.withdraw) buttons.push(actionButton('out', 'Withdraw', () => openSheet('withdraw', account)));
    if (can.transfer) buttons.push(actionButton('send', 'Transfer', () => go('transfer', account.number)));
    buttons.push(el('span', { class: 'spacer' }));
    if (can.manage && account.type === 'shared') buttons.push(actionButton('users', 'Members', () => go('members', account.number)));
    if (can.manage) buttons.push(actionButton('edit', 'Rename', () => openSheet('rename', account)));
    if (can.manage) {
        buttons.push(el('button', {
            class: 'btn is-danger', type: 'button', disabled: account.balance !== 0,
            title: account.balance !== 0 ? 'Empty the account first' : null,
            onclick: () => openSheet('close', account),
        }, icon('trash'), 'Close'));
    }
    if (account.type === 'shared' && (account.role === 'member' || account.role === 'viewer')) {
        buttons.push(actionButton('leave', 'Leave', () => openSheet('leave', account)));
    }
    return el('div', { class: 'actions' }, buttons);
}

function renderAccount() {
    const account = findAccount(ui.number);
    if (!account) return renderDashboard();
    const meta = TYPES[account.type] || TYPES.personal;
    const balance = el('span', {});
    countUp(balance, `account:${account.number}`, account.balance);
    return el('div', { class: 'view' },
        el('button', { class: 'back', type: 'button', onclick: () => go('dashboard') }, icon('back'), 'All accounts'),
        el('section', { class: 'account-hero', dataset: { type: account.type } },
            el('div', {},
                el('span', { class: 'card-type' }, icon(meta.icon), `${meta.label} · ${ROLES[account.role] || account.role}`),
                el('h2', { text: account.name }),
                numberLine(account.number)),
            el('div', { class: 'balance' }, el('small', { text: 'Balance' }), balance)),
        accountActions(account),
        el('div', { class: 'section-title', text: 'History' }),
        renderHistory());
}

// ---------------------------------------------------------------------------
// Bank: sheets (deposit, withdraw, rename, close, leave, transfer confirm)
// ---------------------------------------------------------------------------

function openSheet(kind, account) {
    ui.sheet = { kind, number: account.number, value: kind === 'rename' ? account.name : '' };
    render();
    focusFirstInput();
}

function closeSheet() {
    ui.sheet = null;
    render();
}

function sheetForm(onSubmit, ...children) {
    return el('form', {
        class: 'sheet',
        onsubmit: (event) => { event.preventDefault(); onSubmit(event.currentTarget.querySelector('[type=submit]')); },
    }, ...children);
}

function sheetActions(label, danger = false) {
    return el('div', { class: 'sheet-actions' },
        el('button', { class: 'btn', type: 'button', onclick: closeSheet }, 'Cancel'),
        el('button', { class: `btn ${danger ? 'is-danger' : 'is-primary'}`, type: 'submit' }, label));
}

function amountSheet(kind, account) {
    const isDeposit = kind === 'deposit';
    const available = isDeposit ? ui.state.cash : account.balance;
    const input = amountInput(ui.sheet, 'value');
    const submit = async (button) => {
        const amount = parseAmount(ui.sheet.value);
        const problem = amountProblem(amount, available, isDeposit ? 'cash' : 'money in this account');
        if (problem) return toast(problem, false);
        const result = await act(kind, { number: account.number, amount }, button);
        if (!result.ok) return;
        ui.sheet = null;
        await refresh();
        if (ui.view === 'account') loadHistory(true);
    };
    return sheetForm(submit,
        el('h3', { text: isDeposit ? 'Deposit cash' : 'Withdraw cash' }),
        el('p', { text: `${isDeposit ? 'Into' : 'From'} ${account.name} · ${account.number}` }),
        el('div', { class: 'hint' }, el('span', { text: isDeposit ? 'Cash on hand' : 'Available' }), el('b', { text: money(available) })),
        input,
        quickChips(input, ui.sheet, 'value', available),
        sheetActions(isDeposit ? 'Deposit' : 'Withdraw'));
}

function renameSheet(account) {
    const submit = async (button) => {
        const result = await act('rename', { number: account.number, name: ui.sheet.value }, button);
        if (result.ok) { ui.sheet = null; await refresh(); }
    };
    return sheetForm(submit,
        el('h3', { text: 'Rename account' }),
        el('label', { class: 'field' }, el('span', { text: 'Name (up to 24 characters)' }),
            el('input', { class: 'input', type: 'text', maxlength: '24', value: ui.sheet.value, oninput: (event) => { ui.sheet.value = event.target.value; } })),
        sheetActions('Save'));
}

function confirmSheet(kind, account) {
    const isClose = kind === 'close';
    const submit = async (button) => {
        const result = await act(isClose ? 'closeAccount' : 'leave', { number: account.number }, button);
        if (!result.ok) return;
        ui.sheet = null;
        ui.view = 'dashboard';
        ui.number = null;
        await refresh();
    };
    return sheetForm(submit,
        el('h3', { text: isClose ? 'Close this account?' : 'Leave this account?' }),
        el('p', { text: isClose
            ? `${account.name} (${account.number}) will be closed for good. Its members lose access.`
            : `You will no longer see ${account.name}. The owner can add you again.` }),
        sheetActions(isClose ? 'Close account' : 'Leave', true));
}

function transferSheet() {
    const transfer = ui.transfer;
    const from = findAccount(transfer.from);
    const amount = parseAmount(transfer.amount);
    const submit = async (button) => {
        const result = await act('transfer', { from: transfer.from, to: transfer.receiver.number, amount, note: transfer.note }, button);
        if (!result.ok) return;
        ui.sheet = null;
        ui.transfer = { from: transfer.from, to: '', amount: '', note: '', receiver: null };
        await refresh();
    };
    return sheetForm(submit,
        el('h3', { text: 'Confirm transfer' }),
        el('div', { class: 'summary' },
            summaryLine('From', `${from.name} · ${from.number}`),
            summaryLine('To', `${transfer.receiver.label} · ${transfer.receiver.number}`),
            transfer.note ? summaryLine('Note', transfer.note) : null,
            summaryLine('Amount', money(amount), true)),
        sheetActions('Send money'));
}

function renderSheet() {
    const kind = ui.sheet.kind;
    const account = findAccount(ui.sheet.number);
    let body;
    if (kind === 'transfer') body = transferSheet();
    else if (!account) return null;
    else if (kind === 'deposit' || kind === 'withdraw') body = amountSheet(kind, account);
    else if (kind === 'rename') body = renameSheet(account);
    else body = confirmSheet(kind, account);
    return el('div', { class: 'sheet-layer', onclick: (event) => { if (event.target === event.currentTarget) closeSheet(); } }, body);
}

// ---------------------------------------------------------------------------
// Bank: transfer
// ---------------------------------------------------------------------------

let lookupTimer = null;

function showReceiver(node) {
    const receiver = ui.transfer.receiver;
    node.className = `receiver${receiver ? (receiver.error ? ' is-bad' : ' is-ok') : ''}`;
    if (!receiver) return setChildren(node, el('span', { text: 'Type the 8-digit number - the owner shows up here.' }));
    setChildren(node, icon(receiver.error ? 'alert' : 'check'), el('span', { text: receiver.error || `${receiver.label} · ${receiver.number}` }));
}

function onReceiverInput(value, node) {
    const transfer = ui.transfer;
    transfer.to = value;
    transfer.receiver = null;
    clearTimeout(lookupTimer);
    showReceiver(node);
    if (value.replace(/\D/g, '').length !== 8) return;
    lookupTimer = setTimeout(async () => {
        const result = await post('request', { action: 'lookup', data: { number: value } });
        if (ui.transfer.to !== value) return;
        transfer.receiver = result.ok ? { number: result.data.number, label: result.data.label } : { error: result.message };
        showReceiver(node);
    }, LOOKUP_DELAY_MS);
}

function reviewTransfer() {
    const transfer = ui.transfer;
    const from = findAccount(transfer.from);
    if (!transfer.receiver || transfer.receiver.error) return toast('Enter a valid account number first', false);
    if (transfer.receiver.number === from.number) return toast('Pick a different account to send to', false);
    const problem = amountProblem(parseAmount(transfer.amount), from.balance, 'money in that account');
    if (problem) return toast(problem, false);
    ui.sheet = { kind: 'transfer', number: from.number };
    render();
}

function renderTransfer() {
    const transfer = ui.transfer;
    const sources = ui.state.accounts.filter((account) => account.can && account.can.transfer);
    if (!sources.length) return el('div', { class: 'view' }, el('div', { class: 'empty', text: 'None of your accounts can send money.' }));
    if (!sources.some((account) => account.number === transfer.from)) transfer.from = sources[0].number;
    const from = findAccount(transfer.from);
    const receiver = el('div', { class: 'receiver' });
    showReceiver(receiver);
    const amount = amountInput(transfer, 'amount');
    return el('div', { class: 'view split' },
        el('div', { class: 'form' },
            el('div', { class: 'field' }, el('span', { text: 'From' }),
                el('div', { class: 'picker' }, sources.map((account) => pickRow(account, account.number === transfer.from, () => { transfer.from = account.number; render(); }))))),
        el('form', { class: 'form', onsubmit: (event) => { event.preventDefault(); reviewTransfer(); } },
            el('label', { class: 'field' }, el('span', { text: 'To account number' }),
                el('input', { class: 'input mono', type: 'text', placeholder: 'VB-1234-5678', maxlength: '14', value: transfer.to, oninput: (event) => onReceiverInput(event.target.value, receiver) })),
            receiver,
            el('label', { class: 'field' }, el('span', { text: `Amount · ${money(from.balance)} available` }), amount),
            quickChips(amount, transfer, 'amount', from.balance),
            el('label', { class: 'field' }, el('span', { text: 'Note (optional)' }),
                el('input', { class: 'input', type: 'text', maxlength: '60', placeholder: 'Rent, food, thanks…', value: transfer.note, oninput: (event) => { transfer.note = event.target.value; } })),
            el('button', { class: 'btn is-primary is-wide', type: 'submit' }, icon('send'), 'Review transfer')));
}

// ---------------------------------------------------------------------------
// Bank: open an account
// ---------------------------------------------------------------------------

const OPENABLE = [
    { type: 'savings', title: 'Savings', icon: 'safe', text: 'Money put aside, just for you. Only you can see and use it.' },
    { type: 'shared', title: 'Shared', icon: 'users', text: 'One pot for friends, family or a crew. You add members and choose who can take money out.' },
];
const NAME_IDEAS = { savings: ['Rainy day', 'New car', 'House fund'], shared: ['Crew fund', 'Household', 'Trip money'] };

function wizardFoot(backStep, submitLabel, submitIcon) {
    return el('div', { class: 'wizard-foot' },
        el('button', { class: 'btn is-ghost', type: 'button', onclick: () => { ui.wizard.step = backStep; render(); focusFirstInput(); } }, icon('back'), 'Back'),
        el('button', { class: 'btn is-primary', type: 'submit' }, submitIcon ? icon(submitIcon) : null, submitLabel));
}

function wizardType() {
    const full = ui.state.owned >= ui.state.maxOwned;
    return el('div', {},
        el('div', { class: 'options' }, OPENABLE.map((option) => el('button', {
            class: 'option', type: 'button', dataset: { type: option.type }, disabled: full,
            onclick: () => { ui.wizard = { step: 2, type: option.type, name: '' }; render(); focusFirstInput(); },
        }, icon(option.icon), el('strong', { text: option.title }), el('p', { text: option.text })))),
        el('p', { class: 'note', text: full
            ? `You already own ${ui.state.maxOwned} extra accounts - close one to open another.`
            : `You own ${ui.state.owned} of ${ui.state.maxOwned} extra accounts. Opening one is free.` }));
}

function wizardName() {
    const wizard = ui.wizard;
    const input = el('input', { class: 'input', type: 'text', maxlength: '24', placeholder: 'Account name', value: wizard.name, oninput: (event) => { wizard.name = event.target.value; } });
    const next = (event) => {
        event.preventDefault();
        if (!wizard.name.trim()) return toast('Give the account a name', false);
        wizard.step = 3;
        render();
    };
    return el('form', { class: 'form', style: 'max-width:520px', onsubmit: next },
        el('label', { class: 'field' }, el('span', { text: 'Name your account' }), input),
        el('div', { class: 'chips' }, NAME_IDEAS[wizard.type].map((idea) => el('button', {
            class: 'chip', type: 'button', onclick: () => { wizard.name = idea; input.value = idea; },
        }, idea))),
        wizardFoot(1, 'Continue'));
}

function wizardConfirm() {
    const wizard = ui.wizard;
    const option = OPENABLE.find((entry) => entry.type === wizard.type);
    return el('form', { class: 'form', style: 'max-width:520px', onsubmit: (event) => { event.preventDefault(); openAccount(); } },
        el('div', { class: 'summary' },
            summaryLine('Type', option.title), summaryLine('Name', wizard.name.trim()),
            summaryLine('Owner', ui.state.name), summaryLine('Fee', 'Free')),
        el('p', { class: 'note', text: wizard.type === 'shared'
            ? 'After opening, add members from the account page.'
            : 'You can rename or close it any time from the account page.' }),
        wizardFoot(2, 'Open account', 'check'));
}

async function openAccount() {
    const wizard = ui.wizard;
    const body = appNode.querySelector('.stage-body');
    const loader = makeLoader('Opening your account');
    if (body) setChildren(body, loader.node);
    const result = await post('request', { action: 'openAccount', data: { type: wizard.type, name: wizard.name } });
    if (!result.ok) { loader.stop(); toast(result.message, false); render(); return; }
    await loader.finish();
    ui.opened = result.data;
    await refresh();
}

function renderOpened() {
    const opened = ui.opened;
    return el('div', { class: 'opened' },
        el('span', { class: 'tick' }, icon('check')),
        el('h2', { text: `${opened.name} is open` }),
        el('p', { class: 'note', text: 'Your new account number' }),
        el('div', { class: 'number', text: opened.number }),
        el('div', { class: 'chips' }, el('button', { class: 'chip', type: 'button', onclick: () => copyText(opened.number) }, 'Copy number')),
        el('div', { class: 'wizard-foot', style: 'gap:10px' },
            el('button', { class: 'btn', type: 'button', onclick: () => go('dashboard') }, 'All accounts'),
            el('button', { class: 'btn is-primary', type: 'button', onclick: () => go('account', opened.number) }, 'Go to account')));
}

function renderOpen() {
    if (ui.opened) return renderOpened();
    const wizard = ui.wizard;
    const steps = ['Type', 'Name', 'Confirm'];
    const body = wizard.step === 1 ? wizardType() : (wizard.step === 2 ? wizardName() : wizardConfirm());
    return el('div', { class: 'view' },
        el('div', { class: 'steps' }, steps.map((label, index) => el('div', {
            class: `step${index + 1 < wizard.step ? ' is-done' : ''}${index + 1 === wizard.step ? ' is-current' : ''}`,
        }, el('i'), el('span', { text: `${index + 1} · ${label}` })))),
        body);
}

// ---------------------------------------------------------------------------
// Bank: shared account members
// ---------------------------------------------------------------------------

async function loadMembers() {
    ui.members = null;
    const number = ui.number;
    const result = await post('request', { action: 'members', data: { number } });
    if (ui.number !== number || ui.view !== 'members') return;
    if (!result.ok) toast(result.message, false);
    ui.members = result.ok ? (result.data.members || []) : [];
    render();
}

function roleSelect(value, onchange) {
    return el('select', { class: 'input', onchange: (event) => onchange(event.target.value) },
        ['member', 'viewer'].map((role) => el('option', { value: role, selected: role === value }, ROLES[role])));
}

function memberRow(account, member) {
    return el('div', { class: 'member' },
        el('span', { class: 'avatar', text: member.name.charAt(0).toUpperCase() }),
        el('div', { class: 'row-text' }, el('strong', { text: member.name }), el('small', { text: ROLES[member.role] || member.role })),
        roleSelect(member.role, async (role) => {
            const result = await act('setRole', { number: account.number, citizenid: member.citizenid, role });
            if (result.ok) loadMembers();
        }),
        el('button', {
            class: 'icon-btn', type: 'button', title: 'Remove',
            onclick: async (event) => {
                const result = await act('removeMember', { number: account.number, citizenid: member.citizenid }, event.currentTarget);
                if (result.ok) loadMembers();
            },
        }, icon('trash')));
}

function renderMembers() {
    const account = findAccount(ui.number);
    if (!account) return renderDashboard();
    const add = { target: '', role: 'member' };
    let list;
    if (ui.members === null) list = el('div', { class: 'empty', text: 'Loading members…' });
    else if (!ui.members.length) list = el('div', { class: 'empty', text: 'No members yet. Add someone by their server ID below.' });
    else list = el('div', { class: 'members' }, ui.members.map((member) => memberRow(account, member)));
    const submit = async (event) => {
        event.preventDefault();
        const result = await act('addMember', { number: account.number, target: Number(add.target), role: add.role }, event.currentTarget.querySelector('[type=submit]'));
        if (result.ok) loadMembers();
    };
    return el('div', { class: 'view' },
        el('button', { class: 'back', type: 'button', onclick: () => go('account', account.number) }, icon('back'), account.name),
        el('div', { class: 'section-title', text: 'Members' }),
        list,
        el('div', { class: 'section-title', text: 'Add a member' }),
        el('form', { class: 'add-member', onsubmit: submit },
            el('input', { class: 'input', type: 'text', inputmode: 'numeric', placeholder: 'Server ID (e.g. 12)', oninput: (event) => { add.target = event.target.value.replace(/\D/g, ''); event.target.value = add.target; } }),
            roleSelect('member', (role) => { add.role = role; }),
            el('button', { class: 'btn is-primary', type: 'submit' }, icon('plus'), 'Add')),
        el('p', { class: 'note', text: 'Member: deposit, withdraw and transfer. Viewer: see the history and deposit only. They must be online to be added.' }));
}

// ---------------------------------------------------------------------------
// ATM: withdraw and deposit only
// ---------------------------------------------------------------------------

function resetAtm(number = null) {
    ui.atm = { number, amount: '', loader: null };
}

async function atmAction(kind, account) {
    const amount = parseAmount(ui.atm.amount);
    const available = kind === 'deposit' ? ui.state.cash : account.balance;
    const problem = amountProblem(amount, available, kind === 'deposit' ? 'cash' : 'money in the account');
    if (problem) return toast(problem, false);
    const loader = makeLoader('Processing');
    ui.atm.loader = loader;
    render();
    const result = await post('request', { action: kind, data: { number: account.number, amount } });
    if (result.ok) await loader.finish(); else loader.stop();
    if (ui.atm.loader === loader) ui.atm.loader = null;
    toast(result.message, result.ok);
    if (result.ok) ui.atm.amount = '';
    if (!(await refresh())) render();
}

function atmPick() {
    const list = ui.state.accounts;
    return el('div', { class: 'view' },
        el('h2', { text: `Hello, ${ui.state.name.split(' ')[0]}` }),
        el('p', { text: 'Choose an account' }),
        list.length
            ? el('div', { class: 'atm-list' }, list.map((account) => pickRow(account, false, () => { resetAtm(account.number); render(); })))
            : el('div', { class: 'empty', text: 'No accounts available here.' }));
}

function atmAmount(account) {
    const atm = ui.atm;
    const display = el('div', { class: `atm-amount${atm.amount ? '' : ' is-empty'}`, text: atm.amount ? money(Number(atm.amount)) : '$0' });
    const setAmount = (value) => {
        const clean = value.replace(/\D/g, '').replace(/^0+/, '').slice(0, 9);
        atm.amount = clean;
        display.textContent = clean ? money(Number(clean)) : '$0';
        display.classList.toggle('is-empty', !clean);
    };
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'del'];
    return el('div', { class: 'view' },
        el('button', { class: 'back', type: 'button', onclick: () => { resetAtm(); render(); } }, icon('back'), 'Accounts'),
        el('h2', { text: account.name }),
        el('p', { text: `${account.number} · Balance ${money(account.balance)}` }),
        display,
        el('div', { class: 'chips', style: 'margin-bottom:10px' }, (ui.state.quick || []).map((amount) => el('button', {
            class: 'chip', type: 'button', onclick: () => setAmount(String(amount)),
        }, money(amount)))),
        el('div', { class: 'keypad' }, keys.map((key) => el('button', {
            class: 'key', type: 'button', onclick: () => setAmount(key === 'del' ? atm.amount.slice(0, -1) : atm.amount + key),
        }, key === 'del' ? icon('del') : key))),
        el('div', { class: 'atm-actions' },
            el('button', { class: 'btn is-primary', type: 'button', disabled: !account.can.withdraw, onclick: () => atmAction('withdraw', account) }, icon('out'), 'Withdraw'),
            el('button', { class: 'btn', type: 'button', disabled: !account.can.deposit, onclick: () => atmAction('deposit', account) }, icon('in'), 'Deposit')));
}

function renderAtm() {
    const account = findAccount(ui.atm.number);
    return el('div', { class: 'atm' },
        el('div', { class: 'atm-top' }, brandBlock('ATM'), el('button', { class: 'icon-btn', type: 'button', title: 'Exit', onclick: close }, icon('close'))),
        el('div', { class: 'atm-screen' },
            account ? atmAmount(account) : atmPick(),
            ui.atm.loader ? el('div', { class: 'atm-busy' }, ui.atm.loader.node) : null),
        el('div', { class: 'atm-foot' }, el('span', { text: ui.state.place }), el('span', { text: `CASH ${money(ui.state.cash)}` })));
}

// ---------------------------------------------------------------------------
// Admin: placement bar and branch name prompt
// ---------------------------------------------------------------------------

function legend(key, label) {
    return el('span', {}, el('kbd', { text: key }), ` ${label}`);
}

function showPlacement(data) {
    placementNode.hidden = false;
    const hint = data.hint || (data.kind === 'ATM' ? 'Aim at an ATM until it lights up' : 'Aim at the counter');
    setChildren(placementNode,
        el('div', {}, el('small', { text: 'PLACEMENT' }), el('strong', { text: `${data.kind} (${data.index}/${data.total})` })),
        el('div', { class: 'legend' },
            legend('← →', 'switch'), legend('Click', 'place'), legend('Wheel', 'rotate'), legend('Del', 'remove'), legend('Backspace', 'done')),
        el('span', { class: 'note', style: 'margin:0', text: hint }));
}

function askLabel() {
    const value = { text: '' };
    const finish = (text) => {
        ui.promptFinish = null;
        promptNode.hidden = true;
        setChildren(promptNode);
        post('label', { text });
    };
    ui.promptFinish = finish;
    const input = el('input', { class: 'input', type: 'text', maxlength: '30', placeholder: 'e.g. Fleeca Vespucci', oninput: (event) => { value.text = event.target.value; } });
    const submit = (event) => {
        event.preventDefault();
        if (!value.text.trim()) return toast('Type a name', false);
        finish(value.text.trim());
    };
    promptNode.hidden = false;
    setChildren(promptNode, el('form', { class: 'sheet', onsubmit: submit },
        el('h3', { text: 'Name this branch' }),
        el('p', { text: 'Shown above the counter.' }),
        input,
        el('div', { class: 'sheet-actions' },
            el('button', { class: 'btn', type: 'button', onclick: () => finish(null) }, 'Cancel'),
            el('button', { class: 'btn is-primary', type: 'submit' }, 'Save'))));
    input.focus();
}

// ---------------------------------------------------------------------------
// Messages from the game
// ---------------------------------------------------------------------------

function applyBrand(brand) {
    if (!brand) return;
    ui.brand = { ...ui.brand, ...brand };
    const hex = /^#([0-9a-f]{6})$/i.exec(brand.Accent || '');
    if (!hex) return;
    const n = parseInt(hex[1], 16);
    const rgb = `${n >> 16}, ${(n >> 8) & 255}, ${n & 255}`;
    const root = document.documentElement.style;
    root.setProperty('--accent', brand.Accent);
    root.setProperty('--accent-soft', `rgba(${rgb}, 0.16)`);
    root.setProperty('--accent-line', `rgba(${rgb}, 0.5)`);
}

function resetUi() {
    ui.view = 'dashboard';
    ui.number = null;
    ui.sheet = null;
    ui.opened = null;
    ui.history = [];
    ui.renderedView = null;
    resetAtm();
}

function showApp() {
    appNode.hidden = false;
    appNode.classList.remove('is-closing');
}

function hideApp() {
    if (ui.loader) { ui.loader.stop(); ui.loader = null; }
    appNode.classList.add('is-closing');
    setTimeout(() => {
        appNode.hidden = true;
        appNode.classList.remove('is-closing');
        setChildren(appNode);
        ui.state = null;
    }, CLOSE_MS);
}

/** The server answered: run the loader to 100%, then show the bank / ATM. */
async function onOpen(state) {
    const loader = ui.loader;
    if (loader) await loader.finish();
    if (loader !== ui.loader) return; // closed or re-opened meanwhile
    ui.loader = null;
    resetUi();
    ui.state = state;
    render();
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    switch (data.action) {
        case 'loading':
            showApp();
            if (ui.loader) ui.loader.stop();
            ui.loader = makeLoader('Connecting to Vanguard Bank');
            setChildren(appNode, ui.loader.node);
            break;
        case 'open': applyBrand(data.brand); onOpen(data.state); break;
        case 'state': ui.state = data.state; render(); break;
        case 'close': hideApp(); break;
        case 'placement': showPlacement(data); break;
        case 'placementEnd': placementNode.hidden = true; break;
        case 'askLabel': askLabel(); break;
        default: break;
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (ui.promptFinish) return ui.promptFinish(null);
    if (ui.sheet) return closeSheet();
    if (!appNode.hidden && ui.state) close();
});

// ---------------------------------------------------------------------------
// Browser preview (sample data; does nothing in-game)
// ---------------------------------------------------------------------------

const ALL = { deposit: true, withdraw: true, transfer: true, manage: true };
const USE = { deposit: true, withdraw: true, transfer: true, manage: false };
const NOW = Math.floor(Date.now() / 1000);
const PREVIEW_STATE = {
    mode: 'branch', place: 'Fleeca Legion Square', name: 'Rover Dev', cash: 2350, owned: 2, maxOwned: 3,
    maxAmount: 10000000, quick: [100, 500, 1000, 5000], historyPage: 50,
    accounts: [
        { number: 'VB-4821-0397', type: 'personal', name: 'Personal', balance: 48250, role: 'holder', can: USE },
        { number: 'VB-1180-7724', type: 'savings', name: 'Rainy day', balance: 12000, role: 'owner', can: ALL },
        { number: 'VB-5532-1049', type: 'shared', name: 'Crew fund', balance: 3400, role: 'owner', can: ALL },
        { number: 'VB-9071-2280', type: 'business', name: 'Cat Cafe', balance: 8900, role: 'boss', can: USE },
        { number: 'VB-3305-6618', type: 'job', name: 'Los Santos Police', balance: 250000, role: 'boss', can: USE },
    ],
};
const PREVIEW_HISTORY = [
    { id: 9, kind: 'income', amount: 3300, actor: null, note: 'vanguard-jobs delivery', time: NOW - 1800 },
    { id: 8, kind: 'transfer_out', amount: -1200, actor: 'Rover Dev', note: 'To VB-5532-1049 - Crew dinner', time: NOW - 7200 },
    { id: 7, kind: 'deposit', amount: 5000, actor: 'Rover Dev', note: 'Fleeca Legion Square', time: NOW - 9000 },
    { id: 6, kind: 'payment', amount: -350, actor: null, note: 'qb-shops 24/7', time: NOW - 90000 },
    { id: 5, kind: 'transfer_in', amount: 2500, actor: 'Mia Tanaka', note: 'From VB-7702-4415 - rent', time: NOW - 95000 },
    { id: 4, kind: 'withdraw', amount: -800, actor: 'Rover Dev', note: 'ATM', time: NOW - 200000 },
    { id: 3, kind: 'system', amount: 0, actor: 'Rover Dev', note: 'Account opened', time: NOW - 400000 },
];
const PREVIEW_MEMBERS = [
    { citizenid: 'ABC123', name: 'Mia Tanaka', role: 'member' },
    { citizenid: 'XYZ789', name: 'Sam Rivera', role: 'viewer' },
];

const Preview = {
    state() { return JSON.parse(JSON.stringify(PREVIEW_STATE)); },
    respond(endpoint, data) {
        if (endpoint === 'close' || endpoint === 'label') { hideApp(); return Promise.resolve({}); }
        const action = data.action;
        const replies = {
            open: { ok: true, data: Object.assign(Preview.state(), { mode: ui.state ? ui.state.mode : 'branch' }) },
            history: { ok: true, data: { rows: PREVIEW_HISTORY } },
            lookup: { ok: true, data: { number: 'VB-7702-4415', label: 'Mia Tanaka - Personal' } },
            members: { ok: true, data: { members: PREVIEW_MEMBERS } },
            openAccount: { ok: true, message: 'Account opened', data: { number: 'VB-6604-3318', name: (data.data && data.data.name) || 'Rainy day', type: 'savings' } },
        };
        return Promise.resolve(replies[action] || { ok: true, message: `(preview) ${action}` });
    },
    start() {
        document.body.classList.add('is-preview');
        const page = (location.hash || '#bank').slice(1);
        showApp();
        resetUi();
        ui.state = Preview.state();
        Preview.show(page);
    },
    show(page) {
        const shared = 'VB-5532-1049';
        if (page === 'loading') { ui.loader = makeLoader('Connecting to Vanguard Bank'); return setChildren(appNode, ui.loader.node); }
        if (page === 'atm' || page === 'atmpick') {
            ui.state.mode = 'atm';
            ui.state.place = 'ATM';
            if (page === 'atm') { resetAtm('VB-4821-0397'); ui.atm.amount = '2500'; }
            return render();
        }
        if (page === 'placement') { appNode.hidden = true; return showPlacement({ kind: 'ATM', index: 2, total: 2 }); }
        if (page === 'label') { appNode.hidden = true; return askLabel(); }
        if (page === 'account' || page === 'deposit') {
            go('account', shared);
            if (page === 'deposit') { ui.sheet = { kind: 'deposit', number: shared, value: '1500' }; render(); }
            return undefined;
        }
        if (page === 'transfer' || page === 'confirm') {
            go('transfer', 'VB-4821-0397');
            Object.assign(ui.transfer, { to: 'VB-7702-4415', amount: '2500', note: 'Rent', receiver: { number: 'VB-7702-4415', label: 'Mia Tanaka - Personal' } });
            if (page === 'confirm') ui.sheet = { kind: 'transfer', number: 'VB-4821-0397' };
            return render();
        }
        if (page === 'open' || page === 'name') {
            go('open');
            if (page === 'name') { ui.wizard = { step: 2, type: 'savings', name: 'New car' }; render(); }
            return undefined;
        }
        if (page === 'opened') { go('open'); ui.opened = { number: 'VB-6604-3318', name: 'New car', type: 'savings' }; return render(); }
        if (page === 'members') return go('members', shared);
        return go('dashboard');
    },
};

if (!IS_GAME) {
    Preview.start();
    window.addEventListener('hashchange', () => Preview.start());
}
