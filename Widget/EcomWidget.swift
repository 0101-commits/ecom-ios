import UIKit
import SwiftUI
import WidgetKit

// MARK: - 시간표

struct MarketEntry: TimelineEntry {
    let date: Date
    let snapshot: MarketSnapshot?
}

struct MarketProvider: TimelineProvider {
    func placeholder(in context: Context) -> MarketEntry {
        MarketEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MarketEntry) -> Void) {
        if context.isPreview {
            completion(MarketEntry(date: Date(), snapshot: .sample))
            return
        }
        Task {
            let snap = await MarketFeed.load()
            completion(MarketEntry(date: Date(), snapshot: snap))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MarketEntry>) -> Void) {
        Task {
            let snap = await MarketFeed.load()
            let entry = MarketEntry(date: Date(), snapshot: snap)
            completion(Timeline(entries: [entry], policy: .after(MarketFeed.nextRefresh())))
        }
    }
}

// MARK: - 위젯

@main
struct EcomWidgetBundle: WidgetBundle {
    var body: some Widget {
        MarketWidget()
    }
}

struct MarketWidget: Widget {
    let kind = "EcomMarket"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MarketProvider()) { entry in
            MarketWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("ecom 시세")
        .description("코스피 · 코스닥 · 원·달러 · 미국 지수와 오늘 경보 · 주의")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 표기

enum Fmt {
    static let up = Color(red: 0xE0 / 255, green: 0x44 / 255, blue: 0x3E / 255)
    static let down = Color(red: 0x3E / 255, green: 0x7B / 255, blue: 0xE0 / 255)
    static let brand = Color(red: 0, green: 80 / 255, blue: 52 / 255)

    static func value(_ q: Quote?) -> String {
        guard let q, let v = q.value else { return "—" }
        let digits: Int
        switch q.key {
        case "USDKRW": digits = 1
        case "NASDAQ": digits = 0
        default: digits = 2
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ko_KR")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "—"
    }

    static func change(_ c: Double?) -> String {
        guard let c else { return "—" }
        let mark = c > 0 ? "▲" : (c < 0 ? "▼" : "")
        return mark + String(format: "%.2f%%", abs(c))
    }

    static func color(_ c: Double?) -> Color {
        guard let c, c != 0 else { return .secondary }
        return c > 0 ? up : down
    }

    /// 기준 시각 — 오늘이면 "13:40", 아니면 "11/20 16:08".
    static func asOf(_ snap: MarketSnapshot) -> String {
        guard let d = snap.asOf else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = MarketFeed.kst
        f.dateFormat = MarketFeed.dayString(d) == MarketFeed.dayString(Date()) ? "HH:mm" : "M/d HH:mm"
        return f.string(from: d) + (snap.stale ? " · 이전 값" : "")
    }

    static func signalHead(_ s: SignalSummary) -> String {
        if s.isQuiet { return "오늘 경보·주의 없음" }
        var parts: [String] = []
        if s.alarms > 0 { parts.append("경보 \(s.alarms)") }
        if s.alerts > 0 { parts.append("주의 \(s.alerts)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 화면

struct MarketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MarketEntry

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .systemMedium: MediumView(snap: snap)
            case .accessoryRectangular: LockRectView(snap: snap)
            case .accessoryInline: LockInlineView(snap: snap)
            default: SmallView(snap: snap)
            }
        } else {
            VStack(spacing: 4) {
                Text("ecom").font(.headline)
                Text("시세를 받지 못했습니다").font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(EcomLinks.deepLink())
        }
    }
}

private struct Header: View {
    let snap: MarketSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Text("ECOM")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Fmt.brand)
            Spacer(minLength: 2)
            Text(Fmt.asOf(snap))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 이름 · 값 · 등락을 두 줄로.
private struct QuoteBlock: View {
    let quote: Quote?
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(Fmt.change(quote?.change))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Fmt.color(quote?.change))
                    .lineLimit(1)
            }
            Text(Fmt.value(quote))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct SignalLine: View {
    let signal: SignalSummary?

    var body: some View {
        if let s = signal {
            HStack(spacing: 4) {
                Circle()
                    .fill(s.alarms > 0 ? Fmt.up : (s.alerts > 0 ? Color.orange : Color.secondary.opacity(0.4)))
                    .frame(width: 6, height: 6)
                Text(Fmt.signalHead(s))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let title = s.title, !s.isQuiet {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SmallView: View {
    let snap: MarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Header(snap: snap)
            QuoteBlock(quote: snap.quote("KOSPI"), name: "코스피")
            QuoteBlock(quote: snap.quote("KOSDAQ"), name: "코스닥")
            QuoteBlock(quote: snap.quote("USDKRW"), name: "원·달러")
            Spacer(minLength: 0)
            if let s = snap.signal, !s.isQuiet {
                HStack(spacing: 4) {
                    Circle().fill(s.alarms > 0 ? Fmt.up : Color.orange).frame(width: 6, height: 6)
                    Text(Fmt.signalHead(s)).font(.caption2.weight(.semibold)).lineLimit(1)
                }
            }
        }
        .widgetURL(EcomLinks.deepLink())
    }
}

struct MediumView: View {
    let snap: MarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(snap: snap)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    QuoteBlock(quote: snap.quote("KOSPI"), name: "코스피")
                    QuoteBlock(quote: snap.quote("KOSDAQ"), name: "코스닥")
                    QuoteBlock(quote: snap.quote("USDKRW"), name: "원·달러")
                }
                VStack(alignment: .leading, spacing: 5) {
                    QuoteBlock(quote: snap.quote("SP500"), name: "S&P 500")
                    QuoteBlock(quote: snap.quote("NASDAQ"), name: "나스닥")
                }
            }
            Spacer(minLength: 0)
            if let s = snap.signal {
                Link(destination: EcomLinks.deepLink(route: s.isQuiet ? nil : s.route)) {
                    SignalLine(signal: s)
                }
            }
        }
        .widgetURL(EcomLinks.deepLink())
    }
}

struct LockRectView: View {
    let snap: MarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("코스피", snap.quote("KOSPI"))
            row("원·달러", snap.quote("USDKRW"))
            row("나스닥", snap.quote("NASDAQ"))
        }
        .widgetURL(EcomLinks.deepLink())
    }

    private func row(_ name: String, _ q: Quote?) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.caption2).widgetAccentable()
            Spacer(minLength: 2)
            Text(Fmt.value(q)).font(.caption2.weight(.semibold)).monospacedDigit()
            Text(Fmt.change(q?.change)).font(.caption2).monospacedDigit()
        }
        .lineLimit(1)
    }
}

struct LockInlineView: View {
    let snap: MarketSnapshot

    var body: some View {
        let k = snap.quote("KOSPI")
        Text("코스피 \(Fmt.change(k?.change)) · 원·달러 \(Fmt.value(snap.quote("USDKRW")))")
            .widgetURL(EcomLinks.deepLink())
    }
}
