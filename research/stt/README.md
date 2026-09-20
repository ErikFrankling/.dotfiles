# Speech transcription research

Start here when revisiting model selection. Latest completed study:
**[2026-09-19](2026-09-19/QUALITY_RANKING.md)**. This archive preserves the
evidence behind the decision, rather than treating the chosen model as a
permanent winner.

Deployment follow-up: [2026-09-20 reliability, chunking and mobile UI](2026-09-20/DICTATION_REPAIR.md).

## Decision and priorities

Erik reviewed the side-by-side outputs and considers VibeVoice effectively
comparable in quality to the other strong candidates on this recording.
**Deploy VibeVoice locally for the final pass**, with a separate real-time
recognizer for provisional feedback. This is a practical choice from the
observed outputs, not proof of universal parity with frontier cloud models.

Priorities, in order:

1. Faithful, readable dictation: preserve intent, negation, technical content,
   self-corrections, and questions. Removing “um” and accidental repeats is fine.
2. Accurate project vocabulary, including uncommon function/variable names,
   and useful audio-plus-project-context conditioning.
3. Prefer local inference and GPU residency. Speed and resource use break
   quality ties; a genuinely better-quality candidate merits investigation
   even if slower. Temporary CPU fallback experiments require a documented
   GPU constraint; large persistent CPU models are unacceptable.
4. Streaming feedback is a separate requirement. Preview quality must not
   constrain which model produces the final transcript from original audio.

## Read and compare

| Question | Saved evidence |
|---|---|
| What technology is each model, and why might it behave differently? | [Technology map](2026-09-19/TECHNOLOGY.md) |
| Which tested setup was useful, and what failed? | [Ranking and limitations](2026-09-19/QUALITY_RANKING.md) |
| Show actual outputs, punctuation, and A/B differences | [Interactive report](2026-09-19/results/quality-ranking/ranking.html#compare-runs) — private, on this computer |
| What ran locally, with what memory use? | [Local implementation](2026-09-19/LOCAL_STACK.md), [frontier runtime experiments](2026-09-19/FRONTIER_ROUND.md) |
| Was Codex actually tested on the same audio? | [Codex long-recording study](2026-09-19/CODEX_LONG_STUDY.md) |
| What about hosted APIs and consumer apps? | [Cloud experiments](2026-09-19/CLOUD_RESULTS.md), [consumer products](2026-09-19/CONSUMER_PRODUCTS.md) |
| What research was unavailable or remains promising? | [Research/access map](2026-09-19/RESEARCH.md), [local research availability audit](2026-09-19/LOCAL_STACK.md) |
| How should we extend the study? | [Methodology and revisit checklist](METHODOLOGY.md) |
| What integration was agreed? | [Implementation scope](IMPLEMENTATION.md) |
| Did the chosen stack work in T3? | [Integration evidence](2026-09-19/INTEGRATION.md), [live deployment status](DEPLOYMENT_STATUS.md) |

The dated Markdown files are frozen copies of the completed study. Historical
reports may describe earlier candidate sets or restrictions; the latest ranking
and this decision record take precedence. Do not silently update an old snapshot
when new models arrive: create a new dated study and record what changed.

## Reproducibility and private data

Benchmark runners, model revision/hash catalogs, runtime patches, and report
generators live in [tools/stt-benchmark](../../tools/stt-benchmark/README.md).
The snapshot's code baseline is commit
`c76a67ed` (full identity in `2026-09-19/private/inventory.json`). Use that
revision to recover the exact code rather than assuming future runners match.

`2026-09-19/private/` holds a separate copy of all existing raw result files,
the long original WAV, and the early short-clip corpus. `results` is a relative
link into this private snapshot, keeping existing report links functional.
The inventory records SHA-256 and byte size for every preserved input/output.
Some old audio links contain original absolute paths; the copied WAV and its
hash remain available if those paths change.

**Private recordings, transcripts, and raw provider responses are ignored by
Git.** The research notes travel with the repository; the private directory
needs a separate private backup to survive loss of this machine. No credential
files are included. Do not mistake a pushed documentation commit for an audio
backup.

Recovered discussion source: Codex session
`01a0ab2a-09ff-7fc0-a9d3-ac198051426b`, starting 2026-09-16, under
`~/.codex/sessions/2026/09/16/`. Earlier Claude session:
`4681f3e8-93cf-40eb-aa26-afacb910383e`. These are provenance pointers;
continuing this research should not require rereading those conversations.
