"""Measure the requested Study 1 human baseline; never read model responses."""
from pathlib import Path
import hashlib
import json
import re
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT.parents[2]
SOURCE = DATA / 'aita_unified_153k.parquet'
HUMAN_COLUMNS = [f'comment_{i}_body' for i in (1, 2, 3)]
# The same separators are used by the browser and PostgreSQL counter.
SEPARATORS = re.compile(r'[\x09-\x0d\x1c-\x20\x85\xa0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+')

def count_words(value):
    return len([word for word in SEPARATORS.split(value) if word])

def main():
    ids = set()
    totals = {col: dict(comments=0, words=0, missing=0, removed=0) for col in HUMAN_COLUMNS}
    source_preview = []
    rows = 0
    for batch in pq.ParquetFile(SOURCE).iter_batches(columns=['submission_id', *HUMAN_COLUMNS], batch_size=10000):
        for row in batch.to_pylist():
            rows += 1
            assert row['submission_id'] not in ids, 'Duplicate submission ID'
            ids.add(row['submission_id'])
            preview_counts = {}
            for col in HUMAN_COLUMNS:
                text = row[col]
                if not isinstance(text, str) or not text.strip():
                    totals[col]['missing'] += 1
                    continue
                if text.strip().lower() in ('[deleted]', '[removed]'):
                    totals[col]['removed'] += 1
                    continue
                words = count_words(text)
                totals[col]['comments'] += 1
                totals[col]['words'] += words
                preview_counts[col] = words
            if len(source_preview) < 3:
                source_preview.append(dict(submission_id=row['submission_id'], word_counts=preview_counts))
    comments = sum(v['comments'] for v in totals.values())
    words = sum(v['words'] for v in totals.values())
    assert rows == 153267 and comments == 459801
    assert all(v['missing'] == v['removed'] == 0 for v in totals.values())
    with SOURCE.open('rb') as stream:
        source_hash = hashlib.sha256()
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            source_hash.update(chunk)
        source_sha256 = source_hash.hexdigest()
    evidence = dict(
        source=str(SOURCE.relative_to(DATA)), source_sha256=source_sha256,
        scope='All Study 1 human top-3 comments', columns=HUMAN_COLUMNS,
        post_count=rows, comment_count=comments, total_words=words,
        mean_words=words/comments, word_limit=int(words/comments + 0.5),
        rounding='nearest whole word (half up)',
        count_version='whitespace-total-v1',
        definition='Whitespace-separated words in the entire original human comment, including any verdict label. Hyphenated words and contractions without spaces count as one.',
        exclusions='Only missing/blank and exact [deleted]/[removed] placeholders; none were present. No model columns, trimming of tails, or length-based exclusions.',
        per_column=totals, source_preview=source_preview,
    )
    (ROOT / 'private100-word-limit-evidence.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ('post_count','comment_count','total_words','mean_words','word_limit')}, indent=2))

if __name__ == '__main__':
    main()
