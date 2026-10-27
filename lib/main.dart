import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'paisa_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: const [SystemUiOverlay.bottom],
  );
  final store = await PaisaStore.load();
  runApp(PaisaApp(store: store));
}

const _palettes = <String, Color>{
  'cherry': Color(0xFFFF3F58),
  'toxic': Color(0xFFC7F36B),
  'ocean': Color(0xFF63AAFF),
  'violet': Color(0xFFB69AFF),
  'amber': Color(0xFFFFBF58),
};
const _paletteNames = <String, String>{
  'cherry': 'Cherry Red',
  'toxic': 'Toxic Lime',
  'ocean': 'Deep Ocean',
  'violet': 'Ultraviolet',
  'amber': 'After Hours',
};
const _incomeGreen = Color(0xFF83DF91);
const _foodCategory = 'Food & snacks';

String money(num value, {bool forceDecimals = false}) {
  final n = value.toDouble();
  final decimals = forceDecimals || n % 1 != 0 ? 2 : 0;
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimals,
  ).format(n);
}

class _SensitiveValue extends StatelessWidget {
  const _SensitiveValue({
    this.store,
    this.hidden,
    this.privacyStyle,
    required this.child,
    this.mask = '₹ ••••',
    this.style,
  });
  final PaisaStore? store;
  final bool? hidden;
  final String? privacyStyle;
  final Widget child;
  final String mask;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final isHidden = store?.privacy ?? hidden ?? false;
    final displayMode = store?.privacyStyle ?? privacyStyle ?? 'blur';
    if (!isHidden) return child;
    if (displayMode == 'blur') {
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ExcludeSemantics(child: child),
        ),
      );
    }
    return ExcludeSemantics(child: Text(mask, style: this.style));
  }
}

String dayLabel(DateTime date) => DateFormat('EEE · d MMM').format(date);
String dateLabel(DateTime date) => DateFormat('dd MMM yyyy').format(date);
String isoDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

class _AllowanceCycle {
  const _AllowanceCycle({
    required this.isPayday,
    required this.progress,
    required this.daysUntil,
    required this.payday,
  });

  final bool isPayday;
  final double progress;
  final int daysUntil;
  final DateTime payday;
}

_AllowanceCycle _allowanceCycle(DateTime value, Map<String, dynamic> schedule) {
  final date = DateTime(value.year, value.month, value.day);
  if (schedule['enabled'] != true) {
    final nextMonth = DateTime(date.year, date.month + 1, 1);
    final monthDays = nextMonth
        .difference(DateTime(date.year, date.month, 1))
        .inDays;
    return _AllowanceCycle(
      isPayday: false,
      progress: (date.day - 1) / math.max(1, monthDays - 1),
      daysUntil: nextMonth.difference(date).inDays,
      payday: nextMonth,
    );
  }

  final frequency = '${schedule['frequency'] ?? 'monthly'}';
  if (frequency == 'weekly' || frequency == 'fortnightly') {
    final anchor = DateTime.tryParse('${schedule['nextDate']}');
    if (anchor != null) {
      final interval = frequency == 'weekly' ? 7 : 14;
      final delta = date
          .difference(DateTime(anchor.year, anchor.month, anchor.day))
          .inDays;
      final elapsed = ((delta % interval) + interval) % interval;
      final isPayday = elapsed == 0;
      return _AllowanceCycle(
        isPayday: isPayday,
        progress: isPayday ? 0 : (elapsed / (interval - 1)).clamp(0.0, 1.0),
        daysUntil: isPayday ? 0 : interval - elapsed,
        payday: date.add(Duration(days: isPayday ? 0 : interval - elapsed)),
      );
    }
  }

  final storedNext = DateTime.tryParse('${schedule['nextDate']}');
  final anchorDay = schedule['anchorDay'] is num
      ? (schedule['anchorDay'] as num).round().clamp(1, 31).toInt()
      : storedNext?.day ?? 1;
  DateTime paydayIn(int year, int month) {
    final monthDays = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, math.min(anchorDay, monthDays));
  }

  final thisMonth = paydayIn(date.year, date.month);
  final isPayday = date == thisMonth;
  final previousPayday = date.isBefore(thisMonth)
      ? paydayIn(date.year, date.month - 1)
      : thisMonth;
  final nextPayday = date.isBefore(thisMonth)
      ? thisMonth
      : paydayIn(date.year, date.month + 1);
  final cycleDays = nextPayday.difference(previousPayday).inDays;
  final elapsed = date.difference(previousPayday).inDays;
  return _AllowanceCycle(
    isPayday: isPayday,
    progress: isPayday
        ? 0
        : (elapsed / math.max(1, cycleDays - 1)).clamp(0.0, 1.0),
    daysUntil: isPayday ? 0 : nextPayday.difference(date).inDays,
    payday: isPayday ? thisMonth : nextPayday,
  );
}

String categoryIcon(String category) =>
    const {
      'Food & snacks': '🍜',
      'Food delivery': '🛵',
      'Transport': '🛺',
      'College & printing': '📚',
      'Shopping': '🛍️',
      'Subscriptions': '📱',
      'Social & fun': '🎟️',
      'Personal care': '🧴',
      'Income': '↗',
      'Savings': '🏦',
      'Miscellaneous': '✳️',
    }[category] ??
    '✳️';

class PaisaApp extends StatelessWidget {
  const PaisaApp({super.key, required this.store});
  final PaisaStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final accent = _palettes[store.palette] ?? _palettes['cherry']!;
      final brightness = store.lightMode ? Brightness.light : Brightness.dark;
      final scheme =
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: brightness,
          ).copyWith(
            primary: accent,
            secondary: accent,
            surface: store.lightMode
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF141821),
          );
      return MaterialApp(
        title: 'Paisa.exe',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: brightness,
          colorScheme: scheme,
          scaffoldBackgroundColor: store.lightMode
              ? const Color(0xFFF2F4F7)
              : const Color(0xFF0B0D12),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: scheme.onSurface,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: store.lightMode
                ? Colors.white
                : const Color(0xFF11141C),
            indicatorColor: accent.withValues(alpha: .13),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 10,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: store.lightMode
                ? const Color(0xFF202630)
                : const Color(0xFF252B38),
            contentTextStyle: const TextStyle(color: Colors.white),
            behavior: SnackBarBehavior.floating,
          ),
          dividerColor: scheme.outlineVariant.withValues(alpha: .36),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: store.lightMode
                ? const Color(0xFFF6F7FA)
                : const Color(0xFF10131B),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: accent,
            selectionColor: accent.withValues(alpha: .25),
            selectionHandleColor: accent,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: store.reduceMotion),
          child: child ?? const SizedBox.shrink(),
        ),
        home: SplashSequence(store: store),
      );
    },
  );
}

// Two intentional beats: the brand, then the catchphrase.
class SplashSequence extends StatefulWidget {
  const SplashSequence({super.key, required this.store});
  final PaisaStore store;
  @override
  State<SplashSequence> createState() => _SplashSequenceState();
}

