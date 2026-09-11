# UME Markupv1

PDF viewer and annotator for iPhone and iPad. Import a document, mark it up with a **freehand Pencil highlighter**, underline, Apple Pencil ink, or a page-anchored note, bookmark pages, then leave and reopen with those marks still there. v1 stores the library on **this device** (Application Support). Multi-device iCloud sync is optional and requires a paid Apple Developer Program team later.

This repository is an Xcode-ready thin v1. It was authored on Linux, so **open and run it on a Mac**. There is no App Store or TestFlight submission in this project.

Display name: **UME Markupv1**  
Bundle ID placeholder: `com.ume.markupv1`  
Minimum: iOS 17 / iPadOS 17  
English UI only

## Open in Xcode

1. On a Mac, clone this repo and open `UMEMarkupv1.xcodeproj`.
2. Select the **UME Markupv1** scheme (shared with the project).
3. In the project editor → target **UME Markupv1** → **Signing & Capabilities**:
   - Choose **your** Apple ID / Personal Team. Do not invent a Team ID.
   - Xcode will fill in a development team. Leave the bundle ID as `com.ume.markupv1` or change it to one you own.
4. Choose an iPhone or iPad simulator, or a signed-in device.
5. Press Run.

First-run path that does not need a PDF on disk: **Add Sample PDF** from the library’s + menu. That page is generated in-app. It is not a personal document.

## Signing placeholders

| Setting | Value in the project | What you do |
| --- | --- | --- |
| Bundle identifier | `com.ume.markupv1` | Keep or replace with your own |
| Development team | empty | Select **your** Personal Team in Xcode |
| iCloud | **not enabled** | Personal Team cannot ship iCloud entitlements |
| Certificates / profiles | none committed | Xcode Automatic Signing |

`UMEMarkupv1.entitlements` is an empty dictionary. A Personal Team build should sign without deleting any capability in Xcode.

### Personal Team = local-only

v1 is meant to run on a free Apple ID / Personal Team. PDFs and markup live under Application Support on that device. The library header reads **Saved on this device only**.

### Later: re-enable iCloud sync (paid Apple Developer Program)

A Personal Team **cannot** add the iCloud capability. When you have a paid Apple Developer Program membership:

1. In Xcode → **Signing & Capabilities**, click **+ Capability** → **iCloud**.
2. Check **iCloud Documents**.
3. Add a container named `iCloud.com.ume.markupv1` (or accept Xcode’s `iCloud.` + bundle ID). Do not invent a Team ID.
4. On each device: same Apple ID, iCloud Drive on, run the app once.

Until that capability exists, `FileManager.url(forUbiquityContainerIdentifier:)` returns `nil` and storage stays local. If the container later appears, the code may copy the local library into it once.

### Simulator vs device

- Simulator and Personal Team device: import and annotation persistence work locally. Multi-device sync does not.
- Paid team + iCloud Documents + two devices, same Apple ID: import or annotate on one, wait for iCloud, pull-to-refresh the library on the other.

## Mac-only verification

This environment cannot compile or launch an iOS app. On a Mac, walk through:

1. Run on an iPad simulator (large canvas / split view) and an iPhone simulator.
2. Add Sample PDF. Confirm name + last opened appear in the library. Search for `Sample`.
3. Open it. The toolbar defaults to **Scroll**. On an **iPad with Apple Pencil**:
   - **Highlight** — paint a translucent stroke over *part* of a word or a long run of letters. It must not snap to a whole word or line.
   - **Ink** — write with Pencil. Rest a finger or the heel of your hand on the page: it should **scroll**, not leave a mark.
   - **Eraser** — rub out the highlight and ink strokes with Pencil.
   - **Note** — tap with a finger, type, Save.
   - **Bookmark** — tap the bookmark icon, save this page, scroll away, then jump back from the menu. Repeat on page 2 and 3 of the sample.
   - Leave and reopen: freehand highlights, ink, notes, and bookmarks are still there.
4. Simulator / no Pencil: the pointer is treated as Pencil so you can still draw. Finger-vs-Pencil palm rejection can only be proven on a real iPad.
5. Import a real PDF via **Import PDF…** (Files / document picker).
6. On a device, share a PDF into **UME Markupv1** (the app registers as a PDF editor). It is copied into the library.
7. Delete a document with swipe-to-delete. It should disappear from the list.
8. Confirm the library header says **Saved on this device only**. Leave and reopen: markup is still there (no iCloud required).

## Architecture

```
Library (SwiftUI)
    └── DocumentLibrary scans a folder of document packages
Viewer (SwiftUI + PDFKit)
    ├── PDFView renders pages (auto-scale, continuous scroll)
    ├── PDFAnnotation draws underline / sticky note (and older selection highlights)
    └── PKCanvasView overlays (PDFPageOverlayViewProvider) draw ink + freehand highlight
Storage
    └── one folder per document on this device (Application Support)
```

### Why files on disk (not SwiftData + CloudKit)

PDFs are large binaries. CloudKit records and SwiftData models are a poor fit for “drop a 40 MB lecture PDF in the library and keep a small markup sidecar next to it.” v1 uses a local Application Support folder. The same code can optionally use an iCloud Documents container later if a paid team adds that capability.

