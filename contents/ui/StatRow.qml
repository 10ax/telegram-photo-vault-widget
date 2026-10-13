// One popup row: a label, a right-aligned value, and an optional quieter
// sub-line indented under the label. Every value is passed in; the row only
// lays out.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: statRow

    required property string label
    required property string value
    required property int smallPointSize
    property string subText: ""
    property color valueColor: Kirigami.Theme.textColor

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    // Fixed, so a long label cannot eat the value next to it.
    readonly property real labelWidth: Kirigami.Units.gridUnit * 6

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.preferredWidth: statRow.labelWidth
            Layout.maximumWidth: statRow.labelWidth
            text: statRow.label
            opacity: 0.6
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: statRow.value
            color: statRow.valueColor
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        // Line the sub-line up under the label, not under the value.
        Layout.leftMargin: statRow.labelWidth + Kirigami.Units.smallSpacing
        visible: statRow.subText.length > 0
        text: statRow.subText
        font.pointSize: statRow.smallPointSize
        opacity: 0.6
        elide: Text.ElideRight
    }
}
