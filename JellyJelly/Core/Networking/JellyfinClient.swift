import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case unauthorized
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid server address."
        case .badStatus(let code): return "Server responded with an error (HTTP \(code))."
        case .unauthorized: return "Wrong username or password."
        case .decoding: return "Couldn't read the server's response."
        case .network(let error): return "Couldn't reach the server. \(error.localizedDescription)"
        }
    }
}

/// Thin async client for the Jellyfin REST API.
final class JellyfinClient {
    let baseURL: URL
    let userId: String
    private let token: String
    private let deviceId: String

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromPascalCase
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToPascalCase
        return encoder
    }()

    init(baseURL: URL, token: String, userId: String, deviceId: String) {
        self.baseURL = baseURL
        self.token = token
        self.userId = userId
        self.deviceId = deviceId
    }

    convenience init(profile: ServerProfile, deviceId: String) {
        self.init(baseURL: profile.jellyfinURL, token: profile.accessToken,
                  userId: profile.userId, deviceId: deviceId)
    }

    // MARK: - Unauthenticated endpoints

    static func probe(url: URL) async throws -> PublicSystemInfo {
        let probeURL = url.appending(path: "System/Info/Public")
        let (data, response) = try await fetch(URLRequest(url: probeURL))
        try validate(response)
        return try decode(PublicSystemInfo.self, from: data)
    }

    static func authenticate(url: URL, username: String, password: String,
                             deviceId: String) async throws -> AuthenticationResult {
        var request = URLRequest(url: url.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(deviceId: deviceId, token: nil),
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password,
        ])
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw APIError.unauthorized
        }
        try validate(response)
        return try decode(AuthenticationResult.self, from: data)
    }

    /// Validates the stored token by fetching the signed-in user.
    func currentUser() async throws -> JellyfinUser {
        try await get("Users/Me", as: JellyfinUser.self)
    }

    // MARK: - Library

    func userViews() async throws -> [BaseItem] {
        try await get("Users/\(userId)/Views", as: ItemsResult.self).items
    }

    func resumeItems(limit: Int = 20) async throws -> [BaseItem] {
        try await get("Users/\(userId)/Items/Resume", query: [
            "limit": String(limit),
            "mediaTypes": "Video",
            "fields": "Overview",
        ], as: ItemsResult.self).items
    }

    func nextUp(seriesId: String? = nil, limit: Int = 20) async throws -> [BaseItem] {
        var query = ["userId": userId, "limit": String(limit), "fields": "Overview"]
        if let seriesId { query["seriesId"] = seriesId }
        return try await get("Shows/NextUp", query: query, as: ItemsResult.self).items
    }

    func latest(parentId: String?, limit: Int = 20) async throws -> [BaseItem] {
        var query = ["limit": String(limit), "fields": "Overview"]
        if let parentId { query["parentId"] = parentId }
        return try await get("Users/\(userId)/Items/Latest", query: query, as: [BaseItem].self)
    }

    func items(includeTypes: String, sortBy: String = "SortName", sortOrder: String = "Ascending",
               parentId: String? = nil, startIndex: Int = 0, limit: Int = 60) async throws -> ItemsResult {
        var query = [
            "includeItemTypes": includeTypes,
            "recursive": "true",
            "sortBy": sortBy,
            "sortOrder": sortOrder,
            "startIndex": String(startIndex),
            "limit": String(limit),
            "fields": "Overview",
        ]
        if let parentId { query["parentId"] = parentId }
        return try await get("Users/\(userId)/Items", query: query, as: ItemsResult.self)
    }

    func item(id: String) async throws -> BaseItem {
        try await get("Users/\(userId)/Items/\(id)",
                      query: ["fields": "Overview,People,Genres"], as: BaseItem.self)
    }

    /// Everything a person appears in, newest first — for the person detail page.
    func items(personId: String, limit: Int = 60) async throws -> [BaseItem] {
        try await get("Users/\(userId)/Items", query: [
            "personIds": personId,
            "recursive": "true",
            "includeItemTypes": "Movie,Series",
            "sortBy": "PremiereDate,ProductionYear,SortName",
            "sortOrder": "Descending",
            "limit": String(limit),
            "fields": "Overview",
        ], as: ItemsResult.self).items
    }

    func seasons(seriesId: String) async throws -> [BaseItem] {
        try await get("Shows/\(seriesId)/Seasons", query: ["userId": userId], as: ItemsResult.self).items
    }

    func episodes(seriesId: String, seasonId: String) async throws -> [BaseItem] {
        try await get("Shows/\(seriesId)/Episodes", query: [
            "userId": userId,
            "seasonId": seasonId,
            "fields": "Overview",
        ], as: ItemsResult.self).items
    }

    func similar(to itemId: String, limit: Int = 16) async throws -> [BaseItem] {
        try await get("Items/\(itemId)/Similar", query: [
            "userId": userId,
            "limit": String(limit),
        ], as: ItemsResult.self).items
    }

    func search(term: String, limit: Int = 40) async throws -> [BaseItem] {
        try await get("Users/\(userId)/Items", query: [
            "searchTerm": term,
            "recursive": "true",
            "includeItemTypes": "Movie,Series",
            "limit": String(limit),
            "fields": "Overview",
        ], as: ItemsResult.self).items
    }

    // MARK: - Played / favorite state

    func setPlayed(_ played: Bool, itemId: String) async throws {
        try await send(played ? "POST" : "DELETE", path: "Users/\(userId)/PlayedItems/\(itemId)")
    }

    func setFavorite(_ favorite: Bool, itemId: String) async throws {
        try await send(favorite ? "POST" : "DELETE", path: "Users/\(userId)/FavoriteItems/\(itemId)")
    }

    // MARK: - Images

    enum ImageKind: String {
        case primary = "Primary"
        case backdrop = "Backdrop"
        case thumb = "Thumb"
    }

    func imageURL(itemId: String, kind: ImageKind = .primary, tag: String? = nil, maxWidth: Int = 480) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: "Items/\(itemId)/Images/\(kind.rawValue)"),
            resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90"),
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        components.queryItems = query
        return components.url!
    }

    /// Headshot for a cast member, or nil when the server has no photo for them.
    func personImageURL(_ person: BaseItemPerson, maxWidth: Int = 300) -> URL? {
        guard let tag = person.primaryImageTag else { return nil }
        return imageURL(itemId: person.id, kind: .primary, tag: tag, maxWidth: maxWidth)
    }

    /// Poster image for shelves and grids. Episodes fall back to their series poster.
    func posterURL(for item: BaseItem, maxWidth: Int = 480) -> URL? {
        if let tag = item.imageTags?["Primary"], !item.isEpisode {
            return imageURL(itemId: item.id, kind: .primary, tag: tag, maxWidth: maxWidth)
        }
        if item.isEpisode, let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, kind: .primary, tag: item.seriesPrimaryImageTag, maxWidth: maxWidth)
        }
        if item.imageTags?["Primary"] != nil {
            return imageURL(itemId: item.id, kind: .primary, maxWidth: maxWidth)
        }
        return nil
    }

    /// Wide image: episode stills, or backdrops for movies/series.
    func wideImageURL(for item: BaseItem, maxWidth: Int = 800) -> URL? {
        if item.isEpisode, item.imageTags?["Primary"] != nil {
            return imageURL(itemId: item.id, kind: .primary, maxWidth: maxWidth)
        }
        return backdropURL(for: item, maxWidth: maxWidth)
    }

    /// Small artwork for the ambient background — it gets blurred to a wash,
    /// so a low-res fetch keeps focus changes cheap.
    func ambientImageURL(for item: BaseItem) -> URL? {
        backdropURL(for: item, maxWidth: 480) ?? posterURL(for: item, maxWidth: 320)
    }

    func backdropURL(for item: BaseItem, maxWidth: Int = 1920) -> URL? {
        if item.backdropImageTags?.isEmpty == false {
            return imageURL(itemId: item.id, kind: .backdrop, tag: item.backdropImageTags?.first, maxWidth: maxWidth)
        }
        if let parentId = item.parentBackdropItemId, item.parentBackdropImageTags?.isEmpty == false {
            return imageURL(itemId: parentId, kind: .backdrop, tag: item.parentBackdropImageTags?.first, maxWidth: maxWidth)
        }
        if let seriesId = item.seriesId {
            return imageURL(itemId: seriesId, kind: .backdrop, maxWidth: maxWidth)
        }
        return nil
    }

    // MARK: - Playback

    /// Negotiates how to stream an item: direct play when the container/codec
    /// allow it, otherwise the server's HLS transcode.
    func playbackContext(for item: BaseItem, startAtSeconds: Double) async throws -> PlaybackContext {
        let startTicks = Int64(startAtSeconds * 10_000_000)
        var components = URLComponents(
            url: baseURL.appending(path: "Items/\(item.id)/PlaybackInfo"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "StartTimeTicks", value: String(startTicks)),
            URLQueryItem(name: "IsPlayback", value: "true"),
            URLQueryItem(name: "AutoOpenLiveStream", value: "true"),
            URLQueryItem(name: "MaxStreamingBitrate", value: "120000000"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.httpBody = try Self.encoder.encode(PlaybackInfoRequest(deviceProfile: .appleTV))

        let (data, response) = try await Self.fetch(request)
        try Self.validate(response)
        let info = try Self.decode(PlaybackInfoResponse.self, from: data)

        guard let source = info.mediaSources.first else {
            throw APIError.badStatus(404)
        }

        if source.supportsDirectPlay == true || source.supportsDirectStream == true,
           source.transcodingUrl == nil {
            var stream = URLComponents(
                url: baseURL.appending(path: "Videos/\(item.id)/stream.\(source.container ?? "mp4")"),
                resolvingAgainstBaseURL: false)!
            var query = [
                URLQueryItem(name: "Static", value: "true"),
                URLQueryItem(name: "api_key", value: token),
                URLQueryItem(name: "DeviceId", value: deviceId),
            ]
            if let sourceId = source.id { query.append(URLQueryItem(name: "MediaSourceId", value: sourceId)) }
            if let tag = source.eTag { query.append(URLQueryItem(name: "Tag", value: tag)) }
            if let session = info.playSessionId { query.append(URLQueryItem(name: "PlaySessionId", value: session)) }
            stream.queryItems = query
            return PlaybackContext(item: item, streamURL: stream.url!,
                                   playSessionId: info.playSessionId, mediaSourceId: source.id,
                                   playMethod: "DirectPlay",
                                   startOffsetSeconds: 0, seekOnStartSeconds: startAtSeconds)
        }

        guard let transcodingPath = source.transcodingUrl,
              let streamURL = URL(string: transcodingPath, relativeTo: baseURL) else {
            throw APIError.badStatus(500)
        }
        return PlaybackContext(item: item, streamURL: streamURL.absoluteURL,
                               playSessionId: info.playSessionId, mediaSourceId: source.id,
                               playMethod: "Transcode",
                               startOffsetSeconds: startAtSeconds, seekOnStartSeconds: 0)
    }

    // MARK: - Playback progress reporting

    func reportPlaybackStart(_ context: PlaybackContext, positionSeconds: Double) async {
        await report(path: "Sessions/Playing", context: context,
                     positionSeconds: positionSeconds, isPaused: false)
    }

    func reportPlaybackProgress(_ context: PlaybackContext, positionSeconds: Double, isPaused: Bool) async {
        await report(path: "Sessions/Playing/Progress", context: context,
                     positionSeconds: positionSeconds, isPaused: isPaused)
    }

    func reportPlaybackStopped(_ context: PlaybackContext, positionSeconds: Double) async {
        await report(path: "Sessions/Playing/Stopped", context: context,
                     positionSeconds: positionSeconds, isPaused: false)
    }

    private func report(path: String, context: PlaybackContext,
                        positionSeconds: Double, isPaused: Bool) async {
        var body: [String: Any] = [
            "ItemId": context.item.id,
            "PositionTicks": Int64(positionSeconds * 10_000_000),
            "IsPaused": isPaused,
            "PlayMethod": context.playMethod,
            "CanSeek": true,
        ]
        if let session = context.playSessionId { body["PlaySessionId"] = session }
        if let sourceId = context.mediaSourceId { body["MediaSourceId"] = sourceId }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await Self.fetch(request)
    }

    // MARK: - Request plumbing

    private static func authorizationHeader(deviceId: String, token: String?) -> String {
        var header = "MediaBrowser Client=\"JellyJelly\", Device=\"Apple TV\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
        if let token { header += ", Token=\"\(token)\"" }
        return header
    }

    private func applyAuth(_ request: inout URLRequest) {
        request.setValue(Self.authorizationHeader(deviceId: deviceId, token: token),
                         forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        applyAuth(&request)
        let (data, response) = try await Self.fetch(request)
        try Self.validate(response)
        return try Self.decode(type, from: data)
    }

    private func send(_ method: String, path: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        applyAuth(&request)
        let (_, response) = try await Self.fetch(request)
        try Self.validate(response)
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

// MARK: - Device profile sent with PlaybackInfo

private struct PlaybackInfoRequest: Encodable {
    let deviceProfile: DeviceProfile
}

private struct DeviceProfile: Encodable {
    struct DirectPlayProfile: Encodable {
        let container: String
        let type: String
        let videoCodec: String?
        let audioCodec: String?
    }
    struct TranscodingProfile: Encodable {
        let container: String
        let type: String
        let videoCodec: String
        let audioCodec: String
        let `protocol`: String
        let context: String
        let maxAudioChannels: String
        let minSegments: Int
        let breakOnNonKeyFrames: Bool
    }
    struct SubtitleProfile: Encodable {
        let format: String
        let method: String
    }

    let maxStreamingBitrate: Int
    let directPlayProfiles: [DirectPlayProfile]
    let transcodingProfiles: [TranscodingProfile]
    let subtitleProfiles: [SubtitleProfile]

    /// What an Apple TV can play natively; everything else transcodes to HLS.
    static let appleTV = DeviceProfile(
        maxStreamingBitrate: 120_000_000,
        directPlayProfiles: [
            DirectPlayProfile(container: "mp4,m4v,mov", type: "Video",
                              videoCodec: "hevc,h264",
                              audioCodec: "aac,mp3,ac3,eac3,flac,alac"),
        ],
        transcodingProfiles: [
            TranscodingProfile(container: "ts", type: "Video",
                               videoCodec: "hevc,h264", audioCodec: "aac,ac3,eac3",
                               protocol: "hls", context: "Streaming",
                               maxAudioChannels: "6", minSegments: 1,
                               breakOnNonKeyFrames: true),
        ],
        subtitleProfiles: [
            SubtitleProfile(format: "vtt", method: "Hls"),
            SubtitleProfile(format: "vtt", method: "External"),
        ])
}
