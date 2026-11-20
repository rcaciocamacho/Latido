import QtQuick
import QtQuick.Window

// Mascota flotante del Latido (Pulguito) — ventana X11/XWayland (el lanzador
// fuerza QT_QPA_PLATFORM=xcb, donde el cliente SÍ puede posicionar/desmapear,
// a diferencia de Wayland). ESTADO: visible:false la desmapea por completo
// (sin pet fijo en pantalla) y al mostrar se posiciona en la esquina superior
// derecha. Aparece cuando la temperatura supera el umbral de aviso (temp_warn_c,
// por defecto 75) o la CPU pasa del 90%; se oculta sola a los 10 s o al calmarla.
// No roba el foco (WindowDoesNotAcceptFocus) y un clic encima la oculta.
Window {
    id: stage
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.Tool
    title: "Latido · Pulguito"

    // ---------- configuración (viene del backend del Latido) ----------
    property string apiUrl: "http://127.0.0.1:8136"
    property bool autoShowCfg: true
    property real px: 12                // 18x12=216 x 15x12=180
    property real tempTrigger: 75.0     // aparece si temp es mayor (se actualiza desde config)
    property real cpuTrigger: 90.0      // aparece si CPU supera esto (%)
    property int hideGraceMs: 2500      // espera para ocultarse tras calmarse
    property int maxShowMs: 10000       // se oculta sola a los 10 s aunque siga la carga
    property real _sw: 0                // ancho de pantalla cacheado

    // ---------- métricas del sistema ----------
    property var metrics: ({ temp_c: 0, cpu_pct: 0, mem_pct: 0 })
    // estado térmico del backend (termico.estado): manda sobre los umbrales
    property bool termDisponible: false
    property string termEstado: ""
    property bool shouldShow: false

    width: Math.round(18 * px)
    height: Math.round(15 * px)

    function _reposition() {
        if (stage._sw <= 0) {
            var sc = stage.screen || Screen.primaryScreen
            if (sc && sc.width > 0) stage._sw = sc.width
        }
        if (stage._sw > 0) {
            stage.x = Math.max(0, Math.round(stage._sw - stage.width - 36))
            stage.y = 44
        }
    }

    function apiGet(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", stage.apiUrl + path)
        x.timeout = 4000
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE && x.status === 200) {
                try { cb(JSON.parse(x.responseText)) } catch(e) { cb(null) }
            }
        }
        x.send()
    }

    // estado de la mascota: lo decide el backend (misma tabla que el plasmoid)
    function estadoMascota() {
        if (!stage.termDisponible) return "idle"
        if (stage.termEstado === "idle")
            return stage.metrics.cpu_pct < 4 ? "sleepy" : "idle"
        if (stage.termEstado === "boost") return "busy"
        if (stage.termEstado === "warning") return "hot"
        if (stage.termEstado === "critical") return "crit"
        return "idle"
    }

    function refresh() {
        apiGet("/api/config", function(d) {
            if (!d) return
            stage.autoShowCfg = d.auto_show !== undefined ? d.auto_show : true
            if (d.temp_warn_c > 0) stage.tempTrigger = d.temp_warn_c
        })
        apiGet("/api/status", function(d) {
            if (!d) return
            stage.metrics = {
                temp_c: d.temp_c != null ? d.temp_c : 0,
                cpu_pct: d.cpu_pct || 0,
                mem_pct: d.mem_pct || 0
            }
            var t = d.termico
            stage.termDisponible = !!(t && t.disponible)
            stage.termEstado = stage.termDisponible ? (t.estado || "") : ""
            // «caliente» = banda de aviso o crítica del perfil; sin perfil, el
            // umbral de config (comportamiento antiguo)
            var hot = stage.termDisponible
                ? (stage.termEstado === "warning" || stage.termEstado === "critical")
                : (stage.metrics.temp_c > stage.tempTrigger)
            var load = stage.metrics.cpu_pct > stage.cpuTrigger
            stage.shouldShow = stage.autoShowCfg && (hot || load)
        })
    }

    onShouldShowChanged: {
        if (stage.shouldShow) {
            hideGrace.stop()
            showMaxTimer.stop()
            stage._reposition()
            stage.visible = true
            repositionTimer.start()
            showMaxTimer.start()
        } else {
            hideGrace.start()
        }
    }

    function hideNow() {
        hideGrace.stop()
        showMaxTimer.stop()
        stage.visible = false
    }

    Timer {
        id: showMaxTimer
        interval: stage.maxShowMs
        repeat: false
        onTriggered: stage.hideNow()
    }
    Timer {
        id: hideGrace
        interval: stage.hideGraceMs
        repeat: false
        onTriggered: stage.hideNow()
    }
    Timer {
        id: repositionTimer
        interval: 250
        repeat: false
        onTriggered: stage._reposition()
    }
    Timer {
        id: metricsTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: stage.refresh()
    }
    // saludo inicial: confirma que está vivo (~4 s al arrancar)
    Timer {
        id: helloTimer
        interval: 1200
        repeat: false
        onTriggered: {
            stage.shouldShow = stage.autoShowCfg
            helloHold.start()
        }
    }
    Timer {
        id: helloHold
        interval: 4000
        repeat: false
        onTriggered: { stage.shouldShow = false }
    }

    // ---------- la mascota + clic para ocultar ----------
    Pet {
        anchors.fill: parent
        pixel: stage.px
        backendUp: true
        estadoMascota: stage.estadoMascota()
    }
    MouseArea {
        anchors.fill: parent
        onClicked: stage.hideNow()
        cursorShape: Qt.PointingHandCursor
    }

    Component.onCompleted: {
        stage.refresh()
        stage._reposition()               // aprende la pantalla (sigue oculta)
        helloTimer.start()
    }
}