(function () {
  const CARD_WIDTH = 745;
  const CARD_HEIGHT = 1043;
  const CANVAS_SIZE = 1024;

  let runtime;

  async function getCv() {
    if (runtime) return runtime;
    runtime = new Promise((resolve, reject) => {
      if (typeof window.cv === "undefined") {
        const script = document.createElement("script");
        script.src = "opencv.js";
        script.onerror = () => reject(new Error("OpenCV.js is unavailable."));
        document.head.appendChild(script);
      }
      const started = Date.now();
      const check = () => {
        if (window.cv?.Mat) {
          resolve({ instance: window.cv });
          return;
        }
        if (Date.now() - started >= 30000) {
          reject(new Error("OpenCV.js did not initialize."));
          return;
        }
        setTimeout(check, 25);
      };
      check();
    });
    return runtime;
  }

  function decodeBase64(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  function encodeBase64(bytes) {
    const chunks = [];
    for (let index = 0; index < bytes.length; index += 0x8000) {
      chunks.push(String.fromCharCode(...bytes.subarray(index, index + 0x8000)));
    }
    return btoa(chunks.join(""));
  }

  async function decodeImage(value) {
    const blob = new Blob([decodeBase64(value)]);
    const bitmap = await createImageBitmap(blob);
    const canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.drawImage(bitmap, 0, 0);
    bitmap.close();
    return canvas;
  }

  function orderCorners(points) {
    const by = (selector, direction) => points.reduce((best, point) =>
      direction * selector(point) > direction * selector(best) ? point : best);
    const topLeft = by((point) => point.x + point.y, -1);
    const bottomRight = by((point) => point.x + point.y, 1);
    const topRight = by((point) => point.x - point.y, 1);
    const bottomLeft = by((point) => point.x - point.y, -1);
    const ordered = [topLeft, topRight, bottomRight, bottomLeft];
    if (new Set(ordered).size !== 4) throw new Error("The card corners could not be detected.");
    return ordered;
  }

  function detectCardCorners(cv, image) {
    const scale = Math.min(1, 960 / Math.max(image.cols, image.rows));
    const working = new cv.Mat();
    const gray = new cv.Mat();
    const blurred = new cv.Mat();
    const threshold = new cv.Mat();
    const closed = new cv.Mat();
    const contours = new cv.MatVector();
    const hierarchy = new cv.Mat();
    const kernel = cv.getStructuringElement(cv.MORPH_RECT, new cv.Size(15, 15));
    try {
      cv.resize(image, working, new cv.Size(
        Math.max(1, Math.round(image.cols * scale)),
        Math.max(1, Math.round(image.rows * scale)),
      ), 0, 0, scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
      cv.cvtColor(working, gray, cv.COLOR_RGBA2GRAY);
      cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0);
      cv.threshold(blurred, threshold, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU);
      cv.morphologyEx(threshold, closed, cv.MORPH_CLOSE, kernel);
      cv.findContours(closed, contours, hierarchy, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      const minimumArea = working.rows * working.cols * 0.04;
      let bestScore = 0;
      let best = null;
      for (let index = 0; index < contours.size(); index += 1) {
        const contour = contours.get(index);
        try {
          const area = Math.abs(cv.contourArea(contour));
          if (area < minimumArea) continue;
          const rectangle = cv.minAreaRect(contour);
          const width = rectangle.size.width;
          const height = rectangle.size.height;
          if (width < 1 || height < 1) continue;
          const aspect = Math.min(width, height) / Math.max(width, height);
          const extent = area / (width * height);
          const cardRatio = CARD_WIDTH / CARD_HEIGHT;
          const aspectScore = Math.max(0, 1 - Math.abs(aspect - cardRatio) / cardRatio);
          const score = area * extent * aspectScore;
          if (score <= bestScore) continue;
          bestScore = score;
          best = orderCorners(cv.RotatedRect.points(rectangle).map((point) => ({
            x: point.x / scale,
            y: point.y / scale,
          })));
        } finally {
          contour.delete();
        }
      }
      if (!best) throw new Error("Keep one card fully visible inside the frame and try again.");
      return best;
    } finally {
      kernel.delete();
      hierarchy.delete();
      contours.delete();
      closed.delete();
      threshold.delete();
      blurred.delete();
      gray.delete();
      working.delete();
    }
  }

  function distance(left, right) {
    return Math.hypot(left.x - right.x, left.y - right.y);
  }

  function warpCard(cv, image, corners) {
    const sourceWidth = Math.max(distance(corners[0], corners[1]), distance(corners[3], corners[2]));
    const sourceHeight = Math.max(distance(corners[0], corners[3]), distance(corners[1], corners[2]));
    const landscape = sourceWidth > sourceHeight;
    const width = landscape ? CARD_HEIGHT : CARD_WIDTH;
    const height = landscape ? CARD_WIDTH : CARD_HEIGHT;
    const source = cv.matFromArray(4, 1, cv.CV_32FC2, corners.flatMap((point) => [point.x, point.y]));
    const target = cv.matFromArray(4, 1, cv.CV_32FC2, [0, 0, width - 1, 0, width - 1, height - 1, 0, height - 1]);
    const transform = cv.getPerspectiveTransform(source, target);
    const warped = new cv.Mat();
    try {
      cv.warpPerspective(image, warped, transform, new cv.Size(width, height), cv.INTER_LINEAR, cv.BORDER_CONSTANT, new cv.Scalar(255, 255, 255, 255));
      if (!landscape) return warped;
      const rotated = new cv.Mat();
      cv.rotate(warped, rotated, cv.ROTATE_90_COUNTERCLOCKWISE);
      warped.delete();
      return rotated;
    } finally {
      transform.delete();
      target.delete();
      source.delete();
    }
  }

  function letterbox(cv, rgb) {
    const scale = Math.min(CANVAS_SIZE / rgb.cols, CANVAS_SIZE / rgb.rows);
    const width = Math.round(rgb.cols * scale);
    const height = Math.round(rgb.rows * scale);
    const resized = new cv.Mat();
    const canvas = new cv.Mat(CANVAS_SIZE, CANVAS_SIZE, cv.CV_8UC3, new cv.Scalar(255, 255, 255));
    try {
      cv.resize(rgb, resized, new cv.Size(width, height), 0, 0, cv.INTER_LANCZOS4);
      const region = canvas.roi(new cv.Rect(
        Math.floor((CANVAS_SIZE - width) / 2),
        Math.floor((CANVAS_SIZE - height) / 2),
        width,
        height,
      ));
      try {
        resized.copyTo(region);
      } finally {
        region.delete();
      }
      return canvas;
    } catch (error) {
      canvas.delete();
      throw error;
    } finally {
      resized.delete();
    }
  }

  function jpegBase64(cv, card) {
    const canvas = document.createElement("canvas");
    cv.imshow(canvas, card);
    return canvas.toDataURL("image/jpeg", 0.85).split(",", 2)[1];
  }

  async function processImage(imageBase64) {
    const { instance: cv } = await getCv();
    const imageCanvas = await decodeImage(imageBase64);
    const source = cv.imread(imageCanvas);
    let card;
    let rgb;
    let canvas;
    try {
      card = warpCard(cv, source, detectCardCorners(cv, source));
      rgb = new cv.Mat();
      cv.cvtColor(card, rgb, cv.COLOR_RGBA2RGB);
      canvas = letterbox(cv, rgb);
      const pixelCount = CANVAS_SIZE * CANVAS_SIZE;
      const red = new Uint8Array(pixelCount);
      const green = new Uint8Array(pixelCount);
      const blue = new Uint8Array(pixelCount);
      for (let index = 0; index < pixelCount; index += 1) {
        red[index] = canvas.data[index * 3];
        green[index] = canvas.data[index * 3 + 1];
        blue[index] = canvas.data[index * 3 + 2];
      }
      return {
        red: encodeBase64(red),
        green: encodeBase64(green),
        blue: encodeBase64(blue),
        card: jpegBase64(cv, card),
      };
    } finally {
      if (canvas) canvas.delete();
      if (rgb) rgb.delete();
      if (card) card.delete();
      source.delete();
    }
  }

  window.kandoScan = { processImage };
})();