class _SplashSequenceState extends State<SplashSequence>
    with TickerProviderStateMixin {
  bool _second = false;
  bool _done = false;
  bool _payday = false;
  late final AnimationController _brandReveal;
  late final AnimationController _phraseReveal;
  late final AnimationController _orbit;
  Timer? _brandTimer;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _payday = _allowanceCycle(
      DateTime.now(),
      widget.store.recurringIncome,
    ).isPayday;
    _brandReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _phraseReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.store.reduceMotion) {
      _done = true;
    } else {
      _brandReveal.forward();
      _orbit.repeat();
      _brandTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() => _second = true);
        _phraseReveal.forward(from: 0);
      });
      _finishTimer = Timer(const Duration(milliseconds: 3800), () {
        if (mounted) setState(() => _done = true);
      });
    }
  }

  @override
  void dispose() {
    _brandTimer?.cancel();
    _finishTimer?.cancel();
    _brandReveal.dispose();
    _phraseReveal.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return PaisaShell(store: widget.store);
    final accent = Theme.of(context).colorScheme.primary;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.72, -.72),
                    radius: 1.05,
                    colors: [
                      accent.withValues(alpha: .12),
                      background,
                      background,
                    ],
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(1, viewport.maxHeight - 40),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 520),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .055),
                              end: Offset.zero,
                            ).animate(animation),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .96, end: 1).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: child,
                            ),
                          ),
                        ),
                        child: _second
                            ? _phraseStage(accent)
                            : _brandStage(accent),
                      ),
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

  Widget _brandStage(Color accent) {
    final logo = CurvedAnimation(
      parent: _brandReveal,
      curve: const Interval(0, .72, curve: Curves.easeOutBack),
    );
    final title = CurvedAnimation(
      parent: _brandReveal,
      curve: const Interval(.24, .88, curve: Curves.easeOutCubic),
    );
    final byline = CurvedAnimation(
      parent: _brandReveal,
      curve: const Interval(.48, 1, curve: Curves.easeOutCubic),
    );
    return Column(
      key: const ValueKey('brand'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: logo,
          child: ScaleTransition(
            scale: Tween<double>(begin: .28, end: 1).animate(logo),
            child: AnimatedBuilder(
              animation: _orbit,
              builder: (context, _) => Transform.scale(
                scale: 1 + (math.sin(_orbit.value * math.pi * 2) + 1) * .018,
                child: _SplashMark(accent: accent, orbit: _orbit, size: 132),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        FadeTransition(
          opacity: title,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .6),
              end: Offset.zero,
            ).animate(title),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Paisa',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: '.exe',
                      style: TextStyle(color: accent),
                    ),
                  ],
                ),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.2,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeTransition(
          opacity: byline,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .45),
              end: Offset.zero,
            ).animate(byline),
            child: _SignatureLine(accent: accent),
          ),
        ),
        const SizedBox(height: 27),
        FadeTransition(
          opacity: byline,
          child: _GlowRule(accent: accent, progress: _brandReveal),
        ),
      ],
    );
  }

  Widget _phraseStage(Color accent) {
    final lineOne = CurvedAnimation(
      parent: _phraseReveal,
      curve: const Interval(0, .62, curve: Curves.easeOutCubic),
    );
    final lineTwo = CurvedAnimation(
      parent: _phraseReveal,
      curve: const Interval(.22, .88, curve: Curves.easeOutBack),
    );
    return Column(
      key: const ValueKey('phrase'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: lineOne,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .5),
              end: Offset.zero,
            ).animate(lineOne),
            child: Text(
              _payday ? 'Fresh funds.' : 'Track the plot.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                letterSpacing: .45,
                color: Color(0xFF9299AA),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: lineTwo,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .65),
              end: Offset.zero,
            ).animate(lineTwo),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _payday ? 'Make this cycle yours.' : 'Keep the paisa.',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: -.7,
                  shadows: [
                    Shadow(color: accent.withValues(alpha: .4), blurRadius: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark({
    required this.accent,
    required this.orbit,
    required this.size,
  });
  final Color accent;
  final Animation<double> orbit;
  final double size;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: orbit,
        builder: (context, _) {
          final wiggle = math.sin(orbit.value * math.pi * 2) * .018;
          return Transform.rotate(
            angle: wiggle,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                  child: Image.asset(
                    'assets/images/paisa_logo_tintable.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _LogoMotionPainter(
                      progress: orbit,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LogoMotionPainter extends CustomPainter {
  const _LogoMotionPainter({required this.progress, required this.color});
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final scale = (size.width + size.height) / 2;
    canvas.save();
    canvas.scale(size.width / 1000, size.height / 1000);

    // A moving gloss follows the P's lower wrap, picking up the supplied ring.
    final orbitPath = Path()
      ..moveTo(300, 624)
      ..cubicTo(230, 682, 354, 736, 502, 766)
      ..cubicTo(692, 805, 643, 904, 511, 880);
    _drawMovingStroke(canvas, orbitPath, t, .31, scale * .055, color);

    // Three separately timed streaks ripple and pop above the P.
    final rays = <Path>[
      Path()
        ..moveTo(347, 112)
        ..cubicTo(336, 139, 369, 174, 381, 210),
      Path()
        ..moveTo(249, 196)
        ..cubicTo(270, 203, 302, 241, 337, 259),
      Path()
        ..moveTo(226, 286)
        ..cubicTo(255, 276, 301, 286, 326, 285),
    ];
    for (var i = 0; i < rays.length; i++) {
      final phase = (t * 1.45 + i * .27) % 1;
      final pop = math.sin(phase * math.pi).clamp(0.0, 1.0);
      _drawMovingStroke(
        canvas,
        rays[i],
        phase,
        .36,
        scale * (.047 + pop * .014),
        color.withValues(alpha: .42 + pop * .58),
      );
    }
    canvas.restore();
  }

  void _drawMovingStroke(
    Canvas canvas,
    Path path,
    double phase,
    double trailFraction,
    double strokeWidth,
    Color tint,
  ) {
    final metric = path.computeMetrics().first;
    final length = metric.length;
    final end = (phase % 1) * length;
    final start = end - length * trailFraction;
    final paint = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * .25);
    if (start < 0) {
      canvas.drawPath(metric.extractPath(0, end), paint);
      canvas.drawPath(metric.extractPath(length + start, length), paint);
    } else {
      canvas.drawPath(metric.extractPath(start, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoMotionPainter oldDelegate) =>
      oldDelegate.progress.value != progress.value ||
      oldDelegate.color != color;
}

class _SignatureLine extends StatelessWidget {
  const _SignatureLine({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    decoration: BoxDecoration(
      border: Border.all(color: accent.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(30),
      color: accent.withValues(alpha: .045),
    ),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, letterSpacing: .5),
        children: [
          const TextSpan(
            text: 'by ',
            style: TextStyle(color: Color(0xFF9299AA)),
          ),
          TextSpan(
            text: 'Likhit',
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: ' :)',
            style: TextStyle(color: accent.withValues(alpha: .68)),
          ),
        ],
      ),
    ),
  );
}

class _GlowRule extends StatelessWidget {
  const _GlowRule({required this.accent, required this.progress});
  final Color accent;
  final Animation<double> progress;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 124,
    height: 2,
    child: AnimatedBuilder(
      animation: progress,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress.value,
          minHeight: 2,
          color: accent,
          backgroundColor: accent.withValues(alpha: .12),
        ),
      ),
    ),
  );
}

class PaisaShell extends StatefulWidget {
  const PaisaShell({super.key, required this.store});
  final PaisaStore store;
  @override
  State<PaisaShell> createState() => _PaisaShellState();
}

class _PaisaShellState extends State<PaisaShell>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  int? _previousPage;
  int? _queuedPage;
  double _pageDirection = 1;
  late final AnimationController _pageMotion;
  final List<ScrollController> _tabScrollControllers = List.generate(
    6,
    (_) => ScrollController(),
  );

  @override
  void initState() {
    super.initState();
    _pageMotion =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 360),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _previousPage = null);
              final queued = _queuedPage;
              _queuedPage = null;
              if (queued != null && queued != _page) _goToPage(queued);
            }
          })
          // The incoming page starts one screen-width offstage. Start at the
          // completed position so Home is visible on the very first frame.
          ..value = 1;
  }

  @override
  void dispose() {
    _pageMotion.dispose();
    for (final controller in _tabScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _goToPage(int index) {
    if (index == _page) {
      _queuedPage = null;
      return;
    }
    // Each time a tab is opened, start its main vertical page at the top.
    // Jump before switching so the new tab never flashes its old scroll spot.
    final scrollController = _tabScrollControllers[index];
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    if (widget.store.reduceMotion) {
      _pageMotion.stop();
      _queuedPage = null;
      setState(() {
        _previousPage = null;
        _page = index;
      });
      return;
    }
    if (_pageMotion.isAnimating) {
      _queuedPage = index;
      return;
    }
    _pageDirection = index > _page ? 1 : -1;
    setState(() {
      _previousPage = _page;
      _page = index;
    });
    _pageMotion.forward(from: 0);
  }

  Widget _switchingBody(List<Widget> views) {
    final order = [
      for (var i = 0; i < views.length; i++)
        if (i != _page && i != _previousPage) i,
      _page,
      if (_previousPage != null) _previousPage!,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          for (final index in order)
            Positioned.fill(
              key: ValueKey('paisa-tab-$index'),
              child: AnimatedBuilder(
                animation: _pageMotion,
                child: PrimaryScrollController(
                  controller: _tabScrollControllers[index],
                  child: views[index],
                ),
                builder: (context, child) {
                  final isCurrent = index == _page;
                  final isLeaving = index == _previousPage;
                  final t = Curves.easeInOutCubic.transform(_pageMotion.value);
                  final visible = isCurrent || isLeaving;
                  final x = isCurrent
                      ? _pageDirection * constraints.maxWidth * (1 - t)
                      : -_pageDirection * constraints.maxWidth * t;
                  return IgnorePointer(
                    ignoring: !isCurrent,
                    child: Offstage(
                      offstage: !visible,
                      child: TickerMode(
                        enabled: isCurrent,
                        child: Transform.translate(
                          offset: Offset(x, 0),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _addTransaction([Map<String, dynamic>? preset]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TransactionEditor(store: widget.store, preset: preset),
      );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final views = [
      HomeScreen(store: store, onNavigate: _goToPage),
      ActivityScreen(store: store, onEdit: (t) => _addTransaction(t)),
      CampusScreen(
        store: store,
        onChoose: (food) => _addTransaction({
          'type': 'expense',
          'amount': food['price'],
          'description': '${food['shop']} · ${food['name']}',
          'category': _foodCategory,
          'foodItem': food['name'],
          'foodShop': food['shop'],
        }),
      ),
      BudgetsScreen(store: store),
      InsightsScreen(store: store, onPage: _goToPage),
      SettingsScreen(store: store, onPage: _goToPage),
    ];
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(67),
        child: _TopBar(
          store: store,
          onPrivacy: () => store.saveSettings(hideBalances: !store.privacy),
          onAdd: () => _addTransaction(),
        ),
      ),
      body: _switchingBody(views),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: _goToPage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_rounded),
            label: 'Campus',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_small_outlined),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.store,
    required this.onPrivacy,
    required this.onAdd,
  });
  final PaisaStore store;
  final VoidCallback onPrivacy;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 13, 7),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: accent.withValues(alpha: .2)),
              ),
              padding: const EdgeInsets.all(2),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                child: Image.asset(
                  'assets/images/paisa_logo_tintable.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'paisa'),
                  TextSpan(
                    text: '.exe',
                    style: TextStyle(color: accent),
                  ),
                ],
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                letterSpacing: -.8,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                DateFormat('EEE d MMM').format(DateTime.now()).toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _PrivacyToggle(
              hidden: store.privacy,
              disableAnimations: store.reduceMotion,
              onToggle: onPrivacy,
            ),
            Material(
              color: accent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(12),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.add_rounded,
                    color: Color(0xFF10131A),
                    size: 25,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyToggle extends StatefulWidget {
  const _PrivacyToggle({
    required this.hidden,
    required this.disableAnimations,
    required this.onToggle,
  });
  final bool hidden;
  final bool disableAnimations;
  final VoidCallback onToggle;
  @override
  State<_PrivacyToggle> createState() => _PrivacyToggleState();
}

class _PrivacyToggleState extends State<_PrivacyToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.22), weight: 28),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.22,
        end: .94,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30,
    ),
    TweenSequenceItem(tween: Tween(begin: .94, end: 1), weight: 42),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.hidden ? 'Show balances' : 'Hide balances',
    onPressed: () {
      if (!widget.disableAnimations) _controller.forward(from: 0);
      widget.onToggle();
    },
    icon: widget.disableAnimations
        ? Icon(
            widget.hidden
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            size: 20,
          )
        : ScaleTransition(
            scale: _scale,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: -.12, end: 0).animate(animation),
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                widget.hidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                key: ValueKey(widget.hidden),
                size: 20,
              ),
            ),
          ),
  );
}

