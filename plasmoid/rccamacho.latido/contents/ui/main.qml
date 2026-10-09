import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components as PlasmaComponents3

PlasmoidItem {
    id: root

    // ============================================================
    //  ESTILO — lenguaje visual de LibreLinkUp (theme-aware)
    //  Neutros derivados del tema (se adaptan a claro/oscuro).
    //  Acentos = semántica de estado: verde/ámbar/rojo/azul.
    // ============================================================
    readonly property color cText:   Kirigami.Theme.textColor
    readonly property color cMed:    Qt.alpha(Kirigami.Theme.textColor, 0.80)   // secundario destacado
    readonly property color cDim:    Qt.alpha(Kirigami.Theme.textColor, 0.60)   // pies / captions
    readonly property color cCard:   Qt.alpha(Kirigami.Theme.textColor, 0.05)   // fondo de tarjeta
    readonly property color cBorder: Qt.alpha(Kirigami.Theme.textColor, 0.10)   // borde / track / divisor
    readonly property color cOK:     "#2ecc71"   // verde  — en rango
    readonly property color cWarn:   "#f39c12"   // ámbar  — aviso
    readonly property color cErr:    "#e74c3c"   // rojo   — crítico
    readonly property color cInfo:   "#3498db"   // azul   — acento informativo

    // medidas (escala LibreLinkUp)
    readonly property int rCard:   8
    readonly property int mCard:   10   // margen interno de tarjeta
    readonly property int mMargin: 12   // margen del popup
    readonly property int gSpace:  8    // espaciado entre bloques
    readonly property int fsCap:   10   // caption
    readonly property int fsBody:  11   // cuerpo
    readonly property int fsVal:   22   // valor

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
        if (root.tempC < root.tempWarnC) return root.cOK
        if (root.tempC < root.tempCritC) return root.cWarn
        return root.cErr
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
                color: root.cInfo
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: root.cBorder
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
                color: root.cMed
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
        implicitHeight: mainCol.implicitHeight + 2 * root.mMargin

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.mMargin
            anchors.rightMargin: root.mMargin
            anchors.topMargin: root.mMargin
            spacing: root.gSpace

            // ---------- tarjeta: mascota ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
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
                        font.pixelSize: root.fsBody
                        color: root.cDim
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ---------- header ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                spacing: root.gSpace
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
                    color: root.backendUp ? root.cOK : root.cErr
                }
                PlasmaComponents3.Label {
                    text: root.backendUp ? "en vivo" : "sin datos"
                    font.pixelSize: root.fsBody
                    color: root.backendUp ? root.cOK : root.cErr
                }
            }

            // ---------- aviso backend caído (caja de estado) ----------
            Rectangle {
                Layout.fillWidth: true
                visible: !root.backendUp
                implicitHeight: warnLabel.contentHeight + 2 * root.mCard
                radius: 6
                color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.10)
                border.width: 1
                border.color: Qt.alpha(root.cErr, 0.20)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.gSpace
                    spacing: root.gSpace
                    Kirigami.Icon {
                        source: "dialog-warning"
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents3.Label {
                        id: warnLabel
                        text: "Backend no disponible — inicia latido.service"
                        font.pixelSize: root.fsCap
                        color: root.cErr
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // ---------- tarjeta: temperatura ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace + 4
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
                            font.pixelSize: root.fsCap
                            font.weight: Font.Medium
                            opacity: 0.6
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp ? root.tempDisplay() : "—"
                            font.pixelSize: root.fsVal + 4
                            font.weight: Font.Bold
                            color: root.tempColor()
                        }
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp ? (root.freqMhz / 1000).toFixed(2) + " GHz" : ""
                        font.pixelSize: root.fsBody
                        color: root.cMed
                    }
                }
            }

            // ---------- tarjeta: ventilador ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace + 4
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
                            font.pixelSize: root.fsCap
                            font.weight: Font.Medium
                            opacity: 0.6
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp && root.fanRpm > 0 ? root.fanRpm + " RPM" : "—"
                            font.pixelSize: root.fsVal
                            font.weight: Font.Bold
                            color: root.cMed
                        }
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp && root.fanRpm > 0 ? "en marcha" : "parado"
                        font.pixelSize: root.fsBody
                        color: root.backendUp && root.fanRpm > 0 ? root.cOK : root.cDim
                    }
                }
            }

            // ---------- tarjeta: CPU ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace - 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.gSpace + 4
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
                                font.pixelSize: root.fsCap
                                font.weight: Font.Medium
                                opacity: 0.6
                            }
                            PlasmaComponents3.Label {
                                text: root.backendUp ? Math.round(root.cpuPct) + "%" : "—"
                                font.pixelSize: root.fsVal
                                font.weight: Font.Bold
                                color: root.cInfo
                            }
                        }
                        PlasmaComponents3.Label {
                            text: root.cores > 0 ? root.cores + " hilos" : ""
                            font.pixelSize: root.fsBody
                            color: root.cMed
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
                            color: root.cInfo
                        }
                    }
                    SparkLine {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        lineColor: root.cInfo
                        fillColor: root.cInfo
                        series: root.cpuHist
                    }
                }
            }

            // ---------- tarjeta: RAM ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace - 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.gSpace + 4
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
                                font.pixelSize: root.fsCap
                                font.weight: Font.Medium
                                opacity: 0.6
                            }
                            PlasmaComponents3.Label {
                                text: root.backendUp ? Math.round(root.memPct) + "%" : "—"
                                font.pixelSize: root.fsVal
                                font.weight: Font.Bold
                                color: root.cText
                            }
                        }
                        PlasmaComponents3.Label {
                            text: root.backendUp ? root.memUsed + " / " + root.memTotal + " GB" : ""
                            font.pixelSize: root.fsBody
                            color: root.cMed
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
                            color: root.cMed
                        }
                    }
                    SparkLine {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        lineColor: root.cMed
                        fillColor: root.cMed
                        series: root.memHist
                    }
                }
            }

            // ---------- footer ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                Layout.topMargin: 2
                spacing: root.gSpace
                PlasmaComponents3.Label {
                    text: root.cpuName || "—"
                    font.pixelSize: root.fsBody
                    color: root.cDim
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    text: root.cores > 0 ? root.cores + " hilos" : ""
                    font.pixelSize: root.fsBody
                    color: root.cDim
                }
            }
        }
    }
}
