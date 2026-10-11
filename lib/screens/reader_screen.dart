import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';
import 'package:kittentts/kittentts_flutter.dart';
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

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late PdfController _pdfController;
  late int _currentPage;
  late int _totalPages;
  bool _showHud = false;
  bool _nightInvert = false;
  bool _isLoading = true;
  String? _errorMessage;
  final _KittenAudioPlayer _kittenPlayer = _KittenAudioPlayer();
  final Map<int, String> _pageText = {};
  KittenTTS? _kittenTts;
  Timer? _highlightTimer;
  final Stopwatch _playbackClock = Stopwatch();
  bool _isReadAlongVisible = false;
  bool _isLoadingReadAlong = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _isPreparingVoice = false;
  String? _readAlongError;
  String _spokenText = '';
  List<KittenWordTiming> _wordTimings = const [];
  int? _activeWordIndex;

  // Inversion matrix to convert white PDF pages to dark surfaces
  static const ColorFilter _nightInvertFilter = ColorFilter.matrix([
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 1-based page index for PdfController
    _currentPage = (widget.book.currentPage + 1).clamp(
      1,
      widget.book.totalPages,
    );
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
    widget.bookRepository.updateProgress(widget.book.id, _currentPage - 1);
    _stopNarration();
    _kittenTts?.dispose();
    _kittenPlayer.dispose();
    if (!_isLoading) _pdfController.dispose();

    // Restore standard system UI bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int page) {
    _stopNarration();
    setState(() {
      _currentPage = page;
      _isSpeaking = false;
      _isPaused = false;
      _activeWordIndex = null;
      _isReadAlongVisible = false;
    });
    // Atomic non-blocking save of current page position
    widget.bookRepository.updateProgress(widget.book.id, page - 1);
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

  Future<void> _openReadAlong() async {
    setState(() {
      _showHud = true;
      _isReadAlongVisible = true;
      _isLoadingReadAlong = true;
      _readAlongError = null;
      _activeWordIndex = null;
    });

    try {
      final text = await _textForPage(_currentPage);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        setState(() {
          _spokenText = '';
          _readAlongError = 'This page has no selectable text to read.';
          _isLoadingReadAlong = false;
        });
        return;
      }
      setState(() {
        _spokenText = text;
        _isLoadingReadAlong = false;
      });
      await _speakCurrentPage();
    } catch (_) {
      if (mounted) {
        setState(() {
          _readAlongError = 'Could not extract readable text from this page.';
          _isLoadingReadAlong = false;
        });
      }
    }
  }

  Future<String> _textForPage(int page) async {
    final cached = _pageText[page];
    if (cached != null) return cached;
    final document = await PDFDoc.fromPath(widget.book.pdfPath);
    final text = await document.pageAt(page).text;
    _pageText[page] = text;
    return text;
  }

  Future<void> _speakCurrentPage() async {
    if (_spokenText.trim().isEmpty) return;
    await _stopNarration();
    if (!mounted) return;
    setState(() => _isPreparingVoice = true);
    try {
      final tts = await _getKittenTts();
      final result = await tts.generate(
        _spokenText,
        voice: 'luna',
        speed: 0.94,
      );
      if (!mounted) return;
      setState(() {
        _wordTimings = result.wordTimings;
        _isPreparingVoice = false;
      });
      await tts.play(
        result,
        AudioPlayOptions(onPlaybackStart: _startHighlighting),
      );
      _resetNarrationState();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPreparingVoice = false;
          _readAlongError = 'Could not prepare the offline narrator.';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isSpeaking) {
      await _kittenTts?.pauseSpeaking();
      _playbackClock.stop();
      _highlightTimer?.cancel();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = true;
        });
      }
      return;
    }
    if (_isPaused) {
      await _kittenTts?.resumeSpeaking();
      _playbackClock.start();
      _startHighlightTimer();
      if (mounted) {
        setState(() {
          _isSpeaking = true;
          _isPaused = false;
        });
      }
      return;
    }
    await _speakCurrentPage();
  }

  Future<void> _closeReadAlong() async {
    await _stopNarration();
    if (mounted) {
      setState(() {
        _isReadAlongVisible = false;
        _isSpeaking = false;
        _isPaused = false;
      });
    }
  }

  Future<KittenTTS> _getKittenTts() async {
    final existing = _kittenTts;
    if (existing != null) return existing;
    final tts = await KittenTTS.create(
      player: _kittenPlayer,
      config: const KittenTTSConfig(
        model: 'micro',
        defaultVoice: 'luna',
        speed: 0.94,
        ortNumThreads: 2,
        analytics: false,
      ),
    );
    _kittenTts = tts;
    return tts;
  }

  void _startHighlighting() {
    _playbackClock
      ..reset()
      ..start();
    _startHighlightTimer();
    if (mounted) {
      setState(() {
        _isPreparingVoice = false;
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }

  void _startHighlightTimer() {
    _highlightTimer?.cancel();
    _highlightTimer = Timer.periodic(const Duration(milliseconds: 45), (_) {
      if (!mounted) return;
      final elapsed = _playbackClock.elapsedMilliseconds / 1000;
      final active = _wordTimings.where(
        (timing) => elapsed >= timing.startTime && elapsed < timing.endTime,
      );
      setState(
        () => _activeWordIndex = active.isEmpty ? null : active.first.wordIndex,
      );
    });
  }

  Future<void> _stopNarration() async {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _playbackClock
      ..stop()
      ..reset();
    await _kittenTts?.stop();
    _resetNarrationState();
  }

  void _resetNarrationState() {
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
        _isPreparingVoice = false;
        _activeWordIndex = null;
      });
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
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: AppTheme.amberGold,
                    ),
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
                  IconButton(
                    icon: Icon(
                      _isReadAlongVisible
                          ? Icons.record_voice_over
                          : Icons.volume_up_outlined,
                      color: AppTheme.amberGold,
                    ),
                    onPressed: _openReadAlong,
                    tooltip: 'Read this page aloud',
                  ),
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
                          horizontal: 10,
                          vertical: 6,
                        ),
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

          // 4. Read Along sheet. Text lives outside the PDF canvas so any
          // selectable-text PDF can be followed without page-coordinate data.
          if (_isReadAlongVisible)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _buildReadAlongSheet(),
            ),

          // 5. Minimal HUD Bottom Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            bottom: _showHud
                ? MediaQuery.of(context).padding.bottom +
                      (_isReadAlongVisible ? 278 : 16)
                : -110,
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
                    value: _currentPage.toDouble().clamp(
                      1.0,
                      _totalPages.toDouble(),
                    ),
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

  Widget _buildReadAlongSheet() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 245),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xF50D0F12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over,
                size: 18,
                color: AppTheme.amberGold,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'READ ALONG',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                onPressed: _closeReadAlong,
                tooltip: 'Close read along',
              ),
            ],
          ),
          if (_isLoadingReadAlong || _isPreparingVoice)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 38),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppTheme.amberGold),
                  SizedBox(height: 12),
                  Text(
                    'Preparing Luna, your offline narrator…',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          else if (_readAlongError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                _readAlongError!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            )
          else ...[
            Expanded(
              child: SingleChildScrollView(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      height: 1.55,
                      fontSize: 15,
                    ),
                    children: _highlightedText(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isSpeaking
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: AppTheme.amberGold,
                    size: 34,
                  ),
                  onPressed: _togglePlayback,
                  tooltip: _isSpeaking
                      ? 'Pause'
                      : (_isPaused ? 'Resume page' : 'Read page'),
                ),
                const SizedBox(width: 6),
                Text(
                  _isSpeaking
                      ? 'READING PAGE $_currentPage'
                      : 'PAGE $_currentPage',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _speakCurrentPage,
                  icon: const Icon(Icons.replay, size: 17),
                  label: const Text('RESTART'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.amberGold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<InlineSpan> _highlightedText() {
    final matches = RegExp(
      r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*",
    ).allMatches(_spokenText);
    final spans = <InlineSpan>[];
    var cursor = 0;
    var wordIndex = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: _spokenText.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: wordIndex == _activeWordIndex
              ? const TextStyle(
                  color: AppTheme.obsidianBg,
                  backgroundColor: AppTheme.amberGold,
                  fontWeight: FontWeight.w700,
                )
              : null,
        ),
      );
      cursor = match.end;
      wordIndex++;
    }
    if (cursor < _spokenText.length) {
      spans.add(TextSpan(text: _spokenText.substring(cursor)));
    }
    return spans.isEmpty ? [TextSpan(text: _spokenText)] : spans;
  }
}

class _KittenAudioPlayer implements AudioPlayer {
  final audio.AudioPlayer _player = audio.AudioPlayer();

  @override
  Future<void> play(
    Float32List samples,
    int sampleRate, {
    AudioPlayOptions options = const AudioPlayOptions(),
  }) async {
    final completed = _player.onPlayerComplete.first;
    await _player.stop();
    await _player.play(
      audio.BytesSource(
        WAVEncoder.encode(samples, sampleRate),
        mimeType: 'audio/wav',
      ),
    );
    options.onPlaybackStart?.call();
    await Future.any([
      completed,
      Future<void>.delayed(
        Duration(
          milliseconds: (samples.length / sampleRate * 1000).ceil() + 750,
        ),
      ),
    ]);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  bool get isPlaying => _player.state == audio.PlayerState.playing;

  Future<void> dispose() => _player.dispose();
}
