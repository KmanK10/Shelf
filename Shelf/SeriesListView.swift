import SwiftUI
import ShelfCore

struct SeriesListView: View {
    var library: Library

    @Environment(ShelfModel.self) private var model
    @State private var series: [Series] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let pageSize = 40
    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if let errorMessage, series.isEmpty {
                ContentUnavailableView("Couldn’t load series", systemImage: "books.vertical", description: Text(errorMessage))
            } else if series.isEmpty && !isLoading {
                ContentUnavailableView("No series", systemImage: "books.vertical", description: Text("This library is empty."))
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(series) { item in
                        NavigationLink {
                            SeriesDetailView(series: item)
                        } label: {
                            SeriesCard(series: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                if page < totalPages {
                    Button("Load more") { Task { await load(reset: false) } }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                        .padding(.bottom)
                }
            }
        }
        .navigationTitle(library.displayName)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading && series.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await load(reset: true) }
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let nextPage = reset ? 1 : page + 1
        do {
            let result = try await model.seriesPage(libraryId: library.id, page: nextPage, pageSize: pageSize)
            if reset {
                series = result.items
            } else {
                let existing = Set(series.map(\.id))
                series.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            }
            page = result.pagination?.currentPage ?? nextPage
            totalPages = result.pagination?.totalPages ?? nextPage
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SeriesCard: View {
    var series: Series

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(kind: .series(series.id))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
            Text(series.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}
