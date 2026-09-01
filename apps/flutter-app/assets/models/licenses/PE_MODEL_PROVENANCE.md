# PE-Core-T16-384 Model Provenance

## Conversion source artifact

| File | Format | SHA-256 |
|---|---|---|
| `pe_core_t16_image_fp16.onnx` | ONNX with FP16 weight storage and FP32 I/O | `9d8c56ebb6428bc26f6a85bfd919cd0a73dbdcbb882bbaba8c8d66e9faad0f2d` |

This hash identifies the exact ONNX conversion input supplied by the
workspace-sibling `real_time_recognition` repository. The ONNX file is not
retained in this directory or packaged in the app; the app distributes derived
ORT and Core ML artifacts documented in the parent `README.md`.

## Upstream model

- Repository: `facebook/PE-Core-T16-384`
- Model developer stated by the upstream model card: Meta
- Canonical source: https://huggingface.co/facebook/PE-Core-T16-384
- Pinned revision: `8b4722741a516c18e7d311f158f13c600fea6c78`
- Pinned model card: https://huggingface.co/facebook/PE-Core-T16-384/blob/8b4722741a516c18e7d311f158f13c600fea6c78/README.md
- Pinned checkpoint: https://huggingface.co/facebook/PE-Core-T16-384/resolve/8b4722741a516c18e7d311f158f13c600fea6c78/PE-Core-T16-384.pt
- Upstream checkpoint size reported by Hugging Face: `278284008` bytes
- Upstream linked ETag reported by Hugging Face: `868f89f066b7c1ae51add02d2cb7b925fd051076282773f2ec3c71359fbdaf3b`
- Upstream Xet object hash reported by Hugging Face: `87541917e295a14043c7630b71978670a3f5449371f5c5f98964294b7a17c2d9`
- Metadata checked: 2026-08-17

The pinned Hugging Face API metadata and model-card front matter both identify
the license as `apache-2.0`. The upstream model card identifies Meta as the
model developer. The ETag and Xet hash above are upstream object identifiers;
they were not recomputed from a locally retained copy of the 278 MB checkpoint.

The model card links to Meta's `facebookresearch/perception_models` source
repository. Its Apache-2.0 repository metadata and root file list were checked
at commit `3e352cca660658d4b5c90f42a7808b11469e4c66`. The local `LICENSE.PE` has Git
blob ID `261eeb9e9f8b2b4b0d119366dda99c6fd7d35c64`, exactly matching the upstream
`LICENSE.PE` at that commit. No root `NOTICE` file was present at the checked
revision.

- Source repository: https://github.com/facebookresearch/perception_models
- Pinned license: https://github.com/facebookresearch/perception_models/blob/3e352cca660658d4b5c90f42a7808b11469e4c66/LICENSE.PE

## Project conversion

The source ONNX file is a modified and converted form of the upstream
checkpoint. The project extracted the image encoder used by this application,
fixed the input to `float32[1,3,384,384]`, exposed an L2-normalized
`float32[1,512]` embedding, exported ONNX, and converted eligible weight storage
to FP16. Numerical validation and the preprocessing contract are recorded in
the source `real_time_recognition` repository's `export_report.json`,
`deployment_validation.json`, and `README_zh.md`; those source-project reports
are not duplicated in this directory.

This section is the prominent modification notice required when distributing a
modified Apache-2.0 work. It does not claim that Meta created or endorsed this
ONNX conversion.

## License and release obligations

The upstream model and the project-converted artifacts are distributed under
Apache License 2.0; the complete terms are in `LICENSE.PE`.

When redistributing the model or a derived artifact:

1. Include `LICENSE.PE`, this provenance file, and the upstream attribution.
2. Retain applicable copyright, patent, trademark, and attribution notices.
3. Preserve any upstream `NOTICE` file if a future pinned revision includes one.
4. State further modifications made to the model files.
5. Do not imply Meta endorsement or a grant of Meta trademark rights.

The model license does not grant rights to card images, gallery data, product
names, logos, or trademarks processed by the application. Those assets require
their own authorization and review.
