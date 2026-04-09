# SearchablePickerDialog

## 1. Screen Identity

- Name: `SearchablePickerDialog<T>`
- File path: `lib/presentation/widgets/searchable_picker_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: shared picker surface for item-selection flows such as product picking in pallet creation and product switching

## 2. Purpose

This is the app's reusable searchable modal picker for line-side forms that need fast filtering and single-item selection.

## 3. UI Structure

- dialog container with title and close button
- auto-focused search field
- divider
- filtered list of item rows
- empty-results state with `لا توجد نتائج`
- selected item highlighting and check icon

## 4. State Management

- Local dialog state:
  - `_searchController`
  - `_searchFocusNode`
  - `_filteredItems`
- Initial filtered list is the full provided `items` list
- Filtering is driven entirely by the injected `searchMatcher`

## 5. API Integration

- No direct API integration
- Operates on the in-memory list supplied by the caller
- Returns the selected item to the caller through `Navigator.pop(item)`

## 6. User Actions

- Type into search
- Clear current search
- Select an item from the list
- Close the dialog without choosing an item

## 7. Business Rules in UI

- Search behavior is caller-defined, not hardcoded in the widget.
- Display text, subtitle text, and optional leading widget are all caller-supplied.
- Equality for the selected-state highlight is based on `selectedItem == item`.
- The search field requests focus automatically after the dialog opens.

## 8. Edge Cases

- If the filtered list is empty, the widget shows an empty-results state rather than returning `null`.
- Because selection equality relies on `==`, custom item classes need consistent equality semantics to highlight correctly.
- The dialog is barrier-dismissible.

## 9. Dependencies

- `ResponsiveHelper`
- caller-provided extractors and matchers
- common callers:
  - `CreatePalletDialog`
  - `ProductSwitchDialog`

## 10. Risks / Pitfalls

- This widget is generic but not virtualized beyond `ListView.builder`, so extremely large lists still depend on caller-side data size.
- If item equality is reference-based, `selectedItem` highlighting can fail after remapping objects.
- Search text direction is forced RTL in the text field, which is correct for current Arabic UI but may need reconsideration for mixed-language inputs.

## 11. AI Agent Notes

- Prefer reusing this widget instead of duplicating picker dialogs.
- When introducing a new picker flow, keep the search matcher explicit so filtering stays business-correct.
- Verify any new leading widget remains lightweight; this dialog is used in quick operator workflows.

## Related Screens

- [CreatePalletDialog](./CreatePalletDialog.md)
- [ProductSwitchDialog](./ProductSwitchDialog.md)

## Related Services

- none directly; caller-driven

## Related Backend Concepts

- backend-independent shared UI helper
