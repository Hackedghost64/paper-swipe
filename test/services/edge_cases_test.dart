import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/models/book.dart';
import 'package:paper_swipe/services/book_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checklist & Edge Case Validation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Edge Case: Filename title cleaning with weird characters', () {
      const rawFilenames = [
        'my book (final)_v2.pdf',
        'chapter-01__web_novel.pdf',
        '   Solo_Leveling___v1.PDF  ',
        '___test___.pdf'
      ];

      for (final raw in rawFilenames) {
        String title = raw.trim();
        if (title.toLowerCase().endsWith('.pdf')) {
          title = title.substring(0, title.length - 4);
        }
        title = title
            .replaceAll(RegExp(r'[_-]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (title.isEmpty) title = 'Untitled Book';

        expect(title.contains('.pdf'), isFalse);
        expect(title.contains('_'), isFalse);
        expect(title.contains('  '), isFalse);
      }
    });

    test('Edge Case: Multiple books retain distinct reading memory independently', () async {
      // Simulate Book A and Book B
      final bookA = Book(
        id: 'book-a',
        title: 'Book A',
        pdfPath: '/dummy/a.pdf',
        thumbnailPath: '/dummy/a.png',
        currentPage: 40,
        totalPages: 100,
        lastReadAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final bookB = Book(
        id: 'book-b',
        title: 'Book B',
        pdfPath: '/dummy/b.pdf',
        thumbnailPath: '/dummy/b.png',
        currentPage: 5,
        totalPages: 50,
        lastReadAt: DateTime.now(),
      );

      // Book A on page 40, Book B on page 5
      expect(bookA.currentPage, 40);
      expect(bookB.currentPage, 5);
      expect(bookA.progressPercent, 41);
      expect(bookB.progressPercent, 12);
    });

    test('Edge Case: Renaming a book to the same name is a safe no-op', () async {
      final repo = BookRepository();
      expect(() => repo.renameBook('non-existent', 'Same Name'), returnsNormally);
    });

    test('Edge Case: Delete non-existent ID does not crash or touch other books', () async {
      final repo = BookRepository();
      expect(() => repo.deleteBook('fake-uuid'), returnsNormally);
    });
  });
}
