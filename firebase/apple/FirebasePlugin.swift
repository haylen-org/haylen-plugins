import FirebaseCore
import Foundation

// Native part of the Firebase plugin on Apple platforms. It configures the default Firebase app while the app launches, before any Lua runs and before the other Firebase plugins load, from the GoogleService-Info.plist that the parameter `servicesPlist` names and that the build copies into the app bundle.
@objc(FirebasePlugin)
final class FirebasePlugin: NSObject, HaylenPlugin {
    struct App: Encodable {
        let name: String
        let projectId: String?
        let appId: String
        let senderId: String
        let dataCollection: Bool
    }

    struct DataCollection: Codable {
        let enabled: Bool
    }

    // The parameters of a call that takes none, which decode from any JSON, `null` included.
    struct Nothing: Decodable {
        init(from decoder: Decoder) {}
    }

    func load(with context: HaylenPluginContext) {
        configure(context)

        context.register("app") { (_: Nothing) async throws -> App in
            let app = try Self.defaultApp()
            let options = app.options
            return App(name: app.name, projectId: options.projectID, appId: options.googleAppID, senderId: options.gcmSenderID, dataCollection: app.isDataCollectionDefaultEnabled)
        }

        context.register("setDataCollection") { (params: DataCollection) async throws -> DataCollection in
            try Self.defaultApp().isDataCollectionDefaultEnabled = params.enabled
            return params
        }
    }

    // The build copies the file under its own name, so the plugin looks it up by that name. An app whose file is no valid configuration runs without Firebase, and every call of the Firebase plugins fails with the code `notConfigured`.
    private func configure(_ context: HaylenPluginContext) {
        guard FirebaseApp.app() == nil else {
            return
        }

        let parameter = context.config["servicesPlist"] as? String ?? ""
        let file = (parameter as NSString).lastPathComponent as NSString
        let path = Bundle.main.path(forResource: file.deletingPathExtension, ofType: file.pathExtension)
        guard let path, let options = FirebaseOptions(contentsOfFile: path) else {
            NSLog("The plugin \"firebase\" found no valid \"%@\" in the app bundle, so Firebase stays off. Give the parameter \"servicesPlist\" the GoogleService-Info.plist of the iOS app of the Firebase project.", file)
            return
        }

        FirebaseApp.configure(options: options)
    }

    private static func defaultApp() throws -> FirebaseApp {
        guard let app = FirebaseApp.app() else {
            throw HaylenFailure("Firebase is not configured. Give the parameter \"servicesPlist\" the GoogleService-Info.plist of the iOS app of the Firebase project.", code: "notConfigured")
        }
        return app
    }
}
