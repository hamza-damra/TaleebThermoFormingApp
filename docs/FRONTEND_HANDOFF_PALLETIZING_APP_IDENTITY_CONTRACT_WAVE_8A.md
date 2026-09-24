# Palletizing App — Wave 8 Identity Contract Handoff (CLEAN COORDINATED CUTOVER)

| | |
|---|---|
| **App** | Palletizing App (`taleeb_thermoforming`) |
| **Classification** | **CLEAN_CUTOVER_MIGRATION_REQUIRED** |
| **Cutover strategy** | `COORDINATED_BACKEND_AND_FIRST_PARTY_CLIENT_RELEASE` |
| **Target contract** | `roles` + `primaryRole`. Legacy singular `role` is **ABSENT** |
| **Old-backend compatibility required?** | **NO** |
| **Legacy `role` fallback permitted?** | **NO** |
| **Persisted singular role permitted?** | **NO — this app persists one today and it must be deleted** |
| **Target legacy `role` readers** | **0** |

---

## 1. Purpose

This app was once recorded as *unaffected* by every identity wave, on the grounds that it runs on the
device chain and holds no identity DTO. **That was an inference and it was wrong.** The app calls two
**human** identity endpoints, parses the legacy singular `role` with a non-nullable cast, uses it as
an admission gate, **and persists it to secure storage**.

This document specifies the **final** client shape for the coordinated Wave-8 cutover: identity comes
from `roles` and `primaryRole`, the persisted singular role is deleted, and the app no longer knows
that `role` ever existed.

**This app carries more legacy identity surface than any other of the five**, because it is the only
one that both hard-casts the field *and* stores it. **This is a deletion document.**

## 2. Coordinated release assumption

This client build is intended to ship as part of a coordinated Taleeb backend and first-party app
release.

**It is not required to remain compatible with the pre-Wave-8 backend identity contract.** The
production cutover must not leave old incompatible client builds active against the post-Wave-8b
backend.

That is a **deployment invariant, not a reason to preserve legacy code**.

> **Operational risk, owned by release planning.** Old installed builds of this app will fail against
> the post-Wave-8b backend. Cutover planning must verify every palletizing device is running the
> approved new build before the backend cutover completes. **That risk must not be answered by
> reintroducing the singular field**, and it is the reason §12 may invalidate a stale local session
> rather than carry compatibility code forever.

## 3. Backend Source of Truth

| | |
|---|---|
| **Wave 8a final SHA** | `4ee53664e4db1b0d6460f9cae08f54af170dd645` |
| **Tree** | `4d6895caaf9117bd42d79993022855f5e62378fe` |
| **Annotated tag** | `wave8a-identity-contract-additive-hardening-final` |

Sources: `auth/dto/LoginResponse.java`, `auth/AuthService.java`, `domain/IdentityScope.java`,
`domain/ScopedPrimaryRole.java`, `domain/RolePriority.java`.

> **On history, stated honestly.** The sealed Wave-8a backend is **additive** — it still emits the
> legacy field beside the two new ones. That is where `roles` and `primaryRole` came from and why the
> evidence in §5 is quotable. **Wave 8a's three-field shape is NOT the target.** The target is §6.

## 4. Exact affected endpoints

| method | path | response DTO | target identity fields |
|---|---|---|---|
| `POST` | `/api/v1/auth/login` | `LoginResponse` → `data.user` | `roles`, `primaryRole` |
| `POST` | `/api/v1/auth/pin-login` | `LoginResponse` → `data.user` | `roles`, `primaryRole` |

Both are the **Warehouse mobile** identity surface — `IdentityScope.WAREHOUSE_MOBILE`, admissible set
`{DRIVER, OFFICER}` — shared with the Warehouse App.

**This app calls no other identity endpoint.** A search of `lib/` finds exactly those two paths in
`auth_repository_impl.dart:23` and `:54`, and **no `/me`**. That single fact drives the persistence
decision in §12, so it is stated here rather than buried.

**The palletizing operational APIs are not affected.** Everything under `/api/v1/palletizing-line/**`
runs on the device-key chain and carries no human identity payload. The device key
(`auth_local_storage.dart:63`) and the per-line palletizer session tokens (`:76`–`:89`) are untouched.
**Do not classify this app as unaffected on the strength of that** — its *login* is a human identity
surface.

