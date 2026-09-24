# FRONTEND HANDOFF — Palletizing App: `production-plan-changed` is leaving your stream

**Status:** Backend change. **No frontend code change is required, now or later.**
**Type:** SSE routing correction — a frame you receive today stops arriving, in two stages.
**Right now:** nothing changes for you. The frame still arrives.
**Later:** it stops, when a config flag is switched off. No release of yours is involved.

> **Revised.** An earlier revision of this file said the frame had already been removed from your
> stream. It had been, and then it was put back — deliberately, as a temporary compatibility window
> for the Roll Production App (§2). The end state is unchanged: this frame leaves your stream. Only
> the timing moved.

---

## 1. Executive summary

`GET /api/v1/palletizing-line/events` carries **`production-plan-changed`** today, and will stop
carrying it.

That frame describes a change to the **roll** production plan — which rolls to produce, on which
roll line, in which order. It has never had anything to do with palletizing. Your own handoffs say
so:

> `FRONTEND_HANDOFF_ADMIN_APP_ROLL_PRODUCTION_MULTI_LINE.md` §42 — Palletizing App: *"Additive,
> ignorable"*
>
> `FRONTEND_HANDOFF_ROLL_PRODUCTION_APP_MANUAL_WEIGHT_ENTRY_POLICY.md` §19 — *"Shares the
> `GET /api/v1/palletizing-line/events` SSE stream, so it will receive the new frame. It must keep
> ignoring unknown event names (existing behaviour). No code change expected."*

You receive it only because the broker that emits it happens to be mounted on the palletizing path —
its controller's javadoc gives the reason plainly: *"so it shares the existing `X-Device-Key`
security chain — no extra config in `SecurityConfig` is required."* That is a security-wiring
convenience, not a domain decision.

**You are not the semantic audience for this frame, and you never were.** Its permanent home is
`GET /api/v1/roll-production-app/events`, whose audience is roll operators by construction.

---

## 2. Why it has not left yet

The frame was moved to the roll app's own stream, and real-device acceptance found that the
**installed** Roll Production App registers its handler on *this* stream — so moving it silently
broke live plan refresh on every deployed roll handset.

The backend therefore now delivers the frame to **both** streams, gated by
`app.sse.compat.plan-changed-on-palletizing-channel` (shipped `true`). When the Roll Production App
release that listens on its own stream is in the field, that flag is set `false` and this frame stops
reaching you — permanently.

Full context: `FRONTEND_HANDOFF_ROLL_PRODUCTION_APP_PLAN_CHANGED_SSE_ROUTING.md` §7.

**Nothing here needs sequencing against a Palletizing App release.** You are told because a frame
disappearing from a stream you hold open is the kind of thing that should never be a surprise.

---

## 3. What you must check before assuming "no impact"

**If your app has a handler for `production-plan-changed`, confirm what it does.**

- **Ignores it / no handler** → nothing to do, now or when the flag flips. This is the expected case.
- **Logs it** → the log line stops. Fine.
- **Triggers a refetch of palletizing state** → that refetch is firing on an unrelated domain's
  events. Losing it is a correctness improvement, but if any screen has come to *depend* on that
  incidental refresh, it will need its own trigger. **Tell the backend team if this is you** — it
  would mean a palletizing surface has no signal of its own, which is a real gap worth fixing
  properly rather than by re-crossing the domain boundary. Say so **before** the flag flips; that is
  what the window is for.

Either way, keep ignoring unknown event names. That is the property that makes a shared stream safe,
and it is what will make this removal a non-event for you.

---

## 4. What did NOT change

Everything else on `GET /api/v1/palletizing-line/events` is byte-identical — same URL, same
`X-Device-Key` auth, same 25 s heartbeat, same 5-minute emitter timeout, same `connected` handshake:

| Event name | Status |
| --- | --- |
| `roll-manager-announcement` | unchanged |
| `urgent-manager-announcement` | unchanged (still sanitized) |
| `roll-production-settings-changed` | unchanged |
| `connected` | unchanged |
| `production-plan-changed` | **still delivered today; leaves this stream when the compatibility flag flips** |

`GET /api/v1/palletizing-line/app-events` (`palletizing-lines-changed`) and
`GET /api/v1/palletizing-line/lines/{lineId}/operator-dashboard/events` are entirely untouched.

No REST endpoint, DTO, error code, enum value, validation rule, role or auth mechanism changed.

---

## 5. A known related issue, NOT fixed here

While auditing this channel we confirmed a second cross-domain leak in the opposite direction:
`urgent-manager-announcement` frames carrying `targetDomain: "THERMOFORMING"` are broadcast to
**every** device on the pool with no domain filter, including roll devices.

