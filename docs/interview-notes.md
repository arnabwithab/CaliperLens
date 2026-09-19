# Interview Prep — Freelance AI Engineer (Value-Based Care Healthcare Client)
Resume block: Feb 2026 – Apr 2026

Full record of every question asked, the answer given, and the corrected/final defensible version. Use this to rehearse — not a summary, every point raised is kept.

---

## Bullet 1: "Deployed a multi-agent Text2SQL engine with sandboxed-agent execution serving 21 orgs and 200+ users on AWS."

### Q: Why multi-agent instead of a single agent with tool access?
**Answer given:** Clients were non-technical clinicians facing a complex multi-join DB. A single agent hallucinated tables/join relationships because it didn't understand internal terminology. Needed specialized agents: research, query drafting, validation/retry, and graph traversal (schema/join discovery via RAG-injected context).

**Follow-up asked:** Name the exact pipeline in order — what each agent receives as input, produces as output, and what decides pass-forward vs. loop-back.

**Answer given (full pipeline, as clarified over multiple turns):**
1. **Query rewrite / normalization** — LLM (Gemini 3.1 Flash-Lite — see correction below) converts the natural-language query into a strict JSON output extracting entities: user class, time period, metric type, etc.
2. **Semantic cache check** — the canonical JSON is hashed; exact hash match = cache hit, skip everything downstream, no further LLM calls.
3. **On cache miss → Retrieval agent** — hits RAG (pgvector/HNSW) to identify relevant tables/marts and internal context, then checks dbt marts.
4. **Tiering decision:**
   - **Tier 1** (1 dbt mart needed): straight to SQL generation. Simplest, most frequent path.
   - **Tier 2/3** (2, 3+ marts needed, or marts insufficient): enters a **research node** that hits the GraphRAG (Dijkstra shortest-path over the schema graph) to find join relationships the marts don't cover.
5. **SQL generation agent** — drafts the query (heavier model, e.g. Opus/GPT-class).
6. **Retry/repair loop** — catches malformed SQL, retries/repairs.
7. **Sandbox agent** — invoked if the user needs code-based analysis beyond a raw query result.

### Correction flagged: "Semantic caching" claim
**Initial answer (incorrect as stated):** Normalize query, hash it, exact-match cache lookup.
**Problem raised:** That's exact-match caching with pre-normalization, not semantic caching (which implies embedding/cosine-similarity matching of *differently worded* equivalent queries).
**Risk raised by candidate (valid point):** True cosine-similarity semantic caching risks false-positive hits between *lexically similar but clinically distinct* queries (e.g., different care/plan types) — dangerous in healthcare.
**Resolved mechanism:** Normalization is LLM-driven (not regex) — an LLM extracts structured entities into a fixed JSON schema (user class, time period, metric, etc.), and *that JSON* is hashed. This is what actually distinguishes "Medicaid patients" = "patients enrolled in Medicaid" (same entity) from "this quarter" ≠ "last quarter" (different time entity).
**Verdict:** Defensible design once explained precisely, but do NOT describe it as "hash the normalized text" — describe it as "LLM-based structured entity extraction into canonical JSON, then hash the JSON" if asked to explain the mechanism from scratch.

