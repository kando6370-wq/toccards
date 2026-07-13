# HTTP 接口对接说明

本文档给其它项目调用卡牌识别服务使用。服务由本项目根目录的 `recognize_service.py` 启动,调用方只需要通过 HTTP 上传图片并传识别参数。
启动服务：

```text
.\.venv\Scripts\python.exe recognize_service.py --host 0.0.0.0 --port 8000 --retrieval phash --resident-ocr small --ocr-device auto
```
## 服务地址

假设服务启动在本机 8000 端口:

```text
http://127.0.0.1:8000
```

如果服务绑定 `--host 0.0.0.0`,局域网其它机器使用服务所在机器的 IP 访问:

```text
http://<服务机器IP>:8000
```

## 健康检查

```http
GET /health
```

示例:

```bash
curl http://127.0.0.1:8000/health
```

返回示例:

```json
{
  "ok": true,
  "service": "mtg-card-recognition",
  "games_loaded": 81,
  "resident_phash_matrix_keys": ["all"],
  "recognition_scope": "all_games",
  "resident_ocr_model": "small",
  "ocr_device": "cuda",
  "resident_vector": false,
  "ocr_loaded": true,
  "ocr_loaded_model": "small",
  "ocr_loaded_device": "cuda",
  "vector_loaded": false,
  "phash_matrix_cache_keys": ["all"]
}
```

字段说明:

| 字段 | 说明 |
|---|---|
| `ok` | 服务是否可用 |
| `games_loaded` | 元数据库中加载到的游戏数量 |
| `resident_phash_matrix_keys` | 启动时指定常驻的 pHash 矩阵 key;`all` 表示全游戏矩阵 |
| `recognition_scope` | 固定为 `all_games`,表示服务默认扫描全部游戏 |
| `resident_ocr_model` | 常驻 OCR 模型:`small` / `tiny` / `null` |
| `ocr_device` | OCR 推理设备;服务默认 `auto`,有 CUDA 时为 `cuda`,否则为 `cpu` |
| `resident_vector` | 是否常驻向量检索 |
| `ocr_loaded` | 当前是否已有 OCR 实例 |
| `ocr_loaded_model` | 当前已加载 OCR 模型 |
| `ocr_loaded_device` | 当前已加载 OCR 实例使用的设备 |
| `vector_loaded` | 当前是否已有向量检索实例 |
| `phash_matrix_cache_keys` | 当前 pHash 矩阵缓存 key |

## 单图识别

```http
POST /recognize
Content-Type: multipart/form-data
```

必填参数:

| 参数 | 类型 | 说明 |
|---|---|---|
| `image` | file | 要识别的图片文件 |

可选参数:

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `threshold` | int | `40` | pHash 粗筛基础阈值 |
| `top` | int | `5` | 返回 Top-K 候选 |
| `save_crop` | bool | `false` | 是否保存裁剪后的卡面到 `Current_version/service_outputs/crops/` |
| `no_detect` | bool | `false` | 跳过卡牌检测裁剪,直接把整图当卡面识别 |
| `retrieval` | string | 服务启动默认值 | `hybrid` / `phash` / `vector-only` |
| `crop_method` | string | `contour` | `contour` / `tree` / `yolo` |
| `conf` | float | `0.25` | YOLO 置信度阈值,仅 `crop_method=yolo` 有效 |
| `multi` | bool | `false` | 是否识别图中检测到的所有卡 |
| `no_refine` | bool | `false` | YOLO 模式下关闭框内透视矫正 |
| `ocr_rerank` | string | 服务启动默认值 | `off` / `auto` / `force` |
| `ocr_model` | string | 服务启动默认值 | `small` / `tiny` |
| `ocr_auto_gap` | float | `0.020` | OCR auto 触发距离差阈值 |
| `phash_cluster_gap` | float | `8.0` | pHash 候选簇保留阈值 |
| `vector_cluster_gap` | float | `0.01` | 向量候选簇保留阈值 |

兼容说明:

| 参数 | 说明 |
|---|---|
| `game` | 已废弃。即使传入也会被忽略,服务仍扫描全部游戏,并在 `warnings` 中提示。 |
| `all_games` | 已废弃。服务固定扫描全部游戏;传 `false` 也会被忽略,并在 `warnings` 中提示。 |

调用示例:

```bash
curl -X POST http://127.0.0.1:8000/recognize -F "image=@Sample_images/magic/11958.jpg" -F "retrieval=phash" -F "top=1"
```

Python 示例:

```python
import requests

url = "http://127.0.0.1:8000/recognize"
with open("Sample_images/magic/11958.jpg", "rb") as f:
    resp = requests.post(
        url,
        files={"image": ("11958.jpg", f, "image/jpeg")},
        data={
            "retrieval": "phash",
            "top": "1",
        },
        timeout=120,
    )

print(resp.status_code)
print(resp.json())
```

