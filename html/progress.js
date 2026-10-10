/* Vanguard Bank - loader progress maths (pure; tested in tests/progress.test.js).
   Driven from JavaScript, not CSS, so it still moves when Windows animations are turned off
   (Chromium then reports "reduce motion" and switches CSS animations off). */
'use strict';

const Progress = {
    WAIT_CAP: 90,       // waiting for the server climbs towards this, never past it
    WAIT_RATE_MS: 900,  // how quickly it climbs (about 45% after 600 ms)
    FINISH_MS: 320,     // last stretch to 100% once the server answered
    SPIN_MS: 1100,      // one full turn of the spinner

    /** Percent shown while waiting: 0 at the start, rising towards WAIT_CAP. */
    waiting(elapsedMs) {
        const t = Math.max(0, elapsedMs);
        return Progress.WAIT_CAP * (1 - Math.exp(-t / Progress.WAIT_RATE_MS));
    },

    /** Percent shown after the answer came: from `from` to exactly 100 over FINISH_MS. */
    finishing(from, sinceMs) {
        const t = Math.min(1, Math.max(0, sinceMs) / Progress.FINISH_MS);
        return t >= 1 ? 100 : from + (100 - from) * t;
    },

    /** Spinner angle in degrees. */
    spin(elapsedMs) {
        return ((Math.max(0, elapsedMs) / Progress.SPIN_MS) * 360) % 360;
    },
};

if (typeof module !== 'undefined') module.exports = Progress;