It is deliberately **not** fixed in this release — that release already carries a historical database
restatement, and mixing an unrelated announcement-routing change into it would widen the blast radius
for no schedule benefit. Keep filtering on `targetDomain` client-side as you do today. It is recorded
here so it is not rediscovered as a new defect.

---

## 6. App impact matrix

| App | Affected? | Reason | Required handoff |
| --- | --- | --- | --- |
| **Palletizing App** | **Informational — will lose a frame** | `production-plan-changed` leaves this stream when the compatibility flag flips; no code change expected | this file |
| **Roll Production App** | **YES — client change required** | must handle the frame on its own app-token stream before that flag can flip | `FRONTEND_HANDOFF_ROLL_PRODUCTION_APP_PLAN_CHANGED_SSE_ROUTING.md` |
| Warehouse App | No | does not consume this stream | — |
| Admin App | No | uses `/api/v1/admin-app/events`; unchanged | — |
| Operator App | No | thermoforming domain; unaffected | — |
| Roll Worker App | No | uses `/api/v1/thermoforming-roll-app/events`, which never carried this frame | — |

---

## 7. Rollout

**Backend deploys with no coordinated Palletizing release, in either stage.**

| Stage | Your stream carries | You do |
| --- | --- | --- |
| This backend release | `production-plan-changed` — unchanged from today | nothing |
| Flag set `false`, later | it stops | nothing, unless §3 case 3 applies to you |

---

## 8. Acceptance criteria

While the compatibility window is open:

1. An admin edits the **roll** production plan → the frame still arrives, and **no palletizing screen
   changes** as a result.
2. A manager announcement still arrives on `roll-manager-announcement`.
3. A roll-production settings change still arrives on `roll-production-settings-changed`.
4. The stream stays open across the 25 s heartbeat and reconnects normally at the 5-minute timeout.

After the flag flips:

5. An admin edits the roll production plan → **no** `production-plan-changed` frame arrives, and no
   palletizing screen changes. Criteria 2–4 still hold.

---

## 9. App-side audit result (Palletizing App) — 2026-08-23

**§3 case 1 applies: no handler. Nothing to do, now or when the flag flips. No reply owed to the
backend team.**

Audited and confirmed in this repo:

| Check | Result |
| --- | --- |
| Any handler / listener / constant for `production-plan-changed` | **None.** No match anywhere in `lib/` or `test/`. |
| Does the frame trigger a palletizing refetch? | **No.** It cannot reach a refresh path — see below. |
| Are unknown event names ignored? | **Yes**, by construction — `SseClient._handleFrames` routes only three named events and falls through to an explicit ignore. |
| Does any palletizing surface depend on the incidental refresh? | **No.** |

**This app never opens `GET /api/v1/palletizing-line/events` at all.** Its single SSE connection is
`GET /api/v1/palletizing-line/app-events` ([sse_client.dart](../lib/core/services/sse_client.dart) —
`SseClient.path`), created once in [di.dart](../lib/core/di.dart). That is the only
`ResponseType.stream` / `text/event-stream` request in the codebase, so the flag flip is invisible
here even in principle. (The route spelling discrepancy is pre-existing and already recorded in
[PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md](PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md) §SSE —
`app-events` is the route in production use.)

Refresh triggers are structurally walled off from unknown frames: `RefreshCoordinator` subscribes to
`SseClient.events`, which only ever carries parsed `palletizing-lines-changed` frames, and
`ManagerAnnouncementNotifier` subscribes to `SseClient.announcements` /
`SseClient.connectionState`. There is no path by which a `production-plan-changed` frame — or any
other unrouted event name — can reach a refetch.

### What changed in this repo

No production behaviour changed. Two changes lock the property in place:

1. [sse_client.dart](../lib/core/services/sse_client.dart) — the fall-through ignore branch now names
   the cross-domain frames it drops and why, so a future reader does not "helpfully" wire
   `production-plan-changed` into a palletizing refresh.
2. [test/sse_test.dart](../test/sse_test.dart) — five regression tests covering both sides of the
   flag flip (acceptance criteria 1-5): the frame arriving routes nothing; other roll-domain and
   unknown frames route nothing; an ignored frame interleaved with real ones disturbs neither
   routing, the `connected` state, nor the connection; an ignored frame does not consume a dedupe
   slot (so a later palletizing event reusing that `eventId` is not swallowed); and post-flip the
   stream behaves identically. 25/25 pass.

### §5 (`targetDomain` leak) — no action needed here

The Palletizing App **is** the `THERMOFORMING` audience, so it is not the victim of that leak. It
also does not branch on the nudge's `targetDomain`: every nudge triggers a re-fetch of the
authoritative sanitized `pending` endpoint, which is domain- and line-scoped server-side. That is
strictly safer than a client-side filter and needs no change when the leak is fixed.
