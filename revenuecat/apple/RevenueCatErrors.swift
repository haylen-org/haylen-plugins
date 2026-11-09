import Foundation
import RevenueCat

// The codes that the app reads in the failures of the plugin, one for each error code of RevenueCat, with the same names on Apple platforms and Android. A cancelled purchase is `cancelled`, the code of every screen that the person closes.
enum RevenueCatErrors {
    static func code(of error: any Error) -> String {
        guard let code = error as? ErrorCode else {
            return "unknown"
        }
        return name(of: code)
    }

    static func failure(_ error: any Error) -> HaylenFailure {
        HaylenFailure(error.localizedDescription, code: code(of: error))
    }

    private static func name(of code: ErrorCode) -> String {
        switch code {
        case .unknownError: return "unknown"
        case .purchaseCancelledError: return "cancelled"
        case .storeProblemError: return "storeProblem"
        case .purchaseNotAllowedError: return "purchaseNotAllowed"
        case .purchaseInvalidError: return "purchaseInvalid"
        case .productNotAvailableForPurchaseError: return "productNotAvailableForPurchase"
        case .productAlreadyPurchasedError: return "productAlreadyPurchased"
        case .receiptAlreadyInUseError: return "receiptAlreadyInUse"
        case .invalidReceiptError: return "invalidReceipt"
        case .missingReceiptFileError: return "missingReceiptFile"
        case .networkError: return "network"
        case .invalidCredentialsError: return "invalidCredentials"
        case .unexpectedBackendResponseError: return "unexpectedBackendResponse"
        case .receiptInUseByOtherSubscriberError: return "receiptInUseByOtherSubscriber"
        case .invalidAppUserIdError: return "invalidAppUserId"
        case .operationAlreadyInProgressForProductError: return "operationAlreadyInProgress"
        case .unknownBackendError: return "unknownBackend"
        case .invalidAppleSubscriptionKeyError: return "invalidAppleSubscriptionKey"
        case .ineligibleError: return "ineligible"
        case .insufficientPermissionsError: return "insufficientPermissions"
        case .paymentPendingError: return "paymentPending"
        case .invalidSubscriberAttributesError: return "invalidSubscriberAttributes"
        case .logOutAnonymousUserError: return "logOutAnonymousUser"
        case .configurationError: return "configuration"
        case .unsupportedError: return "unsupported"
        case .emptySubscriberAttributes: return "emptySubscriberAttributes"
        case .productDiscountMissingIdentifierError: return "productDiscountMissingIdentifier"
        case .productDiscountMissingSubscriptionGroupIdentifierError: return "productDiscountMissingSubscriptionGroupIdentifier"
        case .customerInfoError: return "customerInfo"
        case .systemInfoError: return "systemInfo"
        case .beginRefundRequestError: return "beginRefundRequest"
        case .productRequestTimedOut: return "productRequestTimedOut"
        case .apiEndpointBlockedError: return "apiEndpointBlocked"
        case .invalidPromotionalOfferError: return "invalidPromotionalOffer"
        case .offlineConnectionError: return "offlineConnection"
        case .featureNotAvailableInCustomEntitlementsComputationMode: return "featureNotAvailableInCustomEntitlementsComputationMode"
        case .signatureVerificationFailed: return "signatureVerificationFailed"
        case .featureNotSupportedWithStoreKit1: return "featureNotSupportedWithStoreKit1"
        case .invalidWebPurchaseToken: return "invalidWebPurchaseToken"
        case .purchaseBelongsToOtherUser: return "purchaseBelongsToOtherUser"
        case .expiredWebPurchaseToken: return "expiredWebPurchaseToken"
        case .testStoreSimulatedPurchaseError: return "testStoreSimulatedPurchase"
        @unknown default: return "unknown"
        }
    }
}
