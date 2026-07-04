import Foundation

// MARK: - Server profiles persisted across launches

/// One signed-in Jellyfin server, with an optional Jellyseerr paired to it.
/// Users can keep any number of these and switch between them.
struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var jellyfinURL: URL
    var accessToken: String
    var userId: String
    var username: String

    var jellyseerrURL: URL?
    var jellyseerrAPIKey: String?
    /// Session cookie from signing in to Jellyseerr with the Jellyfin account —
    /// the default connection method; the API key is the manual alternative.
    var jellyseerrCookie: String?

    var hasJellyseerr: Bool {
        jellyseerrURL != nil
            && (jellyseerrAPIKey?.isEmpty == false || jellyseerrCookie?.isEmpty == false)
    }
}

// MARK: - Jellyfin DTOs (PascalCase JSON, decoded via .convertFromPascalCase)

struct PublicSystemInfo: Codable {
    let serverName: String?
    let version: String?
    let id: String?
}

struct AuthenticationResult: Codable {
    let user: JellyfinUser
    let accessToken: String
}

struct JellyfinUser: Codable {
    let id: String
    let name: String
}

struct UserItemData: Codable, Hashable {
    var playedPercentage: Double?
    var playbackPositionTicks: Int64?
    var played: Bool?
    var isFavorite: Bool?
    var unplayedItemCount: Int?
}

struct BaseItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let type: String?
    let overview: String?
    let taglines: [String]?
    let genres: [String]?
    let productionYear: Int?
    let premiereDate: String?
    let officialRating: String?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    let seasonName: String?
    let seriesPrimaryImageTag: String?
    let parentBackdropItemId: String?
    let parentBackdropImageTags: [String]?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let childCount: Int?
    let collectionType: String?
    let people: [BaseItemPerson]?
    var userData: UserItemData?

    var isSeries: Bool { type == "Series" }
    var isEpisode: Bool { type == "Episode" }
    var isMovie: Bool { type == "Movie" }

    var runtimeMinutes: Int? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        return Int(ticks / 600_000_000)
    }

    var resumePositionSeconds: Double {
        Double(userData?.playbackPositionTicks ?? 0) / 10_000_000
    }

    var playedFraction: Double? {
        guard let pct = userData?.playedPercentage, pct > 0 else { return nil }
        return min(max(pct / 100, 0), 1)
    }

    /// Line like "2024 · TV-MA · 2h 15m · ★ 7.8"
    var metadataLine: String {
        var parts: [String] = []
        if let year = productionYear { parts.append(String(year)) }
        if let rating = officialRating { parts.append(rating) }
        if let minutes = runtimeMinutes, minutes > 0 {
            if minutes >= 60 { parts.append("\(minutes / 60)h \(minutes % 60)m") }
            else { parts.append("\(minutes)m") }
        }
        if let stars = communityRating { parts.append(String(format: "★ %.1f", stars)) }
        return parts.joined(separator: "  ·  ")
    }

    /// "S1 E4" style label for episodes.
    var episodeLabel: String? {
        guard isEpisode else { return nil }
        var parts: [String] = []
        if let season = parentIndexNumber { parts.append("S\(season)") }
        if let ep = indexNumber { parts.append("E\(ep)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// A cast/crew member attached to a Jellyfin item (People array).
struct BaseItemPerson: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let role: String?          // character name, for actors
    let type: String?          // "Actor", "Director", "Writer", …
    let primaryImageTag: String?

    var isActor: Bool { type == "Actor" }
}

struct ItemsResult: Codable {
    let items: [BaseItem]
    let totalRecordCount: Int?
}

// MARK: - Playback

struct PlaybackInfoResponse: Codable {
    let mediaSources: [MediaSourceInfo]
    let playSessionId: String?
}

struct MediaSourceInfo: Codable {
    let id: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let transcodingUrl: String?
    let eTag: String?
    let runTimeTicks: Int64?
}

/// Everything the player needs to stream one item and report progress.
struct PlaybackContext: Identifiable {
    let id = UUID()
    let item: BaseItem
    let streamURL: URL
    let playSessionId: String?
    let mediaSourceId: String?
    let playMethod: String
    /// Non-zero when the server started the HLS transcode mid-item; playback
    /// timestamps must be shifted by this amount when reporting progress.
    let startOffsetSeconds: Double
    /// Whether the player itself should seek (direct play resumes locally).
    let seekOnStartSeconds: Double
}

// MARK: - PascalCase decoding support

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
}

extension JSONDecoder.KeyDecodingStrategy {
    /// Jellyfin returns PascalCase keys ("RunTimeTicks"); lowercase the first letter.
    static let convertFromPascalCase = JSONDecoder.KeyDecodingStrategy.custom { keys in
        let key = keys.last!.stringValue
        return AnyCodingKey(stringValue: key.prefix(1).lowercased() + key.dropFirst())
    }
}

extension JSONEncoder.KeyEncodingStrategy {
    /// Mirror of `convertFromPascalCase` for request bodies.
    static let convertToPascalCase = JSONEncoder.KeyEncodingStrategy.custom { keys in
        let key = keys.last!.stringValue
        return AnyCodingKey(stringValue: key.prefix(1).uppercased() + key.dropFirst())
    }
}
