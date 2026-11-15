import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lore.dart';
import 'paisa_store.dart';

const Color _ink = Color(0xFFF2E9E3);
const Color _muted = Color(0xFFA2969A);
const Color _bg = Color(0xFF0A090B);
const Color _panel = Color(0xFF141014);
const Color _line = Color(0xFF2C2328);
const Color _cherry = Color(0xFFFF3F58);

Future<void> openLore(BuildContext context, PaisaStore store) {
  final reduce = store.reduceMotion || MediaQuery.of(context).disableAnimations;
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: reduce
          ? Duration.zero
          : const Duration(milliseconds: 460),
      reverseTransitionDuration: reduce
          ? Duration.zero
          : const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => LoreScreen(store: store),
      transitionsBuilder: (_, animation, _, child) {
        if (reduce) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class LoreScreen extends StatefulWidget {
  const LoreScreen({super.key, required this.store});

  final PaisaStore store;

  @override
  State<LoreScreen> createState() => _LoreScreenState();
}

class _LoreScreenState extends State<LoreScreen>
    with SingleTickerProviderStateMixin {
  late LoreState _state;
  late LoreProfile _profile;
  late LoreContext _context;
  late LoreChapter _chapter;
  late int _viewing;
  late final AnimationController _fade;
  final ScrollController _scroll = ScrollController();
  final GlobalKey<_OpeningLineState> _opening = GlobalKey();
  bool _busy = false;
  bool _finished = false;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _reduce = widget.store.reduceMotion;
    _state = LoreState.fromJson(widget.store.loreState);
    _profile = LoreProfile.fromTransactions(widget.store.transactions);
    _context = LoreContext(flags: _state.flags, profile: _profile);
    _viewing = _state.current;
    _chapter = buildLoreChapter(_viewing, _context);
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: _reduce ? 1 : 0,
    );
    if (!_reduce) _fade.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
  }

  @override
  void dispose() {
    _persistScroll();
    _scroll.removeListener(_scheduleScrollSave);
    _scroll.dispose();
    _fade.dispose();
    super.dispose();
  }

  bool _scrollListenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce =
        widget.store.reduceMotion || MediaQuery.of(context).disableAnimations;
    if (_reduce && _fade.value < 1) _fade.value = 1;
    if (!_scrollListenerAttached) {
      _scrollListenerAttached = true;
      _scroll.addListener(_scheduleScrollSave);
    }
  }

  void _restoreScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final saved = _state.scrollFor(_viewing);
    if (saved <= 0) return;
    _scroll.jumpTo(saved.clamp(0, _scroll.position.maxScrollExtent).toDouble());
  }

  void _scheduleScrollSave() {
    if (!_scroll.hasClients) return;
    _scrollSave?.cancel();
    _scrollSave = Timer(const Duration(milliseconds: 450), _persistScroll);
  }

  Timer? _scrollSave;

  void _persistScroll() {
    _scrollSave?.cancel();
    if (!mounted || !_scroll.hasClients) return;
    final offset = _scroll.offset;
    if ((_state.scrollFor(_viewing) - offset).abs() < 4) return;
    final next = _state.withScroll(_viewing, offset);
    _state = next;
    unawaited(widget.store.saveLoreState(next.toJson()));
  }

  void _recompute({bool newChapter = true}) {
    _context = LoreContext(flags: _state.flags, profile: _profile);
    if (newChapter) _chapter = buildLoreChapter(_viewing, _context);
  }

  void _goToChapter(int chapter) {
    if (chapter < 1 || chapter > loreChapterCount) return;
    if (chapter > _state.current && !_state.isRead(chapter)) return;
    if (chapter == _viewing) return;
    _persistScroll();
    HapticFeedback.selectionClick();
    setState(() {
      _viewing = chapter;
      _finished = false;
      _recompute();
    });
    if (!_reduce) _fade.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final saved = _state.scrollFor(_viewing);
      _scroll.jumpTo(saved.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  Future<void> _choose(LoreOption option) async {
    if (_busy || _state.choiceFor(_viewing) != null) return;
    HapticFeedback.lightImpact();
    final next = _state.choose(_viewing, option);
    setState(() {
      _state = next;
      _recompute();
    });
    await widget.store.saveLoreState(next.toJson());
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: _reduce ? Duration.zero : const Duration(milliseconds: 760),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _finishChapter() async {
    if (_busy) return;
    if (_chapter.number == loreChapterCount) {
      HapticFeedback.mediumImpact();
      _busy = true;
      final next = _state.markRead(loreChapterCount);
      setState(() {
        _state = next;
        _finished = true;
        _recompute(newChapter: false);
      });
      await widget.store.saveLoreState(next.toJson());
      _busy = false;
      _scrollToEnd();
      return;
    }
    final wasFrontier = _viewing == _state.current;
    final nextState = _state.markRead(_viewing);
    final target = wasFrontier ? nextState.current : _viewing + 1;
    final canAdvance =
        target <= nextState.current && target <= loreChapterCount;
    HapticFeedback.lightImpact();
    _busy = true;
    _persistScroll();
    setState(() {
      _state = nextState;
      if (canAdvance) _viewing = target;
      _finished = false;
      _recompute();
    });
    await widget.store.saveLoreState(nextState.toJson());
    _busy = false;
    if (canAdvance) {
      if (!_reduce) _fade.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  void _revealAll() => _opening.currentState?.reveal();

  void _markIntroduced() {
    final next = _state.markIntroduced(_viewing);
    if (identical(next, _state)) return;
    _state = next;
    unawaited(widget.store.saveLoreState(next.toJson()));
  }

  Future<void> _openArchive() async {
    HapticFeedback.selectionClick();
    final chapter = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (_) => _ArchiveSheet(
        state: _state,
        viewing: _viewing,
        reduceMotion: _reduce,
      ),
    );
    if (chapter != null && mounted) _goToChapter(chapter);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final loreTheme = baseTheme.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      hintColor: _muted,
      dividerColor: _line,
      textTheme: baseTheme.textTheme.apply(bodyColor: _ink, displayColor: _ink),
      colorScheme: baseTheme.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: _cherry,
        onPrimary: const Color(0xFF1A0709),
        surface: _panel,
        onSurface: _ink,
        onSurfaceVariant: _muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _cherry,
          foregroundColor: const Color(0xFF1A0709),
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .3,
          ),
        ),
      ),
    );
    final visible = _chapter.visibleBlocks(_context);
    final reduced = _reduce;
    final showChoice =
        _chapter.choice != null && _chapter.choice!.options.isNotEmpty;
    return Theme(
      data: loreTheme,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            const Positioned.fill(child: _LoreBackdrop()),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _LoreTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onArchive: _openArchive,
                    chapter: _chapter.number,
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _revealAll,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final horizontal = constraints.maxWidth < 380
                              ? 20.0
                              : 26.0;
                          return FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _fade,
                              curve: Curves.easeOut,
                            ),
                            child: ListView(
                              controller: _scroll,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.fromLTRB(
                                horizontal,
                                8,
                                horizontal,
                                120,
                              ),
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 570,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_chapter.number == 1) ...[
                                          const _LoreMasthead(),
                                          const SizedBox(height: 34),
                                        ],
                                        _ChapterHeading(
                                          number: _chapter.number,
                                          title: _chapter.title,
                                          epigraph: _chapter.epigraph,
                                        ),
                                        const SizedBox(height: 30),
                                        for (var i = 0; i < visible.length; i++)
                                          _StoryBlock(
                                            key: ValueKey(
                                              'block-${_chapter.number}-$i',
                                            ),
                                            block: visible[i],
                                            opening: i == 0
                                                ? _OpeningLine(
                                                    key: _opening,
                                                    text: visible[i].text,
                                                    enabled: !reduced,
                                                    onRevealed: _markIntroduced,
                                                  )
                                                : null,
                                          ),
                                        if (showChoice) ...[
                                          const SizedBox(height: 30),
                                          _ChoiceCard(
                                            choice: _chapter.choice!,
                                            chosen: _state.choiceFor(
                                              _chapter.number,
                                            ),
                                            onChoose: _choose,
                                          ),
                                        ],
                                        if (_finished) ...[
                                          const SizedBox(height: 26),
                                          _EndPanel(
                                            onArchive: _openArchive,
                                            onClose: () =>
                                                Navigator.of(context)
                                                    .maybePop(),
                                            onRestart: () => _goToChapter(1),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _LoreFooter(
          chapter: _chapter.number,
          progress: _chapter.number / loreChapterCount,
          reduceMotion: _reduce,
          label: _footerLabel(showChoice),
          onAction: _footerAction(showChoice),
        ),
      ),
    );
  }

  String _footerLabel(bool showChoice) {
    if (_finished) return 'Close the book';
    if (_chapter.number == loreChapterCount &&
        _state.isRead(loreChapterCount)) {
      return 'Back to Paisa';
    }
    if (showChoice && _state.choiceFor(_viewing) == null) {
      return 'Make a choice';
    }
    if (_viewing < _state.current) return 'Next chapter';
    return 'Continue';
  }

  VoidCallback _footerAction(bool showChoice) {
    if (_finished) return () => Navigator.of(context).maybePop();
    if (_chapter.number == loreChapterCount &&
        _state.isRead(loreChapterCount)) {
      return () => Navigator.of(context).maybePop();
    }
    if (showChoice && _state.choiceFor(_viewing) == null) {
      return () {
        _scrollToEnd();
        HapticFeedback.selectionClick();
      };
    }
    if (_viewing < _state.current) {
      return () => _goToChapter(_viewing + 1);
    }
    return _finishChapter;
  }
}

