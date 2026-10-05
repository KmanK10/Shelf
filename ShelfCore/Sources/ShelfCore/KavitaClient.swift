import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls confirmed against Kavita OpenAPI 0.9.1.10 (`develop`) and the matching controllers.
public actor KavitaClient {
    /// Immutable server origin. URL builders below are `nonisolated` and only read this.
    public nonisolated let address: ServerAddress
    private let session: URLSession
    private var token: String
    private var apiKey: String

    public init(address: ServerAddress, token: String = "", apiKey: String = "", session: URLSession = .shared) {
        self.address = address
        self.token = token
        self.apiKey = apiKey
        self.session = session
    }

    public func setToken(_ token: String) {
        self.token = token
    }

    public func setAPIKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    public var currentAPIKey: String { apiKey }

    public static func login(address: ServerAddress, username: String, password: String, session: URLSession = .shared) async throws -> UserAccount {
        let body = try JSONEncoder().encode(LoginBody(username: username, password: password))
        let request = try makeRequest(address: address, path: "Account/login", method: "POST", body: body, token: nil)
        let (data, _) = try await send(request, session: session)
        return try decode(UserAccount.self, from: data)
    }

    public static func refresh(address: ServerAddress, token: String, refreshToken: String, session: URLSession = .shared) async throws -> TokenPair {
        let body = try JSONEncoder().encode(TokenPair(token: token, refreshToken: refreshToken))
        let request = try makeRequest(address: address, path: "Account/refresh-token", method: "POST", body: body, token: nil)
        let (data, _) = try await send(request, session: session)
        return try decode(TokenPair.self, from: data)
    }

    public func createAuthKey(name: String, length: Int = 32) async throws -> AuthKey {
        let body = try JSONEncoder().encode(CreateAuthKeyBody(keyLength: length, name: name))
        let request = try request(path: "Account/create-auth-key", method: "POST", body: body)
        let (data, _) = try await perform(request)
        return try Self.decode(AuthKey.self, from: data)
    }

    public func libraries() async throws -> [Library] {
        let request = try request(path: "Library/libraries")
        let (data, _) = try await perform(request)
        return try Self.decode([Library].self, from: data)
    }

    public func series(in libraryId: Int, page: Int, pageSize: Int) async throws -> Page<Series> {
        let body = try JSONEncoder().encode(LibrarySeriesQuery.forLibrary(libraryId))
        let request = try request(
            path: "Series/v2",
            method: "POST",
            query: pageQuery(page: page, pageSize: pageSize),
            body: body
        )
        let (data, response) = try await perform(request)
        let items = try Self.decode([Series].self, from: data)
        return Page(items: items, pagination: Self.pagination(from: response))
    }

    public func onDeck(libraryId: Int = 0, page: Int, pageSize: Int) async throws -> Page<Series> {
        var query = pageQuery(page: page, pageSize: pageSize)
        query.append(URLQueryItem(name: "libraryId", value: String(libraryId)))
        let request = try request(path: "Series/on-deck", method: "POST", query: query, body: Data("{}".utf8))
        let (data, response) = try await perform(request)
        let items = try Self.decode([Series].self, from: data)
        return Page(items: items, pagination: Self.pagination(from: response))
    }

    public func search(query: String) async throws -> SearchResultGroup {
        let request = try request(path: "Search/search", query: [
            URLQueryItem(name: "queryString", value: query),
            URLQueryItem(name: "includeChapterAndFiles", value: "false")
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(SearchResultGroup.self, from: data)
    }

    public func series(id: Int) async throws -> Series {
        let request = try request(path: "Series/\(id)")
        let (data, _) = try await perform(request)
        return try Self.decode(Series.self, from: data)
    }

    public func volumes(seriesId: Int) async throws -> [Volume] {
        let request = try request(path: "Series/volumes", query: [
            URLQueryItem(name: "seriesId", value: String(seriesId))
        ])
        let (data, _) = try await perform(request)
        return try Self.decode([Volume].self, from: data)
    }

    public func chapter(id: Int) async throws -> Chapter {
        let request = try request(path: "Series/chapter", query: [
            URLQueryItem(name: "chapterId", value: String(id))
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(Chapter.self, from: data)
    }

    public func continuePoint(seriesId: Int) async throws -> Chapter {
        let request = try request(path: "Reader/continue-point", query: [
            URLQueryItem(name: "seriesId", value: String(seriesId))
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(Chapter.self, from: data)
    }

    public func chapterInfo(chapterId: Int) async throws -> ChapterInfo {
        let request = try request(path: "Reader/chapter-info", query: [
            URLQueryItem(name: "chapterId", value: String(chapterId)),
            URLQueryItem(name: "includeDimensions", value: "false")
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(ChapterInfo.self, from: data)
    }

    public func bookInfo(chapterId: Int) async throws -> BookInfo {
        let request = try request(path: "Book/\(chapterId)/book-info")
        let (data, _) = try await perform(request)
        return try Self.decode(BookInfo.self, from: data)
    }

    public func bookChapters(chapterId: Int) async throws -> [BookChapterItem] {
        let request = try request(path: "Book/\(chapterId)/chapters")
        let (data, _) = try await perform(request)
        return try Self.decode([BookChapterItem].self, from: data)
    }

    /// Spine HTML from the book reader. Kavita JSON-encodes the fragment.
    public func bookPage(chapterId: Int, page: Int) async throws -> String {
        let request = try request(path: "Book/\(chapterId)/book-page", query: [
            URLQueryItem(name: "page", value: String(page))
        ])
        let (data, response) = try await perform(request)
        let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        if type.contains("json"), let fragment = try? JSONDecoder().decode(String.self, from: data) {
            return fragment
        }
        if let fragment = String(data: data, encoding: .utf8) {
            if fragment.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: data) {
                return decoded
            }
            return fragment
        }
        throw KavitaError.decoding("Book page was not text.")
    }

    public func progress(chapterId: Int) async throws -> ReadingProgress {
        let request = try request(path: "Reader/get-progress", query: [
            URLQueryItem(name: "chapterId", value: String(chapterId))
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(ReadingProgress.self, from: data)
    }

    public func saveProgress(volumeId: Int, chapterId: Int, pageNum: Int, seriesId: Int, libraryId: Int, bookScrollId: String?) async throws {
        let body = try JSONEncoder().encode(ProgressBody(
            volumeId: volumeId,
            chapterId: chapterId,
            pageNum: pageNum,
            seriesId: seriesId,
            libraryId: libraryId,
            bookScrollId: bookScrollId
        ))
        let request = try request(path: "Reader/progress", method: "POST", body: body)
        _ = try await perform(request)
    }

    /// `nil` when Kavita has no progress yet (the controller returns 400).
    public func koreaderProgress(hash: String) async throws -> KoreaderBook? {
        let request = try request(path: "Koreader/\(pathEscape(apiKey))/syncs/progress/\(pathEscape(hash))")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KavitaError.transport("The server did not return an HTTP response.")
        }
        if http.statusCode == 400 {
            return nil
        }
        if http.statusCode == 401 {
            throw KavitaError.unauthorized(Self.message(from: data) ?? "Sign in again.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KavitaError.http(http.statusCode, Self.message(from: data) ?? "Kavita could not read reading progress.")
        }
        if data.isEmpty {
            return nil
        }
        return try Self.decode(KoreaderBook.self, from: data)
    }

    public func saveKoreaderProgress(_ payload: KoreaderSyncPayload) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try request(path: "Koreader/\(pathEscape(apiKey))/syncs/progress", method: "PUT", body: body)
        _ = try await perform(request)
    }

    public func nextChapter(seriesId: Int, volumeId: Int, chapterId: Int) async throws -> Int {
        try await adjacentChapter(path: "Reader/next-chapter", seriesId: seriesId, volumeId: volumeId, chapterId: chapterId)
    }

    public func previousChapter(seriesId: Int, volumeId: Int, chapterId: Int) async throws -> Int {
        try await adjacentChapter(path: "Reader/prev-chapter", seriesId: seriesId, volumeId: volumeId, chapterId: chapterId)
    }

    /// Image and PDF URLs are pure functions of the server address and an API key.
    /// The key is an argument so these can be called synchronously from outside the actor.
    public nonisolated func seriesCoverURL(seriesId: Int, apiKey: String) -> URL? {
        address.endpoint("Image/series-cover", query: [
            URLQueryItem(name: "seriesId", value: String(seriesId)),
            URLQueryItem(name: "apiKey", value: apiKey)
        ])
    }

    public nonisolated func libraryCoverURL(libraryId: Int, apiKey: String) -> URL? {
        address.endpoint("Image/library-cover", query: [
            URLQueryItem(name: "libraryId", value: String(libraryId)),
            URLQueryItem(name: "apiKey", value: apiKey)
        ])
    }

    public nonisolated func readerPageURL(chapterId: Int, page: Int, apiKey: String) -> URL? {
        address.endpoint("Reader/image", query: [
            URLQueryItem(name: "chapterId", value: String(chapterId)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "apiKey", value: apiKey)
        ])
    }

    public nonisolated func pdfURL(chapterId: Int, apiKey: String) -> URL? {
        address.endpoint("Reader/pdf", query: [
            URLQueryItem(name: "chapterId", value: String(chapterId)),
            URLQueryItem(name: "apiKey", value: apiKey)
        ])
    }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await perform(request)
        return data
    }

    private func adjacentChapter(path: String, seriesId: Int, volumeId: Int, chapterId: Int) async throws -> Int {
        let request = try request(path: path, query: [
            URLQueryItem(name: "seriesId", value: String(seriesId)),
            URLQueryItem(name: "volumeId", value: String(volumeId)),
            URLQueryItem(name: "currentChapterId", value: String(chapterId))
        ])
        let (data, _) = try await perform(request)
        return try Self.decode(Int.self, from: data)
    }

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        try Self.makeRequest(address: address, path: path, method: method, query: query, body: body, token: token)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Self.send(request, session: session)
    }

    private static func makeRequest(
        address: ServerAddress,
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        token: String?
    ) throws -> URLRequest {
        guard let url = address.endpoint(path, query: query) else {
            throw KavitaError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as KavitaError {
            throw error
        } catch let error as URLError {
            throw KavitaError.transport(error.localizedDescription)
        } catch {
            throw KavitaError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KavitaError.transport("The server did not return an HTTP response.")
        }
        if http.statusCode == 401 {
            throw KavitaError.unauthorized(message(from: data) ?? "Your credentials are not correct.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KavitaError.http(http.statusCode, message(from: data) ?? "Kavita returned HTTP \(http.statusCode).")
        }
        return (data, http)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KavitaError.decoding(String(describing: error))
        }
    }

    static func pagination(from response: HTTPURLResponse) -> Pagination? {
        guard let header = response.value(forHTTPHeaderField: "Pagination"),
              let data = header.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(Pagination.self, from: data)
    }

    static func message(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            if let message = object.message, !message.isEmpty { return message }
            if let title = object.title, !title.isEmpty { return title }
        }
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return nil
            }
            if !trimmed.isEmpty {
                return String(trimmed.prefix(300))
            }
        }
        return nil
    }

    private func pageQuery(page: Int, pageSize: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "pageNumber", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
    }

    private func pathEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct LoginBody: Encodable {
    var username: String
    var password: String
}

private struct CreateAuthKeyBody: Encodable {
    var keyLength: Int
    var name: String
}

struct LibrarySeriesQuery: Encodable, Equatable {
    var statements: [Statement]
    var combination: Int
    var limitTo: Int
    var sortOptions: SortOptions

    struct Statement: Encodable, Equatable {
        var comparison: Int
        var field: Int
        var value: String
    }

    struct SortOptions: Encodable, Equatable {
        var sortField: Int
        var isAscending: Bool
    }

    /// `Libraries` equals the library id, combined with AND, sorted by sort name.
    /// Field numbers are `SeriesFilterField`, `FilterComparison`, `FilterCombination`, and `SeriesSortField`.
    static func forLibrary(_ libraryId: Int) -> LibrarySeriesQuery {
        LibrarySeriesQuery(
            statements: [Statement(comparison: 0, field: 19, value: String(libraryId))],
            combination: 1,
            limitTo: 0,
            sortOptions: SortOptions(sortField: 1, isAscending: true)
        )
    }
}

private struct ProgressBody: Encodable {
    var volumeId: Int
    var chapterId: Int
    var pageNum: Int
    var seriesId: Int
    var libraryId: Int
    var bookScrollId: String?
}

private struct ErrorEnvelope: Decodable {
    var message: String?
    var title: String?
}
