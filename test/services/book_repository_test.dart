import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/services/book_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookRepository Edge Case & Resilience Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('deleteBook does not throw when library is empty (Bug 1 Fix)', () async {
      final repo = BookRepository();

      // Expect this to complete without throwing StateError: No element
      expect(() => repo.deleteBook('non-existent-id'), returnsNormally);
      final books = await repo.getBooks();
      expect(books, isEmpty);
    });

    test('getBooks handles empty storage gracefully', () async {
      final repo = BookRepository();
      final books = await repo.getBooks();
      expect(books, isEmpty);
    });

    test('updateProgress on non-existent book returns normally', () async {
      final repo = BookRepository();
      expect(() => repo.updateProgress('fake-id', 5, immediate: true), returnsNormally);
    });
  });
}
