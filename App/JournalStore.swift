import Foundation
import Observation

@MainActor @Observable
final class JournalStore {
    private let disk: JournalDisk
    private(set) var journal = Journal()
    private(set) var hasLoadError = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        disk = JournalDisk(directory: support.appendingPathComponent("FoodFitJournal", isDirectory: true))
        reload()
    }

    func reload() {
        do {
            journal = try disk.load()
            hasLoadError = false
            disk.removeUnreferencedPhotos(keeping: journal.photosInUse)
        } catch {
            hasLoadError = true
        }
    }

    func photo(_ id: UUID?) -> Data? { disk.photo(id) }

    func saveMeal(_ meal: Meal, photos: [MealPhotoDraft]) throws {
        guard !hasLoadError else { throw JournalIssue.loadFailed }
        do {
            journal = try disk.saveMeal(meal, photos: photos, in: journal)
        } catch {
            throw (error as? JournalIssue) ?? .writeFailed
        }
    }

    func deleteMeal(_ meal: Meal) throws {
        try updatePhoto(oldID: nil, edit: .keep) { journal, _ in
            journal.meals.removeAll { $0.id == meal.id }
        }
    }

    func saveEnergy(_ entry: EnergyEntry, photo: PhotoEdit) throws {
        try updatePhoto(oldID: entry.photoID, edit: photo) { journal, photoID in
            var entry = entry
            entry.photoID = photoID
            try journal.save(entry)
        }
    }

    func deleteEnergy(_ entry: EnergyEntry) throws {
        try updatePhoto(oldID: entry.photoID, edit: .remove) { journal, _ in
            journal.energyEntries.removeAll { $0.day == entry.day }
        }
    }

    func saveSession(_ session: StrengthSession) throws {
        try updatePhoto(oldID: nil, edit: .keep) { journal, _ in try journal.save(session) }
    }

    func deleteSession(_ session: StrengthSession) throws {
        try updatePhoto(oldID: nil, edit: .keep) { journal, _ in
            journal.sessions.removeAll { $0.id == session.id }
        }
    }

    func saveMeasurements(heightCM: Double?, kg: Double?, day: LogDay) throws {
        try updatePhoto(oldID: nil, edit: .keep) { journal, _ in
            try journal.saveMeasurements(heightCM: heightCM, kg: kg, on: day)
        }
    }

    func saveRecap(_ recap: DailyRecap) throws {
        try updatePhoto(oldID: nil, edit: .keep) { journal, _ in try journal.save(recap) }
    }

    private func updatePhoto(oldID: UUID?, edit: PhotoEdit,
                             mutate: (inout Journal, UUID?) throws -> Void) throws {
        guard !hasLoadError else { throw JournalIssue.loadFailed }
        var newFile: UUID?
        do {
            let targetID: UUID?
            switch edit {
            case .keep: targetID = oldID
            case .remove: targetID = nil
            case .replace(let data):
                newFile = try disk.savePhoto(data)
                targetID = newFile
            }

            var next = journal
            try mutate(&next, targetID)
            try disk.save(next, replacing: journal)
            journal = next
        } catch {
            disk.removePhoto(newFile)
            throw (error as? JournalIssue) ?? .writeFailed
        }
    }
}
