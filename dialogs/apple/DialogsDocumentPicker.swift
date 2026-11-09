#if os(iOS) || os(visionOS)
import UIKit

// The document picker of UIKit as its own delegate, since a picker keeps its delegate weakly. The picked documents, the Cancel button and the swipe that dismisses the picker each reach the dialog once.
final class DialogsDocumentPicker: UIDocumentPickerViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    var picked: (([URL]) -> Void)?
    var dismissed: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        presentationController?.delegate = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let answer = picked
        finish()
        answer?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let answer = dismissed
        finish()
        answer?()
    }

    // The person swiped the picker away, which UIKit reports here alone.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let answer = dismissed
        finish()
        answer?()
    }

    private func finish() {
        picked = nil
        dismissed = nil
    }
}
#endif
