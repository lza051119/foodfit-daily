import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct MealPhotoField: View {
    @Binding var photos: [MealPhotoDraft]
    @Binding var isLoading: Bool
    @State private var picked: [PhotosPickerItem] = []
    @State private var issue: String?

    var body: some View {
        if let main = photos.first {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("主图").font(.subheadline.weight(.semibold))
                    Spacer()
                    actions(for: main, title: "主图")
                }
                if let data = main.data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("餐食主图")
                } else {
                    Text("照片无法加载").font(.footnote).foregroundStyle(FitTheme.muted)
                }
            }
        }

        ForEach(photos.dropFirst()) { photo in
            HStack(spacing: 12) {
                ZStack {
                    if let data = photo.data, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        FitTheme.soft
                        Image(systemName: "photo").foregroundStyle(FitTheme.muted)
                    }
                }
                .frame(width: 76, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
                Text("辅助图").font(.subheadline).foregroundStyle(FitTheme.muted)
                Spacer()
                actions(for: photo, title: "辅助图")
            }
        }

        let hasPhotos = !photos.isEmpty
        PhotosPicker(selection: $picked, maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images) {
            Label(hasPhotos ? "继续添加照片" : "从相册添加照片", systemImage: "photo.on.rectangle.angled")
        }
        .disabled(isLoading)
        .task(id: picked) { await load(picked) }

        if isLoading { ProgressView("读取照片中…") }
        if let issue { InlineProblem(message: issue) }
    }

    private func actions(for photo: MealPhotoDraft, title: String) -> some View {
        Menu {
            if photos.first?.id != photo.id {
                Button {
                    photos.removeAll { $0.id == photo.id }
                    photos.insert(photo, at: 0)
                } label: { Label("设为主图", systemImage: "star") }
            }
            Button(role: .destructive) {
                photos.removeAll { $0.id == photo.id }
            } label: { Label("移除照片", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
                .accessibilityLabel("\(title)操作")
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoading = true
        issue = nil
        defer {
            if picked == items {
                isLoading = false
                picked = []
            }
        }

        var loaded: [MealPhotoDraft] = []
        var seen = Set(photos.compactMap(\.data))
        var failed = 0
        for item in items {
            guard !Task.isCancelled else { return }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageIssue.unreadable }
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ImageTools.prepare(data, maxPixels: 2048)
                }.value
                if seen.insert(prepared).inserted { loaded.append(MealPhotoDraft(data: prepared)) }
            } catch {
                failed += 1
            }
        }
        guard !Task.isCancelled, picked == items else { return }
        photos.append(contentsOf: loaded)
        if failed > 0 { issue = "有 \(failed) 张照片读取失败，可以重新选择。" }
    }
}

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
