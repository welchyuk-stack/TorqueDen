import Foundation

struct CloudflareStats {
    let requests: Int
    let pageViews: Int
    let bytes: Int
    let countries: [CountryStat]
    let dailyStats: [DailyStat]
}

struct CountryStat: Identifiable {
    var id: String { isoCode }
    let isoCode: String     // 2-letter ISO, e.g. "GB"
    let requests: Int

    var flagEmoji: String {
        let base: UInt32 = 127397
        return isoCode.unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map(String.init)
            .joined()
    }

    var displayName: String {
        Locale.current.localizedString(forRegionCode: isoCode) ?? isoCode
    }
}

struct DailyStat: Identifiable {
    var id: String { date }
    let date: String        // "yyyy-MM-dd"
    let requests: Int
    let pageViews: Int

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    var parsedDate: Date { Self.formatter.date(from: date) ?? Date() }
}

struct CloudflareAPIClient {
    private static let graphqlURL = URL(string: "https://api.cloudflare.com/client/v4/graphql")!

    private let token: String
    private let zoneId: String

    init() throws {
        token = try KeychainService.load(account: "cloudflareToken")
        zoneId = try KeychainService.load(account: "cloudflareZoneId")
    }

    func fetchStats(days: Int = 30) async throws -> CloudflareStats {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -(days - 1), to: end)!
        let startStr = isoDate(start)
        let endStr = isoDate(end)

        let query = """
        {
          viewer {
            zones(filter: { zoneTag: "\(zoneId)" }) {
              httpRequests1dGroups(
                limit: \(days + 5)
                filter: { date_geq: "\(startStr)", date_leq: "\(endStr)" }
                orderBy: [date_ASC]
              ) {
                dimensions { date }
                sum {
                  requests
                  pageViews
                  bytes
                  countryMap { clientCountryName requests }
                }
              }
            }
          }
        }
        """

        var request = URLRequest(url: Self.graphqlURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudflareError.networkError }
        guard http.statusCode == 200 else { throw CloudflareError.serverError(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let viewer = dataObj["viewer"] as? [String: Any],
              let zones = viewer["zones"] as? [[String: Any]],
              let zone = zones.first,
              let groups = zone["httpRequests1dGroups"] as? [[String: Any]] else {
            // Surface any API errors
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               let msg = errors.first?["message"] as? String {
                throw CloudflareError.apiError(msg)
            }
            throw CloudflareError.parseError
        }

        // Aggregate across all days
        var totalRequests = 0
        var totalPageViews = 0
        var totalBytes = 0
        var countryTotals: [String: Int] = [:]
        var daily: [DailyStat] = []

        for group in groups {
            guard let dims = group["dimensions"] as? [String: Any],
                  let date = dims["date"] as? String,
                  let sum = group["sum"] as? [String: Any] else { continue }

            let req = sum["requests"] as? Int ?? 0
            let pv = sum["pageViews"] as? Int ?? 0
            let b = sum["bytes"] as? Int ?? 0
            totalRequests += req
            totalPageViews += pv
            totalBytes += b
            daily.append(DailyStat(date: date, requests: req, pageViews: pv))

            if let countryMap = sum["countryMap"] as? [[String: Any]] {
                for entry in countryMap {
                    if let code = entry["clientCountryName"] as? String,
                       let count = entry["requests"] as? Int {
                        countryTotals[code, default: 0] += count
                    }
                }
            }
        }

        let countries = countryTotals
            .map { CountryStat(isoCode: $0.key, requests: $0.value) }
            .sorted { $0.requests > $1.requests }

        return CloudflareStats(
            requests: totalRequests,
            pageViews: totalPageViews,
            bytes: totalBytes,
            countries: countries,
            dailyStats: daily
        )
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

enum CloudflareError: LocalizedError {
    case missingCredentials
    case networkError
    case serverError(Int)
    case parseError
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add your Cloudflare API token and Zone ID in Settings."
        case .networkError: return "Network error reaching Cloudflare."
        case .serverError(let code): return "Cloudflare returned HTTP \(code). Check your API token."
        case .parseError: return "Could not parse Cloudflare response."
        case .apiError(let msg): return "Cloudflare API error: \(msg)"
        }
    }
}
