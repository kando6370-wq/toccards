#!/usr/bin/env python3
"""Convert the Android scan models to ORT format for the minimal runtime."""

from __future__ import annotations

import argparse
from pathlib import Path

import onnxruntime as ort
from onnxruntime.tools.ort_format_model.utils import create_config_from_models


ORT_VERSION = "1.23.0"
MODELS = {
    "rtmdet_ins_tiny_card_640_fp16.onnx": ort.GraphOptimizationLevel.ORT_DISABLE_ALL,
    "pe_core_t16_image_fp16.onnx": ort.GraphOptimizationLevel.ORT_ENABLE_BASIC,
}


def convert(source: Path, destination: Path, level: ort.GraphOptimizationLevel) -> None:
    options = ort.SessionOptions()
    options.graph_optimization_level = level
    options.optimized_model_filepath = str(destination.resolve())
    options.add_session_config_entry("session.save_model_format", "ORT")
    ort.InferenceSession(
        str(source.resolve()),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()

    if ort.__version__ != ORT_VERSION:
        raise RuntimeError(
            f"Expected onnxruntime {ORT_VERSION}, found {ort.__version__}."
        )

    args.output_directory.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    for filename, level in MODELS.items():
        source = args.source_directory / filename
        if not source.is_file():
            raise FileNotFoundError(source)
        destination = args.output_directory / source.with_suffix(".ort").name
        convert(source, destination, level)
        outputs.append(destination)
        print(f"{destination}: {destination.stat().st_size} bytes")

    config = args.output_directory / "required_operators_and_types.config"
    create_config_from_models(outputs, config, enable_type_reduction=True)
    print(config)


if __name__ == "__main__":
    main()
