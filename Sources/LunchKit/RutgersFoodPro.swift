import Foundation

/// Public FoodPro HTML adapter. Requests are serialized and paced, not polled.
/// Menus live in MenuRepository; recipe+portion nutrition lives here for 30 days.
public actor RutgersFoodPro: MenuProviding {
    public static let base = "https://menuportal23.dining.rutgers.edu/foodpronet/"
    private let loader: any HTTPLoading
    private let directory: URL?
    private let now: @Sendable () -> Date
    private let spacing: TimeInterval
    private var nutrition: [String: FoodProNutrition] = [:]
    private var tail: Task<Void, Never>?
    private var retryAfter = Date.distantPast
    private var failures = 0
    public private(set) var requestCount = 0
    private var detailsInFlight: [String: Task<FoodProNutrition, any Error>] = [:]
    private var reportsInFlight: [String: Task<MenuDay, any Error>] = [:]

    public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    public init(loader: any HTTPLoading = RutgersFoodPro.defaultSession,
                directory: URL? = RutgersFoodPro.defaultDirectory(), spacing: TimeInterval = 0.35,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.loader = loader; self.directory = directory; self.spacing = spacing; self.now = now
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }
    public static func defaultDirectory() -> URL? {
        MenuCache.defaultDirectory()?.deletingLastPathComponent().appending(path: "recipes")
    }
    public static func menuURL(source: MenuSource, day: LocalDate) -> URL? {
        url(page: "pickmenu.aspx", source: source, day: day, extras: [URLQueryItem(name: "activeMeal", value: source.menuType.slug)])
    }
    static func url(page: String, source: MenuSource, day: LocalDate, extras: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: base + page)!
        components.queryItems = [URLQueryItem(name: "sName", value: "Rutgers University Dining"),
                                URLQueryItem(name: "locationNum", value: source.school.slug),
                                URLQueryItem(name: "locationName", value: source.school.name),
                                URLQueryItem(name: "dtdate", value: "\(day.month)/\(day.day)/\(day.year)")] + extras
        return components.url
    }
    public func week(source: MenuSource, containing day: LocalDate) async throws(NutrisliceError) -> MenuWeek {
        guard let url = Self.menuURL(source: source, day: day) else { throw .invalidData }
        do {
            let parsed = try RutgersParser.menu(try await request(URLRequest(url: url)), date: day, meal: source.menuType.slug)
            return MenuWeek(start: day.weekStart, days: [parsed])
        } catch {
            if !(error is NutrisliceError) { retryAfter = max(retryAfter, now().addingTimeInterval(30)) }
            throw (error as? NutrisliceError) ?? .invalidData
        }
    }

    /// One combined report for all uncached recipes. It preserves per-item values,
    /// so there is no need to fan out one label request per item just to rank protein.
    public func enriched(_ day: MenuDay, source: MenuSource) async throws -> MenuDay {
        let key = source.key + day.date.isoString
        if let existing = reportsInFlight[key] { return try await existing.value }
        let task = Task { try await self.loadNutrition(day, source: source) }
        reportsInFlight[key] = task
        defer { reportsInFlight[key] = nil }
        do { return try await task.value }
        catch {
            if !(error is NutrisliceError) { retryAfter = max(retryAfter, now().addingTimeInterval(30)) }
            throw error
        }
    }
    private func loadNutrition(_ day: MenuDay, source: MenuSource) async throws -> MenuDay {
        var seen = Set<String>()
        let missing = day.items.filter { seen.insert($0.foodID).inserted && cached($0.foodID) == nil }
        // Bounded reports also avoid oversized form submissions on unusually large menus.
        for start in stride(from: 0, to: missing.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + 100, missing.count)])
            let url = Self.url(page: "nutRpt.aspx", source: source, day: day.date,
                               extras: [URLQueryItem(name: "mealName", value: source.menuType.slug)])!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // The report requires the exact recipe*portion*station form token.
            // Omitting station silently truncates recipe IDs, even with HTTP 200.
            var body = URLComponents()
            body.queryItems = batch.flatMap { [URLQueryItem(name: "recipe", value: $0.providerReference ?? $0.foodID), URLQueryItem(name: "QTY", value: "1")] }
            req.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            let reportData = try await request(req)
            let values: [String: FoodProNutrition]
            do { values = try RutgersParser.report(reportData) }
            catch {
                if ProcessInfo.processInfo.arguments.contains("--http-diagnostics") {
                    let path = FileManager.default.currentDirectoryPath + "/.foodpro-report-error.html"
                    try? reportData.write(to: URL(filePath: path))
                    FileHandle.standardError.write(Data("FoodPro report parse failed: \(batch.map(\.foodID)); response saved to \(path)\n".utf8))
                }
                throw error
            }
            let missingIDs = batch.filter { values[$0.foodID] == nil }.map(\.foodID)
            guard missingIDs.isEmpty else {
                if ProcessInfo.processInfo.arguments.contains("--http-diagnostics") {
                    FileHandle.standardError.write(Data("FoodPro missing report IDs: \(missingIDs); got: \(values.keys.sorted())\n".utf8))
                }
                throw RutgersParser.ParseError.unexpectedHTML
            }
            for item in batch {
                if var value = values[item.foodID] { value.fetchedAt = now(); store(value, key: item.foodID) }
            }
        }
        return applyingCached(to: day)
    }
    public func applyingCached(to day: MenuDay) -> MenuDay {
        var copy = day
        for section in copy.sections.indices {
            for row in copy.sections[section].items.indices {
                let item = copy.sections[section].items[row]
                if let value = cached(item.foodID) { copy.sections[section].items[row] = value.applying(to: item) }
            }
        }
        return copy
    }
    public func hasLabel(_ recipe: String) -> Bool { cached(recipe)?.hasLabel == true }
    public func details(_ item: MenuItem, source: MenuSource, day: LocalDate) async throws -> MenuItem {
        if let value = cached(item.foodID), value.hasLabel { return value.applying(to: item) }
        if let existing = detailsInFlight[item.foodID] { return try await existing.value.applying(to: item) }
        guard RutgersParser.validRecipe(item.foodID),
              let url = Self.url(page: "label.aspx", source: source, day: day,
                                 extras: [URLQueryItem(name: "RecNumAndPort", value: item.foodID)]) else { throw NutrisliceError.invalidData }
        let task = Task {
            var label = try RutgersParser.label(try await self.request(URLRequest(url: url)))
            if let previous = self.cached(item.foodID) {
                label.calories = label.calories ?? previous.calories
                let names = Set(label.nutrients.map(\.name))
                label.nutrients += previous.nutrients.filter { !names.contains($0.name) }
            }
            label.fetchedAt = self.now()
            self.store(label, key: item.foodID)
            return label
        }
        detailsInFlight[item.foodID] = task
        defer { detailsInFlight[item.foodID] = nil }
        return try await task.value.applying(to: item)
    }
    private func cached(_ key: String) -> FoodProNutrition? {
        if let hit = nutrition[key], now().timeIntervalSince(hit.fetchedAt) >= 0, now().timeIntervalSince(hit.fetchedAt) < 30 * 86400 { return hit }
        guard let file = file(key), let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(FoodProNutrition.self, from: data),
              now() >= value.fetchedAt, now().timeIntervalSince(value.fetchedAt) < 30 * 86400 else { return nil }
        nutrition[key] = value
        return value
    }
    private func file(_ key: String) -> URL? {
        guard RutgersParser.validRecipe(key) else { return nil }
        return directory?.appending(path: key.replacingOccurrences(of: "*", with: "_").replacingOccurrences(of: "/", with: "_") + ".json")
    }
    private func store(_ value: FoodProNutrition, key: String) {
        nutrition[key] = value
        if let file = file(key), let data = try? JSONEncoder().encode(value) { try? data.write(to: file, options: .atomic) }
    }
    private func request(_ request: URLRequest) async throws -> Data {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await self.perform(request)
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
    private func perform(_ original: URLRequest) async throws -> Data {
        guard now() >= retryAfter else { throw NutrisliceError.server(status: 429) }
        if spacing > 0 { try await Task.sleep(for: .seconds(spacing)) }
        var req = original
        // Form reports must never reuse a previous selection's HTTP cache/session.
        // App-level caches supply freshness; no authenticated session is needed.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpShouldHandleCookies = false
        req.setValue(NutrisliceClient.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        requestCount += 1
        do {
            let (data, response) = try await loader.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw NutrisliceError.invalidData }
            if ProcessInfo.processInfo.arguments.contains("--http-diagnostics") {
                FileHandle.standardError.write(Data("HTTP \(http.statusCode) \(req.httpMethod ?? "GET") \(req.url!.absoluteString) bytes=\(data.count)\n".utf8))
            }
            guard (200..<300).contains(http.statusCode) else {
                if let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
                    retryAfter = now().addingTimeInterval(min(max(seconds, 30), 3600))
                }
                throw NutrisliceError.server(status: http.statusCode)
            }
            failures = 0
            return data
        } catch {
            failures = min(failures + 1, 7)
            retryAfter = max(retryAfter, now().addingTimeInterval(min(30 * pow(2, Double(failures - 1)), 3600)))
            throw (error as? NutrisliceError) ?? NutrisliceClient.map(error, host: "Rutgers Dining")
        }
    }
}
