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
      "priority": "URGENT"
    }
  ]
}
```

- `title`/`message` are **fixed generic strings**. There is **no `messageBody` and no `senderDisplayName` field** at all.
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
  "targetDomain":"THERMOFORMING", "priority":"URGENT" }
```

Sanitized nudge (no body). On receipt, call the pending endpoint and show the generic notice. Also fetch on app start / resume / SSE reconnect. The pending endpoint is authoritative; the nudge is best-effort.

---

## Recommended Flutter integration

- Add a `ManagerAnnouncementNotifier` (Provider / ChangeNotifier) that:
  - exposes the current pending generic notice (if any),
  - polls `pending` on resume + listens to the `urgent-manager-announcement` SSE event,
  - calls `ack` and clears the notice on dismiss.
- Render a **global overlay above `PalletizingScreen`** (not inside a sub-flow) so the urgent notice shows regardless of the current sub-screen.
- The overlay must **not interfere** with existing flows: `lineUiMode`, `LineAuthOverlay`, handover, FALET, or pallet creation. It is a passive, dismissible-by-ack notice layered on top — it does not block scanning/auth logic, just informs the operator to open the operator app.

## Privacy rule (must hold)

- **Never expect or render a real message body.** The sanitized DTO has no such field.
- **Defensive:** even if a future backend bug ever sent a body, ignore it — render only the fixed generic strings + `createdAtDisplay`.
