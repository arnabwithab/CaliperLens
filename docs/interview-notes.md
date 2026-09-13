# CaliperLens — Interview Prep Notes

Source: full Phase 0–6 walkthrough of `docs/architecture.md` (AWS prod).
`docs/design.md` = local demo. This file = how to talk about it in an interview.
Resume window: Freelance AI Engineer, Feb–Apr 2026.

---

## 1. What you drilled (say more on these)

You asked most about: **RLS, tiering, data pipeline (Parquet/DuckDB/Postgres), rate limits, PITR/RPO/RTO, ALB/SSE, WAF, Cognito, Bedrock caching, harnesses.** These are your strong zones — lead with them.

Less covered (know surface-level): observability 3 planes (§5.12), secrets/KMS (§5.11), revocation runbook (§5.13), decisions table (§9), parity seams (§10). Don't bluff deep here; one line each is enough (see §7).

---

## 2. 60-second pitch (maps to your 4 resume bullets)

> "Multi-agent Text2SQL for 21 Medicaid clinics, 200 users, 30–50 concurrent peak. Chat reads a Postgres replica, nightly MySQL→S3→dbt rebuild writes the primary. Tiered routing (1-mart / 2-mart / staging-fallback) skips the planner for ~95% of questions, so p50 stays under 3s with streaming + semantic SQL cache. Isolation is dual-layer: sqlglot injects `org_id`, Postgres RLS refuses cross-org rows even on parser bug. Python stats/charts run in Lambda with zero DB access, rows-only payload."

Bullet → proof:
- "21 orgs, 200+ users on AWS" → shared pool + `org_id` scoping (§1, §5.7), Cognito per-org groups (§5.2).
- "p50<3s at 50+ concurrent" → 5 compression levers (§2), Fargate 3–10 × 15 SSE (§5.3), Bedrock 150k TPM math (§5.5), semantic cache (§5.9).
- "MySQL→S3→dbt→Postgres, PITR RPO≤5m RTO≤1h, decoupled" → §5.6; RPO = Aurora's number, RTO = failover-steps sum + buffer, proven by quarterly drill.
- "HNSW pgvector GraphRAG, 0.87 context recall" → §5.8; see §6 below for how to defend that number.

---

## 3. Architecture end-to-end (one request)

```
Clinician → CloudFront (TLS + React from S3) → WAF (IP count + managed rules)
→ API-GW (per-clinic token-bucket) → ALB (round-robin, no stickiness, 30s → 503)
→ Fargate (verify JWT locally via cached JWKS → RAG preprocess → LangGraph run)
  ├─ Bedrock (Haiku + Titan via VPC endpoint, prompt-cache on org prefix)
  ├─ RDS Proxy (cap 50) → Postgres REPLICA (marts + pgvector + cache, RLS)
  ├─ Lambda sandbox (≤200KB rows in, PNG/stats out, zero DB role)
  └─ Postgres PRIMARY (dbt writes, checkpoints, INSERT-only audit) + S3 lake + Cognito/JWKS sidecar
```

Per-request LangGraph: `search_tables()` (pgvector, ms, tier hint) → skip planner if Tier 1/2 → generate (org claim in context) → check (sqlglot: SELECT-only, inject `org_id`, LIMIT, HEX binaries) → run_tools (replica inside `SET LOCAL app.org_id`) → deterministic validate → stream final. Tier 3 adds planner + NetworkX Dijkstra + LLM validate. Retry ×3 on retryable only (bad join, binary garbage, 429); guardrail rejects fail closed.

---

## 4. Topics you know cold (interview answers)

**RLS.** Policy `USING (org_id = current_setting('app.org_id'))`. Every agent statement: `BEGIN → SET LOCAL app.org_id=<JWT> → SELECT → COMMIT`. Unset = 0 rows (fail closed). Dedicated non-superuser role, no bypass. `(org_id, patient_id)` index so RLS rides the existing scan. Wall 1 injects, Wall 2 refuses.