SwiftData would only duplicate the directory listing. v1 treats the file system as the source of truth.

### How a document is stored

Each imported PDF becomes a folder named with a UUID:

```
Application Support/UMEMarkupv1/Library/<uuid>/
    document.pdf     # untouched copy of the import
    markup.json      # underlines, notes, ink, freehand highlights, page bookmarks
    meta.json        # display name, importedAt, lastOpenedAt
```

If a paid team later enables iCloud Documents, the same layout can live under:

```
<ubiquity container>/Documents/Library/<uuid>/
```

The original PDF is not rewritten. Underline and notes (and any older selection-based highlights) are re-applied as `PDFAnnotation`s when the file opens. Ink and freehand highlight are per-page `PKDrawing`s stored as Base64 in `markup.json` (`inkPages` / `highlightPages`). Bookmarks are 0-based page indices in the same sidecar (`bookmarkedPages`). Saves are atomic (temp file, then replace). Older `markup.json` files without the new keys still load.

### Sync behavior

- **v1 default (Personal Team):** no iCloud entitlement. Library stays on that device.
- Paid team + iCloud Documents + same Apple ID + iCloud Drive → both devices can see the same folders.
- `NSMetadataQuery` and `NSUbiquityIdentityDidChange` refresh the library if iCloud files arrive.
- Items that exist in iCloud but have not finished downloading show **Waiting for iCloud…**
- Conflicts: last writer of `markup.json` wins. There is no merge UI in v1.

### Markup tools

**You must select a tool in the bottom toolbar.** Drawing tools show a **Pencil** caption (for example `Highlight · Pencil`).

On a real iPad, **Ink, Highlight, and Eraser accept Apple Pencil only** (`PKCanvasView.drawingPolicy = .pencilOnly`). Finger and a resting hand pan the PDF. Notes can still be tapped with a finger. The Simulator treats the pointer as Pencil so you can still mark pages on a Mac.

| Tool | What to do | Stored as |
| --- | --- | --- |
| **Scroll** | Pan / pinch the PDF. | — |
| **Highlight** | Paint a translucent highlighter stroke with Apple Pencil. Covers any span of letters — not a text-selection rectangle. Finger still scrolls. | `PKDrawing` marker strokes in `highlightPages` |
| **Underline** | Drag a finger or Pencil across a passage (selection-based). Page panning is paused while this tool is on. | `PDFAnnotation` `.underline` |
| **Ink** | Write or draw with Apple Pencil. Finger still scrolls. | `PKDrawing` sidecar (`inkPages`) |
| **Note** | Tap a page (finger is fine), type in a sheet, Save. | `PDFAnnotation` `.text` |
| **Eraser** | Rub out ink or freehand highlight with Pencil. Tap an underline / note / older selection highlight. | removes that stroke / record |
| **Bookmark** | Toolbar bookmark icon: add/remove the current page, or jump to a saved page. | `bookmarkedPages` in `markup.json` |

Leave the document and reopen it: highlights, underlines, notes, ink, and bookmarks persist in `markup.json` on this device. No paid Apple Developer Program membership is required for v1.

## Project layout

```
UMEMarkupv1.xcodeproj/          # shared scheme included
UMEMarkupv1/
  UMEMarkupv1App.swift          # scene, open-in / share-sheet URL
  Info.plist                    # PDF document type
  UMEMarkupv1.entitlements      # empty — no iCloud (Personal Team signs)
  Models/                       # library item, markup JSON, tools
  Services/                     # storage root, library, JSON persistence
  PDF/                          # PDFKit host, PencilKit overlays, sample PDF
  Views/                        # library, viewer, toolbar, note sheet
  Assets.xcassets/
```

## v1 limitations

Out of scope, on purpose:

- OCR and full-text search inside PDFs (filename search only)
- Folders, tags, collaboration, export-as-new-PDF workflows
- Subscriptions, branding, or extra sample content
- App Store / TestFlight upload
- Password-protected PDFs
- Markup conflict merge across simultaneous editors
- Multi-device iCloud sync on a Personal Team (paid Apple Developer Program is required to add the iCloud capability later)
- Automatic migration of an in-progress local session if iCloud is added mid-edit (local files are copied the first time a ubiquity container appears)

Known thin-v1 behavior:

- Ink and freehand highlight live in a sidecar, not inside the PDF, so Preview / other apps will not show those strokes. Underlines, notes, and older selection highlights are also sidecar-backed (recreated on open) rather than baked into `document.pdf`.
- Highlight is a PencilKit marker stroke. It does not use PDF text selection, so it works the same on scanned image pages.
- On device, Ink / Highlight / Eraser ignore finger input. Use Apple Pencil to mark; use a finger to scroll. Simulator uses `.anyInput` so a mouse can still draw.
- Simulator cannot prove Pencil palm rejection. iCloud multi-device sync is out of scope until a paid team adds the capability.

## Requirements

- Xcode 15 or later (iOS 17 SDK)
- A Mac to build
- A free Apple ID / Personal Team is enough to run on a signed-in device
- Optional later: paid Apple Developer Program membership to re-enable iCloud Documents sync
