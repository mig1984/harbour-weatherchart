import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"
import "../js/weather.js" as W

CoverBackground {
    id: cover

    readonly property var rec: app.forecast && app.nowIndex >= 0 ? app.forecast.hours[app.nowIndex] : null

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: 0
        Label {
            width: parent.width
            text: app.location ? app.location.name : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            truncationMode: TruncationMode.Fade
        }
        Row {
            spacing: Theme.paddingMedium
            Label {
                text: rec ? Math.round(rec.temp) + "°" : "–"
                font.pixelSize: Theme.fontSizeHuge
                color: rec && rec.temp < 0 ? "#5fb3ff" : Theme.primaryColor
            }
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeMedium
                height: width
                source: rec ? W.iconSource(rec.code, rec.isDay, "m") : ""
            }
        }
        Label {
            width: parent.width
            text: rec ? W.describe(rec.code, app.lang) : ""
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            truncationMode: TruncationMode.Fade
        }
    }

    ForecastChart {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: Theme.itemSizeSmall * 0.6 }
        height: cover.height * 0.42
        compact: true
        hours: app.forecast ? app.forecast.hours : []
        startIndex: Math.max(0, app.nowIndex - 2)
        count: 48
        mode: app.mode
        nowIndex: app.nowIndex
        selectedIndex: -1
        lang: app.lang
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: app.refresh()
        }
    }
}
