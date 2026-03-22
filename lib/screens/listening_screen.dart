import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen>
    with TickerProviderStateMixin {
  final _recorder = AudioRecorder();
  String _statusText = 'Listening...';
  bool _hasError = false;
  bool _found = false;
  bool _searching = false;
  Map<String, dynamic>? _result;

  // Core circle breathe
  late AnimationController _breatheController;
  late Animation<double> _breatheAnim;

  // Radar waves — 3 staggered rings
  late AnimationController _radarController;

  // Music notes popping around circle
  late AnimationController _notesController;

  // "Found" text fade
  late AnimationController _foundController;
  late Animation<double> _foundAnim;

  // Navigate after notes finish
  late AnimationController _exitController;
  late Animation<double> _exitAnim;

  final List<_FloatingNote> _notes = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _breatheAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _notesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _foundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _foundAnim = CurvedAnimation(
      parent: _foundController,
      curve: Curves.easeOutCubic,
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _exitAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );

// AFTER
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _result != null && mounted) {
        // Reset visual state before pushing so ListeningScreen looks
        // clean and idle during predictive back peek
        setState(() {
          _found = false;
          _searching = false;
          _statusText = 'Listening...';
        });
        _breatheController.repeat(reverse: true);
        _radarController.stop();
        _notesController.reset();
        _foundController.reset();

        Navigator.pushReplacementNamed(context, '/result', arguments: _result);      }
    });

    _generateNotes();
    startRecording();
  }

  void _generateNotes() {
    const noteSymbols = ['♩', '♪', '♫', '♬', '𝅗𝅥'];
    _notes.clear();
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi + _rng.nextDouble() * 0.4;
      _notes.add(_FloatingNote(
        symbol: noteSymbols[_rng.nextInt(noteSymbols.length)],
        angle: angle,
        radius: 110 + _rng.nextDouble() * 40,
        delay: _rng.nextDouble() * 0.45,
        size: 18 + _rng.nextDouble() * 14,
        rotationDir: _rng.nextBool() ? 1 : -1,
      ));
    }
  }

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _statusText = 'Microphone permission denied';
        });
        HapticFeedback.heavyImpact();
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _searching = true;
      _statusText = 'Listening...';
    });

    _radarController.repeat();

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/audio.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    await Future.delayed(const Duration(seconds: 6));

    if (!mounted) return;
    setState(() => _statusText = 'Identifying...');

    final filePath = await _recorder.stop();
    if (!mounted || filePath == null) return;

    try {
      final result = await ApiService.identify(filePath);
      if (!mounted) return;

      _result = result;
      _onSongFound();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _radarController.stop();
      setState(() {
        _hasError = true;
        _statusText = 'Tap to try again';
      });
    }
  }

  Future<void> _onSongFound() async {
    _radarController.stop();

    // Haptic punch
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.lightImpact();

    setState(() => _found = true);
    _foundController.forward();
    _notesController.forward();

    // Wait for notes to peak then exit
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    _exitController.forward();
  }

  void _retry() async {
    await HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      _found = false;
      _searching = false;
      _statusText = 'Listening...';
    });
    _notesController.reset();
    _foundController.reset();
    _exitController.reset();
    _breatheController.repeat(reverse: true);
    _generateNotes();
    startRecording();
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _radarController.dispose();
    _notesController.dispose();
    _foundController.dispose();
    _exitController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: FadeTransition(
        opacity: _exitAnim,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radar rings — only while searching
              if (_searching && !_found)
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (_, __) => CustomPaint(
                    size: Size(MediaQuery.of(context).size.width,
                        MediaQuery.of(context).size.width),
                    painter: _RadarPainter(
                      progress: _radarController.value,
                      color: cs.primary,
                    ),
                  ),
                ),

              // Floating music notes on found
              if (_found)
                ..._notes.map((note) => _FloatingNoteWidget(
                  note: note,
                  animation: _notesController,
                  color: cs.primary,
                )),

// AFTER — wrap with GestureDetector, swap mic icon for exclamation
              GestureDetector(
                onTap: _hasError ? _retry : null,
                child: AnimatedBuilder(
                  animation: _breatheAnim,
                  builder: (_, child) => Transform.scale(
                    scale: _found ? 1.0 : _breatheAnim.value,
                    child: child,
                  ),
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasError
                          ? cs.errorContainer
                          : _found
                          ? cs.primary
                          : cs.primaryContainer,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _hasError
                            ? Icon(
                          Icons.priority_high_rounded,
                          key: const ValueKey('err'),
                          size: 56,
                          color: cs.onErrorContainer,
                        )
                            : Text(
                          '♫',
                          key: ValueKey(_found),
                          style: TextStyle(
                            fontSize: 56,
                            color: _found
                                ? cs.onPrimary
                                : cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // "Found" label that appears below circle
              if (_found)
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.33,
                  child: FadeTransition(
                    opacity: _foundAnim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.5),
                        end: Offset.zero,
                      ).animate(_foundAnim),
                      child: Text(
                        'Found',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                ),

              // Status text
              if (!_found)
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.28,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      _statusText,
                      key: ValueKey(_statusText),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _hasError
                            ? cs.error
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Radar rings painter ────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const ringCount = 3;
    const maxRadius = 200.0;
    const minRadius = 90.0;

    for (int i = 0; i < ringCount; i++) {
      final delay = i / ringCount;
      final t = ((progress - delay) % 1.0 + 1.0) % 1.0;

      final radius = minRadius + (maxRadius - minRadius) * t;
      final opacity = (1.0 - t) * 0.55;

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress;
}

// ─── Floating note data ──────────────────────────────────────────────────────

class _FloatingNote {
  final String symbol;
  final double angle;
  final double radius;
  final double delay;
  final double size;
  final int rotationDir;

  const _FloatingNote({
    required this.symbol,
    required this.angle,
    required this.radius,
    required this.delay,
    required this.size,
    required this.rotationDir,
  });
}

// ─── Floating note widget ────────────────────────────────────────────────────

class _FloatingNoteWidget extends StatelessWidget {
  final _FloatingNote note;
  final AnimationController animation;
  final Color color;

  const _FloatingNoteWidget({
    required this.note,
    required this.animation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final raw = (animation.value - note.delay).clamp(0.0, 1.0);

        // Arc: rise fast, hold, then drift up
        final rise = Curves.easeOutBack.transform(
          Curves.easeOut.transform(raw.clamp(0.0, 0.7) / 0.7),
        );

        // Fade: in fast, out slow
        final double opacity;
        if (raw < 0.2) {
          opacity = raw / 0.2;
        } else if (raw < 0.75) {
          opacity = 1.0;
        } else {
          opacity = 1.0 - ((raw - 0.75) / 0.25);
        }

        // Start just outside circle, surface outward + upward
        final startRadius = 85.0;
        final currentRadius = startRadius + note.radius * rise;
        final floatUp = -20.0 * raw; // subtle upward drift

        final x = cos(note.angle) * currentRadius;
        final y = sin(note.angle) * currentRadius + floatUp;

        final rotation = note.rotationDir * raw * 0.4;

        return Transform.translate(
          offset: Offset(x, y),
          child: Transform.rotate(
            angle: rotation,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Text(
                note.symbol,
                style: TextStyle(
                  fontSize: note.size,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}