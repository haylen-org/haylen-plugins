#if os(iOS) || os(visionOS)
import UIKit

// The picker that a save shows once its file is written, which a cancel of the app closes.
@MainActor
final class DialogsShown {
    var picker: UIViewController?
}
#endif
