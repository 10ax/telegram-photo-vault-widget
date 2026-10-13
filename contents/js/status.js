// Pure derivation helpers for the Telegram Photo Vault plasmoid.
//
// Nothing here touches i18n, Plasmoid or the theme: the QML side reads the
// settings and the helper JSON and passes plain values in. That keeps every
// binding that calls into this file dependency-tracked, and keeps the
// arithmetic testable on its own (see tests/tst_status.qml).
.pragma library

// Photo pipeline stages that mean "work in flight right now". They drain as
// items advance, so their sum is a live snapshot rather than a running total.
var inProgressStages = ["DOWNLOADED", "CHUNK_UPLOADING", "TG_UPLOADED", "COMPRESSED", "ODROID_UPLOADED"];

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function number(value) {
    const parsed = Number(value);
    return isFinite(parsed) ? parsed : 0;
}

// One stage's count, 0 for a missing or malformed map.
function count(counts, key) {
    if (!counts) {
        return 0;
    }
    return number(counts[key]);
}

// Sum of several stage counts.
function rollup(counts, keys) {
    let total = 0;
    for (const key of keys) {
        total += count(counts, key);
    }
    return total;
}

function inProgressCount(counts) {
    return rollup(counts, inProgressStages);
}

// Parse an ISO timestamp, returning null for anything unusable.
function parseIso(iso) {
    if (!iso) {
        return null;
    }
    // The API emits microsecond precision ("…:20.364877+00:00"). Not every JS
    // engine accepts more than three fractional digits, so trim the rest.
    const text = String(iso).replace(/(\.\d{3})\d+/, "$1");
    const date = new Date(text);
    return isNaN(date.getTime()) ? null : date;
}

// Split a duration into whole days, hours, minutes and seconds. `expired` is
// true when the moment is already behind us; null when the input is not a
// number.
function durationParts(ms) {
    const value = Number(ms);
    if (!isFinite(value)) {
        return null;
    }
    if (value <= 0) {
        return { expired: true, days: 0, hours: 0, minutes: 0, seconds: 0 };
    }
    const totalSeconds = Math.floor(value / 1000);
    return {
        expired: false,
        days: Math.floor(totalSeconds / 86400),
        hours: Math.floor((totalSeconds % 86400) / 3600),
        minutes: Math.floor((totalSeconds % 3600) / 60),
        seconds: totalSeconds % 60
    };
}

// A short, language-neutral duration label: "1d 2h", "3h 12m", "12m", "45s".
// The QML side wraps it in translated text ("running 3h 12m").
function compact(ms) {
    const parts = durationParts(ms);
    if (parts === null) {
        return "";
    }
    if (parts.expired) {
        return "";
    }
    if (parts.days > 0) {
        return parts.days + "d " + parts.hours + "h";
    }
    if (parts.hours > 0) {
        return parts.hours + "h " + parts.minutes + "m";
    }
    if (parts.minutes > 0) {
        return parts.minutes + "m";
    }
    return parts.seconds + "s";
}

// How much time has passed since an ISO timestamp, as a compact label. Empty
// when the timestamp is unusable or in the future.
function sinceText(iso, nowMs) {
    const date = parseIso(iso);
    if (date === null) {
        return "";
    }
    return compact(nowMs - date.getTime());
}

// Time left until an ISO timestamp, as a compact label. Empty when the
// timestamp is unusable or already behind us.
function untilText(iso, nowMs) {
    const date = parseIso(iso);
    if (date === null) {
        return "";
    }
    return compact(date.getTime() - nowMs);
}

// Bytes to GB with one decimal, or null when the value is not a number.
function gigabytes(bytes) {
    // Number(null) and Number("") are 0, which would read as "0 GB free".
    if (bytes === null || bytes === undefined || bytes === "") {
        return null;
    }
    const value = Number(bytes);
    if (!isFinite(value) || value < 0) {
        return null;
    }
    return Math.round((value / 1073741824) * 10) / 10;
}

// Share used, 0..1, from a pair of byte counts.
function usedFraction(used, total) {
    const usedBytes = Number(used);
    const totalBytes = Number(total);
    if (!isFinite(usedBytes) || !isFinite(totalBytes) || totalBytes <= 0) {
        return 0;
    }
    return clamp(usedBytes / totalBytes, 0, 1);
}

// The single state code the tray indicator and tooltip speak from.
//
// "missing"   the unit is not installed at all
// "down"      the service is stopped (or failed)
// "degraded"  running, but the API did not answer (counts came from the DB)
// "attention" running, but something needs the user: failed items or a failed
//             worker run
// "ok"        everything answered and nothing is wrong
function stateCode(service, worker, photos, error) {
    if (!service || service.installed === false) {
        return "missing";
    }
    if (!service.active) {
        return "down";
    }
    if (error) {
        return "degraded";
    }
    if (count(photos, "FAILED") > 0) {
        return "attention";
    }
    if (worker && worker.lastRunError) {
        return "attention";
    }
    return "ok";
}

// Whether the state is one the user has to look at (drives the tray dot and
// the tooltip wording, never colour alone).
function needsAttention(code) {
    return code === "attention" || code === "down" || code === "missing" || code === "degraded";
}
