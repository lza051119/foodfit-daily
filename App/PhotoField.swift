import PhotosUI
import SwiftUI
import UIKit

struct PhotoField: View {
    @Binding var photo: Data?
    @Binding var isLoading: Bool
    let title: String
    let maxPixels: Int
    @State private var picked: PhotosPickerItem?
    @State private var issue: String?

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }

        PhotosPicker(selection: $picked, matching: .images) {
            Label(photo == nil ? title : "更换图片", systemImage: "photo.on.rectangle")
        }
        .task(id: picked) { await load(picked) }

        if photo != nil {
            Button("移除图片", role: .destructive) {
                picked = nil
                photo = nil
                issue = nil
            }
        }

        if isLoading { ProgressView("读取图片中…") }
        if let issue { InlineProblem(message: issue) }

    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else {
            isLoading = false
            return
        }
        isLoading = true
        issue = nil
        defer { if picked == item { isLoading = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageIssue.unreadable }
            let size = maxPixels
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImageTools.prepare(data, maxPixels: size)
            }.value
            guard !Task.isCancelled, picked == item else { return }
            photo = prepared
        } catch {
            if !Task.isCancelled, picked == item { issue = ImageIssue.unreadable.localizedDescription }
        }
    }
}
