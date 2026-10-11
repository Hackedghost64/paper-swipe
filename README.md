# PaperSwipe 📖✨

> **"Silent reading, effortless pages."**  
> A minimalist mobile application that transforms any PDF into a distraction-free, web novel-style swipeable e-book.

---

## 🌟 Overview & Philosophy

Most PDF readers are built for static documents, multi-column reports, and form editing—crowded with toolbars, annotation icons, and zoom controls.

**PaperSwipe** strips away all digital clutter to recreate the pure, quiet focus of reading a web novel or physical book:
- **Instant Shelf with Page-1 Covers**: Each PDF is displayed as a tactile bookshelf card with its first page rendered as a cover thumbnail.
- **Natural Swipe Navigation**: Turn pages with effortless horizontal swipe gestures or gentle edge taps.
- **Atomic Memory Retention**: Every page turn is recorded immediately to atomic storage—no debounce windows, no data loss on force-close or battery death.
- **Silent Night Inversion**: One-tap high-contrast reading filter inverts blinding white PDF pages into deep dark surfaces for strain-free reading in bed.

---

## 📸 Interface & Architecture Preview

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│ [PS] PaperSwipe         3 Books │       │ < Library  Dunes.pdf   [NIGHT]  │
│ ─────────────────────────────── │       │ ─────────────────────────────── │
│      [+ Add Book (PDF)]         │       │                                 │
│                                 │       │   Chapter 4: The Citadel        │
│   YOUR SHELF                    │       │                                 │
│  ┌──────────┐   ┌──────────┐    │       │   The wind carries no scent     │
│  │ [COVER]  │   │ [COVER]  │    │       │   here, only the dry crackle    │
│  │ Page 1   │   │ Page 1   │    │       │   of static over sandstone.     │
│  │          │   │          │    │       │                                 │
│  │ Novel A  │   │ Novel B  │    │       │                  [Swipe →]      │
│  │ p. 48/100│   │ p. 12/80 │    │       │                                 │
│  └──────────┘   └──────────┘    │       │ ────●────────────────────────── │
│                                 │       │ PAGE 48 / 100     48% COMPLETED │
└─────────────────────────────────┘       └─────────────────────────────────┘
         1. Bookshelf Home                         2. Immersive Reader
```

---

## 🚀 Key Features

### 1. Bookshelf Home Screen
- **Page-1 Thumbnail Cards**: Automatically rasterizes Page 1 of any imported PDF at 1.5x scale to generate crisp book covers with physical spine edges.
- **Reading Progress At a Glance**: Clear page count indicators (`p. 48 / 100`) and amber-gold completion bars.
- **Immediate Reading Flow**: Picking a PDF copies it to the app sandbox, generates the cover, and opens directly into the reader.
- **Book Management**: Long-press any book card to rename or safely delete with automatic file and key cleanup.
- **Corrupt Storage Recovery**: Dual-key architecture (`paperswipe_books_v1` and `paperswipe_books_backup_v1`) recovers gracefully from storage corruptions; displays a dedicated recovery state with a **Reset Library** option rather than hanging.

### 2. Immersive Fullscreen Reader
- **Distraction-Free Sticky Mode**: Hides system status and navigation bars.
- **Intuitive Touch Zones**:
  - **Left 22%**: Previous page
  - **Center 56%**: Toggle translucent HUD overlay
  - **Right 22%**: Next page
- **Fast-Scrub Slider**: Scrub across hundreds of pages with real-time numeric readouts (`PAGE 48 OF 100 • 48% COMPLETED`).
- **Night-Inversion Mode**: Color-matrix shader inverts text and backgrounds for comfortable dark-room reading without altering the underlying file.

### 3. Bulletproof Persistence Architecture
- **Thread-Safe Singleton**: `BookRepository` maintains a single synchronized in-memory state across all routes.
- **Atomic Progress Keys**: Page progress is stored under isolated keys (`paperswipe_pos_$id`), eliminating JSON re-serialization overhead and debounce timer race conditions.
- **Lifecycle Guarantees**: Flushes state instantly when paused or sent to the background via `WidgetsBindingObserver`.

---

## 🎨 Design System & Brand Palette

| Role | Color Name | Hex Code | Purpose |
| :--- | :--- | :--- | :--- |
| **Primary Background** | **Silent Obsidian** | `#0D0F12` | True dark mode, zero glare, OLED power efficiency |
| **Card / Surface** | **Smoky Slate** | `#161A22` | Bookshelf cards, bottom sheets, dialogs |
| **Border / Subtle Line** | **Subtle Graphite** | `#262B36` | Hairline borders, dividers |
| **Brand Accent** | **Amber Gold** | `#E0A96D` | Primary action buttons, progress bars, active sliders |
| **Text Primary** | **Pure Frost** | `#F1F3F7` | Headers, titles, high-contrast labels |
| **Text Secondary** | **Pewter Fog** | `#8A91A0` | Page stats, timestamps, metadata |

---

## 📂 Project Structure

```
paper_swipe/
├── assets/
│   └── icons/
│       ├── app_icon.jpg              # 3D Obsidian & Amber Gold app icon
│       └── app_logo.png              # Vector brand glyph
├── lib/
│   ├── main.dart                     # Application entrypoint & theme initialization
│   ├── models/
│   │   └── book.dart                 # Book entity model & JSON serialization
│   ├── services/
│   │   └── book_repository.dart      # Singleton persistence & atomic storage layer
│   ├── theme/
│   │   └── app_theme.dart            # Obsidian dark theme & design tokens
│   ├── widgets/
│   │   └── book_card.dart            # 2-column cover card with progress indicators
│   └── screens/
│       ├── library_screen.dart       # Bookshelf home, import flow, & error recovery
│       └── reader_screen.dart        # Immersive fullscreen reader, HUD, & night mode
├── sample_books/
│   └── dunes_of_the_drift.pdf        # Sample 3-page test PDF
└── test/
    ├── models/
    │   └── book_test.dart            # Unit tests for Book model
    ├── services/
    │   └── book_repository_test.dart # Storage resilience, singleton, & recovery tests
    └── widget_test.dart              # App smoke test
```

---

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.20+ or latest stable)
- Android Studio / Android SDK (for physical device or emulator runs)

### Setup & Run

```bash
# 1. Clone the repository
git clone https://github.com/Hackedghost64/paper-swipe.git
cd paper-swipe

# 2. Install dependencies
flutter pub get

# 3. Run automated tests
flutter test --reporter expanded

# 4. Launch on connected device or emulator
flutter run
```

### Build Release APK

```bash
flutter build apk --release
```
The compiled APK will be output to:  
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🧪 Automated Testing

PaperSwipe includes a full test suite covering data modeling, edge-case resilience, and UI smoke tests:

```bash
flutter test --reporter expanded
```

```text
00:01 +11: test/models/book_test.dart: Book Model Tests
00:01 +14: test/services/book_repository_test.dart: BookRepository Edge Case & Resilience Tests
00:01 +15: test/widget_test.dart: PaperSwipeApp smoke test
00:01 +15: All tests passed!
```

---

## 📄 License
MIT License. Crafted for quiet reading.
