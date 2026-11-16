import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "js/weather.js" as W

ApplicationWindow {
    id: app

    // ---- persistent settings ----------------------------------------------
    ConfigurationGroup {
        id: settings
        path: "/apps/harbour-weatherchart"
        property string locations: "[]"     // JSON [{name, lat, lon}]
        property int currentLocation: 0
        property int days: 3                // 3 or 7
        property string mode: "temp"        // temp | wind | clouds
        property string model: "best_match"
        property string cache: ""           // JSON {key, data}
    }

    // ---- state -------------------------------------------------------------
    property var locationList: []           // parsed settings.locations
    property var location: null             // {name, lat, lon}
    property var forecast: null             // parsed forecast (W.parseForecast)
    property bool loading: false
    property string errorText: ""
    property int selectedIndex: -1          // hour index selected by tapping the chart
    property int nowIndex: forecast ? W.indexNow(forecast.hours, clock.now) : -1
    readonly property string lang: Qt.locale().name
    readonly property int days: settings.days
    readonly property string mode: settings.mode

    // record shown in the header: selected or current
    readonly property var shownRecord: forecast && forecast.hours.length
                                       ? forecast.hours[selectedIndex >= 0 ? selectedIndex : Math.max(0, nowIndex)]
                                       : null

    allowedOrientations: Orientation.Portrait
    _defaultPageOrientations: Orientation.Portrait
    initialPage: Qt.resolvedUrl("pages/MainPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")

    // "now" ticks once a minute so the now-line moves
    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: {
            clock.now = Date.now()
            // auto refresh every 10 minutes, also while minimized (cover visible)
            if (forecast && Date.now() - forecast.fetched > 10 * 60000)
                refresh()
        }
    }
    Connections {
        target: Qt.application
        onActiveChanged: if (Qt.application.active) {
            clock.now = Date.now()
            if (!forecast || Date.now() - forecast.fetched > 10 * 60000) refresh()
        }
    }

    // ---- locations ---------------------------------------------------------
    function loadLocations() {
        try { locationList = JSON.parse(settings.locations) } catch (e) { locationList = [] }
        if (!locationList.length) {
            locationList = [{ name: "Praha", lat: 50.0875, lon: 14.4213 }]
            saveLocations()
        }
        var i = Math.min(Math.max(0, settings.currentLocation), locationList.length - 1)
        location = locationList[i]
    }
    function saveLocations() {
        settings.locations = JSON.stringify(locationList)
    }
    function selectLocation(i) {
        if (i < 0 || i >= locationList.length) return
        settings.currentLocation = i
        location = locationList[i]
        selectedIndex = -1
        forecast = null
        loadCache()
        refresh()
    }
    function addLocation(loc, select) {
        var list = locationList.slice()
        // replace existing with same coords (within ~1 km)
        var idx = -1
        for (var i = 0; i < list.length; i++)
            if (Math.abs(list[i].lat - loc.lat) < 0.01 && Math.abs(list[i].lon - loc.lon) < 0.01) idx = i
        if (idx >= 0) list[idx] = loc; else { list.push(loc); idx = list.length - 1 }
        locationList = list
        saveLocations()
        if (select) selectLocation(idx)
    }
    function removeLocation(i) {
        var list = locationList.slice()
        list.splice(i, 1)
        locationList = list
        saveLocations()
        var cur = settings.currentLocation
        if (!list.length) { loadLocations(); selectLocation(0); return }
        if (i === cur) selectLocation(0)
        else if (i < cur) settings.currentLocation = cur - 1
    }
    // temporary (GPS) location: shown but not necessarily saved
    function useTemporaryLocation(loc) {
        location = loc
        selectedIndex = -1
        forecast = null
        refresh()
    }

    // ---- forecast ----------------------------------------------------------
    function cacheKey() {
        return location ? location.lat.toFixed(3) + "," + location.lon.toFixed(3) + "," + settings.model : ""
    }
    function loadCache() {
        try {
            var c = JSON.parse(settings.cache)
            if (c && c.key === cacheKey() && c.data) forecast = c.data
        } catch (e) {}
    }
    function refresh() {
        if (!location || loading) return
        loading = true
        errorText = ""
        var key = cacheKey()
        W.getJson(W.forecastUrl(location.lat, location.lon, settings.model), function (err, raw) {
            loading = false
            if (key !== cacheKey()) return   // location changed meanwhile
            if (err) {
                errorText = err
                return
            }
            try {
                forecast = W.parseForecast(raw)
                settings.cache = JSON.stringify({ key: key, data: forecast })
                if (selectedIndex >= forecast.hours.length) selectedIndex = -1
            } catch (e) {
                errorText = "" + e
            }
        })
    }

    function setDays(d) { settings.days = d; selectedIndex = -1 }
    function setMode(m) { settings.mode = m }
    function setModel(m) {
        if (settings.model === m) return
        settings.model = m
        forecast = null
        selectedIndex = -1
        refresh()
    }

    Component.onCompleted: {
        loadLocations()
        loadCache()
        refresh()
    }
}
