import Foundation

/// 앱과 위젯이 함께 쓰는 주소.
enum EcomLinks {
    static let site = URL(string: "https://ecom-terminal.pages.dev/")!
    static let host = "ecom-terminal.pages.dev"
    static let scheme = "ecomapp"

    /// 위젯을 누르면 여는 앱 주소. `route` 는 사이트 안 경로(예: "#/i/sox").
    static func deepLink(route: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        if let route, !route.isEmpty {
            c.queryItems = [URLQueryItem(name: "r", value: route)]
        }
        return c.url!
    }

    /// 앱 주소(ecomapp://open?r=…) → 사이트 주소.
    static func siteURL(fromDeepLink url: URL) -> URL {
        guard url.scheme == scheme,
              let route = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "r" })?.value,
              !route.isEmpty
        else { return site }
        if route.hasPrefix("#") {
            return URL(string: site.absoluteString + route) ?? site
        }
        let trimmed = route.hasPrefix("/") ? String(route.dropFirst()) : route
        return URL(string: trimmed, relativeTo: site)?.absoluteURL ?? site
    }
}
