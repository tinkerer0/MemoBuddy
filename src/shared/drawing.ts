// Drawing data shared with the Rust store (notes.json v4) and a port of the
// Swift MemoDrawingEraser. Points are CSS pixels from the sheet's top-left.

export type Point = { x: number; y: number };
export type Stroke = { points: Point[]; width?: number };

export const DEFAULT_STROKE_WIDTH = 2.75;
export const PEN_WIDTHS = [1.5, 2.75, 5] as const;
export const ERASER_RADII = [5, 9, 16] as const;
export const ERASER_RADIUS = 9;
export const MIN_POINT_DISTANCE = 1.5;
const EPSILON = 0.000_000_001;

/** Legacy notes (no drawingCoordinateSpace) stored 0…1 coordinates. */
export function convertLegacyStrokes(strokes: Stroke[], width: number, height: number): Stroke[] {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return strokes;
  return strokes.map((stroke) => ({ ...stroke, points: stroke.points.map((p) => ({ x: p.x * width, y: p.y * height })) }));
}

/** Largest y (plus line width margin) so the sheet can grow to show it. */
export function drawingExtent(strokes: Stroke[]): number {
  let max = 0;
  for (const stroke of strokes) {
    const half = (stroke.width ?? DEFAULT_STROKE_WIDTH) / 2;
    for (const point of stroke.points) if (Number.isFinite(point.y) && point.y + half > max) max = point.y + half;
  }
  return max > 0 ? max + 4 : 0;
}

export function erasing(strokes: Stroke[], start: Point, end: Point, radius = ERASER_RADIUS): Stroke[] {
  const radiusSquared = radius * radius;
  if (!(radius > 0) || !Number.isFinite(radiusSquared) || ![start.x, start.y, end.x, end.y].every(Number.isFinite)) return strokes;
  return strokes.flatMap((stroke) => eraseStroke(stroke, start, end, radiusSquared));
}

function eraseStroke(stroke: Stroke, eraserStart: Point, eraserEnd: Point, radiusSquared: number): Stroke[] {
  const [first] = stroke.points;
  if (!first) return [];
  const fragments: Stroke[] = [];
  let current: Point[] = [];
  // Pieces keep the width of the stroke they were cut from.
  const flush = () => {
    if (current.length) fragments.push(stroke.width === undefined ? { points: current } : { points: current, width: stroke.width });
    current = [];
  };
  if (pointToSegmentDistanceSquared(first, eraserStart, eraserEnd) > radiusSquared) current.push(first);
  for (let index = 1; index < stroke.points.length; index++) {
    const previous = stroke.points[index - 1];
    const point = stroke.points[index];
    const pointErased = pointToSegmentDistanceSquared(point, eraserStart, eraserEnd) <= radiusSquared;
    const lineErased = segmentDistanceSquared(previous, point, eraserStart, eraserEnd) <= radiusSquared;
    if (pointErased || lineErased) {
      flush();
      if (!pointErased) current.push(point);
    } else {
      current.push(point);
    }
  }
  flush();
  return fragments;
}

function segmentDistanceSquared(a1: Point, a2: Point, b1: Point, b2: Point): number {
  if (segmentsIntersect(a1, a2, b1, b2)) return 0;
  return Math.min(
    pointToSegmentDistanceSquared(a1, b1, b2),
    pointToSegmentDistanceSquared(a2, b1, b2),
    pointToSegmentDistanceSquared(b1, a1, a2),
    pointToSegmentDistanceSquared(b2, a1, a2),
  );
}

export function pointToSegmentDistanceSquared(point: Point, start: Point, end: Point): number {
  const sx = end.x - start.x;
  const sy = end.y - start.y;
  const lengthSquared = sx * sx + sy * sy;
  if (lengthSquared <= 0) return squaredDistance(point, start);
  const projection = ((point.x - start.x) * sx + (point.y - start.y) * sy) / lengthSquared;
  const t = Math.min(Math.max(projection, 0), 1);
  return squaredDistance(point, { x: start.x + t * sx, y: start.y + t * sy });
}

function segmentsIntersect(a1: Point, a2: Point, b1: Point, b2: Point): boolean {
  const d1 = cross(a1, a2, b1);
  const d2 = cross(a1, a2, b2);
  const d3 = cross(b1, b2, a1);
  const d4 = cross(b1, b2, a2);
  const opposite = (p: number, q: number) => (p > EPSILON && q < -EPSILON) || (p < -EPSILON && q > EPSILON);
  if (opposite(d1, d2) && opposite(d3, d4)) return true;
  return (
    (Math.abs(d1) <= EPSILON && onSegment(b1, a1, a2)) ||
    (Math.abs(d2) <= EPSILON && onSegment(b2, a1, a2)) ||
    (Math.abs(d3) <= EPSILON && onSegment(a1, b1, b2)) ||
    (Math.abs(d4) <= EPSILON && onSegment(a2, b1, b2))
  );
}

function cross(start: Point, end: Point, point: Point): number {
  return (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x);
}

function onSegment(point: Point, start: Point, end: Point): boolean {
  return (
    point.x >= Math.min(start.x, end.x) - EPSILON &&
    point.x <= Math.max(start.x, end.x) + EPSILON &&
    point.y >= Math.min(start.y, end.y) - EPSILON &&
    point.y <= Math.max(start.y, end.y) + EPSILON
  );
}

function squaredDistance(a: Point, b: Point): number {
  const x = b.x - a.x;
  const y = b.y - a.y;
  return x * x + y * y;
}
