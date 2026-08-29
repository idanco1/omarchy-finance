// Formatting and series helpers for the idanco.finance plugin.

function isNum(x) {
  return typeof x === "number" && isFinite(x)
}

// 0.0123 -> "+1.23%"; null -> "—"
function fmtPct(x) {
  if (!isNum(x)) return "—"
  var pct = x * 100
  var sign = pct > 0 ? "+" : ""
  var digits = Math.abs(pct) >= 100 ? 0 : (Math.abs(pct) >= 10 ? 1 : 2)
  return sign + pct.toFixed(digits) + "%"
}

function fmtNumber(x, digits) {
  if (!isNum(x)) return "—"
  var parts = x.toFixed(digits).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

var CURRENCY_SIGNS = { USD: "$", ILS: "₪", EUR: "€", CHF: "₣", GBP: "£" }

function fmtMoney(x, currency) {
  if (!isNum(x)) return "—"
  var sign = CURRENCY_SIGNS[currency] || ((currency || "") + " ")
  var neg = x < 0 ? "-" : ""
  var abs = Math.abs(x)
  return neg + sign + fmtNumber(abs, abs >= 1000 ? 0 : 2)
}

function fmtSignedMoney(x, currency) {
  if (!isNum(x)) return "—"
  return (x > 0 ? "+" : "") + fmtMoney(x, currency)
}

function fmtPrice(x) {
  if (!isNum(x)) return "—"
  return fmtNumber(x, x >= 1000 ? 0 : 2)
}

function fmtRate(x) {
  return isNum(x) ? x.toFixed(3) : "—"
}

// Color for a signed quantity: green / red / muted.
function pnlColor(x, positive, negative, neutral) {
  if (!isNum(x) || x === 0) return neutral
  return x > 0 ? positive : negative
}

function timeAgo(epoch, nowMs) {
  if (!epoch) return ""
  var s = Math.max(0, Math.floor(nowMs / 1000 - epoch))
  if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m ago"
  if (s < 86400) return Math.floor(s / 3600) + "h ago"
  return Math.floor(s / 86400) + "d ago"
}

// Keep the last `days` calendar days of a [[iso, price, pnl], ...] series.
function tailSeries(series, days) {
  if (!series || series.length === 0) return []
  var lastDate = new Date(series[series.length - 1][0] + "T00:00:00")
  var cutoff = new Date(lastDate.getTime() - days * 86400000)
  var cutoffIso = cutoff.toISOString().slice(0, 10)
  var out = []
  for (var i = 0; i < series.length; i++)
    if (series[i][0] >= cutoffIso) out.push(series[i])
  return out
}

// Values to chart: per-point P&L when the fetcher could compute it
// (position + cost basis known), otherwise the price itself.
function chartValues(series) {
  if (!series || series.length === 0) return { values: [], isPnl: false }
  var isPnl = series[series.length - 1][2] !== null
             && series[series.length - 1][2] !== undefined
  var values = []
  for (var i = 0; i < series.length; i++) {
    var v = isPnl ? series[i][2] : series[i][1]
    if (v !== null && v !== undefined) values.push(v)
  }
  return { values: values, isPnl: isPnl }
}

function shortDate(iso) {
  if (!iso) return ""
  var d = new Date(iso + "T00:00:00")
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

// Axis label: month + year on long ranges, month + day on short ones.
function axisDate(iso, spanDays) {
  if (!iso) return ""
  if (spanDays <= 120) return shortDate(iso)
  var d = new Date(iso + "T00:00:00")
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getFullYear()
}

// 12842 -> "12.8k", 950 -> "950"
function fmtTokens(n) {
  if (!isNum(n)) return "?"
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
  if (n >= 1000) return (n / 1000).toFixed(1) + "k"
  return String(n)
}

// "via claude · claude-fable-5 · 33.1k→210 tok · $0.19 · 11:36"
function aiAttribution(ai) {
  if (!ai) return ""
  var bits = []
  if (ai.agent) bits.push("via " + ai.agent)
  if (ai.model) bits.push(ai.model)
  if (isNum(ai.inputTokens) || isNum(ai.outputTokens))
    bits.push(fmtTokens(ai.inputTokens) + "→" + fmtTokens(ai.outputTokens) + " tok")
  if (isNum(ai.costUsd))
    bits.push("$" + ai.costUsd.toFixed(ai.costUsd < 0.095 ? 3 : 2))
  if (ai.generatedAt) bits.push(clockTime(ai.generatedAt))
  return bits.join(" · ")
}

// Market open/close moment in the machine's local time: "16:30" when it
// falls today, otherwise "Mon 16:30".
function openTime(epoch, nowMs) {
  if (!epoch) return ""
  var d = new Date(epoch * 1000)
  var now = new Date(nowMs)
  function pad(n) { return (n < 10 ? "0" : "") + n }
  var t = pad(d.getHours()) + ":" + pad(d.getMinutes())
  var sameDay = d.getFullYear() === now.getFullYear()
             && d.getMonth() === now.getMonth()
             && d.getDate() === now.getDate()
  if (sameDay) return t
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[d.getDay()] + " " + t
}

function clockTime(epoch) {
  if (!epoch) return ""
  var d = new Date(epoch * 1000)
  function pad(n) { return (n < 10 ? "0" : "") + n }
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}
