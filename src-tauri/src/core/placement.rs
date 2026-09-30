//! CONTRACT: port of Swift `WindowPlacement`. Coordinates are top-left
//! origin logical points (y grows downward), unlike AppKit; convert the
//! Swift tests accordingly.
//!
//! Coordinate-system note: every formula below (`bubble_placement`,
//! `clamped_origin`, the shared `clamp`) only ever combines `x`/`y` with
//! `width`/`height` relatively (min/mid/max of a box, clamped into another
//! box). None of it assumes which direction "up" is, so for a given set of
//! numeric inputs the numeric outputs are identical whether y grows up
//! (AppKit, Swift) or down (this crate). What *does* change between the two
//! systems is which edge of the screen a given y value is close to: e.g. in
//! AppKit y=0 is the *bottom* of the screen, but here y=0 is the *top*. Where
//! a Swift test's numbers only make sense next to a specific screen edge
//! (e.g. "near top/bottom edge"), the edge name in the ported test below is
//! swapped to match what the same numbers mean in a top-left system; the
//! numbers themselves (inputs and expected outputs) are unchanged.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub fn min_x(&self) -> f64 {
        self.x
    }
    pub fn max_x(&self) -> f64 {
        self.x + self.width
    }
    pub fn mid_x(&self) -> f64 {
        self.x + self.width / 2.0
    }
    pub fn min_y(&self) -> f64 {
        self.y
    }
    pub fn max_y(&self) -> f64 {
        self.y + self.height
    }
    pub fn mid_y(&self) -> f64 {
        self.y + self.height / 2.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TailSide {
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BubblePlacement {
    pub x: f64,
    pub y: f64,
    pub tail_side: TailSide,
    /// Distance from the bubble's top edge to the character's vertical center.
    pub tail_center_y: f64,
}

fn clamp(value: f64, minimum: f64, maximum: f64) -> f64 {
    if maximum < minimum {
        return minimum;
    }
    value.max(minimum).min(maximum)
}

pub fn bubble_placement(
    character: Rect,
    bubble_width: f64,
    bubble_height: f64,
    visible: Rect,
) -> BubblePlacement {
    let gap = 8.0;
    let right_origin_x = character.max_x() + gap;
    let left_origin_x = character.min_x() - gap - bubble_width;

    let (origin_x, tail_side) = if right_origin_x + bubble_width <= visible.max_x() {
        (right_origin_x, TailSide::Left)
    } else if left_origin_x >= visible.min_x() {
        (left_origin_x, TailSide::Right)
    } else {
        let clamped = clamp(
            right_origin_x,
            visible.min_x(),
            visible.max_x() - bubble_width,
        );
        let side = if character.mid_x() < visible.mid_x() {
            TailSide::Left
        } else {
            TailSide::Right
        };
        (clamped, side)
    };

    let origin_y = clamp(
        character.mid_y() - bubble_height / 2.0,
        visible.min_y(),
        visible.max_y() - bubble_height,
    );

    // Keep the whole bubble on the visible frame even when the character
    // itself is partly off screen (Swift left it off screen too).
    let origin_x = clamp(origin_x, visible.min_x(), visible.max_x() - bubble_width);

    BubblePlacement {
        x: origin_x,
        y: origin_y,
        tail_side,
        tail_center_y: character.mid_y() - origin_y,
    }
}

pub fn clamped_origin(x: f64, y: f64, width: f64, height: f64, visible: Rect) -> (f64, f64) {
    (
        clamp(x, visible.min_x(), visible.max_x() - width),
        clamp(y, visible.min_y(), visible.max_y() - height),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    // Review finding: a character dragged off the left edge must not put
    // the bubble off screen when the screen has room for it.
    #[test]
    fn bubble_stays_on_screen_when_character_is_off_the_left_edge() {
        let visible = Rect { x: 0.0, y: 0.0, width: 1000.0, height: 800.0 };
        let character = Rect { x: -500.0, y: 100.0, width: 80.0, height: 80.0 };
        let placed = bubble_placement(character, 300.0, 200.0, visible);
        assert!(placed.x >= 0.0 && placed.x + 300.0 <= 1000.0, "x = {}", placed.x);
        assert!(placed.y >= 0.0 && placed.y + 200.0 <= 800.0);
    }

    // Swift: testBubbleUsesRightSideWhenThereIsRoom (numbers are orientation
    // -agnostic here: the character sits mid-screen, not against an edge).
    #[test]
    fn bubble_uses_right_side_when_there_is_room() {
        let placement = bubble_placement(
            Rect {
                x: 100.0,
                y: 100.0,
                width: 80.0,
                height: 80.0,
            },
            300.0,
            200.0,
            Rect {
                x: 0.0,
                y: 0.0,
                width: 1_000.0,
                height: 800.0,
            },
        );

        assert_eq!(placement.tail_side, TailSide::Left);
        assert_eq!(placement.x, 188.0);
        assert_eq!(placement.y, 40.0);
        assert_eq!(placement.tail_center_y, 100.0);
    }

    // Swift: testBubbleFlipsLeftNearRightEdge (right screen edge is on the
    // x-axis, unaffected by the y-orientation flip).
    #[test]
    fn bubble_flips_left_near_right_edge() {
        let placement = bubble_placement(
            Rect {
                x: 900.0,
                y: 300.0,
                width: 80.0,
                height: 80.0,
            },
            300.0,
            200.0,
            Rect {
                x: 0.0,
                y: 0.0,
                width: 1_000.0,
                height: 800.0,
            },
        );

        assert_eq!(placement.tail_side, TailSide::Right);
        assert_eq!(placement.x, 592.0);
    }

    // Swift: testBubbleTailTracksCharacterNearBottomEdge (character y=0 in
    // AppKit's bottom-left origin touches the *bottom* edge; the same y=0 in
    // this crate's top-left origin touches the *top* edge instead, so this
    // ports as the "near top edge" case with identical numbers).
    #[test]
    fn bubble_tail_tracks_character_near_top_edge() {
        let placement = bubble_placement(
            Rect {
                x: 100.0,
                y: 0.0,
                width: 80.0,
                height: 80.0,
            },
            300.0,
            200.0,
            Rect {
                x: 0.0,
                y: 0.0,
                width: 1_000.0,
                height: 800.0,
            },
        );

        assert_eq!(placement.y, 0.0);
        assert_eq!(placement.tail_center_y, 40.0);
    }

    // Swift: testBubbleTailTracksCharacterNearTopEdge (character y=720
    // touches AppKit's *top* edge, i.e. the visible frame's maxY; the same
    // numbers in this crate's top-left origin touch the *bottom* edge).
    #[test]
    fn bubble_tail_tracks_character_near_bottom_edge() {
        let placement = bubble_placement(
            Rect {
                x: 100.0,
                y: 720.0,
                width: 80.0,
                height: 80.0,
            },
            300.0,
            200.0,
            Rect {
                x: 0.0,
                y: 0.0,
                width: 1_000.0,
                height: 800.0,
            },
        );

        assert_eq!(placement.y, 600.0);
        assert_eq!(placement.tail_center_y, 160.0);
    }

    // Swift: testClampedOriginKeepsWindowInsideVisibleFrame (`clamped_origin`
    // clamps x and y independently against the same interval math regardless
    // of orientation, so the numbers carry over unchanged).
    #[test]
    fn clamped_origin_keeps_window_inside_visible_frame() {
        let origin = clamped_origin(
            -500.0,
            900.0,
            80.0,
            80.0,
            Rect {
                x: 0.0,
                y: 24.0,
                width: 1_000.0,
                height: 776.0,
            },
        );

        assert_eq!(origin, (0.0, 720.0));
    }

    // Swift: testBubblePlacementSupportsASecondaryScreenWithNegativeCoordinates
    #[test]
    fn bubble_placement_supports_a_secondary_screen_with_negative_coordinates() {
        let visible = Rect {
            x: -1_920.0,
            y: -120.0,
            width: 1_920.0,
            height: 1_080.0,
        };
        let placement = bubble_placement(
            Rect {
                x: -110.0,
                y: 200.0,
                width: 80.0,
                height: 80.0,
            },
            360.0,
            220.0,
            visible,
        );

        assert_eq!(placement.tail_side, TailSide::Right);
        assert!(placement.x >= visible.min_x());
        assert!(placement.x + 360.0 <= visible.max_x());
        assert!(placement.y >= visible.min_y());
        assert!(placement.y + 220.0 <= visible.max_y());
    }

    // Swift: testOversizedBubbleUsesStableVisibleFrameOrigin
    #[test]
    fn oversized_bubble_uses_stable_visible_frame_origin() {
        let visible = Rect {
            x: 40.0,
            y: 25.0,
            width: 240.0,
            height: 160.0,
        };
        let placement = bubble_placement(
            Rect {
                x: 120.0,
                y: 70.0,
                width: 60.0,
                height: 60.0,
            },
            300.0,
            180.0,
            visible,
        );

        assert_eq!((placement.x, placement.y), (visible.x, visible.y));
        assert!(placement.tail_center_y.is_finite());
    }

    // Swift: testBubbleRemainsInsideScreenAcrossManyDragPositions
    #[test]
    fn bubble_remains_inside_screen_across_many_drag_positions() {
        let visible = Rect {
            x: 0.0,
            y: 24.0,
            width: 1_440.0,
            height: 876.0,
        };
        let (bubble_width, bubble_height) = (360.0, 220.0);

        let mut x = -80i64;
        while x <= 1_440 {
            let mut y = -40i64;
            while y <= 900 {
                let placement = bubble_placement(
                    Rect {
                        x: x as f64,
                        y: y as f64,
                        width: 80.0,
                        height: 80.0,
                    },
                    bubble_width,
                    bubble_height,
                    visible,
                );

                assert!(placement.x >= visible.min_x());
                assert!(placement.x + bubble_width <= visible.max_x());
                assert!(placement.y >= visible.min_y());
                assert!(placement.y + bubble_height <= visible.max_y());
                assert!(placement.tail_center_y.is_finite());

                y += 60;
            }
            x += 40;
        }
    }
}