## 5. Legacy debt to remove — current-state evidence

Read from `TaleebThermoFormingApp` (package `taleeb_thermoforming`) at
`HEAD = 2103b50aab8cc1b02b0453655a9e41e6c45152d8`. **This is the deletion list.**

**Wire read** — `lib/data/models/user_model.dart:16`

```dart
role: json['role'] as String,                          // DELETE
```

**Domain model** — `lib/domain/entities/user.dart:5` — `final String role;`, required and
non-nullable. No `roles`, no `primaryRole`. Roles are raw `String`s; there is no role enum.

**Admission gate** — `lib/data/repositories/auth_repository_impl.dart:18`, `:33`, `:64`

```dart
static const _allowedRoles = {'PALLETIZER', 'DRIVER', 'OFFICER'};   // 'PALLETIZER' is dead — V32
…
if (!_allowedRoles.contains(user.role)) { … }                        // singular → MEMBERSHIP
```

**Persistence** — `auth_repository_impl.dart:41`–`:46` and `:76` call
`saveUserInfo(role: user.role)`, writing the singular role to `FlutterSecureStorage` under
**`user_role`** (`auth_local_storage.dart:8`, `:33`).

**Restore** — `auth_repository_impl.dart:93`–`:105` rebuilds the `User` **entirely from storage**:

```dart
return User(…, role: userInfo['role'] ?? '');          // DELETE the whole singular-role restore
```

### 5.1 Legacy `role` reader census, with target disposition

Production readers only. Every reader is classified; **none is left unclassified.**

| # | site | classification | target disposition |
|---|---|---|---|
| 1 | `lib/data/models/user_model.dart:16` | DEAD LEGACY (wire read) | **DELETE the wire read** |
| 2 | `auth_repository_impl.dart:33` (`login` gate) | **ROLE MEMBERSHIP** | `user.roles.any(_allowedRoles.contains)` |
| 3 | `auth_repository_impl.dart:64` (`pinLogin` gate) | **ROLE MEMBERSHIP** | same |
| 4 | `auth_repository_impl.dart:45` (write) | DEAD LEGACY (serialization) | **DELETE — persist the normalized shape instead** |
| 5 | `auth_repository_impl.dart:76` (write) | DEAD LEGACY (serialization) | **DELETE** |
| 6 | `auth_repository_impl.dart:102` (restore read) | DEAD LEGACY (serialization) | **DELETE — see §12** |

**Current mandatory wire-`role` readers: 1. Current production legacy-`role` readers: 6 sites across
2 files. Current persisted legacy-role fields: 1 (`user_role`). Target for all three: 0.**

Nothing renders the role — a search for `.role` in `lib/` returns only these six data-layer sites.

**`roles` readers today: 0. `primaryRole` readers today: 0.**

## 6. Target coordinated contract

| field | target | meaning |
|---|---|---|
| `roles` | **REQUIRED** | the complete assigned human role set — the only complete role signal |
| `primaryRole` | **REQUIRED** | the scoped singular identity for display and routing |
| `role` | **ABSENT** | deleted legacy field; not read, not stored, not written, not aliased |

```json
{
  "success": true,
  "data": {
    "token": "…",
    "user": {
      "id": 42,
      "name": "…",
      "email": "…@taleeb.ps",
      "roles": ["OFFICER", "DRIVER"],
      "primaryRole": "OFFICER"
    }
  }
}
```

`role` is not listed because it does not exist in the target. A payload that still carries it must
produce byte-identical app behaviour, because nothing reads it (§15.2).

The `role` **JWT claim is removed in the same coordinated cutover.** See §14.

## 7. What is broken today

`json['role'] as String` on a payload with no `role` key throws
`TypeError: null: type 'Null' is not a subtype of type 'String' in type cast` **inside the login
call** — before the gate, before the storage write, and before any handler that could produce a
usable Arabic message. Both the password and the PIN path fail, and the on-screen error will not name
the cause.

