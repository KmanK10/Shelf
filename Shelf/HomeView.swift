import SwiftUI
import ShelfCore

struct HomeView: View {
    @Environment(ShelfModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if !model.onDeck.isEmpty {
                    Section("Continue Reading") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(model.onDeck) { series in
                                    Button {
                                        Task { await model.continueReading(series) }
                                    } label: {
                                        OnDeckCard(series: series)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } else if model.homeError == nil && !model.isLoadingHome {
                    Section("Continue Reading") {
                        Text("Series you have started will show up here.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Libraries") {
                    if model.libraries.isEmpty && !model.isLoadingHome {
                        Text(model.homeError == nil ? "No libraries yet." : "Libraries could not be loaded.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.libraries) { library in
                        NavigationLink {
                            SeriesListView(library: library)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(kind: .library(library.id), symbol: "books.vertical")
                                    .frame(width: 44, height: 64)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(library.displayName)
                                        .font(.body.weight(.semibold))
                                    Text(library.displayType)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let homeError = model.homeError {
                    Section {
                        Text(homeError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Shelf")
            .overlay {
                if model.isLoadingHome && model.libraries.isEmpty {
                    ProgressView()
                }
            }
            .refreshable {
                await model.refreshHome()
            }
        }
    }
}

private struct OnDeckCard: View {
    var series: Series

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(kind: .series(series.id))
                .frame(width: 112, height: 168)
                .overlay(alignment: .bottom) {
                    if let fraction = series.progressFraction {
                        ProgressView(value: fraction)
                            .padding(6)
                            .background(.ultraThinMaterial)
                    }
                }
            Text(series.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(series.displayName)
        .accessibilityHint("Continues reading")
    }
}