class _DateStamp extends StatelessWidget {
  const _DateStamp({required this.date, required this.accent});
  final DateTime date;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: 102,
    height: 70,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 45,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: .5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('EEEE').format(date).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 8,
                  color: accent,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontSize: 29,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
              Text(
                '${date.year}',
                style: TextStyle(
                  fontSize: 8,
                  color: Theme.of(context).hintColor,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.onNavigate});
  final PaisaStore store;
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) {
    final m = store.monthTransactions;
    final income = store.total('income', m), spent = store.total('expense', m);
    final remaining = store.monthlyBudget - spent;
    final pct = store.monthlyBudget <= 0
        ? 0.0
        : (spent / store.monthlyBudget).clamp(0.0, 1.0);
    final accent = Theme.of(context).colorScheme.primary;
    final date = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 26),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Eyebrow(DateFormat('MMMM yyyy').format(date).toUpperCase()),
                  const SizedBox(height: 7),
                  const Text(
                    'Your money, decoded.',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Just the useful bits. Everything here comes from what you log.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            _DateStamp(date: date, accent: accent),
          ],
        ),
        const SizedBox(height: 18),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow('CURRENT BALANCE'),
              const SizedBox(height: 9),
              _SensitiveValue(
                store: store,
                mask: '₹ ••••••',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
                child: SlotBalance(value: store.balance),
              ),
              const SizedBox(height: 7),
              _SensitiveValue(
                store: store,
                mask: 'Starting balance · hidden',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                ),
                child: Text(
                  'Starting balance ${money(store.openingBalance)} · from the entries you add',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            ],
          ),
          tint: accent.withValues(alpha: .04),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title:
                    'INCOME · ${DateFormat('MMM').format(date).toUpperCase()}',
                value: money(income),
                store: store,
                foot: income > 0 ? 'Logged this month' : 'Nothing logged yet',
                color: _incomeGreen,
                icon: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _StatCard(
                title:
                    'SPENT · ${DateFormat('MMM').format(date).toUpperCase()}',
                value: money(spent),
                store: store,
                foot:
                    '${m.where((t) => t['type'] == 'expense').length} expense entries',
                color: Theme.of(context).colorScheme.onSurface,
                icon: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Eyebrow('MONTHLY BUDGET'),
                        const SizedBox(height: 4),
                        _SensitiveValue(
                          store: store,
                          mask: 'Budget amounts hidden',
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 11,
                          ),
                          child: Text(
                            remaining >= 0
                                ? '${money(remaining)} left to plan against'
                                : '${money(-remaining)} past your plan',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onNavigate(3),
                    child: const Text('Adjust →'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: Theme.of(context).dividerColor
                      .withValues(alpha: .25),
                  color: pct > .9 ? const Color(0xFFFF777D) : accent,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SensitiveValue(
                    store: store,
                    mask: 'Spent hidden',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 10,
                    ),
                    child: Text(
                      '${money(spent)} spent',
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  _SensitiveValue(
                    store: store,
                    mask: 'Budget hidden',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 10,
                    ),
                    child: Text(
                      '${(pct * 100).round()}% of ${money(store.monthlyBudget)}',
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent activity',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Your latest entries',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onNavigate(1),
                    child: const Text('See all →'),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              if (store.sortedTransactions.isEmpty)
                const _EmptyLine(
                  'Ready when you are.',
                  'Your ledger fills up as you add transactions.',
                )
              else
                ...store.sortedTransactions
                    .take(3)
                    .map(
                      (t) => TransactionTile(
                        transaction: t,
                        privacy: store.privacy,
                        privacyStyle: store.privacyStyle,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).hintColor,
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.05,
    ),
  );
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.tint});
  final Widget child;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : .0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 6),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: .55),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.foot,
    required this.color,
    required this.icon,
    required this.store,
  });
  final String title, value, foot;
  final Color color;
  final IconData icon;
  final PaisaStore store;
  @override
  Widget build(BuildContext context) => _SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _Eyebrow(title)),
            Icon(icon, size: 15, color: color),
          ],
        ),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _SensitiveValue(
            store: store,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          foot,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 9),
        ),
      ],
    ),
  );
}

