// Loader progress maths (html/progress.js). Usage: node tests/progress.test.js
'use strict';

const assert = require('assert');
const Progress = require('../html/progress.js');

// waiting: starts at 0, climbs, never reaches the end on its own
assert.strictEqual(Progress.waiting(0), 0);
assert.strictEqual(Progress.waiting(-50), 0, 'clock skew never goes below 0');
let previous = 0;
for (let ms = 100; ms <= 20000; ms += 100) {
    const value = Progress.waiting(ms);
    assert.ok(value > previous, `climbs at ${ms} ms`);
    assert.ok(value < 90, `stays below 90 while waiting (${value} at ${ms} ms)`);
    previous = value;
}
const atSixHundred = Progress.waiting(600);
assert.ok(atSixHundred > 40 && atSixHundred < 50, `about 45% after 600 ms, got ${atSixHundred}`);

// finishing: runs from where it was to exactly 100
assert.strictEqual(Progress.finishing(50, 0), 50);
assert.strictEqual(Progress.finishing(50, Progress.FINISH_MS / 2), 75);
assert.strictEqual(Progress.finishing(50, Progress.FINISH_MS), 100);
assert.strictEqual(Progress.finishing(50, Progress.FINISH_MS * 10), 100, 'never past 100');

// spin: one full turn per SPIN_MS
assert.strictEqual(Progress.spin(0), 0);
assert.strictEqual(Progress.spin(Progress.SPIN_MS / 2), 180);
assert.strictEqual(Progress.spin(Progress.SPIN_MS), 0);

process.stdout.write('progress ok\n');
