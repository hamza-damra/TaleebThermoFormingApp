# Product Type Images — Backend Handoff Document

## Section 1: Backend Changes

### Database

**Migration**: `V18__add_image_to_product_types.sql`

Two nullable columns added to `product_types`:

| Column               | Type          | Description                                               |
| -------------------- | ------------- | --------------------------------------------------------- |
| `image_filename`     | VARCHAR(255)  | Unique server-generated filename stored on disk           |
| `image_original_name`| VARCHAR(255)  | Original filename from the upload (for display reference) |

Both columns are nullable — product types are not required to have an image.

### Entity Changes

`ProductType` entity now has:
- `imageFilename` — the stored filename on disk
- `imageOriginalName` — the original uploaded filename

### New DTO Fields

All product-type response DTOs now include an `imageUrl` field:

| DTO                             | Field      | Type     | Notes                                       |
| ------------------------------- | ---------- | -------- | ------------------------------------------- |
| `ProductTypeResponse`           | `imageUrl` | `String` | Used by admin API and web admin              |
| `PalletizingProductTypeResponse`| `imageUrl` | `String` | Used by palletizing mobile app               |
| `ScanValidationResponse`        | `imageUrl` | `String` | Used by mobile scan confirmation screen      |

When a product type has no image, `imageUrl` is `null` (omitted from JSON due to `@JsonInclude(NON_NULL)`).

### Image URL Pattern

```
/api/v1/product-type-images/{filename}
```

Example:
```
/api/v1/product-type-images/pt-img-1711900000000-7a8b9c.jpg
```

This is a **relative URL**. Frontend/mobile must prepend the server base URL:
```
https://your-server.com/api/v1/product-type-images/pt-img-1711900000000-7a8b9c.jpg
```

### New/Updated Endpoints

#### Image Serving Endpoint (NEW)
```
GET /api/v1/product-type-images/{filename}
```
- **Auth**: Any authenticated user (DRIVER, OFFICER, PALLETIZER, ADMIN, MONITORING)
- **Returns**: Image binary with correct `Content-Type` header (`image/jpeg`, `image/png`, `image/webp`)
- **Error**: 404 if file not found

#### Existing Endpoints (Updated Response)
These endpoints now include `imageUrl` in their response:

- `GET /api/v1/admin/product-types` — paginated list
- `GET /api/v1/admin/product-types/{id}` — single product type
- `POST /api/v1/admin/product-types` — create
- `PUT /api/v1/admin/product-types/{id}` — update
- `GET /api/v1/palletizing/product-types` — active product types for palletizing
- `POST /api/v1/scan/validate` — scan validation response

### Validation Rules

| Rule          | Value                              |
| ------------- | ---------------------------------- |
| Max file size | 5 MB                               |
| Allowed types | `image/jpeg`, `image/png`, `image/webp` |
| Extensions    | `.jpg`, `.jpeg`, `.png`, `.webp`   |
| Required      | No — image is optional             |

### Filesystem Storage

- **Default path**: `./product-type-images/` (relative to working directory)
- **Configurable**: `app.product-type-images.path` property or `PRODUCT_TYPE_IMAGES_PATH` env var
- **Filenames**: Server-generated unique names (`pt-img-{timestamp}-{random}.{ext}`)
- **Directory auto-created** on first upload

### Cleanup Behavior

| Action                     | Image Behavior                                    |
| -------------------------- | ------------------------------------------------- |
| Delete product type        | Image file deleted from disk after DB delete       |
| Update with new image      | Old file deleted after successful DB save          |
| Update with "remove image" | Old file deleted, fields set to null               |
| Failed DB save after upload| New file cleaned up, old file preserved            |

---

## Section 2: Frontend Integration Notes

### How to use `imageUrl`

1. **Fetch product types** from any of the standard endpoints (palletizing list, scan validation, admin API)
2. **Check** if `imageUrl` is not null/empty
3. **Prepend base URL** if using relative URLs: `${baseUrl}${imageUrl}`
4. **Render** the image using a standard image component

### Response Examples

**Product type WITH image:**
```json
{
  "id": 5,
  "name": "لنش بوكس / أبيض / 500 كرتونة",
  "productName": "لنش بوكس",
  "prefix": "0005",
  "color": "أبيض",
  "imageUrl": "/api/v1/product-type-images/pt-img-1711900000000-7a8b9c.jpg",
  "active": true
}
```

