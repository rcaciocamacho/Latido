import QtQuick

// Sparkline reutilizable — dibuja la serie `data` (0-100) con línea + área rellena.
// Mismo directorio que main.qml => disponible como tipo sin import adicional.
Canvas {
    id: spark

    property color lineColor: "#00d4ff"
    property color fillColor: "#00d4ff"
    property var series: []
    property real minY: 0
    property real maxY: 100

    onSeriesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var pts = spark.series
        if (!pts || pts.length < 2) return

        var w = width
        var h = height
        var lo = spark.minY
        var hi = spark.maxY
        var range = hi - lo
        if (range <= 0) range = 1

        // línea
        ctx.strokeStyle = spark.lineColor
        ctx.lineWidth = 1.5
        ctx.beginPath()
        for (var i = 0; i < pts.length; i++) {
            var x = i / (pts.length - 1) * w
            var y = h - (pts[i] - lo) / range * h
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
        }
        ctx.stroke()

        // área rellena (alpha bajo)
        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.globalAlpha = 0.15
        ctx.fillStyle = spark.fillColor
        ctx.fill()
    }
}
