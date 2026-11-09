import Foundation

#if os(macOS)
import AppKit
#else
import LinkPresentation
import UIKit
#endif

// Native part of the Share plugin on iOS, iPadOS, Mac Catalyst, visionOS and macOS. The share sheet of UIKit, or the sharing service picker of AppKit on macOS, covers the app while it shows. The files of a share arrive as bytes, which the plugin writes into a folder of its own in the temporary folder, emptied before every share, since the app the person picks may read them after the sheet closes.
@objc(SharePlugin)
final class SharePlugin: NSObject, HaylenPlugin {
    // The parameters of a share, which hold bytes, so they come as a dictionary instead of a decodable value.
    struct Request {
        let text: String?
        let url: URL?
        let title: String?
        let files: [URL]
        let anchor: CGRect?
    }

    private var context: HaylenPluginContext!
    private var pending: HaylenReply?

    #if os(macOS)
    private var picker: SharePicker?
    #endif

    func load(with context: HaylenPluginContext) {
        self.context = context
        context.registerHandler("share") { [unowned self] params, reply in
            guard self.pending == nil else {
                reply(false, ["message": "The share sheet already shows.", "code": "busy"])
                return
            }
            guard let fields = params as? [String: Any] else {
                reply(false, ["message": "The parameters of the share are invalid.", "code": "invalidParams"])
                return
            }
            do {
                let request = try Self.request(from: fields)
                try self.present(request, reply: reply)
            } catch let failure as HaylenFailure {
                reply(false, ["message": failure.message, "code": failure.code ?? "failed"])
            } catch {
                reply(false, ["message": "The files of the share could not be written: \(error.localizedDescription)", "code": "failed"])
            }
        }
    }

    private static func request(from params: [String: Any]) throws -> Request {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)

        var files: [URL] = []
        for file in params["files"] as? [[String: Any]] ?? [] {
            guard let name = file["name"] as? String, let bytes = file["bytes"] as? Data else {
                throw HaylenFailure("A file of the share has no name or no bytes.", code: "invalidParams")
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)
            try bytes.write(to: destination)
            files.append(destination)
        }

        var url: URL?
        if let address = params["url"] as? String {
            guard let parsed = URL(string: address) else {
                throw HaylenFailure("The url \"\(address)\" of the share is not valid.", code: "invalidUrl")
            }
            url = parsed
        }

        var anchor: CGRect?
        if let rect = params["anchor"] as? [String: Double] {
            anchor = CGRect(x: rect["x"] ?? 0, y: rect["y"] ?? 0, width: rect["width"] ?? 0, height: rect["height"] ?? 0)
        }
        return Request(text: params["text"] as? String, url: url, title: params["title"] as? String, files: files, anchor: anchor)
    }

    private func finish(shared: Bool, target: String?) {
        context.uncoverApp()
        var result: [String: Any] = ["shared": shared]
        result["target"] = target
        pending?(true, result)
        pending = nil
    }

    #if os(macOS)
    // The picker of AppKit tells which service the person picked, or that they closed it, so `shared` tells whether they picked one, as on Android.
    private func present(_ request: Request, reply: @escaping HaylenReply) throws {
        guard let view = context.window?.contentView else {
            throw HaylenFailure("The app has no window yet.", code: "noWindow")
        }
        var items: [Any] = request.files
        if let text = request.text {
            items.insert(text, at: 0)
        }
        if let url = request.url {
            items.append(url)
        }

        let bounds = view.bounds
        let fraction = request.anchor ?? CGRect(x: 0.5, y: 0.5, width: 0, height: 0)
        let rect = CGRect(x: bounds.minX + fraction.minX * bounds.width, y: bounds.maxY - fraction.maxY * bounds.height, width: fraction.width * bounds.width, height: fraction.height * bounds.height)
        let picker = SharePicker(items: items, subject: request.title) { [unowned self] service in
            self.picker = nil
            self.finish(shared: service != nil, target: service?.title)
        }
        pending = reply
        self.picker = picker
        context.coverApp()
        picker.show(relativeTo: rect, of: view)
    }
    #else
    // The sheet tells whether the activity that the person picked completed, and a sheet that the person closed completes nothing. On iPad and on the Mac the sheet is a popover over the anchor, or over the middle of the window without an arrow.
    private func present(_ request: Request, reply: @escaping HaylenReply) throws {
        guard let presenter = context.viewController else {
            throw HaylenFailure("The app has no window yet.", code: "noWindow")
        }
        var items: [Any] = request.files
        if let text = request.text {
            items.insert(ShareItem(text, title: request.title), at: 0)
        }
        if let url = request.url {
            items.append(ShareItem(url, title: request.title))
        }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            let bounds = presenter.view.bounds
            popover.sourceView = presenter.view
            if let fraction = request.anchor {
                popover.sourceRect = CGRect(x: fraction.minX * bounds.width, y: fraction.minY * bounds.height, width: fraction.width * bounds.width, height: fraction.height * bounds.height)
            } else {
                popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        sheet.completionWithItemsHandler = { [unowned self] activity, completed, _, _ in
            self.finish(shared: completed, target: completed ? activity?.rawValue : nil)
        }
        pending = reply
        context.coverApp()
        presenter.present(sheet, animated: true)
    }
    #endif
}

#if os(macOS)
// The sharing service picker of AppKit with the subject of the share, which tells the service that the person picked, or nil once they close it.
final class SharePicker: NSObject, NSSharingServicePickerDelegate {
    private let picker: NSSharingServicePicker
    private let subject: String?
    private let chosen: (NSSharingService?) -> Void

    init(items: [Any], subject: String?, chosen: @escaping (NSSharingService?) -> Void) {
        picker = NSSharingServicePicker(items: items)
        self.subject = subject
        self.chosen = chosen
        super.init()
        picker.delegate = self
    }

    func show(relativeTo rect: CGRect, of view: NSView) {
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if let service, let subject {
            service.subject = subject
        }
        chosen(service)
    }
}
#else
// An item of the share sheet with the title of the share, which mail and messages take as their subject and the sheet shows at its top.
final class ShareItem: NSObject, UIActivityItemSource {
    private let value: Any
    private let title: String?

    init(_ value: Any, title: String?) {
        self.value = value
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        value
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        value
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title ?? ""
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        guard let title else {
            return nil
        }
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = value as? URL
        return metadata
    }
}
#endif
