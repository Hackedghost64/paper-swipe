import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import '../models/book.dart';
import '../services/book_repository.dart';
import '../theme/app_theme.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository bookRepository;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.bookRepository,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  late PdfController _pdfController;
  late int _currentPage;
  late int _totalPages;
  bool _showHud = false;
  bool _nightInvert = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Inversion matrix to convert white PDF pages to dark surfaces
  static const ColorFilter _nightInvertFilter = ColorFilter.matrix([
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 1-based page index for PdfController
    _currentPage = (widget.book.currentPage + 1).clamp(1, widget.book.totalPages);
    _totalPages = widget.book.totalPages;

    // Enable sticky immersive mode for silent, distraction-free reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initPdfController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // User pressed Home, switched apps, or swiped away in recent-apps:
      // Guarantee immediate flush to disk so no page progress is ever lost!
      widget.bookRepository.updateProgress(
        widget.book.id,
        _currentPage - 1,
        immediate: true,
      );
    }
  }

  Future<void> _initPdfController() async {
    try {
      _pdfController = PdfController(
        document: PdfDocument.openFile(widget.book.pdfPath),
        initialPage: _currentPage,
      );
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load PDF document: $e';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Persist current page immediately on exit
    widget.bookRepository.updateProgress(
      widget.book.id,
      _currentPage - 1,
    );
    _pdfController.dispose();

    // Restore standard system UI bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    // Atomic non-blocking save of current page position
    widget.bookRepository.updateProgress(
      widget.book.id,
      page - 1,
    );
  }

  void _toggleHud() {
    setState(() {
      _showHud = !_showHud;
    });
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _pdfController.previousPage(
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      _pdfController.nextPage(
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nightInvert ? Colors.black : AppTheme.obsidianBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. PDF Page Viewport
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.amberGold),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            )
          else
            ColorFiltered(
              colorFilter: _nightInvert
                  ? _nightInvertFilter
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: PdfView(
                controller: _pdfController,
                onPageChanged: _onPageChanged,
                scrollDirection: Axis.horizontal,
                pageSnapping: true,
                physics: const BouncingScrollPhysics(),
                onDocumentLoaded: (document) {
                  setState(() {
                    _totalPages = document.pagesCount;
                  });
                },
              ),
            ),

          // 2. Gesture Detector Layer for Tap Zones
          Row(
            children: [
              // Left 22% width: Previous Page tap zone
              Expanded(
                flex: 22,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _previousPage,
                ),
              ),
              // Center 56% width: Toggle HUD tap zone
              Expanded(
                flex: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleHud,
                ),
              ),
              // Right 22% width: Next Page tap zone
              Expanded(
                flex: 22,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _nextPage,
                ),
              ),
            ],
          ),

          // 3. Minimal HUD Top Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: _showHud ? MediaQuery.of(context).padding.top + 10 : -90,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xEE0D0F12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderSubtle, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: AppTheme.amberGold),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back to Library',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _nightInvert
                        ? 'Disable Night Invert'
                        : 'Enable Night Invert (High-contrast for text & web novels)',
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _nightInvert = !_nightInvert;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _nightInvert
                              ? AppTheme.amberGold
                              : AppTheme.slateCardLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _nightInvert
                                ? AppTheme.amberGold
                                : AppTheme.borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _nightInvert
                                  ? Icons.nightlight_round
                                  : Icons.wb_sunny_outlined,
                              size: 14,
                              color: _nightInvert
                                  ? AppTheme.obsidianBg
                                  : AppTheme.amberGold,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _nightInvert ? 'NIGHT' : 'DAY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _nightInvert
                                    ? AppTheme.obsidianBg
                                    : AppTheme.amberGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Minimal HUD Bottom Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            bottom: _showHud ? MediaQuery.of(context).padding.bottom + 16 : -110,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: const Color(0xEE0D0F12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderSubtle, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fast Page Scrub Slider
                  Slider(
                    value: _currentPage.toDouble().clamp(1.0, _totalPages.toDouble()),
                    min: 1.0,
                    max: _totalPages > 1 ? _totalPages.toDouble() : 1.0,
                    divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                    onChanged: (val) {
                      final targetPage = val.round();
                      if (targetPage != _currentPage) {
                        _pdfController.jumpToPage(targetPage);
                        _onPageChanged(targetPage);
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PAGE $_currentPage OF $_totalPages',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${((_currentPage / (_totalPages > 0 ? _totalPages : 1)) * 100).round()}% COMPLETED',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.amberGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
