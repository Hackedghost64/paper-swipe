import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/services/book_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookRepository Edge Case & Resilience Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
  });
}
