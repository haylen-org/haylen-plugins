#if !os(macOS)
import UIKit
import UniformTypeIdentifiers

// The dialogs of iOS, iPadOS, Mac Catalyst, visionOS and tvOS, presented over the topmost view controller of the app, so they show over UI that already shows. A message is an alert. On iOS, iPadOS, Mac Catalyst and visionOS the document picker copies opened files into the folder of the dialog, exports the data of a save from a file there and keeps the access to a picked folder for the session, and the photo picker copies the picked photos. The Apple TV has no document picker and no photo picker, so it shows alerts alone.
@MainActor
final class DialogsPresenter {
    private let context: HaylenPluginContext

    // The dialog that shows, and the dialogs that wait for it to close, in the order the app asked for them.
    private var current: UIViewController?
    private var queued: [(controller: UIViewController, answer: DialogsAnswer)] = []

    #if !os(tvOS)
    // The folders that pickers returned, whose security-scoped access lasts for the session.
    private var folders: [URL] = []

    // The photo pickers that show, whose delegates live until their dialogs answer.
    private var photoPickers: [ObjectIdentifier: DialogsPhotoPicker] = [:]
    #endif

    init(context: HaylenPluginContext) {
        self.context = context
    }

    // An alert answers only through its buttons, in the order of the request, so a message here never answers `nil` unless the app gives it up.
    func showMessage(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let alert = UIAlertController(title: request.title.isEmpty ? nil : request.title, message: request.text, preferredStyle: .alert)
        for (index, label) in request.buttons.enumerated() {
            alert.addAction(UIAlertAction(title: label, style: .default) { _ in answer.succeed(index + 1) })
        }
        try present(alert, answer: answer)
        return { self.close(alert) }
    }

    #if os(tvOS)
    func showOpenFiles(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        throw HaylenFailure("The Apple TV has no document picker, so apps on a TV open no files.", code: "unsupported")
    }

    func showSaveFile(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        throw HaylenFailure("The Apple TV has no document picker, so apps on a TV save no files where the person picks.", code: "unsupported")
    }

    func showOpenFolder(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        throw HaylenFailure("The Apple TV has no document picker, so apps on a TV open no folders.", code: "unsupported")
    }

    func showOpenPhotos(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        throw HaylenFailure("The Apple TV has no photo picker, so apps on a TV pick no photos.", code: "unsupported")
    }
    #else
    // The picker makes copies that belong to the app, which move into the folder of the dialog on a queue of their own, since files may be large.
    func showOpenFiles(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let types = request.extensions.compactMap { UTType(filenameExtension: $0) }
        let picker = DialogsDocumentPicker(forOpeningContentTypes: types.isEmpty ? [.item] : types, asCopy: true)
        picker.allowsMultipleSelection = request.multiple
        let folder = DialogsCopies.makeFolder()
        picker.picked = { urls in Self.move(urls, into: folder, answer: answer) }
        picker.dismissed = { answer.dismiss() }
        try present(picker, answer: answer)
        return { self.close(picker) }
    }

