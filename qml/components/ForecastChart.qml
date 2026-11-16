import QtQuick 2.2
import Sailfish.Silica 1.0
import "../js/weather.js" as W

// Klara-style forecast chart.
//  - row of weather icons (theme icons) on top
//  - hour labels, alternating day bands, day labels at the bottom
//  - mode "temp":   temperature curve, orange above 0 °C and blue below,
//                   fill towards the zero line, extremes labelled
//  - mode "wind":   wind speed curve (m/s), gusts as thin line, direction arrows
//  - mode "clouds": symmetric grey cloud-cover band
//  - precipitation bars at the bottom in all modes: blue = rain, white = snow
//  - dashed vertical line = now; the solid selection line (signal tapped) is
//    an overlay item, not drawn on the canvas
Item {
    id: chart

    property var hours: []          // array from W.parseForecast().hours
    property int startIndex: 0
    property int count: 72
    property string mode: "temp"
    property int nowIndex: -1
    property real nowTime: Date.now()
    property int selectedIndex: -1
    property string lang: "cs"
    property bool compact: false    // cover: no labels/icons

    signal tapped(int index)

    readonly property int endIndex: Math.min(hours.length, startIndex + count)
    readonly property int visibleCount: Math.max(1, endIndex - startIndex)
    readonly property real slotW: width / visibleCount
    readonly property int iconStep: count > 96 ? 6 : 3
    // Icons are laid out in two staggered rows (like Klara) so each icon may
    // be up to two steps wide.
    readonly property real iconSize: compact ? 0 : Math.min(Theme.iconSizeMedium, slotW * iconStep * 1.9)
    readonly property real iconRowH: compact ? 0 : iconSize * 2 + Theme.paddingSmall
    readonly property real labelH: compact ? 0 : Theme.fontSizeTiny + Theme.paddingSmall

    // colours
    readonly property color warmColor: "#ffb24a"
    readonly property color coldColor: "#5fb3ff"
    readonly property color rainColor: "#4a90ff"
    readonly property color snowColor: "#ffffff"
    readonly property color windColor: "#3dbfae"
    readonly property color cloudColor: Theme.rgba(Theme.primaryColor, 0.45)

    onHoursChanged: canvas.requestPaint()
    onStartIndexChanged: canvas.requestPaint()
    onCountChanged: canvas.requestPaint()
    onModeChanged: canvas.requestPaint()
    onNowTimeChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    function xOfTime(t) {
        // x position of an absolute time inside the visible range
        if (!hours.length) return -1
        var first = hours[startIndex].time
        return (t - first) / 3600000 * slotW
    }
    function indexAtX(x) {
        var i = startIndex + Math.floor(x / slotW)
        return Math.max(startIndex, Math.min(endIndex - 1, i))
    }

    // ---- weather icons -----------------------------------------------------
    Item {
        id: iconRow
        visible: !compact
        height: iconRowH
        width: parent.width
        Repeater {
            model: compact ? 0 : Math.ceil(visibleCount / iconStep)
            delegate: Image {
                // centre of the step; odd steps go to the lower row
                x: (index + 0.5) * slotW * iconStep - width / 2
                y: (index % 2) * iconSize
                width: iconSize
                height: iconSize
                sourceSize.width: Theme.iconSizeMedium
                sourceSize.height: Theme.iconSizeMedium
                fillMode: Image.PreserveAspectFit
                source: {
                    // most significant weather within the step: pick the hour
                    // with the highest WMO code (precip/thunder beat clouds)
                    var best = null
                    for (var i = startIndex + index * iconStep; i < Math.min(endIndex, startIndex + (index + 1) * iconStep); i++) {
                        var r = hours[i]
                        if (!best || r.code > best.code) best = r
                    }
                    var mid = hours[Math.min(endIndex - 1, startIndex + index * iconStep + Math.floor(iconStep / 2))]
                    return best ? W.iconSource(best.code, mid ? mid.isDay : best.isDay, "m") : ""
                }
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        function dashedLine(ctx, x, y0, y1, dash) {
            ctx.beginPath()
            for (var y = y0; y < y1; y += dash * 2) {
                ctx.moveTo(x, y)
                ctx.lineTo(x, Math.min(y1, y + dash))
            }
            ctx.stroke()
        }

        // returns [[index, value, isMax], ...] of local extremes with spacing
        function extremes(series, minGap) {
            var res = []
            var n = series.length
            var lastMaxI = -100, lastMinI = -100
            for (var i = 0; i < n; i++) {
                var v = series[i]
                var isMax = true, isMin = true
                for (var k = Math.max(0, i - 3); k <= Math.min(n - 1, i + 3); k++) {
                    if (k === i) continue
                    if (series[k] > v || (series[k] === v && k < i)) isMax = false
                    if (series[k] < v || (series[k] === v && k < i)) isMin = false
                }
                if (isMax && i - lastMaxI >= minGap) { res.push([i, v, true]); lastMaxI = i }
                else if (isMin && i - lastMinI >= minGap) { res.push([i, v, false]); lastMinI = i }
            }
            return res
        }

        function curvePath(ctx, xs, ys) {
            ctx.moveTo(xs[0], ys[0])
            for (var i = 1; i < xs.length; i++) {
                // smooth with midpoint quadratic curves
                var xc = (xs[i - 1] + xs[i]) / 2, yc = (ys[i - 1] + ys[i]) / 2
                ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], xc, yc)
            }
            ctx.lineTo(xs[xs.length - 1], ys[ys.length - 1])
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (!hours || !hours.length || endIndex <= startIndex) return

            var W_ = width, H = height
            var top = iconRowH + labelH          // plot top (below icons + hour row)
            var bottom = H - labelH              // plot bottom (above day row)
            var plotH = bottom - top
            var n = visibleCount
            var primary = Theme.primaryColor
            var secondary = Theme.secondaryColor
            var tiny = Theme.fontSizeTiny
            var small = Theme.fontSizeExtraSmall
            var fontFamily = Theme.fontFamily
            var i, r, x

            // --- day bands + grid ------------------------------------------
            var dayStarts = []   // [x, dateStr]
            for (i = startIndex; i < endIndex; i++) {
                r = hours[i]
                if (i === startIndex || r.localHour === 0)
                    dayStarts.push([(i - startIndex) * slotW, r.localDate, r.localHour])
            }
            for (i = 0; i < dayStarts.length; i++) {
                var x0 = dayStarts[i][0]
                var x1 = i + 1 < dayStarts.length ? dayStarts[i + 1][0] : W_
                var dow = new Date(dayStarts[i][1] + "T12:00:00Z").getUTCDay()
                if (dow % 2 === 1) {
                    ctx.fillStyle = Theme.rgba(primary, 0.06)
                    ctx.fillRect(x0, top, x1 - x0, plotH)
                }
                if (dow === 0 || dow === 6) {
                    ctx.fillStyle = Theme.rgba(Theme.highlightColor, 0.05)
                    ctx.fillRect(x0, top, x1 - x0, plotH)
                }
                // midnight line
                if (i > 0) {
                    ctx.strokeStyle = Theme.rgba(primary, 0.35)
                    ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(x0 + 0.5, iconRowH); ctx.lineTo(x0 + 0.5, H); ctx.stroke()
                }
                // day label (bottom row)
                if (!compact) {
                    var label = W.dayShort(dayStarts[i][1], lang)
                    ctx.font = "bold " + small + "px " + fontFamily
                    ctx.fillStyle = primary
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    var cx = (x0 + x1) / 2
                    if (x1 - x0 > ctx.measureText(label).width + 4)
                        ctx.fillText(label, cx, bottom + labelH / 2)
                }
            }
            // hour grid + labels
            var hourStep = count > 96 ? 12 : 6
            ctx.font = tiny + "px " + fontFamily
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (i = startIndex; i < endIndex; i++) {
                r = hours[i]
                if (r.localHour % hourStep === 0 && r.localHour !== 0) {
                    x = (i - startIndex) * slotW
                    ctx.strokeStyle = Theme.rgba(primary, 0.12)
                    ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(x + 0.5, top); ctx.lineTo(x + 0.5, bottom); ctx.stroke()
                    if (!compact) {
                        var htw = ctx.measureText("" + r.localHour).width
                        if (x - htw / 2 >= 0 && x + htw / 2 <= W_) {
                            ctx.fillStyle = secondary
                            ctx.fillText("" + r.localHour, x, iconRowH + labelH / 2)
                        }
                    }
                }
            }
            // horizontal grid (4 lines)
            ctx.strokeStyle = Theme.rgba(primary, 0.10)
            for (i = 1; i < 4; i++) {
                var gy = Math.round(top + plotH * i / 4) + 0.5
                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(W_, gy); ctx.stroke()
            }

            // --- series arrays ---------------------------------------------
            var xs = [], temps = [], winds = [], gusts = [], clouds = []
            for (i = startIndex; i < endIndex; i++) {
                r = hours[i]
                xs.push((i - startIndex + 0.5) * slotW)
                temps.push(r.temp); winds.push(r.wind); gusts.push(r.gust); clouds.push(r.clouds)
            }

            // --- main series ------------------------------------------------
            var areaTop = top + plotH * 0.08
            var areaBottom = top + plotH * 0.72
            var areaH = areaBottom - areaTop

            if (mode === "temp") {
                var tmin = Math.min.apply(null, temps), tmax = Math.max.apply(null, temps)
                var span = Math.max(8, tmax - tmin)
                var mid = (tmax + tmin) / 2
                var lo = mid - span / 2, hi = mid + span / 2
                var ty = function (v) { return areaBottom - (v - lo) / (hi - lo) * areaH }
                var ys = temps.map(ty)
                var zeroIn = lo < 0 && hi > 0
                var y0 = zeroIn ? ty(0) : (lo >= 0 ? bottom : areaTop)

                // freezing zone band
                if (zeroIn || hi <= 0) {
                    ctx.fillStyle = Theme.rgba(coldColor, 0.10)
                    ctx.fillRect(0, zeroIn ? y0 : top, W_, (zeroIn ? bottom - y0 : plotH))
                    ctx.strokeStyle = Theme.rgba(coldColor, 0.7)
                    ctx.lineWidth = 1
                    if (zeroIn) { ctx.beginPath(); ctx.moveTo(0, Math.round(y0) + 0.5); ctx.lineTo(W_, Math.round(y0) + 0.5); ctx.stroke() }
                }
                // fill between curve and baseline: warm part (above y0)
                ctx.save()
                ctx.beginPath(); ctx.rect(0, 0, W_, y0); ctx.clip()
                ctx.beginPath()
                curvePath(ctx, xs, ys)
                ctx.lineTo(xs[xs.length - 1], y0); ctx.lineTo(xs[0], y0); ctx.closePath()
                ctx.fillStyle = Theme.rgba(warmColor, 0.45)
                ctx.fill()
                ctx.restore()
                // cold part (below y0)
                ctx.save()
                ctx.beginPath(); ctx.rect(0, y0, W_, H - y0); ctx.clip()
                ctx.beginPath()
                curvePath(ctx, xs, ys)
                ctx.lineTo(xs[xs.length - 1], y0); ctx.lineTo(xs[0], y0); ctx.closePath()
                ctx.fillStyle = Theme.rgba(coldColor, 0.40)
                ctx.fill()
                ctx.restore()
                // curve stroke in two colours
                ctx.lineWidth = Math.max(2, Theme.paddingSmall / 3)
                ctx.lineJoin = "round"
                ctx.save()
                ctx.beginPath(); ctx.rect(0, 0, W_, y0); ctx.clip()
                ctx.strokeStyle = warmColor
                ctx.beginPath(); curvePath(ctx, xs, ys); ctx.stroke()
                ctx.restore()
                ctx.save()
                ctx.beginPath(); ctx.rect(0, y0, W_, H - y0); ctx.clip()
                ctx.strokeStyle = coldColor
                ctx.beginPath(); curvePath(ctx, xs, ys); ctx.stroke()
                ctx.restore()
                // labels of extremes
                if (!compact) {
                    var ex = extremes(temps, count > 96 ? 9 : 5)
                    ctx.font = small + "px " + fontFamily
                    ctx.textAlign = "center"
                    for (i = 0; i < ex.length; i++) {
                        var e = ex[i]
                        ctx.fillStyle = e[1] < 0 ? coldColor : primary
                        ctx.textBaseline = e[2] ? "bottom" : "top"
                        var lx = Math.min(W_ - 12, Math.max(12, xs[e[0]]))
                        ctx.fillText("" + Math.round(e[1]), lx, ys[e[0]] + (e[2] ? -4 : 4))
                    }
                }
            } else if (mode === "wind") {
                var wmax = Math.max(5, Math.max.apply(null, gusts))
                var wy = function (v) { return areaBottom - v / wmax * areaH }
                var wys = winds.map(wy), gys = gusts.map(wy)
                ctx.beginPath()
                curvePath(ctx, xs, wys)
                ctx.lineTo(xs[xs.length - 1], areaBottom); ctx.lineTo(xs[0], areaBottom); ctx.closePath()
                ctx.fillStyle = Theme.rgba(windColor, 0.45)
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Theme.rgba(warmColor, 0.7)
                ctx.beginPath(); curvePath(ctx, xs, gys); ctx.stroke()
                ctx.lineWidth = Math.max(2, Theme.paddingSmall / 3)
                ctx.strokeStyle = windColor
                ctx.beginPath(); curvePath(ctx, xs, wys); ctx.stroke()
                // direction arrows along the top of the plot
                var step = count > 96 ? 6 : 3
                var ar = Math.min(slotW * step * 0.4, small * 0.8)
                var ay = top + plotH * 0.04 + ar
                ctx.strokeStyle = primary
                ctx.fillStyle = primary
                ctx.lineWidth = 1.5
                for (i = startIndex + Math.floor(step / 2); i < endIndex; i += step) {
                    r = hours[i]
                    var ax = xs[i - startIndex]
                    var ang = (r.windDir + 180) * Math.PI / 180   // blowing towards
                    ctx.save()
                    ctx.translate(ax, ay)
                    ctx.rotate(ang)
                    ctx.beginPath()
                    ctx.moveTo(0, ar); ctx.lineTo(0, -ar)
                    ctx.moveTo(-ar * 0.5, -ar * 0.4); ctx.lineTo(0, -ar); ctx.lineTo(ar * 0.5, -ar * 0.4)
                    ctx.stroke()
                    ctx.restore()
                }
                if (!compact) {
                    var wex = extremes(winds, count > 96 ? 9 : 5)
                    ctx.font = small + "px " + fontFamily
                    ctx.textAlign = "center"
                    ctx.fillStyle = primary
                    for (i = 0; i < wex.length; i++) {
                        ctx.textBaseline = wex[i][2] ? "bottom" : "top"
                        ctx.fillText((Math.round(wex[i][1] * 10) / 10).toString(),
                                     Math.min(W_ - 14, Math.max(14, xs[wex[i][0]])), wys[wex[i][0]] + (wex[i][2] ? -4 : 4))
                    }
                }
            } else {
                // clouds: symmetric band
                var cmid = top + plotH * 0.38
                var chalf = plotH * 0.30
                var up = [], down = []
                for (i = 0; i < clouds.length; i++) {
                    var hh = Math.max(1, clouds[i] / 100 * chalf)
                    up.push(cmid - hh); down.push(cmid + hh)
                }
                ctx.beginPath()
                curvePath(ctx, xs, up)
                // back along the bottom edge
                var rx = xs.slice().reverse(), rd = down.slice().reverse()
                ctx.lineTo(rx[0], rd[0])
                for (i = 1; i < rx.length; i++) {
                    var xc2 = (rx[i - 1] + rx[i]) / 2, yc2 = (rd[i - 1] + rd[i]) / 2
                    ctx.quadraticCurveTo(rx[i - 1], rd[i - 1], xc2, yc2)
                }
                ctx.closePath()
                ctx.fillStyle = cloudColor
                ctx.fill()
                ctx.strokeStyle = Theme.rgba(primary, 0.7)
                ctx.lineWidth = 1.5
                ctx.stroke()

                // temperature curve on top of the clouds (same scale and colours as temp mode)
                var tcMin = Math.min.apply(null, temps), tcMax = Math.max.apply(null, temps)
                var tcSpan = Math.max(8, tcMax - tcMin), tcMid = (tcMax + tcMin) / 2
                var tcLo = tcMid - tcSpan / 2, tcHi = tcMid + tcSpan / 2
                var tcY = function (v) { return areaBottom - (v - tcLo) / (tcHi - tcLo) * areaH }
                var tcYs = temps.map(tcY)
                var tcY0 = tcLo >= 0 ? bottom : (tcHi <= 0 ? areaTop : tcY(0))
                ctx.lineWidth = Math.max(2, Theme.paddingSmall / 3)
                ctx.lineJoin = "round"
                ctx.save()
                ctx.beginPath(); ctx.rect(0, 0, W_, tcY0); ctx.clip()
                ctx.strokeStyle = warmColor
                ctx.beginPath(); curvePath(ctx, xs, tcYs); ctx.stroke()
                ctx.restore()
                ctx.save()
                ctx.beginPath(); ctx.rect(0, tcY0, W_, H - tcY0); ctx.clip()
                ctx.strokeStyle = coldColor
                ctx.beginPath(); curvePath(ctx, xs, tcYs); ctx.stroke()
                ctx.restore()
            }

            // --- precipitation bars (bottom ~30 %) --------------------------
            var precipH = plotH * 0.30
            var pmaxVal = 0
            var pmaxI = -1
            for (i = startIndex; i < endIndex; i++) {
                if (hours[i].precip > pmaxVal) { pmaxVal = hours[i].precip; pmaxI = i }
            }
            // scale: at least 2 mm/h so drizzle does not fill the whole band
            var pmax = Math.max(2.0, pmaxVal)
            var barW = Math.max(1, slotW * 0.75)
            for (i = startIndex; i < endIndex; i++) {
                r = hours[i]
                if (r.precip <= 0) continue
                x = (i - startIndex) * slotW + (slotW - barW) / 2
                var hRain = r.rain / pmax * precipH
                var hSnow = r.snowWater / pmax * precipH
                var y = bottom
                if (hRain > 0) {
                    ctx.fillStyle = rainColor
                    ctx.fillRect(x, y - hRain, barW, hRain)
                    y -= hRain
                }
                if (hSnow > 0) {
                    ctx.fillStyle = snowColor
                    ctx.fillRect(x, y - hSnow, barW, hSnow)
                    ctx.strokeStyle = rainColor
                    ctx.lineWidth = 1
                    ctx.strokeRect(x + 0.5, y - hSnow + 0.5, barW - 1, hSnow - 1)
                }
            }
            if (!compact && pmaxI >= 0 && hours[pmaxI].precip > 0) {
                ctx.font = tiny + "px " + fontFamily
                ctx.fillStyle = rainColor
                ctx.textAlign = "center"
                ctx.textBaseline = "bottom"
                var pr = hours[pmaxI]
                var snowy = pr.snow > 0 && pr.snowWater >= pr.rain
                var ptxt = snowy ? (Math.round(pr.snow * 10) / 10) + " cm"
                                 : (Math.round(pr.precip * 10) / 10) + " mm"
                var px = xs[pmaxI - startIndex]
                var tw = ctx.measureText(ptxt).width
                if (px - tw / 2 < 2) { ctx.textAlign = "left"; px = 2 }
                else if (px + tw / 2 > W_ - 2) { ctx.textAlign = "right"; px = W_ - 2 }
                ctx.fillText(ptxt, px, bottom - pr.precip / pmax * precipH - 2)
            }

            // --- now line (dashed) and selection line -------------------------
            var nx = xOfTime(nowTime)
            if (nx >= 0 && nx <= W_) {
                ctx.strokeStyle = Theme.rgba(primary, 0.8)
                ctx.lineWidth = 1.5
                dashedLine(ctx, Math.round(nx) + 0.5, iconRowH, bottom, 5)
            }
        }
    }

    // Selection line: plain items instead of canvas drawing, so dragging the
    // selection across the chart does not repaint the whole canvas.
    Item {
        id: selection
        visible: selectedIndex >= startIndex && selectedIndex < endIndex
        x: Math.round((selectedIndex - startIndex + 0.5) * slotW)
        y: iconRowH
        width: 1
        height: chart.height - labelH - iconRowH
        Rectangle {
            x: -1
            width: 2
            height: parent.height
            color: Theme.highlightColor
        }
        // downward triangle marker at the top (lower half of a rotated square)
        Item {
            x: -6
            width: 12
            height: 6
            clip: true
            Rectangle {
                width: 8.5
                height: 8.5
                anchors.horizontalCenter: parent.horizontalCenter
                y: -height / 2
                rotation: 45
                color: Theme.highlightColor
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !compact
        property int pressIndex: -1
        property bool moved: false
        onPressed: { pressIndex = indexAtX(mouse.x); moved = false }
        onPositionChanged: {
            if (!pressed) return
            var i = indexAtX(mouse.x)
            if (i !== pressIndex) moved = true
            if (moved) chart.tapped(i)
        }
        onClicked: {
            if (moved) return
            var i = indexAtX(mouse.x)
            chart.tapped(i === selectedIndex ? -1 : i)
        }
    }
}
