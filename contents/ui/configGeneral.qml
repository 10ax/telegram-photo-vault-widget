import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

// Config page for the "General" group in contents/config/main.xml.
//
// The root is KCM.SimpleKCM (a Kirigami.ScrollablePage), not a bare
// Kirigami.FormLayout: the dialog pushes the page with a "title" initial
// property (the category name) that the PageRow toolbar renders as the page
// heading, and only a Page has that property or page padding.
//
// The framework copies every entry onto this item as a cfg_<name> property, so
// the controls write through those rather than touching Plasmoid.configuration
// directly (that would skip Apply/Discard).
KCM.SimpleKCM {
    id: page

    property alias cfg_pollIntervalSeconds: intervalSpin.value
    property alias cfg_actionsEnabled: actionsCheck.checked
    property alias cfg_confirmStop: confirmCheck.checked
    property alias cfg_showTrayText: trayTextCheck.checked
    property alias cfg_showUploadsRow: uploadsCheck.checked
    property alias cfg_showWorkerRow: workerCheck.checked
    property alias cfg_showRecoveryRow: recoveryCheck.checked
    property alias cfg_showDiskRow: diskCheck.checked
    property alias cfg_showFooter: footerCheck.checked

    // Not an alias: ComboBox maps its current index to a string value.
    property string cfg_trayIndicator

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: intervalSpin

            Kirigami.FormData.label: i18n("Check status every:")

            from: 10
            to: 3600
            stepSize: 10
            editable: true
            textFromValue: (value) => i18n("%1 s", value)
            valueFromText: (text) => Number.parseInt(text, 10) || 30
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Tray")
        }

        QQC2.CheckBox {
            id: trayTextCheck
            text: i18n("Show the pending count next to the tray icon")
        }

        QQC2.ComboBox {
            id: trayIndicatorCombo

            Kirigami.FormData.label: i18n("State indicator:")

            textRole: "text"
            model: [
                { value: "state-dot", text: i18n("Coloured dot (running, warning, stopped)") },
                { value: "icon-swap", text: i18n("Swap the icon (colour-blind friendly)") },
                { value: "none", text: i18n("Nothing extra") }
            ]
            currentIndex: {
                const modes = ["state-dot", "icon-swap", "none"];
                const index = modes.indexOf(page.cfg_trayIndicator);
                return index === -1 ? 0 : index;
            }
            onActivated: page.cfg_trayIndicator = model[currentIndex].value
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Controls")
        }

        QQC2.CheckBox {
            id: actionsCheck
            text: i18n("Allow starting, stopping and restarting from the widget")
        }

        QQC2.CheckBox {
            id: confirmCheck
            text: i18n("Ask for a second click before stopping")
            enabled: page.cfg_actionsEnabled
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Rows")
        }

        QQC2.CheckBox {
            id: uploadsCheck
            text: i18n("Uploads (pending, in progress, failed)")
        }

        QQC2.CheckBox {
            id: workerCheck
            text: i18n("Worker (running, next run, last error)")
        }

        QQC2.CheckBox {
            id: recoveryCheck
            text: i18n("Recovery (tidy state and last batch)")
        }

        QQC2.CheckBox {
            id: diskCheck
            text: i18n("Disk (free space and the download floor)")
        }

        QQC2.CheckBox {
            id: footerCheck
            text: i18n("Show the last update and the next check")
        }
    }
}
