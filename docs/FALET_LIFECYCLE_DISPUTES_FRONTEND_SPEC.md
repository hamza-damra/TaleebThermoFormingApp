# FALET Lifecycle, Disputes & Shift History — Frontend Handoff

> **Version**: 2.5 — Manager-resolved production FALET special card. Aligned with V35+V36 backend.
> **Audience**: Mobile palletizing app frontend developers.
> **Base URL**: `POST|GET /api/v1/palletizing-line/lines/{lineId}/…`

---

## Table of Contents

1. [Same-Session Return (Product Switch)](#1-same-session-return-product-switch)
2. [Confirmed Previous-Shift Handover](#2-confirmed-previous-shift-handover)
3. [Key Distinction: Same-Session vs Previous-Shift](#3-key-distinction-same-session-vs-previous-shift)
4. [Product-Switch Merge Rule (Precise)](#4-product-switch-merge-rule-precise)
5. [When No First-Pallet Suggestion Is Generated](#5-when-no-first-pallet-suggestion-is-generated)
6. [FALET Screen Visibility & Disputed FALET](#6-falet-screen-visibility--disputed-falet)
6.5. [Manager-Resolved Production FALET](#65-manager-resolved-production-falet)
7. [Dispute Resolution Actions + DISPUTE_RELEASE Origin](#7-dispute-resolution-actions--dispute_release-origin)
8. [Pallet Contribution Breakdown & Attribution](#8-pallet-contribution-breakdown--attribution)
9. [Shift History Page Layout](#9-shift-history-page-layout)
10. [Delay Display Rules](#10-delay-display-rules)
11. [Numbered Example Scenarios](#11-numbered-example-scenarios)
12. [API Request/Response Examples](#12-api-requestresponse-examples)
13. [Frontend Decision Tree](#13-frontend-decision-tree)
14. [Edge Cases, Validation Failures & Arabic Labels](#14-edge-cases-validation-failures--arabic-labels)

---

## 1. Same-Session Return (Product Switch)

### What It Is

The **same operator** switches away from product A to product B during their session. Leftover cartons of A are recorded as FALET. Later in the **same authorization session**, the operator switches back to A. The backend detects this and offers a **same-session continuation** suggestion.

### Business Meaning

- These are the **operator's own cartons** from earlier in the same session
- They are **not** "previous shift cartons" — no handover occurred
- The operator can seamlessly continue filling their pallet

### Suggestion Response

```
matchType: "SAME_SESSION_RETURN"
```

### Frontend Wording (Arabic)

> *"لديك {approvedCartons} عبوة متبقية من وقت سابق في هذه المناوبة. تحتاج {suggestedFreshQuantity} عبوة لإكمال الطبلية."*
> ("You have {approvedCartons} cartons remaining from earlier in this session. You need {suggestedFreshQuantity} cartons to complete the pallet.")

**Do NOT say** "من المناوبة السابقة" (from previous shift) — these are same-session cartons.

---

## 2. Confirmed Previous-Shift Handover

### What It Is

The outgoing operator hands over leftover cartons when ending their shift. The incoming operator **confirms** the handover and selects **the same product**. The backend detects the confirmed handover and offers a **previous-shift continuation** suggestion.

### Business Meaning

- These are cartons from a **different operator on a previous shift**
- They were confirmed as accurate by the incoming operator
- The incoming operator uses them to start their first pallet

### Suggestion Response

```
matchType: "CONFIRMED_HANDOVER"
```

### Frontend Wording (Arabic)

> *"لديك {approvedCartons} عبوة من المناوبة السابقة ({sourceOperatorName}). تحتاج {suggestedFreshQuantity} عبوة طازجة لإكمال الطبلية."*
> ("You have {approvedCartons} cartons from the previous shift ({sourceOperatorName}). You need {suggestedFreshQuantity} fresh cartons to complete the pallet.")

**Do say** "من المناوبة السابقة" — these ARE previous-shift cartons, attributed to the source operator.

---

## 3. Key Distinction: Same-Session vs Previous-Shift

These are **two completely distinct business scenarios**. The frontend must present them differently:

| Aspect | Same-Session Return | Confirmed Handover |
|--------|--------------------|--------------------|
| `matchType` | `SAME_SESSION_RETURN` | `CONFIRMED_HANDOVER` |
| Who produced the cartons? | Same operator (current) | Different operator (previous shift) |
| Handover involved? | No | Yes — confirmed by incoming operator |
| Arabic wording | "متبقية من وقت سابق في هذه المناوبة" | "من المناوبة السابقة ({اسم المشغل})" |
| Show source operator name? | Optional (it's the same person) | **Required** — always show who produced them |
| Attribution on pallet | Both rows attribute to same operator | FALET row → previous op, FRESH row → current op |
| Origin type on FALET | `PRODUCT_SWITCH` | `HANDOVER_LAST_ACTIVE` |

### When to Call the Suggestion Endpoint

```
GET /lines/{lineId}/falet/first-pallet-suggestion
```

Call it:
1. **After a product switch** — when the operator returns to a product they previously switched away from
2. **After confirming a handover + selecting product** — before the operator creates their first pallet

The backend determines which case applies and returns the correct `matchType`.

---

## 4. Product-Switch Merge Rule (Precise)

This merge rule applies **only** to product-switch FALET within the same session. It does **not** apply to handover FALET or cross-session FALET.

### When Merge Happens

An operator switches from A→B→A within the **same authorization session**:
1. First switch (A→B): FALET created for product A, qty = X
2. Second switch (B→A): Instead of creating a new FALET, backend **adds** to the existing one: qty = X + Y

### Merge Conditions (All Must Be True)

| Condition | Required? |
|-----------|-----------|
| Same production line | Yes |
| Same product type | Yes |
| Same authorization session (same `auth.id`) | Yes |
| Existing FALET status is `OPEN` | Yes |
| Origin type is `PRODUCT_SWITCH` | Yes (implicit — session scoping guarantees this) |

### When Merge Does NOT Happen

- **Different authorization** (new session after handover) → new FALET created
- **Different product** → new FALET created
- **Different line** → new FALET created
- **Handover FALET** → never merged with product-switch FALET
- **DISPUTED or RESOLVED FALET** → not eligible for merge

---

## 5. When No First-Pallet Suggestion Is Generated

The suggestion endpoint returns `available = false` with specific reasons:

| `unavailableReason` | Meaning | Frontend Action |
|---------------------|---------|------------------|
| `NO_PRODUCT_SELECTED` | No product is currently selected on the line | Prompt operator to select a product first |
| `NO_ELIGIBLE_FALET` | No OPEN FALET exists on this line at all | Normal pallet creation flow — no special action |
| `NO_MATCHING_FALET_FOR_CURRENT_PRODUCT` | OPEN FALET exists on the line but for a *different* product than the current one | No suggestion — operator proceeds normally; FALET remains visible in FALET screen |
| `OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION` | OPEN FALET exists for the current product but is not eligible for auto-suggestion. Reasons: no verified provenance (not same-session, no confirmed handover), or the FALET is `DISPUTE_RELEASE` (manager-resolved, handled via FALET screen card) | No suggestion — FALET is visible in FALET screen; operator acts manually or via manager-resolved card |

### Important: Non-Matching FALET Is NOT Admin-Decision-Required

When OPEN FALET exists for a different product than the one currently being produced:
- The FALET **remains visible** in the FALET screen (`GET /falet`)
- The operator can see it, but no automatic first-pallet suggestion is generated for it
- This is **not** an error condition and does **not** require automatic admin escalation
- The operator proceeds with normal production on the current product
- When the operator later switches to the matching product, the suggestion will then appear

### When Does Admin/Manager Action Apply?

Admin intervention is appropriate only in specific situations:
- **Disputed FALET** after handover rejection (see §7)
- **Operational decisions** — a manager may choose to dispose or palletize FALET that is no longer needed

For operational decisions, the manager can:
1. **DISPOSE** → marks the FALET as waste if cartons are unusable
2. **PALLETIZE** → creates a pallet from the FALET + optional fresh cartons (requires active auth on line)
3. **Reassign operationally** → instruct the operator to switch to the matching product

> **Note:** `RELEASE` is exclusively a **dispute-resolution** action (see §7). It applies only to FALET that was disputed via handover rejection.

### Verified Provenance Requirement for Auto-Suggestion

Automatic first-pallet suggestion requires one of:
1. **Same-session return** — same operator, same auth, same product (`SAME_SESSION_RETURN`)
2. **Confirmed handover** — incoming operator confirmed a handover that included this FALET (`CONFIRMED_HANDOVER`)

If OPEN FALET exists for the current product but neither condition is met, the backend returns `OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION`. The FALET is still visible and usable via manual `convert-to-pallet`, but no automatic suggestion card appears.

### DISPUTE_RELEASE Is Excluded from Auto-Suggestion

`DISPUTE_RELEASE` FALET is **never** eligible for automatic first-pallet suggestion, even if it matches the current product. It is handled separately through the manager-resolved production FALET card in the FALET screen (see §6.5).

The suggestion endpoint explicitly filters out `DISPUTE_RELEASE` items. If `DISPUTE_RELEASE` FALET exists for the current product (but no other eligible FALET), the response will be `OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION` — because the product matches but the item is intentionally excluded from auto-suggestion. The operator should act on it via the manager-resolved card in the FALET screen.

---

## 6. FALET Screen Visibility & Disputed FALET

### FALET Screen Shows All OPEN FALET (Any Product)

The `GET /falet` endpoint returns **all** OPEN usable FALET items on the line, regardless of whether they match the currently selected product. This means:
- If the line has OPEN FALET for product A and product B, **both** appear in the FALET screen
- The current product selection does **not** filter the FALET screen
- Only the first-pallet suggestion is product-aware (see §5)

> **CRITICAL RULE**: Disputed FALET is completely invisible to the operator app. No items, no counts, no badges, no hints.

### What the Operator App Sees

| Endpoint | What Is Returned |
|----------|-----------------|
| `GET /falet` | Only `OPEN` FALET items. **No** disputed count, **no** badge. |
| `GET /falet/first-pallet-suggestion` | Only considers `OPEN` FALET. DISPUTED is never surfaced. |

### FALET Screen Response

`GET /lines/{lineId}/falet`

| Field | Type | Description |
|-------|------|-------------|
| `faletItems` | Array | All OPEN FALET items on the line — **not filtered by current product** |
| `totalOpenFaletCount` | int | Count of all OPEN items (across all products) |
| `hasOpenFalet` | boolean | Whether any OPEN FALET exists on the line |
| `managerResolvedFaletCount` | int | Count of OPEN items with `originType = DISPUTE_RELEASE` (subset of totalOpenFaletCount) |

**There is no `disputedFaletCount` field.** The operator app has zero awareness of disputed FALET.

> **Key point:** The FALET screen is product-agnostic. It shows all OPEN FALET. Only the first-pallet suggestion endpoint is product-aware. Manager-resolved items are included in the list but marked distinctly (see §6.5).

### Where Disputed FALET IS Visible

- **Admin web portal** (`/web/admin/falet-disputes`) — full dispute list + detail pages
- **Admin API** (if applicable) — dispute management endpoints

### FALET Item Response Fields (Operator-Facing)

| Field | Type | Description |
|-------|------|-------------|
| `faletId` | Long | Unique FALET state ID |
| `productTypeId` | Long | Product type FK |
| `productTypeName` | String | Human-readable product name |
| `quantity` | int | Current carton count |
| `status` | String | Always `OPEN` in operator responses |
| `originType` | String | `PRODUCT_SWITCH`, `HANDOVER_LAST_ACTIVE`, or `DISPUTE_RELEASE` |
| `sourceOperatorName` | String | Name of the **original source operator** who produced / handed over the cartons. This applies to all origin types including `DISPUTE_RELEASE` — the release action changes availability/origin state, but does not change original carton attribution. |
| `authorizationId` | Long | ID of the authorization session that created this FALET |
| `managerResolved` | boolean | `true` if `originType = DISPUTE_RELEASE`. Frontend uses this to render a special manager-resolved card. |
| `createdAt` / `updatedAt` | ISO-8601 | Timestamps |
| `createdAtDisplay` / `updatedAtDisplay` | String | Arabic-formatted timestamps |

### Visibility Matrix

| FALET Status | `GET /falet` | `GET /first-pallet-suggestion` | Admin Portal |
|-------------|-------------|-------------------------------|-------------|
| `OPEN` (ordinary) | **Yes** | **Yes** (if product matches + provenance) | Yes |
| `OPEN` (`DISPUTE_RELEASE`) | **Yes** (as manager-resolved card) | **No** (excluded from auto-suggestion) | Yes |
| `DISPUTED` | **No** | **No** | **Yes** |
| `RESOLVED` | **No** | **No** | Yes (history) |

---

## 6.5. Manager-Resolved Production FALET

### What It Is

When a manager/admin resolves a dispute by **releasing** quantity back for production, the resulting FALET item has `originType = DISPUTE_RELEASE`. This is a **semantically distinct** category from ordinary OPEN FALET.

It means:
- A dispute occurred (handover rejection)
- The manager reviewed and decided the cartons should be produced / continued
- The cartons are now usable again — but **not** through normal same-session or confirmed-handover paths
- The manager will instruct the operator to open the FALET screen and act on this item

### How It Differs from Ordinary FALET

| Aspect | Ordinary OPEN FALET | Manager-Resolved FALET |
|--------|---------------------|------------------------|
| Origin | `PRODUCT_SWITCH` or `HANDOVER_LAST_ACTIVE` | `DISPUTE_RELEASE` |
| Auto-suggestion eligible | Yes (if provenance verified) | **No** — excluded from suggestion endpoint |
| `managerResolved` flag | `false` | `true` |
| How operator discovers it | Auto-suggestion card or FALET screen | **FALET screen only** — manager tells operator to check |
| Wording | Same-session / previous-shift language | Manager-resolved / manager-directed language |
| Source attribution | Original producer | **Still original producer** — release does NOT change attribution |

### Frontend Card Rendering

When `managerResolved = true`, render the item as a **distinctive special card** in the FALET screen:

**Suggested UI elements:**
- Manager badge or special styling (e.g., different card color/border)
- Quantity released for production
- Product name
- Source operator name (original producer, NOT the manager)
- Message indicating manager-directed production

**Suggested Arabic wording:**

| Element | Arabic | English equivalent |
|---------|--------|--------------------|
| Card title | فالت معالج من المدير | Manager-resolved FALET |
| Instruction | هذه الكمية تم اعتمادها للإنتاج بقرار من المدير | This quantity was approved for production by manager decision |
| Action prompt | أكمل عليها من إنتاج المناوبة الحالية | Complete it from current shift production |

### Important: NOT the Same as Auto-Suggestion Wording

Do **not** use the same wording as:
- `SAME_SESSION_RETURN` → "كرتونات متبقية في هذه المناوبة" (same-session cartons)
- `CONFIRMED_HANDOVER` → "كرتونات المناوبة السابقة" (previous-shift cartons)

Manager-resolved FALET requires its own distinct wording that communicates:
1. The cartons came from a dispute that was resolved
2. A manager approved them for production
3. The operator should use them in current shift production

### Attribution Separation

For `DISPUTE_RELEASE` items:

| Attribution type | Who | Where stored |
|-----------------|-----|-------------|
| **Source attribution** | Original operator who produced/handed over the cartons | `sourceOperatorName` on FALET item |
| **Decision attribution** | Manager/admin who released the quantity | `FaletDisputeAction.performedByUser` (admin-only) |
| **Fresh attribution** | Current active operator (only if fresh cartons added during palletization) | Pallet contribution breakdown |

### Disposal: Not Visible

When a manager **disposes** disputed FALET:
- Quantity is removed from the operator-visible usable pool
- No FALET card shown to operator
- No suggestion generated
- No production use allowed
- Audit/history preserved: original source operator, disposal decision, quantity
- Operator app sees nothing — disposal is fully backend/admin-side

---

## 7. Dispute Resolution Actions + DISPUTE_RELEASE Origin

### Trigger: Handover Rejection

`POST /lines/{lineId}/handover/{id}/reject`

1. All OPEN FALET states from the handover snapshots → status becomes `DISPUTED`
2. A `FaletDispute` record created with status `OPEN`
3. `FaletDisputeItem` records link each disputed FALET
4. Quantity counters initialized: `heldQty = totalDisputedQty`
5. Operator app immediately sees zero FALET for this line (fully hidden)

### Dispute Statuses

| Status | Arabic | Description |
|--------|--------|-------------|
| `OPEN` | مفتوح | All items pending |
| `PARTIALLY_RESOLVED` | محلول جزئياً | Some items resolved |
| `RESOLVED` | محلول | All quantity resolved |

### Manager Actions (Admin Portal Only)

| Action | Arabic | Effect | Creates Pallet? |
|--------|--------|--------|----------------|
| `DISPOSE` | إتلاف | Reduces FALET quantity, marks as waste | No |
| `PALLETIZE` | تنصيب | Creates pallet from disputed FALET + optional fresh | **Yes** |
| `RELEASE` | إرجاع | Creates new OPEN FALET with `DISPUTE_RELEASE` origin | No |
| `HOLD` | تعليق | Keeps on hold (no quantity change) | No |

### RELEASE Action — Creates `DISPUTE_RELEASE` FALET

When a manager RELEASEs disputed FALET:
1. The original disputed FALET state is reduced by the released quantity (set to `RESOLVED` if fully consumed)
2. A **new** OPEN FALET state is created with the released quantity
3. The new FALET has **`originType = DISPUTE_RELEASE`** — not `RECEIVED_FROM_HANDOVER`
4. It becomes visible in `GET /falet` as a manager-resolved special card (`managerResolved = true`), but is **excluded** from automatic first-pallet suggestions (see §5 and §6.5)

**Why `DISPUTE_RELEASE` and not `RECEIVED_FROM_HANDOVER`?** Because this FALET was disputed and then released by a manager — it has different provenance than a normally-received handover FALET. The frontend and admin reports can distinguish manager-released FALET from regular handover FALET.

### FALET Origin Types (Complete List)

| Value | Arabic | When Created |
|-------|--------|-------------|
| `PRODUCT_SWITCH` | تبديل منتج | Operator switches to a different product |
| `HANDOVER_LAST_ACTIVE` | تسليم آخر منتج | Outgoing operator creates handover |
| `RECEIVED_FROM_HANDOVER` | مستلم من التسليم | *Exists in enum but not currently written to any `FaletCurrentState`* — confirm does not change origin |
| `DISPUTE_RELEASE` | إفراج نزاع | Manager releases disputed FALET back to production |

### PALLETIZE with Fresh Quantity

When a manager palletizes disputed FALET, they can optionally add fresh cartons:
- The pallet gets two breakdown rows: `DISPUTE_RESOLUTION` + `FRESH`
- `DISPUTE_RESOLUTION` row → tracks the original FALET producer as `sourceOperator`
- `FRESH` row → tracks the currently active operator on the line as `sourceOperator`
- **Requires** an active authorization on the line (for fresh cartons and serial generation)

---

## 8. Pallet Contribution Breakdown & Attribution

### Contribution Sources

| Value | Arabic | Description |
|-------|--------|-------------|
| `FRESH` | إنتاج طازج | Fresh production by the current operator |
| `APPROVED_FALET` | فالت معتمد | Cartons carried from a previous shift/switch FALET |
| `DISPUTE_RESOLUTION` | تسوية نزاع | Cartons resolved from a disputed FALET by manager |

### Breakdown Fields

| Field | Description |
|-------|-------------|
| `contributionSource` | One of the three sources above |
| `looseQuantityUsed` | Cartons consumed from the FALET |
| `freshQuantityAdded` | Fresh cartons added by current operator |
| `finalPalleteQuantity` | Total pallet quantity |
| `sourceOperator` | Operator who produced the source cartons |
| `sourceOperatorNameSnapshot` | Snapshot of operator name at creation time |
| `sourceAuthorization` | Authorization session that produced the source cartons |
| `sourceHandover` | Handover that transferred the FALET (if applicable) |
| `faletCurrentState` | Link to the FALET state consumed |

### Attribution Rules

| Scenario | FALET Row `sourceOperator` | FRESH Row `sourceOperator` |
|----------|---------------------------|---------------------------|
| Same-session return | Current operator (same person) | Current operator (same person) |
| Confirmed handover | **Previous-shift operator** | Current operator |
| Dispute resolution (PALLETIZE) | **Original FALET producer** | Current active operator on line |

### Frontend Warning: Do Not Derive User Labels from `contributionSource` Alone

> **Important:** The frontend must **not** decide user-facing wording from `contributionSource` alone.
> For the first-pallet suggestion UI, always use **`matchType`** and the suggestion context to choose the correct Arabic wording:
> - `SAME_SESSION_RETURN` → "كرتونات متبقية في هذه المناوبة" (same-session cartons)
> - `CONFIRMED_HANDOVER` → "كرتونات المناوبة السابقة" (previous-shift cartons)
>
> The breakdown value `APPROVED_FALET` appears in **both** business contexts. If the frontend displays wording based only on `APPROVED_FALET`, it will incorrectly show same-session cartons as "previous shift" or vice versa.

### Example Breakdown

A pallet of 18 cartons made from 7 approved FALET (from Khaled) + 11 fresh (by Ahmad):

| Row | Source | looseQtyUsed | freshQtyAdded | sourceOperatorName |
|-----|--------|-------------|---------------|-------------------|
| 1 | `APPROVED_FALET` | 7 | 0 | Khaled (previous shift) |
| 2 | `FRESH` | 0 | 11 | Ahmad (current operator) |

---

## 9. Shift History Page Layout

### Data Source

`GET /web/admin/shift-history?date=2025-06-15`

Backend returns `ShiftExecutionSnapshotResponse` objects grouped by business date and shift type.

### Page Structure

```
┌─────────────────────────────────────────────────────────┐
│  ◀ 2025-06-14    [ 2025-06-15 ]    2025-06-16 ▶       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ━━ صباحي (MORNING) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                                         │
│  ┌─ Line 1 ────────────────────────────────────────┐   │
│  │ Operator: Ahmad                                  │   │
│  │ Auth: 06:05 → 14:10  │  Ending: HANDOVER        │   │
│  │ Pallets: 12  │  Fresh: 204  │  FALET used: 7    │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌─ Line 2 ────────────────────────────────────────┐   │
│  │ Operator: Khaled                                 │   │
│  │ Auth: 06:02 → 14:05  │  Ending: HANDOVER        │   │
│  │ Pallets: 10  │  Fresh: 180  │  FALET used: 0    │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ━━ مسائي (EVENING) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                                         │
│  ┌─ Line 1 ────────────────────────────────────────┐   │
│  │ Operator: Omar                                   │   │
│  │ Auth: 14:20 → 22:05  │  Ending: HANDOVER        │   │
│  │ Pallets: 11  │  Fresh: 198  │  FALET used: 5    │   │
│  │ ⚠ Delay: 20 min — تجاوز المناوبة السابقة         │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌─ Line 2 ────────────────────────────────────────┐   │
│  │ (no snapshot — line was idle this shift)          │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ━━ ليلي (NIGHT) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  (no snapshots — no operators were active)              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Layout Rules

- **Grouped by business date** — one page per day, navigable with prev/next + date picker
- **3 shift sections per day**: MORNING (صباحي), EVENING (مسائي), NIGHT (ليلي)
- **Inside each shift**: one card per line (Line 1, Line 2)
- If a line had no operator during a shift → show an empty placeholder
- If a line had no operator all day → still show the empty slot
- **One operator can appear on both lines** in the same shift (if they switched lines)
- **Different operators per line** is the normal case

### Per-Snapshot Card Fields

| Field | Display |
|-------|---------|
| `lineName` | Card title: "Line 1" / "Line 2" |
| `operatorName` | Operator name |
| `authStartedAtDisplay` – `authEndedAtDisplay` | Time range |
| `endingReason` | How the session ended |
| `palletsCompleted` | Count |
| `freshCartonsProduced` | Fresh cartons only (excludes FALET) |
| `carriedFaletCartonsUsed` | FALET cartons used in pallets |
| `faletHandedOver` | Flag: FALET was present at handover |
| `disputedFaletExisted` | Flag: disputes existed on line |
| `pickupDelayMinutes` | Only show if `delayDisplayEligible = true` |
| `previousShiftOverrun` / `uncoveredGap` | Delay classification |

### Shift Classification Rule

The **official shift type** is determined by where the operator's **authorization start time** (`authorizedAt`) falls in the active shift schedule profile:

- Compare auth start time against shift definitions in the active `ShiftScheduleProfile`
- The shift whose time window contains the auth start time becomes the official shift
- **Do NOT** use "past half the shift = next shift" logic

### Production Metrics

- **`freshCartonsProduced`** = (total pallet cartons under this auth) − `carriedFaletCartonsUsed`
- **`carriedFaletCartonsUsed`** = sum of `looseQuantityUsed` from breakdowns with `contributionSource = APPROVED_FALET` for this authorization

---

## 10. Delay Display Rules

| Pickup Delay | `delayDisplayEligible` | Frontend Display |
|-------------|----------------------|------------------|
| 0 minutes | `false` | Nothing — operator started on time |
| 1–10 minutes | `false` | **Do not show** — within acceptable tolerance |
| > 10 minutes | `true` | Show delay with classification |

### Delay Classification

When `delayDisplayEligible = true`, the snapshot includes:

| Flag | Arabic | Meaning |
|------|--------|---------|
| `previousShiftOverrun` | تجاوز المناوبة السابقة | Previous operator ran late; current operator waited |
| `uncoveredGap` | فجوة غير مغطاة | No one was on the line before this operator |

Both **cannot** be `true` simultaneously. Display:

- If `previousShiftOverrun`: *"تأخير {pickupDelayMinutes} دقيقة — بسبب تجاوز المناوبة السابقة"*
- If `uncoveredGap`: *"تأخير {pickupDelayMinutes} دقيقة — فجوة غير مغطاة"*

---

## 11. Numbered Example Scenarios

### Scenario 1: Same-session return → first-pallet continuation

1. Operator **Ahmad** is on Line 1, product Red (pkg qty = 18)
2. Ahmad has produced 5 cartons of Red, then switches to Blue
3. Backend creates FALET: `{faletId: 1, product: Red, qty: 5, origin: PRODUCT_SWITCH, auth: Ahmad's session}`
4. Ahmad works on Blue, creates pallets
5. Ahmad switches **back to Red**
6. Frontend calls `GET /falet/first-pallet-suggestion`
7. Response: `{available: true, matchType: "SAME_SESSION_RETURN", approvedCartons: 5, suggestedFreshQuantity: 13}`
8. Frontend shows: *"لديك 5 كرتونات متبقية من وقت سابق في هذه المناوبة. تحتاج 13 عبوة لإكمال الطبلية."*
9. Ahmad produces 13 fresh cartons → pallet created (5 FALET + 13 fresh)
10. Breakdown: `[{source: APPROVED_FALET, loose: 5, sourceOp: Ahmad}, {source: FRESH, fresh: 13, sourceOp: Ahmad}]`

### Scenario 2: Confirmed handover + same product → first-pallet suggestion

1. Operator **Khaled** on Line 1, product Red, has 7 leftover cartons
2. Khaled creates handover → FALET recorded: `{qty: 7, auth: Khaled, origin: HANDOVER_LAST_ACTIVE}`
3. Operator **Ahmad** arrives, confirms handover, selects product Red
4. Frontend calls `GET /falet/first-pallet-suggestion`
5. Response: `{available: true, matchType: "CONFIRMED_HANDOVER", approvedCartons: 7, suggestedFreshQuantity: 11, sourceOperatorName: "Khaled"}`
6. Frontend shows: *"لديك 7 كرتونات من المناوبة السابقة (خالد). تحتاج 11 عبوة طازجة لإكمال الطبلية."*
7. Ahmad produces 11 fresh cartons → pallet created
8. Breakdown: `[{source: APPROVED_FALET, loose: 7, sourceOp: Khaled}, {source: FRESH, fresh: 11, sourceOp: Ahmad}]`

### Scenario 3: Handover + different product → no suggestion, FALET stays visible

1. Operator **Khaled** on Line 1, product Red, has 7 leftover cartons → FALET created
2. Khaled creates handover
3. Operator **Ahmad** arrives, confirms handover, selects product **Blue** (different!)
4. `GET /falet` returns: `{faletItems: [{product: "Red", qty: 7, status: "OPEN"}], totalOpenFaletCount: 1}` — **Red FALET visible**
5. Frontend calls `GET /falet/first-pallet-suggestion`
6. Response: `{available: false, unavailableReason: "NO_MATCHING_FALET_FOR_CURRENT_PRODUCT"}`
7. No suggestion card shown. Ahmad proceeds with normal Blue production.
8. If Ahmad later switches to Red, the suggestion will then become available.

### Scenario 8: Multi-product FALET on line

**Setup:** Outgoing shift handed over FALET for product A (5 cartons) and product B (7 cartons). Both are OPEN.

**Case 1: Current product = A**
1. `GET /falet` → shows both A (5) and B (7)
2. `GET /falet/first-pallet-suggestion` → `{available: true, matchType: "CONFIRMED_HANDOVER", approvedCartons: 5, productTypeName: "A"}`
3. Suggestion only for A; B remains visible in FALET screen but not suggested

**Case 2: Current product = B**
1. `GET /falet` → shows both A (5) and B (7)
2. `GET /falet/first-pallet-suggestion` → `{available: true, matchType: "CONFIRMED_HANDOVER", approvedCartons: 7, productTypeName: "B"}`
3. Suggestion only for B; A remains visible in FALET screen but not suggested

**Case 3: Current product = C (no matching FALET)**
1. `GET /falet` → shows both A (5) and B (7)
2. `GET /falet/first-pallet-suggestion` → `{available: false, unavailableReason: "NO_MATCHING_FALET_FOR_CURRENT_PRODUCT"}`
3. No suggestion shown. Both A and B remain visible in FALET screen.

### Scenario 4: Handover rejection → dispute → RELEASE → manager-resolved card

1. Khaled hands over 10 cartons of Red as FALET
2. Ahmad rejects the handover
3. Backend: FALET status → `DISPUTED`, dispute created
4. `GET /falet` returns: `{faletItems: [], totalOpenFaletCount: 0, hasOpenFalet: false}` — **no dispute info exposed**
5. Manager goes to admin portal → sees dispute
6. Manager **RELEASEs** 10 cartons → new OPEN FALET created with `originType: "DISPUTE_RELEASE"`
7. `GET /falet` now returns:
   - `faletItems: [{qty: 10, status: "OPEN", originType: "DISPUTE_RELEASE", managerResolved: true, sourceOperatorName: "Khaled"}]`
   - `totalOpenFaletCount: 1`, `managerResolvedFaletCount: 1`
8. Frontend renders a **special manager-resolved card** — not a normal suggestion card
9. `GET /falet/first-pallet-suggestion` returns `{available: false, unavailableReason: "OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION"}` — DISPUTE_RELEASE excluded from auto-suggestion
10. Manager instructs Ahmad to open FALET screen and act on the manager-resolved card
11. Ahmad opens FALET screen, sees the special card, and converts to pallet with fresh cartons
12. Source attribution: FALET part → Khaled (original), fresh part → Ahmad (current)

### Scenario 5: Manager palletizes disputed FALET with fresh cartons

1. FALET of 8 cartons (Red) is in dispute on Line 1
2. Manager decides to palletize with 10 additional fresh cartons
3. Active operator Ahmad is currently on Line 1
4. Pallet created: 8 disputed + 10 fresh = 18 total
5. Breakdown: `[{source: DISPUTE_RESOLUTION, loose: 8, sourceOp: Khaled}, {source: FRESH, fresh: 10, sourceOp: Ahmad}]`

### Scenario 9: Manager full disposal

1. Khaled hands over 5 cartons of product A as FALET
2. Ahmad rejects the handover → dispute created
3. Manager reviews and decides full **DISPOSE**
4. Backend: disputed FALET quantity → disposed, status → RESOLVED
5. `GET /falet` returns: `{faletItems: [], totalOpenFaletCount: 0, hasOpenFalet: false}`
6. No FALET card, no suggestion, no production use
7. Audit/history preserved: original source = Khaled, decision actor = manager, disposed quantity = 5

### Scenario 10: Manager release + operator adds fresh cartons later

1. Khaled handed over 5 cartons of product A → dispute → manager releases all 5
2. FALET screen shows: `{qty: 5, originType: "DISPUTE_RELEASE", managerResolved: true, sourceOperatorName: "Khaled"}`
3. Ahmad adds 13 fresh cartons and creates a pallet of 18
4. Pallet contribution breakdown:
   - `{source: APPROVED_FALET, loose: 5, sourceOp: "Khaled"}` — original source preserved
   - `{source: FRESH, fresh: 13, sourceOp: "Ahmad"}` — fresh part attributed to current operator
5. Manager is decision actor only — not in pallet source attribution

### Scenario 6: Pickup delay > 10 minutes with overrun

1. Morning shift scheduled 06:00–14:00
2. Previous operator Khaled finishes at **14:15** (15-minute overrun)
3. Ahmad starts at **14:20** on evening shift (14:00–22:00)
4. Pickup delay = 20 minutes, `delayDisplayEligible = true`, `previousShiftOverrun = true`
5. Display: *"تأخير 20 دقيقة — بسبب تجاوز المناوبة السابقة"*

### Scenario 7: Pickup delay ≤ 10 minutes — not displayed

1. Morning shift scheduled 06:00–14:00
2. Ahmad starts at **06:08** (8 minutes late)
3. Pickup delay = 8 minutes, `delayDisplayEligible = false`
4. Frontend: **nothing displayed** — within 10-minute tolerance

---

## 12. API Request/Response Examples

### GET /lines/{lineId}/falet

```json
{
  "success": true,
  "data": {
    "faletItems": [
      {
        "faletId": 42,
        "productTypeId": 5,
        "productTypeName": "Red 20kg",
        "quantity": 7,
        "status": "OPEN",
        "originType": "PRODUCT_SWITCH",
        "sourceOperatorName": "Khaled",
        "authorizationId": 100,
        "managerResolved": false,
        "createdAt": "2025-06-15T10:30:00.000+03:00",
        "createdAtDisplay": "15/06 10:30",
        "updatedAt": "2025-06-15T10:30:00.000+03:00",
        "updatedAtDisplay": "15/06 10:30"
      }
    ],
    "totalOpenFaletCount": 1,
    "hasOpenFalet": true,
    "managerResolvedFaletCount": 0
  }
}
```

**Manager-resolved FALET in screen:**
```json
{
  "success": true,
  "data": {
    "faletItems": [
      {
        "faletId": 55,
        "productTypeId": 5,
        "productTypeName": "Red 20kg",
        "quantity": 10,
        "status": "OPEN",
        "originType": "DISPUTE_RELEASE",
        "sourceOperatorName": "Khaled",
        "authorizationId": 80,
        "managerResolved": true,
        "createdAt": "2025-06-15T12:00:00.000+03:00",
        "createdAtDisplay": "15/06 12:00",
        "updatedAt": "2025-06-15T12:00:00.000+03:00",
        "updatedAtDisplay": "15/06 12:00"
      }
    ],
    "totalOpenFaletCount": 1,
    "hasOpenFalet": true,
    "managerResolvedFaletCount": 1
  }
}
```

**Note:** No `disputedFaletCount` field. Operator app has zero visibility into disputed FALET.

### GET /lines/{lineId}/falet/first-pallet-suggestion

**Same-session return:**
```json
{
  "success": true,
  "data": {
    "available": true,
    "faletId": 42,
    "productTypeId": 5,
    "productTypeName": "Red 20kg",
    "approvedCartons": 5,
    "defaultPalletQuantity": 18,
    "suggestedFreshQuantity": 13,
    "sourceOperatorName": "Ahmad",
    "originType": "PRODUCT_SWITCH",
    "matchType": "SAME_SESSION_RETURN"
  }
}
```

**Confirmed handover:**
```json
{
  "success": true,
  "data": {
    "available": true,
    "faletId": 43,
    "productTypeId": 5,
    "productTypeName": "Red 20kg",
    "approvedCartons": 7,
    "defaultPalletQuantity": 18,
    "suggestedFreshQuantity": 11,
    "sourceOperatorName": "Khaled",
    "originType": "HANDOVER_LAST_ACTIVE",
    "matchType": "CONFIRMED_HANDOVER"
  }
}
```

**Unavailable (no matching FALET for current product):**
```json
{
  "success": true,
  "data": {
    "available": false,
    "unavailableReason": "NO_MATCHING_FALET_FOR_CURRENT_PRODUCT"
  }
}
```

**Unavailable (matching FALET exists but no verified provenance):**
```json
{
  "success": true,
  "data": {
    "available": false,
    "unavailableReason": "OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION"
  }
}
```

### POST /lines/{lineId}/falet/convert-to-pallet

**Request:**
```json
{
  "faletId": 42,
  "additionalFreshQuantity": 11
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "pallet": {
      "palletId": 500,
      "scannedValue": "001000000042",
      "quantity": 18,
      "currentDestination": "PRODUCTION"
    },
    "creationMode": "FROM_FALET_PLUS_FRESH",
    "faletQuantityUsed": 7,
    "freshQuantityAdded": 11,
    "finalQuantity": 18,
    "faletId": 42
  }
}
```

---

## 13. Frontend Decision Tree

```
Operator authorizes on line
  │
  ├─ Is there a pending handover?
  │   ├─ YES → Show handover confirmation screen
  │   │   ├─ Operator CONFIRMS
  │   │   │   ├─ Operator selects product
  │   │   │   │   └─ Call GET /falet/first-pallet-suggestion
  │   │   │   │       ├─ available=true, matchType=CONFIRMED_HANDOVER
  │   │   │   │       │   → Show "كرتونات المناوبة السابقة" suggestion card
  │   │   │   │       ├─ NO_MATCHING_FALET → No suggestion; FALET visible in screen
  │   │   │   │       └─ NO_ELIGIBLE_FALET → Normal pallet flow
  │   │   │   └─ (continue normal production)
  │   │   └─ Operator REJECTS
  │   │       └─ FALET becomes DISPUTED (fully hidden from operator)
  │   │           └─ Operator sees nothing — dispute handled by admin
  │   └─ NO → Normal flow
  │
  ├─ Operator performs product switch
  │   ├─ FALET recorded for old product
  │   └─ If switching back to same product:
  │       └─ Call GET /falet/first-pallet-suggestion
  │           ├─ available=true, matchType=SAME_SESSION_RETURN
  │           │   → Show "كرتونات متبقية في هذه المناوبة" suggestion card
  │           └─ available=false → Normal flow
  │
  ├─ Creating a pallet with FALET suggestion
  │   └─ POST /falet/convert-to-pallet (faletId + freshQty)
  │       └─ Pallet created with full attribution breakdown
  │
  ├─ Viewing FALET screen
  │   └─ GET /falet
  │       ├─ Ordinary items → normal FALET cards
  │       └─ managerResolved=true → special manager-resolved card
  │           ├─ Show "فالت معالج من المدير" title
  │           ├─ Show quantity + product + source operator
  │           └─ Operator converts via POST /falet/convert-to-pallet
  │
  └─ Manager instructs operator to check FALET screen
      └─ Operator opens FALET screen → sees manager-resolved card → acts
```

---

## 14. Edge Cases, Validation Failures & Arabic Labels

### Error Codes

| Code | Arabic Message | When |
|------|---------------|------|
| `FALET_NOT_FOUND` | الفالت غير موجود | Convert/dispose non-existent FALET |
| `FALET_ALREADY_RESOLVED` | الفالت محلول مسبقاً | Convert/dispose already-resolved FALET |
| `FALET_LINE_MISMATCH` | الفالت لا ينتمي لهذا الخط | FALET belongs to different line |
| `FALET_DISPUTE_NOT_FOUND` | النزاع غير موجود | Dispute ID not found |
| `FALET_DISPUTE_ALREADY_RESOLVED` | النزاع محلول مسبقاً | Action on resolved dispute |
| `FALET_DISPUTE_ITEM_NOT_FOUND` | عنصر النزاع غير موجود | Item not in dispute |
| `FALET_DISPUTE_ITEM_FULLY_RESOLVED` | عنصر النزاع محلول بالكامل | No remaining qty on item |
| `FALET_DISPUTE_QUANTITY_EXCEEDS_REMAINING` | الكمية تتجاوز المتبقي | qty > remaining |
| `FALET_DISPUTE_NO_ACTIVE_AUTH_FOR_PALLETIZE` | يتطلب تفويض نشط للتنصيب | PALLETIZE without active auth |

### Edge Cases

| Case | Backend Behavior |
|------|-----------------|
| FALET qty ≥ default pallet qty | `suggestedFreshQuantity = 0` — no fresh needed |
| FALET qty = 0 | Cannot happen (FALET with qty 0 is auto-RESOLVED) |
| Multiple OPEN FALET for same product on line | Only one per line+product+auth; merge guarantees uniqueness within a session |
| Multiple OPEN FALET for *different* products on line | All visible in FALET screen; suggestion only for the one matching current product |
| Handover with no FALET | Suggestion returns `NO_ELIGIBLE_FALET` — normal flow |
| Auth released without pallets | Snapshot still captured with `palletsCompleted = 0` |
| Midnight-crossing shift | Shift schedule handles correctly; business date from auth start |
| DISPUTED FALET exists but no OPEN FALET | Operator sees empty FALET screen; suggestion returns `NO_ELIGIBLE_FALET` |
| Manager releases disputed FALET | New OPEN FALET with `DISPUTE_RELEASE` origin; visible as manager-resolved card, **excluded** from auto-suggestion |
| Manager disposes disputed FALET | Quantity removed from usable pool; not visible to operator; audit/history preserved |
| DISPUTE_RELEASE + confirmed handover same product | DISPUTE_RELEASE still excluded from suggestion; only ordinary OPEN FALET eligible |

### Arabic Labels Reference

| Concept | Arabic |
|---------|--------|
| FALET | فالت |
| FALET Screen | شاشة الفالت |
| FALET Disputes | نزاعات الفالت |
| First-Pallet Suggestion | اقتراح الطبلية الأولى |
| Same-Session Cartons | كرتونات متبقية في هذه المناوبة |
| Previous-Shift Cartons | كرتونات المناوبة السابقة |
| Shift History | سجل الورديات |
| Open | مفتوح |
| Disputed | متنازع عليه |
| Partially Resolved | محلول جزئياً |
| Resolved | محلول |
| Dispose | إتلاف |
| Palletize | تنصيب |
| Release | إرجاع |
| Hold | تعليق |
| Product Switch | تبديل منتج |
| Handover Last Active | تسليم آخر منتج |
| Received from Handover | مستلم من التسليم |
| Dispute Release | إفراج نزاع |
| Fresh Production | إنتاج طازج |
| Approved FALET | فالت معتمد |
| Dispute Resolution | تسوية نزاع |
| Outgoing Operator | المشغل المسلِّم |
| Incoming Operator | المشغل المستلِم |
| Disputed Quantity | الكمية المتنازع عليها |
| Remaining | المتبقي |
| Morning Shift | صباحي |
| Evening Shift | مسائي |
| Night Shift | ليلي |
| Pickup Delay | تأخير الاستلام |
| Previous Shift Overrun | تجاوز المناوبة السابقة |
| Uncovered Gap | فجوة غير مغطاة |
| Contribution Breakdown | تفصيل المساهمة |
| Source Operator | المشغل المصدر |
| No Matching FALET | لا يوجد فالت مطابق |
| Not Eligible for Auto-Suggestion | غير مؤهل للاقتراح التلقائي |
| Manager-Resolved FALET | فالت معالج من المدير |
| Manager-Approved for Production | هذه الكمية تم اعتمادها للإنتاج بقرار من المدير |
| Complete from Current Shift | أكمل عليها من إنتاج المناوبة الحالية |
