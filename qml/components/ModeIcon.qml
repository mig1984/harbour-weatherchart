import QtQuick 2.2
import Sailfish.Silica 1.0

// Simple vector icons for chart modes: "temp" (thermometer), "wind"
// (three streamlines), "clouds" (cloud). The theme has no such icons.
Canvas {
    id: icon
    property string kind: "temp"
    property bool active: false
    property color color: active ? Theme.highlightColor : Theme.primaryColor

    width: Theme.iconSizeSmall * 2
    height: Theme.iconSizeSmall * 2
    antialiasing: true
    onColorChanged: requestPaint()
    onKindChanged: requestPaint()
    Component.onCompleted: requestPaint()

    // The Canvas content is lost while the app is in the background; repaint
    // on every activation so the icons do not disappear after returning.
    Connections {
        target: Qt.application
        onActiveChanged: if (Qt.application.active) icon.requestPaint()
    }

    onPaint: {
        var ctx = getContext("2d")
        var w = width, h = height
        ctx.reset()
        ctx.clearRect(0, 0, w, h)
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = Math.max(2, w * 0.07)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        var cx = w / 2, cy = h / 2

        if (kind === "temp") {
            var r = w * 0.14          // bulb radius
            var tw = w * 0.14         // tube width
            var top = h * 0.14, bottom = h * 0.68
            ctx.beginPath()
            ctx.moveTo(cx - tw / 2, top + tw / 2)
            ctx.arc(cx, top + tw / 2, tw / 2, Math.PI, 0)
            ctx.lineTo(cx + tw / 2, bottom - r * 0.4)
            ctx.arc(cx, bottom + r * 0.6, r, -Math.PI / 3, Math.PI + Math.PI / 3)
            ctx.closePath()
            ctx.stroke()
            // mercury
            ctx.beginPath()
            ctx.arc(cx, bottom + r * 0.6, r * 0.55, 0, 2 * Math.PI)
            ctx.fill()
            ctx.beginPath()
            ctx.lineWidth = tw * 0.4
            ctx.moveTo(cx, bottom + r * 0.4)
            ctx.lineTo(cx, h * 0.36)
            ctx.stroke()
        } else if (kind === "wind") {
            var lw = ctx.lineWidth
            var stream = function (y, x0, x1, curl, dir) {
                ctx.beginPath()
                ctx.moveTo(x0, y)
                ctx.lineTo(x1, y)
                ctx.arc(x1, y - dir * curl, curl, dir > 0 ? Math.PI / 2 : -Math.PI / 2,
                        dir > 0 ? -Math.PI / 2 : Math.PI / 2, dir > 0)
                ctx.stroke()
            }
            stream(h * 0.33, w * 0.12, w * 0.62, w * 0.10, 1)
            stream(h * 0.52, w * 0.12, w * 0.78, w * 0.10, 1)
            stream(h * 0.71, w * 0.12, w * 0.55, w * 0.09, -1)
        } else {
            // cloud
            ctx.beginPath()
            var b = h * 0.68
            ctx.moveTo(w * 0.22, b)
            ctx.arc(w * 0.26, b - h * 0.12, h * 0.12, Math.PI / 2, Math.PI * 1.5)
            ctx.arc(w * 0.44, b - h * 0.24, h * 0.17, Math.PI * 1.15, Math.PI * 1.85)
            ctx.arc(w * 0.66, b - h * 0.20, h * 0.14, Math.PI * 1.3, Math.PI * 1.95)
            ctx.arc(w * 0.76, b - h * 0.10, h * 0.10, Math.PI * 1.5, Math.PI / 2)
            ctx.closePath()
            ctx.stroke()
        }
    }
}
