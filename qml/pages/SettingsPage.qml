import QtQuick 2.2
import Sailfish.Silica 1.0
import "../js/weather.js" as W

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height

        Column {
            id: col
            width: parent.width

            PageHeader { title: W.tr("settings", app.lang) }

            ComboBox {
                id: modelBox
                label: W.tr("forecast_model", app.lang)
                description: W.tr("model_desc", app.lang)
                currentIndex: {
                    for (var i = 0; i < W.MODELS.length; i++)
                        if (W.MODELS[i].id === settings.model) return i
                    return 0
                }
                menu: ContextMenu {
                    Repeater {
                        model: W.MODELS
                        MenuItem { text: modelData.key ? W.tr(modelData.key, app.lang) : modelData.name }
                    }
                }
                onCurrentIndexChanged: if (currentIndex >= 0) app.setModel(W.MODELS[currentIndex].id)
            }

            ComboBox {
                label: W.tr("default_range", app.lang)
                currentIndex: settings.days === 7 ? 1 : 0
                menu: ContextMenu {
                    MenuItem { text: W.tr("range_3", app.lang) }
                    MenuItem { text: W.tr("range_7", app.lang) }
                }
                onCurrentIndexChanged: app.setDays(currentIndex === 1 ? 7 : 3)
            }

            SectionHeader { text: W.tr("about", app.lang) }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                textFormat: Text.StyledText
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
                text: W.tr("about_text", app.lang).arg("1.1.3")
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
        VerticalScrollDecorator {}
    }
}