**The failure is also delayed, which is worse than immediate.** `getCurrentUser()` (`:93`) reads from
storage and never calls the decoder, so an already-signed-in operator keeps working until their token
is cleared and only then cannot sign back in. In a factory that reads as intermittent rather than as a
cutover. **This app and the Warehouse App are the two clients that hard-fail**, and this is the one
whose failure is hardest to recognise.

## 8. Decoder — target implementation

`roles` and `primaryRole` are contractually required on both identity surfaces. Anything else is a
contract error and must fail loudly.

```dart
// lib/data/models/user_model.dart
factory UserModel.fromJson(Map<String, dynamic> json) {
  final Object? rawPrimary = json['primaryRole'];
  final Object? rawRoles = json['roles'];

  if (rawPrimary is! String || rawPrimary.isEmpty || rawRoles is! List) {
    throw ApiException(
      code: 'IDENTITY_CONTRACT_MALFORMED',
      message: 'تعذّر قراءة بيانات الحساب',
    );
  }

  final List<String> roles =
      rawRoles.whereType<String>().toList(growable: false);
  if (roles.isEmpty) {
    throw ApiException(
      code: 'IDENTITY_CONTRACT_MALFORMED',
      message: 'تعذّر قراءة بيانات الحساب',
    );
  }

  return UserModel(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    primaryRole: rawPrimary,
    roles: roles,
  );
}
```

**There is deliberately no branch that reads `json['role']`, and none may be added.** Reconstructing
the role set from a singular value would hide a backend regression behind a client that appears to
work.

**Unknown role handling.** Because this app keeps roles as raw strings, an unrecognised role name
matches nothing and is ignored — it cannot throw and, critically, **cannot be silently mapped onto a
real factory role**. That is already the safe representation §22 of the programme asks for, and it is
a reason **not** to introduce an enum here (§17).

## 9. Role semantics

- **`roles`** — the complete assigned set. This is what the admission gate asks.
- **`primaryRole`** — the intentionally singular, scoped value. Display or logging only; it is **not**
  the right input to an allow-list check.
- **`role`** — does not exist. No reader, no field, no storage key, no alias.

**Neither field is authorization, and neither is the gate.** The gate is a UX courtesy that produces
one clear Arabic message instead of a string of 403s. The real boundary is server-side: every endpoint
this app calls is authorized on the backend from the stored role assignments.

## 10. Multi-role behaviour and ordering

A warehouse employee may legitimately hold **both** `DRIVER` and `OFFICER` — they supervise the
drivers *and* personally do driver work. On both of this app's endpoints, in the target:

```
roles       contains DRIVER and OFFICER
primaryRole = OFFICER
```

**Never collapse the assigned set**, and never reconstruct it from the singular value — a
single-element set built from `primaryRole` would drop `DRIVER` for exactly the people the gate most
needs to admit.

### 10.1 `roles` ordering carries no meaning

The **set** is authoritative; the **order** is not a contract. This app's two login responses build
`roles` through `Collectors.toSet()` on the backend — a `HashSet`, so **hash order**. Other surfaces
on the same backend emit ladder order or `EnumSet` declaration order for the same user.

**MUST NOT** infer priority from `roles.first`, an array index, sorting, enum ordinal, or
serialization order. `primaryRole` is the explicit singular selection; `roles` is semantically a set.
§15 requires a test that proves reversing the array changes nothing.

## 11. Required production changes

**Model** — `lib/data/models/user_model.dart`

1. Replace the body with §8. The string `json['role']` must not appear in `lib/` afterwards.

**Entity** — `lib/domain/entities/user.dart`

2. **Delete** `final String role;`. Add `final String primaryRole;` and `final List<String> roles;`,
   both non-nullable. **Do not add a `role` getter returning `primaryRole`** — no aliases, no
   deprecated shims.

**Admission gate** — `auth_repository_impl.dart:33` and `:64` — **MEMBERSHIP**

3. ```dart
   if (!user.roles.any(_allowedRoles.contains)) {
     throw ApiException(code: 'ROLE_NOT_ALLOWED',
                        message: 'ليس لديك صلاحية استخدام هذا التطبيق');
   }
   ```
   This is a **correctness fix as well as a migration**. The current gate asks whether the one
   *reported* role is allowed; a person who holds `DRIVER` but whose singular value named something
   else would be locked out despite being entitled. Asking the set removes that permanently.
