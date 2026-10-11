import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
  final ScrollController _readAlongScrollController = ScrollController();
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
  String _selectedVoice = 'luna';
  double _playbackSpeed = 1.0;
  int _currentSentenceIndex = 0;
  List<String> _sentences = const [];
  List<int> _sentenceOffsets = const [];
  bool _isCancelled = false;
  int _speechSessionId = 0;

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
    // Warm up TTS in background so first spoken sentence starts instantly
    _getKittenTts().then((_) {}, onError: (_) {});
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
    _readAlongScrollController.dispose();
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

  static const Map<String, String> _contractionsMap = {
    "you've": "you have",
    "you're": "you are",
    "you'll": "you will",
    "you'd": "you would",
    "i'm": "i am",
    "i've": "i have",
    "i'll": "i will",
    "i'd": "i would",
    "we've": "we have",
    "we're": "we are",
    "we'll": "we will",
    "we'd": "we would",
    "they've": "they have",
    "they're": "they are",
    "they'll": "they will",
    "they'd": "they would",
    "it's": "it is",
    "it'll": "it will",
    "that's": "that is",
    "there's": "there is",
    "what's": "what is",
    "who's": "who is",
    "don't": "do not",
    "doesn't": "does not",
    "didn't": "did not",
    "can't": "cannot",
    "won't": "will not",
    "wouldn't": "would not",
    "couldn't": "could not",
    "shouldn't": "should not",
    "isn't": "is not",
    "aren't": "are not",
    "wasn't": "was not",
    "weren't": "were not",
    "haven't": "have not",
    "hasn't": "has not",
    "hadn't": "had not",
  };

  String _cleanSpokenText(String rawText) {
    var text = rawText
        // Replace smart apostrophes / single quotes with standard ASCII apostrophe
        .replaceAll(RegExp(r'[\u2018\u2019\u201B\u2032`´]'), "'")
        // Replace smart double quotes with standard double quote
        .replaceAll(RegExp(r'[\u201C\u201D\u201E\u201F\u2033]'), '"')
        // Replace unicode dashes / hyphens with standard hyphen or space
        .replaceAll(RegExp(r'[\u2013\u2014]'), ' - ')
        // Remove soft hyphens and zero-width spaces
        .replaceAll(RegExp(r'[\u00AD\u200B\u200C\u200D\uFEFF]'), '')
        // Clean multiple whitespace / newlines
        .replaceAll(RegExp(r'[ \t]+'), ' ');

    return text.trim();
  }

  String _normalizeForPhonemizer(String sentence) {
    var s = sentence
        .replaceAll(RegExp(r'[\u2018\u2019\u201B\u2032`´]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D\u201E\u201F\u2033]'), '"');

    // Expand known contractions if any could cause phonemizer truncation or stutter
    _contractionsMap.forEach((contraction, expansion) {
      s = s.replaceAllMapped(
        RegExp('\\b$contraction\\b', caseSensitive: false),
        (match) {
          final matchedText = match.group(0)!;
          if (matchedText.isEmpty) return expansion;
          // Preserve first character casing
          final isCapitalized = matchedText[0] == matchedText[0].toUpperCase() &&
              matchedText[0] != matchedText[0].toLowerCase();
          if (isCapitalized && expansion.isNotEmpty) {
            return expansion[0].toUpperCase() + expansion.substring(1);
          }
          return expansion;
        },
      );
    });

    // Ensure spaces after commas and semicolons so clauses don't clump
    s = s.replaceAllMapped(RegExp(r'([,;:])([^\s])'), (m) => '${m[1]} ${m[2]}');
    return s.trim();
  }

  List<String> _extractSentences(String text) {
    if (text.trim().isEmpty) return const [];

    // First replace single newlines that are just line-wraps inside a paragraph with spaces
    final unwrap = text
        .replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n\n');

    // Abbreviations that should never cause sentence breaks
    const abbrevs = [
      'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'vs', 'etc', 'i.e', 'e.g',
      'u.s', 'u.k', 'fig', 'al', 'no', 'vol', 'dept', 'est', 'approx'
    ];

    final sentences = <String>[];
    final buffer = StringBuffer();
    final chars = unwrap.runes.map((r) => String.fromCharCode(r)).toList();

    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      buffer.write(ch);

      // Check for paragraph break
      if (ch == '\n' && i + 1 < chars.length && chars[i + 1] == '\n') {
        final candidate = buffer.toString().trim();
        if (candidate.isNotEmpty) {
          sentences.add(candidate);
        }
        buffer.clear();
        i++; // skip next newline
        continue;
      }

      // Check for sentence terminator
      if (ch == '.' || ch == '!' || ch == '?') {
        // Lookahead: is this a decimal number? e.g. 3.14
        final isDigitBefore = i > 0 && RegExp(r'[0-9]').hasMatch(chars[i - 1]);
        final isDigitAfter = i + 1 < chars.length && RegExp(r'[0-9]').hasMatch(chars[i + 1]);
        if (isDigitBefore && isDigitAfter) {
          continue; // Part of a number
        }

        // Lookahead: is this an abbreviation?
        final currentBuf = buffer.toString();
        final words = currentBuf.split(RegExp(r'\s+'));
        final lastWord = words.isNotEmpty ? words.last.toLowerCase().replaceAll(RegExp(r'[^a-z.]'), '') : '';
        final withoutDot = lastWord.replaceAll('.', '');
        if (abbrevs.contains(withoutDot) || (lastWord.length <= 2 && RegExp(r'^[a-z]\.$').hasMatch(lastWord))) {
          // Likely an abbreviation or initial (e.g. J. K. Rowling)
          continue;
        }

        // Lookahead: next character must be whitespace, quote, bracket, or end of string
        var isRealEnd = false;
        if (i + 1 >= chars.length) {
          isRealEnd = true;
        } else {
          var j = i + 1;
          // Consume closing quotes or brackets
          while (j < chars.length && (chars[j] == '"' || chars[j] == "'" || chars[j] == '”' || chars[j] == '’' || chars[j] == ')' || chars[j] == ']')) {
            buffer.write(chars[j]);
            j++;
            i = j - 1;
          }
          if (j >= chars.length || RegExp(r'\s').hasMatch(chars[j])) {
            isRealEnd = true;
          }
        }

        if (isRealEnd) {
          final candidate = buffer.toString().trim();
          if (candidate.isNotEmpty) {
            sentences.add(candidate);
          }
          buffer.clear();
        }
      }
    }

    final leftover = buffer.toString().trim();
    if (leftover.isNotEmpty) {
      sentences.add(leftover);
    }

    return sentences.isEmpty ? [text.trim()] : sentences;
  }

  Future<void> _speakCurrentPage() async {
    if (_spokenText.trim().isEmpty) return;
    await _stopNarration();
    if (!mounted) return;

    final sessionId = ++_speechSessionId;
    _isCancelled = false;
    _currentSentenceIndex = 0;

    // Clean text representations
    final normalizedPage = _cleanSpokenText(_spokenText);
    _sentences = _extractSentences(normalizedPage);

    // Compute cumulative word offsets for each sentence based on whole-page tokenization
    final pageWords = RegExp(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*")
        .allMatches(_spokenText)
        .toList();
    final offsets = <int>[];
    var searchIdx = 0;
    for (final sentence in _sentences) {
      final sentMatches = RegExp(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*")
          .allMatches(sentence)
          .length;
      offsets.add(searchIdx);
      searchIdx += sentMatches;
    }
    _sentenceOffsets = offsets;

    setState(() {
      _isPreparingVoice = true;
      _activeWordIndex = 0;
    });

    try {
      final tts = await _getKittenTts();
      if (_isCancelled || sessionId != _speechSessionId || !mounted) return;

      // Pipeline sliding-window pre-generation buffer (buffers up to 3 sentences ahead)
      // This compensates for 1.15x and faster speeds so audio never stutters or starves.
      const bufferAheadCount = 3;
      final prefetchMap = <int, Future<KittenTTSResult>>{};

      void primePrefetch(int startIndex) {
        for (var offset = 0; offset <= bufferAheadCount; offset++) {
          final targetIdx = startIndex + offset;
          if (targetIdx < _sentences.length && !prefetchMap.containsKey(targetIdx)) {
            final toSpeak = _normalizeForPhonemizer(_sentences[targetIdx]);
            prefetchMap[targetIdx] = tts.generate(
              toSpeak,
              voice: _selectedVoice,
              speed: _playbackSpeed,
            );
          }
        }
      }

      // Pre-warm the initial window of sentences
      primePrefetch(0);

      for (var i = 0; i < _sentences.length; i++) {
        if (_isCancelled || sessionId != _speechSessionId || !mounted) break;
        _currentSentenceIndex = i;
        final wordOffset = i < _sentenceOffsets.length ? _sentenceOffsets[i] : 0;

        // Ensure lookahead buffer is filled
        primePrefetch(i);

        final KittenTTSResult result;
        final pending = prefetchMap[i];
        if (pending != null) {
          result = await pending;
        } else {
          final toSpeak = _normalizeForPhonemizer(_sentences[i]);
          result = await tts.generate(
            toSpeak,
            voice: _selectedVoice,
            speed: _playbackSpeed,
          );
        }
        // Clean up completed future to free memory
        prefetchMap.remove(i);

        if (_isCancelled || sessionId != _speechSessionId || !mounted) break;

        // Keep filling buffer for upcoming sentences while this one plays
        primePrefetch(i + 1);

        setState(() {
          _wordTimings = result.wordTimings;
          _isPreparingVoice = false;
        });

        await tts.play(
          result,
          AudioPlayOptions(
            onPlaybackStart: () {
              if (sessionId != _speechSessionId || !mounted) return;
              _playbackClock
                ..reset()
                ..start();
              _highlightTimer?.cancel();
              _highlightTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
                if (!mounted || _isCancelled || sessionId != _speechSessionId) return;
                final elapsed = _playbackClock.elapsedMilliseconds / 1000;
                final active = _wordTimings.where(
                  (timing) => elapsed >= timing.startTime && elapsed < timing.endTime,
                );
                final sentenceWordIndex = active.isEmpty ? null : active.first.wordIndex;
                final newActiveIndex = sentenceWordIndex != null ? wordOffset + sentenceWordIndex : null;
                if (newActiveIndex != _activeWordIndex) {
                  setState(() {
                    _activeWordIndex = newActiveIndex;
                  });
                  // Auto-scroll follow the active word
                  if (newActiveIndex != null && _readAlongScrollController.hasClients && pageWords.isNotEmpty) {
                    final progress = (newActiveIndex / pageWords.length).clamp(0.0, 1.0);
                    final maxScroll = _readAlongScrollController.position.maxScrollExtent;
                    final targetOffset = maxScroll * progress;
                    if ((targetOffset - _readAlongScrollController.offset).abs() > 40) {
                      _readAlongScrollController.animateTo(
                        targetOffset,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }
                  }
                }
              });
              if (mounted && sessionId == _speechSessionId) {
                setState(() {
                  _isSpeaking = true;
                  _isPaused = false;
                });
              }
            },
          ),
        );
      }

      if (!_isCancelled && sessionId == _speechSessionId) {
        _resetNarrationState();
      }
    } catch (_) {
      if (mounted && !_isCancelled && sessionId == _speechSessionId) {
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

    final docDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${docDir.path}/kitten_tts');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final onnxFile = File('${modelDir.path}/kitten_tts_micro_v0_8.onnx');
    if (!await onnxFile.exists() || await onnxFile.length() == 0) {
      final byteData = await rootBundle.load('assets/models/kitten_tts/kitten_tts_micro_v0_8.onnx');
      await onnxFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes), flush: true);
    }

    final voicesFile = File('${modelDir.path}/voices.npz');
    if (!await voicesFile.exists() || await voicesFile.length() == 0) {
      final byteData = await rootBundle.load('assets/models/kitten_tts/voices.npz');
      await voicesFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes), flush: true);
    }

    final rulesFile = File('${modelDir.path}/en_rules');
    if (!await rulesFile.exists() || await rulesFile.length() == 0) {
      final byteData = await rootBundle.load('assets/models/kitten_tts/en_rules');
      await rulesFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes), flush: true);
    }

    final listFile = File('${modelDir.path}/en_list');
    if (!await listFile.exists() || await listFile.length() == 0) {
      final byteData = await rootBundle.load('assets/models/kitten_tts/en_list');
      await listFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes), flush: true);
    }

    final tts = await KittenTTS.create(
      player: _kittenPlayer,
      config: KittenTTSConfig(
        model: 'micro',
        defaultVoice: 'luna',
        speed: 0.94,
        ortNumThreads: 2,
        analytics: false,
        modelFiles: KittenTTSModelFiles(
          onnxPath: onnxFile.path,
          voicesPath: voicesFile.path,
        ),
        phonemizer: CEPhonemizer(
          rulesPath: rulesFile.path,
          listPath: listFile.path,
        ),
      ),
    );
    _kittenTts = tts;
    return tts;
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
    _speechSessionId++;
    _isCancelled = true;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _playbackClock
      ..stop()
      ..reset();
    await _kittenPlayer.stop();
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
            bottom: (_showHud && !_isReadAlongVisible)
                ? MediaQuery.of(context).padding.bottom + 16
                : -130,
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
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = (screenHeight * 0.35).clamp(200.0, 300.0);
    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
                size: 16,
                color: AppTheme.amberGold,
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'READ ALONG',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Voice selector dropdown
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppTheme.slateCardLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderSubtle, width: 0.8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedVoice,
                    dropdownColor: AppTheme.slateCard,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.amberGold, size: 16),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                    items: const [
                      DropdownMenuItem(value: 'luna', child: Text('Luna')),
                      DropdownMenuItem(value: 'bella', child: Text('Bella')),
                      DropdownMenuItem(value: 'jasper', child: Text('Jasper')),
                      DropdownMenuItem(value: 'bruno', child: Text('Bruno')),
                      DropdownMenuItem(value: 'rosie', child: Text('Rosie')),
                      DropdownMenuItem(value: 'hugo', child: Text('Hugo')),
                    ],
                    onChanged: (newVoice) {
                      if (newVoice != null && newVoice != _selectedVoice) {
                        setState(() => _selectedVoice = newVoice);
                        if (_isSpeaking) _speakCurrentPage();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Speed toggle button
              InkWell(
                onTap: () {
                  final nextSpeed = _playbackSpeed == 0.9
                      ? 1.0
                      : (_playbackSpeed == 1.0 ? 1.15 : 0.9);
                  setState(() => _playbackSpeed = nextSpeed);
                  if (_isSpeaking) _speakCurrentPage();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.slateCardLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderSubtle, width: 0.8),
                  ),
                  child: Center(
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.amberGold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Compact close button that never overflows
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                  onPressed: _closeReadAlong,
                  tooltip: 'Close read along',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isLoadingReadAlong)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amberGold)),
                    SizedBox(width: 10),
                    Text('Reading page text…', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_readAlongError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
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
                controller: _readAlongScrollController,
                physics: const BouncingScrollPhysics(),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      height: 1.55,
                      fontSize: 14.5,
                    ),
                    children: _highlightedText(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                      ? (_isPreparingVoice ? 'PREPARING SPEECH…' : 'READING SENTENCE ${_currentSentenceIndex + 1}/${_sentences.length}')
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
  Completer<void>? _activePlaybackCompleter;
  StreamSubscription<void>? _completeSubscription;

  @override
  Future<void> play(
    Float32List samples,
    int sampleRate, {
    AudioPlayOptions options = const AudioPlayOptions(),
  }) async {
    await stop();

    final completer = Completer<void>();
    _activePlaybackCompleter = completer;

    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    final durationMs = (samples.length / sampleRate * 1000).ceil();
    final safetyTimer = Timer(Duration(milliseconds: durationMs + 800), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _player.play(
        audio.BytesSource(
          WAVEncoder.encode(samples, sampleRate),
          mimeType: 'audio/wav',
        ),
      );
      options.onPlaybackStart?.call();
      await completer.future;
    } finally {
      safetyTimer.cancel();
      await _completeSubscription?.cancel();
      _completeSubscription = null;
      if (identical(_activePlaybackCompleter, completer)) {
        _activePlaybackCompleter = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    final comp = _activePlaybackCompleter;
    if (comp != null && !comp.isCompleted) {
      comp.complete();
    }
    _activePlaybackCompleter = null;
    await _completeSubscription?.cancel();
    _completeSubscription = null;
    await _player.stop();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  bool get isPlaying => _player.state == audio.PlayerState.playing;

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
