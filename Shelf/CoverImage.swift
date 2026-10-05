import SwiftUI
import UIKit

struct CoverImage: View {
    enum Kind {
        case series(Int)
        case library(Int)
    }

    var kind: Kind
    var symbol: String = "book.closed"

    @Environment(ShelfModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: taskID) {
            image = await load()
        }
    }

    private var taskID: String {
        switch kind {
        case .series(let id): return "series-\(id)"
        case .library(let id): return "library-\(id)"
        }
    }

    private func load() async -> UIImage? {
        switch kind {
        case .series(let id):
            return await model.coverImage(seriesId: id)
        case .library(let id):
            return await model.libraryImage(libraryId: id)
        }
    }
}
