import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func test227LinearPreprocessingProducesExpectedCoreMLDetection() throws {
    let imageURL = try XCTUnwrap(
      Bundle(for: type(of: self)).url(forResource: "227", withExtension: "PNG")
    )
    let imageData = try Data(contentsOf: imageURL)
    let prepared = try ScanNativeImageProcessor.prepareDetection([
      "image": FlutterStandardTypedData(bytes: imageData),
      "maximum_size": 640,
    ])
    let sourceWidth = try XCTUnwrap(prepared["source_width"] as? Int)
    let sourceHeight = try XCTUnwrap(prepared["source_height"] as? Int)
    let resizedWidth = try XCTUnwrap(prepared["resized_width"] as? Int)
    let resizedHeight = try XCTUnwrap(prepared["resized_height"] as? Int)
    let rgbData = try XCTUnwrap(
      (prepared["rgb_bytes"] as? FlutterStandardTypedData)?.data
    )
    XCTAssertEqual(sourceWidth, 1206)
    XCTAssertEqual(sourceHeight, 1515)
    XCTAssertEqual(resizedWidth, 509)
    XCTAssertEqual(resizedHeight, 640)
    XCTAssertEqual(rgbData.count, resizedWidth * resizedHeight * 3)

    let inputSize = 640
    let planeSize = inputSize * inputSize
    let mean: [Float32] = [103.53, 116.28, 123.675]
    let standardDeviation: [Float32] = [57.375, 57.12, 58.395]
    var tensor = [Float32](repeating: 0, count: planeSize * 3)
    for channel in 0..<3 {
      let padding = (114 - mean[channel]) / standardDeviation[channel]
      tensor.replaceSubrange(
        (channel * planeSize)..<((channel + 1) * planeSize),
        with: repeatElement(padding, count: planeSize)
      )
    }
    rgbData.withUnsafeBytes { rawBytes in
      let rgb = rawBytes.bindMemory(to: UInt8.self)
      for y in 0..<resizedHeight {
        for x in 0..<resizedWidth {
          let sourceOffset = (y * resizedWidth + x) * 3
          let targetOffset = y * inputSize + x
          for channel in 0..<3 {
            tensor[channel * planeSize + targetOffset] =
              (Float32(rgb[sourceOffset + 2 - channel]) - mean[channel])
              / standardDeviation[channel]
          }
        }
      }
    }
    let tensorData = tensor.withUnsafeBytes { Data($0) }
    let outputs = try ScanModelRuntime.runDetection([
      "tensor": FlutterStandardTypedData(float32: tensorData)
    ])
    let detections = try floatValues(outputs["dets"])
    let masks = try floatValues(outputs["masks"])
    XCTAssertEqual(detections.count, 5)
    XCTAssertEqual(masks.count, inputSize * inputSize)
    XCTAssertEqual(detections[4], 0.535, accuracy: 0.02)

    var minimumX = inputSize
    var minimumY = inputSize
    var maximumX = -1
    var maximumY = -1
    var foregroundCount = 0
    for index in masks.indices where masks[index] >= 0.5 {
      let x = index % inputSize
      let y = index / inputSize
      minimumX = min(minimumX, x)
      minimumY = min(minimumY, y)
      maximumX = max(maximumX, x)
      maximumY = max(maximumY, y)
      foregroundCount += 1
    }
    print(
      "227 detection score=\(detections[4]) "
        + "mask_bbox=\(minimumX),\(minimumY),\(maximumX),\(maximumY) "
        + "foreground=\(foregroundCount)"
    )
    XCTAssertLessThanOrEqual(abs(minimumX - 77), 6)
    XCTAssertLessThanOrEqual(abs(minimumY - 158), 6)
    XCTAssertLessThanOrEqual(abs(maximumX - 418), 6)
    XCTAssertLessThanOrEqual(abs(maximumY - 510), 6)
    XCTAssertLessThanOrEqual(abs(foregroundCount - 101_789), 5_000)
  }

  private func floatValues(_ value: Any?) throws -> [Float32] {
    let data = try XCTUnwrap((value as? FlutterStandardTypedData)?.data)
    XCTAssertEqual(data.count % MemoryLayout<Float32>.size, 0)
    return data.withUnsafeBytes { rawBytes in
      Array(rawBytes.bindMemory(to: Float32.self))
    }
  }
}