class SlotBalance extends StatelessWidget {
  const SlotBalance({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = NumberFormat('#,##0.00', 'en_IN').format(value.abs());
    final chars = text.split('');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value < 0 ? '−₹' : '₹',
            style: TextStyle(
              color: accent,
              fontSize: 31,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          for (var i = 0; i < chars.length; i++)
            if (RegExp(r'\d').hasMatch(chars[i]))
              _SlotDigit(
                key: ValueKey('$i-${chars[i]}'),
                digit: int.parse(chars[i]),
                index: i,
              )
            else
              Text(
                chars[i],
                style: const TextStyle(
                  fontSize: 35,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
        ],
      ),
    );
  }
}

class _SlotDigit extends StatefulWidget {
  const _SlotDigit({super.key, required this.digit, required this.index});
  final int digit, index;
  @override
  State<_SlotDigit> createState() => _SlotDigitState();
}

class _SlotDigitState extends State<_SlotDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delay;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1300 + widget.index % 3 * 120),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _delay?.cancel();
      _started = true;
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _delay = Timer(Duration(milliseconds: 50 * widget.index), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turns = 3 + widget.index % 2;
    final end = turns * 10 + widget.digit;
    const font = 35.0;
    const line = 42.0;
    return ClipRect(
      child: SizedBox(
        width: 22,
        height: line,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Transform.translate(
            offset: Offset(0, -_controller.value * end * line),
            child: Column(
              children: [
                for (var i = 0; i <= end; i++)
                  SizedBox(
                    height: line,
                    child: Center(
                      child: Text(
                        '${i % 10}',
                        style: const TextStyle(
                          fontSize: font,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    ),
  );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.privacy,
    required this.privacyStyle,
  });
  final Map<String, dynamic> transaction;
  final bool privacy;
  final String privacyStyle;
  @override
  Widget build(BuildContext context) {
    final income = transaction['type'] == 'income';
    final date = DateTime.tryParse('${transaction['date']}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: .6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              categoryIcon('${transaction['category']}'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${transaction['description'] ?? transaction['category']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${transaction['category'] ?? 'Other'}${transaction['recurring'] == true ? ' · recurring' : ''} · ${date == null ? '' : DateFormat('d MMM').format(date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SensitiveValue(
            hidden: privacy,
            privacyStyle: privacyStyle,
            mask: '${income ? '+' : '−'}₹••••',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: income
                  ? _incomeGreen
                  : Theme.of(context).colorScheme.onSurface,
            ),
            child: Text(
              '${income ? '+' : '−'}${money(PaisaStore.numberForUi(transaction['amount']))}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: income
                    ? _incomeGreen
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.store, required this.onEdit});
  final PaisaStore store;
  final ValueChanged<Map<String, dynamic>> onEdit;
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _query = '';
  String _type = 'All';
  @override
  Widget build(BuildContext context) {
    final list = widget.store.sortedTransactions
        .where(
          (t) =>
              (_type == 'All' || t['type'] == _type.toLowerCase()) &&
              ('${t['description']} ${t['category']} ${t['notes']}'
                  .toLowerCase()
                  .contains(_query.toLowerCase())),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 26),
      children: [
        const _PageHeading('Activity', 'Your complete money paper trail.'),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search transactions…',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          children: ['All', 'Expense', 'Income']
              .map(
                (t) => ChoiceChip(
                  label: Text(t),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ).build(context),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: list.isEmpty
              ? const _EmptyLine(
                  'No matching entries.',
                  'Try another search or add a transaction.',
                )
              : Column(
                  children: [
                    for (final t in list)
                      InkWell(
                        onTap: () => widget.onEdit(t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: TransactionTile(
                                  transaction: t,
                                  privacy: widget.store.privacy,
                                  privacyStyle: widget.store.privacyStyle,
                                ),
                              ),
                              PopupMenuButton<String>(
                                iconSize: 18,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                                onSelected: (v) async {
                                  if (v == 'edit')
                                    widget.onEdit(t);
                                  else
                                    await widget.store.deleteTransaction(
                                      '${t['id']}',
                                    );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow('PAISA.EXE / ${title.toUpperCase()}'),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
        ),
      ],
    ),
  );
}

List<Map<String, dynamic>> _allFood(PaisaStore store) =>
    store.campusFood.expand((shop) {
      final items = (shop['items'] as List? ?? const []).whereType<Map>();
      return items.map(
        (item) => {...Map<String, dynamic>.from(item), 'shop': shop['shop']},
      );
    }).toList();

String _foodTag(PaisaStore store, String name) => store.foodLikes.contains(name)
    ? '♥ YOUR FAVORITE'
    : store.foodOrders.containsKey(name)
    ? '↺ ORDERED BEFORE'
    : '✦ FITS YOUR PACE';

class CampusScreen extends StatefulWidget {
  const CampusScreen({super.key, required this.store, required this.onChoose});
  final PaisaStore store;
  final ValueChanged<Map<String, dynamic>> onChoose;
  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

class _CampusScreenState extends State<CampusScreen> {
  String? _shop;
  String _search = '';
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final all = _allFood(store);
    final cap = store.dailyPace * 1.35;
    final picks =
        all.where((f) => PaisaStore.numberForUi(f['price']) <= cap).toList()
          ..sort((a, b) {
            final fav = store.foodLikes.contains(b['name']) ? 1 : 0;
            final favA = store.foodLikes.contains(a['name']) ? 1 : 0;
            if (fav != favA) return fav - favA;
            final orders = store.foodOrders['${b['name']}'] ?? 0;
            final ordersA = store.foodOrders['${a['name']}'] ?? 0;
            if (orders != ordersA) return orders - ordersA;
            return PaisaStore.numberForUi(a['price'])
                .compareTo(PaisaStore.numberForUi(b['price']));
          });
    final liked = all
        .where((f) => store.foodLikes.contains(f['name']))
        .toList();
    final ordered = all
        .where((f) => store.foodOrders.containsKey('${f['name']}'))
        .toList();
    Map<String, dynamic>? shop;
    for (final candidate in store.campusFood) {
      if (candidate['shop'] == _shop) {
        shop = candidate;
        break;
      }
    }
    final menu = (shop?['items'] as List? ?? const [])
        .whereType<Map>()
        .map((i) => {...Map<String, dynamic>.from(i), 'shop': shop?['shop']})
        .where(
          (i) => '${i['name']}'.toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 28),
      children: [
        const _PageHeading(
          'Campus food',
          'Find something good, with the price up front.',
        ),
        _SoftCard(
          tint: Theme.of(context).colorScheme.primary.withValues(alpha: .045),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('VIT MENU · SAMPLE DATA'),
                    const SizedBox(height: 6),
                    const Text(
                      'A craving, with a price tag.',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sample menus until you send the real ones.',
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.local_dining_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 29,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow('YOUR BALANCE'),
                  const SizedBox(height: 5),
                  _SensitiveValue(
                    store: store,
                    mask: '₹ ••••',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                    child: Text(
                      money(store.balance),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const _Eyebrow('DAILY PACE'),
                  const SizedBox(height: 5),
                  _SensitiveValue(
                    store: store,
                    mask: '₹ ••••',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    child: Text(
                      money(store.dailyPace),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paisa picks',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Your likes, past picks and spending pace',
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            _OnDeviceTag(color: Theme.of(context).colorScheme.primary),
          ],
        ),
        const SizedBox(height: 4),
        if (picks.isEmpty)
          _SoftCard(
            child: _EmptyLine(
              'Nothing fits today’s pace yet.',
              'Browse a menu anyway, or adjust the pocket money date.',
            ),
          )
        else
          _FoodGrid(
            items: picks.take(4).toList(),
            store: store,
            onChoose: widget.onChoose,
          ),
        if (liked.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel(
            title: 'Your saved cravings',
            subtitle: 'The little list that gets you.',
          ),
          _FoodGrid(items: liked, store: store, onChoose: widget.onChoose),
        ],
        if (ordered.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel(
            title: 'From your past orders',
            subtitle: 'A familiar choice, when it fits.',
          ),
          _FoodGrid(
            items: ordered.take(4).toList(),
            store: store,
            onChoose: widget.onChoose,
          ),
        ],
        const SizedBox(height: 21),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Browse the menus',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Choose a place first. Its menu appears below.',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  _OnDeviceTag(
                    color: Theme.of(context).colorScheme.primary,
                    label: 'SAMPLE',
                  ),
                ],
              ),
              const SizedBox(height: 13),
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _open
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                  ),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _open = !_open),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            _IndexBadge(text: '01'),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _Eyebrow('CHOOSE A FOOD PLACE'),
                                  const SizedBox(height: 4),
                                  Text(
                                    _shop ?? 'Choose a food place…',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _open ? .5 : 0,
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 210),
                      curve: Curves.easeOutCubic,
                      child: !_open
                          ? const SizedBox.shrink()
                          : Column(
                              children: [
                                Divider(
                                  height: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                for (
                                  var i = 0;
                                  i < store.campusFood.length;
                                  i++
                                )
                                  _ShopOption(
                                    index: i,
                                    shop: store.campusFood[i],
                                    selected:
                                        _shop == store.campusFood[i]['shop'],
                                    onTap: () => setState(() {
                                      _shop = '${store.campusFood[i]['shop']}';
                                      _open = false;
                                      _search = '';
                                    }),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              if (shop != null) ...[
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search ${shop['shop']}’s menu…',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                if (menu.isEmpty)
                  const _EmptyLine(
                    'No dishes match that search.',
                    'Try a shorter search.',
                  ),
                for (final item in menu)
                  _MenuRow(item: item, store: store, onChoose: widget.onChoose),
              ] else ...[
                const SizedBox(height: 10),
                const _EmptyLine(
                  'Pick a shop to open its menu.',
                  'The dishes stay tucked away until you choose a place.',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sample VIT places and prices only. Replace with verified menus when you have them.',
          style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}

class _OnDeviceTag extends StatelessWidget {
  const _OnDeviceTag({required this.color, this.label = 'ON DEVICE'});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
      ),
    ],
  );
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: 31,
    height: 31,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ShopOption extends StatelessWidget {
  const _ShopOption({
    required this.index,
    required this.shop,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final Map<String, dynamic> shop;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _IndexBadge(text: '${index + 1}'.padLeft(2, '0')),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${shop['shop']}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${(shop['items'] as List).length} sample menu items',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.arrow_outward_rounded,
            size: 17,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).hintColor,
          ),
        ],
      ),
    ),
  );
}

class _FoodGrid extends StatelessWidget {
  const _FoodGrid({
    required this.items,
    required this.store,
    required this.onChoose,
  });
  final List<Map<String, dynamic>> items;
  final PaisaStore store;
  final ValueChanged<Map<String, dynamic>> onChoose;
  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: items.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      mainAxisExtent: 130,
    ),
    itemBuilder: (context, i) =>
        _FoodCard(item: items[i], store: store, onChoose: onChoose),
  );
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({
    required this.item,
    required this.store,
    required this.onChoose,
  });
  final Map<String, dynamic> item;
  final PaisaStore store;
  final ValueChanged<Map<String, dynamic>> onChoose;
  @override
  Widget build(BuildContext context) {
    final liked = store.foodLikes.contains(item['name']);
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => onChoose(item),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['shop']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    money(PaisaStore.numberForUi(item['price'])),
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _foodTag(store, '${item['name']}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 7,
                      letterSpacing: .25,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 4,
              top: 3,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                tooltip: liked ? 'Remove favorite' : 'Save favorite',
                onPressed: () => store.toggleFoodLike('${item['name']}'),
                icon: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? color : Theme.of(context).hintColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.store,
    required this.onChoose,
  });
  final Map<String, dynamic> item;
  final PaisaStore store;
  final ValueChanged<Map<String, dynamic>> onChoose;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => onChoose(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['name']}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      money(PaisaStore.numberForUi(item['price'])),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                onPressed: () => store.toggleFoodLike('${item['name']}'),
                icon: Icon(
                  store.foodLikes.contains(item['name'])
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: store.foodLikes.contains(item['name'])
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Theme.of(context).hintColor,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> _pickCampusFood(
  BuildContext context,
  PaisaStore store,
) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CampusPickerSheet(store: store),
);

class _CampusPickerSheet extends StatefulWidget {
  const _CampusPickerSheet({required this.store});
  final PaisaStore store;
  @override
  State<_CampusPickerSheet> createState() => _CampusPickerSheetState();
}

class _CampusPickerSheetState extends State<_CampusPickerSheet> {
  String? shop;
  String search = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.store.campusFood
        .where((s) => s['shop'] == shop)
        .expand(
          (s) => (s['items'] as List).map(
            (i) => {...Map<String, dynamic>.from(i), 'shop': s['shop']},
          ),
        )
        .where(
          (i) => '${i['name']}'.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return _SheetFrame(
      title: 'Find a campus dish',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose a place first. Its menu stays tucked away until then.',
              style: TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: shop,
            elevation: 16,
            dropdownColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            menuMaxHeight: 320,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            decoration: const InputDecoration(labelText: 'Food place'),
            items: widget.store.campusFood
                .map(
                  (s) => DropdownMenuItem(
                    value: '${s['shop']}',
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 15,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text('${s['shop']}'),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              shop = v;
              search = '';
            }),
          ),
          if (shop != null) ...[
            const SizedBox(height: 9),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search this menu…',
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, i) => _MenuRow(
                  item: items[i],
                  store: widget.store,
                  onChoose: (dish) => Navigator.pop(context, dish),
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Pick a shop to see its menu.'),
            ),
        ],
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    padding: EdgeInsets.fromLTRB(
      18,
      14,
      18,
      18 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Flexible(child: SingleChildScrollView(child: child)),
      ],
    ),
  );
}

class TransactionEditor extends StatefulWidget {
  const TransactionEditor({super.key, required this.store, this.preset});
  final PaisaStore store;
  final Map<String, dynamic>? preset;
  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key, required this.store});
  final PaisaStore store;
  Future<void> _edit(BuildContext context, [String? name]) async {
    final controller = TextEditingController(
      text: name == null ? '' : '${store.budgets[name]}',
    );
    var category = name ?? '';
    final result = await showDialog<MapEntry<String, double>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(name == null ? 'Add category budget' : 'Edit budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                enabled: name == null,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  hintText: 'Books & supplies',
                ),
                onChanged: (v) => setState(() => category = v.trim()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly limit (₹)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(controller.text);
                if (category.trim().isNotEmpty && amount != null && amount >= 0)
                  Navigator.pop(context, MapEntry(category.trim(), amount));
              },
              child: const Text('Save budget'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) await store.saveBudget(result.key, result.value);
  }

  @override
  Widget build(BuildContext context) {
    final entries = store.budgets.entries.toList();
    final spent = entries.fold<double>(
      0,
      (s, e) => s + store.categorySpend(e.key),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 28),
      children: [
        const _PageHeading(
          'Budgets',
          'A plan for your allowance. Adjust it as real life happens.',
        ),
        _SoftCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('MONTHLY CATEGORY BUDGETS'),
                    const SizedBox(height: 5),
                    Text(
                      '${money(store.monthlyBudget)} total planned',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${money(spent)} recorded this month',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final entry in entries)
          _BudgetTile(
            category: entry.key,
            limit: entry.value,
            spent: store.categorySpend(entry.key),
            onEdit: () => _edit(context, entry.key),
            onDelete: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Remove this budget?'),
                  content: Text(
                    'Transactions in ${entry.key} will stay in your ledger.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep it'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              if (ok == true) await store.removeBudget(entry.key);
            },
          ),
      ],
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.category,
    required this.limit,
    required this.spent,
    required this.onEdit,
    required this.onDelete,
  });
  final String category;
  final double limit, spent;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    final ratio = limit <= 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  categoryIcon(category),
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(spent),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '/ ${money(limit)}',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 10,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                color: ratio >= 1 ? const Color(0xFFFF777D) : accent,
                backgroundColor: Theme.of(context).dividerColor
                    .withValues(alpha: .3),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              spent > limit
                  ? 'Over by ${money(spent - limit)}'
                  : '${money(limit - spent)} remaining',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, required this.store, required this.onPage});
  final PaisaStore store;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    final month = store.monthTransactions;
    final spend = store.total('expense', month);
    final byCategory = <String, double>{};
    for (final t in month.where((t) => t['type'] == 'expense')) {
      final c = '${t['category'] ?? 'Miscellaneous'}';
      byCategory[c] =
          (byCategory[c] ?? 0) + PaisaStore.numberForUi(t['amount']);
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final average = DateTime.now().day == 0 ? 0.0 : spend / DateTime.now().day;
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 28),
      children: [
        const _PageHeading(
          'Insights',
          'Patterns and charts, together when you want them.',
        ),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'THIS MONTH',
                value: money(spend),
                foot: 'Recorded expenses',
                color: Theme.of(context).colorScheme.onSurface,
                icon: Icons.north_east_rounded,
                store: store,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _StatCard(
                title: 'DAILY AVERAGE',
                value: money(average),
                foot: 'Through today',
                color: accent,
                icon: Icons.trending_down_rounded,
                store: store,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _WalletEntryCard(onTap: () => _openWallet(context, store, onPage)),
        const SizedBox(height: 10),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cash flow',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                'Last 7 days · from logged entries',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(height: 160, child: _CashFlowChart(store: store)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where it goes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Category spending · this month',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 13),
              if (categories.isEmpty)
                const _EmptyLine(
                  'A blank ledger tells no stories.',
                  'Add expenses to see category patterns.',
                )
              else
                for (final entry in categories.take(6))
                  _CategoryBar(
                    name: entry.key,
                    amount: entry.value,
                    fraction:
                        entry.value /
                        (categories.first.value == 0
                            ? 1
                            : categories.first.value),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SoftCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Wrapped',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'A small recap of what your ledger says.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _openWrapped(context, store),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletEntryCard extends StatelessWidget {
  const _WalletEntryCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cherry = const Color(0xFFFF3C57);
    return _SoftCard(
      tint: const Color(0xFF20171B),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow('POCKET MONEY, INCOMING'),
                const SizedBox(height: 5),
                const Text(
                  'The Wallet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your next drop has a place to land.',
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: onTap,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Open wallet'),
                  style: FilledButton.styleFrom(
                    foregroundColor: cherry,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 112,
            height: 82,
            child: Image.asset(
              'assets/images/paisa_wallet_hero.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openWallet(
  BuildContext context,
  PaisaStore store,
  ValueChanged<int> onPage,
) => Navigator.of(context).push<void>(
  PageRouteBuilder<void>(
    transitionDuration: store.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 430),
    reverseTransitionDuration: store.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => _WalletScreen(store: store, onPage: onPage),
    transitionsBuilder: (_, animation, secondaryAnimation, child) {
      if (store.reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  ),
);

class _WalletScreen extends StatefulWidget {
  const _WalletScreen({required this.store, required this.onPage});
  final PaisaStore store;
  final ValueChanged<int> onPage;

  @override
  State<_WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<_WalletScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrival;

  @override
  void initState() {
    super.initState();
    _arrival = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
      value: widget.store.reduceMotion ? 1 : 0,
    );
    if (!widget.store.reduceMotion) _arrival.forward();
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cherry = Color(0xFFFF3C57);
    const background = Color(0xFF101013);
    const panel = Color(0xFF1A171A);
    const foreground = Color(0xFFF7F0F1);
    const muted = Color(0xFFB7AAAE);
    final base = Theme.of(context);
    final walletTheme = base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      hintColor: muted,
      dividerColor: const Color(0xFF3E3035),
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: cherry,
        onPrimary: Colors.white,
        surface: panel,
        onSurface: foreground,
        onSurfaceVariant: muted,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
      ),
    );

    return Theme(
      data: walletTheme,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to Insights',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('The Wallet'),
          centerTitle: true,
        ),
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final now = DateTime.now();
            final date = DateTime(now.year, now.month, now.day);
            final configuredNext =
                widget.store.recurringIncome['enabled'] == true
                ? DateTime.tryParse(
                    '${widget.store.recurringIncome['nextDate']}',
                  )
                : null;
            final monthLength = DateTime(date.year, date.month + 1, 0).day;
            final monthDaysLeft = monthLength - date.day;
            final allowance = _allowanceCycle(
              date,
              widget.store.recurringIncome,
            );
            final payoutDays = allowance.daysUntil;
            final next = allowance.payday;
            final hasSchedule =
                widget.store.recurringIncome['enabled'] == true &&
                (configuredNext != null ||
                    widget.store.recurringIncome['frequency'] == 'monthly');
            final amount = PaisaStore.numberForUi(
              widget.store.recurringIncome['amount'],
            );
            final isPayday = allowance.isPayday;
            final arrivalLine = isPayday
                ? 'Pocket money day. Your next cycle starts here.'
                : !hasSchedule
                ? 'Set a payday and we’ll give it a proper landing.'
                : payoutDays == 0
                ? 'Today is looking a little better.'
                : 'Your next pocket-money drop is getting closer.';
            final progressValue = allowance.progress;
            return Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.45),
                  radius: 1.2,
                  colors: [Color(0xFF2B171E), background],
                  stops: [0, 1],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  _Eyebrow(isPayday ? 'PAYDAY · TODAY' : 'THE NEXT ARRIVAL'),
                  const SizedBox(height: 6),
                  Text(
                    isPayday ? 'It landed.' : 'A little closer.',
                    style: TextStyle(
                      fontSize: 29,
                      height: 1.05,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    arrivalLine,
                    style: const TextStyle(
                      color: Color(0xFFB7AAAE),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _WalletHero(
                    arrival: _arrival,
                    progress: progressValue,
                    isPayday: isPayday,
                    reduceMotion: widget.store.reduceMotion,
                  ),
                  if (hasSchedule) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Eyebrow('POCKET MONEY'),
                              const SizedBox(height: 5),
                              _SensitiveValue(
                                store: widget.store,
                                mask: '₹ ••••',
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                                child: Text(
                                  money(amount),
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                DateFormat('EEE · d MMM').format(next),
                                style: const TextStyle(
                                  color: Color(0xFFB7AAAE),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              payoutDays == 0 ? 'TODAY' : '$payoutDays',
                              style: const TextStyle(
                                color: cherry,
                                fontSize: 31,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              'DAYS LEFT',
                              style: const TextStyle(
                                color: Color(0xFFB7AAAE),
                                fontSize: 8,
                                letterSpacing: .8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    const _SoftCard(
                      tint: Color(0xFF1A171A),
                      child: _EmptyLine(
                        'No payday on the calendar yet.',
                        'The monthly coin keeps moving in the meantime.',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).maybePop();
                          widget.onPage(5);
                        },
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Set a payday in More'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _WalletProgress(
                    progress: progressValue,
                    label: isPayday
                        ? 'NEW CYCLE'
                        : !hasSchedule
                        ? 'MONTH IN MOTION'
                        : 'PAYDAY APPROACHING',
                    reduceMotion: widget.store.reduceMotion,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Month ends in $monthDaysLeft ${monthDaysLeft == 1 ? 'day' : 'days'}',
                    style: const TextStyle(
                      color: Color(0xFF8F8588),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 17),
                  const _SignatureLine(accent: cherry),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WalletHero extends StatelessWidget {
  const _WalletHero({
    required this.arrival,
    required this.progress,
    required this.isPayday,
    required this.reduceMotion,
  });
  final AnimationController arrival;
  final double progress;
  final bool isPayday;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 236,
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: arrival,
        builder: (context, _) {
          final intro = reduceMotion
              ? 1.0
              : Curves.easeOutCubic.transform(arrival.value);
          final coinFlight = reduceMotion
              ? 1.0
              : Curves.easeInOutCubic.transform(
                  Interval(.08, .88).transform(arrival.value),
                );
          final targetProgress = progress.clamp(0.0, 1.0);
          final coinPresence = (1 - targetProgress).clamp(0.0, 1.0);
          final targetX = constraints.maxWidth * (.52 + .22 * targetProgress);
          final targetY = 6 + 82 * targetProgress;
          final x =
              constraints.maxWidth * .48 +
              (targetX - constraints.maxWidth * .48) * coinFlight;
          final y =
              -12 +
              (targetY + 12) * coinFlight -
              16 * math.sin(coinFlight * math.pi);
          final coinScale =
              .88 +
              .12 * intro +
              (isPayday ? .045 * math.sin(intro * math.pi) : 0);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: 2,
                child: Container(
                  width: constraints.maxWidth * .72,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66E71E3F),
                        blurRadius: 34,
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: x - 18,
                top: y,
                child: Opacity(
                  opacity: intro * coinPresence,
                  child: Transform.rotate(
                    angle: coinFlight * math.pi * 2.2,
                    child: Transform.scale(
                      scale: coinScale,
                      child: const _WalletCoin(size: 36),
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: intro,
                child: Transform.translate(
                  offset: Offset(0, 15 * (1 - intro)),
                  child: Transform.scale(
                    scale: coinScale,
                    child: Image.asset(
                      'assets/images/paisa_wallet_hero.png',
                      width: constraints.maxWidth,
                      height: 220,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              if (isPayday)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WalletPaydayPulsePainter(
                        progress: intro,
                        center: Offset(constraints.maxWidth * .74, targetY),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _WalletPaydayPulsePainter extends CustomPainter {
  const _WalletPaydayPulsePainter({
    required this.progress,
    required this.center,
  });
  final double progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < .62) return;
    final t = ((progress - .62) / .38).clamp(0.0, 1.0);
    final pulse = math.sin(t * math.pi);
    final radius = 8 + 24 * Curves.easeOutCubic.transform(t);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFFC768).withValues(alpha: .1 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawArc(
      bounds,
      -math.pi * .82,
      math.pi * 1.64,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFD78D).withValues(alpha: .76 * pulse),
    );
    final secondRadius = radius + 7;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: secondRadius),
      -math.pi * .28,
      math.pi * .56,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFB74E).withValues(alpha: .6 * pulse),
    );
  }

  @override
  bool shouldRepaint(covariant _WalletPaydayPulsePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.center != center;
}

class _WalletCoin extends StatelessWidget {
  const _WalletCoin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.38, -.42),
        radius: .92,
        colors: [
          Color(0xFFFFE5AE),
          Color(0xFFFFB94E),
          Color(0xFFDB7627),
          Color(0xFF962E28),
        ],
        stops: [0, .34, .76, 1],
      ),
      border: Border.all(color: const Color(0xFFFFD18A), width: 1.4),
      boxShadow: const [
        BoxShadow(color: Color(0x88F0443E), blurRadius: 17, spreadRadius: 1),
        BoxShadow(
          color: Color(0x99530C19),
          blurRadius: 6,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: size * .62,
        height: size * .62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x99FFF0D1), width: 1),
        ),
        child: Center(
          child: Container(
            width: size * .13,
            height: size * .13,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFF1D6),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WalletProgress extends StatelessWidget {
  const _WalletProgress({
    required this.progress,
    required this.label,
    required this.reduceMotion,
  });
  final double progress;
  final String label;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    const cherry = Color(0xFFFF3C57);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _Eyebrow('THE WAIT, VISUALIZED')),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB7AAAE),
                fontSize: 8,
                letterSpacing: .7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(12, (index) {
            final lit = progress >= (index + 1) / 12;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 11 ? 0 : 4),
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : Duration(milliseconds: 220 + index * 22),
                  curve: Curves.easeOutCubic,
                  height: index.isEven ? 5 : 3,
                  decoration: BoxDecoration(
                    color: lit
                        ? cherry.withValues(alpha: index == 11 ? .95 : .68)
                        : const Color(0xFF55444A).withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.amount,
    required this.fraction,
  });
  final String name;
  final double amount, fraction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Text(categoryIcon(name)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: const TextStyle(fontSize: 10)),
                  ),
                  Text(
                    money(amount),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0, 1),
                  minHeight: 3,
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context).dividerColor
                      .withValues(alpha: .3),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.store});
  final PaisaStore store;
  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      7,
      (i) => DateTime.now().subtract(Duration(days: 6 - i)),
    );
    final income = <double>[], expenses = <double>[];
    for (final day in days) {
      final items = store.transactions.where(
        (t) => '${t['date']}' == isoDay(day),
      );
      income.add(
        items
            .where((t) => t['type'] == 'income')
            .fold<double>(0, (s, t) => s + PaisaStore.numberForUi(t['amount'])),
      );
      expenses.add(
        items
            .where((t) => t['type'] == 'expense')
            .fold<double>(0, (s, t) => s + PaisaStore.numberForUi(t['amount'])),
      );
    }
    return CustomPaint(
      painter: _BarsPainter(
        income: income,
        expenses: expenses,
        primary: Theme.of(context).colorScheme.primary,
        incomeColor: _incomeGreen,
        gridColor: Theme.of(context).dividerColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.income,
    required this.expenses,
    required this.primary,
    required this.incomeColor,
    required this.gridColor,
  });
  final List<double> income, expenses;
  final Color primary, incomeColor, gridColor;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = [
      ...income,
      ...expenses,
    ].fold<double>(100, (a, b) => math.max(a, b));
    final paint = Paint()..strokeWidth = 1;
    for (var row = 0; row < 4; row++) {
      final y = row * size.height / 3;
      paint.color = gridColor.withValues(alpha: .4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final group = size.width / 7;
    for (var i = 0; i < 7; i++) {
      final left = i * group + group * .23;
      final w = group * .22;
      final h1 = income[i] / maxValue * (size.height - 8);
      final h2 = expenses[i] / maxValue * (size.height - 8);
      paint.color = incomeColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h1, w, h1),
          const Radius.circular(4),
        ),
        paint,
      );
      paint.color = primary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + w + 4, size.height - h2, w, h2),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.income != income ||
      old.expenses != expenses ||
      old.primary != primary;
}

Future<void> _openWrapped(BuildContext context, PaisaStore store) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MonthlyWrappedScreen(store: store),
      ),
    );

class _WrappedSlice {
  const _WrappedSlice({
    required this.name,
    required this.amount,
    required this.color,
  });
  final String name;
  final double amount;
  final Color color;
}

class _MonthlyWrappedScreen extends StatefulWidget {
  const _MonthlyWrappedScreen({required this.store});
  final PaisaStore store;

  @override
  State<_MonthlyWrappedScreen> createState() => _MonthlyWrappedScreenState();
}

class _MonthlyWrappedScreenState extends State<_MonthlyWrappedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  late final AnimationController _selectionMotion;
  int? _selectedIndex;
  int? _previousSelectedIndex;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    );
    _selectionMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..value = 1;
    if (widget.store.reduceMotion) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _selectionMotion.dispose();
    super.dispose();
  }

  List<_WrappedSlice> _slices() {
    final totals = <String, double>{};
    for (final transaction in widget.store.monthTransactions.where(
      (t) => t['type'] == 'expense',
    )) {
      final category = '${transaction['category'] ?? 'Miscellaneous'}';
      totals[category] =
          (totals[category] ?? 0) +
          PaisaStore.numberForUi(transaction['amount']);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final baseHue = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
    return [
      for (var i = 0; i < entries.length; i++)
        _WrappedSlice(
          name: entries[i].key,
          amount: entries[i].value,
          color: baseHue
              .withHue((baseHue.hue + i * 43) % 360)
              .withSaturation(.7)
              .withLightness(.6)
              .toColor(),
        ),
    ];
  }

  void _selectSlice(
    TapUpDetails details,
    Size size,
    List<_WrappedSlice> slices,
  ) {
    if (slices.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final point = details.localPosition - center;
    final radialPosition = point.distance / size.shortestSide;
    if (radialPosition < .22 || radialPosition > .47) return;
    var angle = math.atan2(point.dy, point.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final target = angle / (math.pi * 2);
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.amount);
    var cumulative = 0.0;
    for (var i = 0; i < slices.length; i++) {
      cumulative += slices[i].amount / total;
      if (target <= cumulative || i == slices.length - 1) {
        _changeSelection(i);
        return;
      }
    }
  }

  void _changeSelection(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _previousSelectedIndex = _selectedIndex;
      _selectedIndex = index;
    });
    if (!widget.store.reduceMotion) {
      _selectionMotion.forward(from: 0);
    } else {
      _selectionMotion.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Monthly Wrapped'),
    ),
    body: AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final slices = _slices();
        final total = slices.fold<double>(
          0,
          (sum, slice) => sum + slice.amount,
        );
        final entries = widget.store.monthTransactions;
        final selected =
            _selectedIndex != null && _selectedIndex! < slices.length
            ? slices[_selectedIndex!]
            : null;
        final selectedShare = selected == null || total <= 0
            ? null
            : (selected.amount / total * 100).round();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _SoftCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(DateTime.now()),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entries.length} ledger entries · tap a slice to peek',
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SoftCard(
              child: Column(
                children: [
                  Text(
                    selected?.name ?? 'OUT THE DOOR THIS MONTH',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected?.color ?? Theme.of(context).hintColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _SensitiveValue(
                    store: widget.store,
                    mask: '₹ ••••',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                    child: Text(
                      money(selected?.amount ?? total),
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 248,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chartSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) =>
                              _selectSlice(details, chartSize, slices),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedBuilder(
                                animation: Listenable.merge([
                                  _reveal,
                                  _selectionMotion,
                                ]),
                                builder: (context, _) => CustomPaint(
                                  size: chartSize,
                                  painter: _WrappedPiePainter(
                                    slices: slices,
                                    progress: widget.store.reduceMotion
                                        ? 1
                                        : _reveal.value,
                                    selectedIndex: _selectedIndex,
                                    previousSelectedIndex:
                                        _previousSelectedIndex,
                                    selectionProgress: widget.store.reduceMotion
                                        ? 1
                                        : Curves.easeOutCubic.transform(
                                            _selectionMotion.value,
                                          ),
                                    centerColor: Theme.of(context)
                                        .colorScheme
                                        .surface,
                                  ),
                                ),
                              ),
                              Center(
                                child: IgnorePointer(
                                  child: AnimatedSwitcher(
                                    duration: widget.store.reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 240),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: .94,
                                              end: 1,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: Column(
                                      key: ValueKey(selectedShare),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          selectedShare == null
                                              ? 'SPEND MIX'
                                              : 'SHARE OF SPEND',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 7,
                                            letterSpacing: 1.1,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          selectedShare == null
                                              ? '${slices.length}'
                                              : '$selectedShare%',
                                          style: TextStyle(
                                            color:
                                                selected?.color ??
                                                Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                            fontSize: 23,
                                            height: 1,
                                            letterSpacing: -.8,
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          selectedShare == null
                                              ? 'CATEGORIES'
                                              : selected!.name.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                selected?.color ??
                                                Theme.of(context).hintColor,
                                            fontSize: 7,
                                            letterSpacing: .6,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (slices.isEmpty)
                    Text(
                      'Your expenses will make the first slice.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'THE BREAKDOWN',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 8),
            if (slices.isEmpty)
              const _EmptyLine(
                'No slices yet.',
                'Log an expense and your month takes shape here.',
              )
            else
              for (var i = 0; i < slices.length; i++)
                _WrappedSliceRow(
                  slice: slices[i],
                  total: total,
                  selected: i == _selectedIndex,
                  store: widget.store,
                  onTap: () => _changeSelection(i),
                ),
            const SizedBox(height: 10),
            Text(
              'A snapshot of what you logged, not the whole story.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
            ),
          ],
        );
      },
    ),
  );
}

class _WrappedPiePainter extends CustomPainter {
  const _WrappedPiePainter({
    required this.slices,
    required this.progress,
    required this.selectedIndex,
    required this.previousSelectedIndex,
    required this.selectionProgress,
    required this.centerColor,
  });
  final List<_WrappedSlice> slices;
  final double progress;
  final int? selectedIndex;
  final int? previousSelectedIndex;
  final double selectionProgress;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .31;
    final strokeWidth = size.shortestSide * .17;
    final chartBounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = Colors.white.withValues(alpha: .035),
    );
    canvas.drawCircle(
      center,
      radius + strokeWidth * .67,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .045),
    );
    final holeRadius = radius - strokeWidth * .62;
    canvas.drawCircle(
      center,
      holeRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(centerColor, Colors.white, .035)!, centerColor],
        ).createShader(Rect.fromCircle(center: center, radius: holeRadius)),
    );
    canvas.drawCircle(
      center,
      holeRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .07),
    );
    if (slices.isEmpty) {
      return;
    }
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.amount);
    var cumulative = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final delay = slices.length < 2 ? 0.0 : .46 * i / (slices.length - 1);
      final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      final reveal = Curves.easeOutCubic.transform(local).clamp(0.0, 1.0);
      final targetStart = cumulative / total;
      final targetSweep = slice.amount / total;
      cumulative += slice.amount;
      final start = -math.pi / 2 + targetStart * math.pi * 2;
      var sweep = targetSweep * math.pi * 2 * reveal;
      if (reveal <= 0 || sweep <= 0) continue;
      final gap = math.min(.055, sweep * .10);
      sweep = math.max(0, sweep - gap);
      final selected = i == selectedIndex;
      final wasSelected = i == previousSelectedIndex;
      final emphasis = selected
          ? selectionProgress
          : wasSelected
          ? 1 - selectionProgress
          : 0.0;
      final arcRadius = radius + 6 * emphasis;
      final arcRect = Rect.fromCircle(center: center, radius: arcRadius);
      final arcStart = start + gap / 2;
      final arcSweep = math.max(0.0, sweep - gap);
      if (emphasis > 0) {
        canvas.drawArc(
          arcRect,
          arcStart,
          arcSweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + 6 * emphasis
            ..strokeCap = StrokeCap.round
            ..color = slice.color.withValues(alpha: .18 * emphasis)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 2 * emphasis
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: arcStart,
          endAngle: arcStart + arcSweep,
          colors: [
            Color.lerp(slice.color, Colors.white, .20)!,
            slice.color,
            Color.lerp(slice.color, Colors.black, .14)!,
          ],
          stops: const [0, .56, 1],
        ).createShader(chartBounds);
      canvas.drawArc(arcRect, arcStart, arcSweep, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WrappedPiePainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.progress != progress ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.previousSelectedIndex != previousSelectedIndex ||
      oldDelegate.selectionProgress != selectionProgress ||
      oldDelegate.centerColor != centerColor;
}

class _WrappedSliceRow extends StatelessWidget {
  const _WrappedSliceRow({
    required this.slice,
    required this.total,
    required this.selected,
    required this.store,
    required this.onTap,
  });
  final _WrappedSlice slice;
  final double total;
  final bool selected;
  final PaisaStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Material(
      color: selected
          ? slice.color.withValues(alpha: .11)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: slice.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  slice.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                total == 0 ? '0%' : '${(slice.amount / total * 100).round()}%',
                style: TextStyle(
                  color: slice.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              _SensitiveValue(
                store: store,
                mask: '₹ ••••',
                style: const TextStyle(fontSize: 10),
                child: Text(
                  money(slice.amount),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.onPage});
  final PaisaStore store;
  final ValueChanged<int> onPage;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _opening;
  late final TextEditingController _monthly;
  late final TextEditingController _recAmount;
  late final TextEditingController _recLabel;
  late DateTime _nextDate;
  late String _frequency;
  late bool _autoAdd;
  @override
  void initState() {
    super.initState();
    final s = widget.store;
    _opening = TextEditingController(text: '${s.openingBalance}');
    _monthly = TextEditingController(text: '${s.monthlyIncome}');
    _recAmount = TextEditingController(
      text: '${s.recurringIncome['amount'] ?? ''}',
    );
    _recLabel = TextEditingController(
      text: '${s.recurringIncome['description'] ?? 'Pocket money'}',
    );
    _nextDate =
        DateTime.tryParse('${s.recurringIncome['nextDate']}') ?? DateTime.now();
    _frequency = '${s.recurringIncome['frequency'] ?? 'monthly'}';
    _autoAdd = s.recurringIncome['autoAdd'] == true;
  }

  @override
  void dispose() {
    _opening.dispose();
    _monthly.dispose();
    _recAmount.dispose();
    _recLabel.dispose();
    super.dispose();
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _exportCsv() async {
    String quote(Object? value) =>
        '"${'${value ?? ''}'.replaceAll('"', '""')}"';
    final rows = <List<Object?>>[
      [
        'date',
        'type',
        'amount',
        'description',
        'category',
        'payment',
        'recurring',
        'notes',
      ],
      ...widget.store.sortedTransactions.map(
        (t) => [
          t['date'],
          t['type'],
          t['amount'],
          t['description'],
          t['category'],
          t['payment'],
          t['recurring'],
          t['notes'],
        ],
      ),
    ];
    final csv = rows.map((r) => r.map(quote).join(',')).join('\r\n');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('\uFEFF$csv')),
              name: 'paisa-transactions.csv',
              mimeType: 'text/csv',
            ),
          ],
          fileNameOverrides: ['paisa-transactions.csv'],
          text: 'Paisa.exe transaction backup',
        ),
      );
    } catch (e) {
      _notice('Could not open the share sheet. ${e.toString()}');
    }
  }

  Future<void> _importCsv() async {
    try {
      final content = await MethodChannel('com.paisaexe.app/legacy')
          .invokeMethod<String>('pickCsv');
      if (content == null || content.isEmpty) return;
      final rows = _parseCsv(content);
      if (rows.length < 2)
        return _notice('No transaction rows found in that CSV.');
      final heads = rows.first.map((v) => v.trim().toLowerCase()).toList();
      int col(List<String> names) =>
          heads.indexWhere((h) => names.any((n) => h == n || h.contains(n)));
      final dateCol = col(['date']),
          amountCol = col(['amount']),
          descCol = col(['description', 'merchant']),
          catCol = col(['category']),
          typeCol = col(['type']);
      if (dateCol < 0 || amountCol < 0)
        return _notice('CSV needs Date and Amount columns.');
      var added = 0;
      for (final row in rows.skip(1)) {
        if (row.length <= math.max(dateCol, amountCol)) continue;
        final date = DateTime.tryParse(row[dateCol]);
        final amount = double.tryParse(
          row[amountCol].replaceAll(RegExp(r'[₹,\s]'), ''),
        );
        if (date == null || amount == null || amount == 0) continue;
        final description = descCol >= 0 && row.length > descCol
            ? row[descCol]
            : 'Imported transaction';
        final category =
            catCol >= 0 && row.length > catCol && row[catCol].isNotEmpty
            ? row[catCol]
            : 'Miscellaneous';
        final type =
            typeCol >= 0 &&
                row.length > typeCol &&
                row[typeCol].toLowerCase().contains('income')
            ? 'income'
            : 'expense';
        await widget.store.addTransaction({
          'date': isoDay(date),
          'amount': amount.abs(),
          'type': type,
          'description': description,
          'category': category,
          'notes': 'Imported CSV',
        });
        added++;
      }
      _notice(
        added == 0
            ? 'No valid new rows found.'
            : '$added transactions imported.',
      );
    } catch (_) {
      _notice('Could not read that CSV file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 30),
      children: [
        const _PageHeading('More', 'Make Paisa feel like yours.'),
        _SettingsCard(
          title: 'YOUR FINANCIAL BASELINE',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _opening,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Opening balance (₹)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: _monthly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Expected monthly income (₹)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () async {
                    final o = double.tryParse(_opening.text),
                        m = double.tryParse(_monthly.text);
                    if (o == null || o < 0 || m == null || m < 0)
                      return _notice('Enter valid non-negative amounts.');
                    await store.saveSettings(opening: o, income: m);
                    _notice('Financial baseline saved.');
                  },
                  child: const Text('Save baseline'),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Balance = opening balance + income − expenses.',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'POCKET MONEY SCHEDULE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paisa can post each payment when it arrives, or add it automatically when due.',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _recAmount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _frequency,
                      elevation: 16,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      menuMaxHeight: 260,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      decoration: const InputDecoration(labelText: 'Every'),
                      items: const [
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Every week  ·  7 days'),
                        ),
                        DropdownMenuItem(
                          value: 'fortnightly',
                          child: Text('Every 2 weeks  ·  14 days'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Every month'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _frequency = v ?? 'monthly'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _nextDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (d != null) setState(() => _nextDate = d);
                },
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text('Next payment · ${dateLabel(_nextDate)}'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _recLabel,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Auto-add when due',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Posts it when you open Paisa after the due date.',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                value: _autoAdd,
                onChanged: (v) => setState(() => _autoAdd = v),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      final amount = double.tryParse(_recAmount.text) ?? 0;
                      if (amount <= 0)
                        return _notice(
                          'Enter a pocket money amount above zero.',
                        );
                      await store.saveSchedule({
                        'enabled': true,
                        'amount': amount,
                        'frequency': _frequency,
                        'nextDate': isoDay(_nextDate),
                        'autoAdd': _autoAdd,
                        'anchorDay': _nextDate.day,
                        'description': _recLabel.text.trim().isEmpty
                            ? 'Pocket money'
                            : _recLabel.text.trim(),
                      });
                      _notice('Pocket money schedule saved.');
                    },
                    child: const Text('Save schedule'),
                  ),
                  OutlinedButton(
                    onPressed: store.recurringIncome['enabled'] == true
                        ? () async {
                            if (await store.addNextIncome())
                              _notice('Pocket money added to your balance.');
                          }
                        : null,
                    child: const Text('＋ Add next payment now'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'COLOR FREQUENCY',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick an accent. The whole interface shifts with it.',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _palettes.entries
                    .map(
                      (entry) => ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: entry.value,
                          radius: 7,
                        ),
                        label: Text(
                          _paletteNames[entry.key]!,
                          style: const TextStyle(fontSize: 10),
                        ),
                        selected: store.palette == entry.key,
                        onSelected: (_) =>
                            store.saveSettings(selectedPalette: entry.key),
                      ),
                    )
                    .toList(),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Light appearance',
                  style: TextStyle(fontSize: 12),
                ),
                value: store.lightMode,
                onChanged: (v) => store.saveSettings(light: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'MOTION',
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Reduce motion',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Skip splash, page, counter and chart animations.',
              style: TextStyle(fontSize: 9),
            ),
            value: store.reduceMotion,
            onChanged: (value) => store.saveSettings(reduceAnimations: value),
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'PERSONALITY & PRIVACY',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Financial Roast Mode',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: const Text(
                  'Playful commentary, never about your circumstances.',
                  style: TextStyle(fontSize: 9),
                ),
                value: store.roast,
                onChanged: (v) => store.saveSettings(roastMode: v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Hide balances',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: const Text(
                  'Hide amounts on this phone. Choose blur or censor below.',
                  style: TextStyle(fontSize: 9),
                ),
                value: store.privacy,
                onChanged: (v) => store.saveSettings(hideBalances: v),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2, bottom: 8),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'WHEN HIDDEN',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: .6,
                        color: Theme.of(context).hintColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Blur', style: TextStyle(fontSize: 10)),
                      selected: store.privacyStyle == 'blur',
                      onSelected: (_) =>
                          store.saveSettings(hiddenAmountStyle: 'blur'),
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Censor',
                        style: TextStyle(fontSize: 10),
                      ),
                      selected: store.privacyStyle == 'censor',
                      onSelected: (_) =>
                          store.saveSettings(hiddenAmountStyle: 'censor'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'YOUR DATA · ON THIS PHONE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paisa saves locally. Export a CSV copy for an independent backup.',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 7,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('Export transactions'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importCsv,
                    icon: const Icon(Icons.file_open_rounded, size: 16),
                    label: const Text('Import CSV'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'MORE TO EXPLORE',
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openWrapped(context, store),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Monthly Wrapped'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _SettingsCard(
          title: 'START FRESH',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remove transactions and restore default budgets from this phone.',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF777D),
                ),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Reset all local data?'),
                      content: const Text(
                        'This clears transactions, budgets, and personal food preferences from this phone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Reset data'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await store.reset();
                    _notice('Local data reset.');
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Reset all local data'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'A tiny money tool by '),
                TextSpan(
                  text: 'Likhit',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  ✳',
                  style: TextStyle(color: accent),
                ),
              ],
            ),
            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => _SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).hintColor,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  final text = input.replaceFirst('\uFEFF', '');
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  return rows;
}

class _TransactionEditorState extends State<TransactionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late String _type, _category;
  late DateTime _date;
  late bool _recurring;
  Map<String, dynamic>? _food;

  @override
  void initState() {
    super.initState();
    final p = widget.preset ?? {};
    _amount = TextEditingController(
      text: p['amount'] == null ? '' : '${p['amount']}',
    );
    _description = TextEditingController(text: '${p['description'] ?? ''}');
    _notes = TextEditingController(text: '${p['notes'] ?? ''}');
    _type = '${p['type'] ?? 'expense'}';
    _category = '${p['category'] ?? 'Food & snacks'}';
    _date = DateTime.tryParse('${p['date']}') ?? DateTime.now();
    _recurring = p['recurring'] == true;
    if (p['foodItem'] != null)
      _food = {...p, 'name': p['foodItem'], 'shop': p['foodShop']};
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.preset?['id'] != null;
    final categories = {
      ...widget.store.budgets.keys,
      'Food & snacks',
      'Food delivery',
      'Transport',
      'College & printing',
      'Shopping',
      'Subscriptions',
      'Social & fun',
      'Personal care',
      'Miscellaneous',
      'Income',
      'Savings',
    }.toList();
    if (!categories.contains(_category)) categories.add(_category);
    return _SheetFrame(
      title: editing ? 'Edit transaction' : 'Add transaction',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('Income'),
                  icon: Icon(Icons.south_west_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                  ? 'Enter an amount above zero.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description / merchant',
                hintText: 'Chai and snacks',
              ),
            ),
            if (_type == 'expense') ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final food = await _pickCampusFood(context, widget.store);
                  if (food == null || !mounted) return;
                  setState(() {
                    _food = food;
                    _amount.text = '${food['price']}';
                    _description.text = '${food['shop']} · ${food['name']}';
                    _category = _foodCategory;
                  });
                },
                icon: const Icon(Icons.restaurant_menu_rounded),
                label: Text(
                  _food == null
                      ? 'Pick a VIT campus dish'
                      : '${_food!['name']} · ${money(PaisaStore.numberForUi(_food!['price']))}',
                ),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              elevation: 16,
              dropdownColor: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              menuMaxHeight: 360,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(categoryIcon(c)),
                          ),
                          const SizedBox(width: 9),
                          Text(c),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _category = v ?? _category;
                if (_category != _foodCategory) _food = null;
              }),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2018),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text('Date · ${dateLabel(_date)}'),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mark as recurring',
                style: TextStyle(fontSize: 12),
              ),
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 15),
            FilledButton(
              onPressed: _save,
              child: Text(editing ? 'Save changes' : 'Add to ledger'),
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final value = <String, dynamic>{
      'type': _type,
      'amount': double.parse(_amount.text),
      'description': _description.text.trim().isEmpty
          ? _category
          : _description.text.trim(),
      'category': _category,
      'date': isoDay(_date),
      'recurring': _recurring,
      'notes': _notes.text.trim(),
      if (_food != null) 'foodItem': _food!['name'],
      if (_food != null) 'foodShop': _food!['shop'],
    };
    final id = widget.preset?['id'];
    if (id == null) {
      await widget.store.addTransaction(value);
    } else {
      await widget.store.updateTransaction('$id', value);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            id == null
                ? 'Transaction saved on this phone.'
                : 'Transaction updated.',
          ),
        ),
      );
    }
  }
}
