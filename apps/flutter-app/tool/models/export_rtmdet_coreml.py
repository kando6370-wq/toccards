#!/usr/bin/env python3
"""Export the RTMDet-Ins raw prediction head as an iOS Core ML model.

NMS and dynamic mask decoding intentionally stay in the iOS application. Core
ML receives the same normalized NCHW tensor as the Android model and emits
the three detection levels plus the shared mask feature map.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import mmcv.utils.ext_loader
import numpy as np
import torch
from mmengine.config import Config
from mmengine.registry import init_default_scope
from mmengine.runner.checkpoint import load_state_dict


class _UnavailableMmcvOps:
    def __getattr__(self, name: str):
        def unavailable(*_args, **_kwargs):
            raise RuntimeError(f"MMCV native op {name} is unavailable during export")

        return unavailable


# The exported raw head is convolution-only. MMDetection imports its NMS
# modules eagerly, so allow mmcv-lite to register them without loading _ext.
mmcv.utils.ext_loader.load_ext = lambda *_args, **_kwargs: _UnavailableMmcvOps()

import mmdet.models  # noqa: E402,F401
from mmdet.registry import MODELS  # noqa: E402


OUTPUT_NAMES = [
    "cls_8",
    "cls_16",
    "cls_32",
    "bbox_8",
    "bbox_16",
    "bbox_32",
    "kernel_8",
    "kernel_16",
    "kernel_32",
    "mask_features",
]


class RawRTMDetIns(torch.nn.Module):
    def __init__(self, detector: torch.nn.Module) -> None:
        super().__init__()
        self.backbone = detector.backbone
        self.neck = detector.neck
        self.head = detector.bbox_head

    def forward(self, image: torch.Tensor):
        features = self.neck(self.backbone(image))
        cls_scores, bbox_predictions, kernels, mask_features = self.head(features)
        return (*cls_scores, *bbox_predictions, *kernels, mask_features)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--format",
        choices=("mlprogram", "neuralnetwork"),
        default="mlprogram",
        help="Use neuralnetwork on non-macOS hosts that lack BlobWriter.",
    )
    args = parser.parse_args()

    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    config = Config.fromstring(checkpoint["meta"]["cfg"], ".py")
    init_default_scope(config.get("default_scope", "mmdet"))
    detector = MODELS.build(config.model)
    load_state_dict(detector, checkpoint["state_dict"], strict=False)
    detector.eval()

    raw_model = RawRTMDetIns(detector).eval()
    example = torch.zeros((1, 3, 640, 640), dtype=torch.float32)
    with torch.inference_mode():
        traced = torch.jit.trace(raw_model, example, strict=False)

    convert_options = {
        "convert_to": args.format,
        "minimum_deployment_target": (
            ct.target.iOS16 if args.format == "mlprogram" else ct.target.iOS14
        ),
        "inputs": [
            ct.TensorType(
                name="input",
                shape=(1, 3, 640, 640),
                dtype=np.float32,
            )
        ],
        "outputs": [ct.TensorType(name=name) for name in OUTPUT_NAMES],
    }
    if args.format == "mlprogram":
        convert_options["compute_precision"] = ct.precision.FLOAT16
    converted = ct.convert(traced, **convert_options)
    if args.format == "neuralnetwork":
        from coremltools.models.neural_network.quantization_utils import (
            quantize_weights,
        )

        converted = quantize_weights(converted, nbits=16)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(args.output))


if __name__ == "__main__":
    main()
