// Copyright 2026 The Flutter Authors and the CardScanFox contributors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation

struct DuoScanAngles {
  let preview: Int
  let capture: Int

  init(previewDegrees: CGFloat, captureDegrees: CGFloat) {
    preview = Self.quarterTurns(previewDegrees)
    capture = Self.quarterTurns(captureDegrees)
  }

  private static func quarterTurns(_ degrees: CGFloat) -> Int {
    // 视频连接只接受四个直角。预览和拍照都按相同规则取整。
    guard degrees.isFinite else { return 0 }
    let turns = Int((degrees.truncatingRemainder(dividingBy: 360) / 90).rounded())
    return (turns + 4) % 4
  }
}

@available(iOS 17.0, *)
final class DuoScanRotation: NSObject {
  private let coordinator: AVCaptureDevice.RotationCoordinator
  private var observations: [NSKeyValueObservation] = []

  init(device: AVCaptureDevice, previewLayer: CALayer) {
    coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
  }

  var angles: DuoScanAngles {
    DuoScanAngles(
      previewDegrees: coordinator.videoRotationAngleForHorizonLevelPreview,
      captureDegrees: coordinator.videoRotationAngleForHorizonLevelCapture)
  }

  func observe(_ update: @escaping (DuoScanAngles) -> Void) {
    // KVO 在主线程回调。每次都读取预览和拍照角度，再一起交给相机会话队列。
    observations = [
      coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
        [weak self] _, _ in
        if let self { update(self.angles) }
      },
      coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) {
        [weak self] _, _ in
        if let self { update(self.angles) }
      },
    ]
  }
}
