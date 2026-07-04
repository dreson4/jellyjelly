import Foundation

// MARK: - Jellyseerr DTOs (camelCase JSON)

/// TMDB artwork URL. Some Jellyseerr versions return bare paths ("/abc.jpg"),
/// others full URLs — handle both.
func tmdbImageURL(_ path: String?, size: String) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    if path.hasPrefix("http") { return URL(string: path) }
    return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
}

enum SeerMediaStatus: Int, Codable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5

    /// Jellyseerr keeps growing this enum (6 = deleted, 7 = blocklisted, …).
    /// Treat anything we don't know as "not in the library" instead of
    /// failing the whole page decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = SeerMediaStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .unknown: return ""
        case .pending: return "Requested"
        case .processing: return "Processing"
        case .partiallyAvailable: return "Partially Available"
        case .available: return "Available"
        }
    }
}

struct SeerMediaInfoSeason: Codable, Hashable {
    let seasonNumber: Int?
    let status: SeerMediaStatus?
}

struct SeerMediaInfo: Codable, Hashable {
    let status: SeerMediaStatus?
    var seasons: [SeerMediaInfoSeason]?

    init(status: SeerMediaStatus?, seasons: [SeerMediaInfoSeason]? = nil) {
        self.status = status
        self.seasons = seasons
    }
}

struct SeerResult: Codable, Identifiable, Hashable {
    let id: Int                    // TMDB id
    let mediaType: String          // "movie" | "tv" | "person"
    let title: String?             // movies
    let name: String?              // tv
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?       // movies
    let firstAirDate: String?      // tv
    let voteAverage: Double?
    let popularity: Double?
    var mediaInfo: SeerMediaInfo?
    /// Person search results carry their notable titles here.
    let knownFor: [SeerResult]?

    var displayTitle: String { title ?? name ?? "Untitled" }
    var isMovie: Bool { mediaType == "movie" }
    var isTV: Bool { mediaType == "tv" }
    var isPerson: Bool { mediaType == "person" }

    var year: String? {
        let date = releaseDate ?? firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    var metadataLine: String {
        var parts: [String] = []
        if let year { parts.append(year) }
        parts.append(isMovie ? "Movie" : "Series")
        if let vote = voteAverage, vote > 0 { parts.append(String(format: "★ %.1f", vote)) }
        return parts.joined(separator: "  ·  ")
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    /// Low-res artwork for the ambient background.
    var ambientURL: URL? {
        if let backdropPath { return URL(string: "https://image.tmdb.org/t/p/w300\(backdropPath)") }
        if let posterPath { return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)") }
        return nil
    }

    var status: SeerMediaStatus { mediaInfo?.status ?? .unknown }
}

/// Decodes an element or swallows the failure, so one malformed result
/// can't sink an entire page.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct SeerPage: Decodable {
    let page: Int?
    let totalPages: Int?
    let results: [SeerResult]

    private enum CodingKeys: String, CodingKey { case page, totalPages, results }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(Int.self, forKey: .page)
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages)
        results = try container.decode([FailableDecodable<SeerResult>].self, forKey: .results)
            .compactMap(\.value)
    }
}

struct SeerSeason: Codable, Hashable {
    let seasonNumber: Int
    let episodeCount: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let posterPath: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
    }
}

struct SeerTVDetails: Codable {
    let seasons: [SeerSeason]
}

// MARK: - Per-season episode listing (tv/{id}/season/{n})

struct SeerEpisode: Codable, Identifiable, Hashable {
    let id: Int
    let episodeNumber: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let stillPath: String?

    var stillURL: URL? { tmdbImageURL(stillPath, size: "w500") }

    /// "Jul 4, 2026" from a "2026-07-04" air date.
    var airDateLabel: String? {
        guard let airDate, airDate.count >= 10 else { return nil }
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        guard let date = input.date(from: String(airDate.prefix(10))) else { return nil }
        let output = DateFormatter()
        output.dateFormat = "MMM d, yyyy"
        output.locale = Locale(identifier: "en_US_POSIX")
        return output.string(from: date)
    }
}

struct SeerSeasonDetails: Decodable {
    let episodes: [SeerEpisode]

    private enum CodingKeys: String, CodingKey { case episodes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try container.decodeIfPresent([FailableDecodable<SeerEpisode>].self, forKey: .episodes)?
            .compactMap(\.value) ?? []
    }
}

struct SeerUser: Codable {
    let id: Int
    let displayName: String?
}

// MARK: - Full title details (movie/{id} and tv/{id} share most fields)

struct SeerGenre: Codable, Hashable {
    let id: Int?
    let name: String?
}

struct SeerCastMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let character: String?
    let profilePath: String?

    var imageURL: URL? { tmdbImageURL(profilePath, size: "w300") }
}

struct SeerCredits: Codable {
    let cast: [SeerCastMember]?
}

struct SeerDetails: Decodable {
    let id: Int
    let title: String?             // movies
    let name: String?              // tv
    let tagline: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?       // movies
    let firstAirDate: String?      // tv
    let runtime: Int?              // movies, minutes
    let genres: [SeerGenre]?
    let status: String?            // "Released", "Returning Series", …
    let voteAverage: Double?
    let credits: SeerCredits?
    let seasons: [SeerSeason]?     // tv
    let mediaInfo: SeerMediaInfo?

    var displayTitle: String { title ?? name ?? "Untitled" }

    var year: String? {
        let date = releaseDate ?? firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    /// "1h 49m" for movies, "3 Seasons" for series.
    var lengthLabel: String? {
        if let runtime, runtime > 0 {
            return runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m"
        }
        if let seasons {
            let count = seasons.filter { $0.seasonNumber > 0 }.count
            if count > 0 { return count == 1 ? "1 Season" : "\(count) Seasons" }
        }
        return nil
    }

    var genreLine: String? {
        let names = (genres ?? []).compactMap(\.name).prefix(3)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    var cast: [SeerCastMember] { credits?.cast ?? [] }

    var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
    }

    var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }
}

/// Rotten Tomatoes scores, when Jellyseerr can resolve them.
struct SeerRatings: Decodable {
    let criticsScore: Int?
    let audienceScore: Int?
}

// MARK: - People (person/{id} + person/{id}/combined_credits)

struct SeerPerson: Decodable {
    let id: Int
    let name: String?
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?

    var imageURL: URL? { tmdbImageURL(profilePath, size: "h632") }

    /// "Born July 4, 1971 · New York City" when the pieces are present.
    var lifeLine: String? {
        var parts: [String] = []
        if let born = Self.prettyDate(birthday) {
            if let died = Self.prettyDate(deathday) {
                parts.append("\(born) – \(died)")
            } else {
                parts.append("Born \(born)")
            }
        }
        if let placeOfBirth, !placeOfBirth.isEmpty { parts.append(placeOfBirth) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private static func prettyDate(_ raw: String?) -> String? {
        guard let raw, raw.count >= 10 else { return nil }
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        guard let date = input.date(from: String(raw.prefix(10))) else { return nil }
        let output = DateFormatter()
        output.dateFormat = "MMMM d, yyyy"
        output.locale = Locale(identifier: "en_US_POSIX")
        return output.string(from: date)
    }
}

/// person/{id}/combined_credits — the cast array holds the titles they appear in.
struct SeerPersonCredits: Decodable {
    let cast: [SeerResult]

    private enum CodingKeys: String, CodingKey { case cast }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cast = try container.decodeIfPresent([FailableDecodable<SeerResult>].self, forKey: .cast)?
            .compactMap(\.value) ?? []
    }
}
