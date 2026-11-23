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
    readonly property color cBoost:  "#9b59b6"   // violeta — carga alta (tono propio, D2 23/11/2026)

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
    property var fanRpm: null          // int, o null = SIN lectura del sensor
    property double cpuPct: 0
    property double memPct: 0
    property string memUsed: "0"
    property string memTotal: "0"
    property string cpuName: ""
    property int cores: 0
    property int freqMhz: 0
    property var cpuHist: []
    property var memHist: []

    // ---- perfil térmico compartido (bloque «termico» del backend, §3.4) ----
    // El estado lo calcula el backend (suavizado, histéresis, persistencia);
    // el QML solo lo pinta. Sin la librería instalada: termDisponible = false
    // y se mantiene el aspecto neutro de siempre.
    property bool termDisponible: false
    property string termEstado: ""         // idle|normal|boost|warning|critical
    property string termEstadoAnterior: ""
    property var tempSuaveC: null          // °C suavizados
    property int termDesdeS: 0             // segundos en el estado actual
    property int restanteS: 0              // segundos que faltan para bajar
    property bool fanAviso: false          // anomalía declarada por el backend
    property string fanAvisoMotivo: ""
    property bool fanSensorOk: true        // false = sin lectura del ventilador
    property int tic: 0                    // tic de 1 Hz (parpadeo de «critical»)

    // ---- configuración ----
    property int pollMs: 2000          // cadencia del QML (el muestreo del backend es 1 s)
    property string unit: "C"          // "C" | "F"
    property bool cfgLoaded: false
    // override legítimo de warning_min/critical_min del perfil (§4.3): el
    // backend los publica en termico.perfil.umbrales y NO colorean por sí solos
    property int tempWarnC: 87
    property int tempCritC: 94

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
            // null = el sensor no responde (NO es 0 rpm: contrato §3.2)
            root.fanRpm = (d.fan_rpm === null || d.fan_rpm === undefined) ? null : d.fan_rpm
            root.cpuPct = d.cpu_pct || 0
            root.memPct = d.mem_pct || 0
            root.memUsed = d.mem_used_gb != null ? d.mem_used_gb.toFixed(1) : "0"
            root.memTotal = d.mem_total_gb != null ? d.mem_total_gb.toFixed(1) : "0"
            root.cpuName = d.cpu_name || ""
            root.cores = d.cores || 0
            root.freqMhz = d.freq_mhz || 0
            root.cpuHist = d.history || []
            root.memHist = d.mem_history || []
            // umbrales de temperatura (override del perfil, se refresca en vivo
            // con cada status: cambios en Configurar se propagan sin reiniciar)
            if (d.temp_warn_c > 0) root.tempWarnC = d.temp_warn_c
            if (d.temp_crit_c > 0) root.tempCritC = d.temp_crit_c
            // ---- estado térmico compartido ----
            var t = d.termico
            if (t && t.disponible) {
                root.termDisponible = true
                root.termEstado = t.estado || ""
                root.termEstadoAnterior = t.estado_anterior || ""
                root.tempSuaveC = (t.temp_suave_c === undefined ? null : t.temp_suave_c)
                root.termDesdeS = t.desde_s || 0
                root.restanteS = t.restante_s || 0
                const v = t.ventilador || {}
                root.fanAviso = v.aviso === true
                root.fanAvisoMotivo = v.aviso_motivo || ""
                const s = t.sensor || {}
                root.fanSensorOk = s.fan_disponible !== false
            } else {
                // degradación (§5.11): sin perfil no hay banda; aspecto neutro
                root.termDisponible = false
                root.termEstado = ""
                root.termEstadoAnterior = ""
                root.tempSuaveC = null
                root.termDesdeS = 0
                root.restanteS = 0
                root.fanAviso = false
                root.fanAvisoMotivo = ""
                root.fanSensorOk = true
            }
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
    function tempSuaveDisplay() {
        if (root.tempSuaveC === null) return ""
        var t = root.unit === "F" ? root.tempSuaveC * 9 / 5 + 32 : root.tempSuaveC
        return Math.round(t) + "°"
    }
    // §4.1 — tabla de estados: color, icono y etiqueta salen de termico.estado
    function estadoColor(e) {
        if (e === "normal") return root.cOK
        if (e === "boost") return root.cBoost
        if (e === "warning") return root.cWarn
        if (e === "critical") return root.cErr
        return root.cMed                    // idle (y estado desconocido)
    }
    function estadoIcono(e) {
        if (e === "idle") return "temperature-cold-symbolic"
        if (e === "warning" || e === "critical") return "temperature-warm-symbolic"
        return "temperature-normal-symbolic" // normal y boost
    }
    function estadoEtiqueta(e) {
        if (e === "idle") return "Reposo"
        if (e === "normal") return "Normal"
        if (e === "boost") return "Carga alta"
        if (e === "warning") return "Aviso"
        if (e === "critical") return "Crítico"
        return ""
    }
    function tempColor() {
        // SIEMPRE la banda del backend; sin perfil, neutro (nunca umbrales QML)
        return root.termDisponible ? root.estadoColor(root.termEstado) : root.cMed
    }
    function tempIcon() {
        return root.termDisponible ? root.estadoIcono(root.termEstado)
                                   : "temperature-cold-symbolic"
    }
    // «critical» parpadea a 1 Hz con binding sobre el tic, sin animaciones
    function parpadeoCritico() {
        var _ = root.tic
        if (!root.termDisponible || root.termEstado !== "critical") return 1.0
        return (root.tic % 2) === 0 ? 0.25 : 1.0
    }
    // temp_suave_c como subtítulo solo si difiere ≥ 2 °C del instantáneo
    function tempSuaveVisible() {
        if (!root.termDisponible || root.tempSuaveC === null) return false
        return Math.abs(root.tempSuaveC - root.tempC) >= 2
    }
    function restanteTexto() {
        return root.restanteS > 0 ? "bajando en " + root.restanteS + "s" : ""
    }
    function fanCompactText() {
        if (!root.backendUp || root.fanRpm === null || !root.fanSensorOk) return "—"
        if (root.fanRpm >= 1000) return Math.floor(root.fanRpm / 1000) + "K"
        return String(root.fanRpm)
    }
    function fanValorTexto() {
        if (!root.backendUp || root.fanRpm === null || !root.fanSensorOk) return "—"
        return root.fanRpm + " RPM"
    }
    // tarjeta VENTILADOR: en marcha / parado / ¡sin respuesta!
    function fanEstadoTexto() {
        if (!root.backendUp) return "—"
        if (root.fanAviso) return "¡sin respuesta!"
        if (root.fanRpm === null || !root.fanSensorOk) return "—"
        return root.fanRpm > 0 ? "en marcha" : "parado"
    }
    function fanEstadoColor() {
        if (!root.backendUp) return root.cDim
        if (root.fanAviso) return root.cErr
        if (root.fanRpm === null || !root.fanSensorOk) return root.cDim
        return root.fanRpm > 0 ? root.cOK : root.cDim
    }
    function fanTooltip() {
        if (root.fanAviso)
            return root.fanAvisoMotivo.length > 0 ? root.fanAvisoMotivo
                                                  : "temperatura alta sin respuesta del ventilador"
        if (!root.backendUp) return "backend no disponible"
        if (root.fanRpm === null || !root.fanSensorOk)
            return "sin lectura del sensor del ventilador"
        return root.fanRpm > 0 ? root.fanRpm + " RPM" : "parado (0 RPM)"
    }
    function tempTooltip() {
        var partes = []
        if (root.termDisponible && root.termEstado !== "")
            partes.push(root.estadoEtiqueta(root.termEstado))
        if (root.termDisponible && root.tempSuaveC !== null)
            partes.push("media " + root.tempSuaveDisplay())
        if (root.termDesdeS > 0) partes.push("desde hace " + root.termDesdeS + "s")
        if (root.restanteS > 0) partes.push(root.restanteTexto())
        return partes.join(" · ")
    }
    // La mascota lee el estado del backend (no umbrales del QML, §4.2)
    function petStateName() {
        if (!root.backendUp || !root.termDisponible) return "idle"
        if (root.termEstado === "idle") return root.cpuPct < 4 ? "sleepy" : "idle"
        if (root.termEstado === "boost") return "busy"
        if (root.termEstado === "warning") return "hot"
        if (root.termEstado === "critical") return "crit"
        return "idle"                       // normal (y estado desconocido)
    }
    function petMoodText() {
        var s = root.petStateName()
        if (s === "crit") return "¡Aguanta, que se quema!"
        if (s === "hot") return "Uf… qué calor hace aquí"
        if (s === "busy") return "¡A darle caña! 💪"
        if (s === "sleepy") return "Zzz… todo en calma"
        return "Todo tranquilo…"
    }

    // ---- tooltip del icono del panel (y «ficha» al pasar el ratón) ----
    toolTipMainText: root.backendUp
        ? "Latido — " + root.tempDisplay()
          + (root.termDisponible ? " · " + root.estadoEtiqueta(root.termEstado) : "")
        : "Latido — sin datos"
    toolTipSubText: root.backendUp
        ? [root.restanteTexto(),
           root.fanAviso ? "ventilador: ¡sin respuesta!" : ""]
              .filter(function(s) { return s !== "" }).join(" · ")
        : "Backend no disponible"

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

    // tic de 1 Hz: única fuente del parpadeo de «critical» (§4.1)
    Timer {
        id: ticTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.tic++
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
                opacity: root.backendUp ? root.parpadeoCritico() : 0.4
            }
            PlasmaComponents3.Label {
                text: root.backendUp ? root.tempDisplay() : "—"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.tempColor()
                opacity: root.parpadeoCritico()
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
                        // el estado lo decide el backend (termico.estado)
                        estadoMascota: root.petStateName()
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
                id: tempCard
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: root.rCard
                color: root.cCard
                border.width: 1
                border.color: root.cBorder

                HoverHandler { id: tempHover }
                PlasmaComponents3.ToolTip {
                    visible: tempHover.hovered && root.tempTooltip() !== ""
                    text: root.tempTooltip()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace + 4
                    Kirigami.Icon {
                        source: root.tempIcon()
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        opacity: root.parpadeoCritico()
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        // rótulo + chip del estado (el chip no debe empujar nada:
                        // el rótulo se elide con minimumWidth 0)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 6
                            PlasmaComponents3.Label {
                                text: "TEMPERATURA CPU"
                                font.pixelSize: root.fsCap
                                font.weight: Font.Medium
                                opacity: 0.6
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }
                            Rectangle {
                                id: chipEstado
                                visible: root.termDisponible && root.termEstado !== ""
                                implicitWidth: chipEstadoLabel.implicitWidth + 12
                                implicitHeight: chipEstadoLabel.implicitHeight + 4
                                radius: 4
                                color: Qt.rgba(root.estadoColor(root.termEstado).r,
                                               root.estadoColor(root.termEstado).g,
                                               root.estadoColor(root.termEstado).b, 0.16)
                                PlasmaComponents3.Label {
                                    id: chipEstadoLabel
                                    anchors.centerIn: parent
                                    text: root.estadoEtiqueta(root.termEstado)
                                    font.pixelSize: root.fsCap
                                    font.weight: Font.DemiBold
                                    color: root.estadoColor(root.termEstado)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 6
                            PlasmaComponents3.Label {
                                text: root.backendUp ? root.tempDisplay() : "—"
                                font.pixelSize: root.fsVal + 4
                                font.weight: Font.Bold
                                color: root.tempColor()
                                opacity: root.parpadeoCritico()
                            }
                            // temp_suave_c solo cuando difiere ≥ 2 °C del instantáneo
                            PlasmaComponents3.Label {
                                visible: root.tempSuaveVisible()
                                text: "media " + root.tempSuaveDisplay()
                                font.pixelSize: root.fsBody
                                color: root.cDim
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }
                        }
                    }
                    PlasmaComponents3.Label {
                        text: root.backendUp ? (root.freqMhz / 1000).toFixed(2) + " GHz" : ""
                        font.pixelSize: root.fsBody
                        color: root.cMed
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }

            // ---------- tarjeta: ventilador ----------
            Rectangle {
                id: fanCard
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                radius: root.rCard
                color: root.cCard
                border.width: 1
                // el aviso de anomalía se ve también en el borde de la tarjeta
                border.color: root.fanAviso ? root.cErr : root.cBorder

                HoverHandler { id: fanHover }
                PlasmaComponents3.ToolTip {
                    visible: fanHover.hovered
                    text: root.fanTooltip()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.mCard
                    spacing: root.gSpace + 4
                    Image {
                        source: "../images/fan.svg"
                        sourceSize: Qt.size(26, 26)
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        opacity: root.backendUp ? 1 : 0.4
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        PlasmaComponents3.Label {
                            text: "VENTILADOR"
                            font.pixelSize: root.fsCap
                            font.weight: Font.Medium
                            opacity: 0.6
                            elide: Text.ElideRight
                            Layout.minimumWidth: 0
                        }
                        PlasmaComponents3.Label {
                            text: root.fanValorTexto()
                            font.pixelSize: root.fsVal
                            font.weight: Font.Bold
                            color: root.cMed
                            elide: Text.ElideRight
                            Layout.minimumWidth: 0
                        }
                    }
                    // tres estados: en marcha / parado / ¡sin respuesta!
                    PlasmaComponents3.Label {
                        text: root.fanEstadoTexto()
                        font.pixelSize: root.fsBody
                        font.weight: root.fanAviso ? Font.DemiBold : Font.Normal
                        color: root.fanEstadoColor()
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
