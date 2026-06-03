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

HUMAN_COMMENT_COUNT = 5
LLM_COMMENT_COUNT = 3


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
    stimuli: list[dict[str, object]],
    slots: list[dict[str, object]],
) -> None:
    sample_ids = set(sample["submission_id"].astype(str))
    exposure_ids = set(orders["exposure_submission_id"].astype(str))
    target_ids = set(orders["target_submission_id"].astype(str))

    if len(rating_rows) != 300:
        raise RuntimeError(f"Expected 300 rating posts, found {len(rating_rows)}")
    if len({row["submission_id"] for row in rating_rows}) != 300:
        raise RuntimeError("Rating submission IDs are not unique")
    if any(not row["title"] or not row["body"] for row in rating_rows):
        raise RuntimeError("Rating rows contain empty title/body")
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
    stimuli, slots = build_advice_rows(sample, orders, human_comments, llm_comments)
    validate(sample, orders, rating_rows, stimuli, slots)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(
        args.output_dir / "rating_posts_import_full153k_v1.csv",
        rating_rows,
        RATING_COLUMNS,
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
        "adviceStimuli": len(stimuli),
        "adviceSlots": len(slots),
        "humanCommentsPerHumanSlot": HUMAN_COMMENT_COUNT,
        "llmCommentsPerLlmSlot": LLM_COMMENT_COUNT,
        "outputFiles": [
            "rating_posts_import_full153k_v1.csv",
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
