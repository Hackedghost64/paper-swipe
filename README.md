# PaperSwipe 📖✨

> **"Silent reading, effortless pages."**  
> A minimalist mobile application that transforms any PDF into a distraction-free, web novel-style swipeable e-book.

---

## 🌟 Key Features

- **Bookshelf Home Screen**:
  - Displays a clean **2-column cover grid** where each book's cover is rendered directly from **Page 1 of the PDF**.
  - Shows reading progress (`p. 42 / 120` and percentage bar in Amber Gold).
  - Prominent **"Add Book (PDF)"** action button.
  - Automatically launches the reader immediately upon importing a new PDF.
  - Long-press to rename or remove books from your shelf.

- **Distraction-Free Immersive Reader**:
  - **True Fullscreen**: Hides Android system and navigation bars for silent reading in bed or on the go.
  - **Natural Swipe Gestures**: Smooth horizontal page-turning with physics and edge-tap navigation (left edge = previous page, right edge = next page).
  - **Single Center Tap HUD**: Reveals a minimal, frosted-glass top & bottom HUD (slider scrubber, page counter, back button).
  - **Night-Inversion Mode**: One-tap toggle inverts bright white PDF pages into soft dark surfaces with crisp cream text for eye comfort in the dark.
  - **Memory Retention**: Remembers your exact page and timestamp on every single page turn so you always resume where you left off.

- **Sandbox Storage**:
  - Imported PDFs are copied into the app's internal sandbox so books are never broken or lost even if the original file is deleted from `Downloads`.
  - Cover thumbnails are cached as PNGs for 60fps scrolling.

---

## 🎨 Brand & Color System

- **Silent Obsidian**: `#0D0F12` (OLED true black, zero glare)
- **Smoky Slate**: `#161A22` (Card surfaces & dialogs)
- **Amber Gold**: `#E0A96D` (Foil accents, progress bars, active sliders)
- **Pure Frost**: `#F1F3F7` (High readability typography)

---

## 📱 Architecture & Folder Structure

```
paper_swipe/
├── assets/
│   └── icons/
│       ├── app_icon.jpg        # 3D Obsidian & Amber Gold App Icon
│       └── app_logo.png        # Brand Vector Glyph
├── lib/
│   ├── main.dart               # App entrypoint with Obsidian dark theme
│   ├── models/
│   │   └── book.dart           # Book entity with progress & JSON serialization
│   ├── services/
│   │   └── book_repository.dart# Storage sandbox, thumbnail rasterizer, persistence
│   ├── theme/
│   │   └── app_theme.dart      # Design tokens, typography, and Material theme
│   ├── widgets/
│   │   └── book_card.dart      # 2-column card with Page-1 thumbnail & progress bar
│   └── screens/
│       ├── library_screen.dart # Bookshelf home view & PDF import flow
│       └── reader_screen.dart  # Fullscreen swipe reader, HUD, & night inverter
├── sample_books/
│   └── dunes_of_the_drift.pdf  # Sample 3-page test novel
└── test/
    ├── models/
    │   └── book_test.dart      # Unit tests for Book model
    └── widget_test.dart        # Smoke tests for PaperSwipeApp
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.20+)
- Android Studio / Android SDK (for Android device/emulator)

### Running the App

```bash
# 1. Clone repository
git clone https://github.com/Hackedghost64/paper-swipe.git
cd paper-swipe

# 2. Get dependencies
flutter pub get

# 3. Run unit tests
flutter test

# 4. Launch on connected device or emulator
flutter run
```

### Building Android APK

```bash
flutter build apk --release
```
The release APK will be generated at `build/app/outputs/flutter-apk/app-release.apk`.

---

## 🧪 Testing

Run all unit and widget tests:
```bash
flutter test
```
Run static analysis:
```bash
flutter analyze
```

---

## 📄 License
MIT License. Created with ❤️ for silent, distraction-free reading.
