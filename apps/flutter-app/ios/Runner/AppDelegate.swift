import Flutter
import CryptoKit
import DeviceCheck
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.cardai.tcg/apple-current-entitlements",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard
        call.method == "syncCurrentEntitlements" ||
        call.method == "readCurrentEntitlements"
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let productIds = arguments["product_ids"] as? [String]
      else {
        result(FlutterError(
          code: "invalid_restore_request",
          message: "Configured Product IDs are required.",
          details: nil
        ))
        return
      }
      let configuredProductIds = Set(productIds)
      Task {
        do {
          if call.method == "syncCurrentEntitlements" {
            try await AppStore.sync()
          }
          var entitlements: [[String: String]] = []
          var hasUnverifiedConfiguredEntitlement = false
          for await verificationResult in Transaction.currentEntitlements {
            switch verificationResult {
            case .verified(let transaction):
              guard configuredProductIds.contains(transaction.productID) else { continue }
              entitlements.append([
                "product_id": transaction.productID,
                "signed_transaction_info": verificationResult.jwsRepresentation,
              ])
            case .unverified(let transaction, _):
              if configuredProductIds.contains(transaction.productID) {
                hasUnverifiedConfiguredEntitlement = true
              }
            }
          }
          if hasUnverifiedConfiguredEntitlement {
            await MainActor.run {
              result(FlutterError(
                code: "apple_restore_unverified",
                message: "A current App Store entitlement could not be verified.",
                details: nil
              ))
            }
            return
          }
          await MainActor.run { result(entitlements) }
        } catch {
          await MainActor.run {
            result(FlutterError(
              code: "apple_restore_failed",
              message: "Unable to synchronize App Store entitlements.",
              details: nil
            ))
          }
        }
      }
    }

    let appAttestChannel = FlutterMethodChannel(
      name: "com.cardai.tcg/apple-app-attest",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appAttestChannel.setMethodCallHandler { call, result in
      let service = DCAppAttestService.shared
      switch call.method {
      case "isSupported":
        result(service.isSupported)
      case "generateKey":
        service.generateKey { keyId, error in
          Self.completeAppAttest(result, value: keyId, error: error)
        }
      case "attestKey", "generateAssertion":
        guard
          let arguments = call.arguments as? [String: Any],
          let keyId = arguments["key_id"] as? String,
          let clientData = arguments["client_data"] as? String,
          let clientDataBytes = clientData.data(using: .utf8)
        else {
          result(FlutterError(
            code: "invalid_app_attest_request",
            message: "App Attest key and client data are required.",
            details: nil
          ))
          return
        }
        let clientDataHash = Data(SHA256.hash(data: clientDataBytes))
        if call.method == "attestKey" {
          service.attestKey(keyId, clientDataHash: clientDataHash) { data, error in
            Self.completeAppAttest(result, value: data?.base64EncodedString(), error: error)
          }
        } else {
          service.generateAssertion(keyId, clientDataHash: clientDataHash) { data, error in
            Self.completeAppAttest(result, value: data?.base64EncodedString(), error: error)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func completeAppAttest(
    _ result: @escaping FlutterResult,
    value: String?,
    error: Error?
  ) {
    DispatchQueue.main.async {
      if let value {
        result(value)
      } else {
        result(FlutterError(
          code: "apple_app_attest_failed",
          message: "Unable to create Apple App Attest proof.",
          details: error?.localizedDescription
        ))
      }
    }
  }
}
