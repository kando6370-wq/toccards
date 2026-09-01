import Flutter
import CoreImage
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
    ScanNativeImageProcessor.register(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    ScanModelRuntime.register(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    let channel = FlutterMethodChannel(
      name: "com.cardai.tcg/apple-current-entitlements",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard
        call.method == "syncAppStore" ||
        call.method == "syncCurrentEntitlements" ||
        call.method == "readCurrentEntitlements"
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "syncAppStore" {
        Task {
          do {
            try await AppStore.sync()
            await MainActor.run { result(nil) }
          } catch StoreKitError.userCancelled {
            await MainActor.run {
              result(FlutterError(
                code: "apple_restore_cancelled",
                message: "App Store synchronization was cancelled.",
                details: nil
              ))
            }
          } catch {
            let nsError = error as NSError
            await MainActor.run {
              result(FlutterError(
                code: "apple_restore_failed",
                message: "Unable to synchronize App Store entitlements.",
                details: [
                  "domain": nsError.domain,
                  "code": nsError.code,
                ]
              ))
            }
          }
        }
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
          let nsError = error as NSError
          let errorDomain = nsError.domain
          let errorCode = nsError.code
          await MainActor.run {
            result(FlutterError(
              code: "apple_restore_failed",
              message: "Unable to synchronize App Store entitlements.",
              details: [
                "domain": errorDomain,
                "code": errorCode,
              ]
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

private enum ScanNativeImageProcessor {
  private static let queue = DispatchQueue(
    label: "com.cardai.tcg.scan-image-processor",
    qos: .userInitiated
  )
  private static let ciContext = CIContext(options: [.cacheIntermediates: false])
  private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.cardai.tcg/scan-image-processor",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepareDetection" || call.method == "rectifyCard" else {
        result(FlutterMethodNotImplemented)
        return
      }
      queue.async {
        do {
          let value: [String: Any]
          if call.method == "prepareDetection" {
            value = try prepareDetection(call.arguments)
          } else {
            value = try rectifyCard(call.arguments)
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "scan_image_processing_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
  }

  private static func prepareDetection(_ rawArguments: Any?) throws -> [String: Any] {
    guard
      let arguments = rawArguments as? [String: Any],
      let typedData = arguments["image"] as? FlutterStandardTypedData,
      let maximumSize = arguments["maximum_size"] as? Int,
      maximumSize > 0,
      let image = UIImage(data: typedData.data),
      let cgImage = image.cgImage
    else {
      throw ScanNativeImageError.invalidInput
    }

    let swapsDimensions: Bool
    switch image.imageOrientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      swapsDimensions = true
    default:
      swapsDimensions = false
    }
    let sourceWidth = swapsDimensions ? cgImage.height : cgImage.width
    let sourceHeight = swapsDimensions ? cgImage.width : cgImage.height
    let scale = min(
      Double(maximumSize) / Double(sourceWidth),
      Double(maximumSize) / Double(sourceHeight)
    )
    let resizedWidth = max(1, min(maximumSize, Int((Double(sourceWidth) * scale).rounded(.toNearestOrEven))))
    let resizedHeight = max(1, min(maximumSize, Int((Double(sourceHeight) * scale).rounded(.toNearestOrEven))))
    let rgb = try rgbBytes(from: image, width: resizedWidth, height: resizedHeight)
    return [
      "source_width": sourceWidth,
      "source_height": sourceHeight,
      "resized_width": resizedWidth,
      "resized_height": resizedHeight,
      "rgb_bytes": FlutterStandardTypedData(bytes: rgb),
    ]
  }

  private static func rectifyCard(_ rawArguments: Any?) throws -> [String: Any] {
    guard
      let arguments = rawArguments as? [String: Any],
      let typedData = arguments["image"] as? FlutterStandardTypedData,
      let cornerNumbers = arguments["corners"] as? [NSNumber],
      cornerNumbers.count == 8,
      cornerNumbers.allSatisfy({ $0.doubleValue.isFinite }),
      let cardWidth = arguments["card_width"] as? Int,
      let cardHeight = arguments["card_height"] as? Int,
      let embeddingSize = arguments["embedding_size"] as? Int,
      let jpegQuality = arguments["jpeg_quality"] as? Int,
      cardWidth > 0,
      cardHeight > 0,
      embeddingSize > 0,
      let source = CIImage(
        data: typedData.data,
        options: [.applyOrientationProperty: true]
      )
    else {
      throw ScanNativeImageError.invalidInput
    }

    let extent = source.extent
    guard !extent.isEmpty && !extent.isInfinite else {
      throw ScanNativeImageError.invalidInput
    }
    func vector(_ index: Int) -> CIVector {
      CIVector(
        x: extent.minX + CGFloat(cornerNumbers[index * 2].doubleValue),
        y: extent.maxY - CGFloat(cornerNumbers[index * 2 + 1].doubleValue)
      )
    }
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      throw ScanNativeImageError.correctionFailed
    }
    filter.setValue(source, forKey: kCIInputImageKey)
    filter.setValue(vector(0), forKey: "inputTopLeft")
    filter.setValue(vector(1), forKey: "inputTopRight")
    filter.setValue(vector(2), forKey: "inputBottomRight")
    filter.setValue(vector(3), forKey: "inputBottomLeft")
    guard let corrected = filter.outputImage, !corrected.extent.isEmpty else {
      throw ScanNativeImageError.correctionFailed
    }

    let translated = corrected.transformed(
      by: CGAffineTransform(
        translationX: -corrected.extent.minX,
        y: -corrected.extent.minY
      )
    )
    let fixed = translated
      .transformed(
        by: CGAffineTransform(
          scaleX: CGFloat(cardWidth) / translated.extent.width,
          y: CGFloat(cardHeight) / translated.extent.height
        )
      )
      .cropped(
        to: CGRect(
          x: 0,
          y: 0,
          width: CGFloat(cardWidth),
          height: CGFloat(cardHeight)
        )
      )
    guard let fixedCGImage = ciContext.createCGImage(fixed, from: fixed.extent) else {
      throw ScanNativeImageError.correctionFailed
    }
    let cardImage = UIImage(cgImage: fixedCGImage)
    guard let jpeg = cardImage.jpegData(compressionQuality: CGFloat(jpegQuality) / 100) else {
      throw ScanNativeImageError.encodingFailed
    }
    let embeddingRgb = try rgbBytes(
      from: cardImage,
      width: embeddingSize,
      height: embeddingSize
    )
    return [
      "card_image_bytes": FlutterStandardTypedData(bytes: jpeg),
      "embedding_rgb_bytes": FlutterStandardTypedData(bytes: embeddingRgb),
    ]
  }

  private static func rgbBytes(from image: UIImage, width: Int, height: Int) throws -> Data {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
    let created = rgba.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let base = bytes.baseAddress,
        let context = CGContext(
          data: base,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else { return false }
      context.interpolationQuality = .medium
      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      image.draw(
        in: CGRect(
          x: 0,
          y: 0,
          width: CGFloat(width),
          height: CGFloat(height)
        )
      )
      UIGraphicsPopContext()
      return true
    }
    guard created else { throw ScanNativeImageError.renderingFailed }

    var rgb = Data(count: width * height * 3)
    rgb.withUnsafeMutableBytes { outputBytes in
      guard let output = outputBytes.bindMemory(to: UInt8.self).baseAddress else { return }
      for index in 0..<(width * height) {
        let source = index * bytesPerPixel
        let target = index * 3
        output[target] = rgba[source]
        output[target + 1] = rgba[source + 1]
        output[target + 2] = rgba[source + 2]
      }
    }
    return rgb
  }
}

private enum ScanNativeImageError: LocalizedError {
  case invalidInput
  case correctionFailed
  case encodingFailed
  case renderingFailed

  var errorDescription: String? {
    switch self {
    case .invalidInput:
      return "The selected image is invalid."
    case .correctionFailed:
      return "The detected card could not be perspective-corrected."
    case .encodingFailed:
      return "The corrected card image could not be encoded."
    case .renderingFailed:
      return "The image could not be rendered."
    }
  }
}