4. **Delete `'PALLETIZER'` from `_allowedRoles`** (`:18`). The backend removed that role in migration
   `V32`; it matches nothing. This is the cleanup release.

**Persistence** — §12. This is the step most likely to be missed and the one unique to this app.

## 12. Local persistence — target

**CONFIRMED: this app persists the singular role today, and it is the only affected client that does
so in a dedicated storage key.**

| store | key | today | target |
|---|---|---|---|
| `FlutterSecureStorage` | `auth_token` | the JWT | **keep** |
| `FlutterSecureStorage` | `user_id`, `user_name`, `user_email` | identity | keep |
| `FlutterSecureStorage` | **`user_role`** | **the singular role** | **DELETE the key** |
| `FlutterSecureStorage` | `palletizer_session_token_<lineId>` | per-line session | keep, unrelated |

### 12.1 The design decision, and why

The programme offers two clean shapes: persist the normalized identity, or persist only a token and
re-fetch identity. **Only the first is available to this app**, and the reason is structural rather
than a preference:

> **This app has no identity re-fetch endpoint.** It calls `/auth/login` and `/auth/pin-login` and
> nothing else (§4). `checkAuthStatus()` in `lib/presentation/providers/auth_provider.dart:24`–`:41`
> restores the session purely from local storage. Choosing "persist only the token" would require
> adding a new `GET /api/v1/me` call on every cold start — a new network dependency, and a new failure
> mode, on shop-floor devices whose connectivity is the least reliable part of the system.

**Decision: persist the normalized identity shape.** Replace the `user_role` key with a `user_roles`
key holding the JSON-encoded `List<String>`, and add a `user_primary_role` key.

5. Add `user_roles` and `user_primary_role` to `AuthLocalStorage`; **remove `_userRoleKey` and every
   read and write of it.**
6. Write both in `saveUserInfo`; read both in `getUserInfo`; rebuild `roles` and `primaryRole` in
   `getCurrentUser()`.
7. **Do not keep `user_role` alongside them.** Two sources of the same truth is the defect this
   release removes, and the singular value is derivable from neither more nor less than `primaryRole`
   already is.

### 12.2 The stale installed session — invalidate, do not migrate

A device that signed in on the current build holds `user_role` and **no** `user_roles`. There are two
ways to handle that, and the coordinated cutover makes the choice clean:

**Chosen: invalidate.** On cold start, if `user_roles` is absent while a token is present, treat the
stored session as unusable — clear storage via the existing `clearAll()` (`auth_local_storage.dart:52`,
a `deleteAll()`) and route to login.

8. Implement that check in `getCurrentUser()` or `checkAuthStatus()`. It is roughly five lines, it
   runs once per device, and it leaves **zero** permanent compatibility code.

**Rejected: migrating the stale key** by synthesising `roles: [user_role]`. It would mean shipping a
legacy reader in the "clean" build, it would silently produce a **one-element** set for dual-role
employees — dropping `DRIVER` for exactly the people §10 is about — and it would have no removal
date. The cost of the chosen option is one PIN entry per device during a release that is already
coordinated and already requires each device to be verified (§2).

**Document this in the release notes**: operators re-authenticate once on first launch of the new
build. That is a cutover step, not a defect.

## 13. Routing / UX impact

**None beyond the login screen.** This app never renders the role and never branches a screen on it.

The only user-visible behaviour attached to identity is the `ROLE_NOT_ALLOWED` message, and §11
preserves it exactly — including the Arabic string `ليس لديك صلاحية استخدام هذا التطبيق`, which must
not change.

The one added user-visible event is the **one-time re-authentication** in §12.2.

## 14. Security rules

- **Flutter UI is not backend authorization.** The `_allowedRoles` gate is a courtesy message, not a
  control. Every endpoint re-checks server-side.
- **Do not use `primaryRole` as authorization truth**, and do not use it as the allow-list input —
  that is what the complete set is for.
- **Do not treat `roles` as permissions.** Role membership is not capability.
- **`permissions[]` must never enter this contract**, and the client must not recreate backend
  authorization rules locally. Legacy cleanup is not an opportunity to build a client permission
  engine.
