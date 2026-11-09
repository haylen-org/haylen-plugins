import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

// Native part of the AdMob plugin on iOS and iPadOS. The consent form, the privacy options, the interstitial ads and the rewarded ads are screens of the plugin, so the engine covers the app while they show. The banner is a view of the overlay, which reserves its edge of the safe area so the interface of the app moves out of its way, and the page that a tap on the banner opens covers the app until it closes.
@objc(AdMobPlugin)
final class AdMobPlugin: NSObject, HaylenPlugin, BannerViewDelegate {
    struct Empty: Codable {}

    struct Started: Encodable {
        let started: Bool
    }

    struct Consent: Decodable {
        let debugGeography: String?
        let testDeviceIds: [String]?
    }

    struct ConsentState: Encodable {
        let status: String
        let canRequestAds: Bool
        let privacyOptionsRequired: Bool
    }

    struct Banner: Decodable {
        let adUnitId: String
        let position: String
    }

    struct Unit: Decodable {
        let adUnitId: String
    }

    struct Loaded: Encodable {
        let loaded: Bool
    }

    // Ends the screen of a full-screen ad once the person closes the ad, with the reward of a rewarded ad when the person earned it.
    private final class FullScreenEnd: NSObject, FullScreenContentDelegate {
        let screen: HaylenScreen
        let ended: () -> Void
        var reward: AdReward?

        init(screen: HaylenScreen, ended: @escaping () -> Void) {
            self.screen = screen
            self.ended = ended
        }

        func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
            var result: [String: Any] = ["shown": true, "rewarded": reward != nil]
            if let reward {
                result["type"] = reward.type
                result["amount"] = reward.amount.doubleValue
            }
            screen.finish(result)
            ended()
        }

