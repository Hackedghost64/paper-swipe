import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';

class BookRepository {
  static const String _storageKey = 'paperswipe_books_v1';
  static const String _backupStorageKey = 'paperswipe_books_backup_v1';
  final Uuid _uuid = const Uuid();

  // In-memory cache to eliminate repetitive disk reads and JSON decodes
  List<Book>? _cachedBooks;

  // Debounce timer for saving reading progress during rapid page flips
  Timer? _debounceSaveTimer;

  /// Loads all stored books sorted by most recently read.
  /// Throws an exception on corrupt storage rather than silently returning [] to prevent data wipe.
  Future<List<Book>> getBooks({bool forceReload = false}) async {
    if (!forceReload && _cachedBooks != null) {
      return List<Book>.from(_cachedBooks!);
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonListStr = prefs.getString(_storageKey);

    if (jsonListStr == null || jsonListStr.isEmpty) {
      _cachedBooks = [];
      return [];
    }

    try {
      final books = _parseBooksJson(jsonListStr);
      _cachedBooks = books;
      return List<Book>.from(books);
    } catch (primaryError) {
      // Primary corrupted: Attempt recovery from backup
      final backupStr = prefs.getString(_backupStorageKey);
      if (backupStr != null && backupStr.isNotEmpty) {
        try {
          final recovered = _parseBooksJson(backupStr);
          _cachedBooks = recovered;
          // Restore primary key with recovered data
          await prefs.setString(_storageKey, backupStr);
          return List<Book>.from(recovered);
        } catch (_) {}
      }

      // If both fail or no backup exists, DO NOT silently return []!
      // Preserve existing cache if available, or throw error so caller never overwrites disk with []
      if (_cachedBooks != null) {
        return List<Book>.from(_cachedBooks!);
      }
      throw Exception('Storage corruption detected: Unable to parse library data: $primaryError');
    }
  }

  List<Book> _parseBooksJson(String jsonStr) {
    final List<dynamic> decoded = jsonDecode(jsonStr) as List<dynamic>;
    final books = decoded
        .map((item) => Book.fromJson(item as Map<String, dynamic>))
        .toList();

    // Filter out books whose PDF files no longer exist
    final validBooks = <Book>[];
    for (final book in books) {
      if (File(book.pdfPath).existsSync()) {
        validBooks.add(book);
      }
    }

    validBooks.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return validBooks;
  }

  /// Atomically saves list of books to persistent storage with backup
  Future<void> _saveBooks(List<Book> books) async {
    // Safety check: Never allow saving an empty list if we know we had books and this was an unintended call
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(books.map((b) => b.toJson()).toList());

    // 1. Keep previous valid data in backup key
    final currentData = prefs.getString(_storageKey);
    if (currentData != null && currentData.isNotEmpty) {
      await prefs.setString(_backupStorageKey, currentData);
    }

    // 2. Save new data
    await prefs.setString(_storageKey, encoded);

    // 3. Update memory cache
    _cachedBooks = List<Book>.from(books);
  }

  /// Picks a PDF, copies to sandbox, generates Page 1 thumbnail, and persists
  Future<Book?> importPdf() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (files.isEmpty) {
      return null;
    }

    final pickedPath = files.first.path;
    if (pickedPath == null || !File(pickedPath).existsSync()) {
      return null;
    }

    final originalName = files.first.name;
    final bookId = _uuid.v4();

    // Prepare App Documents sandbox directories
    final appDocDir = await getApplicationDocumentsDirectory();
    final booksDir = Directory(p.join(appDocDir.path, 'books'));
    final thumbsDir = Directory(p.join(appDocDir.path, 'thumbnails'));

    if (!booksDir.existsSync()) await booksDir.create(recursive: true);
    if (!thumbsDir.existsSync()) await thumbsDir.create(recursive: true);

    // Copy PDF to internal sandbox
    final destPdfPath = p.join(booksDir.path, '$bookId.pdf');
    await File(pickedPath).copy(destPdfPath);

    // Open PDF to get page count and rasterize Page 1 for thumbnail
    int totalPages = 1;
    final thumbPath = p.join(thumbsDir.path, '$bookId.png');

    try {
      final document = await PdfDocument.openFile(destPdfPath);
      totalPages = document.pagesCount;

      if (totalPages > 0) {
        final page = await document.getPage(1);
        final pageImage = await page.render(
          width: page.width * 1.5,
          height: page.height * 1.5,
          format: PdfPageImageFormat.png,
        );
        await page.close();

        if (pageImage != null && pageImage.bytes.isNotEmpty) {
          await File(thumbPath).writeAsBytes(pageImage.bytes);
        }
      }
      await document.close();
    } catch (_) {
      // In case of thumbnail generation failure, proceed gracefully
    }

    // Clean title from filename
    String title = originalName;
    if (title.toLowerCase().endsWith('.pdf')) {
      title = title.substring(0, title.length - 4);
    }
    title = title.replaceAll(RegExp(r'[_-]'), ' ').trim();

    final newBook = Book(
      id: bookId,
      title: title,
      pdfPath: destPdfPath,
      thumbnailPath: File(thumbPath).existsSync() ? thumbPath : '',
      currentPage: 0,
      totalPages: totalPages > 0 ? totalPages : 1,
      lastReadAt: DateTime.now(),
    );

    final books = await getBooks();
    books.insert(0, newBook);
    await _saveBooks(books);

    return newBook;
  }