**Product type WITHOUT image:**
```json
{
  "id": 6,
  "name": "أطباق / شفاف / 1000 كيس",
  "productName": "أطباق",
  "prefix": "0006",
  "color": "شفاف",
  "active": true
}
```

Note: When there is no image, the `imageUrl` field is completely absent from the JSON (not `null`, just omitted) due to `@JsonInclude(NON_NULL)`.

### Scan Validation Response with Image

```json
{
  "valid": true,
  "scannedValue": "000512345678",
  "prefix": "0005",
  "productTypeExists": true,
  "productTypeActive": true,
  "description": "لنش بوكس مقطع",
  "defaultQuantity": 500,
  "quantityUnit": "كرتونة",
  "imageUrl": "/api/v1/product-type-images/pt-img-1711900000000-7a8b9c.jpg"
}
```

### Authentication

The image serving endpoint requires authentication (JWT Bearer token). Mobile apps must include the `Authorization: Bearer <token>` header when fetching images, just like any other API call.

---

## Section 3: Ready-to-Use Prompt for Frontend AI Agent

Below is a copy-pasteable prompt for the frontend (mobile) AI agent:

---

```
You are working on the Taleeb mobile app (Flutter / Android).

The backend has added product type image support. Each product type now has an optional
`imageUrl` field in API responses. Your task is to display these images in the app.

## What changed on the backend

- All product type responses now include an optional `imageUrl` field (String, nullable/absent).
- The URL is relative, e.g. `/api/v1/product-type-images/pt-img-1711900000000-abc.jpg`
- You must prepend the backend base URL to form the full URL.
- The endpoint requires authentication — include the JWT Bearer token in the request header.
- Supported image formats: JPEG, PNG, WebP.
- When `imageUrl` is absent or null, the product type has no image.

## What you must implement

### 1. Product type selection / picker UI
- In the product type selection list/picker, display a small thumbnail image next to each product type
- If the product type has an image, show it as a small rounded thumbnail (e.g. 40x40 or 48x48)
- If the product type has no image, show a placeholder icon (e.g. a package/box icon or a grey circle)
- Image should be loaded with proper caching (e.g. `CachedNetworkImage` or equivalent)
- Include authorization headers when loading the image

### 2. Product confirmation screen
- After scanning or selecting a product, the confirmation/detail screen should display
  the product type image prominently
- Use a card or container with the product image (e.g. 120x120 or similar appropriate size)
- The image must:
  - Fit fully within its container without cropping (use `BoxFit.contain` or equivalent)
  - Not stretch or distort
  - Have rounded corners consistent with the app design
  - Have a light/subtle border or shadow for clean appearance
  - Sit well within the existing confirmation card/layout
- If no image exists, show a clean placeholder (matching icon, or a styled "no image" placeholder)

### 3. Image loading states
- Show a loading shimmer/spinner while the image is loading
- Show the placeholder/fallback if the image fails to load (network error, 404, etc.)
- Do NOT show broken image icons — always fall back gracefully

### 4. Image caching and performance
- Cache images in memory and on disk to avoid re-fetching
- Use a proven image loading library (e.g. `cached_network_image` in Flutter)
- Pass the auth token in the image request headers:
  ```
  Authorization: Bearer <jwt_token>
  ```

### 5. RTL and responsive layout
- The app is RTL (Arabic). Ensure images are positioned correctly in RTL mode.
- Images should look good on both phones and tablets
- Do not break existing spacing, padding, or alignment
- Keep the same design language (colors, rounded corners, shadows) as the rest of the app

### 6. Specific technical guidance
- The `imageUrl` field comes from:
  - `PalletizingProductTypeResponse.imageUrl` (product type picker/list)
  - `ScanValidationResponse.imageUrl` (scan confirmation screen)
  - `ProductTypeResponse.imageUrl` (admin/detail views)
- Build the full image URL: `"$baseUrl$imageUrl"` (e.g. `"https://api.taleeb.ps/api/v1/product-type-images/pt-img-123.jpg"`)
- Check for null/empty `imageUrl` before attempting to load

### 7. What NOT to do
- Do NOT store images locally or cache indefinitely (they may be replaced by admin)
- Do NOT break the existing product selection flow
- Do NOT change API calls — the `imageUrl` is already included in existing endpoint responses
- Do NOT add new API endpoints or modify request payloads
- Do NOT hardcode image dimensions in a way that prevents responsiveness
```

---

*End of handoff document.*
