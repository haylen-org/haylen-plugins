#if os(macOS)
import AppKit
import UniformTypeIdentifiers

// The dialogs of macOS, each a sheet of the window of the app: an alert, and the panels of files to open, of a place to save, of a folder and of images. Picked files are files of the Mac, which the app reads where they are, and the file of a save is written on a queue of its own, so a large file never holds the frames back.
@MainActor
final class DialogsPanels {
    private let context: HaylenPluginContext

    // Whether a sheet shows, and the sheets that wait for it to end, in the order the app asked for them.
    private var showing = false
    private var queued: [(begin: () -> Void, answer: DialogsAnswer)] = []

    init(context: HaylenPluginContext) {
        self.context = context
    }

    // The first button answers Return, and a button named Cancel answers Escape, as in every alert of the Mac.
    func showMessage(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let window = try getWindow()
        let alert = NSAlert()
        alert.alertStyle = Self.style(of: request.kind)
        alert.messageText = request.title.isEmpty ? request.text : request.title
        alert.informativeText = request.title.isEmpty ? "" : request.text
        for label in request.buttons {
            alert.addButton(withTitle: label)
        }

        let count = request.buttons.count
        show(answer) {
            alert.beginSheetModal(for: window) { response in
                self.ended()
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                if index >= 0 && index < count {
                    answer.succeed(index + 1)
                } else {
                    answer.dismiss()
                }
            }
        }
        return {
            if alert.window.sheetParent != nil {
                window.endSheet(alert.window, returnCode: .cancel)
            }
        }
    }

    func showOpenFiles(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let window = try getWindow()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = request.multiple
        panel.message = request.title
        let types = Self.contentTypes(of: request.extensions)
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        return open(panel, over: window, answer: answer)
    }

    func showSaveFile(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let window = try getWindow()
        let panel = NSSavePanel()
        panel.message = request.title
        panel.nameFieldStringValue = request.name
        panel.canCreateDirectories = true
        let types = Self.contentTypes(of: request.extensions)
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }

        let data = request.data
        show(answer) {
            panel.beginSheetModal(for: window) { response in
                self.ended()
                guard response == .OK, let url = panel.url else {
                    answer.dismiss()
                    return
                }
                Self.write(data, to: url, answer: answer)
            }
        }
        return { Self.close(panel) }
    }

    func showOpenFolder(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let window = try getWindow()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = request.title
        show(answer) {
            panel.beginSheetModal(for: window) { response in
                self.ended()
                guard response == .OK, let url = panel.url else {
                    answer.dismiss()
                    return
                }
                answer.succeed(url.path)
            }
        }
        return { Self.close(panel) }
    }

    // The Mac keeps photos as image files, so the panel of images opens in the Pictures folder.
    func showOpenPhotos(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let window = try getWindow()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = request.multiple
        panel.message = request.title
        panel.allowedContentTypes = [.image]
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        return open(panel, over: window, answer: answer)
    }

    private func open(_ panel: NSOpenPanel, over window: NSWindow, answer: DialogsAnswer) -> DialogsClose {
        show(answer) {
            panel.beginSheetModal(for: window) { response in
                self.ended()
                guard response == .OK else {
                    answer.dismiss()
                    return
                }
                answer.succeed(panel.urls.map { ["name": $0.lastPathComponent, "path": $0.path] })
            }
        }
        return { Self.close(panel) }
    }

    // One sheet shows at a time, and the next one begins once it ended, since AppKit drops a panel that begins while another sheet shows. A sheet that the app gives up while it waits never begins.
    private func show(_ answer: DialogsAnswer, begin: @escaping () -> Void) {
        queued.append((begin, answer))
        showNext()
    }

    private func showNext() {
        if showing {
            return
        }
        while !queued.isEmpty {
            let next = queued.removeFirst()
            if !next.answer.isPending {
                continue
            }
            showing = true
            next.begin()
            return
        }
    }

    // The completion of a sheet runs while AppKit still ends it, so the next sheet begins on a later turn of the main queue.
    private func ended() {
        showing = false
        DispatchQueue.main.async {
            self.showNext()
        }
    }

    // Ends the sheet of a panel that shows, whose completion then runs. A panel that waits has nothing to end.
    private static func close(_ panel: NSSavePanel) {
        if panel.sheetParent != nil {
            panel.cancel(nil)
        }
    }

    private func getWindow() throws -> NSWindow {
        guard let window = context.window else {
            throw HaylenFailure("The app has no window to show the dialog on.", code: "failed")
        }
        return window
    }

    private static func style(of kind: DialogsRequest.Kind) -> NSAlert.Style {
        switch kind {
        case .info:
            return .informational
        case .warning:
            return .warning
        case .error:
            return .critical
        }
    }

    private static func contentTypes(of extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }

    private static func write(_ data: Data, to url: URL, answer: DialogsAnswer) {
        DispatchQueue.global(qos: .userInitiated).async {
            let failure: String?
            do {
                try data.write(to: url, options: .atomic)
                failure = nil
            } catch {
                failure = "The file could not be written. " + error.localizedDescription
            }
            DispatchQueue.main.async {
                if let failure {
                    answer.fail(failure, code: "failed")
                } else {
                    answer.succeed(["name": url.lastPathComponent, "path": url.path])
                }
            }
        }
    }
}
#endif
