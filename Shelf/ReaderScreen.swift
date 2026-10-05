import SwiftUI
import ShelfCore

struct ReaderScreen: View {
    @Environment(ShelfModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current: ReaderLaunch
    @State private var prepared: ReaderLaunch?
    @State private var startPage = 0
    @State private var scrollAnchor: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    init(launch: ReaderLaunch) {
        _current = State(initialValue: launch)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Opening")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else if let errorMessage {
                ContentUnavailableView("Can’t open this chapter", systemImage: "book.closed", description: Text(errorMessage))
                    .safeAreaInset(edge: .top) {
                        HStack {
                            Button("Close") { dismiss() }
                                .padding()
                            Spacer()
                        }
                    }
            } else if let prepared {
                reader(for: prepared)
                    .id(prepared.chapterId)
            }
        }
        .task { await load() }
        .alert(
            "Progress wasn’t saved",
            isPresented: Binding(
                get: { model.readerSyncError != nil },
                set: { if !$0 { model.readerSyncError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.readerSyncError ?? "")
        }
    }

    @ViewBuilder
    private func reader(for prepared: ReaderLaunch) -> some View {
        switch ReadingKind.kind(for: prepared.format) {
        case .images:
            ComicReaderView(launch: prepared, startPage: startPage) { next in
                Task { await advance(to: next) }
            }
        case .epub:
            EpubReaderView(launch: prepared, startPage: startPage, scrollAnchor: scrollAnchor) { next in
                Task { await advance(to: next) }
            }
        case .pdf:
            PdfReaderView(launch: prepared, startPage: startPage) { next in
                Task { await advance(to: next) }
            }
        }
    }

    private func advance(to next: ReaderLaunch) async {
        current = next
        prepared = nil
        isLoading = true
        errorMessage = nil
        await load()
    }

    private func load() async {
        do {
            let ready = try await model.prepare(current)
            let position = await model.resumePosition(for: ready)
            let count = max(ready.pageCount, 1)
            startPage = min(max(0, position.pageIndex), count - 1)
            scrollAnchor = position.bookScrollId
            prepared = ready
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ReaderToolbar: View {
    var title: String
    var subtitle: String
    var pageLabel: String
    var showsDirection: Bool
    var onClose: () -> Void
    var onPreviousChapter: (() -> Void)?
    var onNextChapter: (() -> Void)?

    @Environment(ShelfModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if showsDirection {
                    Button {
                        model.readingDirection = model.readingDirection == .leftToRight ? .rightToLeft : .leftToRight
                    } label: {
                        Image(systemName: model.readingDirection == .rightToLeft ? "arrow.left" : "arrow.right")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(model.readingDirection.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack {
                if let onPreviousChapter {
                    Button("Previous", action: onPreviousChapter)
                        .font(.subheadline)
                }
                Spacer()
                Text(pageLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let onNextChapter {
                    Button("Next", action: onNextChapter)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}
