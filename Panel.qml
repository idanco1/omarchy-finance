import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "idanco.finance"
  ipcTarget: "idanco.finance"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar identifies this panel by the widget mounted in its slot.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- panel open/close contract (mirrors the built-in panels)

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- data state

  property var portfolioData: null
  property var detailData: null
  property var aiData: null
  property bool aiLoading: false
  property string view: "portfolio"       // "portfolio" | "detail"
  property string detailSymbol: ""
  property bool portfolioLoading: false
  property bool detailLoading: false
  property int chartDays: 1825
  property double nowMs: Date.now()

  readonly property string scriptPath: Qt.resolvedUrl("bin/finance-fetch").toString().replace("file://", "")

  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 5), 10) || 5)
  readonly property color positiveColor: setting("positiveColor", "#81c995")
  readonly property color negativeColor: setting("negativeColor", "#f28b82")
  readonly property color entryColor: setting("entryColor", "#e53935")
  readonly property color mutedColor: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
  readonly property color softColor: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
  readonly property color fgColor: root.bar ? root.bar.foreground : Color.foreground
  readonly property string panelFont: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var positions: portfolioData && portfolioData.ok ? (portfolioData.positions || []) : []
  readonly property var summary: portfolioData && portfolioData.ok ? portfolioData.portfolio : null
  readonly property var fxRates: portfolioData && portfolioData.ok ? (portfolioData.fx || []) : []
  readonly property var chartSeries: detailData && detailData.ok ? Model.tailSeries(detailData.series, chartDays) : []
  readonly property var market: portfolioData && portfolioData.ok ? (portfolioData.market || null) : null
  readonly property bool marketOpen: market ? market.state === "open" : true
  readonly property string marketLine: {
    if (!market) return ""
    if (market.state === "open")
      return " Market open · closes " + Model.openTime(market.nextClose, nowMs)
    var label = market.state === "premarket" ? "Pre-market"
              : market.state === "afterhours" ? "After hours" : "Market closed"
    return "󰖔 " + label + " · opens " + Model.openTime(market.nextOpen, nowMs)
  }

  // ---- bar pill state

  readonly property string label: {
    if (!portfolioData) return ""
    if (!portfolioData.ok) return " !"
    var d2d = summary ? summary.d2d : null
    var icon = marketOpen ? "" : "󰖔"
    return icon + " " + (d2d === null || d2d === undefined ? "" : Model.fmtPct(d2d))
  }
  readonly property color labelColor: {
    if (!portfolioData || !portfolioData.ok || !summary) return fgColor
    if (!marketOpen) return mutedColor
    return Model.pnlColor(summary.d2d, positiveColor, negativeColor, fgColor)
  }

  function pctColor(x) {
    return Model.pnlColor(x, positiveColor, negativeColor, softColor)
  }

  // ---- fetching

  function refresh() {
    nowMs = Date.now()
    if (portfolioProc.running) return
    portfolioLoading = true
    portfolioProc.command = ["python3", root.scriptPath, "portfolio"]
    portfolioProc.running = true
  }

  function forceRefresh() {
    if (portfolioProc.running) portfolioProc.running = false
    portfolioLoading = true
    portfolioProc.command = ["python3", root.scriptPath, "refresh-positions"]
    portfolioProc.running = true
  }

  function openDetail(symbol) {
    view = "detail"
    if (detailSymbol !== symbol) {
      detailData = null
      aiData = null
    }
    detailSymbol = symbol
    detailLoading = true
    if (detailProc.running) detailProc.running = false
    detailProc.command = ["python3", root.scriptPath, "detail", symbol]
    detailProc.running = true
    aiLoading = true
    if (aiProc.running) aiProc.running = false
    aiProc.command = ["python3", root.scriptPath, "ai", symbol, "--cached-only"]
    aiProc.running = true
  }

  // Generation is expensive (it runs the default agent), so it only starts
  // after the instant cache lookup misses, and never blocks the fast data.
  function startAiGeneration(force) {
    aiLoading = true
    if (aiProc.running) aiProc.running = false
    var cmd = ["python3", root.scriptPath, "ai", detailSymbol]
    if (force) cmd.push("--force")
    aiProc.command = cmd
    aiProc.running = true
  }

  function rerunAi() {
    aiData = null
    startAiGeneration(true)
  }

  function backToPortfolio() {
    view = "portfolio"
    if (detailProc.running) detailProc.running = false
    detailLoading = false
  }

  function openUrl(url) {
    if (!root.bar || !/^https?:\/\//.test(url)) return
    root.bar.run("xdg-open '" + url.replace(/'/g, "%27") + "'")
  }

  Process {
    id: portfolioProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.portfolioLoading = false
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.portfolioData = JSON.parse(raw)
        } catch (e) {
          root.portfolioData = { ok: false, error: "Fetcher returned invalid JSON" }
        }
      }
    }
  }

  Process {
    id: detailProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.detailLoading = false
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.detailData = JSON.parse(raw)
        } catch (e) {
          root.detailData = { ok: false, error: "Fetcher returned invalid JSON" }
        }
      }
    }
  }

  Process {
    id: aiProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.aiLoading = false; return }
        try {
          var parsed = JSON.parse(raw)
          if (parsed && parsed.miss === true) {
            Qt.callLater(function() { root.startAiGeneration(false) })
            return
          }
          root.aiData = parsed
        } catch (e) {
          root.aiData = { ok: false, error: "AI summary returned invalid JSON" }
        }
        root.aiLoading = false
      }
    }
  }

  // Off-hours the quotes barely move, so spawn the fetcher far less often
  // (it also answers from cache then — see finance-fetch).
  readonly property int effectiveRefreshMs: {
    var base = refreshMinutes * 60 * 1000
    if (!market || market.state === "open") return base
    if (market.state === "premarket" || market.state === "afterhours")
      return Math.max(base, 15 * 60 * 1000)
    return Math.max(base, 60 * 60 * 1000)
  }

  Timer {
    interval: root.effectiveRefreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.forceRefresh() }
    function detail(symbol: string): void {
      root.openFromHotkey()
      root.openDetail(symbol)
    }
  }

  // ---- UI

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight + Style.space(8))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.view === "detail") root.backToPortfolio()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(12)

          // ================= status / setup =================

          Text {
            visible: !root.portfolioData && root.portfolioLoading
            x: Style.space(16)
            text: "Loading portfolio…"
            color: root.mutedColor
            font.family: root.panelFont
            font.pixelSize: Style.font.body
            font.italic: true
          }

          Column {
            visible: root.portfolioData !== null && !root.portfolioData.ok
            x: Style.space(16)
            width: parent.width - Style.space(32)
            spacing: Style.space(6)

            Text {
              text: root.portfolioData && root.portfolioData.needsConfig
                ? "Finance plugin needs configuration"
                : "Failed to load portfolio"
              color: root.fgColor
              font.family: root.panelFont
              font.pixelSize: Style.font.title
            }
            Text {
              width: parent.width
              text: root.portfolioData ? String(root.portfolioData.error || "") : ""
              color: root.mutedColor
              font.family: root.panelFont
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
            }
          }

          // ================= portfolio page =================

          Column {
            visible: root.view === "portfolio" && root.summary !== null
            width: parent.width
            spacing: Style.space(12)

            // ---- hero: total value + period returns
            Item {
              width: parent.width
              height: Math.max(heroLeft.implicitHeight, heroRight.implicitHeight)

              Column {
                id: heroLeft
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "PORTFOLIO"
                  color: root.mutedColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: root.summary ? Model.fmtMoney(root.summary.value, root.portfolioData.baseCurrency) : "—"
                  color: root.fgColor
                  font.family: root.panelFont
                  font.pixelSize: 34
                  font.bold: true
                }
                Text {
                  visible: root.summary && Model.isNum(root.summary.unrealized)
                  text: root.summary ? (Model.fmtSignedMoney(root.summary.unrealized, root.portfolioData.baseCurrency) + " unrealized") : ""
                  color: root.summary ? root.pctColor(root.summary.unrealized) : root.mutedColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Row {
                id: heroRight
                anchors.right: parent.right
                anchors.rightMargin: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(24)

                Repeater {
                  model: [
                    { label: "DTD", key: "d2d" },
                    { label: "MTD", key: "mtd" },
                    { label: "YTD", key: "ytd" },
                    { label: "ALL", key: "all" }
                  ]

                  Column {
                    required property var modelData
                    spacing: Style.space(4)

                    Text {
                      text: modelData.label
                      color: root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                    }
                    Text {
                      text: root.summary ? Model.fmtPct(root.summary[modelData.key]) : "—"
                      color: root.summary ? root.pctColor(root.summary[modelData.key]) : root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.title
                    }
                  }
                }
              }
            }

            // ---- FX rates
            Item {
              width: parent.width
              height: fxRow.implicitHeight

              Row {
                id: fxRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(28)

                Repeater {
                  model: root.fxRates

                  Row {
                    required property var modelData
                    spacing: Style.space(6)

                    Text {
                      text: modelData.pair
                      color: root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      text: Model.fmtRate(modelData.rate)
                      color: root.fgColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      text: Model.fmtPct(modelData.d2d)
                      color: root.pctColor(modelData.d2d)
                      font.family: root.panelFont
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: root.fgColor
              opacity: 0.12
            }

            // ---- positions table
            Column {
              width: parent.width
              spacing: 0

              // header
              Item {
                width: parent.width
                height: Style.space(22)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter

                  Text { width: Style.space(112); text: "TICKER"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
                  Text { width: Style.space(74); text: "PRICE"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                  Text { width: Style.space(62); text: "DTD"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                  Text { width: Style.space(62); text: "MTD"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                  Text { width: Style.space(62); text: "YTD"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                  Text { width: Style.space(62); text: "ALL"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                  Text { width: Style.space(92); text: "VALUE"; color: root.mutedColor; font.family: root.panelFont; font.pixelSize: Style.font.caption; font.letterSpacing: 1; horizontalAlignment: Text.AlignRight }
                }
              }

              Repeater {
                model: root.positions

                Rectangle {
                  required property var modelData
                  width: parent.width
                  height: Style.space(34)
                  radius: Style.cornerRadius
                  color: rowArea.containsMouse ? Style.hoverFillFor(root.fgColor, Color.accent) : "transparent"

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter

                    Column {
                      width: Style.space(112)
                      spacing: 0

                      Text {
                        text: modelData.symbol
                        color: root.fgColor
                        font.family: root.panelFont
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                      Text {
                        visible: text !== ""
                        width: Style.space(106)
                        text: modelData.error ? "no data" : (modelData.name || "")
                        color: root.mutedColor
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text { width: Style.space(74); text: Model.fmtPrice(modelData.price); color: root.fgColor; font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                    Text { width: Style.space(62); text: Model.fmtPct(modelData.d2d); color: root.pctColor(modelData.d2d); font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                    Text { width: Style.space(62); text: Model.fmtPct(modelData.mtd); color: root.pctColor(modelData.mtd); font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                    Text { width: Style.space(62); text: Model.fmtPct(modelData.ytd); color: root.pctColor(modelData.ytd); font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                    Text { width: Style.space(62); text: Model.fmtPct(modelData.unrealizedPct); color: root.pctColor(modelData.unrealizedPct); font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                    Column {
                      width: Style.space(92)
                      spacing: 0

                      Text { width: parent.width; text: Model.fmtMoney(modelData.value, modelData.currency); color: root.fgColor; font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
                      Text {
                        visible: Model.isNum(modelData.unrealized)
                        width: parent.width
                        text: Model.fmtSignedMoney(modelData.unrealized, modelData.currency)
                        color: root.pctColor(modelData.unrealized)
                        font.family: root.panelFont
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignRight
                      }
                    }
                  }

                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail(modelData.symbol)
                  }
                }
              }
            }

            // ---- footer
            Item {
              width: parent.width
              height: footerText.implicitHeight

              Text {
                id: footerText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                width: parent.width - Style.space(32)
                text: {
                  var bits = []
                  if (root.marketLine !== "") bits.push(root.marketLine)
                  if (root.portfolioData) {
                    bits.push("Updated " + Model.clockTime(root.portfolioData.asOf)
                              + " · " + (root.portfolioData.source === "ibkr-flex" ? "IBKR Flex" : root.portfolioData.source))
                    if (root.portfolioData.warning) bits.push("⚠ " + root.portfolioData.warning)
                  }
                  bits.push("Click a ticker for chart & news · middle-click pill to refresh positions")
                  return bits.join("\n")
                }
                color: root.mutedColor
                font.family: root.panelFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // ================= detail page =================

          Column {
            visible: root.view === "detail"
            width: parent.width
            spacing: Style.space(12)

            // ---- back + title row
            Item {
              width: parent.width
              height: Style.space(30)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Rectangle {
                  width: backLabel.implicitWidth + Style.space(16)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: backArea.containsMouse ? Style.hoverFillFor(root.fgColor, Color.accent) : "transparent"
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: backLabel
                    anchors.centerIn: parent
                    text: "← ALL"
                    color: root.mutedColor
                    font.family: root.panelFont
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }
                  MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.backToPortfolio()
                  }
                }

                Text {
                  text: root.detailSymbol
                  color: root.fgColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.title
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  width: Math.min(implicitWidth, Style.space(220))
                  text: root.detailData && root.detailData.ok ? (root.detailData.name || "") : ""
                  color: root.mutedColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              // range buttons
              Row {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { label: "1M", days: 31 },
                    { label: "6M", days: 183 },
                    { label: "1Y", days: 365 },
                    { label: "5Y", days: 1825 }
                  ]

                  Rectangle {
                    required property var modelData
                    width: rangeLabel.implicitWidth + Style.space(14)
                    height: Style.space(22)
                    radius: Style.cornerRadius
                    color: root.chartDays === modelData.days
                      ? Style.hoverFillFor(root.fgColor, Color.accent)
                      : (rangeArea.containsMouse ? Style.hoverFillFor(root.fgColor, Color.accent) : "transparent")
                    opacity: root.chartDays === modelData.days ? 1.0 : 0.7

                    Text {
                      id: rangeLabel
                      anchors.centerIn: parent
                      text: modelData.label
                      color: root.chartDays === modelData.days ? root.fgColor : root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: rangeArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.chartDays = modelData.days
                    }
                  }
                }
              }
            }

            Text {
              visible: root.detailLoading && !root.detailData
              x: Style.space(16)
              text: "Loading " + root.detailSymbol + "…"
              color: root.mutedColor
              font.family: root.panelFont
              font.pixelSize: Style.font.body
              font.italic: true
            }

            Text {
              visible: root.detailData !== null && !root.detailData.ok
              x: Style.space(16)
              width: parent.width - Style.space(32)
              text: root.detailData ? ("Failed to load: " + String(root.detailData.error || "")) : ""
              color: root.mutedColor
              font.family: root.panelFont
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
            }

            // ---- stat chips
            Item {
              visible: root.detailData !== null && root.detailData.ok
              width: parent.width
              height: statRow.implicitHeight

              Row {
                id: statRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                spacing: Style.space(22)

                Repeater {
                  model: !root.detailData || !root.detailData.ok ? [] : [
                    { label: "PRICE", value: Model.fmtPrice(root.detailData.price), tint: root.fgColor },
                    { label: "DTD", value: Model.fmtPct(root.detailData.d2d), tint: root.pctColor(root.detailData.d2d) },
                    { label: "MTD", value: Model.fmtPct(root.detailData.mtd), tint: root.pctColor(root.detailData.mtd) },
                    { label: "YTD", value: Model.fmtPct(root.detailData.ytd), tint: root.pctColor(root.detailData.ytd) },
                    { label: "ALL", value: Model.fmtPct(root.detailData.unrealizedPct), tint: root.pctColor(root.detailData.unrealizedPct) },
                    { label: "P&L", value: Model.fmtSignedMoney(root.detailData.unrealized, root.detailData.currency), tint: root.pctColor(root.detailData.unrealized) }
                  ]

                  Column {
                    required property var modelData
                    spacing: Style.space(3)

                    Text {
                      text: modelData.label
                      color: root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                    }
                    Text {
                      text: modelData.value
                      color: modelData.tint
                      font.family: root.panelFont
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }

            // ---- P&L chart
            Item {
              visible: root.detailData !== null && root.detailData.ok && root.chartSeries.length > 1
              width: parent.width
              height: Style.space(180)

              Canvas {
                id: chartCanvas
                anchors.fill: parent
                anchors.leftMargin: Style.space(16)
                anchors.rightMargin: Style.space(16)

                Connections {
                  target: root
                  function onChartSeriesChanged() { chartCanvas.requestPaint() }
                  function onFgColorChanged() { chartCanvas.requestPaint() }
                }
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var series = root.chartSeries
                  if (!series || series.length < 2) return
                  var chart = Model.chartValues(series)
                  var values = chart.values
                  if (values.length < 2) return

                  var w = width
                  var h = height
                  var padTop = 18
                  var padBottom = 22
                  var plotH = h - padTop - padBottom

                  var min = Math.min.apply(null, values)
                  var max = Math.max.apply(null, values)
                  if (max === min) { max += 1; min -= 1 }
                  var span = max - min

                  function xAt(i) { return (i / (values.length - 1)) * w }
                  function yAt(v) { return padTop + (1 - (v - min) / span) * plotH }

                  var last = values[values.length - 1]
                  var up = chart.isPnl ? last >= 0 : last >= values[0]
                  var lineColor = up ? String(root.positiveColor) : String(root.negativeColor)

                  // zero line for P&L charts that cross it
                  if (chart.isPnl && min < 0 && max > 0) {
                    ctx.strokeStyle = String(root.mutedColor)
                    ctx.globalAlpha = 0.4
                    ctx.setLineDash([4, 4])
                    ctx.beginPath()
                    ctx.moveTo(0, yAt(0))
                    ctx.lineTo(w, yAt(0))
                    ctx.stroke()
                    ctx.setLineDash([])
                    ctx.globalAlpha = 1.0
                  }

                  // area fill
                  var grad = ctx.createLinearGradient(0, padTop, 0, h - padBottom)
                  grad.addColorStop(0, Qt.rgba(up ? 0.5 : 0.95, up ? 0.8 : 0.55, 0.55, 0.28))
                  grad.addColorStop(1, Qt.rgba(up ? 0.5 : 0.95, up ? 0.8 : 0.55, 0.55, 0.02))
                  ctx.beginPath()
                  ctx.moveTo(xAt(0), h - padBottom)
                  for (var i = 0; i < values.length; i++) ctx.lineTo(xAt(i), yAt(values[i]))
                  ctx.lineTo(xAt(values.length - 1), h - padBottom)
                  ctx.closePath()
                  ctx.fillStyle = grad
                  ctx.fill()

                  // line
                  ctx.beginPath()
                  for (var j = 0; j < values.length; j++) {
                    if (j === 0) ctx.moveTo(xAt(j), yAt(values[j]))
                    else ctx.lineTo(xAt(j), yAt(values[j]))
                  }
                  ctx.strokeStyle = lineColor
                  ctx.lineWidth = 2
                  ctx.lineJoin = "round"
                  ctx.stroke()

                  // end dot
                  ctx.beginPath()
                  ctx.arc(xAt(values.length - 1), yAt(last), 3, 0, Math.PI * 2)
                  ctx.fillStyle = lineColor
                  ctx.fill()

                  // entry markers: hollow dots where lots were opened
                  var entries = root.detailData && root.detailData.entries ? root.detailData.entries : []
                  var drewEntry = false
                  ctx.lineWidth = 2
                  for (var k = 0; k < entries.length; k++) {
                    var ed = entries[k].date
                    if (!ed || ed > series[series.length - 1][0]) continue
                    var idx = -1
                    for (var m = 0; m < series.length; m++) {
                      if (series[m][0] >= ed) { idx = m; break }
                    }
                    if (idx < 0 || idx >= values.length) continue
                    // entries before the visible window collapse onto the
                    // first point; skip those rather than mislabel them.
                    if (ed < series[0][0]) continue
                    ctx.beginPath()
                    ctx.arc(xAt(idx), yAt(values[idx]), 3.5, 0, Math.PI * 2)
                    ctx.fillStyle = String(root.entryColor)
                    ctx.fill()
                    drewEntry = true
                  }

                  // labels
                  var cur = root.detailData ? root.detailData.currency : "USD"
                  ctx.fillStyle = String(root.mutedColor)
                  ctx.font = Style.font.caption + "px \"" + root.panelFont + "\""
                  ctx.textAlign = "left"
                  ctx.fillText(Model.axisDate(series[0][0], root.chartDays), 0, h - 6)
                  ctx.textAlign = "right"
                  ctx.fillText(Model.shortDate(series[series.length - 1][0]), w, h - 6)
                  if (drewEntry) {
                    ctx.textAlign = "center"
                    ctx.fillStyle = String(root.entryColor)
                    ctx.fillText("\u25cf entry", w / 2, h - 6)
                  }
                  ctx.textAlign = "left"
                  ctx.fillText((chart.isPnl ? "P&L " : "price ") + Model.fmtMoney(max, cur), 0, 12)
                  ctx.fillStyle = lineColor
                  ctx.textAlign = "right"
                  ctx.fillText(Model.fmtMoney(last, cur), w, 12)
                }
              }
            }

            Rectangle {
              visible: root.detailData !== null && root.detailData.ok
              width: parent.width
              height: Style.spacing.hairline
              color: root.fgColor
              opacity: 0.12
            }

            // ---- AI summary (generated by the machine's default agent)
            Column {
              visible: root.detailData !== null && root.detailData.ok
              width: parent.width
              spacing: Style.space(6)

              Row {
                x: Style.space(16)
                spacing: Style.space(8)

                Text {
                  text: "AI SUMMARY"
                  color: root.mutedColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  visible: root.aiData !== null && root.aiData.ok === true
                  text: Model.aiAttribution(root.aiData)
                  color: root.mutedColor
                  font.family: root.panelFont
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  visible: root.aiData !== null && !root.aiLoading
                  width: rerunLabel.implicitWidth + Style.space(10)
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  anchors.verticalCenter: parent.verticalCenter
                  color: rerunArea.containsMouse ? Style.hoverFillFor(root.fgColor, Color.accent) : "transparent"

                  Text {
                    id: rerunLabel
                    anchors.centerIn: parent
                    text: "↻ rerun"
                    color: root.mutedColor
                    font.family: root.panelFont
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    id: rerunArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rerunAi()
                  }
                }
              }

              Text {
                visible: root.aiLoading && !root.aiData
                x: Style.space(16)
                text: "Thinking…"
                color: root.mutedColor
                font.family: root.panelFont
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }

              Text {
                visible: root.aiData !== null && root.aiData.ok !== true
                x: Style.space(16)
                width: parent.width - Style.space(32)
                text: root.aiData ? String(root.aiData.error || "AI summary unavailable") : ""
                color: root.mutedColor
                font.family: root.panelFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.aiData !== null && root.aiData.ok === true
                x: Style.space(16)
                width: parent.width - Style.space(32)
                text: root.aiData && root.aiData.summary ? root.aiData.summary : ""
                textFormat: Text.MarkdownText
                color: root.fgColor
                font.family: root.panelFont
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Rectangle {
              visible: root.detailData !== null && root.detailData.ok
              width: parent.width
              height: Style.spacing.hairline
              color: root.fgColor
              opacity: 0.12
            }

            // ---- news
            Column {
              visible: root.detailData !== null && root.detailData.ok
              width: parent.width
              spacing: Style.space(2)

              Text {
                x: Style.space(16)
                text: "NEWS"
                color: root.mutedColor
                font.family: root.panelFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                visible: root.detailData && root.detailData.ok && (!root.detailData.news || root.detailData.news.length === 0)
                x: Style.space(16)
                text: "No recent news found."
                color: root.mutedColor
                font.family: root.panelFont
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }

              Repeater {
                model: root.detailData && root.detailData.ok ? (root.detailData.news || []) : []

                Rectangle {
                  required property var modelData
                  width: parent.width
                  height: newsCol.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: newsArea.containsMouse ? Style.hoverFillFor(root.fgColor, Color.accent) : "transparent"

                  Column {
                    id: newsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(16)
                    anchors.rightMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: modelData.title || ""
                      color: root.fgColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                    Text {
                      text: (modelData.publisher || "") +
                            (modelData.time ? " · " + Model.timeAgo(modelData.time, root.nowMs) : "")
                      color: root.mutedColor
                      font.family: root.panelFont
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: newsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openUrl(modelData.link || "")
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
