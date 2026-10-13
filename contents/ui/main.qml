pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

import "../js/status.js" as Status

PlasmoidItem {
    id: root

    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/telegram-photo-vaultctl")).replace(/^file:\/\//, ""))

    readonly property string dashboardUrl: "http://localhost:8100/"

    readonly property int pollIntervalMs: Math.max(10, Math.min(3600,
        Number(Plasmoid.configuration.pollIntervalSeconds) || 30)) * 1000

    // Populated from the helper JSON. On a failed check the last good values
    // stay put on purpose and errorText explains what went wrong.
    property var service: null
    property var photos: null
    property var worker: null
    property var recovery: null
    property var system: null
    property string source: ""
    property bool hasData: false
    property string errorText: ""

    // Result of the last start/stop/restart/run action, shown in the popup.
    property string actionMessage: ""
    property string actionError: ""

    // Ticked every second so "started 29h 23m ago" and the refresh countdown
    // stay live between checks.
    property double nowMs: Date.now()
    property double nextPollMs: 0

    // Armed by the first click on Stop, cleared by the second or by a timeout.
    property bool stopArmed: false

    readonly property bool serviceActive: !!(root.service && root.service.active)
    readonly property string stateCode: Status.stateCode(root.service, root.worker, root.photos, root.errorText)

    readonly property string stateText: {
        switch (root.stateCode) {
        case "ok":
            return i18n("Running");
        case "degraded":
            return i18n("Running — no live data");
        case "attention":
            return i18n("Needs attention");
        case "down":
            return i18n("Stopped");
        default:
            return i18n("Not installed");
        }
    }

    readonly property color stateColor: {
        switch (root.stateCode) {
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

    readonly property int pendingCount: Status.count(root.photos, "PENDING")
    readonly property int failedCount: Status.count(root.photos, "FAILED")

    // Validated on read: the config file is user-editable, so an unknown value
    // must not leave the widget with no state indicator at all.
    readonly property string trayIndicator: {
        const mode = Plasmoid.configuration.trayIndicator;
        return ["state-dot", "icon-swap", "none"].indexOf(mode) !== -1 ? mode : "state-dot";
    }

    // Only "icon-swap" changes the glyph; the other modes keep one icon so the
    // panel stays visually stable.
    readonly property string trayIcon: {
        if (root.trayIndicator === "icon-swap") {
            switch (root.stateCode) {
            case "attention":
                return "state-warning-symbolic";
            case "down":
            case "missing":
                return "state-offline-symbolic";
            default:
                return "cloud-upload-symbolic";
            }
        }
        return "cloud-upload-symbolic";
    }

    readonly property int smallPointSize: Math.max(6, Kirigami.Theme.defaultFont.pointSize - 1)

    readonly property string refreshCountdownText: i18n("Checking in %1s",
        Math.max(0, Math.ceil((root.nextPollMs - root.nowMs) / 1000)))

    readonly property string workerSummary: {
        if (!root.worker) {
            return root.serviceActive ? i18n("worker unknown") : "";
        }
        if (root.worker.running) {
            const since = Status.sinceText(root.worker.lastRunStartedAt, root.nowMs);
            return since ? i18n("working %1", since) : i18n("working now");
        }
        const until = Status.untilText(root.worker.nextRunAt, root.nowMs);
        return until ? i18n("next run in %1", until) : i18n("worker idle");
    }

    Plasmoid.icon: root.trayIcon
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.title: i18n("Telegram Photo Vault")

    toolTipMainText: Plasmoid.title
    toolTipSubText: {
        if (!root.hasData) {
            return root.errorText || i18n("Loading…");
        }
        const parts = [root.stateText, i18n("%1 pending", root.pendingCount)];
        if (root.failedCount > 0) {
            parts.push(i18n("%1 failed", root.failedCount));
        }
        if (root.workerSummary) {
            parts.push(root.workerSummary);
        }
        return parts.join(" · ");
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function refresh() {
        root.nowMs = Date.now();
        root.nextPollMs = root.nowMs + root.pollIntervalMs;
        // The trailing comment is a cheap cache-buster: the executable engine
        // treats every distinct source string as a new request.
        statusEngine.connectSource(shellQuote(root.helperPath) + " json # " + Date.now());
    }

    function runAction(command) {
        root.actionMessage = "";
        root.actionError = "";
        actionEngine.connectSource(shellQuote(root.helperPath) + " " + command + " # " + Date.now());
    }

    // Start and stop share one button. Stopping can cut a chunk upload
    // mid-flight (it resumes on the next run), so with "confirmStop" on the
    // first click only arms the button.
    function toggleService() {
        if (root.serviceActive && Plasmoid.configuration.confirmStop && !root.stopArmed) {
            root.stopArmed = true;
            stopConfirmTimer.restart();
            return;
        }
        root.stopArmed = false;
        root.runAction(root.serviceActive ? "stop" : "start");
    }

    function errorMessageFor(code) {
        switch (code) {
        case "network":
            return i18n("The vault API did not answer on port 8100.");
        case "unauthorized":
            return i18n("The vault rejected the API key. Check API_KEY in the repository .env file.");
        case "not-configured":
            return i18n("The service has no API_KEY configured, so it refuses every request.");
        case "no-api-key":
            return i18n("No API_KEY in the repository .env file.");
        case "no-db":
            return i18n("The vault database could not be read.");
        case "bad-response":
            return i18n("The vault API answered with an unexpected response.");
        case "missing-jq":
            return i18n("Missing dependency: jq");
        case "":
            return "";
        default:
            return i18n("Status check failed (%1).", code);
        }
    }

    compactRepresentation: MouseArea {
        id: compactMouseArea

        // Only one tooltip here: the native applet one built from
        // toolTipMainText / toolTipSubText above. A QQC2.ToolTip on this
        // MouseArea would open a second, clipped bubble on top of it.

        // The tray hands us the panel's icon size as our height. With the text
        // off we ask for no width of our own, so the tray keeps giving us that
        // square slot; with it on we widen to fit the count.
        anchors.fill: parent
        implicitWidth: Plasmoid.configuration.showTrayText ? compactRow.implicitWidth : 0
        hoverEnabled: true

        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow

            anchors.centerIn: parent
            // Tighter than smallSpacing: the count should read as a caption on
            // the icon, not as a second tray entry.
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)

            Kirigami.Icon {
                id: iconItem

                source: root.trayIcon
                active: compactMouseArea.containsMouse
                // Square, and as large as the slot allows.
                implicitWidth: compactMouseArea.height > 0
                    ? compactMouseArea.height
                    : Kirigami.Units.iconSizes.medium
                implicitHeight: implicitWidth

                // State badge: the glyph is the same in every state, so the
                // state rides on a coloured dot anchored to the icon. Colour is
                // never the only carrier — the tooltip and the popup both say
                // the state in words.
                Rectangle {
                    readonly property real diameter: Math.max(6, Math.round(Math.min(parent.width, parent.height) * 0.35))

                    visible: root.trayIndicator === "state-dot"
                    width: diameter
                    height: diameter
                    radius: diameter / 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: root.stateColor
                    border.width: Math.max(1, Math.round(diameter * 0.15))
                    border.color: Kirigami.Theme.backgroundColor
                }
            }

            PlasmaComponents3.Label {
                visible: Plasmoid.configuration.showTrayText
                text: String(root.pendingCount)
                // Scaled to the slot the tray gives us: at the default font the
                // count is almost as tall as the panel icon and the row reads as
                // clutter (and crowds the neighbouring tray items in a vertical
                // panel). Dimmed, so the icon stays the subject.
                font.pixelSize: Math.max(8, Math.min(12, Math.round(compactMouseArea.height * 0.45)))
                opacity: 0.75
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: Kirigami.Units.gridUnit * 2
                elide: Text.ElideRight
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        // Exactly as tall as the content: minimumHeight stops a host from
        // clipping the last row, preferredHeight lets a content-sized host hug
        // it instead of leaving slack.
        Layout.minimumHeight: body.implicitHeight + topPadding + bottomPadding
        Layout.preferredHeight: body.implicitHeight + topPadding + bottomPadding
        collapseMarginsHint: true

        // Guarantee an even inset on every edge instead of relying on the
        // theme's dialog-background metrics.
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing

        contentItem: StatusBody {
            id: body

            service: root.service
            photos: root.photos
            worker: root.worker
            recovery: root.recovery
            system: root.system
            source: root.source
            stateText: root.stateText
            hasData: root.hasData
            errorText: root.errorText
            actionMessage: root.actionMessage
            actionError: root.actionError
            refreshText: root.refreshCountdownText
            dashboardUrl: root.dashboardUrl
            smallPointSize: root.smallPointSize
            nowMs: root.nowMs
            serviceActive: root.serviceActive
            stopArmed: root.stopArmed
            confirmStop: Plasmoid.configuration.confirmStop
            actionsEnabled: Plasmoid.configuration.actionsEnabled
            showUploadsRow: Plasmoid.configuration.showUploadsRow
            showWorkerRow: Plasmoid.configuration.showWorkerRow
            showRecoveryRow: Plasmoid.configuration.showRecoveryRow
            showDiskRow: Plasmoid.configuration.showDiskRow
            showFooter: Plasmoid.configuration.showFooter

            onStartRequested: root.runAction("start")
            onStopRequested: root.toggleService()
            onRestartRequested: root.runAction("restart")
            onRunRequested: root.runAction("run")
            onDashboardRequested: Qt.openUrlExternally(root.dashboardUrl)
            onRefreshRequested: root.refresh()
        }
    }

    PlasmaCore.Action {
        id: toggleAction
        text: root.serviceActive ? i18n("Stop Telegram Photo Vault") : i18n("Start Telegram Photo Vault")
        icon.name: root.serviceActive ? "media-playback-stop-symbolic" : "media-playback-start-symbolic"
        onTriggered: root.toggleService()
    }

    PlasmaCore.Action {
        id: restartAction
        text: i18n("Restart Telegram Photo Vault")
        icon.name: "system-reboot-symbolic"
        enabled: root.serviceActive
        onTriggered: root.runAction("restart")
    }

    PlasmaCore.Action {
        id: runNowAction
        text: i18n("Run the Worker Now")
        icon.name: "media-record-symbolic"
        enabled: root.serviceActive
        onTriggered: root.runAction("run")
    }

    PlasmaCore.Action {
        id: openDashboardAction
        text: i18n("Open the Dashboard")
        icon.name: "internet-services-symbolic"
        onTriggered: Qt.openUrlExternally(root.dashboardUrl)
    }

    PlasmaCore.Action {
        id: refreshAction
        text: i18n("Refresh Now")
        icon.name: "view-refresh-symbolic"
        onTriggered: root.refresh()
    }

    Plasmoid.contextualActions: [toggleAction, restartAction, runNowAction, openDashboardAction, refreshAction]

    P5Support.DataSource {
        id: statusEngine
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            statusEngine.disconnectSource(sourceName);

            const stdout = String(data.stdout || "").trim();
            let payload = null;
            try {
                payload = JSON.parse(stdout);
            } catch (error) {
                payload = null;
            }

            if (!payload || typeof payload !== "object" || !payload.ok) {
                // Keep the last good values on purpose.
                const code = payload && payload.error ? payload.error : "bad-output";
                root.errorText = root.errorMessageFor(code);
                return;
            }

            root.service = payload.service || null;
            root.photos = payload.photos || null;
            root.worker = payload.worker || null;
            root.recovery = payload.recovery || null;
            root.system = payload.system || null;
            root.source = payload.source || "";
            root.hasData = root.photos !== null || root.service !== null;
            root.errorText = root.errorMessageFor(payload.error || "");
        }
    }

    // Service actions go through their own engine so an action and a status
    // refresh can never be mistaken for one another.
    P5Support.DataSource {
        id: actionEngine
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            actionEngine.disconnectSource(sourceName);

            const stdout = String(data.stdout || "").trim();
            const stderr = String(data.stderr || "").trim();
            // The Plasma executable engine exposes the exit status under the
            // key "exit code" (with a space), not "exitCode".
            const exitCode = Number(data["exit code"]);

            if (exitCode === 0) {
                root.actionMessage = stdout || i18n("Done.");
                root.actionError = "";
            } else {
                root.actionMessage = "";
                root.actionError = stderr || stdout || i18n("The action failed.");
            }

            // Let systemd settle before asking for the new state.
            delayedStatusRefresh.restart();
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        running: true
        // triggeredOnStart does the first check at startup, so there is no
        // Component.onCompleted that would check a second time.
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Drives the elapsed/next-run labels and the refresh countdown.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }

    Timer {
        id: stopConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.stopArmed = false
    }

    Timer {
        id: delayedStatusRefresh
        interval: 700
        repeat: false
        onTriggered: root.refresh()
    }
}
