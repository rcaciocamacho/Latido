import QtQuick
import "petFrames.js" as PetData

// Mascota pixel del Latido — slime con antena que reacciona a la CPU y
// temperatura. Dibuja los frames de petFrames.js sobre un Canvas.
// Estados: idle / sleepy / busy / hot / crit.

Canvas {
    id: pet

    // ---- datos del sistema (se enlazan desde main.qml) ----
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
        if (PetData.PET_STATES[pet.stateName]) pet.animTimer.interval = PetData.PET_STATES[pet.stateName].interval
        pet.animTimer.restart()
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
        var st = PetData.PET_STATES[pet.stateName]
        if (!st || st.frames.length === 0) return
        var grid = st.frames[pet.frame % st.frames.length]
        var px = pet.pixel
        var hop = pet.stateName === "crit" ? pet.hopY : 0
        for (var y = 0; y < grid.length; y++) {
            var row = grid[y]
            for (var x = 0; x < row.length; x++) {
                var ch = row.charAt(x)
                if (ch === " ") continue
                var col = PetData.PET_PALETTE[ch]
                if (!col) continue
                ctx.fillStyle = col
                ctx.fillRect(x * px, y * px + hop, px, px)
            }
        }
    }
}