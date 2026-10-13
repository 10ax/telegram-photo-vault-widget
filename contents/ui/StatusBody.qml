pragma ComponentBehavior: Bound

// The popup body: header, controls, the data rows, the notes and the footer.
// It owns the presentation and the i18n text; every value it shows is passed
// in by main.qml, which owns the polling state.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../js/status.js" as Status

ColumnLayout {
    id: body

    required property var service
    required property var photos
    required property var worker
    required property var recovery
    required property var system
    required property string source
    required property string stateText
    required property bool hasData
    required property string errorText
    required property string actionMessage
    required property string actionError
    required property string refreshText
    required property url dashboardUrl
    required property int smallPointSize
    required property double nowMs
    required property bool serviceActive
    required property bool stopArmed
    required property bool confirmStop
    required property bool actionsEnabled
    required property bool showUploadsRow
    required property bool showWorkerRow
    required property bool showRecoveryRow
    required property bool showDiskRow
    required property bool showFooter

    signal startRequested()
    signal stopRequested()
    signal restartRequested()
    signal runRequested()
    signal dashboardRequested()
    signal refreshRequested()

    spacing: Kirigami.Units.largeSpacing

    readonly property var floorGb: Status.gigabytes(body.recovery && body.recovery.disk
        ? body.recovery.disk.minFreeBytes : null)
    readonly property bool belowFloor: !!(body.recovery && body.recovery.disk && body.recovery.disk.belowFloor)

    readonly property color stateColor: {
        switch (Status.stateCode(body.service, body.worker, body.photos, body.errorText)) {
        case "ok":
            return Kirigami.Theme.positiveTextColor;
        case "attention":
            return Kirigami.Theme.negativeTextColor;
        case "degraded":
            return Kirigami.Theme.neutralTextColor;
        default:
            return Kirigami.Theme.disabledTextColor;
        }
    }

    // The one line under the controls that explains a degraded state: a real
    // error when there is one, otherwise just why the worker row is empty.
    readonly property string noteText: {
        if (body.errorText) {
            return body.errorText;
        }
        if (!body.hasData) {
            return "";
        }
        if (body.service && body.service.installed === false) {
            return i18n("No systemd user unit found for this service.");
        }
        if (!body.serviceActive) {
            return i18n("Service is stopped — upload counts are read from the database.");
        }
        return "";
    }
    readonly property color noteColor: body.errorText
        ? Kirigami.Theme.negativeTextColor
        : Kirigami.Theme.neutralTextColor

    function serviceDetail() {
        const details = [];
        const state = body.service;
        if (!state) {
            return "";
        }
        const since = Status.sinceText(state.since, body.nowMs);
        if (state.active && since) {
            details.push(i18n("up %1", since));
        }
        details.push(state.enabled ? i18n("starts at boot") : i18n("manual start only"));
        const restarts = Status.number(state.restarts);
        if (restarts > 0) {
            details.push(i18np("%1 restart", "%1 restarts", restarts));
        }
        return details.join(" · ");
    }

    function intervalText() {
        const seconds = body.worker ? Status.number(body.worker.runIntervalSeconds) : 0;
        return seconds > 0 ? Math.round(seconds / 60) : 0;
    }

    function workerValue() {
        if (!body.worker) {
            return i18n("Unknown");
        }
        return body.worker.running ? i18n("Running") : i18n("Idle");
    }

    function workerSubText() {
        if (!body.worker) {
            return body.serviceActive
                ? i18n("The service did not report a worker.")
                : i18n("Service is not running.");
        }
        const parts = [];
        if (body.worker.running) {
            const since = Status.sinceText(body.worker.lastRunStartedAt, body.nowMs);
            parts.push(since ? i18n("started %1 ago", since) : i18n("running now"));
        } else {
            const until = Status.untilText(body.worker.nextRunAt, body.nowMs);
            parts.push(until ? i18n("next run in %1", until) : i18n("waiting for the next interval"));
        }
        const minutes = body.intervalText();
        if (minutes > 0) {
            parts.push(i18n("every %1 min", minutes));
        }
        return parts.join(" · ");
    }

    function recoveryValue() {
        if (!body.recovery) {
            return i18n("Unknown");
        }
        if (body.recovery.running) {
            return body.recovery.activity || i18n("Working");
        }
        return i18n("Idle");
    }

    function recoverySubText() {
        if (!body.recovery) {
            return body.serviceActive ? "" : i18n("Service is not running.");
        }
        const batch = body.recovery.batch;
        if (batch) {
            const processed = Status.number(batch.processed);
            const total = Status.number(batch.total);
            const captioned = Status.number(batch.captioned);
            const deferred = Status.number(batch.deferred);
            return body.recovery.running
                ? i18n("Running — batch %1/%2 · captioned %3 · deferred %4",
                       processed, total, captioned, deferred)
                : i18n("Last batch %1/%2 · captioned %3 · deferred %4",
                       processed, total, captioned, deferred);
        }
        const items = body.recovery.items;
        if (items) {
            return i18n("%1 tidied · %2 skipped",
                        Status.count(items, "COMPLETED"), Status.count(items, "SKIPPED"));
        }
        return "";
    }

    function diskValue() {
        if (!body.system) {
            return i18n("Unknown");
        }
        const free = Status.gigabytes(body.system.freeBytes);
        return free === null ? i18n("Unknown") : i18n("%1 GB free", free);
    }

    function diskSubText() {
        if (!body.system) {
            return "";
        }
        if (body.belowFloor) {
            return i18n("Below the %1 GB floor — tidy downloads are paused", body.floorGb);
        }
        if (body.floorGb !== null) {
            return i18n("%1% used · tidy download floor %2 GB",
                        Status.number(body.system.usedPercent), body.floorGb);
        }
        return i18n("%1% used", Status.number(body.system.usedPercent));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: i18n("Photo Vault")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            Layout.alignment: Qt.AlignBaseline
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            text: body.stateText
            color: body.stateColor
            elide: Text.ElideRight
        }

        PlasmaComponents3.Button {
            text: i18n("Dashboard")
            // Flat, so the header is not dominated by a boxed control twice as
            // tall as the text next to it.
            flat: true
            onClicked: body.dashboardRequested()
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: body.serviceDetail()
        font.pointSize: body.smallPointSize
        opacity: 0.6
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        visible: body.actionsEnabled
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            Layout.fillWidth: true
            text: body.serviceActive
                ? (body.stopArmed && body.confirmStop ? i18n("Confirm stop") : i18n("Stop"))
                : i18n("Start")
            icon.name: body.serviceActive ? "media-playback-stop-symbolic" : "media-playback-start-symbolic"
            onClicked: body.serviceActive ? body.stopRequested() : body.startRequested()
        }

        PlasmaComponents3.Button {
            icon.name: "system-reboot-symbolic"
            enabled: body.serviceActive
            display: QQC2.AbstractButton.IconOnly
            onClicked: body.restartRequested()

            QQC2.ToolTip.text: i18n("Restart the service")
            QQC2.ToolTip.visible: hovered
        }

        PlasmaComponents3.Button {
            icon.name: "media-record-symbolic"
            enabled: body.serviceActive
            display: QQC2.AbstractButton.IconOnly
            onClicked: body.runRequested()

            QQC2.ToolTip.text: i18n("Run the worker now")
            QQC2.ToolTip.visible: hovered
        }
    }

    // The result of the last action, and whatever is wrong right now.
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        visible: body.actionError.length > 0 || body.actionMessage.length > 0
        text: body.actionError.length > 0 ? body.actionError : body.actionMessage
        color: body.actionError.length > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        font.pointSize: body.smallPointSize
        opacity: body.actionError.length > 0 ? 1 : 0.7
        wrapMode: Text.WordWrap
    }

    PlasmaExtras.PlaceholderMessage {
        Layout.fillWidth: true
        visible: !body.hasData
        iconName: "cloud-upload-symbolic"
        text: body.errorText || i18n("Loading…")
        explanation: i18n("Reads the service state from systemd and the upload counts from the vault API.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        // Wider than the gap inside one row, so the rows read as groups.
        spacing: Math.round(Kirigami.Units.gridUnit * 0.75)
        visible: body.hasData

        StatRow {
            visible: body.showUploadsRow
            label: i18n("Uploads")
            value: i18n("%1 pending", Status.count(body.photos, "PENDING"))
            subText: i18n("%1 in progress · %2 failed",
                          Status.inProgressCount(body.photos),
                          Status.count(body.photos, "FAILED"))
            valueColor: Status.count(body.photos, "FAILED") > 0
                ? Kirigami.Theme.negativeTextColor
                : Kirigami.Theme.textColor
            smallPointSize: body.smallPointSize
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: body.showWorkerRow

            StatRow {
                label: i18n("Worker")
                value: body.workerValue()
                subText: body.workerSubText()
                smallPointSize: body.smallPointSize
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 6 + Kirigami.Units.smallSpacing
                visible: !!(body.worker && body.worker.lastRunError)
                text: i18n("Last run failed — see the dashboard for the traceback.")
                color: Kirigami.Theme.negativeTextColor
                font.pointSize: body.smallPointSize
                elide: Text.ElideRight
            }
        }

        StatRow {
            visible: body.showRecoveryRow
            label: i18n("Tidy")
            value: body.recoveryValue()
            subText: body.recoverySubText()
            smallPointSize: body.smallPointSize
        }

        StatRow {
            visible: body.showDiskRow
            label: i18n("Disk")
            value: body.diskValue()
            subText: body.diskSubText()
            valueColor: body.belowFloor ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            smallPointSize: body.smallPointSize
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        visible: body.noteText.length > 0
        text: body.noteText
        color: body.noteColor
        font.pointSize: body.smallPointSize
        wrapMode: Text.WordWrap
    }

    // The system tray gives its popup a fixed size, and Qt Quick's layouts pour
    // the leftover height into the gaps *between* children. This spacer takes
    // all of the slack instead, so the rows keep their spacing and the footer
    // stays at the bottom. It collapses to zero in a content-sized host.
    Item {
        Layout.fillHeight: true
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: body.showFooter && body.hasData
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: body.showFooter && body.hasData
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: i18n("Updated %1", Qt.formatTime(new Date(body.nowMs), "HH:mm"))
            font.pointSize: body.smallPointSize
            opacity: 0.6
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            text: body.refreshText
            font.pointSize: body.smallPointSize
            opacity: 0.6
        }
    }
}
