import SwiftUI
import PDFKit

struct PdfReaderView: View {
    var launch: ReaderLaunch
    var startPage: Int
    var onAdvance: (ReaderLaunch) -> Void

    @Environment(ShelfModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var currentPage: Int
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var didChangePage = false
    @State private var saveTask: Task<Void, Never>?

    init(launch: ReaderLaunch, startPage: Int, onAdvance: @escaping (ReaderLaunch) -> Void) {
        self.launch = launch
        self.startPage = startPage
        self.onAdvance = onAdvance
        _currentPage = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(
                title: launch.title,
                subtitle: launch.seriesTitle,
                pageLabel: pageLabel,
                showsDirection: true,
                onClose: { close() },
                onPreviousChapter: { Task { await moveChapter(forward: false) } },
                onNextChapter: { Task { await moveChapter(forward: true) } }
            )
            ZStack {
                if isLoading {
                    ProgressView("Loading PDF")
                } else if let errorMessage {
                    ContentUnavailableView("PDF unavailable", systemImage: "doc", description: Text(errorMessage))
                } else if let document {
                    PDFKitView(
                        document: document,
                        startPage: startPage,
                        rightToLeft: model.readingDirection == .rightToLeft
                    ) { page in
                        guard page != currentPage else { return }
                        currentPage = page
                        didChangePage = true
                        scheduleSave()
                    }
                    .id(model.readingDirection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .task { await load() }
        .onDisappear {
            saveTask?.cancel()
            Task { await save() }
        }
    }

    private var pageLabel: String {
        let count = document?.pageCount ?? launch.pageCount
        return "\(currentPage + 1) / \(max(count, 1))"
    }

    private func load() async {
        do {
            let data = try await model.pdfData(chapterId: launch.chapterId)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                errorMessage = "Kavita did not return a readable PDF."
                isLoading = false
                return
            }
            self.document = document
            if startPage >= document.pageCount {
                currentPage = document.pageCount - 1
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        guard didChangePage, let document else { return }
        await model.savePosition(
            for: launch,
            pageIndex: currentPage,
            pageCount: document.pageCount,
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
}

struct PDFKitView: UIViewRepresentable {
    var document: PDFDocument
    var startPage: Int
    var rightToLeft: Bool
    var onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange, startPage: startPage)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = .black
        view.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
        let index = min(max(0, startPage), max(document.pageCount - 1, 0))
        if let page = document.page(at: index) {
            view.go(to: page)
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
        view.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
    }

    final class Coordinator: NSObject {
        var onPageChange: (Int) -> Void
        var startPage: Int
        var ignoreFirst = true

        init(onPageChange: @escaping (Int) -> Void, startPage: Int) {
            self.onPageChange = onPageChange
            self.startPage = startPage
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document
            else { return }
            let index = document.index(for: page)
            if ignoreFirst {
                ignoreFirst = false
                if index == startPage { return }
            }
            onPageChange(index)
        }
    }
}
