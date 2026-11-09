#if os(iOS) || os(visionOS)
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// The photo picker of the system with its delegate, which copies each picked photo into the folder of its dialog, in the order the person picked them. The picker runs outside the app and hands over only the photos that the person picks, so it needs no permission. Its Cancel button and the swipe that dismisses it answer the dialog with `nil`.
@MainActor
final class DialogsPhotoPicker: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    let controller: PHPickerViewController
    private let folder: URL
    private let answer: DialogsAnswer

    // Runs once the dialog answered or closed, so the presenter lets the picker go.
    var finished: (() -> Void)?

    init(multiple: Bool, folder: URL, answer: DialogsAnswer) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = multiple ? 0 : 1
        configuration.preferredAssetRepresentationMode = .current
        controller = PHPickerViewController(configuration: configuration)
        self.folder = folder
        self.answer = answer
        super.init()
        controller.delegate = self
        controller.presentationController?.delegate = self
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            answer.dismiss()
            finish()
            return
        }
        copy(results)
    }

    // The person swiped the picker away, which UIKit reports here alone.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        answer.dismiss()
        finish()
    }

    // The provider removes its file once the completion returns, so each photo is copied inside it, on the queue of the provider.
    private func copy(_ results: [PHPickerResult]) {
        let group = DispatchGroup()
        let copies = DialogsPhotoCopies(count: results.count)
        for (index, result) in results.enumerated() {
            group.enter()
            let provider = result.itemProvider
            let suggested = provider.suggestedName
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [folder] url, error in
                copies.store(index, Self.copy(url, error: error, named: suggested, into: folder))
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.report(copies)
        }
    }

    private func report(_ copies: DialogsPhotoCopies) {
        if let failure = copies.failure {
            answer.fail("The picked photos could not be copied for the app. " + failure, code: "failed")
        } else {
            answer.succeed(copies.files)
        }
        finish()
    }

    private func finish() {
        let done = finished
        finished = nil
        done?()
    }

    private nonisolated static func copy(_ url: URL?, error: (any Error)?, named suggested: String?, into folder: URL) -> Result<[String: String], any Error> {
        guard let url else {
            return .failure(error ?? CocoaError(.fileReadUnknown))
        }
        let base = suggested.map { ($0 as NSString).deletingPathExtension } ?? url.deletingPathExtension().lastPathComponent
        let name = url.pathExtension.isEmpty ? base : base + "." + url.pathExtension
        return Result {
            let target = try DialogsCopies.place(name, in: folder)
            try FileManager.default.copyItem(at: url, to: target)
            return ["name": target.lastPathComponent, "path": target.path]
        }
    }
}
#endif
