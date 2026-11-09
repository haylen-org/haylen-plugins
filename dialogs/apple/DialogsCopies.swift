import Foundation

// The copies of picked files that the app could not read where they are, in the folder `dialogs` of the temporary folder of the app, which the plugin empties when the process starts, so the folder never grows. Each dialog copies into a numbered folder of its own, and a second file of the same name goes into a numbered folder inside it.
enum DialogsCopies {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("dialogs", isDirectory: true)

    @MainActor private static var nextFolder = 1

    // A folder that cannot be emptied keeps its old copies, which the log names, and the new ones go next to them.
    static func clear() {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            NSLog("The copies of picked files in \"%@\" could not be removed: %@", root.path, error.localizedDescription)
        }
    }

    @MainActor
    static func makeFolder() -> URL {
        let folder = root.appendingPathComponent(String(nextFolder), isDirectory: true)
        nextFolder += 1
        return folder
    }

    // Returns where the file of `name` goes inside the folder of a dialog, once its folder exists.
    static func place(_ name: String, in folder: URL) throws -> URL {
        var target = folder.appendingPathComponent(name)
        var copy = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(String(copy), isDirectory: true).appendingPathComponent(name)
            copy += 1
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        return target
    }

    // Moves files that belong to the app, such as the copies of the document picker, into the folder of a dialog, and returns them as the app receives them.
    static func move(_ urls: [URL], into folder: URL) throws -> [[String: String]] {
        try urls.map { url in
            let target = try place(url.lastPathComponent, in: folder)
            try FileManager.default.moveItem(at: url, to: target)
            return ["name": target.lastPathComponent, "path": target.path]
        }
    }
}