    // The picker exports a file with the data from the folder of the dialog, which is written first on a queue of its own, so a large file never holds the frames back. A dialog that the app gave up meanwhile shows no picker.
    func showSaveFile(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let folder = DialogsCopies.makeFolder()
        let file = folder.appendingPathComponent(request.name)
        let data = request.data
        let shown = DialogsShown()
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = Self.write(data, to: file)
            DispatchQueue.main.async {
                shown.picker = self.export(file, failure: failure, answer: answer)
            }
        }
        return {
            if let picker = shown.picker {
                self.close(picker)
            }
        }
    }

    // A folder outside the app is reachable only while its security-scoped access lasts, which the session keeps.
    func showOpenFolder(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let picker = DialogsDocumentPicker(forOpeningContentTypes: [.folder])
        picker.picked = { [weak self] urls in
            guard let folder = urls.first else {
                answer.dismiss()
                return
            }
            if folder.startAccessingSecurityScopedResource() {
                self?.folders.append(folder)
            }
            answer.succeed(folder.path)
        }
        picker.dismissed = { answer.dismiss() }
        try present(picker, answer: answer)
        return { self.close(picker) }
    }

    // The photo picker of the system runs outside the app and hands over only what the person picks, so it needs no permission.
    func showOpenPhotos(_ request: DialogsRequest, answer: DialogsAnswer) throws -> DialogsClose {
        let picker = DialogsPhotoPicker(multiple: request.multiple, folder: DialogsCopies.makeFolder(), answer: answer)
        let key = ObjectIdentifier(picker)
        photoPickers[key] = picker
        picker.finished = { [weak self] in self?.photoPickers[key] = nil }
        do {
            try present(picker.controller, answer: answer)
        } catch {
            photoPickers[key] = nil
            throw error
        }
        return { [weak self] in
            self?.close(picker.controller)
            self?.photoPickers[key] = nil
        }
    }

    private func export(_ file: URL, failure: String?, answer: DialogsAnswer) -> UIViewController? {
        guard answer.isPending else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        if let failure {
            try? FileManager.default.removeItem(at: file)
            answer.fail("The data to save could not be written to a file to export. " + failure, code: "failed")
            return nil
        }
        let picker = DialogsDocumentPicker(forExporting: [file], asCopy: true)
        picker.picked = { urls in
            try? FileManager.default.removeItem(at: file)
            guard let saved = urls.first else {
                answer.dismiss()
                return
            }
            answer.succeed(["name": saved.lastPathComponent, "path": saved.path])
        }
        picker.dismissed = {
            try? FileManager.default.removeItem(at: file)
            answer.dismiss()
        }
        do {
            try present(picker, answer: answer)
        } catch {
            try? FileManager.default.removeItem(at: file)
            answer.fail(error)
            return nil
        }
        return picker
    }

    private nonisolated static func write(_ data: Data, to file: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func move(_ urls: [URL], into folder: URL, answer: DialogsAnswer) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try DialogsCopies.move(urls, into: folder) }
            DispatchQueue.main.async {
                switch result {
                case .success(let files):
                    answer.succeed(files)
                case .failure(let error):
                    answer.fail("The picked files could not be copied for the app. " + error.localizedDescription, code: "failed")
                }
            }
        }
    }
    #endif

    // One dialog shows at a time, as the dialogs of macOS and Windows do, and the next one shows once it answered and closed. UIKit drops without an answer a presentation that starts while another one runs, such as a document picker that presents only once its remote view loaded, so a dialog also waits for the transition that runs. It presents from the topmost view controller of the app at that moment.
    private func present(_ controller: UIViewController, answer: DialogsAnswer) throws {
        guard context.viewController != nil else {
            throw HaylenFailure("The app has no window to show the dialog over.", code: "failed")
        }
        queued.append((controller, answer))
        showNext()
    }

    private func showNext() {
        if current != nil {
            return
        }
        while !queued.isEmpty {
            let next = queued.removeFirst()
            if !next.answer.isPending {
                continue
            }
            current = next.controller
            next.answer.settled = { [weak self] in self?.closed() }
            presentAfterTransition(next.controller, answer: next.answer)
            return
        }
    }

    private func closed() {
        current = nil
        showNext()
    }

    private func presentAfterTransition(_ controller: UIViewController, answer: DialogsAnswer) {
        guard answer.isPending else {
            closed()
            return
        }
        guard let presenter = context.viewController else {
            answer.fail("The app has no window to show the dialog over.", code: "failed")
            return
        }
        if let coordinator = presenter.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.presentAfterTransition(controller, answer: answer)
            }
            return
        }

        // The app may give the dialog up while UIKit presents it, and then it closes once it shows.
        presenter.present(controller, animated: true) {
            if !answer.isPending {
                self.close(controller)
            }
        }
    }

    // Closes the dialog that the app gave up. A dialog that still waits never shows, since its answer no longer waits.
    private func close(_ controller: UIViewController) {
        guard current === controller, controller.presentingViewController != nil else {
            return
        }
        controller.dismiss(animated: true) {
            self.closed()
        }
    }
}
#endif
