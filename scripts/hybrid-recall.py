#!/usr/bin/env python3
"""
hybrid-recall.py — Hybrid memory search for the iriseye mesh.

Combines:
  1. BM25 keyword search over OpenViking memory files (exact term matching)
  2. Semantic vector search via OpenViking API
  3. RRF (Reciprocal Rank Fusion) to merge results

Usage:
  python3 hybrid-recall.py "your query" [--limit 10] [--rrf-k 60]

Also importable:
  from hybrid_recall import hybrid_recall
  results = hybrid_recall("your query", limit=10)
"""

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

from rank_bm25 import BM25Okapi

# ── Config ────────────────────────────────────────────────────────────────────
OV_BASE    = os.getenv("OV_BASE_URL", "http://localhost:1933")
OV_API_KEY = os.getenv("OV_API_KEY", "REDACTED-ROTATED-KEY")
OV_ACCOUNT = os.getenv("OV_ACCOUNT", "teamirs")
OV_USER    = os.getenv("OV_USER", "iris")
OV_DATA    = Path(os.getenv("OV_DATA", str(Path.home() / ".openviking/data/viking")))
RRF_K      = 60  # standard RRF constant — higher = less weight to top ranks


def tokenize(text: str) -> list[str]:
    """Simple whitespace + punctuation tokenizer."""
    return re.findall(r"\b\w+\b", text.lower())


def load_memory_corpus() -> tuple[list[str], list[str], list[str]]:
    """
    Load all markdown memory files from OpenViking data dir.
    Returns (doc_ids, raw_texts, tokenized_corpus).
    """
    ids, texts, tokenized = [], [], []
    for md in OV_DATA.rglob("*.md"):
        try:
            text = md.read_text(errors="replace")
            if text.strip():
                ids.append(str(md.relative_to(OV_DATA)))
                texts.append(text)
                tokenized.append(tokenize(text))
        except Exception:
            continue
    return ids, texts, tokenized


def bm25_search(query: str, limit: int) -> list[tuple[str, str, float]]:
    """BM25 search over memory files. Returns [(id, text_snippet, score)]."""
    ids, texts, tokenized = load_memory_corpus()
    if not tokenized:
        return []

    bm25 = BM25Okapi(tokenized)
    q_tokens = tokenize(query)
    scores = bm25.get_scores(q_tokens)

    ranked = sorted(zip(ids, texts, scores), key=lambda x: x[2], reverse=True)
    # filter zero-score results
    ranked = [(i, t, s) for i, t, s in ranked if s > 0]
    return ranked[:limit]


def semantic_search(query: str, limit: int) -> list[dict]:
    """Semantic vector search via OpenViking API. Returns list of result dicts."""
    payload = json.dumps({
        "query": query,
        "limit": limit,
        "score_threshold": 0.3
    }).encode()

    req = urllib.request.Request(
        f"{OV_BASE}/api/v1/search/find",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "X-API-Key": OV_API_KEY,
            "X-OpenViking-Account": OV_ACCOUNT,
            "X-OpenViking-User": OV_USER
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            result = data.get("result", data)
            if isinstance(result, dict):
                return result.get("memories", []) + result.get("resources", [])
            return result if isinstance(result, list) else []
    except Exception as e:
        print(f"[hybrid-recall] semantic search error: {e}", file=sys.stderr)
        return []


def rrf_fuse(
    bm25_results: list[tuple[str, str, float]],
    semantic_results: list[dict],
    limit: int,
    k: int = RRF_K
) -> list[dict]:
    """
    Reciprocal Rank Fusion.
    Score = sum(1 / (k + rank)) across result lists.
    """
    scores: dict[str, float] = {}
    docs: dict[str, dict] = {}

    # BM25 contributions
    for rank, (doc_id, text, bm25_score) in enumerate(bm25_results):
        rrf_score = 1.0 / (k + rank + 1)
        scores[doc_id] = scores.get(doc_id, 0) + rrf_score
        if doc_id not in docs:
            snippet = text[:400].strip().replace("\n", " ")
            docs[doc_id] = {
                "id": doc_id,
                "source": "bm25",
                "snippet": snippet,
                "bm25_score": round(bm25_score, 4)
            }

    # Semantic contributions
    for rank, result in enumerate(semantic_results):
        # OpenViking returns various shapes — normalize
        doc_id = (
            result.get("uri") or
            result.get("id") or
            result.get("resource_uri") or
            f"semantic-{rank}"
        )
        content = (
            result.get("abstract") or
            result.get("content") or
            result.get("text") or
            result.get("body") or
            str(result)
        )
        rrf_score = 1.0 / (k + rank + 1)
        scores[doc_id] = scores.get(doc_id, 0) + rrf_score
        if doc_id not in docs:
            snippet = str(content)[:400].strip().replace("\n", " ")
            docs[doc_id] = {
                "id": doc_id,
                "source": "semantic",
                "snippet": snippet,
                "semantic_score": round(result.get("score", 0), 4)
            }
        else:
            docs[doc_id]["source"] = "hybrid"
            docs[doc_id]["semantic_score"] = round(result.get("score", 0), 4)

    # Sort by RRF score
    ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    output = []
    for doc_id, rrf_score in ranked[:limit]:
        entry = docs[doc_id].copy()
        entry["rrf_score"] = round(rrf_score, 6)
        output.append(entry)

    return output


def hybrid_recall(query: str, limit: int = 10, rrf_k: int = RRF_K) -> list[dict]:
    """Main entry point. Run hybrid search and return fused results."""
    bm25 = bm25_search(query, limit * 2)
    semantic = semantic_search(query, limit * 2)
    # extract memories list from OpenViking response shape
    if isinstance(semantic, dict):
        semantic = semantic.get("memories", []) + semantic.get("resources", [])
    return rrf_fuse(bm25, semantic, limit, rrf_k)


# ── CLI ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Hybrid memory search (BM25 + semantic + RRF)")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--rrf-k", type=int, default=RRF_K)
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    results = hybrid_recall(args.query, args.limit, args.rrf_k)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"\nHybrid recall: '{args.query}' — {len(results)} results\n")
        for i, r in enumerate(results, 1):
            source_tag = {"hybrid": "[BM25+SEM]", "bm25": "[BM25]", "semantic": "[SEM]"}.get(r["source"], "")
            print(f"{i}. {source_tag} {r['id']}")
            print(f"   RRF: {r['rrf_score']}  |  {r['snippet'][:120]}...")
            print()
