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
    property int warnC: 60              // umbral aviso (siempre en °C)
    property int critC: 80              // umbral crítico (siempre en °C)
    property bool autoShow: true        // mostrar la mascota periódicamente
    property int autoShowIntervalS: 120 // cada cuántos segundos

    // conversión según la unidad elegida (los umbrales se guardan en °C)
    function cToUnit(c) { return page.unit === "F" ? Math.round(c * 9 / 5 + 32) : Math.round(c) }
    function unitToC(v) { return page.unit === "F" ? Math.round((v - 32) / 1.8) : Math.round(v) }

    function refreshSpins() {
        warnSpin.value = page.cToUnit(page.warnC)
        critSpin.value = page.cToUnit(page.critC)
    }

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
        x.send(JSON.stringify({
            interval_s: page.intervalS,
            unit: page.unit,
            temp_warn_c: page.warnC,
            temp_crit_c: page.critC,
            auto_show: page.autoShow,
            auto_show_interval_s: page.autoShowIntervalS
        }))
    }

    Component.onCompleted: {
        apiGet("/api/config", function(d) {
            if (!d) return
            page.intervalS = d.interval_s || 2
            page.unit = d.unit === "F" ? "F" : "C"
            page.warnC = d.temp_warn_c || 60
            page.critC = d.temp_crit_c || 80
            page.autoShow = d.auto_show !== undefined ? d.auto_show : true
            page.autoShowIntervalS = d.auto_show_interval_s > 0 ? d.auto_show_interval_s : 120
            autoSpin.value = page.autoShowIntervalS
            for (var i = 0; i < intervalCombo.model.count; i++) {
                if (intervalCombo.model.get(i).value === page.intervalS) intervalCombo.currentIndex = i
            }
            for (var j = 0; j < unitCombo.model.count; j++) {
                if (unitCombo.model.get(j).value === page.unit) unitCombo.currentIndex = j
            }
            page.refreshSpins()
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
                onActivated: {
                    page.unit = unitCombo.model.get(currentIndex).value
                    page.refreshSpins()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.12
        }

        // umbral de aviso
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: "Aviso de temperatura (ámbar)"
                Layout.fillWidth: true
            }
            Controls.SpinBox {
                id: warnSpin
                Layout.preferredWidth: 90
                from: 20; to: 260; stepSize: 1; editable: true
                wrap: true
                onValueModified: page.warnC = page.unitToC(value)
            }
            PlasmaComponents3.Label {
                text: page.unit
                color: Kirigami.Theme.textColor
                opacity: 0.6
                Layout.preferredWidth: 18
            }
        }

        // umbral crítico
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: "Temperatura crítica (rojo)"
                Layout.fillWidth: true
            }
            Controls.SpinBox {
                id: critSpin
                Layout.preferredWidth: 90
                from: 30; to: 270; stepSize: 1; editable: true
                wrap: true
                onValueModified: page.critC = page.unitToC(value)
            }
            PlasmaComponents3.Label {
                text: page.unit
                color: Kirigami.Theme.textColor
                opacity: 0.6
                Layout.preferredWidth: 18
            }
        }

        // mascota periódica
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.12
        }
        Controls.CheckBox {
            text: "Mostrar la mascota periódicamente"
            checked: page.autoShow
            onToggled: page.autoShow = checked
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            PlasmaComponents3.Label {
                text: "Mostrar cada"
                Layout.fillWidth: true
            }
            Controls.SpinBox {
                id: autoSpin
                Layout.preferredWidth: 90
                from: 30; to: 3600; stepSize: 30; editable: true
                onValueModified: page.autoShowIntervalS = value
            }
            PlasmaComponents3.Label {
                text: "seg"
                color: Kirigami.Theme.textColor
                opacity: 0.6
                Layout.preferredWidth: 30
            }
        }

        Controls.Button {
            text: "Guardar"
            onClicked: page.save()
        }
    }
}