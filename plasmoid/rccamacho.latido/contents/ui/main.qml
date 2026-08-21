import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components as PlasmaComponents3

PlasmoidItem {
    id: root

    // Paleta oscura fija (patrón JARVIS — Kirigami.Theme no aplica el color scheme)
    readonly property color cBG:      "#00060a"
    readonly property color cPanel:   "#010d14"
    readonly property color cBorder:  "#0d3347"
    readonly property color cPri:     "#00d4ff"
    readonly property color cGreen:   "#00ff88"
    readonly property color cRed:     "#ff3366"
    readonly property color cAmber:   "#f5a623"
    readonly property color cText:    "#8ffcff"
    readonly property color cTextDim: "#3a8a9a"
    readonly property color cTextMed: "#5ab8cc"

    property string apiUrl: "http://127.0.0.1:8136"
    property bool backendUp: false

    // ---- métricas (alimentadas por /api/status) ----
    property double tempC: 0
    property int fanRpm: 0
    property double cpuPct: 0
    property double memPct: 0
    property string memUsed: "0"
    property string memTotal: "0"
    property string cpuName: ""
    property int cores: 0
    property int freqMhz: 0
    property var cpuHist: []
    property var memHist: []

    // ---- configuración ----
    property int pollMs: 2000
    property string unit: "C"          // "C" | "F"
    property bool cfgLoaded: false
    property int tempWarnC: 60         // desde aquí -> ámbar
    property int tempCritC: 80         // desde aquí -> rojo

    // ---------------- API helpers ----------------
    function apiGet(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", root.apiUrl + path)
        x.timeout = 4000
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE) {
                if (x.status === 200) { try { cb(JSON.parse(x.responseText)) } catch(e) { cb(null) } }
                else cb(null)
            }
        }
        x.send()
    }

    function refreshStatus() {
        apiGet("/api/status", function(d) {
            if (!d) { root.backendUp = false; return }
            root.backendUp = true
            root.tempC = d.temp_c != null ? d.temp_c : 0
            root.fanRpm = d.fan_rpm || 0
            root.cpuPct = d.cpu_pct || 0
            root.memPct = d.mem_pct || 0
            root.memUsed = d.mem_used_gb != null ? d.mem_used_gb.toFixed(1) : "0"
            root.memTotal = d.mem_total_gb != null ? d.mem_total_gb.toFixed(1) : "0"
            root.cpuName = d.cpu_name || ""
            root.cores = d.cores || 0
            root.freqMhz = d.freq_mhz || 0
            root.cpuHist = d.history || []
            root.memHist = d.mem_history || []
            // umbrales de temperatura — se refrescan con cada status (cambios en
            // Configurar → General se propagan en vivo, sin reiniciar el widget)
            if (d.temp_warn_c > 0) root.tempWarnC = d.temp_warn_c
            if (d.temp_crit_c > 0) root.tempCritC = d.temp_crit_c
        })
    }

    function fetchConfig() {
        apiGet("/api/config", function(d) {
            if (!d) return
            if (d.unit === "F" || d.unit === "C") root.unit = d.unit
            if (d.interval_s > 0) root.pollMs = d.interval_s * 1000
            if (d.temp_warn_c > 0) root.tempWarnC = d.temp_warn_c
            if (d.temp_crit_c > 0) root.tempCritC = d.temp_crit_c
            root.cfgLoaded = true
        })
    }

    // ---------------- display helpers ----------------
    function tempDisplay() {
        var t = root.unit === "F" ? root.tempC * 9 / 5 + 32 : root.tempC
        return Math.round(t) + "°"
    }
    function tempColor() {
        if (root.tempC < root.tempWarnC) return root.cText
        if (root.tempC < root.tempCritC) return root.cAmber
        return root.cRed
    }
    function tempIcon() {
        if (root.tempC < root.tempWarnC) return "temperature-cold-symbolic"
        if (root.tempC < root.tempCritC) return "temperature-normal-symbolic"
        return "temperature-warm-symbolic"
    }
    function fanCompactText() {
        if (!root.backendUp || root.fanRpm <= 0) return "—"
        if (root.fanRpm >= 1000) return Math.floor(root.fanRpm / 1000) + "K"
        return String(root.fanRpm)
    }
    function petStateName() {
        if (!root.backendUp) return "idle"
        if (root.tempC >= root.tempCritC) return "crit"
        if (root.tempC >= root.tempWarnC) return "hot"
        if (root.cpuPct >= 60) return "busy"
        if (root.cpuPct < 4 && root.tempC < root.tempWarnC - 8) return "sleepy"
        return "idle"
    }
    function petMoodText() {
        var s = root.petStateName()
        if (s === "crit") return "¡Aguanta, que se quema!"
        if (s === "hot") return "Uf… qué calor hace aquí"
        if (s === "busy") return "¡A darle caña! 💪"
        if (s === "sleepy") return "Zzz… todo en calma"
        return "Todo tranquilo…"
    }

    Timer {
        id: pollTimer
        interval: root.pollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }
    onPollMsChanged: {
        if (root.cfgLoaded) pollTimer.restart()
    }

    Component.onCompleted: {
        root.fetchConfig()
        root.refreshStatus()
    }

    // ============================================================
    //  ICONO DEL PANEL
    // ============================================================
    compactRepresentation: Item {
        Layout.minimumWidth: 216
        Layout.minimumHeight: 28

        RowLayout {
            anchors.centerIn: parent
            spacing: 4

            Kirigami.Icon {
                source: root.backendUp ? root.tempIcon() : "temperature-cold-symbolic"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                opacity: root.backendUp ? 1 : 0.4
            }
            PlasmaComponents3.Label {
                text: root.backendUp ? root.tempDisplay() : "—"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.tempColor()
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: root.cBorder
                opacity: 0.7
            }

            Kirigami.Icon {
                source: "cpu"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                opacity: root.backendUp ? 1 : 0.4
            }
            PlasmaComponents3.Label {
                text: root.backendUp ? Math.round(root.cpuPct) + "%" : "—"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.cPri
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: root.cBorder
                opacity: 0.7
            }

            Kirigami.Icon {
                source: "memory"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                opacity: root.backendUp ? 1 : 0.4
            }
            PlasmaComponents3.Label {
                text: root.backendUp ? Math.round(root.memPct) + "%" : "—"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.cText
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: root.cBorder
                opacity: 0.7
            }

            Image {
                source: "../images/fan.svg"
                sourceSize: Qt.size(18, 18)
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                opacity: root.backendUp ? 1 : 0.4
            }
            PlasmaComponents3.Label {
                text: root.fanCompactText()
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.cTextMed
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ============================================================
    //  PANEL EXPANDIDO
    // ============================================================
    fullRepresentation: Item {
        implicitWidth: 330
        implicitHeight: mainCol.implicitHeight

        Rectangle { anchors.fill: parent; color: root.cBG }

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 6

            // ---------- mascota ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 4
                    spacing: 2
                    Pet {
                        Layout.alignment: Qt.AlignHCenter
                        pixel: 5
                        backendUp: root.backendUp
                        cpuPct: root.cpuPct
                        tempC: root.tempC
                        tempWarnC: root.tempWarnC
                        tempCritC: root.tempCritC
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp ? root.petMoodText() : "El sistema está fuera…"
                        font.pixelSize: 11
                        color: root.cTextMed
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.5
            }

            // ---------- header ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8
                    Kirigami.Icon {
                        source: "utilities-system-monitor"
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                    }
                    PlasmaComponents3.Label {
                        text: "Latido"
                        font.weight: Font.DemiBold
                        font.pixelSize: 14
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: root.backendUp ? root.cGreen : root.cRed
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp ? "en vivo" : "sin datos"
                        font.pixelSize: 11
                        color: root.backendUp ? root.cGreen : root.cRed
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.5
            }

            // ---------- aviso backend caído ----------
            Rectangle {
                Layout.fillWidth: true
                visible: !root.backendUp
                color: "#3d0a0a"
                Layout.preferredHeight: 34
                PlasmaComponents3.Label {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    verticalAlignment: Text.AlignVCenter
                    text: "⚠ Backend no disponible — inicia latido.service"
                    font.pixelSize: 11
                    color: "#ff8080"
                }
            }

            // ---------- tarjeta temperatura ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Kirigami.Icon {
                        source: root.tempIcon()
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            text: "TEMPERATURA CPU"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: root.cTextDim
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp ? root.tempDisplay() : "—"
                            font.pixelSize: 26
                            font.weight: Font.Bold
                            color: root.tempColor()
                        }
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp ? (root.freqMhz / 1000).toFixed(2) + " GHz" : ""
                        font.pixelSize: 11
                        color: root.cTextMed
                    }
                }
            }

            // ---------- línea divisoria ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.35
            }

            // ---------- tarjeta ventilador ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Image {
                        source: "../images/fan.svg"
                        sourceSize: Qt.size(26, 26)
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        opacity: root.backendUp ? 1 : 0.4
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            text: "VENTILADOR"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: root.cTextDim
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp && root.fanRpm > 0 ? root.fanRpm + " RPM" : "—"
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            color: root.cTextMed
                        }
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp && root.fanRpm > 0 ? "en marcha" : "parado"
                        font.pixelSize: 11
                        color: root.backendUp && root.fanRpm > 0 ? root.cGreen : root.cTextDim
                    }
                }
            }

            // ---------- línea divisoria ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.35
            }

            // ---------- tarjeta CPU ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Kirigami.Icon {
                            source: "cpu"
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            PlasmaComponents3.Label {
                                text: "CPU"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: root.cTextDim
                            }
                            PlasmaComponents3.Label {
                                text: root.backendUp ? Math.round(root.cpuPct) + "%" : "—"
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                color: root.cPri
                            }
                        }
                        PlasmaComponents3.Label {
                            text: root.cores > 0 ? root.cores + " hilos" : ""
                            font.pixelSize: 11
                            color: root.cTextMed
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: root.cBorder
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * Math.min(1, root.cpuPct / 100)
                            height: 4
                            radius: 2
                            color: root.cPri
                        }
                    }
                    SparkLine {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        lineColor: root.cPri
                        fillColor: root.cPri
                        series: root.cpuHist
                    }
                }
            }

            // ---------- línea divisoria ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.35
            }

            // ---------- tarjeta RAM ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Kirigami.Icon {
                            source: "memory"
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            PlasmaComponents3.Label {
                                text: "MEMORIA"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: root.cTextDim
                            }
                            PlasmaComponents3.Label {
                                text: root.backendUp ? Math.round(root.memPct) + "%" : "—"
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                color: root.cText
                            }
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp ? root.memUsed + " / " + root.memTotal + " GB" : ""
                            font.pixelSize: 11
                            color: root.cTextMed
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: root.cBorder
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * Math.min(1, root.memPct / 100)
                            height: 4
                            radius: 2
                            color: root.cTextMed
                        }
                    }
                    SparkLine {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        lineColor: root.cTextMed
                        fillColor: root.cTextMed
                        series: root.memHist
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.cBorder
                opacity: 0.5
            }

            // ---------- footer ----------
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8
                    PlasmaComponents3.Label {
                        text: root.cpuName || "—"
                        font.pixelSize: 10
                        color: root.cTextDim
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        text: root.cores > 0 ? root.cores + " hilos" : ""
                        font.pixelSize: 10
                        color: root.cTextDim
                    }
                }
            }
        }
    }
}