  /// Updates reading position in memory immediately, and debounces disk write.
  /// Set [immediate] to true when exiting or pausing to guarantee instant disk commit.
  Future<void> updateProgress(String bookId, int pageIndex, {bool immediate = false}) async {
    final books = await getBooks();
    final index = books.indexWhere((b) => b.id == bookId);

    if (index == -1) return;

    // Update in-memory state instantly so UI always has current progress
    books[index] = books[index].copyWith(
      currentPage: pageIndex,
      lastReadAt: DateTime.now(),
    );
    _cachedBooks = books;

    _debounceSaveTimer?.cancel();

    if (immediate) {
      await _saveBooks(books);
    } else {
      // Debounce disk write by 600ms to eliminate stutter during rapid page flipping
      _debounceSaveTimer = Timer(const Duration(milliseconds: 600), () async {
        if (_cachedBooks != null) {
          await _saveBooks(_cachedBooks!);
        }
      });
    }
  }

  /// Flushes any pending debounced progress writes to disk immediately
  Future<void> flush() async {
    _debounceSaveTimer?.cancel();
    if (_cachedBooks != null) {
      await _saveBooks(_cachedBooks!);
    }
  }

  /// Renames a book safely
  Future<void> renameBook(String bookId, String newTitle) async {
    final books = await getBooks();
    final index = books.indexWhere((b) => b.id == bookId);
    if (index != -1) {
      books[index] = books[index].copyWith(
        title: newTitle.trim(),
      );
      await _saveBooks(books);
    }
  }

  /// Deletes a book safely with early return if not found (Bug 1 Fix)
  Future<void> deleteBook(String bookId) async {
    final books = await getBooks();
    final index = books.indexWhere((b) => b.id == bookId);

    // If book is not found or list is empty, exit immediately — never touch random books!
    if (index == -1) return;

    final target = books[index];

    // Delete sandboxed PDF and thumbnail files
    try {
      final pdfFile = File(target.pdfPath);
      if (pdfFile.existsSync()) {
        await pdfFile.delete();
      }
      if (target.thumbnailPath.isNotEmpty) {
        final thumbFile = File(target.thumbnailPath);
        if (thumbFile.existsSync()) {
          await thumbFile.delete();
        }
      }
    } catch (_) {}

    books.removeAt(index);
    await _saveBooks(books);
  }
}