成功返回示例:

```json
{
  "ok": true,
  "filename": "11958.jpg",
  "elapsed": 0.272336,
  "retrieval": "phash",
  "ocr_model": "small",
  "cards_detected": 1,
  "warnings": [],
  "results": [
    {
      "index": 1,
      "label": "11958.jpg",
      "matched": true,
      "elapsed": 0.112546,
      "convert_elapsed": 0.113,
      "crop_path": null,
      "matches": [
        {
          "product_id": "11958",
          "game": "Magic: The Gathering",
          "name": "Bushi Tenderfoot // Kenzo the Hardhearted",
          "number": "1",
          "set": "CHK",
          "rarity": "R",
          "distance": 35.333333333333336,
          "confidence": 86.2,
          "retrieval": "phash",
          "phash_confidence": 86.2,
          "mser_score": 0.58
        }
      ]
    }
  ]
}
```

主要返回字段:

| 字段 | 说明 |
|---|---|
| `ok` | 请求是否成功执行 |
| `filename` | 上传文件名 |
| `elapsed` | 服务端处理该图片的总耗时,单位秒 |
| `retrieval` | 本次请求使用的检索模式 |
| `ocr_model` | 本次请求使用的 OCR 模型 |
| `cards_detected` | 本图检测/处理出的卡面数量 |
| `warnings` | 非致命警告 |
| `results[].index` | 第几张卡面,从 1 开始 |
| `results[].matched` | 是否有候选命中 |
| `results[].elapsed` | 单张卡面核心识别耗时,单位秒 |
| `results[].crop_path` | `save_crop=true` 时保存的裁剪图路径 |
| `results[].matches` | 候选卡列表,按当前策略排序 |
| `matches[].product_id` | 卡牌产品 ID |
| `matches[].game` | 游戏名 |
| `matches[].name` | 卡名 |
| `matches[].distance` | pHash 距离或检索距离 |
| `matches[].confidence` | 综合置信度 |
| `matches[].retrieval` | 候选来源,如 `phash` / `vector` |
| `matches[].vector_score` | 向量分数,仅向量相关模式可能出现 |
| `matches[].ocr_distance` | OCR 文本距离,OCR 重排触发时可能出现 |
| `matches[].ocr_rank` | OCR 重排后的名次 |

没有匹配时:

```json
{
  "ok": true,
  "cards_detected": 1,
  "results": [
    {
      "index": 1,
      "matched": false,
      "matches": []
    }
  ]
}
```

## 批量识别

```http
POST /recognize/batch
Content-Type: multipart/form-data
```

参数与 `/recognize` 基本一致,区别是图片字段名为 `images`,可重复上传多个文件。

curl 示例:

```bash
curl -X POST http://127.0.0.1:8000/recognize/batch ^
  -F "images=@Sample_images/magic/11958.jpg" ^
  -F "images=@Sample_images/magic/14114.jpg" ^
  -F "retrieval=phash" ^
  -F "top=1"
```

返回结构:

```json
{
  "ok": true,
  "elapsed": 0.8123,
  "count": 2,
  "results": [
    {
      "ok": true,
      "filename": "11958.jpg",
      "results": []
    },
    {
      "ok": true,
      "filename": "14114.jpg",
      "results": []
    }
  ]
}
```

`results` 数组中的每一项与单图 `/recognize` 返回结构一致。

## 错误返回

请求参数错误:

```json
{
  "ok": false,
  "error": {
    "code": "BAD_REQUEST",
    "message": "retrieval must be one of: hybrid, phash, vector-only"
  }
}
```

服务未初始化:

```json
{
  "ok": false,
  "error": {
    "code": "SERVICE_NOT_READY",
    "message": "service is not initialized"
  }
}
```

内部异常:

```json
{
  "ok": false,
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "..."
  }
}
```

## 对接建议

- 普通单图调用建议使用 `/recognize`。
- 一张照片内已有标准卡面、无需裁剪时传 `no_detect=true`,速度更快。
- 服务默认就是全游戏检索,调用方不需要传 `game` 或 `all_games`。
- 不需要向量检索时明确传 `retrieval=phash`,避免临时加载 CLIP/FAISS。
- 如果服务启动时常驻了 `small` OCR,请求不要频繁切换 `ocr_model=tiny`;否则服务会临时切换模型再恢复常驻模型。
- OCR 设备由服务启动参数 `--ocr-device` 决定,默认 `auto`:GPU 服务器安装了可用 CUDA/Paddle 环境时使用 `cuda`,否则使用 `cpu`。
- 客户端超时时间建议不低于 120 秒,避免首次临时加载向量或 OCR 时被过早断开。