class _LoreTopBar extends StatelessWidget {
  const _LoreTopBar({
    required this.onBack,
    required this.onArchive,
    required this.chapter,
  });

  final VoidCallback onBack;
  final VoidCallback onArchive;
  final int chapter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back to Paisa',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: _muted, size: 21),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            'PAISA.EXE / LORE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _muted.withValues(alpha: .9),
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${loreRoman[chapter - 1]} / ${loreRoman.last}',
          style: const TextStyle(
            color: _muted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        IconButton(
          tooltip: 'Chapter archive',
          onPressed: onArchive,
          icon: const Icon(Icons.menu_book_rounded, color: _muted, size: 20),
        ),
      ],
    ),
  );
}

class _LoreMasthead extends StatelessWidget {
  const _LoreMasthead();

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A PAISA.EXE SERIAL',
            style: TextStyle(
              color: _cherry.withValues(alpha: .85),
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.8,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your Money\nHas a Lore',
            style: TextStyle(
              color: _ink,
              fontSize: 30,
              height: 1.02,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Seven chapters. One ledger. A town eleven minutes ahead of itself.',
            style: TextStyle(color: _muted, fontSize: 10.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ChapterHeading extends StatelessWidget {
  const _ChapterHeading({
    required this.number,
    required this.title,
    required this.epigraph,
  });

  final int number;
  final String title;
  final String epigraph;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 640),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: child,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -6,
            top: -34,
            child: IgnorePointer(
              child: Text(
                loreRoman[number - 1],
                style: TextStyle(
                  color: _cherry.withValues(alpha: .055),
                  fontSize: 132,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -10,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 1,
                    color: _cherry.withValues(alpha: .75),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CHAPTER ${loreRoman[number - 1]}',
                    style: const TextStyle(
                      color: _cherry,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.02,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                epigraph,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11.5,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  letterSpacing: .1,
                ),
              ),
              const SizedBox(height: 20),
              _Ornament(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ornament extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Container(height: 1, color: _line.withValues(alpha: .9))),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('✦', style: TextStyle(color: _cherry, fontSize: 8)),
      ),
      Expanded(child: Container(height: 1, color: _line.withValues(alpha: .9))),
    ],
  );
}

class _StoryBlock extends StatelessWidget {
  const _StoryBlock({super.key, required this.block, this.opening});

  final LoreBlock block;
  final Widget? opening;

  @override
  Widget build(BuildContext context) {
    final aside = block.kind == LoreBlockKind.aside;
    final reveal = block.kind == LoreBlockKind.reveal;
    final style = TextStyle(
      fontSize: aside ? 13 : (reveal ? 16.5 : 15.5),
      height: aside ? 1.65 : 1.72,
      fontWeight: reveal ? FontWeight.w500 : FontWeight.w400,
      fontStyle: aside ? FontStyle.italic : FontStyle.normal,
      color: aside ? _muted : _ink,
      letterSpacing: aside ? .1 : .05,
    );
    final text = opening ?? Text(block.text, style: style);
    return Padding(
      padding: EdgeInsets.only(bottom: aside ? 17 : (reveal ? 21 : 17)),
      child: RepaintBoundary(child: text),
    );
  }
}

/// A deliberately cheap typewriter: batches of characters on a short timer,
/// only for the opening line, cancelled on tap or dispose.
class _OpeningLine extends StatefulWidget {
  const _OpeningLine({
    super.key,
    required this.text,
    required this.enabled,
    required this.onRevealed,
  });

  final String text;
  final bool enabled;
  final VoidCallback onRevealed;

  @override
  State<_OpeningLine> createState() => _OpeningLineState();
}

class _OpeningLineState extends State<_OpeningLine> {
  static const int _batch = 2;
  Timer? _timer;
  int _visible = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled && widget.text.isNotEmpty) {
      _timer = Timer.periodic(const Duration(milliseconds: 24), _tick);
    } else {
      _visible = widget.text.length;
      _done = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_done && MediaQuery.of(context).disableAnimations) reveal();
  }

