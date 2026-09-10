# Android minimal ONNX Runtime

Android uses ONNX Runtime 1.23.0 built specifically for the two scan models.
The checked-in AAR contains the four Android ABIs and only the CPU operators
and tensor types listed in `required_operators_and_types.config`.

Generate the ORT models and operator configuration with ONNX Runtime 1.23.0:

```text
python convert_models_to_ort.py <onnx-source-directory> <output-directory>
python validate_ort_models.py <onnx-source-directory> <output-directory>
```

After validation, copy the two `.ort` files to
`../../android/app/src/main/assets/models/` and replace
`required_operators_and_types.config` in this directory with the generated
configuration before rebuilding the AAR. The source `.onnx` models remain in
the caller-provided source directory (normally the workspace-sibling
`<workspace>/real_time_recognition` repository) and are not packaged in the
Android app.

Build the AAR from an ONNX Runtime checkout at tag `v1.23.0`:

```text
pwsh ./build_minimal_aar.ps1 \
  -OnnxRuntimeSource <onnxruntime-source> \
  -AndroidSdk <android-sdk> \
  -AndroidNdk <android-ndk>
```

The build uses `MinSizeRel`, LTO, the minimal runtime, reduced operator/type
support, and disables exceptions, ML ops, contrib ops, and KleidiAI. Linux is
the recommended build host for the upstream multi-ABI AAR script. On Windows,
use a short build path and enable symbolic-link creation for the packaging
step.

The generated ORT artifacts used by the app are:

- `android/app/libs/onnxruntime-minimal-1.23.0.aar`: 3,754,131 bytes,
  SHA-256 `6A98BCC4F8D9C18A84C1EFF495F0E83069F04765F657CBFC41865C04682593CA`.
- `rtmdet_ins_tiny_card_640_fp16.ort`: SHA-256 `9CF6389186A56FB08E26A52DF39CDBE551416556BF278D9BB8194F51D7225BEE`.
- `pe_core_t16_image_fp16.ort`: SHA-256 `35EC37B210DBF785B9FC6D298D4012372DC8C0F1A1182A1FFF051BFCF59ADCCD`.
- `required_operators_and_types.config`: SHA-256 `1EBFFF28310D7EF107040B2B8B72CDF9173935161A65D4C2E14EAB572D688CC2`.

The validation script uses deterministic random inputs and requires maximum
absolute output error no greater than `1e-4`; the embedding cosine similarity
must be at least `0.999999`.

Compared with the official 1.23.0 Android AAR and the original ONNX models,
the checked-in runtime AAR is 26,282,994 bytes smaller while the ORT models
are 811,395 bytes larger. The combined packaged inputs are therefore
25,471,599 bytes (24.29 MiB) smaller. This is an artifact-level comparison;
the final APK/AAB installed-size delta must be measured from release builds.
