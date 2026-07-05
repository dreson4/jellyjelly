import Foundation

enum JellyseerrAuth {
    case apiKey(String)
    case sessionCookie(String)
}

/// How the user connects to Jellyseerr. Jellyfin sign-in reuses the media
/// server account; local sign-in is Jellyseerr's own email/password accounts.
enum JellyseerrConnectMethod: String, CaseIterable {
    case jellyfinAccount = "Jellyfin Sign-In"
    case localAccount = "Jellyseerr Sign-In"
    case apiKey = "API Key"
}

private actor SeerResponseCache {
    private struct Entry {
        let value: Any
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Any, Error>] = [:]

    func value<T>(for key: String, ttl: TimeInterval, load: @escaping () async throws -> T) async throws -> T {
        let now = Date()
        if let entry = entries[key], entry.expiresAt > now, let value = entry.value as? T {
            return value
        }

        if let task = inFlight[key] {
            let value = try await task.value
            guard let typed = value as? T else { throw APIError.decoding(CacheTypeMismatch()) }
            return typed
        }

        let task = Task<Any, Error> { try await load() }
        inFlight[key] = task

        do {
            let value = try await task.value
            entries[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
            inFlight[key] = nil
            guard let typed = value as? T else { throw APIError.decoding(CacheTypeMismatch()) }
            return typed
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func remove(_ key: String) {
        entries[key] = nil
        inFlight[key] = nil
    }

    func remove(prefix: String) {
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
        inFlight = inFlight.filter { !$0.key.hasPrefix(prefix) }
    }

    private struct CacheTypeMismatch: LocalizedError {
        var errorDescription: String? { "Cached Jellyseerr response had the wrong type." }
    }
}

/// Thin async client for the Jellyseerr (Overseerr-compatible) API.
final class JellyseerrClient {
    private let baseURL: URL      // e.g. https://requests.example.com
    private let auth: JellyseerrAuth
    private let cache = SeerResponseCache()

    private static let decoder = JSONDecoder()

    init(baseURL: URL, auth: JellyseerrAuth) {
        self.baseURL = baseURL
        self.auth = auth
    }

    convenience init?(profile: ServerProfile) {
        guard let url = profile.jellyseerrURL else { return nil }
        if let cookie = profile.jellyseerrCookie, !cookie.isEmpty {
            self.init(baseURL: url, auth: .sessionCookie(cookie))
        } else if let key = profile.jellyseerrAPIKey, !key.isEmpty {
            self.init(baseURL: url, auth: .apiKey(key))
        } else {
            return nil
        }
    }

    /// Signs in to Jellyseerr with the user's Jellyfin credentials and returns
    /// the session cookie. Same account as the media server — no API key needed.
    static func loginWithJellyfin(baseURL: URL, username: String, password: String) async throws -> String {
        try await sessionLogin(baseURL: baseURL, path: "api/v1/auth/jellyfin", body: [
            "username": username,
            "password": password,
        ])
    }

    /// Signs in with a local Jellyseerr account (email + password) and returns
    /// the session cookie.
    static func loginLocal(baseURL: URL, email: String, password: String) async throws -> String {
        try await sessionLogin(baseURL: baseURL, path: "api/v1/auth/local", body: [
            "email": email,
            "password": password,
        ])
    }

    private static func sessionLogin(baseURL: URL, path: String, body: [String: String]) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }

        let headers = http.allHeaderFields as? [String: String] ?? [:]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: baseURL)
        guard let session = cookies.first(where: { $0.name == "connect.sid" })?.value else {
            _ = data
            throw APIError.decoding(NSError(domain: "JellyJelly", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Jellyseerr didn't return a session cookie.",
            ]))
        }
        return session
    }

    /// Validates the connection.
    func me() async throws -> SeerUser {
        try await get("auth/me", as: SeerUser.self)
    }

    func trending(page: Int = 1) async throws -> [SeerResult] {
        try await cached("discover:trending:\(page)", ttl: 10 * 60) {
            try await self.get("discover/trending", query: ["page": String(page)], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    func popularMovies(page: Int = 1) async throws -> [SeerResult] {
        try await cached("discover:movies:\(page)", ttl: 10 * 60) {
            try await self.get("discover/movies", query: ["page": String(page)], as: SeerPage.self).results
        }
    }

    func popularTV(page: Int = 1) async throws -> [SeerResult] {
        try await cached("discover:tv:\(page)", ttl: 10 * 60) {
            try await self.get("discover/tv", query: ["page": String(page)], as: SeerPage.self).results
        }
    }

    func upcomingMovies(page: Int = 1) async throws -> [SeerResult] {
        try await cached("discover:movies:upcoming:\(page)", ttl: 10 * 60) {
            try await self.get("discover/movies/upcoming", query: ["page": String(page)], as: SeerPage.self).results
        }
    }

    func search(query: String, page: Int = 1) async throws -> [SeerResult] {
        try await cached("search:\(query.lowercased()):\(page)", ttl: 2 * 60) {
            try await self.get("search", query: ["query": query, "page": String(page)], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    /// Full movie/tv payload: credits, genres, runtime, status, availability.
    func details(for media: SeerResult) async throws -> SeerDetails {
        try await details(mediaType: media.mediaType, id: media.id)
    }

    func refreshDetails(for media: SeerResult) async throws -> SeerDetails {
        await cache.remove(Self.detailsKey(mediaType: media.mediaType, id: media.id))
        return try await details(for: media)
    }

    func recommendations(for media: SeerResult) async throws -> [SeerResult] {
        try await cached("recommendations:\(media.mediaType):\(media.id)", ttl: 30 * 60) {
            try await self.get("\(media.mediaType)/\(media.id)/recommendations",
                               query: ["page": "1"], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    func similar(to media: SeerResult) async throws -> [SeerResult] {
        try await cached("similar:\(media.mediaType):\(media.id)", ttl: 30 * 60) {
            try await self.get("\(media.mediaType)/\(media.id)/similar",
                               query: ["page": "1"], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    /// Multi-source ratings. Movies expose Rotten Tomatoes + IMDb via
    /// `ratingscombined`; series only expose Rotten Tomatoes via `ratings`
    /// (`ratingscombined` 404s for TV), so IMDb is nil there.
    func ratings(for media: SeerResult) async throws -> SeerRatings {
        try await cached("ratings:\(media.mediaType):\(media.id)", ttl: 60 * 60) {
            if media.isMovie {
                return try await self.get("movie/\(media.id)/ratingscombined", as: SeerRatings.self)
            } else {
                let rt = try await self.get("tv/\(media.id)/ratings", as: SeerRTRating.self)
                return SeerRatings(rt: rt, imdb: nil)
            }
        }
    }

    /// Episodes (with stills, air dates, overviews) for one season of a series.
    func seasonDetails(tvId: Int, season: Int) async throws -> SeerSeasonDetails {
        try await cached("season:\(tvId):\(season)", ttl: 60 * 60) {
            try await self.get("tv/\(tvId)/season/\(season)", as: SeerSeasonDetails.self, attempts: 4)
        }
    }

    /// Full details by media type + TMDB id (for enriching request/media lists
    /// that only carry ids).
    func details(mediaType: String, id: Int) async throws -> SeerDetails {
        try await cached(Self.detailsKey(mediaType: mediaType, id: id), ttl: 10 * 60) {
            try await self.get("\(mediaType)/\(id)", as: SeerDetails.self)
        }
    }

    // MARK: - Requests

    func requests(take: Int = 30, skip: Int = 0,
                  filter: String = "all", sort: String = "modified") async throws -> [SeerRequest] {
        try await cached("requests:\(take):\(skip):\(filter):\(sort)", ttl: 30) {
            try await self.get("request", query: [
                "take": String(take), "skip": String(skip), "filter": filter, "sort": sort,
            ], as: SeerRequestPage.self).results
        }
    }

    /// Cancels/removes a request.
    func deleteRequest(id: Int) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/request/\(id)"))
        request.httpMethod = "DELETE"
        applyAuth(&request)
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        }
        await cache.remove(prefix: "requests:")
        await cache.remove(prefix: "details:")
    }

    // MARK: - Categories

    func genres(_ mediaType: String) async throws -> [SeerGenre] {
        try await cached("genres:\(mediaType)", ttl: 60 * 60) {
            try await self.get("genres/\(mediaType)", as: [SeerGenre].self)
        }
    }

    func upcomingTV(page: Int = 1) async throws -> [SeerResult] {
        try await cached("discover:tv:upcoming:\(page)", ttl: 10 * 60) {
            try await self.get("discover/tv/upcoming", query: ["page": String(page)], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    /// Titles filtered by genre / network / studio (page-based).
    func discover(_ category: SeerCategory, page: Int = 1) async throws -> [SeerResult] {
        let path: String
        switch category.kind {
        case .movieGenre(let id): path = "discover/movies/genre/\(id)"
        case .tvGenre(let id):    path = "discover/tv/genre/\(id)"
        case .network(let id):    path = "discover/tv/network/\(id)"
        case .studio(let id):     path = "discover/movies/studio/\(id)"
        }
        return try await cached("discover:category:\(category.hashValue):\(page)", ttl: 10 * 60) {
            try await self.get(path, query: ["page": String(page)], as: SeerPage.self)
                .results.filter { $0.isMovie || $0.isTV }
        }
    }

    // MARK: - People

    /// A person's bio and photo. Some Jellyseerr versions can't resolve
    /// `person/{id}` from TMDB and return 500 — callers should fall back to
    /// `personFromSearch(name:)`.
    func person(id: Int) async throws -> SeerPerson {
        try await cached("person:\(id)", ttl: 60 * 60) {
            try await self.get("person/\(id)", as: SeerPerson.self)
        }
    }

    /// The titles a person is credited in, most-popular first.
    func personCredits(id: Int) async throws -> [SeerResult] {
        try await cached("person:credits:\(id)", ttl: 60 * 60) {
            try await self.get("person/\(id)/combined_credits", as: SeerPersonCredits.self)
                .cast
                .filter { $0.isMovie || $0.isTV }
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        }
    }

    /// Fallback when the person endpoints 500: the search results for a name
    /// carry a `knownFor` array of that person's notable titles.
    func personFromSearch(id: Int, name: String) async throws -> [SeerResult] {
        try await cached("person:search:\(id):\(name.lowercased())", ttl: 30 * 60) {
            let results = try await self.get("search", query: ["query": name, "page": "1"], as: SeerPage.self).results
            let match = results.first { $0.id == id && $0.isPerson } ?? results.first { $0.isPerson }
            return (match?.knownFor ?? [])
                .filter { $0.isMovie || $0.isTV }
                .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        }
    }

    // MARK: - Request options

    func requestOptions(for media: SeerResult) async throws -> [SeerRequestOption] {
        let kind = media.isMovie ? "radarr" : "sonarr"
        let servers = try await requestServices(kind: kind)
        var options: [SeerRequestOption] = []
        for server in servers {
            // The list endpoint only carries the active ids; the real quality
            // profile + root folder lists come from the per-server detail.
            let details = try? await requestServiceDetails(kind: kind, id: server.id)
            options += Self.options(server: server, details: details)
        }
        return options.sorted(by: Self.sortRequestOptions)
    }

    func prefetch(_ media: SeerResult) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await self.details(for: media) }
            group.addTask { _ = try? await self.ratings(for: media) }
            group.addTask { _ = try? await self.requestOptions(for: media) }
        }

        let loadedDetails = try? await details(for: media)
        guard media.isTV,
              let firstSeason = loadedDetails?.seasons?
                .filter({ $0.seasonNumber > 0 })
                .sorted(by: { $0.seasonNumber < $1.seasonNumber })
                .first?.seasonNumber
        else { return }
        _ = try? await seasonDetails(tvId: media.id, season: firstSeason)
    }

    private func requestServices(kind: String) async throws -> [SeerRequestService] {
        try await cached("services:\(kind)", ttl: 5 * 60) {
            try await self.get("service/\(kind)", as: SeerRequestServiceList.self).services
        }
    }

    private func requestServiceDetails(kind: String, id: Int) async throws -> SeerServiceDetails {
        try await cached("service:\(kind):\(id)", ttl: 5 * 60) {
            try await self.get("service/\(kind)/\(id)", as: SeerServiceDetails.self)
        }
    }

    private static func options(server: SeerRequestService,
                                details: SeerServiceDetails?) -> [SeerRequestOption] {
        // Prefer the full profile list from the detail endpoint; fall back to
        // anything the list carried.
        let profiles = (details?.profiles.isEmpty == false) ? details!.profiles : server.qualityProfiles
        let activeProfileId = server.activeProfileId ?? details?.server?.activeProfileId
        let rootFolder = server.activeDirectory
            ?? details?.server?.activeDirectory
            ?? details?.rootFolders.compactMap(\.path).first
        let languageProfileId = server.activeLanguageProfileId ?? details?.server?.activeLanguageProfileId

        guard !profiles.isEmpty else {
            return [
                SeerRequestOption(serverId: server.id,
                                  serverName: server.displayName,
                                  profileId: activeProfileId,
                                  profileName: activeProfileId.map { "Profile \($0)" } ?? "Default Profile",
                                  rootFolder: rootFolder,
                                  languageProfileId: languageProfileId,
                                  tags: server.tags,
                                  is4K: server.is4k == true,
                                  isDefault: true),
            ]
        }

        return profiles.map { profile in
            SeerRequestOption(serverId: server.id,
                              serverName: server.displayName,
                              profileId: profile.id,
                              profileName: profile.name ?? "Profile \(profile.id)",
                              rootFolder: rootFolder,
                              languageProfileId: languageProfileId,
                              tags: server.tags,
                              is4K: server.is4k == true,
                              isDefault: profile.id == activeProfileId)
        }
    }

    private static func sortRequestOptions(_ lhs: SeerRequestOption, _ rhs: SeerRequestOption) -> Bool {
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        if lhs.is4K != rhs.is4K { return !lhs.is4K }
        if lhs.serverName != rhs.serverName { return lhs.serverName < rhs.serverName }
        return lhs.profileName < rhs.profileName
    }

    /// Requests a movie, or the given seasons of a series (all seasons when nil).
    func request(_ media: SeerResult, seasons: [Int]? = nil,
                 option: SeerRequestOption? = nil) async throws {
        var body: [String: Any] = [
            "mediaType": media.mediaType,
            "mediaId": media.id,
        ]
        if let option {
            if let serverId = option.serverId { body["serverId"] = serverId }
            if let profileId = option.profileId { body["profileId"] = profileId }
            if let rootFolder = option.rootFolder, !rootFolder.isEmpty { body["rootFolder"] = rootFolder }
            if let languageProfileId = option.languageProfileId { body["languageProfileId"] = languageProfileId }
            if let tags = option.tags, !tags.isEmpty { body["tags"] = tags }
        }
        if media.isTV {
            let seasonNumbers: [Int]
            if let seasons {
                seasonNumbers = seasons.filter { $0 > 0 }
            } else {
                let details = try await details(for: media)
                seasonNumbers = (details.seasons ?? []).map(\.seasonNumber).filter { $0 > 0 }
            }
            body["seasons"] = seasonNumbers.isEmpty ? [1] : seasonNumbers
        }

        var request = URLRequest(url: baseURL.appending(path: "api/v1/request"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        }
        await cache.remove(Self.detailsKey(mediaType: media.mediaType, id: media.id))
        await cache.remove(prefix: "requests:")
    }

    private func applyAuth(_ request: inout URLRequest) {
        switch auth {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        case .sessionCookie(let cookie):
            // Send exactly our stored session; don't let URLSession's cookie
            // jar substitute stale ones.
            request.httpShouldHandleCookies = false
            request.setValue("connect.sid=\(cookie)", forHTTPHeaderField: "Cookie")
        }
    }

    /// RFC 3986 unreserved characters. Jellyseerr 3.x rejects requests whose
    /// query values contain unescaped reserved characters (spaces are fine,
    /// but apostrophes, +, & … in a search term cause an HTTP 400), and
    /// URLComponents alone leaves those unescaped.
    private static let strictQueryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func detailsKey(mediaType: String, id: Int) -> String {
        "details:\(mediaType):\(id)"
    }

    private func cached<T>(_ key: String, ttl: TimeInterval,
                           load: @escaping () async throws -> T) async throws -> T {
        try await cache.value(for: key, ttl: ttl, load: load)
    }

    /// GET with automatic retry. Jellyseerr's TMDB-backed endpoints (discover,
    /// season episodes, ratings) 500 or drop the connection transiently, so we
    /// repeat a few times before giving up. Client errors (4xx) and decode
    /// failures aren't retried — repeating won't fix them.
    private func get<T: Decodable>(_ path: String, query: [String: String] = [:],
                                   as type: T.Type, attempts: Int = 3) async throws -> T {
        var lastError: Error = APIError.badStatus(0)
        for attempt in 0..<attempts {
            do {
                return try await performGet(path, query: query, as: type)
            } catch {
                lastError = error
                guard Self.isRetryable(error), attempt < attempts - 1, !Task.isCancelled else { throw error }
                try? await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                if Task.isCancelled { throw error }
            }
        }
        throw lastError
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .network: return true                     // dropped connection, timeout
        case .badStatus(let code): return code >= 500 || code == 429
        default: return false                          // 4xx, decoding: deterministic
        }
    }

    private func performGet<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        var components = URLComponents(
            url: baseURL.appending(path: "api/v1/\(path)"),
            resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.percentEncodedQueryItems = query.map {
                URLQueryItem(
                    name: $0.key,
                    value: $0.value.addingPercentEncoding(withAllowedCharacters: Self.strictQueryAllowed))
            }
        }
        var request = URLRequest(url: components.url!)
        applyAuth(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        }
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