  void _tick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    final next = _visible + _batch;
    if (next >= widget.text.length) {
      reveal();
      return;
    }
    setState(() => _visible = next);
  }

  void reveal() {
    _timer?.cancel();
    _timer = null;
    if (_done) return;
    _done = true;
    if (mounted) setState(() => _visible = widget.text.length);
    widget.onRevealed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(
      0,
      _visible.clamp(0, widget.text.length),
    );
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: Text(
          shown,
          style: const TextStyle(
            fontSize: 20,
            height: 1.42,
            fontWeight: FontWeight.w500,
            letterSpacing: -.3,
            color: _ink,
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.choice,
    required this.chosen,
    required this.onChoose,
  });

  final LoreChoice choice;
  final String? chosen;
  final ValueChanged<LoreOption> onChoose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 17, 16, 14),
    decoration: BoxDecoration(
      color: _panel.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _cherry.withValues(alpha: .26)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .35),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('✦', style: TextStyle(color: _cherry, fontSize: 9)),
            const SizedBox(width: 8),
            Text(
              'A DECISION',
              style: TextStyle(
                color: _cherry.withValues(alpha: .9),
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          choice.prompt,
          style: const TextStyle(
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < choice.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ChoiceOption(
            index: i,
            option: choice.options[i],
            selected: chosen == choice.options[i].id,
            locked: chosen != null,
            onTap: () => onChoose(choice.options[i]),
          ),
        ],
        if (chosen != null) ...[
          const SizedBox(height: 11),
          Text(
            'This decision is part of your record.',
            style: TextStyle(
              color: _muted.withValues(alpha: .8),
              fontSize: 9.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({
    required this.index,
    required this.option,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final int index;
  final LoreOption option;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? _cherry.withValues(alpha: .65)
        : _line.withValues(alpha: .9);
    return Semantics(
      button: true,
      enabled: !locked,
      label: '${option.label}. ${option.detail}',
      child: Material(
        color: selected
            ? _cherry.withValues(alpha: .09)
            : Colors.white.withValues(alpha: .017),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(13),
          splashColor: _cherry.withValues(alpha: .12),
          highlightColor: _cherry.withValues(alpha: .06),
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? _cherry : _cherry.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: selected ? const Color(0xFF1A0709) : _cherry,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          color: selected ? _ink : _ink.withValues(alpha: .92),
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.detail,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 4),
                    child: Icon(Icons.check_rounded, color: _cherry, size: 15),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndPanel extends StatelessWidget {
  const _EndPanel({
    required this.onArchive,
    required this.onClose,
    required this.onRestart,
  });

  final VoidCallback onArchive;
  final VoidCallback onClose;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _panel.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'END OF THE FIRST ARC',
          style: TextStyle(
            color: _cherry,
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'The book stays open.',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'You can revisit any chapter from the archive, or go back to the ledger you actually live in.',
          style: TextStyle(color: _muted, fontSize: 10.5, height: 1.5),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onArchive,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: BorderSide(color: _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.menu_book_rounded, size: 15),
              label: const Text('Open archive'),
            ),
            OutlinedButton.icon(
              onPressed: onRestart,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: BorderSide(color: _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.replay_rounded, size: 15),
              label: const Text('Re-read I'),
            ),
            FilledButton.tonal(
              onPressed: onClose,
              child: const Text('Back to Paisa'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LoreFooter extends StatelessWidget {
  const _LoreFooter({
    required this.chapter,
    required this.progress,
    required this.reduceMotion,
    required this.label,
    required this.onAction,
  });

  final int chapter;
  final double progress;
  final bool reduceMotion;
  final String label;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_bg.withValues(alpha: 0), _bg.withValues(alpha: .94), _bg],
        stops: const [0, .32, 1],
      ),
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  'CHAPTER ${loreRoman[chapter - 1]} OF ${loreRoman.last}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: _muted.withValues(alpha: .75),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: _line.withValues(alpha: .7),
                color: _cherry,
              ),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  const SizedBox(width: 7),
                  Icon(
                    label == 'Make a choice'
                        ? Icons.keyboard_double_arrow_down_rounded
                        : label == 'Continue' || label == 'Next chapter'
                        ? Icons.arrow_forward_rounded
                        : Icons.close_rounded,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArchiveSheet extends StatelessWidget {
  const _ArchiveSheet({
    required this.state,
    required this.viewing,
    required this.reduceMotion,
  });

  final LoreState state;
  final int viewing;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final ending = state.ending;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .78,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 34,
              height: 3,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Row(
                children: [
                  Text(
                    'THE ARCHIVE',
                    style: TextStyle(
                      color: _cherry,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'SEVEN CHAPTERS',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Text(
                'The Kattur branch ledger',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                itemCount: loreChapterCount,
                itemBuilder: (context, index) {
                  final number = index + 1;
                  final read = state.isRead(number);
                  final current = number == state.current;
                  final unlocked = read || current;
                  final chosen = state.choiceFor(number);
                  return _ArchiveRow(
                    number: number,
                    read: read,
                    current: current,
                    viewing: number == viewing,
                    unlocked: unlocked,
                    reduceMotion: reduceMotion,
                    ending: number == 6 ? ending : null,
                    choice: chosen,
                    onTap: unlocked
                        ? () => Navigator.of(context).pop(number)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({
    required this.number,
    required this.read,
    required this.current,
    required this.viewing,
    required this.unlocked,
    required this.reduceMotion,
    required this.ending,
    required this.choice,
    required this.onTap,
  });

  final int number;
  final bool read;
  final bool current;
  final bool viewing;
  final bool unlocked;
  final bool reduceMotion;
  final String? ending;
  final String? choice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = loreChapterTitles[number - 1];
    final active = current || viewing;
    final status = !unlocked
        ? 'SEALED'
        : read
        ? 'READ'
        : 'READING';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active
            ? _cherry.withValues(alpha: .07)
            : Colors.white.withValues(alpha: .014),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: active
                    ? _cherry.withValues(alpha: .35)
                    : _line.withValues(alpha: .75),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    loreRoman[number - 1],
                    style: TextStyle(
                      color: unlocked ? _cherry : _muted.withValues(alpha: .5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unlocked ? title : 'Chapter ${loreRoman[number - 1]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unlocked
                              ? _ink
                              : _muted.withValues(alpha: .62),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unlocked
                            ? [
                                status,
                                if (choice != null) 'DECISION KEPT',
                                if (ending != null)
                                  'ENDING: ${ending!.toUpperCase()}',
                              ].join(' · ')
                            : 'Sealed until you reach it',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _muted.withValues(alpha: .8),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unlocked)
                  Icon(
                    viewing
                        ? Icons.radio_button_checked_rounded
                        : Icons.chevron_right_rounded,
                    color: viewing ? _cherry : _muted,
                    size: 16,
                  )
                else
                  Icon(
                    Icons.lock_outline_rounded,
                    color: _muted.withValues(alpha: .35),
                    size: 14,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoreBackdrop extends StatelessWidget {
  const _LoreBackdrop();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.85, -.92),
          radius: 1.35,
          colors: [Color(0xFF2C1219), _bg, _bg],
          stops: [0, .46, 1],
        ),
      ),
      child: CustomPaint(painter: _GrainPainter(), size: Size.infinite),
    ),
  );
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(1741);
    final paint = Paint()..color = Colors.white.withValues(alpha: .016);
    for (var i = 0; i < 110; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .35 + random.nextDouble() * .9,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
