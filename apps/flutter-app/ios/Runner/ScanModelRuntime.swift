import CoreML
import Flutter
import Foundation

private enum ScanModelRuntimeError: LocalizedError {
  case invalidInput
  case modelMissing(String)
  case invalidOutput(String)
  case noDetection

  var errorDescription: String? {
    switch self {
    case .invalidInput:
      return "The model input tensor is invalid."
    case .modelMissing(let name):
      return "The bundled model \(name) is missing."
    case .invalidOutput(let name):
      return "The model output \(name) is invalid."
    case .noDetection:
      return "No card was detected."
    }
  }
}

private struct ScanTensorView {
  let array: MLMultiArray
  let pointer: UnsafeMutablePointer<Float32>
  let strides: [Int]

  init(_ array: MLMultiArray, shape: [Int]) throws {
    let actualShape = array.shape.map(\.intValue)
    guard
      array.dataType == .float32,
      actualShape == shape || actualShape == [1] + shape
    else {
      throw ScanModelRuntimeError.invalidOutput("tensor")
    }
    self.array = array
    pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
    let actualStrides = array.strides.map(\.intValue)
    strides = actualShape.count == 4 ? actualStrides : [0] + actualStrides
  }

  subscript(_ batch: Int, _ channel: Int, _ y: Int, _ x: Int) -> Float32 {
    pointer[
      batch * strides[0] + channel * strides[1] + y * strides[2] + x * strides[3]
    ]
  }
}

private struct ScanDetectionCandidate {
  let score: Float32
  let x1: Float32
  let y1: Float32
  let x2: Float32
  let y2: Float32
  let gridX: Int
  let gridY: Int
  let stride: Int
  let kernel: ScanTensorView
}

