import Photos
import SwiftUI
import UIKit

@MainActor
struct DailySummarySheet: View {
    private enum Sheet: String, Identifiable {
        case recap, share
        var id: String { rawValue }
    }

    private struct ReportState: Equatable {
        let weight: Double?
        let recap: String?
        let meals: [Meal]
    }

    private struct ReportPhoto: Identifiable {
        let id: UUID
        let title: String
        let image: CGImage
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    let day: LogDay
    let balance: DayBalance
    let meals: [Meal]
    let sessions: [StrengthSession]
    let workouts: [AppleWorkout]
    let health: HealthBridge?
    @State private var graphic: UIImage?
    @State private var png: Data?
    @State private var failed = false
    @State private var sheet: Sheet?
    @State private var saving = false
    @State private var saveMessage: String?
    @State private var saveIssue: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let graphic {
                    Image(uiImage: graphic)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("\(day.heading)体重、摄入、消耗和运动总结")
                } else if failed {
                    InlineProblem(message: "长图暂时无法生成。")
                    Button("重新生成", action: renderImage).buttonStyle(FitActionStyle())
                } else {
                    ProgressView("正在生成长图…")
                }
            }
            .contentMargins(14)
            .safeAreaInset(edge: .bottom, spacing: 0) { exportBar }
            .background(FitTheme.canvas)
            .navigationTitle("每日总结")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { sheet = .recap } label: {
                        Label("AI 建议", systemImage: "sparkles")
                    }.disabled(saving || store.hasLoadError)
                }
            }
            .task(id: ReportState(weight: weight, recap: recap, meals: meals)) { renderImage() }
            .sheet(item: $sheet) { item in
                switch item {
                case .recap: AIRecapSheet(day: day, health: health, saved: store.journal.recap(on: day))
                case .share:
                    if let graphic { SummaryShareSheet(image: graphic) }
                }
            }
        }
    }

    private var lifts: [Lift] { sessions.flatMap(\.lifts).filter { !$0.sets.isEmpty } }
    private var weight: Double? { store.journal.weight(on: day) }
    private var recap: String? { store.journal.recap(on: day)?.text }

    private var exportBar: some View {
        VStack(spacing: 8) {
            if let saveIssue { InlineProblem(message: saveIssue) }
            if let saveMessage, saveIssue == nil {
                Text(saveMessage)
                    .font(.footnote).foregroundStyle(FitTheme.accent)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { exportButtons }
                VStack(spacing: 8) { exportButtons }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(FitTheme.paper)
    }

    @ViewBuilder
    private var exportButtons: some View {
        Button { Task { await saveToPhotos() } } label: {
            Label(saving ? "正在保存…" : "保存到照片", systemImage: "photo")
        }
        .buttonStyle(FitActionStyle(prominent: true))
        .disabled(png == nil || saving)

        Button { sheet = .share } label: {
            Label("分享长图", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(FitActionStyle())
        .disabled(graphic == nil || saving)
    }

    private func renderImage() {
        failed = false
        graphic = nil
        png = nil
        saveMessage = nil
        saveIssue = nil
        let renderer = ImageRenderer(content: report
            .frame(width: 420)
            .fixedSize(horizontal: true, vertical: true)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else {
            failed = true
            return
        }
        graphic = image
        png = data
    }

    private func saveToPhotos() async {
        guard let png, !saving else { return }
        saving = true
        saveIssue = nil
        saveMessage = nil
        defer { saving = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            saveIssue = "请在 iPhone 设置里允许「食动日记」添加照片，也可以直接分享长图。"
            return
        }
        let filename = "食动日记-\(day.isoDate).png"
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: options)
            }
            saveMessage = "长图已保存到照片。"
        } catch {
            saveIssue = "长图暂时无法保存，请重试。"
        }
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("食动日记", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(FitTheme.accent)
                Text("每日总结").font(.largeTitle.bold())
                Text("\(String(day.year))年\(day.heading)").font(.subheadline).foregroundStyle(FitTheme.muted)
            }
            energyPanel
            if let energy = balance.energy {
                let details = [energy.source.title, energy.active.map { "活动 \($0.formatted()) 大卡" },
                               energy.resting.map { "静息 \($0.formatted()) 大卡" }].compactMap { $0 }
                Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(FitTheme.muted)
            }

            LabeledContent("当天体重", value: weight.map { WeightRecord.label(for: $0) } ?? "未记录")
                .font(.subheadline.weight(.medium))
                .fitPanel(padding: 12)

            Text("饮食摄入").font(.title3.bold())
            VStack(alignment: .leading, spacing: 10) {
                if meals.isEmpty { Text("还没有饮食记录").foregroundStyle(FitTheme.muted) }
                ForEach(meals) { meal in
                    LabeledContent(meal.name == meal.kind.title ? meal.name : "\(meal.kind.title) · \(meal.name)",
                                   value: "\(meal.kcal.formatted()) 大卡")
                }
            }
            .font(.subheadline)
            .fitPanel()

            Text("运动与力量").font(.title3.bold())
            VStack(alignment: .leading, spacing: 11) {
                if workouts.isEmpty && lifts.isEmpty { Text("还没有运动记录").foregroundStyle(FitTheme.muted) }
                ForEach(workouts) { workout in
                    let detail = ["Apple 健康", "\(workout.minutes) 分钟",
                                  workout.activeKcal.map { "活动 \($0.formatted()) 大卡" }].compactMap { $0 }
                    reportRow(workout.title, detail: detail.joined(separator: " · "))
                }
                ForEach(lifts) { lift in
                    let detail = lift.sets.map { set in
                        let weight = set.kg.map { "\($0.formatted()) kg" } ?? "自重"
                        return "\(set.groupCount) 组 × \(set.reps) 次 · \(weight)"
                    }.joined(separator: " / ")
                    reportRow(lift.name, detail: detail)
                }
            }
            .font(.subheadline)
            .fitPanel()

            if let recap {
                Text("日总结与建议").font(.title3.bold())
                Text(recap)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .fitPanel()
            }

            photoAppendix

            Text("按所选日期的已记录饮食与总消耗估算。")
                .font(.caption).foregroundStyle(FitTheme.muted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.canvas)
        .foregroundStyle(FitTheme.ink)
    }

    @ViewBuilder
    private var photoAppendix: some View {
        let photos = meals.compactMap { meal -> ReportPhoto? in
            guard let data = store.photo(meal.photoID),
                  let image = try? ImageTools.thumbnail(of: data, maxPixels: 820) else { return nil }
            let title = meal.name == meal.kind.title ? meal.name : "\(meal.kind.title) · \(meal.name)"
            return ReportPhoto(id: meal.id, title: title, image: image)
        }
        if !photos.isEmpty {
            Text("餐食照片").font(.title3.bold())
            ForEach(photos) { photo in
                VStack(alignment: .leading, spacing: 8) {
                    Text(photo.title).font(.subheadline.weight(.medium))
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 410)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var energyPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            metric("摄入", balance.intake)
            metric("总消耗", balance.energy?.total)
            metric((balance.deficit ?? 0) < 0 ? "估算盈余" : "估算缺口", balance.deficit.map { abs($0) })
        }
        .padding(17)
        .frame(maxWidth: .infinity)
        .background(FitTheme.hero, in: RoundedRectangle(cornerRadius: 19))
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(FitTheme.heroMuted)
            Text(value?.formatted() ?? "—")
                .font(FitTheme.number(23, relativeTo: .headline))
                .foregroundStyle(.white)
            if value != nil { Text("大卡").font(.caption2).foregroundStyle(FitTheme.heroMuted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(FitTheme.muted)
        }
    }
}

private struct SummaryShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
