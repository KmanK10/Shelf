import SwiftUI
import ShelfCore

struct SeriesDetailView: View {
    var series: Series

    @Environment(ShelfModel.self) private var model
    @State private var volumes: [Volume] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isOpeningContinue = false

    var body: some View {
        List {
            Section {
                Button {
                    openContinue()
                } label: {
                    Label("Continue", systemImage: "book")
                        .font(.body.weight(.semibold))
                }
                .disabled(isOpeningContinue)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            ForEach(volumes) { volume in
                Section(volume.displayTitle) {
                    let chapters = volume.chapters ?? []
                    if chapters.isEmpty {
                        Text("No chapters")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chapters) { chapter in
                        Button {
                            model.open(chapter: chapter, series: series)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.displayTitle)
                                        .foregroundStyle(.primary)
                                    if chapter.isSpecial == true {
                                        Text("Special")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if chapter.pageCount > 0 {
                                    Text("\(chapter.pagesRead ?? 0)/\(chapter.pageCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(series.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && volumes.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            volumes = try await model.volumes(seriesId: series.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openContinue() {
        isOpeningContinue = true
        Task {
            await model.continueReading(series)
            isOpeningContinue = false
        }
    }
}
