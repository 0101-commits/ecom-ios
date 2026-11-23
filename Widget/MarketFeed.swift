import Foundation

/// 위젯 한 칸에 보이는 시세.
struct Quote: Codable, Hashable, Identifiable {
    let key: String
    let name: String
    let value: Double?
    let change: Double?
    var id: String { key }
}

/// 오늘(한국 시각) 경보 · 주의 요약.
struct SignalSummary: Codable, Hashable {
    let alarms: Int
    let alerts: Int
    let level: String?
    let title: String?
    let route: String?

    var isQuiet: Bool { alarms == 0 && alerts == 0 }
}

struct MarketSnapshot: Codable, Hashable {
    let quotes: [Quote]
    let signal: SignalSummary?
    let asOf: Date?
    let fetchedAt: Date
    var stale: Bool

    func quote(_ key: String) -> Quote? { quotes.first { $0.key == key } }

    static let sample = MarketSnapshot(
        quotes: [
            Quote(key: "KOSPI", name: "코스피", value: 4699.32, change: -3.50),
            Quote(key: "KOSDAQ", name: "코스닥", value: 625.98, change: -3.02),
            Quote(key: "USDKRW", name: "원·달러", value: 1349.8, change: 0.27),
            Quote(key: "SP500", name: "S&P 500", value: 7175.83, change: -2.0),
            Quote(key: "NASDAQ", name: "나스닥", value: 23879.2, change: -2.24),
        ],
        signal: SignalSummary(alarms: 2, alerts: 2, level: "alarm",
                              title: "코스피 매도 사이드카 발동", route: nil),
        asOf: Date(), fetchedAt: Date(), stale: false)
}

enum MarketFeed {
    static let base = URL(string: "https://ecom-terminal.pages.dev/")!
    private static let cacheKey = "ecom.snapshot.v1"

    /// 표시 순서 · 이름 · 자료 위치.
    private static let items: [(key: String, name: String, group: String, field: String)] = [
        ("KOSPI", "코스피", "indices", "price"),
        ("KOSDAQ", "코스닥", "indices", "price"),
        ("USDKRW", "원·달러", "fx", "rate"),
        ("SP500", "S&P 500", "indices", "price"),
        ("NASDAQ", "나스닥", "indices", "price"),
    ]

    static var kst: TimeZone { TimeZone(identifier: "Asia/Seoul")! }

    /// 받아 오기 → 저장. 실패하면 마지막 값(낡음 표시)을, 그것도 없으면 nil.
    static func load() async -> MarketSnapshot? {
        do {
            let snap = try await fetch()
            save(snap)
            return snap
        } catch {
            guard var old = cached() else { return nil }
            old.stale = true
            return old
        }
    }

    static func fetch() async throws -> MarketSnapshot {
        async let dataJSON = getJSON("data.json")
        async let eventsJSON = getJSON("events/latest.json")

        guard let data = try await dataJSON as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var quotes: [Quote] = []
        for item in items {
            let group = data[item.group] as? [String: Any]
            let node = group?[item.key] as? [String: Any]
            quotes.append(Quote(key: item.key, name: item.name,
                                value: number(node?[item.field]),
                                change: number(node?["change"])))
        }
        let asOf = parseDate(data["lastUpdated"] as? String)
        // 신호 목록은 못 받아도 시세는 보여 준다.
        let events = (try? await eventsJSON) as? [[String: Any]]
        let signal = events.map { summarize($0) }
        return MarketSnapshot(quotes: quotes, signal: signal, asOf: asOf,
                              fetchedAt: Date(), stale: false)
    }

    /// 오늘 경보 · 주의 수와 가장 최근 것 하나.
    static func summarize(_ rows: [[String: Any]], now: Date = Date()) -> SignalSummary {
        let today = dayString(now)
        let todays = rows.filter { row in
            guard let level = row["level"] as? String, level == "alarm" || level == "alert",
                  let ts = row["ts"] as? String else { return false }
            return ts.prefix(10) == today
        }
        .sorted { ($0["ts"] as? String ?? "") > ($1["ts"] as? String ?? "") }

        let alarms = todays.filter { ($0["level"] as? String) == "alarm" }
        let lead = alarms.first ?? todays.first
        return SignalSummary(alarms: alarms.count,
                             alerts: todays.count - alarms.count,
                             level: lead?["level"] as? String,
                             title: lead?["title"] as? String,
                             route: lead?["url"] as? String)
    }

    // MARK: - 다음 갱신 시각

    /// 한국 장중 15분 · 미국 장중 30분 · 그 밖 1시간. 실제 갱신 횟수는 iOS 가 정한다.
    static func nextRefresh(after now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kst
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let weekday = c.weekday ?? 1 // 1 = 일요일
        let weekdayKR = (2...6).contains(weekday)
        let krOpen = weekdayKR && minutes >= 8 * 60 + 50 && minutes <= 15 * 60 + 40
        // 미국 장(한국 시각 22:30~06:10) — 화~토 새벽 포함.
        let usEvening = (2...6).contains(weekday) && minutes >= 22 * 60 + 30
        let usMorning = (3...7).contains(weekday) && minutes <= 6 * 60 + 10
        let step: TimeInterval = krOpen ? 15 * 60 : (usEvening || usMorning) ? 30 * 60 : 60 * 60
        return now.addingTimeInterval(step)
    }

    // MARK: - 도우미

    private static func getJSON(_ path: String) async throws -> Any {
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        let (body, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: body)
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = kst
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// "2026-11-23T13:40:45.764442+09:00" — 소수점 아래 자릿수가 들쭉날쭉해 떼고 읽는다.
    static func parseDate(_ s: String?) -> Date? {
        guard var s else { return nil }
        if let dot = s.firstIndex(of: "."),
           let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            s.removeSubrange(dot..<tz)
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static func save(_ snap: MarketSnapshot) {
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func cached() -> MarketSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(MarketSnapshot.self, from: data)
    }
}
