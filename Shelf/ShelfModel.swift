import Foundation
import UIKit
import ShelfCore

enum ShelfDefaults {
    static let direction = "readingDirection"
    static let allowUntrusted = "allowUntrustedCertificates"
}

enum ReadingDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: return "Left to right"
        case .rightToLeft: return "Right to left"
        }
    }
}

struct ReaderLaunch: Identifiable, Equatable {
    var id = UUID()
    var chapterId: Int
    var seriesId: Int
    var volumeId: Int
    var libraryId: Int
    var title: String
    var seriesTitle: String
    var format: MangaFormat
    var koreaderHash: String?
    var pageCount: Int

    func replacing(chapter: Chapter, seriesTitle: String) -> ReaderLaunch {
        let format = chapter.resolvedFormat == .unknown ? self.format : chapter.resolvedFormat
        return ReaderLaunch(
            chapterId: chapter.id,
            seriesId: seriesId,
            volumeId: chapter.volumeId ?? volumeId,
            libraryId: libraryId,
            title: chapter.displayTitle,
            seriesTitle: seriesTitle,
            format: format,
            koreaderHash: chapter.koreaderHash,
            pageCount: chapter.pageCount
        )
    }
}

@MainActor
@Observable
final class ShelfModel {
    private(set) var session: StoredSession?
    var isRestoring = true
    var libraries: [Library] = []
    var onDeck: [Series] = []
    var homeError: String?
    var loginMessage: String?
    var isLoadingHome = false
    var activeReader: ReaderLaunch?
    var readerSyncError: String?
    var prefilledServer = ""
    var prefilledUsername = ""

    var readingDirection: ReadingDirection {
        didSet {
            UserDefaults.standard.set(readingDirection.rawValue, forKey: ShelfDefaults.direction)
        }
    }

    var allowUntrustedCertificates: Bool {
        didSet {
            UserDefaults.standard.set(allowUntrustedCertificates, forKey: ShelfDefaults.allowUntrusted)
            trustDelegate.allowUntrusted = allowUntrustedCertificates
        }
    }

    @ObservationIgnored private var client: KavitaClient?
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private var authRefresh: Task<Void, Error>?
    @ObservationIgnored private let trustDelegate = TrustDelegate()
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let images = NSCache<NSURL, UIImage>()

    init() {
        let storedDirection = UserDefaults.standard.string(forKey: ShelfDefaults.direction) ?? ""
        readingDirection = ReadingDirection(rawValue: storedDirection) ?? .leftToRight
        allowUntrustedCertificates = UserDefaults.standard.bool(forKey: ShelfDefaults.allowUntrusted)
        trustDelegate.allowUntrusted = allowUntrustedCertificates

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = true
        urlSession = URLSession(configuration: configuration, delegate: trustDelegate, delegateQueue: nil)

        do {
            session = try KeychainStore.load()
        } catch {
            KeychainStore.delete()
            session = nil
        }
        if let session {
            prefilledServer = session.serverURL
            prefilledUsername = session.username
            client = makeClient(for: session)
        }
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        defer { isRestoring = false }
        guard session != nil else { return }
        do {
            _ = try await withClient { try await $0.libraries() }
            await refreshHome()
        } catch KavitaError.unauthorized {
            let server = session?.serverURL ?? ""
            let username = session?.username ?? ""
            signOut()
            prefilledServer = server
            prefilledUsername = username
            loginMessage = "Sign in again to continue."
        } catch {
            homeError = error.localizedDescription
        }
    }

    func signIn(server: String, username: String, password: String) async throws {
        let address = try ServerAddress(userInput: server)
        let account = try await KavitaClient.login(
            address: address,
            username: username,
            password: password,
            session: urlSession
        )
        let deviceId = session?.deviceId ?? UUID().uuidString
        try await adopt(account: account, address: address, username: username, password: password, deviceId: deviceId)
        loginMessage = nil
        await refreshHome()
    }

    func signOut() {
        KeychainStore.delete()
        session = nil
        client = nil
        libraries = []
        onDeck = []
        activeReader = nil
        homeError = nil
        readerSyncError = nil
        prefilledServer = ""
        prefilledUsername = ""
        images.removeAllObjects()
    }

    func refreshHome() async {
        guard session != nil else { return }
        isLoadingHome = true
        defer { isLoadingHome = false }
        do {
            libraries = try await withClient { try await $0.libraries() }
            onDeck = try await withClient { try await $0.onDeck(libraryId: 0, page: 1, pageSize: 20) }.items
            homeError = nil
        } catch {
            homeError = error.localizedDescription
        }
    }

    func refreshTokensQuietly() async {
        guard session != nil else { return }
        try? await refreshSession()
    }

    func seriesPage(libraryId: Int, page: Int, pageSize: Int) async throws -> Page<Series> {
        try await withClient { try await $0.series(in: libraryId, page: page, pageSize: pageSize) }
    }

