import Foundation

// What closes a dialog that shows, when the app gives it up.
typealias DialogsClose = @MainActor () -> Void

// Native part of the Dialogs plugin on Apple platforms. The runtime creates it by the class name that `plugin.json` gives, and loads it while the app launches. macOS shows every dialog as a sheet of the window of the app. iOS, iPadOS, Mac Catalyst and visionOS show an alert, the document picker and the photo picker over the topmost view controller. tvOS shows alerts alone.
@objc(DialogsPlugin)
final class DialogsPlugin: NSObject, HaylenPlugin {
    // A dialog shows from its handler and returns what closes it.
    typealias Show = @MainActor (DialogsRequest, DialogsAnswer) throws -> DialogsClose

    func load(with context: HaylenPluginContext) {
        DialogsCopies.clear()
        #if os(macOS)
        let dialogs = DialogsPanels(context: context)
        #else
        let dialogs = DialogsPresenter(context: context)
        #endif

        register(context, "message", show: dialogs.showMessage)
        register(context, "openFiles", show: dialogs.showOpenFiles)
        register(context, "saveFile", show: dialogs.showSaveFile)
        register(context, "openFolder", show: dialogs.showOpenFolder)
        register(context, "openPhotos", show: dialogs.showOpenPhotos)
    }

    // Handlers and their cancel blocks run on the main queue.
    private func register(_ context: HaylenPluginContext, _ method: String, show: @escaping Show) {
        context.registerCancellableHandler(method) { params, reply in
            MainActor.assumeIsolated { Self.open(params, reply: reply, show: show) }
        }
    }

    // A cancel or a timeout of the app gives the answer up before the dialog closes, so the dialog that closes answers nothing.
    @MainActor
    private static func open(_ params: Any, reply: @escaping HaylenReply, show: Show) -> HaylenCancel? {
        let answer = DialogsAnswer(reply)
        let close: DialogsClose
        do {
            close = try show(DialogsRequest(params), answer)
        } catch {
            answer.fail(error)
            return nil
        }

        return {
            MainActor.assumeIsolated {
                answer.giveUp()
                close()
            }
        }
    }
}
