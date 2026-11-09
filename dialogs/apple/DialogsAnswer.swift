import Foundation

// The answer of one dialog, which reaches the app once: the choice of the person, `nil` when the person dismissed the dialog, or a failure. A dialog that the app gave up answers nothing. It lives on the main thread, so work on other queues comes back there to answer.
@MainActor
final class DialogsAnswer {
    private var reply: HaylenReply?

    // Runs once when the answer settles, but not when the app gives the dialog up, so the presenter shows the next dialog.
    var settled: (() -> Void)?

    init(_ reply: @escaping HaylenReply) {
        self.reply = reply
    }

    var isPending: Bool {
        reply != nil
    }

    func succeed(_ value: Any) {
        take()?(true, value)
    }

    func dismiss() {
        take()?(true, NSNull())
    }

    func fail(_ message: String, code: String) {
        take()?(false, ["message": message, "code": code])
    }

    // A thrown `HaylenFailure` keeps its code, and any other error fails with the code `failed`.
    func fail(_ error: any Error) {
        if let failure = error as? HaylenFailure {
            fail(failure.message, code: failure.code ?? "failed")
            return
        }
        fail(error.localizedDescription, code: "failed")
    }

    func giveUp() {
        reply = nil
        settled = nil
    }

    private func take() -> HaylenReply? {
        let pending = reply
        reply = nil
        if pending != nil {
            let ended = settled
            settled = nil
            ended?()
        }
        return pending
    }
}
