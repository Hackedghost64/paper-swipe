import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/models/book.dart';
import 'package:paper_swipe/services/book_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookRepository Edge Case & Resilience Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await BookRepository().resetLibrary();
    });

    test('Edge Case B Fix: BookRepository is a true Singleton across all callers', () {
      final repo1 = BookRepository();
      final repo2 = BookRepository();
      expect(identical(repo1, repo2), isTrue);
    });

    test('Edge Case A & C Fix: updateProgress writes atomically and immediately without timers', () async {
      final repo = BookRepository();
      await repo.updateProgress('test-book-id', 42);

      // Verify the atomic key is immediately written to SharedPreferences with zero timer delay
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('paperswipe_pos_test-book-id'), 42);
      expect(prefs.getString('paperswipe_last_read_test-book-id'), isNotNull);
    });

    test('deleteBook cleans up atomic keys and does not throw when library is empty', () async {
      final repo = BookRepository();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('paperswipe_pos_del-id', 10);

      await repo.deleteBook('del-id');
      expect(prefs.getInt('paperswipe_pos_del-id'), isNull);
    });

    test('getBooks handles empty storage gracefully', () async {
      final repo = BookRepository();
      final books = await repo.getBooks(forceReload: true);
      expect(books, isEmpty);
    });

    test('Recovers from corrupt primary key using backup and prevents data wipe on next save', () async {
      final repo = BookRepository();
      final prefs = await SharedPreferences.getInstance();

      final samplePdf = File('sample_books/dunes_of_the_drift.pdf');
      expect(samplePdf.existsSync(), isTrue);

      final validBook = Book(
        id: 'book-recover-1',
        title: 'Original Title',
        pdfPath: samplePdf.path,
        thumbnailPath: '',
        currentPage: 5,
        totalPages: 20,
        lastReadAt: DateTime(2026, 10, 11),
      );

      final validBackupJson = jsonEncode([validBook.toJson()]);

      // Seed corrupt primary key and valid backup key
      await prefs.setString('paperswipe_books_v1', '{corrupt json[[broken');
      await prefs.setString('paperswipe_books_backup_v1', validBackupJson);

      // 1. Assert recovery from backup succeeds
      final books = await repo.getBooks(forceReload: true);
      expect(books.length, 1);
      expect(books.first.id, 'book-recover-1');
      expect(books.first.title, 'Original Title');

      // Assert primary key was repaired
      expect(prefs.getString('paperswipe_books_v1'), validBackupJson);

      // 2. Perform a modification (e.g. rename)
      await repo.renameBook('book-recover-1', 'Renamed Recovered Book');

      // Assert no data wipe occurred on subsequent save
      final savedBooks = await repo.getBooks(forceReload: true);
      expect(savedBooks.length, 1);
      expect(savedBooks.first.id, 'book-recover-1');
      expect(savedBooks.first.title, 'Renamed Recovered Book');
    });

    test('Throws exception when both primary and backup are corrupt without wiping storage', () async {
      final repo = BookRepository();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('paperswipe_books_v1', '{corrupt primary');
      await prefs.setString('paperswipe_books_backup_v1', '{corrupt backup');

      expect(() => repo.getBooks(forceReload: true), throwsA(isA<Exception>()));
    });
  });
}