**Tiering.** Deterministic from pgvector top-K, no LLM. 1 mart → T1 (no join), 2 marts sharing `patient_id` → T2 (`JOIN ON patient_id` via `MART_SHARED_KEYS`), else T3 (staging + Dijkstra). That's why 95% skip the planner (2 LLM calls: generate + final).

**Data pipeline.** Raw MySQL is 3NF with 4-hop joins (`patient → map → lob → org`) that LLMs bungle. Nightly: MySQL → S3 Parquet (columnar, compressed, per-org folders, `v42` versioned, SSE-KMS, snapshot = rollback) → dbt-duckdb (DuckDB reads Parquet directly; Postgres can't) with Postgres ATTACHed → 4 marts to PRIMARY. Staging views (10, thin, stable contract) → intermediate tables (4, materialize joins once, tested) → marts (persistent, all share `patient_id`). Only marts persist to Postgres; rest is nightly scaffolding. Chat reads replica; lag alarm >30s.

**Parquet vs DuckDB vs Postgres.** S3 = lake (cheap, versioned). DuckDB = compute (scans Parquet fast, in-process). Postgres = serve (concurrency, replica, indexes, RLS, pgvector in one engine). `dbt-postgres` rejected (can't read lake); DuckDB-file prod rejected (no replica/RLS/concurrency).

**Rate limits (7 layers, cheap drops first).** WAF per-IP 5-min count → API-GW per-clinic token-bucket (rate+burst, numbers unset) → backend 20 req/min/user sliding-60s → Fargate ~15 SSE/task (excess queues at ALB) → RDS Proxy 50 backend conns → Bedrock ~150k TPM (429 = retryable) → Lambda reserved 100. ALB 30s is duration cap, not rate.

**ALB/SSE/stickiness.** SSE = one held-open `text/event-stream` per chat, tokens pushed as generated (that's TTFT). Round-robin = cycle A→B→C, dead removed by health-check. 15 = concurrency cap, 30s = duration cap (different axes; 3×15=45 ready, 10×15=150 max). Stickiness OFF by design: state in Postgres (`thread_id=session_id` + owner check), any task resumes any session. JWT-local-verify (cached JWKS, zero Cognito calls/chat) is what makes stateless + round-robin possible.

**WAF/managed rules.** WAF sits CloudFront→API-GW, checks URI/query/headers/body (64KB): your rate rule + `AWSManagedRules*` (Common/SQLi, auto-updated OWASP patterns). Coarse flood + script-kiddie filter; org/prompt/row attacks handled later in Fargate.

**Cognito.** Not inline. Login: browser→Cognito→JWT (access 30m + refresh 7d, `org_id` from group). Chat: JWT rides each request, Fargate verifies locally. Sidecar in diagram for that reason (`fargate → verify JWKS, 0 calls/req → cognito`).

**Bedrock + prompt cache.** Bedrock = AWS LLM API (Haiku reason, Titan embed) over VPC endpoint + BAA so PHI never leaves VPC. Quota: 50 runs × 2 seq calls × 2.5k tok / 2s ≈ 125k TPM → 150k with headroom; TPM is the dimension Bedrock limits. Prompt cache = Bedrock-managed KV reuse on byte-identical static prefix (system+schema per org); we own partitioning (keep prefix stable, volatile text last). Cost lever mainly. Semantic cache (ours, Postgres `hash(normalized q + org + mart_ver)→SQL`) is the latency lever — exact hash, never vector, because near-duplicate questions must not share SQL.

**Harnesses.** B1 = deterministic SQL lock (30–50 redteam cases, CI gate: bypass/encoding/smuggle/sentinel-99/coverage). B2 = LLM mouth (Garak static probes + PyRIT multi-turn vs staging nightly). Centerpiece: planted `"SYSTEM: ignore org…" ` row — before: trusted + lies; after: nonce-wrapped untrusted + RLS holds + audit. Judge lifecycle: 50–100 human labels (growing) → 1 judge/criterion, wrong-reason = error → gate+critic (retry ×3, then flagged-uncertain + audit) → weekly human sample, >2σ drift = re-tune, human approves rubrics, old kept for rollback. Mapped to OWASP LLM01/02/07 + agentic set.

**PITR/RPO/RTO/drill.** PITR = nightly photo + continuous diary, rewind to any second in 35d. RPO≤5m = Aurora's log-ship granularity (adopted, not measured; marts rebuildable from S3 anyway). RTO≤1h = detect+promote+proxy+health+smoke ≈ 15–30m + buffer, proven by quarterly drill: restore to temp cluster → row-count + RLS spot-checks → staging task smoke queries → record RTO/RPO → delete → file evidence (HIPAA paper trail).

---

## 5. Normalization (semantic cache) — exact wording

`lowercase → trim → collapse spaces → strip punctuation`. `"  Show TOP 5 Medicaid?? "` → `"show top 5 medicaid"`. Key = `sha256(that + org_id + mart_version)`. "list" vs "show" = miss by design (different SQL). No stemming/synonyms — that's what vectors are for, and vectors must never pick SQL.

---

## 6. Context recall 0.87 — how to defend it

⚠️ `architecture.md` / `design.md` never define 0.87. Don't present it as doc-backed. Defensible telling:

> "Retrieval hit-rate on the eval set (`eval/questions.json`, 25 questions): fraction where `search_tables()` top-K contained every table the reference SQL needed. Business-context + DDL docs embedded together is what lifts domain synonyms ('Medicaid' → `insurance_name`) from ~0.6 keyword baseline to 0.87. Measured pre-graph (retrieval only), not end-to-end SQL pass-rate; Tier-3 Dijkstra covers the residual."

If pressed: K value (e.g. top-5), embedding model (`text-embedding-004` local / Titan prod), eval categories (simple/filtered/agg/join/multi/edge). Offer the failure slice: residual = Tier-3 staging fallback. Never claim it as SQL accuracy or clinical accuracy.

---

## 7. One-liners for skipped zones (don't get pulled deep)

- **§5.11 secrets:** DB creds only in Secrets Manager (rotated); Bedrock via task IAM role (no keys); KMS CMKs on Aurora/S3/logs; read-once at startup.
- **§5.12 observability:** same `/metrics` + JSON logs (`trace_id/session/node`) everywhere; local = compose Prometheus/Grafana, AWS = AMP remote-write + Managed Grafana + CloudWatch/X-Ray; audit = INSERT-only → S3 Object Lock 7yr (compliance plane); LangSmith full traces under its BAA, `LANGSMITH_TRACING` flag is cost-pause not redaction.
- **§5.13 identity/revocation:** agent acts as service identity (task role + least-privilege DB role), org claim re-read from JWT every request (never memory). Kill: Fargate→0 (<1m) + IAM deny on `TokenIssueTime` + proxy/role rotation = agent dead ≤5m; issued JWT tail ≤30m by TTL design. Read-only so no HITL until a write-tool exists.
- **§9/§10:** every "rejected" column answers "why not X" (EKS, OpenSearch, MWAA, Clerk, single-call gen). Parity: one-flag seams, merge rule = ship both backends + local test.

---

## 8. Tough follow-ups to expect

1. "Why shared pool, not per-org DBs?" → 21 orgs, pilot ops cost; dual-layer org isolation + per-org audit + RLS proven by staging runs.
2. "50 concurrent — measured?" → No. Locked sizing assumption (200 users, huddle/rush/reporting overlap ≈ ¼ online). Sizes Fargate/Proxy/TPM/Lambda; validate with metrics live.
3. "Why hash not vector for SQL cache?" → exactness + safety; vectors retrieve tables, never SQL.
4. "WAF bypass via JWT?" → WAF never sees trust; org comes from verified JWT per-request + RLS.
5. "Task dies mid-stream?" → checkpoint in Postgres survives; client retries, lands anywhere, owner check resumes.
6. "Cost blowup?" → prompt cache + semantic cache + 20/min/user + per-org cost-per-query metric + LangSmith spend alarm.
