import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:http/http.dart' as http;

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late Map data;
  List _lyrics = [];
  int currentIndex = 0;
  bool _initialized = false;
  bool _isPaused = false;

  List<GlobalKey> _lyricKeys = [];
  Timer? _timer;
  DateTime? _syncStartTime;
  double _syncStartOffset = 0;
  double _pausedAtOffset = 0;

  // Palette colors
  Color _bgTop = const Color(0xFF1A1A2E);
  Color _bgBottom = const Color(0xFF0D0D0D);
  Color _accentColor = const Color(0xFF6750A4);
  Color _textColor = Colors.white;
  bool _paletteLoaded = false;

  late ScrollController _scrollController;
  late AnimationController _entranceController;
  late AnimationController _lineHighlightController;
  late AnimationController _albumArtController;
  late Animation<double> _entranceAnim;
  late Animation<double> _lineScale;
  late Animation<double> _albumArtAnim;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _lineHighlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _albumArtController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _entranceAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );

    _lineScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _lineHighlightController, curve: Curves.elasticOut),
    );

    _albumArtAnim = CurvedAnimation(
      parent: _albumArtController,
      curve: Curves.easeOutCubic,
    );
  }

// In didChangeDependencies, replace the _scrollController line and _startSync call:

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      data = ModalRoute.of(context)!.settings.arguments as Map;

      print('=== RESULT SCREEN DATA ===');
      print('title: ${data['title']}');
      print('albumArt: ${data['albumArt']}');  // ← is it here?
      print('all keys: ${data.keys.toList()}');
      print('==========================');

      _lyrics = (data['lyrics'] as List?) ?? [];
      _lyricKeys = List.generate(_lyrics.length, (_) => GlobalKey());

      final startIndex = (data['currentIndex'] as num?)?.toInt() ?? 0;
      const estimatedItemHeight = 52.0;
      final viewportHeight = MediaQuery.of(context).size.height;
      final initialOffset = (startIndex * estimatedItemHeight -
          viewportHeight * 0.38)
          .clamp(0.0, double.infinity);

      _scrollController = ScrollController(initialScrollOffset: initialOffset);

      _entranceController.forward();
      HapticFeedback.lightImpact();
      _startSync();

      final albumArt = data['albumArt'] as String? ?? '';
      print('albumArt value being passed to _loadPalette: "$albumArt"');
      if (albumArt.isNotEmpty) {
        _loadPalette(albumArt);
      } else {
        print('albumArt is EMPTY — _loadPalette not called');
      }
    }
  }

  Future<void> _loadPalette(String imageUrl) async {
    print('=== PALETTE DEBUG ===');
    print('Image URL: $imageUrl');  // is URL even arriving?

    if (imageUrl.isEmpty) {
      print('URL is empty — albumArt not coming from backend');
      return;
    }

    try {
      final response = await http.get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 6));

      print('Image fetch status: ${response.statusCode}');
      print('Image bytes length: ${response.bodyBytes.length}');

      if (response.statusCode != 200) return;

      final imageProvider = MemoryImage(response.bodyBytes);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      );

      print('dominant:    ${palette.dominantColor?.color}');
      print('vibrant:     ${palette.vibrantColor?.color}');
      print('darkVibrant: ${palette.darkVibrantColor?.color}');
      print('darkMuted:   ${palette.darkMutedColor?.color}');

      if (!mounted) return;

      setState(() {
        _bgTop       = palette.darkVibrantColor?.color ??
            palette.darkMutedColor?.color ??
            palette.dominantColor?.color ??
            _bgTop;
        _bgBottom    = palette.darkMutedColor?.color ??
            palette.dominantColor?.color ??
            _bgBottom;
        _accentColor = palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.dominantColor?.color ??
            _accentColor;

        final luminance = _bgTop.computeLuminance();
        _textColor   = luminance > 0.35 ? Colors.black : Colors.white;
        _paletteLoaded = true;
      });

      print('_bgTop set to: $_bgTop');
      print('_accentColor set to: $_accentColor');
      print('=== END PALETTE DEBUG ===');

      _albumArtController.forward();
    } catch (e) {
      print('Palette error: $e');
    }
  }

  void _startSync() {
    if (_lyrics.isEmpty) return;

    final serverOffset = (data['offset'] as num).toDouble();
    final requestSentAt = data['requestSentAt'] as DateTime;

    // How many seconds have passed since the recording snapshot was taken
    final elapsedSinceRequest = DateTime.now().difference(requestSentAt).inMilliseconds / 1000.0;

    // True position in the song right now
    _syncStartOffset = serverOffset + elapsedSinceRequest;
    _syncStartTime = DateTime.now();

    currentIndex = (data['currentIndex'] as num?)?.toInt() ?? 0;

    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_isPaused || _syncStartTime == null) return;

      final realElapsed = _syncStartOffset +
          DateTime.now().difference(_syncStartTime!).inMilliseconds / 1000.0;

      int newIndex = 0;
      for (int i = 0; i < _lyrics.length; i++) {
        if ((_lyrics[i]['time'] as num) <= realElapsed) {
          newIndex = i;
        } else {
          break;
        }
      }

      if (newIndex != currentIndex) {
        setState(() => currentIndex = newIndex);
        HapticFeedback.selectionClick();
        _lineHighlightController.forward(from: 0);
        _autoScroll(newIndex);
      }
    });
  }

  void _togglePause() async {
    await HapticFeedback.mediumImpact();

    if (_isPaused) {
      // Resume — reset anchor so sync continues from where we paused
      _syncStartOffset = _pausedAtOffset;
      _syncStartTime = DateTime.now();
      setState(() => _isPaused = false);
    } else {
      // Pause — record current elapsed position
      if (_syncStartTime != null) {
        _pausedAtOffset = _syncStartOffset +
            DateTime.now().difference(_syncStartTime!).inMilliseconds / 1000.0;
      }
      setState(() => _isPaused = true);
    }
  }

  void _autoScroll(int index, {bool animated = true}) {
    if (index < 0 || index >= _lyricKeys.length) return;
    final key = _lyricKeys[index];
    if (key.currentContext == null) return;

    Scrollable.ensureVisible(
      key.currentContext!,
      alignment: 0.38,
      duration: animated ? const Duration(milliseconds: 500) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  void _seekTo(int index) async {
    HapticFeedback.selectionClick();

    final seekTime = (_lyrics[index]['time'] as num).toDouble();
    _syncStartOffset = seekTime;
    _syncStartTime = DateTime.now();
    _pausedAtOffset = seekTime;

    setState(() => currentIndex = index);
    _autoScroll(index);
  }

  void _relisten() async {
    await HapticFeedback.mediumImpact();
    _timer?.cancel();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entranceController.dispose();
    _lineHighlightController.dispose();
    _albumArtController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title'] ?? 'Unknown';
    final artist = data['artist'] ?? '';
    final albumArt = data['albumArt'] as String? ?? '';
    final isSynced = data['synced'] ?? false;

        return Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgTop, _bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: AnimatedBuilder(
          animation: _entranceAnim,
          builder: (context, child) => Opacity(
            opacity: _entranceAnim.value,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - _entranceAnim.value)),
              child: child,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(title, artist, albumArt),
                const SizedBox(height: 4),
                if (isSynced) _buildSyncBadge(),
                const SizedBox(height: 4),
                Expanded(
                  child: isSynced
                      ? _buildSyncedLyrics()
                      : _buildPlainLyrics(),
                ),
                _buildControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title, String artist, String albumArt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _relisten,
            icon: Icon(Icons.mic_rounded, color: _textColor.withOpacity(0.8)),
            tooltip: 'Listen again',
          ),
          const SizedBox(width: 8),

          // Album art
          if (albumArt.isNotEmpty)
            FadeTransition(
              opacity: _albumArtAnim,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  albumArt,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 52),
                ),
              ),
            ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist.isNotEmpty)
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: 13,
                      color: _textColor.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBadge() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accentColor.withOpacity(0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_rounded, size: 13, color: _accentColor),
              const SizedBox(width: 4),
              Text(
                'Synced lyrics',
                style: TextStyle(
                  fontSize: 12,
                  color: _accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pause / Resume button
          GestureDetector(
            onTap: _togglePause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentColor.withOpacity(0.2),
                border: Border.all(color: _accentColor.withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: _textColor,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncedLyrics() {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent
        ],
        stops: const [0.0, 0.07, 0.88, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
        itemCount: _lyrics.length,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemBuilder: (context, index) {
          final isActive = index == currentIndex;
          final isPast = index < currentIndex;

          return GestureDetector(
            onTap: () => _seekTo(index),
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: _lyricKeys[index],
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: isActive ? 26 : 18,
                  height: 1.4,
                  color: isActive
                      ? _textColor
                      : isPast
                      ? _textColor.withOpacity(0.28)
                      : _textColor.withOpacity(0.55),
                  fontWeight:
                  isActive ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: isActive ? -0.5 : 0.1,
                ),
                child: isActive
                    ? AnimatedBuilder(
                  animation: _lineScale,
                  builder: (_, child) => Transform.scale(
                    scale: _lineScale.value,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                  child: _LyricLine(
                    text: _lyrics[index]['text'],
                    isActive: true,
                    accentColor: _accentColor,
                    textColor: _textColor,
                  ),
                )
                    : _LyricLine(
                  text: _lyrics[index]['text'],
                  isActive: false,
                  accentColor: _accentColor,
                  textColor: _textColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlainLyrics() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: _lyrics.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          _lyrics[index]['text'],
          style: TextStyle(
            fontSize: 16,
            color: _textColor.withOpacity(0.7),
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

class _LyricLine extends StatelessWidget {
  final String text;
  final bool isActive;
  final Color accentColor;
  final Color textColor;

  const _LyricLine({
    required this.text,
    required this.isActive,
    required this.accentColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return Text(text);

    return Stack(
      children: [
        // Soft glow using accent color
        Text(
          text,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8
              ..color = accentColor.withOpacity(0.2)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
          ),
        ),
        Text(text),
      ],
    );
  }
}