import QtQuick

// Mascota pixel del Latido (Pulguito) — slime con antena que reacciona a la CPU
// y temperatura. Autocontenido: paleta + frames embebidos (sin import externo).
// Estados: idle / sleepy / busy / hot / crit.
Canvas {
    id: pet

    // ---- datos del sistema (se enlazan desde main.qml / PetStage.qml) ----
    property bool backendUp: false
    property real cpuPct: 0
    property real tempC: 0
    property real tempWarnC: 60
    property real tempCritC: 80

    // ---- animación ----
    property string stateName: "idle"
    property int frame: 0
    property real pixel: 4
    property real hopY: 0           // rebote (estado crítico)

    width: 18 * pixel
    height: 15 * pixel

    // ---- datos de la mascota (generados) ----
    function _data() {
        return { palette: { "K": "#01060a", "B": "#3abed2", "D": "#0e7a8a", "H": "#b8f7ff", "W": "#ffffff", "P": "#01060a", "A": "#f5a623", "R": "#ff3366", "G": "#00ff88", "F": "#f5a623", "O": "#ff7828", "S": "#8cd2f0", "M": "#01060a", "N": "#78848c", "b": "#ff965a", "r": "#eb5064", "E": "#aa1e32" }, states: { "idle": { interval: 700, frames: [["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KPWBBPWK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBBBBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KKKBBKKK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBBBBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KPWBBPWK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBMMBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KPWBBWWK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBBBBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "]] }, "sleepy": { interval: 900, frames: [["        A      W  ", "        K     W   ", "        K    WWW  ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KKBBBKBK     ", "     KKKBBKKK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBBBBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A      W  ", "        K     W   ", "        K    WWW  ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KKKBBKKK     ", "     KBBBBBBK     ", "     KBBMMBBK     ", "     KBBBBBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "]] }, "busy": { interval: 260, frames: [["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KPWBBPWK     ", "     KBBBBBBK     ", "     KBMMMBBK     ", "     KBMMMBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K    N    ", "   N    K   N     ", "  N  KKKKK   N    ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KBBBBBBK     ", "     KKWBBKWK     ", "     KBBBBBBK     ", "     KBMMMBBK     ", "     KBMMMBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KBBHBBBK     ", "     KKBBKKBK     ", "     KPWBBPWK     ", "     KBBBBBBK     ", "     KBMMMBBK     ", "     KBMMMBBK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "]] }, "hot": { interval: 320, frames: [["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "     KbbHbbbK     ", "     KbbbbbbK     ", "     KPWbbPWK     ", "     RRbbbbRR     ", "     KbbMMbbK     ", "     KbbRRbbK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "  SS KbbHbbbKSS   ", "     KbbbbbbK S   ", "     KKKbbKKK     ", "     RRbbbbRR     ", "     KbbMMbbK     ", "     KbbRRbbK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "], ["        A         ", "        K         ", "        K         ", "     KKKKK        ", "     KHHHHHK      ", "  SS KbbHbbbKSS   ", "     KbbbbbbK S   ", "     KPWbbPWK     ", "     RRbbbbRR     ", "     KbbMMbbK     ", "     KbbRRbbK     ", "     KDDDDDDK     ", "     KKKKKKK      ", "     D D  D D     ", "      K    K      "]] }, "crit": { interval: 150, frames: [["       OO         ", "      FFO         ", "        K O       ", "     KKKKK        ", "     KHHHHHK      ", "  SS KrrHrrrKSS   ", "     KrrrrrrK S   ", "     WWWrWWWK     ", "     KPrrrPrK     ", "     KrMMMrrK     ", "     KrMMMrrK     ", "     KEEEEEEK     ", "     KKKKKKK      ", "     E E  E E     ", "      K    K      "], ["      OOO         ", "      FFO  FON    ", "   N    K O N     ", "  N  KKKKK   N    ", "     KHHHHHK      ", "  SS KrrHrrrKSS   ", "     KrrrrrrK S   ", "     WWWrWWWK     ", "     KPrrrPrK     ", "     KrMMMrrK     ", "     KrMMMrrK     ", "     KEEEEEEK     ", "     KKKKKKK      ", "     E E  E E     ", "      K    K      "], ["      OOO         ", "      FFO  FO     ", "        K O       ", "     KKKKK        ", "     KHHHHHK      ", "  SS KrrHrrrKSS   ", "     KrrrrrrK S   ", "     WWWrWWWK     ", "     KPrrrPrK     ", "     KrMMMrrK     ", "     KrMMMrrK     ", "     KEEEEEEK     ", "     KKKKKKK      ", "     E E  E E     ", "      K    K      "]] } } };
    }

    function computeState() {
        if (!pet.backendUp) return "idle"
        if (pet.tempC >= pet.tempCritC) return "crit"
        if (pet.tempC >= pet.tempWarnC) return "hot"
        if (pet.cpuPct >= 60) return "busy"
        if (pet.cpuPct < 4 && pet.tempC < pet.tempWarnC - 8) return "sleepy"
        return "idle"
    }

    function syncState() {
        var s = pet.computeState()
        if (s !== pet.stateName) pet.stateName = s
    }

    onBackendUpChanged: pet.syncState()
    onCpuPctChanged: pet.syncState()
    onTempCChanged: pet.syncState()
    onTempWarnCChanged: pet.syncState()
    onTempCritCChanged: pet.syncState()

    Component.onCompleted: pet.syncState()

    onStateNameChanged: {
        pet.frame = 0
        var D = pet._data()
        var st = D ? D.states[pet.stateName] : null
        if (st && st.interval > 0) animTimer.interval = st.interval
        animTimer.restart()
        if (pet.stateName !== "crit") pet.hopY = 0
        pet.requestPaint()
    }

    Timer {
        id: animTimer
        interval: 700
        running: true
        repeat: true
        onTriggered: {
            pet.frame++
            pet.requestPaint()
        }
    }

    // rebote frenético en estado crítico
    SequentialAnimation {
        id: hopAnim
        running: pet.stateName === "crit"
        loops: Animation.Infinite
        NumberAnimation { target: pet; property: "hopY"; to: -8; duration: 90 }
        NumberAnimation { target: pet; property: "hopY"; to: 0;  duration: 90 }
        NumberAnimation { target: pet; property: "hopY"; to: -8; duration: 90 }
        NumberAnimation { target: pet; property: "hopY"; to: 0;  duration: 160 }
    }

    onHopYChanged: pet.requestPaint()

    onPaint: {
        var ctx = pet.getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var D = pet._data()
        var st = D.states[pet.stateName]
        if (!st || !st.frames || st.frames.length === 0) return
        var grid = st.frames[pet.frame % st.frames.length]
        var px = pet.pixel
        var hop = pet.stateName === "crit" ? pet.hopY : 0
        var pal = D.palette
        for (var y = 0; y < grid.length; y++) {
            var row = grid[y]
            for (var x = 0; x < row.length; x++) {
                var ch = row.charAt(x)
                if (ch === " ") continue
                var col = pal[ch]
                if (!col) continue
                ctx.fillStyle = col
                ctx.fillRect(x * px, y * px + hop, px, px)
            }
        }
    }
}
