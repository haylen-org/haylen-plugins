import BackgroundAssets
import Foundation
import System

// Native part of the Background Assets plugin on iOS, tvOS and visionOS. It makes the asset pack of the App Store that holds a named pack of the content available on the device, reports its progress, and answers each fetch with the folder of the pack inside the downloaded asset packs, or with no folder on systems before 26 and for packs that the App Store does not host, so the content server delivers them instead.
@objc(BackgroundAssetsPlugin)
final class BackgroundAssetsPlugin: NSObject, HaylenPlugin {
    struct Pack: Decodable {
        let pack: String
    }

    struct Folder: Encodable {
        let folder: String?
    }

    struct State: Encodable {
        let pack: String
        let status: String
    }

    struct Progress: Encodable {
        let pack: String
        let receivedBytes: Int64
        let totalBytes: Int64
    }

    func load(with context: HaylenPluginContext) {
        context.register("fetch") { (params: Pack) async throws -> Folder in
            guard #available(iOS 26, tvOS 26, visionOS 26, *) else {
                return Folder(folder: nil)
            }
            return try await Self.fetch(params.pack, context: context)
        }
        context.register("state") { (params: Pack) async throws -> State in
            guard #available(iOS 26.4, tvOS 26.4, visionOS 26.4, *) else {
                return State(pack: params.pack, status: "unavailable")
            }
            let local = AssetPackManager.shared.assetPackIsAvailableLocally(withID: params.pack)
            return State(pack: params.pack, status: local ? "available" : "notDownloaded")
        }
    }

    // The App Store gives no asset pack to an app that it does not host packs for, such as one installed another way, or while the device cannot reach it, and the next source of packs or the content server delivers the pack then.
    @available(iOS 26, tvOS 26, visionOS 26, *)
    private static func hostedPack(_ id: String, manager: AssetPackManager) async -> AssetPack? {
        if #available(iOS 27, tvOS 27, visionOS 27, *) {
            let manifest = try? await manager.manifest
            return manifest?.assetPack(withID: id)
        }
        return try? await manager.assetPack(withID: id)
    }

    // A pack on the device may be the version of an earlier build of the app, which lacks the shards that this build needs, so systems that tell versions bring the latest one.
    @available(iOS 26, tvOS 26, visionOS 26, *)
    private static func download(_ pack: AssetPack, manager: AssetPackManager) async throws {
        do {
            if #available(iOS 26.4, tvOS 26.4, visionOS 26.4, *) {
                try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
                return
            }
            try await manager.ensureLocalAvailability(of: pack)
        } catch {
            throw HaylenFailure("The system failed to download the asset pack \"\(pack.id)\". \(error.localizedDescription)", code: "downloadFailed")
        }
    }

    @available(iOS 26, tvOS 26, visionOS 26, *)
    private static func reportProgress(of pack: AssetPack, manager: AssetPackManager, context: HaylenPluginContext) -> Task<Void, Never> {
        Task { @MainActor in
            let total = Int64(pack.downloadSize)
            for await update in manager.statusUpdates(forAssetPackWithID: pack.id) {
                guard case .downloading(_, let fraction) = update else {
                    continue
                }
                let received = Int64(fraction.fractionCompleted * Double(total))
                try? context.emit("progress", Progress(pack: pack.id, receivedBytes: received, totalBytes: total))
            }
        }
    }

    @available(iOS 26, tvOS 26, visionOS 26, *)
    private static func fetch(_ id: String, context: HaylenPluginContext) async throws -> Folder {
        let manager = AssetPackManager.shared
        guard let pack = await hostedPack(id, manager: manager) else {
            return Folder(folder: nil)
        }

        let progress = reportProgress(of: pack, manager: manager, context: context)
        defer {
            progress.cancel()
        }
        try await download(pack, manager: manager)

        // The lookup reads the file system, so it runs off the main thread.
        let folder = try await Task.detached {
            try manager.url(for: FilePath(id)).path
        }.value
        return Folder(folder: folder)
    }
}
