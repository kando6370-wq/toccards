# Scan models

The source ONNX artifacts originate from the workspace-sibling
`real_time_recognition` repository (`<workspace>/real_time_recognition`). They
are conversion inputs and are not retained in this directory or packaged in
the final Android or iOS app:

- `rtmdet_ins_tiny_card_640_fp16.onnx`: RTMDet-Ins card detector, SHA-256 `6593D3537B9874F8D1485F3E491AB406AD6B965A4D15883616BED278014188B6`.
- `pe_core_t16_image_fp16.onnx`: PE-Core-T16 512-dimensional image embedding model, SHA-256 `9D8C56EBB6428BC26F6A85BFD919CD0A73DBDCBB882BBABA8C8D66E9FAAD0F2D`.

License, third-party notice, manifest, and provenance files are retained in
this directory's `licenses/` folder. Android packages model-specific ORT-format
artifacts in `android/app/src/main/assets/models/` and runs them with the local
minimal ONNX Runtime AAR. iOS uses the corresponding converted Core ML models
from `ios/Runner/Models/`. Conversion and validation commands must receive an
external ONNX source directory containing the two files above. The runtime
contract is `pe-core-t16-384-cosine-v1`; these models are not compatible with
the retired RGB pHash protocol.