- **Do not read roles out of the JWT.** **CONFIRMED: this app does not decode the JWT today** — no
  `jwt_decoder` or `jwt_decode` dependency in `pubspec.yaml`, no manual base64 segment split in
  `lib/`. **Do not start.** Consume the documented HTTP identity contract, not a parallel JWT source.
  The coordinated cutover removes the singular `role` claim too.
- **Do not conflate the chains.** The device key and the per-line palletizer session tokens are a
  separate mechanism with separate lifetimes. The human role must never gate or derive them.
- **Do not send `roles` or `primaryRole` back to the server** as identity.

## 15. Tests required

Existing coverage: 18 Dart test files — the thinnest of the five. **Every fixture below is a
target-contract fixture with no `role` key.** Tests asserting that a legacy-only payload parses, or
that a fallback works, must be **deleted** rather than adapted.

### 15.1 Model parsing — target fixtures

1. **DRIVER + OFFICER, no `role` key:** `roles: ["OFFICER","DRIVER"]`, `primaryRole: "OFFICER"` →
   parses; `roles` has both; `primaryRole == 'OFFICER'`.
2. **DRIVER only, no `role` key.**
3. **Reversed array ordering:** `roles: ["DRIVER","OFFICER"]` behaves **identically** to test 1. Pins
   §10.1.
4. **Missing `roles`** → `IDENTITY_CONTRACT_MALFORMED`. Intentional contract failure.
5. **Missing `primaryRole`** → `IDENTITY_CONTRACT_MALFORMED`.
6. **Empty `roles`** → `IDENTITY_CONTRACT_MALFORMED`.
7. `roles` containing roles this app has no concept of parses, and they are simply not in the
   allow-list — nothing is coerced.

### 15.2 Zero-legacy behavioural ratchet

8. **The legacy field has no effect.** Take the fixture from test 1, add `"role": "OFFICER"`, and
   assert the decoded `User` and the gate outcome are **equal** to the run without it. Remove it and
   assert equality again.

### 15.3 Admission gate

9. A user whose `primaryRole` is **outside** the allow-list but whose `roles` contains `DRIVER` is
   **admitted**. This is the §11.3 correctness fix and cannot be asserted through a singular value.
10. A user whose `roles` contains none of `{DRIVER, OFFICER}` is rejected with `ROLE_NOT_ALLOWED` and
    the exact Arabic message.
11. Both `login` and `pinLogin` enforce the gate identically — assert on both.

### 15.4 Persistence

12. After login, `user_roles` and `user_primary_role` are written, **`user_role` is not**, and
    `getCurrentUser()` returns a user whose `roles` matches what the server sent.
13. **Stale-session invalidation:** storage seeded with a legacy `user_role` and a token but **no**
    `user_roles` → `checkAuthStatus()` ends `unauthenticated`, storage is cleared, and the app routes
    to login. Asserts §12.2.
14. A dual-role user's persisted `roles` round-trips with **both** entries — proving §12.2's rejected
    option would have lost one.
15. `logout()` clears every identity key.

### 15.5 Static

16. `flutter analyze` clean; Dart suite green.
17. Mechanical zero-legacy evidence (§16).

## 16. Clean-client readiness criteria

The app may declare **`PALLETIZING_APP_W8B_CLEAN_CLIENT_READY`** when **all** hold:

- [ ] `roles` model implemented (`List<String>`, non-nullable).
- [ ] `primaryRole` model implemented (non-nullable).
- [ ] Legacy identity property `User.role` **removed**, with **no** alias getter.
- [ ] `MANDATORY_WIRE_ROLE_READERS = 0`.
- [ ] `PRODUCTION_LEGACY_ROLE_READERS = 0`.
- [ ] `LEGACY_ROLE_FALLBACKS = 0` — no code path reads `json['role']`.
- [ ] **`PERSISTED_LEGACY_ROLE_FIELDS = 0`** — the `user_role` key is gone from writes *and* reads.
- [ ] The admission gate asks the **complete set**.
- [ ] A payload **without** `role` succeeds on both login paths.
- [ ] A stale pre-migration local session is invalidated, not silently reconstructed.
- [ ] Reversed `roles` ordering changes nothing.
- [ ] Unknown role names are never mapped to a real factory role.
- [ ] `'PALLETIZER'` removed from the allow-list.
- [ ] The `ROLE_NOT_ALLOWED` Arabic message is unchanged.
- [ ] No JWT decoding; no `permissions[]` consumption.
- [ ] `flutter analyze` green; test suite green.

