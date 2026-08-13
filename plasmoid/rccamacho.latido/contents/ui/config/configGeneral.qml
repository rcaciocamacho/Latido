import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string apiUrl: "http://127.0.0.1:8136"
    property int intervalS: 2
    property string unit: "C"

    function apiGet(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", page.apiUrl + path)
        x.timeout = 4000
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE && x.status === 200) {
                try { cb(JSON.parse(x.responseText)) } catch(e) { cb(null) }
            }
        }
        x.send()
    }

    function save() {
        var x = new XMLHttpRequest()
        x.open("POST", page.apiUrl + "/api/config")
        x.setRequestHeader("Content-Type", "application/json")
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE && x.status === 200) {
                // ok — el plasmoid recoge la nueva config en su próximo fetch
            }
        }
        x.send(JSON.stringify({interval_s: page.intervalS, unit: page.unit}))
    }

    Component.onCompleted: {
        apiGet("/api/config", function(d) {
            if (!d) return
            page.intervalS = d.interval_s || 2
            page.unit = d.unit === "F" ? "F" : "C"
            for (var i = 0; i < intervalCombo.model.count; i++) {
                if (intervalCombo.model.get(i).value === page.intervalS) intervalCombo.currentIndex = i
            }
            for (var j = 0; j < unitCombo.model.count; j++) {
                if (unitCombo.model.get(j).value === page.unit) unitCombo.currentIndex = j
            }
        })
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.Label {
            text: "Latido — CPU · RAM · Temperatura"
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: "Intervalo de refresco"
                Layout.fillWidth: true
            }
            Controls.ComboBox {
                id: intervalCombo
                Layout.preferredWidth: 140
                model: ListModel {
                    ListElement { text: "1 segundo"; value: 1 }
                    ListElement { text: "2 segundos"; value: 2 }
                    ListElement { text: "3 segundos"; value: 3 }
                    ListElement { text: "5 segundos"; value: 5 }
                }
                textRole: "text"
                onActivated: page.intervalS = intervalCombo.model.get(currentIndex).value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: "Unidad de temperatura"
                Layout.fillWidth: true
            }
            Controls.ComboBox {
                id: unitCombo
                Layout.preferredWidth: 140
                model: ListModel {
                    ListElement { text: "Grados Celsius (°C)"; value: "C" }
                    ListElement { text: "Grados Fahrenheit (°F)"; value: "F" }
                }
                textRole: "text"
                onActivated: page.unit = unitCombo.model.get(currentIndex).value
            }
        }

        Controls.Button {
            text: "Guardar"
            onClicked: page.save()
        }
    }
}
