# Guide to writing plans

Written for **AI agents** — **mandatory** when an agent drafts, reviews, or implements from **`docs/plans/*`**.

Plan markdown lives in **`docs/plans/`**; completed work archives under **`docs/plans/done/`**.

This repo is small. For the full checklist, emoji legend, edit-syntax contract, and Vala coding rules, treat the OLLMchat copy as canonical:

- ℹ️ `/home/alan/gitlive/OLLMchat/docs/guide-to-writing-plans.md`
- ℹ️ `/home/alan/gitlive/OLLMchat/docs/coding-standards.md` (via **`coding-standards-router.md`** when implementing Vala)

## Checklist for plans (short)

- **Single location per topic** — **Remove** / **Replace with** / **Add** fences live in the section that discusses that work.
- **Edit syntax** — actionable fences are **Remove** / **Replace with** / **Add** only; **Keep** is context, never an edit.
- **No orphan code** — no implementation fences in **Purpose** or **LLM notes**.
- **Do not invent helpers** unless the user or plan names them.

## Status markers

| Marker | Meaning |
| ------ | ------- |
| **✅** | User confirmed done |
| **✔️** | Agent implemented — not user-approved yet |
| **⏳** | Not done (backlog) |
| **🔷** | User-specified requirement |
| **💩** | LLM suggestion — confirm before build |
| **ℹ️** | Pointer / reference |
| **🚫** | Out of scope / do not implement |

Pair every open task: **`🔷` `⏳`** or **`💩` `⏳`**. Do **not** promote **✔️ → ✅**.

## Plan shape

1. **Title** — `# N.N Title`
2. **`Status:`**
3. **Pointer** to this guide
4. **`## Purpose`** — nested bullets (**🔷** / **⏳** / **ℹ️**)
5. **Topic / phase sections** — discussion + inline code proposals
6. Optional short **`## LLM notes`** / implementer guardrails at the bottom

## Implementation workflow

1. Implement only what was approved.
2. If blocked: revert speculative code, update the plan, ask before continuing.
3. Mark agent work **✔️**, not **✅**.
