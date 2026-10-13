// Unit tests for the pure helpers in js/status.js.
//
//   ./dev.sh test            (qmltestrunner over contents/tests)
//
// They need no display and no plasmoid host: status.js takes plain values and
// returns plain values, which is exactly what makes it worth testing here.
import QtQuick
import QtTest

import "../js/status.js" as Status

TestCase {
    name: "StatusHelpers"

    function test_counts() {
        const counts = { PENDING: 2, COMPLETED: 3670, FAILED: 0 };
        compare(Status.count(counts, "PENDING"), 2);
        compare(Status.count(counts, "MISSING"), 0, "an absent stage reads as zero");
        compare(Status.count(counts, "FAILED"), 0);
        compare(Status.count(null, "PENDING"), 0, "no map reads as zero");
        compare(Status.count({ PENDING: "3" }, "PENDING"), 3, "string counts are accepted");
        compare(Status.count({ PENDING: "nonsense" }, "PENDING"), 0, "garbage reads as zero");
    }

    function test_rollupAndInProgress() {
        const counts = { PENDING: 2, DOWNLOADED: 1, TG_UPLOADED: 2, FAILED: 4, COMPLETED: 10 };
        compare(Status.rollup(counts, ["PENDING", "COMPLETED"]), 12);
        compare(Status.rollup(counts, []), 0);
        // Only the stages between PENDING and the final states count as in flight.
        compare(Status.inProgressCount(counts), 3, "PENDING and terminal stages are excluded");
        compare(Status.inProgressCount(null), 0);
    }

    function test_durationParts() {
        const long = Status.durationParts(((1 * 24) + 2) * 3600000 + 3 * 60000);
        compare(JSON.stringify(long),
                JSON.stringify({ expired: false, days: 1, hours: 2, minutes: 3, seconds: 0 }));

        compare(Status.durationParts(0).expired, true, "the deadline itself is expired");
        compare(Status.durationParts(-1000).expired, true, "the past is expired");
        compare(Status.durationParts(59000).expired, false, "59 s is still in the future");
        compare(Status.durationParts(59000).seconds, 59);
        compare(Status.durationParts(NaN), null);
        compare(Status.durationParts(undefined), null);
    }

    function test_compact() {
        const minutes = (m) => m * 60000;
        const hours = (h) => h * 3600000;
        compare(Status.compact(hours(29) + minutes(23)), "1d 5h");
        compare(Status.compact(hours(3) + minutes(12)), "3h 12m");
        compare(Status.compact(minutes(12)), "12m");
        compare(Status.compact(45000), "45s");
        compare(Status.compact(0), "", "an expired duration has no label");
        compare(Status.compact(-5), "");
        compare(Status.compact(NaN), "");
    }

    function test_parseIso() {
        compare(Status.parseIso(null), null);
        compare(Status.parseIso(""), null);
        compare(Status.parseIso("not a date"), null);
        compare(Status.parseIso("2026-10-13T12:00:00Z").toISOString(), "2026-10-13T12:00:00.000Z");
        // The API reports microseconds and a +00:00 offset, not a Z suffix.
        compare(Status.parseIso("2026-10-12T07:13:20.364877+00:00").toISOString(),
                "2026-10-12T07:13:20.364Z");
        compare(Status.parseIso("2026-10-12T09:11:58+02:00").toISOString(),
                "2026-10-12T07:11:58.000Z");
    }

    function test_sinceAndUntil() {
        const now = Status.parseIso("2026-10-13T12:00:00Z").getTime();
        compare(Status.sinceText("2026-10-13T09:00:00Z", now), "3h 0m");
        compare(Status.untilText("2026-10-13T12:15:00Z", now), "15m");
        compare(Status.sinceText("2026-10-13T13:00:00Z", now), "", "a future start has no elapsed label");
        compare(Status.untilText("2026-10-13T11:00:00Z", now), "", "an elapsed deadline has no countdown");
        compare(Status.sinceText("not a date", now), "");
        compare(Status.sinceText(null, now), "");
    }

    function test_gigabytesAndFraction() {
        compare(Status.gigabytes(121770250240), 113.4);
        compare(Status.gigabytes(0), 0);
        compare(Status.gigabytes(-1), null, "a negative size is not a size");
        compare(Status.gigabytes(null), null);
        compare(Status.gigabytes("nonsense"), null);
        compare(Status.usedFraction(50, 100), 0.5);
        compare(Status.usedFraction(50, 0), 0, "a zero total cannot be a share");
        compare(Status.usedFraction(150, 100), 1, "clamped above");
        compare(Status.usedFraction(-5, 100), 0, "clamped below");
    }

    function test_stateCode() {
        const up = { installed: true, active: true };
        const worker = { running: true, lastRunError: null };
        const quiet = { FAILED: 0, PENDING: 2 };

        compare(Status.stateCode(up, worker, quiet, ""), "ok");
        compare(Status.stateCode({ installed: false, active: false }, null, quiet, ""), "missing");
        compare(Status.stateCode({ installed: true, active: false }, null, quiet, ""), "down");
        compare(Status.stateCode(up, worker, quiet, "network"), "degraded");
        compare(Status.stateCode(up, worker, { FAILED: 3 }, ""), "attention");
        compare(Status.stateCode(up, { running: false, lastRunError: "boom" }, quiet, ""), "attention");
        compare(Status.stateCode(null, null, null, ""), "missing", "no service block means no unit");

        compare(Status.needsAttention("ok"), false);
        compare(Status.needsAttention("attention"), true);
        compare(Status.needsAttention("degraded"), true);
        compare(Status.needsAttention("down"), true);
        compare(Status.needsAttention("missing"), true);
    }
}
