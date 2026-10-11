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
  final Uuid _uuid = const Uuid();

  /// Loads all stored books sorted by most recently read
  Future<List<Book>> getBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonListStr = prefs.getString(_storageKey);
    if (jsonListStr == null || jsonListStr.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(jsonListStr) as List<dynamic>;
      final books = decoded
          .map((item) => Book.fromJson(item as Map<String, dynamic>))
          .toList();

      // Filter out any books whose PDF files no longer exist
      final validBooks = <Book>[];
      for (final book in books) {
        if (File(book.pdfPath).existsSync()) {
          validBooks.add(book);
        }
      }

      // Sort by lastReadAt descending
      validBooks.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
      return validBooks;
    } catch (e) {
      return [];
    }
  }

  /// Saves list of books to persistent storage
  Future<void> _saveBooks(List<Book> books) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(books.map((b) => b.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
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
    } catch (e) {
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

  /// Updates reading position & last read timestamp
  Future<void> updateProgress(String bookId, int pageIndex) async {
    final books = await getBooks();
    final index = books.indexWhere((b) => b.id == bookId);
    if (index != -1) {
      final book = books[index];
      books[index] = book.copyWith(
        currentPage: pageIndex,
        lastReadAt: DateTime.now(),
      );
      await _saveBooks(books);
    }
  }

  /// Renames a book
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

  /// Deletes a book and cleans up internal storage
  Future<void> deleteBook(String bookId) async {
    final books = await getBooks();
    final target = books.firstWhere((b) => b.id == bookId, orElse: () => books.first);

    // Delete PDF and thumbnail files
    try {
      if (File(target.pdfPath).existsSync()) {
        await File(target.pdfPath).delete();
      }
      if (target.thumbnailPath.isNotEmpty && File(target.thumbnailPath).existsSync()) {
        await File(target.thumbnailPath).delete();
      }
    } catch (_) {}

    books.removeWhere((b) => b.id == bookId);
    await _saveBooks(books);
  }
}
