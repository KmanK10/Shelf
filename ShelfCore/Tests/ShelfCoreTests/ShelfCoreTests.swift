import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShelfCore

final class ServerAddressTests: XCTestCase {
    func testNormalizesCommonInputs() throws {
        let plain = try ServerAddress(userInput: "https://kavita.example")
        XCTAssertEqual(plain.display, "https://kavita.example")
        XCTAssertEqual(plain.apiRoot.absoluteString, "https://kavita.example/api")

        let trailing = try ServerAddress(userInput: "https://kavita.example/")
        XCTAssertEqual(trailing.apiRoot.absoluteString, "https://kavita.example/api")

        let withAPI = try ServerAddress(userInput: "https://kavita.example/api/")
        XCTAssertEqual(withAPI.apiRoot.absoluteString, "https://kavita.example/api")

        let subpath = try ServerAddress(userInput: "https://example.com/kavita")
        XCTAssertEqual(subpath.apiRoot.absoluteString, "https://example.com/kavita/api")

        let lan = try ServerAddress(userInput: "http://192.168.1.20:5000")
        XCTAssertEqual(lan.apiRoot.absoluteString, "http://192.168.1.20:5000/api")

        let endpoint = plain.endpoint("Library/libraries")
        XCTAssertEqual(endpoint?.absoluteString, "https://kavita.example/api/Library/libraries")
    }

    func testRejectsEmptyAndSchemelessGarbage() {
        XCTAssertThrowsError(try ServerAddress(userInput: "   "))
        XCTAssertThrowsError(try ServerAddress(userInput: "http://"))
    }
}