final class ScanModelRuntime {
  private static let queue = DispatchQueue(
    label: "com.cardai.tcg.scan-model-runtime",
    qos: .userInitiated
  )
  private static var detectionModel: MLModel?
  private static var embeddingModel: MLModel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.cardai.tcg/scan-model-runtime",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "runDetection" || call.method == "runEmbedding" else {
        result(FlutterMethodNotImplemented)
        return
      }
      queue.async {
        do {
          let value: Any
          if call.method == "runDetection" {
            value = try runDetection(call.arguments)
          } else {
            value = try runEmbedding(call.arguments)
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "scan_model_runtime_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
  }

  private static func runDetection(_ rawArguments: Any?) throws -> [String: Any] {
    let input = try inputArray(rawArguments, shape: [1, 3, 640, 640])
    let model = try loadModel(
      named: "RTMDetInsTinyCardRawFP16",
      cached: &detectionModel
    )
    let provider = try MLDictionaryFeatureProvider(dictionary: [
      "input": MLFeatureValue(multiArray: input)
    ])
    let output = try model.prediction(from: provider)
    let candidate = try bestCandidate(output)
    let mask = try decodeMask(candidate, output: output)
    let detections: [Float32] = [
      candidate.x1,
      candidate.y1,
      candidate.x2,
      candidate.y2,
      candidate.score,
    ]
    return [
      "dets": typedFloats(detections),
      "dets_shape": [1, 1, 5],
      "masks": typedFloats(mask),
      "masks_shape": [1, 1, 640, 640],
    ]
  }

  private static func runEmbedding(_ rawArguments: Any?) throws -> FlutterStandardTypedData {
    let input = try inputArray(rawArguments, shape: [1, 3, 384, 384])
    let model = try loadModel(named: "PECoreT16ImageFP16", cached: &embeddingModel)
    let provider = try MLDictionaryFeatureProvider(dictionary: [
      "image": MLFeatureValue(multiArray: input)
    ])
    let output = try model.prediction(from: provider)
    guard
      let embedding = output.featureValue(for: "embedding")?.multiArrayValue,
      embedding.dataType == .float32,
      embedding.count == 512
    else {
      throw ScanModelRuntimeError.invalidOutput("embedding")
    }
    let pointer = embedding.dataPointer.bindMemory(to: Float32.self, capacity: 512)
    return typedFloats(Array(UnsafeBufferPointer(start: pointer, count: 512)))
  }

  private static func inputArray(
    _ rawArguments: Any?,
    shape: [NSNumber]
  ) throws -> MLMultiArray {
    guard
      let arguments = rawArguments as? [String: Any],
      let typedData = arguments["tensor"] as? FlutterStandardTypedData
    else {
      throw ScanModelRuntimeError.invalidInput
    }
    let count = shape.reduce(1) { $0 * $1.intValue }
    guard typedData.data.count == count * MemoryLayout<Float32>.size else {
      throw ScanModelRuntimeError.invalidInput
    }
    let array = try MLMultiArray(shape: shape, dataType: .float32)
    typedData.data.withUnsafeBytes { source in
      guard let sourceAddress = source.baseAddress else { return }
      memcpy(array.dataPointer, sourceAddress, typedData.data.count)
    }
    return array
  }

  private static func loadModel(
    named name: String,
    cached model: inout MLModel?
  ) throws -> MLModel {
    if let model { return model }
    guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
      throw ScanModelRuntimeError.modelMissing(name)
    }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    let loaded = try MLModel(contentsOf: url, configuration: configuration)
    model = loaded
    return loaded
  }

  private static func bestCandidate(
    _ output: MLFeatureProvider
  ) throws -> ScanDetectionCandidate {
    var best: ScanDetectionCandidate?
    for stride in [8, 16, 32] {
      guard
        let clsArray = output.featureValue(for: "cls_\(stride)")?.multiArrayValue,
        let bboxArray = output.featureValue(for: "bbox_\(stride)")?.multiArrayValue,
        let kernelArray = output.featureValue(for: "kernel_\(stride)")?.multiArrayValue
      else {
        throw ScanModelRuntimeError.invalidOutput("detection level \(stride)")
      }
      let height = 640 / stride
      let width = 640 / stride
      let cls = try ScanTensorView(clsArray, shape: [1, height, width])
      let bbox = try ScanTensorView(bboxArray, shape: [4, height, width])
      let kernel = try ScanTensorView(kernelArray, shape: [169, height, width])
      for y in 0..<height {
        for x in 0..<width {
          let score = cls[0, 0, y, x]
          if let best, score <= best.score { continue }
          let centerX = Float32(x * stride)
          let centerY = Float32(y * stride)
          let x1 = max(0, centerX - bbox[0, 0, y, x])
          let y1 = max(0, centerY - bbox[0, 1, y, x])
          let x2 = min(640, centerX + bbox[0, 2, y, x])
          let y2 = min(640, centerY + bbox[0, 3, y, x])
          guard x2 > x1, y2 > y1 else { continue }
          best = ScanDetectionCandidate(
            score: score,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            gridX: x,
            gridY: y,
            stride: stride,
            kernel: kernel
          )
        }
      }
    }
    guard let best else { throw ScanModelRuntimeError.noDetection }
    return best
  }

  private static func decodeMask(
    _ candidate: ScanDetectionCandidate,
    output: MLFeatureProvider
  ) throws -> [Float32] {
    guard let featureArray = output.featureValue(for: "mask_features")?.multiArrayValue else {
      throw ScanModelRuntimeError.invalidOutput("mask_features")
    }
    let features = try ScanTensorView(featureArray, shape: [8, 80, 80])
    var parameters = [Float32](repeating: 0, count: 169)
    for index in parameters.indices {
      parameters[index] = candidate.kernel[
        0,
        index,
        candidate.gridY,
        candidate.gridX
      ]
    }

    var lowResolution = [Float32](repeating: 0, count: 80 * 80)
    let priorX = Float32(candidate.gridX * candidate.stride)
    let priorY = Float32(candidate.gridY * candidate.stride)
    let coordinateScale = Float32(candidate.stride * 8)
    for y in 0..<80 {
      for x in 0..<80 {
        var input = [Float32](repeating: 0, count: 10)
        input[0] = (priorX - Float32(x * 8)) / coordinateScale
        input[1] = (priorY - Float32(y * 8)) / coordinateScale
        for channel in 0..<8 {
          input[channel + 2] = features[0, channel, y, x]
        }
        var hidden1 = [Float32](repeating: 0, count: 8)
        for channel in 0..<8 {
          var value = parameters[152 + channel]
          for inputChannel in 0..<10 {
            value += parameters[channel * 10 + inputChannel] * input[inputChannel]
          }
          hidden1[channel] = max(0, value)
        }
        var hidden2 = [Float32](repeating: 0, count: 8)
        for channel in 0..<8 {
          var value = parameters[160 + channel]
          for inputChannel in 0..<8 {
            value += parameters[80 + channel * 8 + inputChannel] * hidden1[inputChannel]
          }
          hidden2[channel] = max(0, value)
        }
        var logit = parameters[168]
        for channel in 0..<8 {
          logit += parameters[144 + channel] * hidden2[channel]
        }
        lowResolution[y * 80 + x] = logit
      }
    }
    return upsampleMask(lowResolution)
  }

  private static func upsampleMask(_ source: [Float32]) -> [Float32] {
    var output = [Float32](repeating: 0, count: 640 * 640)
    for y in 0..<640 {
      let sourceY = (Float32(y) + 0.5) / 8 - 0.5
      let y0 = max(0, min(79, Int(floor(sourceY))))
      let y1 = min(79, y0 + 1)
      let yWeight = max(0, min(1, sourceY - Float32(y0)))
      for x in 0..<640 {
        let sourceX = (Float32(x) + 0.5) / 8 - 0.5
        let x0 = max(0, min(79, Int(floor(sourceX))))
        let x1 = min(79, x0 + 1)
        let xWeight = max(0, min(1, sourceX - Float32(x0)))
        let top = source[y0 * 80 + x0] * (1 - xWeight)
          + source[y0 * 80 + x1] * xWeight
        let bottom = source[y1 * 80 + x0] * (1 - xWeight)
          + source[y1 * 80 + x1] * xWeight
        output[y * 640 + x] = sigmoid(top * (1 - yWeight) + bottom * yWeight)
      }
    }
    return output
  }

  private static func sigmoid(_ value: Float32) -> Float32 {
    1 / (1 + exp(-value))
  }

  private static func typedFloats(_ values: [Float32]) -> FlutterStandardTypedData {
    values.withUnsafeBytes { bytes in
      FlutterStandardTypedData(float32: Data(bytes))
    }
  }
}