### Correction flagged: Model name
**Claimed initially:** "Gemini 3.5 Flash Lite" — does not exist / anachronistic for the Feb–Apr 2026 window (3.5 Flash-Lite's documented existence traces to mid/later 2026).
**Corrected to:** Gemini 3.1 Flash-Lite.
**Lesson:** Know your exact model name/version cold. An interviewer catching a wrong/anachronistic model name will doubt whether the whole story is accurately recalled.

### Latency budget for Tier 1 cache-miss (reconciled after some back-and-forth)
- Rewrite (Flash-Lite call): ~500ms
- RAG/vector mart-lookup: pure vector similarity, no LLM, sub-100ms
- SQL generation: heavier model (Opus-class), remaining budget — worst case latency accounted for here
- **Note:** Initial answer said "only 1 LLM call for Tier 1" which contradicted the earlier full-pipeline description (rewrite + SQL-gen = at least 2 calls). Resolved: candidate meant "1 LLM call *after* rewrite" (i.e., just SQL generation) for the simplest Tier 1 path.

---

## Bullet 2: "Achieved p50<3s via tiered agent routing, auto-scaling Fargate, and semantic caching at 50+ concurrent users."

### Fargate scaling config
- Min tasks: 3, Max tasks: 10
- Per-task streaming concurrency cap: 15
- ALB handles excess queue
- Scaling metric: request queue depth + concurrent connections (not CPU/memory — correct call, since LLM workloads are I/O-bound and CPU doesn't correlate with actual load)

### Checkpointing claim: "dying mid-request isn't an issue, states are checkpointed in Postgres"
**Challenge raised:** This implies automatic recovery. Need to specify: checkpoint granularity (per agent-hop?), and whether there's an actual reconciliation process that detects orphaned in-flight requests and auto-requeues them, vs. checkpoints merely making a *client-initiated retry* cheaper (skip redoing completed stages) without true automatic recovery.
**How to answer honestly (agreed framing):** "We checkpoint after every agent hop — rewrite, retrieval/mart-selection, SQL generation, validation, execution. If a task dies mid-request, there's no automatic orphan-detection/requeue system — the client's connection drops and on retry, the orchestrator sees an existing checkpoint for that request ID and resumes from the last completed stage rather than restarting cold. That's a retry-cost optimization, not full automatic exactly-once recovery — I'd be upfront about that distinction if asked whether failures are fully invisible to the user."

### Cooldown question — candidate pushback (resolved well)
**Interviewer pressed:** What were scale-out/scale-in cooldowns, did you tune them, did you observe/fix thrashing?
**Candidate's answer:** ECS default cooldowns were sufficient — no tuning needed. Reasoning: peak concurrency is only 30-50 users, average concurrent is ~5 (out of 200 total registered users, many inactive). At this scale, min=3 tasks already absorbs baseline, and load changes happen over minutes (meeting/call cadence), not fast enough for cooldown thrashing to be a real risk.
**Strengthened framing (agreed as the correct answer):** "Tuning cooldowns wasn't a real bottleneck at this traffic scale — reaching for custom cooldown tuning would have been solving a problem we didn't have. Thrashing only becomes a concern with frequent, high-amplitude load oscillation; our load pattern doesn't produce that." This is a *better* answer than claiming unearned tuning work.

### Follow-up: why min=3 if per-task cap (15) already exceeds average load (5)?
**Inconsistency caught:** Candidate initially said min=3 was for "3x throughput headroom," but math shows even 1 task (cap 15) comfortably absorbs average load of 5, undermining the throughput justification.
**Resolved/correct answer:** The real reason for min=3 is **availability/redundancy**, not throughput — min=1 creates a single point of failure (a crashed task, failed health check, or mid-rolling-deploy leaves zero capacity for the recovery window). Min=3 gives N+1 redundancy plus extra margin for rolling deploys (need a warm spare beyond steady-state need). Marginal cost of a 3rd small Fargate task is negligible vs. cost of a client-visible outage.
**Lesson:** Don't conflate throughput reasoning with availability reasoning — know which one actually drove each decision.

---

## Bullet 3: "Engineered MySQL→S3→dbt→Postgres pipeline, with PITR: RPO<5min, RTO<1h, decoupled from live traffic."

### Q: Why decouple from live MySQL traffic at all?
**Correct/agreed answer (two distinct reasons):**
1. **Resource contention / blast radius isolation** — LLM-generated SQL is unpredictable in cost (could trigger full table scans or bad joins). Running that directly against production MySQL risks degrading or locking the system serving real-time clinician/patient traffic.
2. **Query shape mismatch** — production OLTP schema is normalized for transactional writes, not analytical multi-join reads. The dbt mart layer denormalizes specifically to make multi-join queries fast AND to reduce the reasoning surface for the LLM (fewer tables, pre-joined structures = less hallucination risk on join paths). Decoupling is what makes the mart-based approach tractable, not just a safety measure.

### RPO<5min claim
**Interviewer initially pushed back**, claiming RPO is not "just an AWS standard" but something you define yourself.
**Candidate pushback:** RDS PITR does have a standard ~5min RPO as a documented mechanism.
**Verified via search — candidate was correct.** RDS uploads transaction logs to S3 every ~5 minutes as part of automated backups/PITR, giving a documented, standard "<5min RPO" figure tied to that specific backup mechanism. This is a legitimate, citable claim, not something you invented.
**Lesson:** Know that the *mechanism* behind "<5min RPO" is RDS's continuous transaction-log-to-S3 upload (every 5 min) enabling point-in-time recovery — be ready to name this mechanism, not just the number.

### RTO<1h claim
**Initial answer (incorrect):** Conflated RTO with the biweekly mart-rebuild refresh cadence (unrelated concepts — refresh cadence ≠ disaster recovery time).
**Corrected framing (agreed as the right answer):** RTO refers to recovery from a mart-layer failure (e.g., Postgres marts corrupted/lost) — recovery mechanism is re-running the dbt build against the S3 lake (which holds the raw MySQL extract independent of the live mart DB), NOT waiting on MySQL. Feasible under 1 hour because mart tables are pre-aggregated and scoped (a handful of dbt models per org), so a full rebuild completes quickly.
**Honesty flag to include if pressed:** "The 1-hour figure is an engineering estimate/target based on typical dbt run time — I can't say we validated it via an actual timed disaster-recovery drill in a 3-month freelance engagement." State this distinction clearly rather than presenting it as a validated SLA.

---

## Bullet 4: "Built HNSW-indexed pgvector GraphRAG for schema discovery, achieving 0.87 context recall on domain knowledge."

### HNSW parameters
- Used **default** parameters for m, ef_construction, ef_search (not tuned — inherited handover context that discouraged tuning since 0.87 recall on defaults was seen as adequate).
- Trade-offs (confirmed correct):
  - **m** ↑ → recall ↑, RAM usage ↑ (more bidirectional links; also affects build/insertion throughput)
  - **ef_construction**: trade-off between graph quality and index build time (insertions/updates)
  - **ef_search**: trade-off between recall and query latency

### 0.87 Context Recall — methodology deep dive
- **Eval set:** 50 human-annotated pairs (query, ground-truth relevant chunk, expected SQL execution output). Annotated using a combination of production logs (from when latency was a known problem) plus joint data-science-team + clinician annotation.
- **Chunk definition:** mix of table descriptions, column descriptions, dbt mart names. Join relationships needed no extra engineering since all 4 dbt marts link cleanly via patient_id.
- **Metric clarified — NOT recall@k.** This is **RAGAS Context Recall**, an LLM-as-judge metric: for a given ground-truth statement decomposed into N facts, judge determines how many of those facts are attributable to/present in the retrieved context. Different from checking whether specific chunk IDs were retrieved.
- **Judge model:** GPT-4o, temperature=0 (deterministic). Candidate's reasoning for not validating judge-vs-human alignment: task is simple (binary "is this fact in the context, yes/no"), so common LLM-judge pitfalls (miscalibration, leniency) were judged unlikely to be a real risk here. If ever an issue, candidate would run judge-vs-human alignment checks / build rubrics.
- **Run count:** single run, not repeated. No variance/confidence interval computed.
- **Honest framing to give if pressed on statistical rigor:** "With n=50 and a single run, this isn't a statistically tight estimate — true population recall could plausibly range from high-0.7s to mid-0.9s. I'd state 0.87 as our one measured data point, not a robust, narrow-CI metric. This was a 3-month freelance engagement — we shipped, measured once, documented it in the handover for the client's engineers (LangSmith + Prometheus set up for their ongoing monitoring), and moved on. That's a legitimate scope limitation of freelance work, not something I'd pretend was more rigorously validated than it was."

### Major correction: "GraphRAG" naming / architecture clarity
**Problem surfaced:** Candidate initially implied GraphRAG (graph traversal + RAG) was a single coupled system credited with both schema discovery AND the 0.87 recall figure.
**Clarified under questioning:**
- The **graph** component: nodes = tables, edges = join relationships, traversal = literal Dijkstra shortest-path. This was the **original, foundational** version of the system — used **upfront**, during initial schema exploration, to discover which of the 40+ join relationships (across 60+ tables) were worth pre-materializing into the 4 dbt marts.
- The **RAG (pgvector + HNSW)** component is **entirely separate** — it's the semantic retrieval system used for mart-selection, and it's what's actually serving 95%+ of production traffic today.
- The **0.87 context recall number belongs to the mart-selection RAG system** (the one serving live traffic), NOT to the original graph-traversal system.
- The graph/Dijkstra fallback (for the <5% of tier-3 queries where marts are insufficient) **has not actually been invoked in production yet** — it exists as a worst-case fallback, accounted for architecturally but unexercised so far. The "<5%" figure is an unmeasured/vague expectation, not a logged statistic.
**Conceded directly:** "GraphRAG" as a single term is a naming simplification — the two components (graph traversal, vector RAG) operate independently/at different pipeline stages, not as a coupled retrieval-informs-traversal (or vice versa) system that the term usually implies.
**Recommended reframe for resume/interview:** Separate the two contributions explicitly — credit the vector-retrieval system for the measured 0.87 recall on live production traffic, and separately describe the graph-based join-discovery work as what identified mart boundaries during initial schema analysis (a foundational/exploratory contribution, now a dormant fallback path). Do not present them as one validated, unified "GraphRAG" system.

---

## Summary of things to tighten before a real interview
1. Get the exact model name right cold (Gemini 3.1 Flash-Lite, not 3.5).
2. Don't call the caching mechanism "semantic caching" without immediately clarifying it's LLM-driven structured-entity extraction + exact hash match on canonical JSON — not cosine-similarity matching.
3. Be ready to distinguish "retry-cost optimization via checkpointing" from "automatic failure recovery" — don't overclaim the latter.
4. Know your min-task-count reasoning is availability/redundancy, not throughput headroom — don't conflate the two if asked "why 3 and not 1."
5. RPO<5min: name the actual mechanism (RDS automated transaction-log-to-S3 upload every 5 min enabling PITR) — this is a legitimate, defensible claim.
6. RTO<1h: describe the actual recovery mechanism (dbt rebuild from S3 lake, independent of live MySQL) and be upfront that the 1-hour figure is an engineering estimate, not a validated DR-drill result, unless you can say otherwise.
7. Biggest one: rewrite/reframe the "GraphRAG" bullet to honestly separate (a) the measured, live-serving vector-retrieval system (0.87 recall, 95%+ of traffic) from (b) the foundational, now-dormant graph-traversal fallback used for initial schema discovery. Don't let an interviewer catch you implying these are one coupled, validated system.
8. On the 0.87 number: know it's RAGAS context recall (LLM-as-judge over decomposed facts), n=50, single run, GPT-4o judge, temp=0 — not recall@k, not a large or repeated-sample statistic. Be ready to state its limitations plainly if pressed.
