import Foundation
import RevenueCat

// Native part of the RevenueCat plugin on Apple platforms. It configures RevenueCat while the app launches with the parameter `appleApiKey`, answers with offerings and customer info as plain tables, and sells a package through the screen `purchase`, which covers the app while the sheet of the App Store shows. Customer info that changes on its own, such as a renewal or a purchase made on another device, reaches the app as the retained event `customerInfoUpdated`. RevenueCat calls its delegate on the main thread, so the plugin conforms to the delegate protocol on the main actor.
@objc(RevenueCatPlugin)
final class RevenueCatPlugin: NSObject, HaylenPlugin, @MainActor PurchasesDelegate {
    struct Empty: Codable {}

    struct User: Decodable {
        let appUserId: String
    }

    struct Purchase: Decodable {
        let offering: String?
        let package: String
    }

    struct Customer: Encodable {
        let appUserId: String
        let activeEntitlements: [String]
        let activeSubscriptions: [String]
        let purchasedProducts: [String]
        let managementUrl: String?

        init(_ info: CustomerInfo) {
            appUserId = info.originalAppUserId
            activeEntitlements = info.entitlements.active.keys.sorted()
            activeSubscriptions = info.activeSubscriptions.sorted()
            purchasedProducts = info.allPurchasedProductIdentifiers.sorted()
            managementUrl = info.managementURL?.absoluteString
        }
    }

    struct LoggedIn: Encodable {
        let customerInfo: Customer
        let created: Bool
    }

    struct Purchased: Encodable {
        let productIdentifier: String
        let customerInfo: Customer
    }

    struct Product: Encodable {
        let identifier: String
        let productIdentifier: String
        let title: String
        let description: String
        let price: Double
        let priceString: String
        let currencyCode: String?

        init(_ package: Package) {
            let product = package.storeProduct
            identifier = package.identifier
            productIdentifier = product.productIdentifier
            title = product.localizedTitle
            description = product.localizedDescription
            price = NSDecimalNumber(decimal: product.price).doubleValue
            priceString = product.localizedPriceString
            currencyCode = product.currencyCode
        }
    }

    struct OfferingAnswer: Encodable {
        let identifier: String
        let description: String
        let packages: [Product]

        init(_ offering: Offering) {
            identifier = offering.identifier
            description = offering.serverDescription
            packages = offering.availablePackages.map(Product.init)
        }
    }

    struct OfferingsAnswer: Encodable {
        let current: String?
        let all: [OfferingAnswer]

        init(_ offerings: Offerings) {
            current = offerings.current?.identifier
            all = offerings.all.values.sorted { $0.identifier < $1.identifier }.map(OfferingAnswer.init)
        }
    }

    private var context: HaylenPluginContext!

    func load(with context: HaylenPluginContext) {
        self.context = context
        let debugLogs = context.config["debugLogs"] as? Bool ?? false
        Purchases.logLevel = debugLogs ? .debug : .warn

        // The tooling stops a build whose haylen.json gives no key.
        let apiKey = context.config["appleApiKey"] as! String
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self

        registerCustomer()
        registerPurchase()
    }

    private func registerCustomer() {
        context.register("customerInfo") { (_: Empty) async throws -> Customer in
            let info = try await Self.revenueCat { try await Purchases.shared.customerInfo() }
            return Customer(info)
        }
        context.register("offerings") { (_: Empty) async throws -> OfferingsAnswer in
            let offerings = try await Self.revenueCat { try await Purchases.shared.offerings() }
            return OfferingsAnswer(offerings)
        }
        context.register("restorePurchases") { (_: Empty) async throws -> Customer in
            let info = try await Self.revenueCat { try await Purchases.shared.restorePurchases() }
            return Customer(info)
        }
        context.register("logIn") { (params: User) async throws -> LoggedIn in
            let (info, created) = try await Self.revenueCat { try await Purchases.shared.logIn(params.appUserId) }
            return LoggedIn(customerInfo: Customer(info), created: created)
        }
        context.register("logOut") { (_: Empty) async throws -> Customer in
            let info = try await Self.revenueCat { try await Purchases.shared.logOut() }
            return Customer(info)
        }
    }

    // The sheet of the App Store presents itself, and the app cannot close it, so a cancel of the app waits for the person to answer the sheet.
    private func registerPurchase() {
        context.registerScreen("purchase") { [unowned self] (params: Purchase, screen: HaylenScreen) in
            screen.cancelHandler = {}
            Task { await self.purchase(params, screen: screen) }
        }
    }

    private func purchase(_ params: Purchase, screen: HaylenScreen) async {
        do {
            let package = try await Self.package(params)
            let result = try await Self.revenueCat { try await Purchases.shared.purchase(package: package) }
            guard !result.userCancelled else {
                screen.fail("The person closed the purchase.", code: "cancelled", data: nil)
                return
            }

            let productIdentifier = result.transaction?.productIdentifier ?? package.storeProduct.productIdentifier
            try screen.finish(encoding: Purchased(productIdentifier: productIdentifier, customerInfo: Customer(result.customerInfo)))
        } catch let failure as HaylenFailure {
            screen.fail(failure.message, code: failure.code, data: nil)
        } catch {
            screen.fail(error.localizedDescription, code: "exception", data: nil)
        }
    }

    // The package of the offering that the app names, or of the current offering without a name.
    private static func package(_ params: Purchase) async throws -> Package {
        let offerings = try await revenueCat { try await Purchases.shared.offerings() }
        var offering = offerings.current
        if let name = params.offering {
            offering = offerings.offering(identifier: name)
        }
        guard let offering else {
            throw HaylenFailure("RevenueCat has no offering \"\(params.offering ?? "current")\".", code: "notFound")
        }
        guard let package = offering.package(identifier: params.package) else {
            throw HaylenFailure("The offering \"\(offering.identifier)\" holds no package \"\(params.package)\".", code: "notFound")
        }
        return package
    }

    // Runs a call of RevenueCat and fails with the code of its error.
    private static func revenueCat<Answer>(_ call: () async throws -> Answer) async throws -> Answer {
        do {
            return try await call()
        } catch {
            throw RevenueCatErrors.failure(error)
        }
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        do {
            try context.emit("customerInfoUpdated", Customer(customerInfo), retain: true)
        } catch {
            NSLog("The plugin \"revenuecat\" could not encode the customer info: \(error)")
        }
    }
}
