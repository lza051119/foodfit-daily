import Foundation

struct MealPhotoDraft: Identifiable, Equatable {
    var id = UUID()
    let data: Data?
}

enum PhotoEdit {
    case keep, remove, replace(Data)

    init(original: Data?, current: Data?) {
        if original == current {
            self = .keep
        } else if let current {
            self = .replace(current)
        } else {
            self = .remove
        }
    }
}

struct JournalDisk {
    let directory: URL

    private var index: URL { directory.appendingPathComponent("journal.json") }
    private var photos: URL { directory.appendingPathComponent("photos", isDirectory: true) }

    func load() throws -> Journal {
        do {
            let data = try Data(contentsOf: index)
            return try JSONDecoder().decode(Journal.self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return Journal()
        }
    }

    func save(_ journal: Journal) throws {
        let encoded = try JSONEncoder().encode(journal)
        try prepareDirectory()
        try encoded.write(to: index, options: writeOptions)
    }

    func save(_ journal: Journal, replacing previous: Journal) throws {
        try save(journal)
        for id in previous.photosInUse.subtracting(journal.photosInUse) {
            removePhoto(id)
        }
    }

    func saveMeal(_ meal: Meal, photos: [MealPhotoDraft], in journal: Journal) throws -> Journal {
        let existing = Set(journal.meals.first { $0.id == meal.id }?.photoIDs ?? [])
        var newFiles: [UUID] = []
        do {
            var updated = meal
            let ids = try photos.map { photo in
                if existing.contains(photo.id) { return photo.id }
                guard let data = photo.data else { throw JournalIssue.writeFailed }
                let id = try savePhoto(data)
                newFiles.append(id)
                return id
            }
            updated.photoID = ids.first
            updated.referencePhotoIDs = ids.count > 1 ? Array(ids.dropFirst()) : nil
            var next = journal
            try next.save(updated)
            try save(next, replacing: journal)
            return next
        } catch {
            newFiles.forEach { removePhoto($0) }
            throw error
        }
    }

    func photo(_ id: UUID?) -> Data? {
        guard let id else { return nil }
        return try? Data(contentsOf: photoURL(id))
    }

    func savePhoto(_ data: Data) throws -> UUID {
        try prepareDirectory()
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let id = UUID()
        try data.write(to: photoURL(id), options: writeOptions)
        return id
    }

    func removePhoto(_ id: UUID?) {
        guard let id else { return }
        try? FileManager.default.removeItem(at: photoURL(id))
    }

    func removeUnreferencedPhotos(keeping ids: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: photos,
                                                                       includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "jpg" {
            if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !ids.contains(id) {
                removePhoto(id)
            }
        }
    }

    private func photoURL(_ id: UUID) -> URL {
        photos.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var target = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        #endif
    }

    private var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
}
