import { describe, expect, it } from "vitest";
import { convertLegacyStrokes, drawingExtent, erasing, pointToSegmentDistanceSquared, type Stroke } from "./drawing";

const line = (...xs: number[]): Stroke => ({ points: xs.map((x) => ({ x, y: 0 })) });

describe("erasing", () => {
  it("keeps strokes the eraser does not touch", () => {
    const strokes = [line(0, 10, 20)];
    expect(erasing(strokes, { x: 0, y: 50 }, { x: 20, y: 50 }, 9)).toEqual(strokes);
  });

  it("splits a stroke around an erased middle point", () => {
    const result = erasing([line(0, 10, 20, 30, 40)], { x: 20, y: 0 }, { x: 20, y: 0 }, 5);
    expect(result).toEqual([line(0, 10), line(30, 40)]);
  });

  it("removes a stroke whose every point is erased", () => {
    expect(erasing([line(0, 1, 2)], { x: -5, y: 0 }, { x: 5, y: 0 }, 9)).toEqual([]);
  });

  it("cuts a segment the eraser path crosses even when both ends survive", () => {
    const stroke: Stroke = { points: [{ x: 0, y: -50 }, { x: 0, y: 50 }] };
    const result = erasing([stroke], { x: -30, y: 0 }, { x: 30, y: 0 }, 1);
    expect(result).toEqual([{ points: [{ x: 0, y: -50 }] }, { points: [{ x: 0, y: 50 }] }]);
  });

  it("ignores non-finite eraser input", () => {
    const strokes = [line(0, 10)];
    expect(erasing(strokes, { x: Number.NaN, y: 0 }, { x: 0, y: 0 })).toBe(strokes);
  });

  it("drops empty strokes", () => {
    expect(erasing([{ points: [] }], { x: 100, y: 100 }, { x: 100, y: 100 })).toEqual([]);
  });
});

describe("geometry helpers", () => {
  it("measures distance to a segment", () => {
    expect(pointToSegmentDistanceSquared({ x: 5, y: 3 }, { x: 0, y: 0 }, { x: 10, y: 0 })).toBe(9);
    expect(pointToSegmentDistanceSquared({ x: -3, y: 4 }, { x: 0, y: 0 }, { x: 10, y: 0 })).toBe(25);
  });

  it("converts legacy normalized strokes with the canvas size", () => {
    expect(convertLegacyStrokes([{ points: [{ x: 0.5, y: 0.25 }] }], 320, 180)).toEqual([{ points: [{ x: 160, y: 45 }] }]);
    const untouched = [{ points: [{ x: 0.5, y: 0.5 }] }];
    expect(convertLegacyStrokes(untouched, 0, 100)).toBe(untouched);
  });

  it("reports the lowest drawn point plus half the line and a margin", () => {
    expect(drawingExtent([])).toBe(0);
    expect(drawingExtent([{ points: [{ x: 1, y: 10 }, { x: 2, y: 400 }] }])).toBeCloseTo(400 + 1.375 + 4);
    expect(drawingExtent([{ points: [{ x: 2, y: 400 }], width: 10 }])).toBe(409);
  });

  it("keeps the stroke width on every erased piece", () => {
    const result = erasing([{ points: line(0, 10, 20, 30, 40).points, width: 5 }], { x: 20, y: 0 }, { x: 20, y: 0 }, 5);
    expect(result).toEqual([{ ...line(0, 10), width: 5 }, { ...line(30, 40), width: 5 }]);
  });
});