final class DecodingTests: XCTestCase {
    func testLoginUserDecodesTokensAndAuthKeys() throws {
        let json = """
        {
          "id": 7,
          "username": "kiefer",
          "token": "jwt-value",
          "refreshToken": "refresh-value",
          "apiKey": "opdskeyvalue",
          "kavitaVersion": "0.9.1.10",
          "preferences": { "theme": { "name": "ignored" } },
          "authKeys": [
            { "id": 1, "key": "opdskeyvalue", "name": "opds", "provider": 1 },
            { "id": 2, "key": "imagekey1", "name": "image-only", "provider": 1 }
          ]
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(UserAccount.self, from: json)
        XCTAssertEqual(user.username, "kiefer")
        XCTAssertEqual(user.token, "jwt-value")
        XCTAssertEqual(user.refreshToken, "refresh-value")
        XCTAssertEqual(user.apiKey, "opdskeyvalue")
        XCTAssertEqual(user.authKeys?.count, 2)
        XCTAssertEqual(APIKeySelection.preferred(apiKey: user.apiKey, authKeys: user.authKeys ?? []), "opdskeyvalue")
    }

    func testPrefersOpdsKeyWhenTopLevelKeyMissing() {
        let keys = [
            AuthKey(id: 2, key: "imagekey1", name: "image-only"),
            AuthKey(id: 3, key: "shelfkey01", name: "shelf")
        ]
        XCTAssertEqual(APIKeySelection.preferred(apiKey: nil, authKeys: keys), "shelfkey01")
        XCTAssertEqual(APIKeySelection.preferred(apiKey: "  ", authKeys: [AuthKey(id: 1, key: "onlyimage", name: "image-only")]), "onlyimage")
    }

    func testSeriesVolumeChapterAndSearch() throws {
        let seriesJSON = """
        {
          "id": 4,
          "name": "Original",
          "localizedName": "Localized",
          "pages": 120,
          "pagesRead": 30,
          "format": 3,
          "libraryId": 2,
          "libraryName": "Books",
          "lastChapterAdded": "2024-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        let series = try JSONDecoder().decode(Series.self, from: seriesJSON)
        XCTAssertEqual(series.displayName, "Localized")
        XCTAssertEqual(series.resolvedFormat, .epub)
        XCTAssertEqual(series.progressFraction, 0.25)

        let volumeJSON = """
        [{
          "id": 9,
          "number": 1,
          "name": "Volume 1",
          "pages": 40,
          "pagesRead": 10,
          "chapters": [{
            "id": 15,
            "number": "1",
            "titleName": "Opening",
            "pages": 20,
            "pagesRead": 4,
            "volumeId": 9,
            "isSpecial": false,
            "files": [{
              "id": 3,
              "pages": 20,
              "format": 1,
              "koreaderHash": "ABC123",
              "bytes": 10
            }]
          }]
        }]
        """.data(using: .utf8)!
        let volumes = try JSONDecoder().decode([Volume].self, from: volumeJSON)
        XCTAssertEqual(volumes.first?.chapters?.first?.displayTitle, "Opening")
        XCTAssertEqual(volumes.first?.chapters?.first?.koreaderHash, "ABC123")
        XCTAssertEqual(volumes.first?.chapters?.first?.resolvedFormat, .archive)

        let searchJSON = """
        {
          "libraries": [{ "id": 2, "name": "Books", "type": 2 }],
          "series": [{ "seriesId": 4, "name": "Original", "localizedName": "Localized", "format": 4, "libraryId": 2 }],
          "persons": [],
          "files": []
        }
        """.data(using: .utf8)!
        let search = try JSONDecoder().decode(SearchResultGroup.self, from: searchJSON)
        XCTAssertEqual(search.series?.first?.displayName, "Localized")
        XCTAssertEqual(search.series?.first?.format, .pdf)
        XCTAssertEqual(search.libraries?.first?.displayType, "Books")
    }

    func testUnknownFormatDoesNotFailDecode() throws {
        let json = """
        { "id": 1, "name": "Future", "format": 99, "libraryId": 1 }
        """.data(using: .utf8)!
        let series = try JSONDecoder().decode(Series.self, from: json)
        XCTAssertEqual(series.resolvedFormat, .unknown)
    }

    func testChapterInfoBookInfoAndProgress() throws {
        let info = try JSONDecoder().decode(ChapterInfo.self, from: """
        { "pages": 12, "seriesFormat": 4, "seriesId": 1, "libraryId": 2, "volumeId": 3, "seriesName": "Demo", "isSpecial": false }
        """.data(using: .utf8)!)
        XCTAssertEqual(info.seriesFormat, .pdf)
        XCTAssertEqual(info.pages, 12)

        let book = try JSONDecoder().decode(BookInfo.self, from: """
        { "bookTitle": "Demo", "pages": 8, "seriesFormat": 3, "seriesId": 1, "volumeId": 3, "libraryId": 2 }
        """.data(using: .utf8)!)
        XCTAssertEqual(book.pages, 8)

        let progress = try JSONDecoder().decode(ReadingProgress.self, from: """
        { "volumeId": 3, "chapterId": 9, "pageNum": 4, "seriesId": 1, "libraryId": 2, "bookScrollId": "//body/p[2]" }
        """.data(using: .utf8)!)
        XCTAssertEqual(progress.pageNum, 4)
        XCTAssertEqual(progress.bookScrollId, "//body/p[2]")

        let koreader = try JSONDecoder().decode(KoreaderBook.self, from: """
        { "document": "HASH", "device_id": "dev", "device": "KOReader", "percentage": 0.5, "progress": "3", "timestamp": 1700000000 }
        """.data(using: .utf8)!)
        XCTAssertEqual(koreader.deviceId, "dev")
        XCTAssertEqual(koreader.progress, "3")
        XCTAssertEqual(koreader.timestamp, 1_700_000_000)
    }

    func testPaginationHeader() throws {
        let header = """
        {"currentPage":2,"itemsPerPage":40,"totalItems":80,"totalPages":2}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(Pagination.self, from: header)
        XCTAssertEqual(page.currentPage, 2)
        XCTAssertEqual(page.totalPages, 2)
    }

    func testLibrarySeriesFilterMatchesKavitaFieldNumbers() throws {
        let query = LibrarySeriesQuery.forLibrary(6)
        let data = try JSONEncoder().encode(query)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let statements = object?["statements"] as? [[String: Any]]
        XCTAssertEqual(statements?.first?["comparison"] as? Int, 0)
        XCTAssertEqual(statements?.first?["field"] as? Int, 19)
        XCTAssertEqual(statements?.first?["value"] as? String, "6")
        XCTAssertEqual(object?["combination"] as? Int, 1)
        let sort = object?["sortOptions"] as? [String: Any]
        XCTAssertEqual(sort?["sortField"] as? Int, 1)
        XCTAssertEqual(sort?["isAscending"] as? Bool, true)
    }
}

final class KoreaderProgressTests: XCTestCase {
    func testArchiveAndPDFPageNumbersAreOneBased() {
        XCTAssertEqual(KoreaderProgress.encode(pageIndex: 0, format: .archive, bookScrollId: nil), "1")
        XCTAssertEqual(KoreaderProgress.encode(pageIndex: 4, format: .pdf, bookScrollId: nil), "5")
        XCTAssertEqual(KoreaderProgress.decode("5"), DecodedKoreaderPosition(pageIndex: 4))
        XCTAssertEqual(KoreaderProgress.decode("1"), DecodedKoreaderPosition(pageIndex: 0))
    }

    func testEpubFragmentRoundTrip() {
        XCTAssertEqual(
            KoreaderProgress.encode(pageIndex: 0, format: .epub, bookScrollId: nil),
            "/body/DocFragment[1].0"
        )
        XCTAssertEqual(
            KoreaderProgress.encode(pageIndex: 3, format: .epub, bookScrollId: "//body/div/p[2]"),
            "/body/DocFragment[4]/body/div/p[2].0"
        )
        XCTAssertEqual(
            KoreaderProgress.decode("/body/DocFragment[10].0"),
            DecodedKoreaderPosition(pageIndex: 9)
        )
        XCTAssertEqual(
            KoreaderProgress.decode("/body/DocFragment[4]/body/div/p[2].0"),
            DecodedKoreaderPosition(pageIndex: 3, bookScrollId: "//body/div/p[2]")
        )
    }

    func testEpubHashAnchorsAndTextOffsets() {
        XCTAssertEqual(KoreaderProgress.decode("#_doc_fragment_26")?.pageIndex, 25)
        XCTAssertEqual(KoreaderProgress.decode("#_doc_fragment26")?.pageIndex, 25)
        XCTAssertEqual(KoreaderProgress.decode("#_doc_fragment_10_ some_anchor")?.pageIndex, 9)
        XCTAssertEqual(
            KoreaderProgress.decode("/body/DocFragment[2]/body/p[3]/text().0"),
            DecodedKoreaderPosition(pageIndex: 1, bookScrollId: "//body/p[3]")
        )
        XCTAssertEqual(
            KoreaderProgress.encode(pageIndex: 2, format: .epub, bookScrollId: "//body/id('foo')"),
            "/body/DocFragment[3].0"
        )
    }

    func testLastPageIsStoredOnePastTheEnd() {
        XCTAssertEqual(KoreaderProgress.storedPageIndex(currentIndex: 0, pageCount: 10), 0)
        XCTAssertEqual(KoreaderProgress.storedPageIndex(currentIndex: 8, pageCount: 10), 8)
        XCTAssertEqual(KoreaderProgress.storedPageIndex(currentIndex: 9, pageCount: 10), 10)
    }

    func testPayloadUsesKoreaderFieldNames() throws {
        let payload = KoreaderProgress.payload(
            documentHash: "HASH",
            deviceId: "device",
            progress: "2",
            pageIndex: 1,
            pageCount: 4,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["document"] as? String, "HASH")
        XCTAssertEqual(object?["device_id"] as? String, "device")
        XCTAssertEqual(object?["device"] as? String, "Shelf")
        XCTAssertEqual(object?["progress"] as? String, "2")
        XCTAssertEqual(object?["percentage"] as? Double, 0.25)
        XCTAssertEqual(object?["timestamp"] as? Int, 1_700_000_000)
    }
}

final class EpubHTMLTests: XCTestCase {
    func testRewritesProtocolRelativeResourceURLs() {
        let raw = "<img src=\"//kavita.example/api/Book/1/book-resources?apiKey=abc&file=i.jpg\">"
        let html = EpubHTML.document(from: raw, scheme: "https")
        XCTAssertTrue(html.contains("src=\"https://kavita.example/api/Book/1/book-resources?apiKey=abc&file=i.jpg\""))
        XCTAssertTrue(html.contains("class=\"book-content\""))
        XCTAssertTrue(html.contains("kavita-page"))
    }
}

final class KavitaClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testLoginPostsUsernameAndDecodesUser() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/Account/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: String]
            XCTAssertEqual(body?["username"], "kiefer")
            XCTAssertEqual(body?["password"], "secret")
            let json = """
            {"id":1,"username":"kiefer","token":"jwt","refreshToken":"ref","apiKey":"opdskey"}
            """.data(using: .utf8)!
            return (Self.response(url: request.url!, status: 200), json)
        }

        let address = try ServerAddress(userInput: "https://kavita.example")
        let user = try await KavitaClient.login(address: address, username: "kiefer", password: "secret", session: Self.session())
        XCTAssertEqual(user.token, "jwt")
        XCTAssertEqual(user.refreshToken, "ref")
    }

    func testLibrariesSendBearerTokenAndDecodePagination() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
            if request.url?.path.hasSuffix("/Library/libraries") == true {
                let json = """
                [{"id":2,"name":"Manga","type":0}]
                """.data(using: .utf8)!
                return (Self.response(url: request.url!, status: 200), json)
            }
            let response = Self.response(
                url: request.url!,
                status: 200,
                headers: ["Content-Type": "application/json", "Pagination": "{\"currentPage\":1,\"itemsPerPage\":40,\"totalItems\":1,\"totalPages\":1}"]
            )
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            let statements = body?["statements"] as? [[String: Any]]
            XCTAssertEqual(statements?.first?["value"] as? String, "2")
            let json = """
            [{"id":8,"name":"Series","format":1,"libraryId":2,"pages":10,"pagesRead":2}]
            """.data(using: .utf8)!
            return (response, json)
        }

        let address = try ServerAddress(userInput: "https://kavita.example")
        let client = KavitaClient(address: address, token: "jwt", apiKey: "opdskey", session: Self.session())
        let libraries = try await client.libraries()
        XCTAssertEqual(libraries.first?.displayName, "Manga")
        let page = try await client.series(in: 2, page: 1, pageSize: 40)
        XCTAssertEqual(page.items.first?.id, 8)
        XCTAssertEqual(page.pagination?.totalItems, 1)
    }

    func testMissingKoreaderProgressIsNil() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/Koreader/opdskey/syncs/progress/HASH") == true)
            return (Self.response(url: request.url!, status: 400), Data("No progress".utf8))
        }
        let address = try ServerAddress(userInput: "https://kavita.example")
        let client = KavitaClient(address: address, token: "jwt", apiKey: "opdskey", session: Self.session())
        let progress = try await client.koreaderProgress(hash: "HASH")
        XCTAssertNil(progress)
    }

    func testSaveKoreaderProgressPutsDocumentHash() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/Koreader/opdskey/syncs/progress")
            let body = try JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            XCTAssertEqual(body?["document"] as? String, "HASH")
            XCTAssertEqual(body?["progress"] as? String, "/body/DocFragment[2].0")
            return (Self.response(url: request.url!, status: 200), Data("{}".utf8))
        }
        let address = try ServerAddress(userInput: "https://kavita.example")
        let client = KavitaClient(address: address, token: "jwt", apiKey: "opdskey", session: Self.session())
        let payload = KoreaderProgress.payload(documentHash: "HASH", deviceId: "device", progress: "/body/DocFragment[2].0", pageIndex: 1, pageCount: 5)
        try await client.saveKoreaderProgress(payload)
    }

    func testUnauthorizedLoginSurfacesServerMessage() async throws {
        MockURLProtocol.handler = { request in
            (Self.response(url: request.url!, status: 401), Data("Your credentials are not correct".utf8))
        }
        let address = try ServerAddress(userInput: "https://kavita.example")
        do {
            _ = try await KavitaClient.login(address: address, username: "kiefer", password: "nope", session: Self.session())
            XCTFail("Expected an error")
        } catch let error as KavitaError {
            XCTAssertEqual(error, .unauthorized("Your credentials are not correct"))
        }
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(url: URL, status: Int, headers: [String: String] = ["Content-Type": "application/json"]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
