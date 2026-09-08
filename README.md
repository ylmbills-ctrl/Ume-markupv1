# UME Markupv1

PDF viewer and annotator for iPhone and iPad. Import a document, mark it up with highlight, underline, Apple Pencil / finger ink, or a page-anchored note, then leave and reopen with those marks still there. The same library syncs across the user’s devices through iCloud Documents when the capability is enabled.

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
| Development team | empty | Select your team in Xcode |
| iCloud container | `iCloud.com.ume.markupv1` | Create this container on your team (steps below) |
| Certificates / profiles | none committed | Xcode Automatic Signing |

The entitlements file is a **placeholder**. Apple Developer portal values must come from your account.

## Enable iCloud (capability + container)

v1 uses **iCloud Documents**, not a custom backend and not SwiftData + CloudKit. That keeps large PDFs and their sidecar files as ordinary files that iCloud already knows how to sync.

1. In Xcode, open **Signing & Capabilities**.
2. Click **+ Capability** → **iCloud**.
3. Check **iCloud Documents**.
4. Add a container named `iCloud.com.ume.markupv1` (or accept Xcode’s `iCloud.` + bundle ID).
5. If Xcode rewrites `UMEMarkupv1.entitlements`, keep `CloudDocuments` and that container identifier.
6. On each test device / simulator: sign into the **same Apple ID**, enable **iCloud Drive**, and run the app once so the ubiquity container is created.

Until the container exists on your team, `FileManager.url(forUbiquityContainerIdentifier:)` returns `nil` and the app stores the library under Application Support on that device. The library header then reads **Saved on this device only**. Local markup still persists.

If Automatic Signing fails because the iCloud container is not on your team, either create the container or temporarily remove the iCloud capability to run locally. The code already falls back to local storage.

### Simulator vs device

- Simulator: import and annotation persistence work without iCloud. Multi-device sync does not.
- Two physical devices, same Apple ID, iCloud Drive on: import or annotate on one, wait for iCloud, pull-to-refresh the library on the other.

## Mac-only verification

This environment cannot compile or launch an iOS app. On a Mac, walk through:

1. Run on an iPad simulator (large canvas / split view) and an iPhone simulator.
2. Add Sample PDF. Confirm name + last opened appear in the library. Search for `Sample`.
3. Open it. Scroll pages (one page in the sample). Select **Highlight** and drag across a paragraph. Select **Underline** and drag again. Select **Ink** and draw with the mouse or Pencil. Select **Note**, tap the page, type a comment, Save.
4. Press Home or go back to the library. Reopen the document. Highlights, underline, ink, and the note should still be there.
5. Import a real PDF via **Import PDF…** (Files / document picker).
6. On a device, share a PDF into **UME Markupv1** (the app registers as a PDF editor). It is copied into the library.
7. Delete a document with swipe-to-delete. It should disappear from the list.
8. With iCloud enabled, confirm the library header says **iCloud sync on**, then repeat steps 3–4 on a second device.

## Architecture

```
Library (SwiftUI)
    └── DocumentLibrary scans a folder of document packages
Viewer (SwiftUI + PDFKit)
    ├── PDFView renders pages (auto-scale, continuous scroll)
    ├── PDFAnnotation draws highlight / underline / sticky note
    └── PKCanvasView overlays (PDFPageOverlayViewProvider) draw ink
Storage
    └── one folder per document, synced as iCloud Documents
```

### Why files + iCloud Documents (not SwiftData + CloudKit)

PDFs are large binaries. CloudKit records and SwiftData models are a poor fit for “drop a 40 MB lecture PDF in the library and keep a small markup sidecar next to it.” iCloud Documents gives a local-first folder that the system syncs when signed in. The same code path works offline: if the ubiquity container is missing, the folder is Application Support.

SwiftData would only duplicate the directory listing. v1 treats the file system as the source of truth.

### How a document is stored

Each imported PDF becomes a folder named with a UUID:

```
<ubiquity container>/Documents/Library/<uuid>/
    document.pdf     # untouched copy of the import
    markup.json      # highlights, underlines, notes, PencilKit drawings
    meta.json        # display name, importedAt, lastOpenedAt
```

Local fallback:

```
Application Support/UMEMarkupv1/Library/<uuid>/
```

The original PDF is not rewritten. Highlight, underline, and notes are re-applied as `PDFAnnotation`s when the file opens. Ink is a per-page `PKDrawing` stored as Base64 in `markup.json`. Saves are atomic (temp file, then replace).

If iCloud later becomes available, any existing local library folder is copied into the ubiquity container once.

### Sync behavior

- Same Apple ID, iCloud Drive enabled → both devices see the same folders.
- `NSMetadataQuery` and `NSUbiquityIdentityDidChange` refresh the library when files arrive.
- Items that exist in iCloud but have not finished downloading show **Waiting for iCloud…**
- Conflicts: last writer of `markup.json` wins. There is no merge UI in v1.

### Markup tools

| Tool | Input | Stored as |
| --- | --- | --- |
| Scroll | Drag / pinch | — |
| Highlight | Drag (text selection when the page has text, otherwise a rectangle) | `PDFAnnotation` `.highlight` |
| Underline | Same gesture | `PDFAnnotation` `.underline` |
| Ink | Apple Pencil or finger (`PKCanvasView.drawingPolicy = .anyInput`) | `PKDrawing` sidecar |
| Note | Tap a page, type in a sheet | `PDFAnnotation` `.text` |
| Eraser | Tap a highlight / underline / note, or rub out ink | removes that record / stroke |

## Project layout

```
UMEMarkupv1.xcodeproj/          # shared scheme included
UMEMarkupv1/
  UMEMarkupv1App.swift          # scene, open-in / share-sheet URL
  Info.plist                    # PDF document type + iCloud container publicity
  UMEMarkupv1.entitlements      # iCloud Documents placeholders
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
- Automatic migration of an in-progress local session if the user signs into iCloud mid-edit (local files are copied the first time the container appears)

Known thin-v1 behavior:

- Ink lives in a sidecar, not inside the PDF, so Preview / other apps will not show those strokes. Highlights, underlines, and notes are also sidecar-backed (recreated on open) rather than baked into `document.pdf`.
- Highlight on a scanned image PDF becomes a rectangle you dragged, not a text selection.
- Simulator cannot prove Pencil pressure or true iCloud multi-device sync.

## Requirements

- Xcode 15 or later (iOS 17 SDK)
- A Mac to build
- Optional: Apple Developer Program membership to create the iCloud container and run on devices
