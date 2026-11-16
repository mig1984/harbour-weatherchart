import QtQuick 2.2
import Sailfish.Silica 1.0
import "../components"
import "../js/weather.js" as W

Page {
    id: page

    readonly property var rec: app.shownRecord
    readonly property bool selected: app.selectedIndex >= 0

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: app.days === 3 ? W.tr("forecast_7", app.lang) : W.tr("forecast_3", app.lang)
                onClicked: app.setDays(app.days === 3 ? 7 : 3)
            }
            MenuItem {
                text: W.tr("change_location", app.lang)
                onClicked: pageStack.push(Qt.resolvedUrl("LocationsPage.qml"))
            }
            MenuItem {
                text: W.tr("settings", app.lang)
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: W.tr("refresh", app.lang)
                enabled: !app.loading
                onClicked: app.refresh()
            }
        }

        Column {
            id: column
            width: page.width

            PageHeader {
                id: header
                title: app.location ? app.location.name : W.tr("weather", app.lang)
                description: rec ? W.timeLabel(rec, app.lang)
                                 : (app.loading ? W.tr("loading", app.lang) : "")
                // tap the header title to go to locations too
                MouseArea {
                    anchors.fill: parent
                    onClicked: pageStack.push(Qt.resolvedUrl("LocationsPage.qml"))
                }

                // ---- mode switch: top left, on the level of the location name
                Row {
                    id: modeRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.top: parent.top
                    anchors.topMargin: Theme.paddingLarge
                    spacing: Theme.paddingMedium
                    Repeater {
                        model: ["temp", "wind", "clouds"]
                        delegate: Item {
                            width: Theme.iconSizeSmall * 2 + Theme.paddingSmall
                            height: Theme.iconSizeSmall * 2 + Theme.paddingSmall
                            ModeIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                kind: modelData
                                active: app.mode === modelData
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.7
                                height: 3
                                radius: 1.5
                                color: Theme.highlightColor
                                visible: app.mode === modelData
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: app.setMode(modelData)
                            }
                        }
                    }
                }
            }

            // ---- current / selected values -----------------------------------
            Item {
                width: parent.width
                height: valuesBox.height + Theme.paddingMedium
                Rectangle {
                    // Klara-like accent bar left of the temperature
                    x: Theme.horizontalPageMargin - Theme.paddingMedium
                    y: Theme.paddingSmall
                    width: 4
                    height: bigTemp.height
                    color: rec && rec.temp < 0 ? "#5fb3ff" : "#ffb24a"
                    visible: !!rec
                }
                Column {
                    id: valuesBox
                    x: Theme.horizontalPageMargin
                    y: Theme.paddingSmall
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    spacing: 0
                    Row {
                        width: parent.width
                        spacing: Theme.paddingLarge
                        Label {
                            id: bigTemp
                            text: rec ? W.formatTemp(rec.temp) : (app.errorText ? "–" : "")
                            font.pixelSize: Theme.fontSizeHuge
                            color: selected ? Theme.highlightColor : Theme.primaryColor
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            visible: !!rec
                            Row {
                                spacing: Theme.paddingSmall
                                Label {
                                    text: W.tr("feels_like", app.lang)
                                    color: "#ffb24a"
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }
                                Label {
                                    text: rec ? W.formatTemp(rec.feels) : ""
                                    color: Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }
                            }
                            Row {
                                spacing: Theme.paddingSmall
                                Label {
                                    text: rec ? ((rec.snow > 0 && rec.snowWater >= rec.rain)
                                                 ? "\u2744 " + (Math.round(rec.snow * 10) / 10) + " cm/h"
                                                 : "\u25BC " + (Math.round(rec.precip * 10) / 10) + " mm/h")
                                              : ""
                                    color: rec && rec.precip > 0 ? "#4a90ff" : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }
                                Label {
                                    text: rec && rec.pop !== null && rec.pop !== undefined ? "(" + rec.pop + " %)" : ""
                                    color: Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        text: {
                            if (!rec) return app.errorText ? app.errorText : ""
                            if (app.mode === "wind")
                                return W.windName(rec.wind, app.lang) + " " + (Math.round(rec.wind * 10) / 10) + " m/s "
                                        + W.windDirName(rec.windDir, app.lang)
                                        + (rec.gust > rec.wind + 2 ? W.tr("gusts", app.lang).arg(Math.round(rec.gust)) : "")
                            if (app.mode === "clouds")
                                return W.cloudName(rec.clouds, app.lang) + " (" + rec.clouds + " %)"
                            return W.describe(rec.code, app.lang)
                        }
                        color: app.errorText && !rec ? Theme.errorColor : Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            // ---- chart ---------------------------------------------------------
            ForecastChart {
                id: chart
                width: page.width
                height: page.height - y - Theme.paddingLarge
                hours: app.forecast ? app.forecast.hours : []
                startIndex: Math.max(0, app.nowIndex - 2)
                count: app.days * 24
                mode: app.mode
                nowIndex: app.nowIndex
                nowTime: app.now
                selectedIndex: app.selectedIndex
                lang: app.lang
                onTapped: app.selectedIndex = index

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Large
                    running: app.loading && !app.forecast
                }
                Label {
                    anchors.centerIn: parent
                    visible: !app.loading && !app.forecast
                    text: app.errorText ? W.tr("could_not_load", app.lang) : ""
                    color: Theme.secondaryColor
                }
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }

        // small busy indicator at the top when refreshing with data shown
        BusyIndicator {
            anchors { top: parent.top; right: parent.right; margins: Theme.paddingLarge }
            size: BusyIndicatorSize.Small
            running: app.loading && !!app.forecast
        }
    }
}
