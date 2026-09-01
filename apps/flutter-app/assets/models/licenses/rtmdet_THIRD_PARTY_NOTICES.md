# Third-Party Notices

The trained models were developed and exported with the following principal
open-source projects. This summary is informational; the upstream license text
and notices control.

| Component | Version used | License | Role |
|---|---:|---|---|
| MMDetection | 3.3.0 | Apache-2.0 | RTMDet and RTMDet-Ins implementation |
| MMCV | 2.1.0 | Apache-2.0 | Model operators and infrastructure |
| MMEngine | 0.10.7 | Apache-2.0 | Training and configuration runtime |
| MMDeploy | 1.3.1 | Apache-2.0 | ONNX export tooling |
| MMPose | 1.3.2 | Apache-2.0 | RTMPose implementation for the alternative pipeline |
| ONNX | 1.17.0 | Apache-2.0 | Model interchange format/tooling |
| ONNX Runtime | 1.20.1 | MIT | Recommended iOS/Android inference runtime |
| OpenCV | 4.11.0 | Apache-2.0 | Reference image geometry and contour processing |

The mobile application distributor must include license notices for the actual
libraries bundled in the application. In particular, bundling ONNX Runtime
requires retaining its MIT copyright and license notice. Apple system
frameworks such as Core ML are governed by Apple's applicable terms.

No Ultralytics implementation or Ultralytics checkpoint is used by the models
in `app_pre`. The archived AGPL YOLO baseline elsewhere in the development
repository is not part of this mobile distribution package.

The training data is derived from `cards-keypoints v1` and `Card-SEG v10
PhoneCardSegV1`, both published under CC BY 4.0. Required dataset attribution,
source URLs, transformations, and usage counts are recorded in
`DATASET_PROVENANCE.md`.
