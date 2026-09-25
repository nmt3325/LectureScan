#!/usr/bin/env python3
"""Compare the pre-area and area-priority rectangle acquisition policies.

This is a deterministic candidate-level synthetic experiment, not an image or
real-device accuracy claim. Each scene defines the largest valid rectangle as
the intended main surface, then randomizes Vision rank, position, shape, and
one to five smaller distractors. The formulas mirror RectangleResolver before
and after the area-priority change closely enough to expose selector bias.
"""

from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass
from typing import Callable, Optional


@dataclass(frozen=True)
class Candidate:
    area: float
    minimum_edge_ratio: float
    fill_ratio: float
    rank_utility: float
    center_utility: float
    is_main: bool
    original_index: int


def smoothstep(lower: float, upper: float, value: float) -> float:
    t = min(max((value - lower) / (upper - lower), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def clamp(value: float) -> float:
    return min(max(value, 0.0), 1.0)


def previous_score(candidate: Candidate) -> float:
    size_utility = smoothstep(0.08, 0.25, candidate.minimum_edge_ratio)
    fill_utility = clamp((candidate.fill_ratio - 0.45) / (1.0 - 0.45))
    return (
        0.45 * size_utility
        + 0.30 * fill_utility
        + 0.15 * candidate.rank_utility
        + 0.10 * candidate.center_utility
    )


def area_score(candidate: Candidate, maximum_area: float) -> float:
    size_utility = smoothstep(0.08, 0.25, candidate.minimum_edge_ratio)
    relative_area_utility = clamp(candidate.area / maximum_area)
    absolute_area_utility = smoothstep(0.03, 0.40, candidate.area)
    fill_utility = clamp((candidate.fill_ratio - 0.45) / (1.0 - 0.45))
    return (
        0.35 * relative_area_utility
        + 0.25 * absolute_area_utility
        + 0.15 * size_utility
        + 0.10 * fill_utility
        + 0.05 * candidate.rank_utility
        + 0.10 * candidate.center_utility
    )


def select_previous(candidates: list[Candidate]) -> Optional[Candidate]:
    ranked = sorted(
        candidates,
        key=lambda candidate: (-previous_score(candidate), candidate.original_index),
    )
    if previous_score(ranked[0]) < 0.55:
        return None
    if len(ranked) > 1 and previous_score(ranked[0]) - previous_score(ranked[1]) < 0.12:
        return None
    return ranked[0]


def select_area_priority(candidates: list[Candidate]) -> Optional[Candidate]:
    by_area = sorted(candidates, key=lambda candidate: (-candidate.area, candidate.original_index))
    maximum_area = by_area[0].area
    if len(by_area) == 1 or maximum_area >= by_area[1].area * 1.25:
        if area_score(by_area[0], maximum_area) >= 0.55:
            return by_area[0]

    area_tier = [candidate for candidate in candidates if candidate.area >= maximum_area * 0.70]
    ranked = sorted(
        area_tier,
        key=lambda candidate: (
            -area_score(candidate, maximum_area),
            -candidate.area,
            candidate.original_index,
        ),
    )
    if area_score(ranked[0], maximum_area) < 0.55:
        return None
    if len(ranked) > 1 and area_score(ranked[0], maximum_area) - area_score(ranked[1], maximum_area) < 0.12:
        return None
    return ranked[0]


def dimensions(rng: random.Random, area: float, aspect_range: tuple[float, float]) -> tuple[float, float]:
    while True:
        aspect = rng.uniform(*aspect_range)
        width = math.sqrt(area * aspect)
        height = math.sqrt(area / aspect)
        if width <= 0.96 and height <= 0.96:
            return width, height


def make_candidate(
    rng: random.Random,
    *,
    area: float,
    original_index: int,
    total_count: int,
    is_main: bool,
) -> Candidate:
    aspect_range = (1.4, 4.0) if is_main else (0.65, 1.8)
    width, height = dimensions(rng, area, aspect_range)
    minimum_edge_ratio = min(width * 1_024, height * 768) / 768
    if is_main:
        center_x = rng.uniform(0.35, 0.65)
        center_y = rng.uniform(0.30, 0.70)
    else:
        center_x = clamp(rng.gauss(0.5, 0.16))
        center_y = clamp(rng.gauss(0.5, 0.16))
    center_distance = math.hypot(center_x - 0.5, center_y - 0.5) / math.sqrt(0.5)
    return Candidate(
        area=area,
        minimum_edge_ratio=minimum_edge_ratio,
        fill_ratio=rng.uniform(0.78, 1.0),
        rank_utility=clamp(1.0 - original_index / max(total_count - 1, 1)),
        center_utility=1.0 - clamp(center_distance),
        is_main=is_main,
        original_index=original_index,
    )


def generate_scene(rng: random.Random) -> list[Candidate]:
    total_count = rng.randint(2, 6)
    main_area = rng.uniform(0.16, 0.48)
    indices = list(range(total_count))
    rng.shuffle(indices)
    candidates = [
        make_candidate(
            rng,
            area=main_area,
            original_index=indices[0],
            total_count=total_count,
            is_main=True,
        )
    ]
    for index in indices[1:]:
        candidates.append(
            make_candidate(
                rng,
                area=main_area * rng.uniform(0.08, 0.95),
                original_index=index,
                total_count=total_count,
                is_main=False,
            )
        )
    return candidates


def evaluate(
    scenes: list[list[Candidate]],
    selector: Callable[[list[Candidate]], Optional[Candidate]],
) -> dict[str, int]:
    result = {"correct": 0, "smaller_selected": 0, "abstained": 0}
    for candidates in scenes:
        selected = selector(candidates)
        if selected is None:
            result["abstained"] += 1
        elif selected.is_main:
            result["correct"] += 1
        else:
            result["smaller_selected"] += 1
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=7_600)
    parser.add_argument("--scenes", type=int, default=20_000)
    parser.add_argument("--assert-improvement", action="store_true")
    arguments = parser.parse_args()

    rng = random.Random(arguments.seed)
    scenes = [generate_scene(rng) for _ in range(arguments.scenes)]
    previous = evaluate(scenes, select_previous)
    area_priority = evaluate(scenes, select_area_priority)

    print(f"seed={arguments.seed} scenes={arguments.scenes}")
    for name, result in (("previous", previous), ("area_priority", area_priority)):
        total = sum(result.values())
        correct_rate = result["correct"] / total
        smaller_rate = result["smaller_selected"] / total
        print(
            f"{name}: correct={result['correct']} ({correct_rate:.2%}) "
            f"smaller_selected={result['smaller_selected']} ({smaller_rate:.2%}) "
            f"abstained={result['abstained']}"
        )

    if arguments.assert_improvement:
        assert area_priority["smaller_selected"] == 0
        assert area_priority["correct"] / arguments.scenes >= 0.60
        assert area_priority["correct"] > previous["correct"]
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
