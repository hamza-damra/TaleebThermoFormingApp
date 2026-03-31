# Shimmer Loading Implementation Handoff

## Overview

This document describes the shimmer/skeleton loading implementation added to the Taleeb ThermoForming palletizing app (تكوين المشاتيح).

## Package Selection

### Chosen Package: `skeletonizer` v2.1.3

After researching available Flutter shimmer/skeleton packages, **skeletonizer** was selected for the following reasons:

| Criteria | skeletonizer | shimmer | shimmer_animation |
|----------|-------------|---------|-------------------|
| Maintenance | ✅ Good (active) | ❌ Poor | ✅ Good |
| Auto-conversion | ✅ Yes | ❌ No | ❌ No |
| Custom skeletons | ✅ Bone widgets | ❌ Manual | ❌ Manual |
| RTL Support | ✅ Automatic | ⚠️ Manual | ⚠️ Manual |
| Modern Flutter | ✅ Yes | ⚠️ Outdated | ✅ Yes |

### Key Advantages

1. **Auto-converts widgets to skeletons** - Can wrap existing widgets
2. **Bone widgets for custom layouts** - Precise control over skeleton shapes
3. **Inherent RTL support** - Works automatically with Arabic UI
4. **Smooth shimmer animation** - Professional appearance
5. **Lightweight and performant** - No heavy dependencies

## Implementation Structure

### Files Created

```
lib/presentation/widgets/shimmer/
├── palletizing_shimmer.dart    # Main shimmer widgets
└── shimmer_widgets.dart        # Barrel export file
```

### Files Modified

- `pubspec.yaml` - Added skeletonizer dependency
- `lib/presentation/screens/palletizing_screen.dart` - Integrated shimmer loading

## Shimmer Widgets

### PalletizingShimmer

The main shimmer widget that mirrors the exact structure of `ProductionLineSection`:

```dart
PalletizingShimmer(line: ProductionLine.line1)
```

**Structure matches:**
- Header (desktop only)
- Form card with operator and product fields
- Summary card with stats boxes
- Create pallet button

### PalletizingShimmerDualPane

For tablet/desktop layouts with two production lines side by side:

```dart
const PalletizingShimmerDualPane()
```

## Usage Pattern

The shimmer is integrated into `PalletizingScreen._buildBody()`:

```dart
Widget _buildBody(PalletizingProvider provider, bool isMobile) {
  if (provider.isLoading) {
    return _buildLoadingShimmer(isMobile);
  }
  // ... rest of body
}

Widget _buildLoadingShimmer(bool isMobile) {
  if (isMobile) {
    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        PalletizingShimmer(line: ProductionLine.line1),
        PalletizingShimmer(line: ProductionLine.line2),
      ],
    );
  }
  return const PalletizingShimmerDualPane();
}
```

## Shimmer Configuration

The shimmer effect uses subtle, professional colors:

```dart
Skeletonizer(
  effect: ShimmerEffect(
    baseColor: Colors.grey.shade200,
    highlightColor: Colors.grey.shade50,
    duration: const Duration(milliseconds: 1500),
  ),
  child: // skeleton content
)
```

## Responsive Support

The shimmer automatically adapts to:

| Screen Type | Shimmer Layout |
|-------------|----------------|
| Mobile (<600px) | Single pane with TabBarView |
| Tablet (600-1200px) | Dual pane side-by-side |
| Desktop (>1200px) | Dual pane with header |

## RTL Support

Skeletonizer automatically supports RTL layouts because:
1. It uses standard Flutter layout widgets
2. Bone widgets inherit directional context
3. No hardcoded directional values

The Arabic UI works correctly without any additional configuration.

## Adding Shimmer to New Screens

To add shimmer loading to a new screen:

### 1. Create a shimmer widget

```dart
import 'package:skeletonizer/skeletonizer.dart';

class MyScreenShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      effect: ShimmerEffect(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        duration: const Duration(milliseconds: 1500),
      ),
      child: _buildSkeletonContent(context),
    );
  }
  
  Widget _buildSkeletonContent(BuildContext context) {
    return Column(
      children: [
        // Use Bone widgets to match your UI structure
        Bone.text(words: 2),  // Text placeholder
        Bone.square(size: 48),  // Icon/square placeholder
        Bone.circle(size: 40),  // Circle placeholder
        Bone.icon(size: 24),  // Icon placeholder
      ],
    );
  }
}
```

### 2. Integrate into screen

```dart
if (isLoading) {
  return MyScreenShimmer();
}
```

## Bone Widget Reference

| Widget | Usage |
|--------|-------|
| `Bone.text(words: n)` | Text placeholder with n words |
| `Bone.square(size: n)` | Square placeholder |
| `Bone.circle(size: n)` | Circular placeholder |
| `Bone.icon(size: n)` | Icon placeholder |
| `Bone.button()` | Button placeholder |

## Loading States Not Using Shimmer

The following loading states intentionally use spinner instead of shimmer:

| Location | Reason |
|----------|--------|
| `AuthWrapper` initial/loading | Very brief, auth check only |
| `AuthWrapper` handover check | Overlay with text message |
| `ProductionLineSection` create button | Action feedback, not content load |

These are intentional because they represent action feedback or very brief states where shimmer would be excessive.

## Performance Considerations

1. **Animation is GPU-accelerated** - Smooth 60fps
2. **Single animation controller** - Efficient resource usage
3. **No layout rebuilds** - Static skeleton structure
4. **Minimal overdraw** - Clean widget tree

## Testing

To verify shimmer is working:

1. Run the app: `flutter run`
2. Login with a valid PIN
3. Observe the shimmer loading on the palletizing screen
4. Pull to refresh to see shimmer again
5. Test on tablet for dual-pane shimmer

## Future Enhancements

Potential improvements for future iterations:

1. Add shimmer to settings screens
2. Add shimmer to dialog content loading
3. Add shimmer to printer selection loading
4. Consider adding shimmer to list items during refresh
