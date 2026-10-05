import Foundation

public enum MangaFormat: Int, Sendable {
    case image = 0
    case archive = 1
    case unknown = 2
    case epub = 3
    case pdf = 4

    public init(apiValue: Int) {
        self = MangaFormat(rawValue: apiValue) ?? .unknown
    }
}

extension MangaFormat: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.init(apiValue: value)
            return
        }
        self = .unknown
    }
}

public enum LibraryType: Int, Sendable {
    case manga = 0
    case comic = 1
    case book = 2
    case image = 3
    case lightNovel = 4
    case comicVine = 5
    case unknown = -1

    public var title: String {
        switch self {
        case .manga: return "Manga"
        case .comic: return "Comic"
        case .book: return "Books"
        case .image: return "Images"
        case .lightNovel: return "Light Novels"
        case .comicVine: return "Comic"
        case .unknown: return "Library"
        }
    }
}

extension LibraryType: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(Int.self)) ?? -1
        self = LibraryType(rawValue: value) ?? .unknown
    }
}

public enum ReadingKind: String, Sendable {
    case images
    case epub
    case pdf

    public static func kind(for format: MangaFormat) -> ReadingKind {
        switch format {
        case .epub:
            return .epub
        case .pdf:
            return .pdf
        case .image, .archive, .unknown:
            return .images
        }
    }
}

public struct AuthKey: Decodable, Sendable, Equatable {
    public var id: Int?
    public var key: String?
    public var name: String?
}

public struct UserAccount: Decodable, Sendable, Equatable {
    public var id: Int?
    public var username: String?
    public var token: String?
    public var refreshToken: String?
    public var apiKey: String?
    public var kavitaVersion: String?
    public var authKeys: [AuthKey]?
}

public struct TokenPair: Codable, Sendable, Equatable {
    public var token: String?
    public var refreshToken: String?
}

public struct Library: Decodable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var type: LibraryType?

    public var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Library" : trimmed
    }

    public var displayType: String {
        (type ?? .unknown).title
    }
}

public struct Series: Decodable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var originalName: String?
    public var localizedName: String?
    public var pages: Int?
    public var pagesRead: Int?
    public var format: MangaFormat?
    public var libraryId: Int?
    public var libraryName: String?

    public var displayName: String {
        for candidate in [localizedName, name, originalName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Untitled"
    }

    public var pageCount: Int { pages ?? 0 }
    public var pagesReadCount: Int { pagesRead ?? 0 }
    public var resolvedFormat: MangaFormat { format ?? .unknown }
    public var resolvedLibraryId: Int { libraryId ?? 0 }

    public var progressFraction: Double? {
        guard pageCount > 0, pagesReadCount > 0 else { return nil }
        return min(1, Double(pagesReadCount) / Double(pageCount))
    }
}

public struct MangaFile: Decodable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var pages: Int?
    public var format: MangaFormat?
    public var koreaderHash: String?
}

public struct Chapter: Decodable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var number: String?
    public var title: String?
    public var titleName: String?
    public var pages: Int?
    public var pagesRead: Int?
    public var isSpecial: Bool?
    public var volumeId: Int?
    public var files: [MangaFile]?
    public var minNumber: Double?
    public var range: String?

    public var displayTitle: String {
        for candidate in [titleName, title] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if isSpecial == true {
            if let number, !number.isEmpty {
                return "Special \(number)"
            }
            return "Special"
        }
        if let range, !range.isEmpty, range != number {
            return "Chapter \(range)"
        }
        if let number, !number.isEmpty {
            return "Chapter \(number)"
        }
        return "Chapter"
    }

    public var pageCount: Int {
        if let filePages = files?.first?.pages, filePages > 0 {
            return filePages
        }
        return pages ?? 0
    }

    public var resolvedFormat: MangaFormat {
        files?.first?.format ?? .unknown
    }

    public var koreaderHash: String? {
        let hash = files?.first?.koreaderHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash, !hash.isEmpty {
            return hash
        }
        return nil
    }
}

public struct Volume: Decodable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var number: Int?
    public var pages: Int?
    public var pagesRead: Int?
    public var chapters: [Chapter]?

    public var displayTitle: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty && trimmed != "0" {
            return trimmed
        }
        let value = number ?? 0
        if value <= 0 {
            return "Chapters"
        }
        return "Volume \(value)"
    }
}

public struct ChapterInfo: Decodable, Sendable, Equatable {
    public var pages: Int?
    public var seriesFormat: MangaFormat?
    public var seriesId: Int?
    public var libraryId: Int?
    public var volumeId: Int?
    public var seriesName: String?
    public var chapterTitle: String?
    public var fileName: String?
    public var chapterNumber: String?
    public var volumeNumber: String?
    public var isSpecial: Bool?
}

public struct BookInfo: Decodable, Sendable, Equatable {
    public var bookTitle: String?
    public var pages: Int?
    public var seriesFormat: MangaFormat?
    public var seriesId: Int?
    public var volumeId: Int?
    public var libraryId: Int?
    public var seriesName: String?
    public var chapterTitle: String?
}

public struct BookChapterItem: Decodable, Sendable, Equatable {
    public var title: String?
    public var part: String?
    public var page: Int?
    public var children: [BookChapterItem]?
}

public struct SearchHit: Decodable, Identifiable, Sendable, Equatable {
    public var seriesId: Int
    public var name: String?
    public var localizedName: String?
    public var originalName: String?
    public var format: MangaFormat?
    public var libraryId: Int?
    public var libraryName: String?

    public var id: Int { seriesId }

    public var displayName: String {
        for candidate in [localizedName, name, originalName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Untitled"
    }
}

public struct SearchResultGroup: Decodable, Sendable, Equatable {
    public var libraries: [Library]?
    public var series: [SearchHit]?
}

public struct ReadingProgress: Decodable, Sendable, Equatable {
    public var volumeId: Int?
    public var chapterId: Int?
    public var pageNum: Int?
    public var seriesId: Int?
    public var libraryId: Int?
    public var bookScrollId: String?
}

public struct KoreaderBook: Decodable, Sendable, Equatable {
    public var document: String?
    public var deviceId: String?
    public var device: String?
    public var percentage: Double?
    public var progress: String?
    public var timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case document
        case deviceId = "device_id"
        case device
        case percentage
        case progress
        case timestamp
    }
}

public struct Pagination: Decodable, Sendable, Equatable {
    public var currentPage: Int
    public var itemsPerPage: Int
    public var totalItems: Int
    public var totalPages: Int
}

public struct Page<Item: Decodable & Sendable>: Sendable {
    public var items: [Item]
    public var pagination: Pagination?

    public init(items: [Item], pagination: Pagination?) {
        self.items = items
        self.pagination = pagination
    }
}

public enum APIKeySelection {
    /// Prefer the OPDS key Kavita returns as `apiKey`. That key authenticates image,
    /// reader, and KOReader routes. Fall back to any non-image key, then any key.
    public static func preferred(apiKey: String?, authKeys: [AuthKey]) -> String? {
        if let apiKey = cleaned(apiKey) {
            return apiKey
        }
        if let opds = authKeys.first(where: { $0.name == "opds" }), let key = cleaned(opds.key) {
            return key
        }
        if let general = authKeys.first(where: { $0.name != "image-only" }), let key = cleaned(general.key) {
            return key
        }
        return authKeys.compactMap { cleaned($0.key) }.first
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
