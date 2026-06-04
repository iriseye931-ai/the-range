---
name: dual-think
description: Co-reasoning between Atlas (Claude) and Hermes (Qwen3.6 local). Use when facing architecture decisions, security-sensitive choices, or irreversible changes where a second opinion from a different model matters. NOT for routine code review, debugging, or anything with a clear correctness criterion.
---

# Dual-Think — Atlas + Hermes Co-Reasoning

Two different models, different architectures, different blind spots. One paragraph each. Iris decides.

## When to invoke

- Architecture decisions with no clear right answer
- Security-sensitive choices where a blind spot is costly
- About to ship something irreversible (migration, protocol change, config overhaul)
- Cross-domain judgment calls at the intersection of two areas

**Do NOT invoke for:** code review, debugging, routine tasks, anything with a clear correctness criterion.

## Protocol

1. **Atlas formulates his take first** — one paragraph, what you'd do and why, and what you're uncertain about
2. **Send the problem to Hermes** — same problem statement, no anchoring with Atlas's take
3. **Wait up to 120 seconds** for Hermes to respond via direct API
4. **Present both takes side-by-side** to Iris — no voting, no averaging, Iris decides

## How to run it

When the user invokes `/dual-think` or you decide co-thinking is warranted:

**Step 1 — Write Atlas's take:**

Before contacting Hermes, write your own paragraph:
```
**Atlas:** [One paragraph: what I'd do, the key tradeoff I see, and what I'm most uncertain about.]
```

**Step 2 — Send to Hermes via direct API:**

Use the 35B model directly — faster and more reliable than `hermes --cli` (1s vs 90s):

```bash
rtk proxy curl -s --max-time 120 http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer local" \
  -d "{\"model\":\"/Users/iris/.mlx/models/Qwen3.6-35B-A3B-OptiQ-4bit\",\"messages\":[{\"role\":\"user\",\"content\":\"DUAL-THINK REQUEST from Atlas:\\n\\nProblem: [concise self-contained problem statement — do not include Atlas's take]\\n\\nRespond with ONE paragraph starting with **Hermes:** — your recommendation, the key tradeoff you see, and what you would flag as a blind spot. Be direct, disagree with the obvious answer if you have reason to.\"}],\"max_tokens\":400,\"temperature\":0.6}" 2>&1 \
  | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d['choices'][0]['message'].get('content','NO CONTENT'))"
```

If the command times out or errors, note it and proceed with Atlas's take alone.

**Step 3 — Present to Iris:**

```
**DUAL-THINK** — [problem title]

**Atlas (Claude Sonnet):** [one paragraph]

**Hermes (Qwen3.6):** [one paragraph, or "timed out — proceeding with Atlas's take"]

*Iris decides.*
```

## Key constraints

- One paragraph max per model. If it can't fit in a paragraph, decompose the problem first.
- 120-second hard timeout on Hermes API call. Never block on it.
- No synthesis, no voting, no "we both agree." Present the views, Iris chooses.
- Send the raw problem to Hermes — don't prime it with Atlas's view.
- Hermes's disagreement is valuable. Don't smooth it over.