**Mechanical ratchet.** The primary proof is behavioural: §15.2 asserts that adding or removing `role`
from a realistic fixture leaves the decoded session and the gate outcome unchanged, through the real
decode path. Back it with an analyzer/AST check asserting **zero** occurrences of the `role` string
key in `lib/` — including the storage-key constant, which is why `_userRoleKey` must be deleted rather
than left unused. Prefer the analyzer to a grep.

Client readiness is for the **coordinated backend Wave-8b contract**. Rewriting this document
discharges nothing: `W8B_CLIENT_RELEASE_BARRIER` stays `NOT_YET_DISCHARGED` until a released build is
confirmed in the field, and the backend removal is separate, not-yet-performed work.

## 17. Non-goals

Do **not** redesign any of the following:

- The device-key mechanism or the per-line palletizer session tokens.
- Anything under `/api/v1/palletizing-line/**` — no operational API is in this wave.
- The login screen layout, the PIN flow, or the Arabic copy.
- The `ApiException` / error-mapping model, beyond the one code in §8.

And specifically **do not**:

- add a compatibility layer, alias, adapter or dual-read path;
- introduce a role enum — raw strings are adequate and are what make unknown values inert (§8);
- add a `/me` call merely to avoid persisting identity (§12.1);
- build a client permission model.

## 18. Evidence

**Backend** — sealed tree `4ee53664`, tag `wave8a-identity-contract-additive-hardening-final`

| file | what it establishes |
|---|---|
| `auth/dto/LoginResponse.java` | the wire fields; the legacy one documented as removed in Wave 8b |
| `auth/AuthService.java:74`–`79` | `/auth/login`; `roles` via `Collectors.toSet()` (hash order) |
| `auth/AuthService.java:147`, `:161`–`163` | `/auth/pin-login`; the same derivations |
| `domain/IdentityScope.java` | `WAREHOUSE_MOBILE` admits `{DRIVER, OFFICER}` |
| `domain/ScopedPrimaryRole.java` | the single derivation; the three live `roles` orderings |
| `domain/RolePriority.java:31`–`44` | the ladder — `OFFICER` above `DRIVER` |
| `security/JwtService.java:128`–`135` | the `role` claim, removed in the coordinated cutover |

**Client** — `TaleebThermoFormingApp`, `HEAD = 2103b50a`

| file:line | symbol | what it establishes |
|---|---|---|
| `lib/data/models/user_model.dart:16` | `UserModel.fromJson` | the mandatory legacy read — deletion target 1 |
| `lib/domain/entities/user.dart:5` | `User.role` | required, non-nullable raw `String`; no `roles` |
| `lib/data/repositories/auth_repository_impl.dart:23`, `:54` | `login`, `pinLogin` | the only two identity endpoints — and **no `/me`**, which decides §12 |
| `…/auth_repository_impl.dart:18`, `:33`, `:64` | `_allowedRoles`, the gate | singular value used as a membership test; `'PALLETIZER'` dead since `V32` |
| `…/auth_repository_impl.dart:41`–`46`, `:76` | `saveUserInfo` | the role is persisted — deletion target 2 |
| `…/auth_repository_impl.dart:93`–`105` | `getCurrentUser` | the restore path rebuilds from storage and never re-runs the gate |
| `lib/presentation/providers/auth_provider.dart:24`–`41` | `checkAuthStatus` | cold start restores from storage only — no network identity |
| `lib/data/datasources/auth_local_storage.dart:8`, `:33`, `:42` | `_userRoleKey` | the `user_role` key to delete |
| `lib/data/datasources/auth_local_storage.dart:52` | `clearAll` | `deleteAll()` — the mechanism §12.2 uses |
| `lib/data/datasources/auth_local_storage.dart:63`, `:76`–`89` | device key, session tokens | the separate, unaffected chain |
| `pubspec.yaml` | — | no JWT-decoding dependency |
