#!/usr/bin/env python3
"""Compare ONNX and ORT scan-model outputs using ONNX Runtime 1.23.0."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import onnxruntime as ort


ORT_VERSION = "1.23.0"
MAX_ABSOLUTE_ERROR = 1e-4
MIN_EMBEDDING_COSINE_SIMILARITY = 0.999999
MODELS = {
    "rtmdet_ins_tiny_card_640_fp16": ("input", (1, 3, 640, 640)),
    "pe_core_t16_image_fp16": ("image", (1, 3, 384, 384)),
}


def session(path: Path) -> ort.InferenceSession:
    return ort.InferenceSession(str(path.resolve()), providers=["CPUExecutionProvider"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("onnx_directory", type=Path)
    parser.add_argument("ort_directory", type=Path)
    args = parser.parse_args()

    if ort.__version__ != ORT_VERSION:
        raise RuntimeError(
            f"Expected onnxruntime {ORT_VERSION}, found {ort.__version__}."
        )

    rng = np.random.default_rng(20260901)
    for stem, (input_name, shape) in MODELS.items():
        values = rng.standard_normal(shape, dtype=np.float32)
        onnx_outputs = session(args.onnx_directory / f"{stem}.onnx").run(
            None, {input_name: values}
        )
        ort_outputs = session(args.ort_directory / f"{stem}.ort").run(
            None, {input_name: values}
        )
        if len(onnx_outputs) != len(ort_outputs):
            raise AssertionError(f"{stem}: output count differs")
        for index, (expected, actual) in enumerate(zip(onnx_outputs, ort_outputs)):
            if expected.shape != actual.shape:
                raise AssertionError(
                    f"{stem}[{index}]: shape {expected.shape} != {actual.shape}"
                )
            if np.issubdtype(expected.dtype, np.integer):
                np.testing.assert_array_equal(actual, expected)
                maximum_error = 0.0
            else:
                maximum_error = (
                    float(np.max(np.abs(actual - expected))) if actual.size else 0.0
                )
                if maximum_error > MAX_ABSOLUTE_ERROR:
                    raise AssertionError(
                        f"{stem}[{index}]: max absolute error {maximum_error} "
                        f"exceeds {MAX_ABSOLUTE_ERROR}"
                    )
            print(
                f"{stem}[{index}]: shape={actual.shape}, max_abs={maximum_error:.8g}"
            )

        if stem == "pe_core_t16_image_fp16":
            expected = onnx_outputs[0].astype(np.float64).reshape(-1)
            actual = ort_outputs[0].astype(np.float64).reshape(-1)
            denominator = np.linalg.norm(expected) * np.linalg.norm(actual)
            cosine_similarity = float(np.dot(expected, actual) / denominator)
            if cosine_similarity < MIN_EMBEDDING_COSINE_SIMILARITY:
                raise AssertionError(
                    f"{stem}: cosine similarity {cosine_similarity} is below "
                    f"{MIN_EMBEDDING_COSINE_SIMILARITY}"
                )
            print(f"{stem}: cosine_similarity={cosine_similarity:.10f}")


if __name__ == "__main__":
    main()
