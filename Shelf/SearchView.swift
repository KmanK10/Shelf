import SwiftUI
import ShelfCore

struct SearchView: View {
    @Environment(ShelfModel.self) private var model
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search Kavita", systemImage: "magnifyingglass", description: Text("Find a series by name."))
                } else if let errorMessage, hits.isEmpty {
                    ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(errorMessage))
                } else if hits.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(hits) { hit in
                        Button {
                            Task {
                                do {
                                    try await model.open(hit: hit)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(kind: .series(hit.seriesId))
                                    .frame(width: 44, height: 66)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.displayName)
                                        .foregroundStyle(.primary)
                                    if let library = hit.libraryName, !library.isEmpty {
                                        Text(library)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .overlay {
                        if isSearching && hits.isEmpty {
                            ProgressView()
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let errorMessage, !hits.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.bar)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Series")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task { await search(newValue) }
            }
        }
    }

    private func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            errorMessage = nil
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.search(query: trimmed)
            guard !Task.isCancelled else { return }
            hits = found
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
