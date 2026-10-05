import SwiftUI
import WebKit
import ShelfCore

struct EpubReaderView: View {
    var launch: ReaderLaunch
    var startPage: Int
    var scrollAnchor: String?
    var onAdvance: (ReaderLaunch) -> Void

    @Environment(ShelfModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int
    @State private var html = ""
    @State private var chapters: [BookChapterItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showsTOC = false
    @State private var saveTask: Task<Void, Never>?
    @State private var didChangePage = false

    init(launch: ReaderLaunch, startPage: Int, scrollAnchor: String?, onAdvance: @escaping (ReaderLaunch) -> Void) {
        self.launch = launch
        self.startPage = startPage
        self.scrollAnchor = scrollAnchor
        self.onAdvance = onAdvance
        _currentPage = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(
                title: launch.title,
                subtitle: launch.seriesTitle,
                pageLabel: "\(currentPage + 1) / \(max(launch.pageCount, 1))",
                showsDirection: false,
                onClose: { close() },
                onPreviousChapter: { Task { await moveChapter(forward: false) } },
                onNextChapter: { Task { await moveChapter(forward: true) } }
            )
            ZStack {
                if isLoading {
                    ProgressView("Loading page")
                } else if let errorMessage {
                    ContentUnavailableView("Page unavailable", systemImage: "book", description: Text(errorMessage))
                } else {
                    EpubWebView(html: html, scrollAnchor: currentPage == startPage ? scrollAnchor : nil) { page in
                        guard page != currentPage, page >= 0, page < max(launch.pageCount, 1) else { return }
                        currentPage = page
                        didChangePage = true
                        Task { await loadPage() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button {
                    turn(by: -1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(currentPage <= 0)
                Spacer()
                Button("Contents") { showsTOC = true }
                    .disabled(chapters.isEmpty)
                Spacer()
                Button {
                    turn(by: 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(currentPage >= max(launch.pageCount, 1) - 1)
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .padding()
            .background(.bar)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showsTOC) {
            NavigationStack {
                List(flattenedChapters, id: \.id) { item in
                    Button(item.title) {
                        showsTOC = false
                        guard item.page != currentPage else { return }
                        currentPage = item.page
                        didChangePage = true
                        Task { await loadPage() }
                    }
                }
                .navigationTitle("Contents")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsTOC = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            await loadChapters()
            await loadPage()
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await save() }
        }
    }

    private var flattenedChapters: [TOCEntry] {
        flatten(chapters)
    }

    private func turn(by delta: Int) {
        let next = currentPage + delta
        guard next >= 0, next < max(launch.pageCount, 1) else { return }
        currentPage = next
        didChangePage = true
        Task { await loadPage() }
    }

    private func loadPage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fragment = try await model.bookPage(chapterId: launch.chapterId, page: currentPage)
            html = EpubHTML.document(from: fragment, scheme: model.epubScheme())
            errorMessage = nil
            scheduleSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadChapters() async {
        chapters = (try? await model.bookChapters(chapterId: launch.chapterId)) ?? []
    }

    private func scheduleSave() {
        guard didChangePage else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        guard didChangePage else { return }
        await model.savePosition(
            for: launch,
            pageIndex: currentPage,
            pageCount: launch.pageCount,
            bookScrollId: nil,
            keepScroll: false
        )
    }

    private func close() {
        saveTask?.cancel()
        Task {
            await save()
            dismiss()
        }
    }

    private func moveChapter(forward: Bool) async {
        await save()
        do {
            guard let next = try await model.adjacentLaunch(after: launch, forward: forward) else { return }
            onAdvance(next)
        } catch {
            model.readerSyncError = error.localizedDescription
        }
    }

    private func flatten(_ items: [BookChapterItem], depth: Int = 0) -> [TOCEntry] {
        items.flatMap { item -> [TOCEntry] in
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (title?.isEmpty == false ? title! : "Section")
            let prefix = String(repeating: "  ", count: depth)
            var entries = [TOCEntry(id: "\(depth)-\(item.page ?? 0)-\(label)", title: prefix + label, page: item.page ?? 0)]
            entries.append(contentsOf: flatten(item.children ?? [], depth: depth + 1))
            return entries
        }
    }
}

private struct TOCEntry: Identifiable {
    var id: String
    var title: String
    var page: Int
}

struct EpubWebView: UIViewRepresentable {
    var html: String
    var scrollAnchor: String?
    var onJump: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onJump: onJump)
    }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "shelf")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.anchor = scrollAnchor
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "shelf")
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onJump = onJump
        context.coordinator.anchor = scrollAnchor
        guard context.coordinator.rendered != html else { return }
        context.coordinator.rendered = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onJump: (Int) -> Void
        var rendered = ""
        var anchor: String?

        init(onJump: @escaping (Int) -> Void) {
            self.onJump = onJump
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let page: Int?
            if let number = message.body as? Int {
                page = number
            } else if let text = message.body as? String {
                page = Int(text)
            } else {
                page = nil
            }
            if let page {
                onJump(page)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let anchor, !anchor.isEmpty else { return }
            let escaped = anchor
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("shelfScrollTo('\(escaped)')", completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
