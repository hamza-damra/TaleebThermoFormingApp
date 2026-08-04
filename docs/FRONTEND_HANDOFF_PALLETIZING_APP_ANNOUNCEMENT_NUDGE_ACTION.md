build arm64 v8a release production vertion so the base url is taleeb.me

# Frontend Handoff — Palletizing App — Manager-Announcement Nudge `action`

## 1. Executive Summary

**What changed in the backend.** Manager announcements are now *timed*: every announcement carries an
absolute `expiresAt`, and the sanitized SSE nudge this app already receives gains an additive
**`action`** field describing what happened to the announcement (`CREATED` / `UPDATED` /
`DEACTIVATED` / `DELETED`). Previously the nudge only ever meant "one was created".

**Why this app must change.** Strictly speaking it does **not have to**. The change is additive and the
app's existing behaviour — refetch the generic pending notice when a nudge arrives — remains correct
for every action value. This handoff exists because the app's SSE contract changed and that must be
documented rather than discovered.

**Business problem solved.** An announcement that has been switched off, deleted, or retargeted to
another department previously produced no signal at all for this app, so a generic notice could linger
until the next natural refetch. Now every lifecycle step produces a nudge.

**Required before production rollout?** **No.** Backend may deploy first; this app keeps working
unchanged.

## 2. Affected App

**Palletizing App.**

Related apps, documented separately:

- Roll Production App → `FRONTEND_HANDOFF_ROLL_PRODUCTION_APP_TIMED_MANAGER_ANNOUNCEMENTS.md`
- Thermoforming Operator App → `FRONTEND_HANDOFF_OPERATOR_APP_THERMOFORMING_MANAGER_NOTE_AND_ANNOUNCEMENT_TICKER.md`
- Roll Worker App → `FRONTEND_HANDOFF_ROLL_WORKER_APP_ANNOUNCEMENT_NUDGE_ACTION.md`

Explicitly **unaffected**: Warehouse App, Admin App.

## 3. Business Context

A manager posts an urgent announcement targeted at the **Thermoforming** department. The palletizing
station is not the audience, so it must never see the message body or the sender — it receives only a
sanitized "there is an urgent notice for the operator" marker so the station is aware something is
happening on the line. That privacy split is unchanged.

What is new is that the manager can now also **time** the announcement, **edit** it, **switch it off**,
or **move it to another department** — and each of those now reaches the station as a nudge.

## 4. Backend Contract Changes

### 4.1 SSE nudge — `urgent-manager-announcement`

Stream: `GET /api/v1/palletizing-line/events` (unchanged; device-key authenticated).
SSE event name: `urgent-manager-announcement` (**unchanged**).

**Before**

```jsonc
{
  "eventType": "URGENT_MANAGER_ANNOUNCEMENT_CREATED",
  "announcementId": 99,
  "targetDomain": "THERMOFORMING",
  "priority": "URGENT"
}
```

**Now**

```jsonc
{
  "eventType": "URGENT_MANAGER_ANNOUNCEMENT_CREATED",
  "announcementId": 99,
  "targetDomain": "THERMOFORMING",
  "priority": "URGENT",
  "action": "CREATED"                 // ← NEW: CREATED | UPDATED | DEACTIVATED | DELETED
}
```

**`eventType` is a frozen legacy literal.** It still reads `..._CREATED` for every action, deliberately,
so deployed builds keep matching it. New code should branch on `action`.

The frame still carries **no `message`, no `messageBody`, no `senderDisplayName`, no `title`** — those
fields do not exist on the event type, so they cannot leak.

### 4.2 Generic pending endpoint — unchanged route, two new fields

`GET /api/v1/palletizing-line/urgent-announcements/pending?lineId={lineId}`

```jsonc
{
  "success": true,
  "data": [
    {
      "id": 99,
      "targetDomain": "THERMOFORMING",
      "title": "ملاحظة عاجلة من المدير",
      "message": "أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.",
      "createdAt": "2026-07-31T09:00:00.000Z",
      "createdAtDisplay": "2026-07-31، 12:00 مساءً",
      "expiresAt": "2026-07-31T11:00:00.000Z",       // ← NEW (null on a legacy row)
      "expiresAtDisplay": "2026-07-31، 02:00 مساءً",  // ← NEW (null on a legacy row)
      "priority": "URGENT"
    }
  ],
  "error": null
}
```

