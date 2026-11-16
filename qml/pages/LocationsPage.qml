import QtQuick 2.2
import Sailfish.Silica 1.0
import QtPositioning 5.2
import "../js/weather.js" as W

// Saved locations, place search (Open-Meteo geocoding) and GPS position.
Page {
    id: page

    property var results: []        // search results [{name, lat, lon, detail}]
    property bool searching: false
    property string searchError: ""
    property bool gpsWaiting: false
    property string searchText: ""
    readonly property bool showResults: searchText.length >= 2

    PositionSource {
        id: gps
        updateInterval: 2000
        active: false
        onPositionChanged: {
            if (!position.latitudeValid || !position.longitudeValid) return
            if (!gpsWaiting) return
            gpsWaiting = false
            active = false
            var lat = position.coordinate.latitude, lon = position.coordinate.longitude
            var loc = { name: W.tr("my_location", app.lang), lat: lat, lon: lon, gps: true }
            // try to resolve a name (Nominatim); fall back to coordinates
            W.getJson(W.reverseUrl(lat, lon, app.lang), function (err, j) {
                if (!err && j && j.address) {
                    var a = j.address
                    loc.name = a.city || a.town || a.village || a.municipality || a.hamlet || a.county || j.name || loc.name
                } else {
                    loc.name = lat.toFixed(3) + ", " + lon.toFixed(3)
                }
                app.addLocation(loc, true)
                pageStack.pop()
            })
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                gpsWaiting = false
                active = false
                searchError = W.tr("position_unavailable", app.lang)
            }
        }
    }
    Timer {
        id: gpsTimeout
        interval: 30000
        onTriggered: if (gpsWaiting) { gpsWaiting = false; gps.active = false; searchError = W.tr("position_timeout", app.lang) }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: search()
    }

    function search() {
        var q = searchText.trim()
        if (q.length < 2) { results = []; return }
        searching = true
        searchError = ""
        W.getJson(W.geocodeUrl(q, app.lang), function (err, j) {
            searching = false
            if (q !== searchText.trim()) return
            if (err) { searchError = err; results = []; return }
            var out = []
            var rs = (j && j.results) || []
            for (var i = 0; i < rs.length; i++) {
                var r = rs[i]
                var parts = []
                if (r.admin1) parts.push(r.admin1)
                if (r.country) parts.push(r.country)
                out.push({ name: r.name, lat: r.latitude, lon: r.longitude,
                           detail: parts.join(", ") + (r.elevation !== undefined ? " · " + Math.round(r.elevation) + " m" : "") })
            }
            results = out
        })
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: showResults ? results : app.locationList
        currentIndex: -1

        header: Column {
            width: page.width
            PageHeader { title: W.tr("locations", app.lang) }
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: W.tr("search_place", app.lang)
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: { focus = false; search() }
                onTextChanged: { page.searchText = text; if (text.length >= 2) debounce.restart(); else results = [] }
            }
            BackgroundItem {
                width: parent.width
                visible: !showResults
                onClicked: {
                    searchError = ""
                    gpsWaiting = true
                    gps.active = true
                    gpsTimeout.restart()
                }
                Row {
                    x: Theme.horizontalPageMargin
                    height: parent.height
                    spacing: Theme.paddingMedium
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-gps"
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: gpsWaiting ? W.tr("waiting_position", app.lang) : W.tr("use_current", app.lang)
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    BusyIndicator {
                        anchors.verticalCenter: parent.verticalCenter
                        size: BusyIndicatorSize.Small
                        running: gpsWaiting
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: searchError.length > 0
                text: searchError
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
            SectionHeader {
                text: showResults ? W.tr("results", app.lang) : W.tr("saved_locations", app.lang)
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Theme.itemSizeMedium
            readonly property bool isCurrent: !showResults && app.location
                                              && Math.abs(app.location.lat - modelData.lat) < 1e-6
                                              && Math.abs(app.location.lon - modelData.lon) < 1e-6
            menu: showResults ? null : ctxMenu
            onClicked: {
                if (showResults) {
                    app.addLocation({ name: modelData.name, lat: modelData.lat, lon: modelData.lon }, true)
                } else {
                    app.selectLocation(index)
                }
                pageStack.pop()
            }
            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x - (showResults ? 0 : Theme.itemSizeSmall)
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    text: modelData.name
                    color: (item.highlighted || item.isCurrent) ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: showResults ? modelData.detail
                                      : modelData.lat.toFixed(3) + ", " + modelData.lon.toFixed(3)
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
            // visible remove button for saved locations (in addition to the long-press menu)
            Item {
                id: removeBtn
                visible: !showResults
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.itemSizeSmall
                height: Theme.itemSizeSmall
                Icon {
                    anchors.centerIn: parent
                    source: "image://theme/icon-m-remove"
                    highlighted: removeMouse.pressed
                }
                MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    onClicked: item.remorseAction(W.tr("removing", app.lang), function () { app.removeLocation(index) })
                }
            }
            Component {
                id: ctxMenu
                ContextMenu {
                    MenuItem {
                        text: W.tr("remove", app.lang)
                        onClicked: item.remorseAction(W.tr("removing", app.lang), function () { app.removeLocation(index) })
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0 && !searching
            text: showResults ? W.tr("no_places", app.lang) : W.tr("no_saved", app.lang)
        }
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: searching && list.count === 0
        }
        VerticalScrollDecorator {}
    }
}
