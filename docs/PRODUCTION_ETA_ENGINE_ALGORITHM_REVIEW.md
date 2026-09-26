# Production ETA Engine — Algorithm Review and Enhancement Suggestions

**Status:** design review, no production code changed.
**Evidence base:** production backup `taleeb_prod_2026-09-26_02-18-07` (Flyway V193), loaded locally as `taleeb_eta_20260926`; 6,564 plan-linked pallets, 241 plan items, 2026-05-25 → 2026-09-26. Every number below comes from that data or from a leak-free backtest on it (history built only from events before each test item started; live state only from the item's own events up to the checkpoint).
**Companion:** the original investigation report (chat, 2026-09-26) describes the existing system, data quality and the candidate-model comparison. This document reviews the recommended algorithm (v1.0) and proposes v1.1.

---

## 1. The algorithm under review (v1.0)

```
1. Prior rate      μ0 = shrunken mean of log(median min/package) along family → product → product+line
2. Live rate       ŷ  = median of log(gap/qty) over within-shift gaps; var = (1.2533·σ)²/n, σ = 0.30
3. Posterior       1/v = 1/τ² + 1/var ;  μ = v·(μ0/τ² + ŷ/var) ; τ = 0.20 ; m = e^μ  (min/package)
4. Expected gap    I = q_next · m
5. Silence state   u = s / I ;  P(stop | u) from the shared normalized-gap table ; residual = I · MRL(u)
6. Future          (R − q_next)·m productive, + within-shift stop allowance (E[r] ≈ 1.09), + handover loss per 00/07/16 boundary
7. Output          Monte Carlo (1,000 paths): m ~ LogN(μ, v); current gap | r > u; later gaps r from the empirical table;
                   gaps that cross a shift boundary use the handover table → P10 / P50 / P90 + explanation
```

Backtest result (items that reached target, 80 items / 2,477 checkpoints): MAE 239 min, median error 71 min, 80% interval covers 82%. Naive average-rate baseline: MAE 363 min.

---

## 2. Review verdict

### What holds up

| Claim in v1.0 | Re-checked | Result |
|---|---|---|
| Family (mold) is the only structural predictor of speed | within-item F-tests for operator, palletizer, shift, weekday | all p ≥ 0.44; keep family-first hierarchy |
| One normalized-gap table serves all products | per-family quantiles of r = gap/(qty·rate) | P95 1.5–2.1 for every family with n ≥ 30; holds |
| Rate is stable within a run (no regime changes) | between-shift variance of item log-rate vs noise | 0.015 observed vs 0.024 expected from noise → no extra variance; CUSUM made ETA worse |
| Stops are memoryless | P(stop \| previous gap was a stop) | 0.031 vs 0.040 base → no clustering; iid draws are correct |
| Downtime, not rate, dominates the error | oracle test with the true item rate | MAE 229 → 191 only; ~85% of error is stoppage timing |
| Intervals are honest | 80% interval coverage | 0.82 (reached-target items); 0.76 (all items incl. early close) |

### Weaknesses found

| # | Weakness | Severity | Evidence |
|---|---|---|---|
| W1 | **No known-state layer.** v1.0 treats every silence as a possible stop, but 2.9% of shift ends have no incoming operator within 30 min, and when that happens the gap is long (median 193 min, P75 1,575 min). Palletizer login lags the operator by a median 4.9 min and exceeds 30 min in 9.4% of shift lines. These are *known* states, not statistical stops. | High | shift-line and palletizer-session tables |
| W2 | **One handover distribution for three boundaries.** Loss at 16:00 is 2–3× the others (median 20 / mean 44 / P90 90 min vs 7 / 28 / 56 at 00:00 and 10 / 28 / 47 at 07:00). | Medium | 630 handover gaps |
| W3 | **Median live estimator is inefficient** on erratic runs; it also ignores cross-shift gaps entirely. | Medium | split-half test §3.2 |
| W4 | **Fixed τ = 0.20** even when the family prior comes from 1–2 items (LINE_3, new molds). The posterior then over-trusts a thin prior. | Medium | 19 of 46 products have < 5 items |
| W5 | **Interval coverage drops to 0.73–0.76 on items that close early** (half of all items). The P50 is 2–6% pessimistic on median (log(actual/P50) = −0.02 to −0.06). | Medium | §3.4 |
| W6 | **MRL tail fallback is arbitrary** (0.5·s beyond data). Long silences are exactly where the estimate matters most. | Medium | design |
| W7 | **Scheduled pauses and admin pauses are ignored.** `thermoforming_line_pause_schedules` carries `scheduled_pause_at` and `pause_duration_seconds`; an open pause interval should freeze the ETA. | Medium | 8 pause intervals, 1 schedule |
| W8 | **Last pallet assumed full-size.** The MC uses the median event quantity for the final event; the real last pallet is the remainder. Small but systematic. | Low | ppp vs target |
| W9 | **Registration catch-up is not modelled.** The first pallet after a stop arrives early (median r = 0.85) because it was partly stacked before the stop; the stop duration derived as `gap − q·m` is therefore ~15% of an interval too long. | Low | 220 stop gaps |
| W10 | **Displayed ETA jumps** when a pallet arrives (gap-state residual resets from I·MRL(u) to a fresh interval). Correct statistically, unpleasant in a UI. | Low (UX) | design |
| W11 | **Backtest selection effects.** "Reached target" mode selects on the outcome; 60 of 168 test items have a migration-reconstructed `started_at`; hourly checkpoints are 77% of all checkpoints, so metrics weight mid-run. | Medium (evidence quality) | backtest design |

---

## 3. Enhancements tested against the data

All variants were run through the same leak-free harness in two modes: **target** (80 items that reached target, 2,477 checkpoints) and **all** (168 items incl. early closes, finish = final quantity, 5,371 checkpoints).

### 3.1 End-to-end ablation

| Variant | target MAE | target bias | target cov80 | all MAE | all RMSE | all bias | all cov80 |
|---|---|---|---|---|---|---|---|
| v1.0 Monte Carlo (base) | 240.8 | −3 | 0.831 | 282.3 | 599 | −35 | 0.762 |
| + all four below | 242.3 | +8 | 0.789 | **269.6** | **579** | **−15** | 0.750 |
| − Huber (median instead) | **237.2** | −6 | 0.813 | 283.8 | 596 | −39 | 0.747 |
| − per-family σ | 241.7 | +5 | 0.799 | 268.7 | 580 | −17 | 0.750 |
| − per-boundary handover | 245.9 | +13 | 0.786 | 270.0 | 580 | −9 | 0.752 |
| − time-of-day stop tables | 241.4 | +7 | 0.794 | 271.1 | 583 | −14 | 0.750 |

Reading: the enhancements buy **−4.5% MAE and −3% RMSE on the full population**, mostly from the Huber estimator on erratic runs (n > 20 events: 255 → 218 min), while being neutral on clean runs. Per-boundary handover tables are a small, consistent win and halve the bias in target mode. Time-of-day stop tables and per-family σ are noise; drop them for simplicity.

### 3.2 Live-rate estimator (Huber vs median vs trimmed total)

Split-half test inside each item with ≥ 16 gaps: estimate the log-rate from the first k gaps, compare with the rest of the run.

| k gaps | median | trimmed total/total | **Huber (clip ±0.6 around median)** |
|---|---|---|---|
| 3 | 0.277 | 0.308 | **0.262** |
| 5 | 0.214 | 0.218 | **0.186** |
| 8 | 0.162 | 0.152 | **0.148** |

Huber lowers rate error by 9–13%, roughly equal to seeing 30% more pallets. It is the reason the "all" MAE improves. The clipped mean carries ~15% more variance than a clean mean, so its posterior weight must use `var = 1.15·σ²/n`, not `σ²/n`; under-stating this variance is what made the target-mode result slightly worse.

### 3.3 Time-of-day effects (why the table did not help)

| Hour of gap end | 0–6 | 7 | 9 | 11 | 14 | 16 | 18–22 |
|---|---|---|---|---|---|---|---|
| Stops per 100 running h | 2.5–4.6 | 5.4 | 6.6 | 7.2 | **10.4** | **11.2** | 4.8–8.1 |
| Share of wall time lost | 0.12–0.15 | 0.21 | 0.18 | 0.19 | **0.25** | 0.16 | 0.17–0.21 |

Nights are quieter and 14:00–15:00 loses twice the usual time (a recurring break or prayer/lunch pattern is likely — **question for the factory**). The effect is real but small relative to the stoppage variance, so a day/night split of the r-table changed the MAE by < 1 min. Worth revisiting only if a fixed break time is confirmed, in which case it becomes a deterministic deduction, not a distribution.

### 3.4 Interval calibration (conformal correction)

Calibrate on the earlier half of test items, evaluate on the later half.

| Mode | raw MC cov80 | scale-only conformal | horizon-bucketed ratio conformal |
|---|---|---|---|
| target | 0.816 | 0.801 (k = 0.95) | 0.764 |
| all | 0.729 | 0.729 (k = 1.00) | **0.781** |

The raw intervals are already calibrated for runs that reach target. For the full population they are ~7 points too narrow, and a multiplicative correction bucketed by predicted horizon (< 2 h, 2–8 h, > 8 h) recovers it. Recommendation: **do not bake a correction in**; ship a coverage monitor and apply the bucketed correction automatically only when the trailing-60-item coverage leaves the 0.75–0.85 band.

### 3.5 Early close — can it be predicted?

50% of items close below target (median 3.6 pallets short, IQR 1.4–8.0). A logistic model on target size, mold change and line has pseudo-R² = 0.03; only larger targets are slightly more likely to be cut short (p = 0.03). **Not predictable from production data.** The engine should always report *ETA to target* and let the V190 close-request flow override it ("closing early: request pending").

### 3.6 Uncovered shifts

| Boundary | shift ends | P(no operator within 30 min) | P(> 2 h) |
|---|---|---|---|
| 00:00 | 219 | 0.01 | 0.01 |
| 07:00 | 206 | **0.05** | 0.02 |
| 16:00 | 218 | 0.01 | 0.00 |

Rare, but these gaps are the tail that breaks P90 in "all" mode (P75 of an uncovered gap is 26 h). They must be handled as a *state* (W1), not sampled.

---

## 4. Enhancement suggestions

### 4.1 Adopt in v1.1 (evidence-backed)

**E1. Known-state layer before any statistics** (fixes W1, W7). Evaluate in this order and short-circuit:

| State | Detected from | ETA behaviour |
|---|---|---|
| `TARGET_REACHED` | Σ ACTIVE pallet qty ≥ target | no ETA; show "target reached, awaiting close" |
| `CLOSE_REQUEST_PENDING` | `thermoforming_plan_item_close_requests.active_lock` | ETA of the *next* item's start = confirmation; show the request state |
| `LINE_PAUSED` | open `thermoforming_line_pause_intervals` | freeze ETA at pause start; add `scheduled_resume_at` (or MRL of past pause lengths) |
| `PAUSE_SCHEDULED` | `thermoforming_line_pause_schedules` (PENDING) | inject the pause deterministically into the MC path |
| `NO_OPERATOR` | no ACTIVE `thermoforming_shift_lines` for the line | resume = next shift boundary from `shift_definitions` + handover startup loss; label "waiting for operator" |
| `NO_PALLETIZER` | ACTIVE shift line, no ACTIVE `palletizer_sessions` | production may be running; treat silence as registration lag: cap u at 1.0 and add the palletizer-login distribution (median 5 min, P90 28) |
| `RUNNING` | otherwise | statistical path (E2–E8) |

Each state should be a named reason in the explanation payload; the UI stops guessing from the 30-minute rule in `AdminAppStatusMapper`, which flags 39% of normal running time as inactive.

**E2. Huber live estimator with correct variance** (W3). `ŷ = mean(clip(log(gap/qty), med − 0.6, med + 0.6))` over within-shift gaps; `var = 1.15·σ²/n`. Gain: −4.5% MAE on the full population. Optionally include cross-shift gaps in the clipped mean once n ≥ 6, since the clip neutralizes the handover excess; not yet tested.

**E3. Per-boundary handover tables** (W2). Keep three empirical distributions of the normalized handover gap r_x, keyed by boundary hour bucket {00, 07, 16}; fall back to the pooled table below 30 samples. Gain: −1.5% MAE and −40% bias in target mode; also makes the explanation truthful ("16:00 handover typically costs ~20 min").

**E4. Widen the prior for thin families** (W4). `τ_eff² = τ² + τ²/(n_level + κ)` where `n_level` is the number of items at the deepest hierarchy level that had data. With one item, τ_eff ≈ 0.28; with ten, ≈ 0.21. When the family itself is unseen (new mold), fall back to the global level with τ = 0.29 and flag `confidence = LOW` in the explanation.

**E5. Parametric silence tail** (W6). Fit the stop-duration distribution once per nightly rebuild (log-normal fitted on `excess = gap − q·m` of gaps with r > 2; current data: median 51 min, P90 102, P95 122) and use its mean residual life beyond the empirical table instead of `0.5·s`. Cap the residual at the `NO_OPERATOR` resume rule when a boundary is closer.

**E6. Exact remainder for the last event** (W8). `q_last = R mod q_ev` (or `q_ev` if zero); the final MC interval uses `q_last·m`.

**E7. Catch-up correction for stop accounting** (W9). When labelling downtime for explanation and for the nightly stop-duration table, use `excess = gap − 0.85·q·m` for the interval that ends the stop (the 0.85 is the observed median r of the first post-stop gap). This does not affect the ETA path, only the reported stop lengths and the fitted tail in E5.

**E8. Display hysteresis** (W10). Keep the raw P50 internally; the displayed ETA moves only when the change exceeds max(5 min, 3% of remaining) or when the known state changes. Publish both `eta_raw` and `eta_display` so the UI can animate honestly.

**E9. Calibration monitor with conditional conformal correction** (W5). Store every published P10/P50/P90 with its item id; when the item finishes, score it. Maintain trailing coverage over the last 60 finished items. If cov80 leaves [0.75, 0.85], apply the horizon-bucketed multiplicative correction (§3.4) until it returns. Also track median log(actual/P50); a persistent value below −0.05 means the stop allowance is too generous.

**E10. Explanation payload as a first-class output.** Every ETA response carries:

```
state, eta_p10, eta_p50, eta_p90, remaining_packages,
rate_prior_min_per_pkg, rate_prior_source {level, n_items}, rate_posterior_min_per_pkg, live_gaps_used,
run_vs_baseline_pct, silence_min, silence_ratio_u, stop_probability,
stop_started_at (if P ≥ 0.9), expected_handovers [{boundary, expected_loss_min}],
expected_within_shift_loss_min, confidence_band {LOW|MEDIUM|HIGH from τ_eff and n}, model_version, profile_built_at
```

### 4.2 Tested and rejected (do not add)

| Idea | Result | Why |
|---|---|---|
| Change-point detection (CUSUM on live rate) | MAE 271 vs 245 | resets throw away good data; within-run rate is stable |
| Operator / palletizer baselines | MAE +2 min, effects flip between data halves | no signal (p ≥ 0.44); overfits 6–12 identities |
| Recency weighting (half-life 30/60 d) or drift correction | ±1 min | drift (+7%/30 d) exists but the live update absorbs it within 4 gaps |
| Time-of-day stop tables | < 1 min | effect real but tiny vs stoppage variance |
| Per-family σ | < 1 min | shrinks to 0.30 anyway; TT-1R/TT-2R spread is a registration artefact |
| LightGBM quantile model | MAE 362–566 vs 252–316; cov80 0.53–0.64 | too few items (≤ 141 in train); learned mostly to copy the analytic estimate |
| Roll events as a heartbeat | roll mounts continue during 88% of long stops | backfilled in bursts; not a run signal today |
| Roll age (curing) as a rate predictor | rate flat across 48 h–144 h+ | no measurable effect |

### 4.3 Data-capture changes (largest remaining lever)

About 85% of the residual error is stoppage timing that pallet data cannot see; a stop shorter than ~20 min is invisible. In priority order:

1. **Stop / resume buttons with a reason code** in the thermoforming operator app (mold change, piston/cutter repair, granulator jam, no rolls, quality hold, power, break). Operators already write these in free text (`LINE_STOPPED_DUE_TO_MALFUNCTION` notes, 28 rows; 188 general notes mention stops). Structured start/end timestamps would let the engine switch from inference to fact, and would give the nightly job a labelled stop table.
2. **`product_types.mold_code`** (or `family`) as a real column instead of parsing the name prefix. Today the hierarchy depends on a naming convention.
3. **Target versioning** — `updateItem` overwrites `target_package_quantity`; backtests and audits need the target as it was at time T.
4. **Break schedule** — if 14:00 is a fixed break, record it in `shift_definitions` (or a new breaks table) so the engine deducts it deterministically.
5. **Planned early switch flag** — when management decides to switch product before target, record it on the item at decision time; it is the only way an "early close" can ever be anticipated.
6. **Machine cycle signal** via the existing `factory_edge` agent (currently attendance punches only) — the only route to seeing stops shorter than a pallet interval.

### 4.4 Future ideas (need more data or a decision)

- **Material runway.** 22 items closed for INPUTS / ROLLS_FINISHED. Remaining kg needed = `remaining_packages × package_weight_kg ÷ (1 − grinding %)`; compare with the mounted roll's `remaining_weight_kg` plus cured roll stock of a compatible `roll_type` (`min_curing_hours` 65–72 h). A shortfall is a predictable stop.
- **Other-line signal.** When the sibling line is also silent, a stop is 2.3× more likely (25% vs 11%). Could enter the stop posterior as a likelihood ratio; needs validation on more factory-wide events.
- **Line schedule projection.** Chain items: next item start = this ETA + changeover (13 min same mold, ~85 min mold change) → a per-line plan timeline for the admin app.
- **Grinding-order tables (V198+, not in this dump)** as a stop indicator; granulator jams are a top cause in operator notes.

---

## 5. Revised algorithm (v1.1)

All rates in minutes per package. `R` = packages remaining to target, `s` = minutes since the last registration event, `q_ev` = median event quantity of this run (or `packages_per_pallet` before 2 events).

```
0. Event stream   ACTIVE pallets of the item; merge registrations ≤ 3 min apart into one event (qty summed);
                  tag each gap with cross_shift (shift_line changed) and boundary bucket {00,07,16}
1. State          E1 table; if not RUNNING → state-specific ETA, skip to 8
2. Prior          μ0 by shrinkage family → product → product+line, κ = 1.5 items
                  τ_eff² = τ² + τ²/(n_level + κ),  τ = 0.20 (0.29 if only the global level exists)
3. Live           within-shift gaps: lr_k = log(gap_k / qty_k); med = median(lr);
                  ŷ = mean(clip(lr, med−0.6, med+0.6)); var = 1.15·σ²/n, σ = 0.30
                  (n = 0 → skip; the prior stands)
4. Posterior      1/v = 1/τ_eff² + 1/var;  μ = v·(μ0/τ_eff² + ŷ/var);  m = e^μ
                  live weight = (1/var) / (1/var + 1/τ_eff²)   → ≈ n/(n+3.5) at τ = 0.20
                  run_vs_baseline = exp(ŷ − μ0) − 1
5. Silence        I = q_ev·m;  u = s/I
                  P(stop|u) = 1 − π0·S0(u)/S(u),  S0 = LogN(0, 0.31) survival, π0 = 0.94, S = empirical r survival
                  u: 1.0→4%  1.25→16%  1.5→33%  1.75→51%  2.0→71%  2.5→93%  3.0→98%
                  stop_started_at = t_last + I  once P ≥ 0.9
                  residual = I·MRL(u) from the empirical r table (cross-shift table if the shift changed),
                  parametric log-normal tail beyond the data (E5), capped by the NO_OPERATOR rule
6. Changeover     n = 0: remaining = MRL(elapsed) of the changeover distribution for {same mold | mold change}
                  (same mold: median 13 min, P90 51; mold change: median ~85 min, P90 ~200); exclude
                  changeovers that overlapped a pause or an uncovered shift when fitting
7. Monte Carlo    1,000 paths:  m ~ LogN(μ, v)
                  t = residual sample (r | r > u)·q_ev·m − s          [or changeover sample]
                  for each remaining event (q = q_ev, last = R mod q_ev):
                      r ~ empirical within-shift table;  dt = r·q·m
                      if [t, t+dt] crosses a boundary b: dt = max(dt, r_x[b]·q·m)
                      inject scheduled pauses that fall inside [t, t+dt]
                      t += dt
                  → P10 / P50 / P90 (+ optional conformal factor from E9)
8. Output         E10 payload; eta_display with hysteresis (E8)
```

Constants are data-derived and must live in a versioned profile row rebuilt nightly (rolling 120-day window, ACTIVE pallets only, items with ≥ 3 events): family/product/line log-rate means and counts, the r tables (within-shift, three handover buckets), the changeover distributions, the stop-duration log-normal, π0 and S0.

---

## 6. Expected accuracy after v1.1

| Population | v1.0 MAE | v1.1 MAE (measured) | v1.1 + E1 (estimated) | cov80 |
|---|---|---|---|---|
| Items that reach target | 241 | 237–242 | ~235 | 0.79–0.83 |
| All items incl. early close | 282 | 270 | ~250 | 0.75 → 0.78 with E9 |

E1 was not backtestable in the harness (it needs the live line state at each checkpoint); the estimate assumes it removes most of the uncovered-shift tail (1–3% of gaps, 4,000+ min each) from the statistical path. Median error in the last hour before finish is 8 min; the ±5/±10-minute targets are only realistic there.

**Backtest limitations to carry forward (W11):** results are for one plan on two lines over four months; 60 of 168 items have a reconstructed `started_at`; hourly checkpoints dominate the sample. Shadow mode (store every published interval, score on finish) is the real acceptance test. Gates: trailing cov80 in [0.75, 0.85], |bias| < 30 min, MAE not worse than the current model on the same items.

---

## 7. Implementation notes

- **Tables:** `production_eta_profiles` (one JSON/row per profile version), `production_eta_snapshots` (published intervals + realized outcome for E9), `product_types.mold_code`.
- **Service:** `ProductionEtaService` — reads the item's events, the profile, and the line state; 1,000 MC paths cost ~30 ms in numpy and should be well under 10 ms in Java. No history scan at request time.
- **Rebuild job:** nightly, under `system_job_lock`; recompute profiles, refit tails, and score finished snapshots.
- **Integration points:** ETA block on plan-item and line DTOs; push on every pallet registration over SSE; replace the 30-minute inactivity rule in `AdminAppStatusMapper` with `state` + `stop_probability`.
- **Testing:** port the backtest harness (bt.py / bt2.py, scratchpad) as a JUnit regression test over a fixture dump; assert the metrics in §6 within tolerance.

---

## 8. Open questions for the factory (unchanged from the investigation, plus two)

1. Does "finish" mean target reached or item closed? (v1.1 assumes target reached.)
2. Why are TT-1R / TT-2R pallets registered in pairs? (Two stacks, two cavities?)
3. Is the product-name prefix really the mold? Are TL3-5 and TL-7, TT-1R and TT-1S different molds?
4. Is there a fixed break around 14:00? Stop rate doubles in that hour.
5. Can FALET from a *different* item end up in a pallet's quantity?
6. Should the ETA freeze or show "paused" during an admin pause?
7. Is TF_LINE_3 physically identical to TF1/TF2? It currently borrows family priors.
8. **New:** why do TT-3 (88%) and TT-20 (100%) items so often close below target — are their targets set deliberately high as a ceiling?
9. **New:** at the 07:00 boundary, 5% of shift ends have no incoming operator; is the morning shift sometimes unstaffed by design (weekly schedule), so the engine can know in advance?
