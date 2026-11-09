package com.haylen.plugins.revenuecat

import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode

// The codes that the app reads in the failures of the plugin, one for each error code of RevenueCat, with the same names on Android and Apple platforms. A cancelled purchase is `cancelled`, the code of every screen that the person closes.
object RevenueCatErrors {
    fun code(error: PurchasesError): String =
        when (error.code) {
            PurchasesErrorCode.UnknownError -> "unknown"
            PurchasesErrorCode.PurchaseCancelledError -> "cancelled"
            PurchasesErrorCode.StoreProblemError -> "storeProblem"
            PurchasesErrorCode.PurchaseNotAllowedError -> "purchaseNotAllowed"
            PurchasesErrorCode.PurchaseInvalidError -> "purchaseInvalid"
            PurchasesErrorCode.ProductNotAvailableForPurchaseError -> "productNotAvailableForPurchase"
            PurchasesErrorCode.ProductAlreadyPurchasedError -> "productAlreadyPurchased"
            PurchasesErrorCode.ReceiptAlreadyInUseError -> "receiptAlreadyInUse"
            PurchasesErrorCode.InvalidReceiptError -> "invalidReceipt"
            PurchasesErrorCode.MissingReceiptFileError -> "missingReceiptFile"
            PurchasesErrorCode.NetworkError -> "network"
            PurchasesErrorCode.InvalidCredentialsError -> "invalidCredentials"
            PurchasesErrorCode.UnexpectedBackendResponseError -> "unexpectedBackendResponse"
            PurchasesErrorCode.InvalidAppUserIdError -> "invalidAppUserId"
            PurchasesErrorCode.OperationAlreadyInProgressError -> "operationAlreadyInProgress"
            PurchasesErrorCode.UnknownBackendError -> "unknownBackend"
            PurchasesErrorCode.InvalidAppleSubscriptionKeyError -> "invalidAppleSubscriptionKey"
            PurchasesErrorCode.IneligibleError -> "ineligible"
            PurchasesErrorCode.InsufficientPermissionsError -> "insufficientPermissions"
            PurchasesErrorCode.PaymentPendingError -> "paymentPending"
            PurchasesErrorCode.InvalidSubscriberAttributesError -> "invalidSubscriberAttributes"
            PurchasesErrorCode.LogOutWithAnonymousUserError -> "logOutAnonymousUser"
            PurchasesErrorCode.ConfigurationError -> "configuration"
            PurchasesErrorCode.UnsupportedError -> "unsupported"
            PurchasesErrorCode.EmptySubscriberAttributesError -> "emptySubscriberAttributes"
            PurchasesErrorCode.CustomerInfoError -> "customerInfo"
            PurchasesErrorCode.SignatureVerificationError -> "signatureVerificationFailed"
            PurchasesErrorCode.TestStoreSimulatedPurchaseError -> "testStoreSimulatedPurchase"
        }
}
