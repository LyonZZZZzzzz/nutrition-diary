import Foundation

actor LocalPhotoStore {
    private let fileManager = FileManager.default

    func save(_ images: [Data]) throws -> [String] {
        let directory = try photoDirectory()
        var filenames: [String] = []
        for data in images {
            let filename = "meal-\(UUID().uuidString).img"
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            filenames.append(filename)
        }
        return filenames
    }

    func data(for filename: String) -> Data? {
        guard let directory = try? photoDirectory() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    func restore(_ photos: [String: Data], replaceExisting: Bool) throws {
        let directory = try photoDirectory()
        if replaceExisting {
            let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls { try? fileManager.removeItem(at: url) }
        }
        for (filename, data) in photos {
            guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\\") else { continue }
            try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func allData() -> [String: Data] {
        guard let directory = try? photoDirectory(),
              let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: Data] = [:]
        for url in urls where !url.hasDirectoryPath {
            if let data = try? Data(contentsOf: url) { result[url.lastPathComponent] = data }
        }
        return result
    }

    func deleteAll() {
        guard let directory = try? photoDirectory(), let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
    }

    func delete(_ filenames: [String]) {
        guard let directory = try? photoDirectory() else { return }
        for filename in filenames {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
        }
    }

    private func photoDirectory() throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("MealPhotos", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