    func volumes(seriesId: Int) async throws -> [Volume] {
        try await withClient { try await $0.volumes(seriesId: seriesId) }
    }

    func search(query: String) async throws -> [SearchHit] {
        let group = try await withClient { try await $0.search(query: query) }
        return group.series ?? []
    }

    func continueReading(_ series: Series) async {
        do {
            let chapter = try await withClient { try await $0.continuePoint(seriesId: series.id) }
            open(chapter: chapter, series: series)
        } catch {
            homeError = error.localizedDescription
        }
    }

    func open(chapter: Chapter, series: Series) {
        let format = chapter.resolvedFormat == .unknown ? series.resolvedFormat : chapter.resolvedFormat
        activeReader = ReaderLaunch(
            chapterId: chapter.id,
            seriesId: series.id,
            volumeId: chapter.volumeId ?? 0,
            libraryId: series.resolvedLibraryId,
            title: chapter.displayTitle,
            seriesTitle: series.displayName,
            format: format,
            koreaderHash: chapter.koreaderHash,
            pageCount: chapter.pageCount
        )
        readerSyncError = nil
    }

    func open(hit: SearchHit) async throws {
        let series = try await withClient { try await $0.series(id: hit.seriesId) }
        let chapter = try await withClient { try await $0.continuePoint(seriesId: series.id) }
        open(chapter: chapter, series: series)
    }

    func prepare(_ launch: ReaderLaunch) async throws -> ReaderLaunch {
        var updated = launch
        if ReadingKind.kind(for: launch.format) == .epub {
            let info = try await withClient { try await $0.bookInfo(chapterId: launch.chapterId) }
            if let pages = info.pages, pages > 0 {
                updated.pageCount = pages
            }
            if updated.format == .unknown, let format = info.seriesFormat {
                updated.format = format
            }
            return updated
        }
        let info = try await withClient { try await $0.chapterInfo(chapterId: launch.chapterId) }
        if let pages = info.pages, pages > 0 {
            updated.pageCount = pages
        }
        if updated.format == .unknown, let format = info.seriesFormat {
            updated.format = format
        }
        return updated
    }

    func resumePosition(for launch: ReaderLaunch) async -> DecodedKoreaderPosition {
        do {
            if let hash = launch.koreaderHash,
               let book = try await withClient({ try await $0.koreaderProgress(hash: hash) }),
               let raw = book.progress,
               let decoded = KoreaderProgress.decode(raw) {
                return decoded
            }
            let progress = try await withClient { try await $0.progress(chapterId: launch.chapterId) }
            return DecodedKoreaderPosition(pageIndex: progress.pageNum ?? 0, bookScrollId: progress.bookScrollId)
        } catch {
            return DecodedKoreaderPosition(pageIndex: 0)
        }
    }

    func savePosition(for launch: ReaderLaunch, pageIndex: Int, pageCount: Int, bookScrollId: String?, keepScroll: Bool) async {
        let stored = KoreaderProgress.storedPageIndex(currentIndex: pageIndex, pageCount: pageCount)
        let scroll = keepScroll ? bookScrollId : nil
        do {
            try await withClient { client in
                if let hash = launch.koreaderHash {
                    let encoded = KoreaderProgress.encode(pageIndex: stored, format: launch.format, bookScrollId: scroll)
                    let payload = KoreaderProgress.payload(
                        documentHash: hash,
                        deviceId: self.session?.deviceId ?? "shelf",
                        progress: encoded,
                        pageIndex: stored,
                        pageCount: max(pageCount, 1)
                    )
                    try await client.saveKoreaderProgress(payload)
                } else {
                    try await client.saveProgress(
                        volumeId: launch.volumeId,
                        chapterId: launch.chapterId,
                        pageNum: stored,
                        seriesId: launch.seriesId,
                        libraryId: launch.libraryId,
                        bookScrollId: launch.format == .epub ? scroll : nil
                    )
                }
            }
            readerSyncError = nil
        } catch {
            readerSyncError = error.localizedDescription
        }
    }

    func adjacentLaunch(after launch: ReaderLaunch, forward: Bool) async throws -> ReaderLaunch? {
        let identifier = try await withClient { client in
            forward
                ? try await client.nextChapter(seriesId: launch.seriesId, volumeId: launch.volumeId, chapterId: launch.chapterId)
                : try await client.previousChapter(seriesId: launch.seriesId, volumeId: launch.volumeId, chapterId: launch.chapterId)
        }
        guard identifier > 0, identifier != launch.chapterId else { return nil }
        let chapter = try await withClient { try await $0.chapter(id: identifier) }
        return launch.replacing(chapter: chapter, seriesTitle: launch.seriesTitle)
    }

    func bookPage(chapterId: Int, page: Int) async throws -> String {
        try await withClient { try await $0.bookPage(chapterId: chapterId, page: page) }
    }

    func bookChapters(chapterId: Int) async throws -> [BookChapterItem] {
        try await withClient { try await $0.bookChapters(chapterId: chapterId) }
    }

