# FaletScreen

## 1. Screen Identity

- Name: `FaletScreen`
- File path: `lib/presentation/widgets/falet_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: pushed from `ProductionLineSection` when the operator opens the FALET view for a specific line

## 2. Purpose

This screen exposes the line's open `FALET` items and lets the operator either convert a leftover carton balance into a completed pallet or dispose of it with an optional reason.

## 3. UI Structure

- line-colored `AppBar` titled `الفالت`
- loading state with centered progress indicator
- pull-to-refresh wrapper
- empty state when no FALET items are returned
- list of FALET cards showing:
  - compact product name
  - package quantity
  - created/updated display timestamps when present
  - `تحويل لطبلية` action
  - `إتلاف` action

## 4. State Management

- Watches `PalletizingProvider`
- Triggers `fetchFaletItems(line.number)` in `initState()`
- Reads:
  - `isFaletItemsLoading(line.number)`
  - `getFaletItems(line.number)`
- Convert and dispose actions call provider methods that refresh both:
  - line state through `refreshLineState(lineNumber)`
  - FALET list through `fetchFaletItems(lineNumber)`

## 5. API Integration

- Initial load and pull-to-refresh:
  - `GET /palletizing-line/lines/{lineId}/falet`
- Convert action:
  - `POST /palletizing-line/lines/{lineId}/falet/convert-to-pallet`
- Dispose action:
  - `POST /palletizing-line/lines/{lineId}/falet/dispose`
- Related workflow doc:
  - [FALET Screen and Actions](../02_APP_WORKFLOWS.md#9-falet-screen-and-actions)

## 6. User Actions

- Open the screen from a line section
- Pull to refresh the current FALET list
- Tap `تحويل لطبلية` to open `ConvertFaletToPalletDialog`
- Tap `إتلاف` to open `DisposeFaletDialog`
- After a successful conversion, review the returned `PalletSuccessDialog`

## 7. Business Rules in UI

- FALET operations are line-scoped and always use `widget.line.number`.
- Conversion is not done inline; the operator must explicitly confirm quantity handling in `ConvertFaletToPalletDialog`.
- Disposal allows an empty reason and passes `null` to the backend when the trimmed text is empty.
- The screen does not locally validate whether FALET exists for a line before navigation; it trusts provider/backend results.

## 8. Edge Cases

- While first load is running and no cached response exists, the whole body is blocked by a spinner.
- If the backend returns no FALET items, the screen shows an empty success-style state instead of an error.
- API failures are surfaced as red snackbars using `ApiException.displayMessage`.
- Timestamp rows render only when `createdAtDisplay` or `updatedAtDisplay` is present.

## 9. Dependencies

- `PalletizingProvider`
- `FaletItem`
- `ConvertFaletToPalletDialog`
- `DisposeFaletDialog`
- `PalletSuccessDialog`
- `ProductType.formatCompactName`

## 10. Risks / Pitfalls

- The screen stores no local cache beyond what the provider exposes, so a refresh immediately changes the rendered list.
- Conversion success depends on backend pallet creation rules that are not revalidated in this widget.
- The widget accepts `dynamic faletResponse` in `_buildBody`; shape assumptions come from provider/repository behavior rather than static typing.

## 11. AI Agent Notes

- Do not break the post-frame `fetchFaletItems()` call unless FALET data is prefetched elsewhere.
- If you change convert or dispose behavior, verify both the FALET list and the parent line state still refresh.
- Before changing fields shown here, review `FaletItem`, `FaletItemsResponse`, and the backend `FaletService` contract.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [ConvertFaletToPalletDialog](./ConvertFaletToPalletDialog.md)
- [DisposeFaletDialog](./DisposeFaletDialog.md)
- [PalletSuccessDialog](./PalletSuccessDialog.md)

## Related Services

- `PalletizingProvider`
- `PalletizingRepositoryImpl`

## Related Backend Concepts

- `FaletService`
- `PalletizingService`
