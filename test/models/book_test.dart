import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/models/book.dart';

void main() {
  group('Book Model Tests', () {
    test('Calculates progress and percentage correctly', () {
      final book = Book(
        id: 'test-1',
        title: 'Test Web Novel',
        pdfPath: '/path/to/novel.pdf',
        thumbnailPath: '/path/to/thumb.png',
        currentPage: 24, // 25th page
        totalPages: 100,
        lastReadAt: DateTime.parse('2026-10-11T12:00:00Z'),
      );

      expect(book.progress, closeTo(0.25, 0.001));
      expect(book.progressPercent, 25);
    });

    test('Clamps progress to 1.0 when at last page', () {
      final book = Book(
        id: 'test-2',
        title: 'Finished Book',
        pdfPath: '/path/to/book.pdf',
        thumbnailPath: '/path/to/thumb.png',
        currentPage: 99,
        totalPages: 100,
        lastReadAt: DateTime.now(),
      );

      expect(book.progress, closeTo(1.0, 0.001));
      expect(book.progressPercent, 100);
    });

    test('Serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final original = Book(
        id: 'uuid-123',
        title: 'The Great Journey',
        pdfPath: '/app/books/uuid-123.pdf',
        thumbnailPath: '/app/thumbs/uuid-123.png',
        currentPage: 42,
        totalPages: 200,
        lastReadAt: now,
      );

      final json = original.toJson();
      final reconstructed = Book.fromJson(json);

      expect(reconstructed.id, original.id);
      expect(reconstructed.title, original.title);
      expect(reconstructed.pdfPath, original.pdfPath);
      expect(reconstructed.thumbnailPath, original.thumbnailPath);
      expect(reconstructed.currentPage, 42);
      expect(reconstructed.totalPages, 200);
      expect(
        reconstructed.lastReadAt.millisecondsSinceEpoch,
        original.lastReadAt.millisecondsSinceEpoch,
      );
    });

    test('copyWith updates fields as expected', () {
      final original = Book(
        id: 'uuid-1',
        title: 'Original Title',
        pdfPath: '/path/1.pdf',
        thumbnailPath: '/path/1.png',
        currentPage: 0,
        totalPages: 50,
        lastReadAt: DateTime(2026, 1, 1),
      );

      final updated = original.copyWith(
        currentPage: 10,
        title: 'New Title',
      );

      expect(updated.id, original.id);
      expect(updated.title, 'New Title');
      expect(updated.currentPage, 10);
      expect(updated.totalPages, 50);
      expect(updated.pdfPath, original.pdfPath);
    });
  });
}