    func pdfData(chapterId: Int) async throws -> Data {
        try await withClient { client in
            guard let url = client.pdfURL(chapterId: chapterId) else {
                throw KavitaError.invalidServerURL
            }
            return try await client.data(from: url)
        }
    }

    func pageImage(chapterId: Int, page: Int) async -> UIImage? {
        do {
            return try await withClient { client in
                guard let url = client.readerPageURL(chapterId: chapterId, page: page) else { return nil }
                if let cached = self.images.object(forKey: url as NSURL) {
                    return cached
                }
                let data = try await client.data(from: url)
                guard let image = UIImage(data: data) else { return nil }
                self.images.setObject(image, forKey: url as NSURL)
                return image
            }
        } catch {
            return nil
        }
    }

    func coverImage(seriesId: Int) async -> UIImage? {
        await remoteImage { $0.seriesCoverURL(seriesId: seriesId) }
    }

    func libraryImage(libraryId: Int) async -> UIImage? {
        await remoteImage { $0.libraryCoverURL(libraryId: libraryId) }
    }

    func epubScheme() -> String {
        guard let server = session?.serverURL, let address = try? ServerAddress(userInput: server) else {
            return "https"
        }
        return address.origin.scheme ?? "https"
    }

    private func remoteImage(_ url: (KavitaClient) -> URL?) async -> UIImage? {
        do {
            return try await withClient { client in
                guard let url = url(client) else { return nil }
                if let cached = self.images.object(forKey: url as NSURL) {
                    return cached
                }
                let data = try await client.data(from: url)
                guard let image = UIImage(data: data) else { return nil }
                self.images.setObject(image, forKey: url as NSURL)
                return image
            }
        } catch {
            return nil
        }
    }

    private func withClient<T>(_ work: (KavitaClient) async throws -> T) async throws -> T {
        guard let client else {
            throw KavitaError.unauthorized("Sign in to Kavita.")
        }
        do {
            return try await work(client)
        } catch KavitaError.unauthorized {
            try await refreshSession()
            return try await work(client)
        }
    }

    private func refreshSession() async throws {
        if let authRefresh {
            try await authRefresh.value
            return
        }
        let task = Task { @MainActor in
            try await self.refreshOrLogin()
        }
        authRefresh = task
        defer { authRefresh = nil }
        try await task.value
    }

    private func refreshOrLogin() async throws {
        guard let session else {
            throw KavitaError.unauthorized("Sign in to Kavita.")
        }
        let address = try ServerAddress(userInput: session.serverURL)
        if let pair = try? await KavitaClient.refresh(
            address: address,
            token: session.token,
            refreshToken: session.refreshToken,
            session: urlSession
        ), let token = pair.token, let refresh = pair.refreshToken, !token.isEmpty, !refresh.isEmpty {
            var updated = session
            updated.token = token
            updated.refreshToken = refresh
            try KeychainStore.save(updated)
            self.session = updated
            await client?.setToken(token)
            return
        }
        let account = try await KavitaClient.login(
            address: address,
            username: session.username,
            password: session.password,
            session: urlSession
        )
        try await adopt(
            account: account,
            address: address,
            username: session.username,
            password: session.password,
            deviceId: session.deviceId
        )
    }

    private func adopt(
        account: UserAccount,
        address: ServerAddress,
        username: String,
        password: String,
        deviceId: String
    ) async throws {
        guard let token = account.token, !token.isEmpty,
              let refresh = account.refreshToken, !refresh.isEmpty else {
            throw KavitaError.unauthorized("Kavita did not return a session token.")
        }
        var apiKey = APIKeySelection.preferred(apiKey: account.apiKey, authKeys: account.authKeys ?? []) ?? ""
        let provisional = KavitaClient(address: address, token: token, apiKey: apiKey, session: urlSession)
        if apiKey.isEmpty {
            let created = try await provisional.createAuthKey(name: "shelf", length: 32)
            apiKey = created.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await provisional.setAPIKey(apiKey)
        }
        guard !apiKey.isEmpty else {
            throw KavitaError.unauthorized("Kavita did not return an API key.")
        }
        let stored = StoredSession(
            serverURL: address.display,
            username: account.username ?? username,
            password: password,
            token: token,
            refreshToken: refresh,
            apiKey: apiKey,
            deviceId: deviceId,
            kavitaVersion: account.kavitaVersion
        )
        try KeychainStore.save(stored)
        session = stored
        client = provisional
        prefilledServer = stored.serverURL
        prefilledUsername = stored.username
    }

    private func makeClient(for session: StoredSession) -> KavitaClient? {
        guard let address = try? ServerAddress(userInput: session.serverURL) else { return nil }
        return KavitaClient(address: address, token: session.token, apiKey: session.apiKey, session: urlSession)
    }
}

final class TrustDelegate: NSObject, URLSessionDelegate {
    var allowUntrusted = false

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if allowUntrusted,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