`title` and `message` remain **fixed generic constants** — never the real announcement content.

Empty case: `{ "success": true, "data": [], "error": null }`

**Expired announcements are now excluded server-side.** The endpoint applies
`active AND (expiresAt IS NULL OR expiresAt > now)`, boundary exclusive.

### 4.3 Ack endpoint

`POST /api/v1/palletizing-line/urgent-announcements/{id}/ack?lineId={lineId}` — **unchanged**,
idempotent per line as before.

### 4.4 Error codes

No new error codes. `ROLL_ANNOUNCEMENT_NOT_FOUND` (404) on an ack of an unknown id, as before.

### 4.5 Refresh expectations

Unchanged and still mandatory: refetch the pending list on app start, on resume, on SSE connect and on
every reconnect, and on each `urgent-manager-announcement` nudge.

## 5. Required Frontend Screens / Dialogs

**None.** No screen, dialog or flow changes. The existing generic-notice surface is correct as-is.

## 6. Required Models / DTO Changes

Optional, and only if the app wants exact-second removal:

| Field                | Type          | Notes                                                     |
| -------------------- | ------------- | --------------------------------------------------------- |
| `expiresAt`        | `DateTime?` | ISO-8601 UTC (`…Z`); `null` = never expires          |
| `expiresAtDisplay` | `String?`   | already business-zone formatted                           |
| `action` (SSE)     | `String`    | `CREATED` / `UPDATED` / `DEACTIVATED` / `DELETED` |

Unknown JSON keys must continue to be ignored — that is what makes this additive.

## 7. Required Repository / API Client Changes

**None required.** If adding the fields above, extend the existing generic-notice model only; no method
names, paths, error mapping or retry behaviour change.

## 8. Required Provider / State Management Changes

**None required.** Optionally arm a one-shot local timer at the nearest `expiresAt` so a generic notice
disappears exactly on time instead of at the next refetch. REST stays authoritative.

## 9. Required UX Flow

- **Happy path:** nudge arrives → refetch pending → render/clear the generic notice. Unchanged.
- **Validation failure:** not applicable.
- **Network failure:** existing retry/refetch-on-resume behaviour applies.
- **Backend business error:** unchanged.
- **Retry / double-submit:** ack is already idempotent per line; unchanged.
- **Cancel / back:** unchanged.

## 10. Arabic UI Text

No new strings. The generic notice text is server-supplied and unchanged:

- Title: `ملاحظة عاجلة من المدير`
- Message: `أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.`

## 11. Edge Cases

| Case                                            | Expected                                                 |
| ----------------------------------------------- | -------------------------------------------------------- |
| `action` key absent (older backend)           | treat as`CREATED`; refetch anyway                      |
| unknown future`action` value                  | refetch anyway — refetching is always the safe response |
| `expiresAt: null`                             | never expires                                            |
| announcement expires while app backgrounded     | resume refetch already omits it                          |
| announcement retargeted away from Thermoforming | `DEACTIVATED` nudge → refetch → notice gone          |
| SSE reconnect after a gap                       | mandatory refetch reconciles state                       |
| user double-taps ack                            | already idempotent per line                              |
| session/device key replaced                     | unchanged behaviour                                      |

## 12. Testing Requirements

- **Unit:** the nudge model tolerates the new `action` key and an absent one.
- **Repository/API:** `expiresAt` / `expiresAtDisplay` parse, including `null`.
- **Provider/state:** a nudge of each action value triggers exactly one refetch.
- **Manual smoke:** post a Thermoforming announcement → station shows the generic notice; deactivate it
  → the notice clears without restarting the app.
- **Regression:** the station never renders the real message body or sender.

## 13. Backend Compatibility Notes

- Required backend version: the release containing timed manager announcements.
- **Old app versions remain fully compatible** — the change is additive and `eventType` is unchanged.
- No coordinated rollout required. No feature flag required.
- If the frontend is never updated: nothing breaks; expired notices simply clear on the next refetch
  rather than at the exact second.

## 14. Final Acceptance Criteria

- The app continues to refetch on every `urgent-manager-announcement` nudge, whatever its `action`.
- The real message body and sender never appear on this app.
- If `expiresAt` is adopted, an expired generic notice disappears without another SSE frame.
