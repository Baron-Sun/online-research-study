#!/usr/bin/env python3
"""Prepare Supabase import files for the full153k v1 study launch."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = (
    ROOT
    / "unified_dataset"
    / "controversy_index_analysis"
    / "full153k_experiment_selection_v1"
)
DEFAULT_PAIRING_SOURCE = DEFAULT_SOURCE / "dilemma_pairing_materials_v1"
DEFAULT_OUTPUT = ROOT / "supabase_import" / "full153k_v1"

RATING_COLUMNS = [
    "task_id",
    "submission_id",
    "sampling_level",
    "sampling_level_label",
    "rank_within_level",
    "reddit_score",
    "dominant_verdict",
    "top_comment_verdicts",
    "title",
    "body",
    "post_text",
    "month",
]

ADVICE_STIMULI_COLUMNS = [
    "stimulus_id",
    "exposure_title",
    "exposure_body",
    "friend_title",
    "friend_body",
    "moral_theme_metadata",
    "human_comments",
    "llm_comments",
    "active",
]

ADVICE_SLOTS_COLUMNS = [
    "slot_id",
    "stimulus_id",
    "condition",
    "slot_index",
    "status",
]

RATING_ASSIGNMENT_SLOT_COLUMNS = [
    "slot_id",
    "slot_index",
    "pattern",
    "post_ids",
    "metadata",
    "status",
]

HUMAN_COMMENT_COUNT = 5
LLM_COMMENT_COUNT = 3
RATING_SLOT_COUNT = 180
RATING_POSTS_PER_SLOT = 5
RATING_REPETITIONS_PER_POST = 3
RATING_RANDOM_SEED = 0
RATING_BUCKETS = ["all_same", "2_of_3", "all_different"]
RATING_PATTERNS = {
    "A": ["all_same", "2_of_3", "2_of_3", "all_different", "all_different"],
    "B": ["all_same", "all_same", "2_of_3", "all_different", "all_different"],
    "C": ["all_same", "all_same", "2_of_3", "2_of_3", "all_different"],
}


def clean_text(value: object) -> str:
    if not isinstance(value, str):
        return ""
    return value.replace("\r\n", "\n").replace("\r", "\n").strip()


def read_frame(path: Path) -> pd.DataFrame:
    if path.suffix == ".parquet":
        return pd.read_parquet(path)
    return pd.read_csv(path)


def json_cell(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def postgres_text_array(values: list[str]) -> str:
    escaped = []
    for value in values:
        text = str(value)
        if any(char in text for char in [",", '"', "\\", "{", "}", " "]):
            text = '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'
        escaped.append(text)
    return "{" + ",".join(escaped) + "}"


def write_csv(path: Path, rows: list[dict[str, object]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def top_comment_verdicts(row: pd.Series) -> str:
    verdicts = [
        row.get("top3_comment_1_verdict", ""),
        row.get("top3_comment_2_verdict", ""),
        row.get("top3_comment_3_verdict", ""),
    ]
    return ",".join(str(verdict).strip() for verdict in verdicts if str(verdict).strip())


def build_rating_rows(sample: pd.DataFrame) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for row in sample.sort_values(
        ["assigned_topic_id", "top3_agreement", "sample_cell_rank", "submission_id"]
    ).itertuples(index=False):
        body = clean_text(row.body)
        title = clean_text(row.title)
        rows.append(
            {
                "task_id": str(row.submission_id),
                "submission_id": str(row.submission_id),
                "sampling_level": str(row.top3_agreement),
                "sampling_level_label": str(row.assigned_topic_name),
                "rank_within_level": int(row.sample_cell_rank),
                "reddit_score": int(row.score),
                "dominant_verdict": clean_text(row.verdict),
                "top_comment_verdicts": top_comment_verdicts(pd.Series(row._asdict())),
                "title": title,
                "body": body,
                "post_text": f"{title}\n\n{body}",
                "month": clean_text(row.month),
            }
        )
    return rows


def build_rating_assignment_slots(
    rating_rows: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Build 180 fixed five-post rating assignments with exact cell balance."""
    import random
    from collections import Counter

    rng = random.Random(RATING_RANDOM_SEED)
    topics = sorted({str(row["sampling_level_label"]) for row in rating_rows})
    posts_by_cell: dict[tuple[str, str], list[dict[str, object]]] = {}
    for row in rating_rows:
        key = (str(row["sampling_level_label"]), str(row["sampling_level"]))
        posts_by_cell.setdefault(key, []).append(row)

    expected_cells = {
        (topic, bucket)
        for topic in topics
        for bucket in RATING_BUCKETS
    }
    if set(posts_by_cell) != expected_cells:
        missing = sorted(expected_cells - set(posts_by_cell))
        extra = sorted(set(posts_by_cell) - expected_cells)
        raise RuntimeError(f"Unexpected rating cells; missing={missing}, extra={extra}")

    for key, posts in posts_by_cell.items():
        if len(posts) != 10:
            raise RuntimeError(f"{key} has {len(posts)} posts; expected 10")
        posts.sort(key=lambda row: (int(row["rank_within_level"]), str(row["task_id"])))

    remaining = {
        (topic, bucket): len(posts_by_cell[(topic, bucket)]) * RATING_REPETITIONS_PER_POST
        for topic in topics
        for bucket in RATING_BUCKETS
    }
    pattern_sequence = [
        pattern
        for _ in range(RATING_SLOT_COUNT // len(RATING_PATTERNS))
        for pattern in ["A", "B", "C"]
    ]
    if len(pattern_sequence) != RATING_SLOT_COUNT:
        raise RuntimeError("Rating pattern sequence length is wrong")

    cell_slots: list[dict[str, object]] = []
    for slot_index, pattern in enumerate(pattern_sequence, start=1):
        bucket_items = list(RATING_PATTERNS[pattern])
        rng.shuffle(bucket_items)
        used_topics: set[str] = set()
        cells: list[tuple[str, str]] = []

        for bucket in bucket_items:
            candidates = [
                topic
                for topic in topics
                if topic not in used_topics and remaining[(topic, bucket)] > 0
            ]
            if not candidates:
                raise RuntimeError(f"Could not fill slot {slot_index} for bucket {bucket}")

            max_bucket_remaining = max(remaining[(topic, bucket)] for topic in candidates)
            candidates = [
                topic for topic in candidates if remaining[(topic, bucket)] == max_bucket_remaining
            ]
            max_topic_remaining = max(
                sum(remaining[(topic, other_bucket)] for other_bucket in RATING_BUCKETS)
                for topic in candidates
            )
            candidates = [
                topic
                for topic in candidates
                if sum(remaining[(topic, other_bucket)] for other_bucket in RATING_BUCKETS)
                == max_topic_remaining
            ]

            topic = rng.choice(candidates)
            remaining[(topic, bucket)] -= 1
            used_topics.add(topic)
            cells.append((topic, bucket))

        cell_slots.append(
            {
                "slot_index": slot_index,
                "pattern": pattern,
                "cells": cells,
            }
        )

    leftover = {key: count for key, count in remaining.items() if count != 0}
    if leftover:
        raise RuntimeError(f"Rating cell assignment did not exhaust all cells: {leftover}")

    post_queues: dict[tuple[str, str], list[dict[str, object]]] = {}
    for key, posts in posts_by_cell.items():
        queue = [
            post
            for post in posts
            for _ in range(RATING_REPETITIONS_PER_POST)
        ]
        rng.shuffle(queue)
        post_queues[key] = queue

    rows: list[dict[str, object]] = []
    for slot in cell_slots:
        assignments: list[dict[str, str]] = []
        for topic, bucket in slot["cells"]:
            post = post_queues[(topic, bucket)].pop()
            assignments.append(
                {
                    "postId": str(post["task_id"]),
                    "topic": topic,
                    "controversyBucket": bucket,
                }
            )

        post_ids = [item["postId"] for item in assignments]
        metadata = {
            "sourceDataset": "full153k_experiment_selection_v1",
            "design": "rating_fixed_slots_180x5_v1",
            "slotIndex": int(slot["slot_index"]),
            "pattern": str(slot["pattern"]),
            "postsPerParticipant": RATING_POSTS_PER_SLOT,
            "postRepetitions": RATING_REPETITIONS_PER_POST,
            "assignments": assignments,
        }
        rows.append(
            {
                "slot_id": f"rating_full153k_v1_slot_{int(slot['slot_index']):03d}",
                "slot_index": int(slot["slot_index"]),
                "pattern": str(slot["pattern"]),
                "post_ids": postgres_text_array(post_ids),
                "metadata": json_cell(metadata),
                "status": "open",
            }
        )

    for key, queue in post_queues.items():
        if queue:
            raise RuntimeError(f"{key} still has {len(queue)} unassigned post tokens")

    pattern_counts = Counter(row["pattern"] for row in rows)
    if pattern_counts != {"A": 60, "B": 60, "C": 60}:
        raise RuntimeError(f"Unexpected pattern counts: {pattern_counts}")

    return rows


def comments_by_submission(
    comments: pd.DataFrame,
    body_column: str,
    order_columns: list[str],
    count: int,
) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    sorted_comments = comments.sort_values(order_columns)
    for submission_id, group in sorted_comments.groupby("submission_id", sort=False):
        bodies = [clean_text(value) for value in group[body_column].tolist()]
        bodies = [body for body in bodies if body]
        out[str(submission_id)] = bodies[:count]
    return out


def build_advice_rows(
    sample: pd.DataFrame,
    orders: pd.DataFrame,
    human_comments: pd.DataFrame,
    llm_comments: pd.DataFrame,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    sample_by_id = {
        str(row.submission_id): row
        for row in sample.itertuples(index=False)
    }
    human_by_id = comments_by_submission(
        human_comments,
        body_column="body",
        order_columns=["submission_id", "comment_selection_rank", "score", "comment_id"],
        count=HUMAN_COMMENT_COUNT,
    )
    llm_source_order = {"DeepSeek": 1, "GPT": 2, "Llama": 3}
    llm_comments = llm_comments.copy()
    llm_comments["_source_order"] = llm_comments["ai_source"].map(llm_source_order).fillna(99)
    llm_by_id = comments_by_submission(
        llm_comments,
        body_column="comment_body",
        order_columns=["submission_id", "_source_order", "ai_source_field"],
        count=LLM_COMMENT_COUNT,
    )

    stimuli: list[dict[str, object]] = []
    slots: list[dict[str, object]] = []

    for order in orders.sort_values(["pair_id", "order_version"]).itertuples(index=False):
        exposure_id = str(order.exposure_submission_id)
        target_id = str(order.target_submission_id)
        exposure = sample_by_id[exposure_id]
        target = sample_by_id[target_id]
        human_feed = human_by_id.get(exposure_id, [])
        llm_feed = llm_by_id.get(exposure_id, [])
        stimulus_id = f"full153k_v1_{order.pair_id}_{order.order_version}"
        metadata = {
            "sourceDataset": "full153k_experiment_selection_v1",
            "pairId": str(order.pair_id),
            "orderVersion": str(order.order_version),
            "exposureSubmissionId": exposure_id,
            "targetSubmissionId": target_id,
            "assignedTopicId": int(order.assigned_topic_id),
            "assignedTopicName": str(order.assigned_topic_name),
            "top3Agreement": str(order.top3_agreement),
            "humanCommentCount": HUMAN_COMMENT_COUNT,
            "llmCommentCount": LLM_COMMENT_COUNT,
        }

        stimuli.append(
            {
                "stimulus_id": stimulus_id,
                "exposure_title": clean_text(exposure.title),
                "exposure_body": clean_text(exposure.body),
                "friend_title": clean_text(target.title),
                "friend_body": clean_text(target.body),
                "moral_theme_metadata": json_cell(metadata),
                "human_comments": json_cell(human_feed),
                "llm_comments": json_cell(llm_feed),
                "active": "true",
            }
        )

        for condition in ["human_comments", "llm_comments"]:
            slot_id = f"{stimulus_id}_{condition}"
            slots.append(
                {
                    "slot_id": slot_id,
                    "stimulus_id": stimulus_id,
                    "condition": condition,
                    "slot_index": 1,
                    "status": "open",
                }
            )

    return stimuli, slots


def validate(
    sample: pd.DataFrame,
    orders: pd.DataFrame,
    rating_rows: list[dict[str, object]],
    rating_slots: list[dict[str, object]],
    stimuli: list[dict[str, object]],
    slots: list[dict[str, object]],
) -> None:
    from collections import Counter

    sample_ids = set(sample["submission_id"].astype(str))
    exposure_ids = set(orders["exposure_submission_id"].astype(str))
    target_ids = set(orders["target_submission_id"].astype(str))

    if len(rating_rows) != 300:
        raise RuntimeError(f"Expected 300 rating posts, found {len(rating_rows)}")
    if len({row["submission_id"] for row in rating_rows}) != 300:
        raise RuntimeError("Rating submission IDs are not unique")
    if any(not row["title"] or not row["body"] for row in rating_rows):
        raise RuntimeError("Rating rows contain empty title/body")
    if len(rating_slots) != RATING_SLOT_COUNT:
        raise RuntimeError(f"Expected {RATING_SLOT_COUNT} rating slots, found {len(rating_slots)}")
    if len(stimuli) != 300:
        raise RuntimeError(f"Expected 300 advice stimuli, found {len(stimuli)}")
    if len(slots) != 600:
        raise RuntimeError(f"Expected 600 advice slots, found {len(slots)}")
    if exposure_ids - sample_ids:
        raise RuntimeError(f"Missing exposure IDs: {sorted(exposure_ids - sample_ids)[:5]}")
    if target_ids - sample_ids:
        raise RuntimeError(f"Missing target IDs: {sorted(target_ids - sample_ids)[:5]}")

    for row in stimuli:
        human = json.loads(str(row["human_comments"]))
        llm = json.loads(str(row["llm_comments"]))
        if len(human) != HUMAN_COMMENT_COUNT:
            raise RuntimeError(f"{row['stimulus_id']} has {len(human)} human comments")
        if len(llm) != LLM_COMMENT_COUNT:
            raise RuntimeError(f"{row['stimulus_id']} has {len(llm)} LLM comments")
        if any(not isinstance(text, str) or not text.strip() for text in human + llm):
            raise RuntimeError(f"{row['stimulus_id']} has blank comment text")

    rating_by_id = {str(row["task_id"]): row for row in rating_rows}
    post_counts: Counter[str] = Counter()
    topic_counts: Counter[str] = Counter()
    bucket_counts: Counter[str] = Counter()
    cell_counts: Counter[tuple[str, str]] = Counter()
    pattern_counts: Counter[str] = Counter()

    for row in rating_slots:
        metadata = json.loads(str(row["metadata"]))
        assignments = metadata["assignments"]
        if len(assignments) != RATING_POSTS_PER_SLOT:
            raise RuntimeError(f"{row['slot_id']} does not have 5 posts")
        topics = [item["topic"] for item in assignments]
        buckets = [item["controversyBucket"] for item in assignments]
        post_ids = [item["postId"] for item in assignments]
        if len(set(topics)) != RATING_POSTS_PER_SLOT:
            raise RuntimeError(f"{row['slot_id']} repeats a topic")
        if len(set(post_ids)) != RATING_POSTS_PER_SLOT:
            raise RuntimeError(f"{row['slot_id']} repeats a post")
        if Counter(buckets) != Counter(RATING_PATTERNS[str(row["pattern"])]):
            raise RuntimeError(f"{row['slot_id']} does not match pattern {row['pattern']}")

        pattern_counts[str(row["pattern"])] += 1
        for item in assignments:
            post_id = str(item["postId"])
            if post_id not in rating_by_id:
                raise RuntimeError(f"{row['slot_id']} references unknown post {post_id}")
            source = rating_by_id[post_id]
            if item["topic"] != source["sampling_level_label"]:
                raise RuntimeError(f"{row['slot_id']} topic mismatch for {post_id}")
            if item["controversyBucket"] != source["sampling_level"]:
                raise RuntimeError(f"{row['slot_id']} bucket mismatch for {post_id}")
            post_counts[post_id] += 1
            topic_counts[str(item["topic"])] += 1
            bucket_counts[str(item["controversyBucket"])] += 1
            cell_counts[(str(item["topic"]), str(item["controversyBucket"]))] += 1

    if pattern_counts != {"A": 60, "B": 60, "C": 60}:
        raise RuntimeError(f"Rating patterns are not balanced: {pattern_counts}")
    if set(post_counts.values()) != {RATING_REPETITIONS_PER_POST}:
        raise RuntimeError("Not every rating post appears exactly 3 times")
    if set(topic_counts.values()) != {90}:
        raise RuntimeError(f"Rating topics are not 90 each: {topic_counts}")
    if bucket_counts != {"all_same": 300, "2_of_3": 300, "all_different": 300}:
        raise RuntimeError(f"Rating buckets are not balanced: {bucket_counts}")
    if set(cell_counts.values()) != {30}:
        raise RuntimeError("Not every topic x controversy cell appears exactly 30 times")


def write_reset_sql(output_dir: Path) -> None:
    sql = """-- Backup existing live tables, then clear them for the full153k v1 import.
-- Run this before importing the generated CSV files into Supabase.

create schema if not exists researcher_backups;

create table researcher_backups.rating_posts_before_full153k_v1 as
  select * from public.rating_posts;
create table researcher_backups.rating_assignments_before_full153k_v1 as
  select * from public.rating_assignments;
create table researcher_backups.rating_submissions_before_full153k_v1 as
  select * from public.rating_submissions;
create table researcher_backups.rating_assignment_slots_before_full153k_v1 as
  select * from public.rating_assignment_slots;

create table researcher_backups.advice_stimuli_before_full153k_v1 as
  select * from public.advice_stimuli;
create table researcher_backups.advice_slots_before_full153k_v1 as
  select * from public.advice_slots;
create table researcher_backups.advice_assignments_before_full153k_v1 as
  select * from public.advice_assignments;
create table researcher_backups.advice_submissions_before_full153k_v1 as
  select * from public.advice_submissions;

truncate table public.rating_submissions restart identity cascade;
truncate table public.rating_assignments restart identity cascade;
truncate table public.rating_assignment_slots restart identity cascade;
truncate table public.rating_posts restart identity cascade;

truncate table public.advice_submissions restart identity cascade;
truncate table public.advice_assignments restart identity cascade;
truncate table public.advice_slots restart identity cascade;
truncate table public.advice_stimuli restart identity cascade;
"""
    (output_dir / "reset_live_tables_before_full153k_v1.sql").write_text(sql, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--pairing-dir", type=Path, default=DEFAULT_PAIRING_SOURCE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    sample = read_frame(args.source_dir / "draft_sample_300_full153k_v1.parquet")
    human_comments = read_frame(args.source_dir / "selected_comments_full153k_v1.parquet")
    orders = read_frame(args.pairing_dir / "dilemma_pair_orders_300_v1.parquet")
    llm_comments = read_frame(args.pairing_dir / "ai_comments_for_sample_v1.parquet")

    for frame in [sample, human_comments, orders, llm_comments]:
        if "submission_id" in frame.columns:
            frame["submission_id"] = frame["submission_id"].astype(str)
    orders["exposure_submission_id"] = orders["exposure_submission_id"].astype(str)
    orders["target_submission_id"] = orders["target_submission_id"].astype(str)

    rating_rows = build_rating_rows(sample)
    rating_slots = build_rating_assignment_slots(rating_rows)
    stimuli, slots = build_advice_rows(sample, orders, human_comments, llm_comments)
    validate(sample, orders, rating_rows, rating_slots, stimuli, slots)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(
        args.output_dir / "rating_posts_import_full153k_v1.csv",
        rating_rows,
        RATING_COLUMNS,
    )
    write_csv(
        args.output_dir / "rating_assignment_slots_import_full153k_v1.csv",
        rating_slots,
        RATING_ASSIGNMENT_SLOT_COLUMNS,
    )
    write_csv(
        args.output_dir / "advice_stimuli_import_full153k_v1.csv",
        stimuli,
        ADVICE_STIMULI_COLUMNS,
    )
    write_csv(
        args.output_dir / "advice_slots_import_full153k_v1.csv",
        slots,
        ADVICE_SLOTS_COLUMNS,
    )
    write_reset_sql(args.output_dir)

    manifest = {
        "sourceDir": str(args.source_dir),
        "pairingDir": str(args.pairing_dir),
        "ratingPosts": len(rating_rows),
        "ratingAssignmentSlots": len(rating_slots),
        "ratingPostsPerSlot": RATING_POSTS_PER_SLOT,
        "ratingRepetitionsPerPost": RATING_REPETITIONS_PER_POST,
        "adviceStimuli": len(stimuli),
        "adviceSlots": len(slots),
        "humanCommentsPerHumanSlot": HUMAN_COMMENT_COUNT,
        "llmCommentsPerLlmSlot": LLM_COMMENT_COUNT,
        "outputFiles": [
            "rating_posts_import_full153k_v1.csv",
            "rating_assignment_slots_import_full153k_v1.csv",
            "advice_stimuli_import_full153k_v1.csv",
            "advice_slots_import_full153k_v1.csv",
            "reset_live_tables_before_full153k_v1.sql",
        ],
    }
    (args.output_dir / "manifest_full153k_v1.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
