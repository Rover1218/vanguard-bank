// Runs every tests/*_spec.lua against the shared Lua files. Usage: npm test
'use strict';

const fs = require('fs');
const path = require('path');
const { createState, run } = require('../tools/lua');

const L = createState();
const specs = fs.readdirSync(__dirname).filter((file) => file.endsWith('_spec.lua')).sort();

try {
    for (const spec of specs) run(L, fs.readFileSync(path.join(__dirname, spec), 'utf8'), spec);
    const summary = run(L, `local T = require('tests.lib.t'); return T.summary()`, 'summary');
    console.log(summary);
    process.exit(summary.includes(' 0 failed') ? 0 : 1);
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