        func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
            screen.fail(error.localizedDescription, code: "showFailed", data: nil)
            ended()
        }
    }

    private var context: HaylenPluginContext!
    private var banner: BannerView?
    private var bannerItem: HaylenOverlay.Item?
    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var showing: FullScreenEnd?

    func load(with context: HaylenPluginContext) {
        self.context = context
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = context.config["testDeviceIds"] as? [String] ?? []

        context.register("start") { (_: Empty) async throws -> Started in
            _ = await MobileAds.shared.start()
            return Started(started: true)
        }
        context.register("consentState") { (_: Empty) async throws -> ConsentState in
            Self.consentState()
        }
        registerConsent()
        registerBanner()
        registerFullScreenAds()
    }

    // The forms of the User Messaging Platform present themselves, and the app cannot close them, so a cancel of the app waits for the person to answer the form.
    private func registerConsent() {
        context.registerScreen("consent") { [unowned self] (params: Consent, screen: HaylenScreen) in
            let parameters = try Self.consentParameters(params)
            screen.cancelHandler = {}
            Task { await self.presentConsent(parameters, screen: screen) }
        }
        context.registerScreen("privacyOptions") { [unowned self] (_: Empty, screen: HaylenScreen) in
            screen.cancelHandler = {}
            Task { await self.presentPrivacyOptions(screen) }
        }
    }

    private func registerBanner() {
        context.register("showBanner") { [unowned self] (params: Banner) async throws -> Empty in
            try self.showBanner(params)
            return Empty()
        }
        context.register("hideBanner") { [unowned self] (_: Empty) async throws -> Empty in
            self.hideBanner()
            return Empty()
        }
    }

    // An ad that shows cannot be closed by the app, so a cancel of the app waits for the person to close it.
    private func registerFullScreenAds() {
        context.register("loadInterstitial") { [unowned self] (params: Unit) async throws -> Loaded in
            self.interstitial = try await Self.loading { try await InterstitialAd.load(with: params.adUnitId, request: Request()) }
            return Loaded(loaded: true)
        }
        context.register("loadRewarded") { [unowned self] (params: Unit) async throws -> Loaded in
            self.rewarded = try await Self.loading { try await RewardedAd.load(with: params.adUnitId, request: Request()) }
            return Loaded(loaded: true)
        }
        context.registerScreen("interstitial") { [unowned self] (_: Empty, screen: HaylenScreen) in
            guard let ad = self.interstitial else {
                throw HaylenFailure("No interstitial ad is loaded. Load one with \"admob.loadInterstitial\" first.", code: "notLoaded")
            }
            self.interstitial = nil
            ad.fullScreenContentDelegate = self.endsScreen(screen)
            screen.cancelHandler = {}
            ad.present(from: screen.presenter)
        }
        context.registerScreen("rewarded") { [unowned self] (_: Empty, screen: HaylenScreen) in
            guard let ad = self.rewarded else {
                throw HaylenFailure("No rewarded ad is loaded. Load one with \"admob.loadRewarded\" first.", code: "notLoaded")
            }
            self.rewarded = nil
            let end = self.endsScreen(screen)
            ad.fullScreenContentDelegate = end
            screen.cancelHandler = {}
            ad.present(from: screen.presenter) {
                end.reward = ad.adReward
            }
        }
    }

    private func endsScreen(_ screen: HaylenScreen) -> FullScreenEnd {
        let end = FullScreenEnd(screen: screen) { [weak self] in
            self?.showing = nil
        }
        showing = end
        return end
    }

    private static func loading<Ad>(_ load: () async throws -> Ad) async throws -> Ad {
        do {
            return try await load()
        } catch {
            throw HaylenFailure(error.localizedDescription, code: "loadFailed", data: ["errorCode": (error as NSError).code])
        }
    }

    private static func consentParameters(_ params: Consent) throws -> RequestParameters {
        let parameters = RequestParameters()
        guard params.debugGeography != nil || params.testDeviceIds != nil else {
            return parameters
        }

        let debug = DebugSettings()
        debug.geography = try debugGeography(params.debugGeography)
        debug.testDeviceIdentifiers = params.testDeviceIds ?? []
        parameters.debugSettings = debug
        return parameters
    }

    private static func debugGeography(_ name: String?) throws -> DebugGeography {
        switch name {
        case nil:
            return .disabled
        case "eea":
            return .EEA
        case "notEea":
            return .other
        default:
            throw HaylenFailure("The \"debugGeography\" of the consent is \"eea\" or \"notEea\", not \"\(name ?? "")\".", code: "invalidParams")
        }
    }

    private func presentConsent(_ parameters: RequestParameters, screen: HaylenScreen) async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: screen.presenter)
            try screen.finish(encoding: Self.consentState())
        } catch {
            screen.fail(error.localizedDescription, code: "consentFailed", data: nil)
        }
    }

    private func presentPrivacyOptions(_ screen: HaylenScreen) async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: screen.presenter)
            try screen.finish(encoding: Self.consentState())
        } catch {
            screen.fail(error.localizedDescription, code: "consentFailed", data: nil)
        }
    }

    private static func consentState() -> ConsentState {
        let information = ConsentInformation.shared
        let privacyOptionsRequired = information.privacyOptionsRequirementStatus == .required
        return ConsentState(status: statusName(information.consentStatus), canRequestAds: information.canRequestAds, privacyOptionsRequired: privacyOptionsRequired)
    }

    private static func statusName(_ status: ConsentStatus) -> String {
        switch status {
        case .obtained:
            return "obtained"
        case .required:
            return "required"
        case .notRequired:
            return "notRequired"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    // The banner takes the width of the safe area of the app and the height that Google picks for that width.
    private func showBanner(_ params: Banner) throws {
        let anchor = try Self.anchor(params.position)
        guard let presenter = context.viewController else {
            throw HaylenFailure("The app has no window yet.", code: "noWindow")
        }

        hideBanner()
        let safeWidth = presenter.view.bounds.inset(by: presenter.view.safeAreaInsets).width
        let view = BannerView(adSize: largeAnchoredAdaptiveBanner(width: safeWidth))
        view.adUnitID = params.adUnitId
        view.rootViewController = presenter
        view.delegate = self

        let placement = HaylenPlacement(anchor: anchor)
        placement.reserve = true
        placement.width = view.adSize.size.width
        placement.height = view.adSize.size.height
        banner = view
        bannerItem = context.overlay.add(view, placement: placement)
        view.load(Request())
    }

    private static func anchor(_ position: String) throws -> HaylenPlacement.Anchor {
        switch position {
        case "top":
            return .top
        case "bottom":
            return .bottom
        default:
            throw HaylenFailure("The position of a banner is \"top\" or \"bottom\", not \"\(position)\".", code: "invalidParams")
        }
    }

    private func hideBanner() {
        bannerItem?.remove()
        bannerItem = nil
        banner = nil
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        context.emit("bannerLoaded", payload: ["width": bannerView.adSize.size.width, "height": bannerView.adSize.size.height])
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
        context.emit("bannerFailed", payload: ["message": error.localizedDescription, "code": (error as NSError).code])
    }

    func bannerViewWillPresentScreen(_ bannerView: BannerView) {
        context.coverApp()
    }

    func bannerViewDidDismissScreen(_ bannerView: BannerView) {
        context.uncoverApp()
    }
}
