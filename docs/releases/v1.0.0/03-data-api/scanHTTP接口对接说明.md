# v1.0.0 扫描识别接口

本文记录 Flutter、Workers 与外部 OCR 服务之间当前生效的协议。App 只调用 Workers，不直接调用 OCR 服务。

## App -> Workers

```http
POST /api/v1/scan/recognize
Authorization: Bearer <access_token>
Content-Type: multipart/form-data
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `image` | 是 | 经服务端格式、尺寸和容量校验的卡牌图片 |
| `r`、`g`、`b` | 是 | RGB 三通道 pHash，43 个 Base64URL 字符 |
| `game_id` | 否 | 限定识别游戏 |
| `card_number` | 否 | OCR 提取的卡号，用于候选消歧 |
| `filename`、`platform`、`app_version` | 否 | 扫描审计元数据 |
| `device_model`、`os_version` | 否 | 设备审计元数据 |

Workers 必须先验证 App JWT，并要求 `OCR_SERVICE_BASE_URL` 与 `SCAN_IMAGES` binding 可用。图片写入 R2 后才调用上游；扫描记录保存当前所有者、R2 key、候选、上游原始响应和耗时信息。

## Workers -> OCR

```http
POST {OCR_SERVICE_BASE_URL}/recognize
Accept: application/json
Content-Type: application/json
```

请求：

```json
{
  "r": "<base64url-phash>",
  "g": "<base64url-phash>",
  "b": "<base64url-phash>",
  "game_id": 1
}
```

`game_id` 未提供时省略。当前 Workers 不向 OCR 服务转发原图或 `card_number`。

响应必须包含 `candidates` 数组：

```json
{
  "candidates": [
    { "product_id": 12345, "confidence": 96.4 }
  ]
}
```

- `product_id` 必须是 1 至 `4294967295` 的整数。
- `confidence` 必须是 0 至 100 的有限数值。
- 重复 `product_id` 只保留第一次出现。
- 整个响应结构非法时按上游失败处理。

## 候选解析

Workers 使用 `product_id` 查询 D1 卡牌目录并转换为 `card_ref`。未命中目录的候选保留在审计数据中，但不返回给 App。若提供 `card_number`，服务端优先排列号码匹配项，并可用候选名称和卡号补充检索目录。

识别状态：有效候选为 `success`，合法空候选为 `no_match`，上游/解析失败为 `failed`。

## 确认入库

```http
POST /api/v1/scan/:scan_id/confirm
Authorization: Bearer <access_token>
Content-Type: application/json
```

请求使用收藏条目草稿字段，包括扫描候选中的 `card_ref`、当前所有者文件夹、数量、Raw/评级属性、语言、工艺、购买价和备注。服务端验证扫描与文件夹都属于当前所有者、扫描仍为 `pending`、候选存在且收藏 SKU 不重复。

成功后批量创建收藏条目和事件、删除同卡愿望单、把扫描确认状态改为 `confirmed`。重复确认或并发冲突返回 409。

## 失败补偿

- R2 写入失败：不调用 OCR，不创建扫描记录。
- OCR 失败：保留扫描原图和失败审计记录，返回 502。
- 扫描记录持久化失败：尝试删除刚上传的 R2 对象。
- 确认失败：不把扫描标记为成功确认。

证据：`apps/workers-api/src/scan/routes.ts`、`apps/flutter-app/lib/features/scan/`。
