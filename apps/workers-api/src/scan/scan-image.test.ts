import { describe, expect, it } from "vitest";
import { validateScanImage } from "./scan-image";

describe("scan image validation", () => {
  it("accepts a controlled corrected-card JPEG because audit storage must not require the surrounding camera frame", async () => {
    const image = await validateScanImage(
      new File([jpeg(745, 1043)], "scan.jpg", { type: "image/jpeg" }),
    );

    expect(image).toEqual(expect.objectContaining({
      contentType: "image/jpeg",
      extension: "jpg",
      width: 745,
      height: 1043,
    }));
  });

  it("rejects MIME and pixel dimensions outside the audit contract because R2 must not become arbitrary file storage", async () => {
    await expect(validateScanImage(
      new File([jpeg(745, 1043)], "scan.png", { type: "image/png" }),
    )).resolves.toBeNull();
    await expect(validateScanImage(
      new File([jpeg(200, 200)], "scan.jpg", { type: "image/jpeg" }),
    )).resolves.toBeNull();
  });
});

function jpeg(width: number, height: number): Uint8Array {
  return new Uint8Array([
    0xff, 0xd8,
    0xff, 0xc0, 0x00, 0x11, 0x08,
    (height >>> 8) & 0xff, height & 0xff,
    (width >>> 8) & 0xff, width & 0xff,
    0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
    0xff, 0xd9,
  ]);
}
