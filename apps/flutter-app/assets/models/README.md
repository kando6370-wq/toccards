# Scan models

The source ONNX artifacts originate from the workspace-sibling
`real_time_recognition` repository (`<workspace>/real_time_recognition`). They
are conversion inputs and are not retained in this directory or packaged in
the final Android or iOS app:

- `rtmdet_ins_tiny_card_640_fp16.onnx`: RTMDet-Ins card detector, SHA-256 `6593D3537B9874F8D1485F3E491AB406AD6B965A4D15883616BED278014188B6`.
- `pe_core_t16_image_fp16.onnx`: PE-Core-T16 512-dimensional image embedding model, SHA-256 `9D8C56EBB6428BC26F6A85BFD919CD0A73DBDCBB882BBABA8C8D66E9FAAD0F2D`.

License, third-party notice, manifest, and provenance files are retained in
this directory's `licenses/` folder. The pHash scan implementation keeps the
converted PE-Core-T16 `.ort` and `.mlpackage` in this source-only
directory for comparison and rollback. `pubspec.yaml` does not declare this
directory as a Flutter asset, and Xcode has no PE-Core build reference.
Android packages only the RTMDet `.ort` from `android/app/src/main/assets/models/`
and retains the existing minimal ONNX Runtime AAR for detection. iOS builds
only the RTMDet Core ML model from `ios/Runner/Models/`. Conversion and
validation commands must receive an external ONNX source directory containing
the two files above; the embedding model is not used in this pHash build.
