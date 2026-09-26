# SESSION PRODUCTION DETAIL — CURRENT LOCATION GAP

**Severity:** Low — one badge in a read-only dialog stays hidden; no workflow is blocked.
**Owner:** Palletizing-Line backend service.
**Filed by:** Palletizing Flutter app (`TaleebThermoFormingApp`).
**Date filed:** 2026-09-25.
**Status:** OPEN.

---

## 1. Summary

The Palletizing App's «ملخص المناوبة» → «تفاصيل إنتاج المناوبة» dialog should show
a «تم النقل إلى الرصيف» badge on every pallet whose **current** location is
`TRANSIT`, next to the existing grinding status chip.

`GET /api/v1/palletizing-line/lines/{lineId}/session-production-detail` returns
no location for its pallets: `SessionPalletDetail` (backend
`palletizing/dto/SessionPalletDetail.java`) has `palletId`, `scannedValue`,
`serialNumber`, `quantity`, `sourceType`, `createdAt(Display)` and the grinding
fields only.

No other Palletizing App endpoint can fill the gap:

- `GET /palletizing-line/palletizer/production-pending-pallets` lists only
  pallets still at `PRODUCTION`. A pallet missing from it may be at `TRANSIT`,
  in a warehouse, cancelled or held for grinding, so "not pending" does not mean
  "at TRANSIT".
- The move response carries `currentLocation`, but only for the pallets this
  device moved, and only until the warehouse moves or undoes them.

## 2. Requested change (additive)

Add to each `SessionPalletDetail`:

| Field | Type | Meaning |
|---|---|---|
| `currentLocation` | `Destination` enum name, nullable | The pallet's current location, read the same way as `currentLocation` in the V210 move response (a missing status row = `PRODUCTION`). |

Example:

```json
{
  "palletId": 55012,
  "scannedValue": "101000000123",
  "quantity": 120,
  "createdAt": "2026-09-24T11:40:00Z",
  "createdAtDisplay": "2026-09-24، 02:40 مساءً",
  "currentLocation": "TRANSIT"
}
```

No new endpoint and no request change are needed. A location change already
publishes `palletizing-lines-changed`, and the app re-reads the open dialog when
its line's pending set changes.

## 3. App status

The app already reads the optional `currentLocation` and shows the badge when
its value is `TRANSIT`
(`lib/presentation/widgets/session_drilldown_dialog.dart`,
`TransitLocationChip`). Until the backend sends the field, the badge never
appears. The app does not guess a location.
