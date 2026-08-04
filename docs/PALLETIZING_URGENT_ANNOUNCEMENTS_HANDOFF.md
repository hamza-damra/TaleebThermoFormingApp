# Palletizing App — Handoff: Urgent Manager Announcements (sanitized)

> Backend implemented and verified. Backend branch: `feature/manager-urgent-announcements-and-thermoforming-sse-reasons`.

The Palletizing App receives only a **sanitized generic notice** when a THERMOFORMING urgent announcement exists. It **never** receives the real message body or sender.

## Auth & transport (unchanged — do NOT change)

- Endpoints stay under `/api/v1/palletizing-line/**`.
- Use the existing **`X-Device-Key`** header. **Do not** switch to bearer/JWT.
- The device key is a shared secret, so per-station identity for acknowledgements is the **`lineId`** the station is operating (you already know this in the app). Send it as a query parameter.

---

## Pending endpoint (SANITIZED)

```
GET /api/v1/palletizing-line/urgent-announcements/pending?lineId={lineId}
Header: X-Device-Key
```

Response (oldest first; active, not expired, not-yet-acked by this line):

```json
{
  "success": true,
  "data": [
    {
      "id": 123,
      "targetDomain": "THERMOFORMING",
      "title": "ملاحظة عاجلة من المدير",
      "message": "أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.",
      "createdAt": "2026-06-10T15:10:00Z",
      "createdAtDisplay": "2026-06-10، 06:10 مساءً",
      "expiresAt": "2026-06-10T17:10:00Z",
      "expiresAtDisplay": "2026-06-10، 08:10 مساءً",
      "priority": "URGENT"
    }
  ]
}
```

- `title`/`message` are **fixed generic strings**. There is **no `messageBody` and no `senderDisplayName` field** at all.
- **Announcements are timed.** `expiresAt` / `expiresAtDisplay` are `null` when the announcement never expires (and on a legacy row). The backend filters expired rows itself — `active AND (expiresAt IS NULL OR expiresAt > now)`, boundary exclusive — so this endpoint stays authoritative. The app additionally arms a one-shot local timer on the soonest `expiresAt` so a notice clears on the second rather than at the next natural re-fetch. `expiresAtDisplay` is parsed but **not rendered**: the overlay carries no new strings.
- Generic blocking notice to display:
  - title: **"ملاحظة عاجلة من المدير"**
  - message: **"أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها."**

## Acknowledge endpoint (GENERIC_NOTICE_ACK)

```
POST /api/v1/palletizing-line/urgent-announcements/{id}/ack?lineId={lineId}
Header: X-Device-Key
```

Response: `{ "success": true }`. Backend forces `acknowledgementType = GENERIC_NOTICE_ACK`, keyed per `lineId`. Duplicate acks return success (idempotent). Another line still sees the notice until it acks for itself.

---

## SSE nudge

On the existing device SSE channel (`GET /api/v1/palletizing-line/events`), a new SSE event name `urgent-manager-announcement`:

```json
{ "eventType":"URGENT_MANAGER_ANNOUNCEMENT_CREATED", "announcementId":123,
  "targetDomain":"THERMOFORMING", "priority":"URGENT", "action":"CREATED" }
```

Sanitized nudge (no body). On receipt, call the pending endpoint and show the generic notice. The pending endpoint is authoritative; the nudge is best-effort.

- `action` is `CREATED` / `UPDATED` / `DEACTIVATED` / `DELETED` — every lifecycle step now nudges, so an announcement that is edited, switched off, deleted or retargeted away from Thermoforming clears the station notice instead of lingering. It is absent on an older backend, which means `CREATED`.
- **`eventType` is a frozen legacy literal**: it reads `..._CREATED` for every action so deployed builds keep matching it. Never infer the lifecycle step from it.
- **Do not branch on `action`.** Every value — including an unknown future one — maps to the same response: re-fetch `pending`. The app parses it for contract parity and debug logging only.
- Re-fetch triggers (all mandatory): app start, app resume, **every SSE connect and reconnect**, every nudge. The app adds one more of its own — the expiry deadline of the soonest timed notice.

> App-side note: this app's SSE stream is `GET /api/v1/palletizing-line/app-events` (see `SseClient.path`), not `/events` as spelled above and in the backend handoff. The `app-events` route is the one in production use.

---

## Recommended Flutter integration

- Add a `ManagerAnnouncementNotifier` (Provider / ChangeNotifier) that:
  - exposes the current pending generic notice (if any),
  - re-fetches `pending` on app start / resume, on every SSE connect + reconnect (`SseClient.connectionState`), and on every `urgent-manager-announcement` nudge — all debounced into one fetch,
  - arms a one-shot timer on the soonest future `expiresAt` and re-fetches when it fires; the local clock only drops a notice outright when every line is unreachable, so REST stays authoritative,
  - calls `ack` and clears the notice on dismiss.
- Render a **global overlay above `PalletizingScreen`** (not inside a sub-flow) so the urgent notice shows regardless of the current sub-screen.
- The overlay must **not interfere** with existing flows: `lineUiMode`, `LineAuthOverlay`, handover, FALET, or pallet creation. It is a passive, dismissible-by-ack notice layered on top — it does not block scanning/auth logic, just informs the operator to open the operator app.

## Privacy rule (must hold)

- **Never expect or render a real message body.** The sanitized DTO has no such field.
- **Defensive:** even if a future backend bug ever sent a body, ignore it — render only the fixed generic strings + `createdAtDisplay`.
