import 'dart:math' as math;

/// The number of chapters in the first Lore arc.
const int loreChapterCount = 7;

const List<String> loreRoman = <String>[
  'I',
  'II',
  'III',
  'IV',
  'V',
  'VI',
  'VII',
];

/// Archive metadata is intentionally separate from chapter prose so a locked
/// chapter can be listed without building its content.
const List<String> loreChapterTitles = <String>[
  'The Warm Coin',
  'The Passbook',
  'The Quiet Hour',
  'What the Advance Buys',
  'Room Zero',
  'The Reconciliation',
  'The Ordinary Ledger',
];

/// A very small, privacy-safe reading of the local ledger.
///
/// This is only used to colour the atmosphere of a chapter. It never mentions
/// an actual transaction, amount, or balance, and every field is optional.
class LoreProfile {
  const LoreProfile({
    required this.loggedExpenses,
    required this.lateNights,
    required this.foodHeavy,
    required this.expensiveDay,
    required this.quietMonth,
  });

  const LoreProfile.empty()
    : loggedExpenses = 0,
      lateNights = false,
      foodHeavy = false,
      expensiveDay = false,
      quietMonth = true;

  final int loggedExpenses;
  final bool lateNights;
  final bool foodHeavy;
  final bool expensiveDay;
  final bool quietMonth;

  bool get hasHistory => loggedExpenses > 0;

  /// Derives the pattern from visible expense entries only. Hidden entries and
  /// old demo rows are ignored, so the story can never reveal private data.
  factory LoreProfile.fromTransactions(
    Iterable<Map<String, dynamic>> source, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    var logged = 0;
    var late = 0;
    var food = 0;
    var monthCount = 0;
    var biggestDay = 0.0;
    final byDay = <String, double>{};
    for (final transaction in source) {
      if (transaction['type'] != 'expense' ||
          transaction['hidden'] == true ||
          transaction['demo'] == true) {
        continue;
      }
      final amount = _amount(transaction['amount']);
      if (amount <= 0 || !amount.isFinite) continue;
      final date = DateTime.tryParse('${transaction['date']}');
      if (date == null) continue;
      logged++;
      final created = DateTime.tryParse('${transaction['created'] ?? ''}');
      if (created != null && (created.hour >= 22 || created.hour < 4)) {
        late++;
      }
      final category = '${transaction['category'] ?? ''}'.toLowerCase();
      if (category.contains('food')) food++;
      if (date.year == at.year && date.month == at.month) {
        monthCount++;
        final key = '${date.year}-${date.month}-${date.day}';
        byDay[key] = (byDay[key] ?? 0) + amount;
      }
    }
    for (final total in byDay.values) {
      biggestDay = math.max(biggestDay, total);
    }
    return LoreProfile(
      loggedExpenses: logged,
      lateNights: late >= 2,
      foodHeavy: logged >= 4 && food / logged >= .55,
      expensiveDay: biggestDay >= 2000,
      quietMonth: monthCount <= 2,
    );
  }

  static double _amount(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

/// Everything the story engine is allowed to know at render time.
class LoreContext {
  const LoreContext({required this.flags, required this.profile});

  final Map<String, String> flags;
  final LoreProfile profile;

  String? flag(String key) => flags[key];

  bool isFlag(String key, String value) => flags[key] == value;

  bool hasFlag(String key) => flags.containsKey(key);
}

enum LoreBlockKind { prose, aside, reveal }

/// A paragraph, optionally gated on narrative state.
class LoreBlock {
  const LoreBlock(this.text, {this.kind = LoreBlockKind.prose, this.when});

  final String text;
  final LoreBlockKind kind;
  final bool Function(LoreContext context)? when;

  bool visibleIn(LoreContext context) => when?.call(context) ?? true;
}

class LoreOption {
  const LoreOption({
    required this.id,
    required this.label,
    required this.detail,
    required this.flags,
  });

  final String id;
  final String label;
  final String detail;
  final Map<String, String> flags;
}

class LoreChoice {
  const LoreChoice({required this.prompt, required this.options});

  final String prompt;
  final List<LoreOption> options;
}

class LoreChapter {
  const LoreChapter({
    required this.number,
    required this.title,
    required this.epigraph,
    required this.blocks,
    this.choice,
    this.endingChosen = false,
  });

  final int number;
  final String title;
  final String epigraph;
  final List<LoreBlock> blocks;
  final LoreChoice? choice;

  /// True when the current narrative state has resolved this chapter's ending.
  final bool endingChosen;

  List<LoreBlock> visibleBlocks(LoreContext context) =>
      blocks.where((block) => block.visibleIn(context)).toList(growable: false);
}

/// The local, structured record of the reader's journey.
///
/// Only ids, short flags, chapter numbers, and scroll offsets are stored. The
/// rendered story itself is never persisted.
class LoreState {
  const LoreState({
    required this.current,
    required this.read,
    required this.introduced,
    required this.choices,
    required this.flags,
    required this.scroll,
  });

  static const int storageVersion = 1;

  final int current;
  final Set<int> read;
  final Set<int> introduced;
  final Map<String, String> choices;
  final Map<String, String> flags;
  final Map<int, double> scroll;

  factory LoreState.initial() => const LoreState(
    current: 1,
    read: <int>{},
    introduced: <int>{},
    choices: <String, String>{},
    flags: <String, String>{},
    scroll: <int, double>{},
  );

  /// Repairs malformed or missing state instead of throwing.
  factory LoreState.fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return LoreState.initial();
    final current = _int(
      raw['current'],
      fallback: 1,
    ).clamp(1, loreChapterCount);
    final read = _chapterSet(raw['read']);
    final introduced = _chapterSet(raw['introduced']);
    final choices = _stringMap(raw['choices']);
    final flags = _stringMap(raw['flags']);
    final scroll = <int, double>{};
    final rawScroll = raw['scroll'];
    if (rawScroll is Map) {
      for (final entry in rawScroll.entries) {
        final chapter = int.tryParse('${entry.key}');
        final value = entry.value is num
            ? (entry.value as num).toDouble()
            : double.tryParse('${entry.value}');
        if (chapter == null ||
            chapter < 1 ||
            chapter > loreChapterCount ||
            value == null ||
            !value.isFinite) {
          continue;
        }
        scroll[chapter] = value.clamp(0, 200000).toDouble();
      }
    }
    // A saved "current" can never leap past the next unread chapter.
    final highestRead = read.isEmpty ? 0 : read.reduce(math.max);
    final safeCurrent = math.min(
      current,
      math.min(loreChapterCount, highestRead + 1),
    );
    return LoreState(
      current: math.max(1, safeCurrent),
      read: read,
      introduced: introduced,
      choices: choices,
      flags: flags,
      scroll: scroll,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': storageVersion,
    'current': current,
    'read': read.toList()..sort(),
    'introduced': introduced.toList()..sort(),
    'choices': choices,
    'flags': flags,
    'scroll': {for (final entry in scroll.entries) '${entry.key}': entry.value},
  };

  bool isRead(int chapter) => read.contains(chapter);

  bool isIntroduced(int chapter) => introduced.contains(chapter);

  double scrollFor(int chapter) => scroll[chapter] ?? 0;

  String? choiceFor(int chapter) => choices['$chapter'];

  String? get ending => flags['ending'];

  LoreState markIntroduced(int chapter) {
    if (introduced.contains(chapter)) return this;
    return _copyWith(introduced: {...introduced, chapter});
  }

  LoreState withScroll(int chapter, double offset) {
    if (!offset.isFinite || offset < 0) return this;
    final next = {...scroll, chapter: offset};
    return _copyWith(scroll: next);
  }

  /// Completes a chapter. Reading an earlier chapter again never rewinds or
  /// skips the furthest point the reader has reached.
  LoreState markRead(int chapter) {
    final nextRead = {...read, chapter};
    final nextCurrent = chapter == current && current < loreChapterCount
        ? current + 1
        : current;
    return _copyWith(read: nextRead, current: nextCurrent);
  }

  /// A chapter's choice can only be made once. Revisiting it never rewrites
  /// the consequences recorded earlier.
  LoreState choose(int chapter, LoreOption option) {
    if (chapter < 1 || chapter > loreChapterCount) return this;
    if (choices['$chapter'] != null) return this;
    return _copyWith(
      flags: {...flags, ...option.flags},
      choices: {...choices, '$chapter': option.id},
    );
  }

  LoreState _copyWith({
    int? current,
    Set<int>? read,
    Set<int>? introduced,
    Map<String, String>? choices,
    Map<String, String>? flags,
    Map<int, double>? scroll,
  }) => LoreState(
    current: current ?? this.current,
    read: read ?? this.read,
    introduced: introduced ?? this.introduced,
    choices: choices ?? this.choices,
    flags: flags ?? this.flags,
    scroll: scroll ?? this.scroll,
  );

  static Set<int> _chapterSet(Object? value) {
    final result = <int>{};
    if (value is List) {
      for (final item in value) {
        final number = item is num ? item.toInt() : int.tryParse('$item');
        if (number != null && number >= 1 && number <= loreChapterCount) {
          result.add(number);
        }
      }
    }
    return result;
  }

  static Map<String, String> _stringMap(Object? value) {
    final result = <String, String>{};
    if (value is Map) {
      for (final entry in value.entries) {
        final key = '${entry.key}';
        if (key.isEmpty || key.length > 40) continue;
        final raw = entry.value;
        if (raw is bool) {
          result[key] = raw ? 'true' : 'false';
        } else if (raw is num || raw is String) {
          final text = '$raw';
          if (text.length <= 64) result[key] = text;
        }
      }
    }
    return result;
  }

  static int _int(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}

/// Builds only the chapter the reader is currently inside. Chapter prose is
/// authored in advance; nothing is generated or fetched at runtime.
LoreChapter buildLoreChapter(int number, LoreContext context) {
  switch (number.clamp(1, loreChapterCount)) {
    case 1:
      return _chapterOne(context);
    case 2:
      return _chapterTwo(context);
    case 3:
      return _chapterThree(context);
    case 4:
      return _chapterFour(context);
    case 5:
      return _chapterFive(context);
    case 6:
      return _chapterSix(context);
    default:
      return _chapterSeven(context);
  }
}

List<LoreBlock> _chapterOneBlocks(LoreContext c) => [
  const LoreBlock(
    r'''The coin is warm when the woman in the grey coat sets it on the counter.''',
    kind: LoreBlockKind.reveal,
  ),
  const LoreBlock(
    r'''Mira has been awake for nineteen hours. She notices the warmth before she notices the coat, before the water wicking off the woman’s sleeves onto the laminate, before the small sound the coin makes as it settles, like a tooth being set down.''',
  ),
  const LoreBlock(r'''“One copy,” the woman says.'''),
  const LoreBlock(
    r'''There are no papers in her hands. The Xerox room is the only lit thing in the basement of the Annex, and at 2:40 in the morning it smells of toner, rain, and the tea Devraj leaves on the radiator until it becomes a kind of syrup. The machine hums its green eye at both of them.''',
  ),
  const LoreBlock(r'''“Of what?” Mira asks.'''),
  const LoreBlock(
    r'''The woman considers the machine the way people consider a dog that has learned one trick. “Of the hour,” she says. “The one you aren’t using.”''',
  ),
  LoreBlock(
    r'''The corridor outside is still full of last night’s rain. Someone is eating a late dinner from a foil box by the lift, and the smell of it follows Mira all the way down the stairs and sits with her behind the counter.''',
    kind: LoreBlockKind.aside,
    when: (context) => context.profile.lateNights || context.profile.foodHeavy,
  ),
  const LoreBlock(
    r'''Mira laughs, because it is 2:40 in the morning and because the alternative is to look directly at the woman’s face, which is the colour of a waiting room. She feeds a blank sheet into the tray. “Sure,” she says. “One hour, coming up.”''',
  ),
  const LoreBlock(
    r'''The machine copies the blank page. Then it copies it again. On the third pass, the sheet comes out with a line of type on it, in a font the machine does not own:''',
  ),
  const LoreBlock(
    r'''RECEIVED — ONE EVENING. RETURNED — NOTHING YET.''',
    kind: LoreBlockKind.reveal,
  ),
  const LoreBlock(
    r'''The woman tears the page along a fold that was not there before. She leaves the coin. She does not leave footprints, although the floor is wet.''',
  ),
  const LoreBlock(
    r'''Devraj finds Mira ten minutes later with the coin in her palm. He is fifty-eight and moves like a man carrying furniture. He looks at the coin, then at the machine, then at Mira, and his face does a thing she has never seen it do: it closes.''',
  ),
  const LoreBlock(
    r'''“Put it somewhere cold,” he says. “Not your pocket. Warm money remembers.”''',
  ),
  const LoreBlock(r'''“It’s a coin,” Mira says.'''),
  const LoreBlock(r'''“It’s a receipt,” he says.'''),
  const LoreBlock(
    r'''In her notebook — the small one, the one where she writes down everything she spends so that the month cannot surprise her — there is a new line. It is in her handwriting. She has not written it.''',
  ),
  const LoreBlock(
    r'''3:17 a.m. — one hour, borrowed. Interest: remember to return it.''',
    kind: LoreBlockKind.reveal,
  ),
  const LoreBlock(
    r'''Outside, the rain stops. Every clock in the Annex agrees on the time at once, and for eleven minutes the building is so quiet that Mira can hear the coin cooling in her hand.''',
    kind: LoreBlockKind.aside,
  ),
];

LoreChapter _chapterOne(LoreContext c) => LoreChapter(
  number: 1,
  title: 'The Warm Coin',
  epigraph: 'A receipt can be a kind of door.',
  blocks: _chapterOneBlocks(c),
);

LoreChapter _chapterTwo(LoreContext c) => LoreChapter(
  number: 2,
  title: 'The Passbook',
  epigraph: 'Some accounts are kept in afternoons.',
  blocks: [
    const LoreBlock(
      r'''The passbook is green, the colour of old hospital doors. Mr. Iyer keeps it under his pillow in ward 9 and holds it out to Mira before she has taken off her rain jacket.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''“The bank has begun using a font I don’t trust,” he says. “Read it to me.”''',
    ),
    const LoreBlock(
      r'''He is eighty-one and has the careful voice of a man who once kept records for a living. Mira sits on the plastic chair beside his bed and opens the book.''',
    ),
    const LoreBlock(
      r'''The first page is ordinary. Name, branch, account number, the date the account was opened. The second page is not.''',
    ),
    const LoreBlock(
      r'''14 NOV 1993 — DEPOSIT — ONE UNCLAIMED FAVOUR''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''02 AUG 1994 — WITHDRAWAL — ONE SUNDAY WITH MY DAUGHTER.''',
    ),
    const LoreBlock(
      r'''11 MAR 1997 — WITHDRAWAL — THE SMELL OF MY WIFE’S HAIR OIL.''',
    ),
    const LoreBlock(
      r'''06 JUN 2001 — WITHDRAWAL — THE SOUND OF MY SON PRACTISING THE VIOLIN.''',
    ),
    const LoreBlock(
      r'''19 JAN 2019 — WITHDRAWAL — THE LAST AFTERNOON IN THE OLD HOUSE.''',
    ),
    const LoreBlock(
      r'''There are more. There are so many more that the dates begin to look like a queue of people waiting for a bus.''',
    ),
    const LoreBlock(r'''“Mr. Iyer,” Mira says. “These aren’t amounts.”'''),
    const LoreBlock(
      r'''“No,” he says. “They are what the amounts were made of.”''',
    ),
    LoreBlock(
      r'''The canteen has smelled of cardamom for three nights now. Mira has started to think of it as the ward’s official weather.''',
      kind: LoreBlockKind.aside,
      when: (context) => context.profile.foodHeavy,
    ),
    const LoreBlock(
      r'''He tells her about his son, who wanted to go to Canada, and the bank that said no, and the other office that said yes. The office had a grey carpet and a woman who did not blink. “They did not take money,” he says. “They took the afternoons. A man can survive without an afternoon.”''',
    ),
    const LoreBlock(r'''“Your son calls you,” Mira says. “I’ve heard you.”'''),
    const LoreBlock(
      r'''“He calls every Sunday,” Mr. Iyer says. “I know he calls because he tells me he called.”''',
    ),
    const LoreBlock(
      r'''On the last page, under PENDING, there is a line that makes Mira’s thumb go still.''',
    ),
    const LoreBlock(
      r'''ONE NIGHT SHIFT — MIRA — TO BE COLLECTED.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''“That’s my name,” she says. The rain has stopped outside, but the window is still beaded with it, and the ward’s one working clock is eleven minutes fast. She has known this for two years and never once thought of it as a fact about the building.''',
    ),
    const LoreBlock(
      r'''“Then you should keep the coin away from the machine,” Mr. Iyer says, and closes his eyes, as if he has just completed a transaction.''',
    ),
    const LoreBlock(
      r'''Anu arrives at the end of visiting hours with a roll of tracing paper under one arm and a samosa in the other. She is studying architecture, which means she has learned to make buildings out of paper and then argue with them.''',
    ),
    const LoreBlock(
      r'''She unrolls the paper across the foot of the bed. It is a map of the Annex: every ward, every stairwell, every cupboard that should not be a cupboard. In the basement, beside the Xerox room, there is a door Mira has never seen.''',
    ),
    const LoreBlock(
      r'''ROOM 0 — RECONCILIATION, the map says, in Anu’s blocky hand. Underneath, smaller: the clocks agree at 3:17.''',
    ),
    const LoreBlock(
      r'''“The basement only has the records office,” Mira says.''',
    ),
    const LoreBlock(
      r'''“I drew it from a dream,” Anu says. “Don’t look at me like that. Architecture is mostly dreams with plumbing.” She taps the corner of the sheet, where the date is written. It is next year’s date.''',
    ),
    const LoreBlock(r'''“You’ve dated it wrong,” Mira says.'''),
    const LoreBlock(
      r'''Anu looks at the date for a long moment, then rolls the map up very carefully, as if it might hear them.''',
    ),
    const LoreBlock(
      r'''That night, the machine is warm when Mira arrives, though nobody has switched it on.''',
      kind: LoreBlockKind.aside,
    ),
  ],
);

LoreChapter _chapterThree(LoreContext c) => LoreChapter(
  number: 3,
  title: 'The Quiet Hour',
  epigraph: 'Every balance has a keeper.',
  blocks: [
    const LoreBlock(
      r'''At 3:17 the Annex goes quiet.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''Not the ordinary quiet of a hospital at night, which is made of small sounds: a trolley, a lift, a nurse laughing once at the end of a corridor. This is the other quiet. The one where the building seems to be holding its breath so that something can count.''',
    ),
    const LoreBlock(
      r'''The Xerox room door opens without a handle turning. The woman in the grey coat sits on the stool Mira has never seen anyone else use. On her lap is a leather folio, and on the folio is a ledger the colour of a drowned leaf.''',
    ),
    const LoreBlock(r'''“You have questions,” the woman says.'''),
    const LoreBlock(r'''“I have a shift,” Mira says. “It ends at five.”'''),
    const LoreBlock(
      r'''The woman opens the ledger. The pages are not paper. They are a thin, grey, patient substance that takes the light and gives nothing back. “In 1993,” she says, “the monsoon took the lower town. Four thousand claims came to Southern Mutual. We did not have the money.”''',
    ),
    const LoreBlock(
      r'''“You had a building,” Mira says, because Devraj has told her this and she has never known why he tells it like a warning.''',
    ),
    const LoreBlock(
      r'''“We had a building, a filing system, and a machine that could reproduce anything placed in front of it.” The woman’s pen moves without her looking at it. “We settled in hours. A Sunday here. A song there. The smell of a kitchen. The town has run eleven minutes fast ever since. You have all been paying the difference without noticing.”''',
    ),
    const LoreBlock(
      r'''Mira thinks of every clock she has ever corrected in this town, and every time she has been told that the correct time is the one the building keeps.''',
    ),
    const LoreBlock(r'''“What does that make you?” she asks.'''),
    const LoreBlock(
      r'''The woman looks up. Her eyes are the exact grey of the ledger. “The last claims adjuster of the Kattur branch,” she says. “My name was Leela Vaz. I signed the settlement on 17 November 1993. The next morning I came to work and the branch had become a book.”''',
    ),
    const LoreBlock(
      r'''She turns the ledger around. There are forty lines on the left-hand page. Thirty-nine are crossed out. The last line is not a name. It is a small drawing of a coin.''',
    ),
    const LoreBlock(
      r'''“Forty tokens were issued to the children at the relief camp,” she says. “They were told they could redeem one night of their choosing. Most of them lost the tokens. Some of them grew up and forgot. Your mother was nine. She kept hers because it was warm.”''',
    ),
    const LoreBlock(
      r'''Mira’s hand goes to her pocket. The coin is there, wrapped in the receipt from the machine. She has not decided when she started carrying it.''',
    ),
    const LoreBlock(
      r'''“The offer,” Leela Vaz says, “is simple. Sign the ledger. Become the keeper of this branch. You will receive an advance against the account: money now, one hour later. An hour you will not miss, because you will not remember it.”''',
    ),
    const LoreBlock(r'''“What hour?”'''),
    const LoreBlock(
      r'''“The ledger chooses. It is not cruel. It is arithmetic.”''',
    ),
    const LoreBlock(
      r'''Behind Mira, the door opens. Devraj stands in the corridor with his cap in his hands, and he looks older than she has ever seen him.''',
    ),
    const LoreBlock(r'''“Don’t,” he says.'''),
    const LoreBlock(
      r'''Leela Vaz does not turn. “Mr. Devraj,” she says. “You signed for one night in 1993. You were twenty-five. You processed the settlement by hand.”''',
    ),
    const LoreBlock(
      r'''“I processed four thousand claims,” Devraj says. “I signed for my wedding.” His voice is very even. “I remember the form. I remember the pen. I don’t remember the wedding. My wife shows me the photographs and I believe her. That is not the same thing as remembering.”''',
    ),
    const LoreBlock(
      r'''“He kept the marriage,” Leela Vaz says to Mira. “He lost the day.”''',
    ),
    const LoreBlock(
      r'''The ledger waits on the counter. The pen lies beside it, warm as a hand.''',
    ),
  ],
  choice: const LoreChoice(
    prompt: 'The pen is waiting.',
    options: [
      LoreOption(
        id: 'sign',
        label: 'Sign the ledger.',
        detail: 'The money arrives tonight. The ledger chooses one remembered hour, later.',
        flags: {'contract': 'signed', 'advance': 'true'},
      ),
      LoreOption(
        id: 'ask',
        label: 'Ask what the ledger actually is.',
        detail: 'No signature. You keep asking questions, and the room keeps answering them.',
        flags: {'contract': 'none', 'asked': 'true'},
      ),
      LoreOption(
        id: 'refuse',
        label: 'Close the ledger and leave.',
        detail:
            'No money. No signature. The account still has to balance somehow.',
        flags: {'contract': 'none'},
      ),
    ],
  ),
);

LoreChapter _chapterFour(LoreContext c) {
  final signed = c.isFlag('contract', 'signed');
  final asked = c.isFlag('asked', 'true');
  return LoreChapter(
    number: 4,
    title: 'What the Advance Buys',
    epigraph: 'The bill always finds the smallest hour first.',
    blocks: [
      if (signed) ...[
        const LoreBlock(
          r'''The money arrives the way weather arrives: without a sound, and then everywhere.''',
          kind: LoreBlockKind.reveal,
        ),
        const LoreBlock(
          r'''Mira does not see it land. She sees the hospital cashier on Tuesday morning, squinting at a screen, then at her, then back at the screen. She sees the physiotherapy department find a cancellation for Thursday. She sees her mother walk from the ward door to the window without holding the rail.''',
        ),
        const LoreBlock(r'''“You didn’t have to,” Kamala says.'''),
        const LoreBlock(
          r'''“I had it,” Mira says, and the sentence feels true in a way that should worry her more than it does.''',
        ),
        const LoreBlock(
          r'''For three days it is simply money. She pays the electricity bill. She buys Anu a new set of fineliners. She sleeps through a whole afternoon and wakes up without the old tightness behind her ribs.''',
        ),
        const LoreBlock(
          r'''Then Anu says, “You cried at the film, remember?”''',
        ),
        const LoreBlock(
          r'''Mira does not remember the film. She remembers agreeing to go. She remembers the poster. She does not remember sitting in the dark beside Anu, or the ending, or walking home afterward with her shoes in her hand.''',
        ),
        const LoreBlock(
          r'''There is a ticket stub in the pocket of her rain jacket. On the back, in her own handwriting: one Tuesday.''',
        ),
        const LoreBlock(
          r'''She tries to remember the tiffin box her mother packed for her on the first day of college. Steel, with a blue lid. She knows this the way she knows the colour of a house she has only seen in photographs.''',
        ),
        const LoreBlock(
          r'''At 3:17 that night, the machine turns itself on in the empty room and prints a single line:''',
        ),
        const LoreBlock(
          r'''INSTALMENT RECEIVED — ONE TUESDAY. BALANCE REMAINING: ONE EVENING.''',
          kind: LoreBlockKind.reveal,
        ),
      ] else ...[
        const LoreBlock(
          r'''Mira does not sign. The ledger closes with a sound like a door in another building.''',
          kind: LoreBlockKind.reveal,
        ),
        const LoreBlock(
          r'''By Thursday, the east wing has lost an hour that nobody can account for. The nurses' station clock is correct; the clock in the dispensary is correct; the clock in Matron's office is eleven minutes slow, which is worse. The physiotherapy department cannot find Mira's mother's file twice in one morning.''',
        ),
        const LoreBlock(
          r'''Devraj's radio loses the cricket. He sits with it on his knee in the corridor, turning the dial, and the static has a rhythm to it, like a room full of people breathing.''',
        ),
        if (asked) ...[
          const LoreBlock(
            r'''“You asked her what the ledger was,” Devraj says. “She told you. That was more than I ever did.”''',
          ),
          const LoreBlock(r'''“What did she tell you?”'''),
          const LoreBlock(
            r'''“That it balances. That it does not punish.” He turns the dial again. “I used to think that was a comfort. A thing that only balances can take the smallest hour first. A song. A smell. The name of a street. It can take them for years and call it fair.”''',
          ),
        ] else ...[
          const LoreBlock(
            r'''“You did the right thing,” Devraj says, and he says it too quickly, the way people reassure a dog.''',
          ),
          const LoreBlock(r'''“Then why is the east wing missing an hour?”'''),
          const LoreBlock(
            r'''“Because the account still exists. It doesn't care whether you sign. It cares that it is owed.”''',
          ),
        ],
        const LoreBlock(
          r'''At home, Mira's mother has stopped mentioning the operation. This is worse than if she had mentioned it.''',
        ),
        const LoreBlock(
          r'''On Saturday, a nurse in the east wing cannot remember her daughter's first word. She laughs about it, then stops laughing. Mira stands in the corridor holding a box of toner and understands that the ledger has started collecting from the town instead.''',
        ),
        const LoreBlock(
          r'''At 3:17 the machine wakes up and prints a new appointment card.''',
        ),
        const LoreBlock(
          r'''KEEPER OF THE KATTUR BRANCH — 3:17 A.M. — BRING THE TOKEN.''',
          kind: LoreBlockKind.reveal,
        ),
      ],
      const LoreBlock(
        r'''Anu is waiting outside the Xerox room when Mira's shift ends. She has the map with her, and she is holding it the way people hold a torch in a power cut.''',
      ),
      const LoreBlock(
        r'''“I checked the hospital plans,” Anu says. “There is no Room 0. There is a records office, a pump room, and a wall.”''',
      ),
      const LoreBlock(r'''“And?”'''),
      const LoreBlock(
        r'''“And the wall is on the map,” Anu says. “I drew a door in it. I want to know why.”''',
      ),
      const LoreBlock(
        r'''They go down together, past the laundry, past the place where the corridor smells of warm dust. The filing cabinet that should be against the east wall has been moved. There is a door behind it. It is not a door anyone has used in a long time, but the handle is clean.''',
      ),
      const LoreBlock(
        r'''At 3:17, the Annex holds its breath again.''',
        kind: LoreBlockKind.aside,
      ),
    ],
  );
}

LoreChapter _chapterFive(LoreContext c) => LoreChapter(
  number: 5,
  title: 'Room Zero',
  epigraph: 'A building remembers what its paperwork forgets.',
  blocks: [
    const LoreBlock(
      r'''Room 0 is smaller than the map promised and colder than the basement. It contains one desk, one chair, a filing cabinet, and a smell of paper that has been kept dry for a very long time.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''Anu holds the map up to the bare bulb. On paper, Room 0 is large enough for a meeting. In the room, Anu's shoulders touch both walls.''',
    ),
    const LoreBlock(r'''“This is the wrong room,” she says.'''),
    const LoreBlock(
      r'''“Or the right one,” Mira says, “seen from the wrong year.”''',
    ),
    const LoreBlock(
      r'''The filing cabinet is full of Southern Mutual folders. Most are claims: water damage, roof collapse, a bicycle, a cow. At the back, in a folder tied with green string, is the settlement.''',
    ),
    const LoreBlock(
      r'''CLAIM 0040 — KATTUR LOWER TOWN — MONSOON 1993.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''The file is thin. A list of forty children. A box of brass tokens. A signed form, three pages, dated 17 November 1993.''',
    ),
    const LoreBlock(
      r'''The signature at the bottom is Devraj's. It is younger and rounder, but unmistakably his.''',
    ),
    const LoreBlock(
      r'''Above it, in a neat, slanting hand: L. VAZ — BRANCH ADJUSTER.''',
    ),
    const LoreBlock(
      r'''The last line of the form is not a signature. It is a transfer notice. TRANSFER TO RECONCILIATION. NO FORWARDING ADDRESS.''',
    ),
    const LoreBlock(
      r'''Anu reads the list of names twice. “Kamala,” she says. “That's your mother.”''',
    ),
    const LoreBlock(
      r'''Number 40. Age nine. Token issued. Token not returned.''',
    ),
    const LoreBlock(
      r'''Mira sits down in the one chair. It is the same stool from the Xerox room. She does not know how she knows this.''',
    ),
    const LoreBlock(
      r'''“They borrowed the town's future,” Anu says slowly, “eleven minutes at a time. That's not a haunting. That's a payment plan.”''',
    ),
    const LoreBlock(r'''“For thirty-three years,” Mira says.'''),
    const LoreBlock(
      r'''“Four thousand claims. Eleven minutes a day.” Anu's mouth moves around the arithmetic and gives up. “The town should be nothing but a queue of people who can't remember why they're standing.”''',
    ),
    const LoreBlock(
      r'''“It takes the smallest hours first,” Mira says. She is thinking of the nurse, and of Devraj's radio, and of a tiffin box she can no longer picture.''',
    ),
    LoreBlock(
      r'''The Annex is quieter than it has been all week. The corridors have the careful hush of a room where everyone has agreed to stop mentioning something.''',
      kind: LoreBlockKind.aside,
      when: (context) =>
          context.profile.hasHistory && context.profile.quietMonth,
    ),
    const LoreBlock(
      r'''Anu finds the ledger inside the filing cabinet, wrapped in oilcloth. It is not a book. It is the building's memory of a book: grey pages, no ink, a spine that is warm to the touch.''',
    ),
    const LoreBlock(r'''“How do you close something like this?” she asks.'''),
    const LoreBlock(
      r'''The answer is written on the inside cover, in the same slanting hand.''',
    ),
    const LoreBlock(
      r'''A BOOK IS CLOSED BY RETURNING THE LAST TOKEN AND ONE REMEMBERED HOUR, FREELY GIVEN. NOT SOLD. NOT BORROWED. GIVEN.''',
      kind: LoreBlockKind.reveal,
    ),
    const LoreBlock(
      r'''“Freely given,” Anu repeats. “So someone has to lose an hour.”''',
    ),
    const LoreBlock(
      r'''“No,” Mira says. “Someone has to choose which one to lose.”''',
    ),
    const LoreBlock(
      r'''Her phone has no signal in the basement. She climbs to the ward and calls her mother from the corridor.''',
    ),
    const LoreBlock(
      r'''“The coin,” Mira says. “The brass one. Where did it come from?”''',
    ),
    const LoreBlock(
      r'''There is a pause full of hospital noise. “They gave them to the children at the camp,” Kamala says. “After the flood. We thought they were toys. I kept mine because it was warm.”''',
    ),
    const LoreBlock(r'''“Why did you give it to me?”'''),
    const LoreBlock(
      r'''“Because you were leaving,” her mother says, as if this explains everything. “For an emergency or an ice cream.”''',
    ),
    const LoreBlock(
      r'''Mira stands in the corridor with the phone against her ear and understands, at last, what the coin is. It is not her inheritance. It is her mother's night. A night from 1993, kept in a drawer for thirty years, handed over in a hostel driveway without a word of explanation.''',
    ),
    const LoreBlock(
      r'''When she gets back to the basement, the machine is already on. The appointment card has been moved to the front of the tray.''',
    ),
    const LoreBlock(
      r'''3:17 A.M. — THE LEDGER IS OPEN.''',
      kind: LoreBlockKind.reveal,
    ),
  ],
);

LoreChapter _chapterSix(LoreContext c) {
  final ending = c.flag('ending');
  final signed = c.isFlag('contract', 'signed');
  return LoreChapter(
    number: 6,
    title: 'The Reconciliation',
    epigraph: 'There are three ways to close a book.',
    endingChosen: ending != null,
    blocks: [
      if (ending == null) ...[
        const LoreBlock(
          r'''The rain has come back. It arrives against the basement window in long grey sheets, and the Annex makes the sound a building makes when it is trying not to be heard.''',
          kind: LoreBlockKind.reveal,
        ),
        const LoreBlock(
          r'''Leela Vaz is already seated. The ledger is open on the counter. Beside it: the coin, her pen, and a second form, blank except for a line at the top that says SETTLEMENT — VOLUNTARY.''',
        ),
        const LoreBlock(r'''“You found Room 0,” she says.'''),
        const LoreBlock(r'''“You left the door behind a filing cabinet.”'''),
        const LoreBlock(
          r'''“I left it where it could be found by someone who was looking.” She folds her hands. “There are three ways to close a book. You may return the token and give one remembered hour, freely. You may take my place, and the town keeps its time, and I go home. Or you may burn the ledger.”''',
        ),
        const LoreBlock(r'''“What happens if I burn it?”'''),
        const LoreBlock(
          r'''“Every borrowed hour comes back at once,” Leela Vaz says. “All of them. To everyone. People are not built for that.”''',
        ),
        const LoreBlock(r'''“And if I take your place?”'''),
        const LoreBlock(
          r'''“The account stays open. The town stays eleven minutes fast. You keep the ledger, and the ledger keeps you.” She says this without self-pity, which is somehow worse. “I was not a bad adjuster. I was a careful one. The book does not need to be cruel.”''',
        ),
        if (signed) ...[
          const LoreBlock(
            r'''Mira takes the advance receipt out of her pocket. It is warm, the way the coin was warm. She has been carrying it for a week, and she has begun to understand that the ledger did not choose a Tuesday because it was small. It chose a Tuesday because she would not notice until it was gone.''',
          ),
        ] else ...[
          const LoreBlock(
            r'''Mira takes the coin out of her pocket. It is warm, the way it has been warm since the first night. For a week she has been telling herself that the warmth is ordinary friction, body heat, physics. She has stopped believing it.''',
          ),
        ],
        const LoreBlock(
          r'''“The hour has to be remembered,” Leela Vaz says. “You cannot give me one you have already lost. It must be a real hour, one you would have kept.”''',
        ),
        const LoreBlock(
          r'''Mira looks at the blank form. Behind her, Devraj stands in the doorway. Anu is somewhere above them in the wards, holding a map of a room that should not exist. The rain goes on. The whole town is eleven minutes into a future it did not agree to.''',
        ),
      ],
      if (ending == 'return') ...[
        const LoreBlock(r'''THE LEDGER CLOSES''', kind: LoreBlockKind.reveal),
        const LoreBlock(
          r'''The hour Mira chooses is not a grand one. It is the first night she came to Kattur: the bus arriving at dawn with its lights still on, her mother waiting on the platform with a steel tiffin box, the two of them walking to the hostel through streets that smelled of wet stone and someone else's breakfast. She has kept it for two years without knowing she was keeping it.''',
        ),
        const LoreBlock(
          r'''She says it out loud. Leela Vaz writes it down. The pen makes no sound on the grey page, and then something in Mira's chest goes quiet, like a room after a guest has left.''',
        ),
        const LoreBlock(
          r'''She remembers that she used to remember it. That is all. The tiffin box is gone. The platform is gone. Her mother's face in the dawn light is gone, replaced by the knowledge that it was there.''',
        ),
        const LoreBlock(
          r'''Leela Vaz closes the ledger. The coin goes cold in Mira's hand, an ordinary piece of brass with a hole in it. Outside, every clock in the Annex moves backward eleven minutes at once. Somewhere above them, a nurse looks up at the wall and frowns.''',
        ),
        const LoreBlock(
          r'''“The account is settled,” Leela Vaz says. She takes off her grey coat and folds it over the back of the chair. Without it she is a tired woman in a cardigan, someone's aunt, someone's former supervisor. “I have been at work for thirty-three years,” she says. “I would like to go home.”''',
        ),
        const LoreBlock(
          r'''Devraj makes a sound in the doorway. He is crying in the way that men of his generation cry, which is to say he is standing very still and looking at the ceiling. “The harmonium,” he says. “My wedding. There was a harmonium, and my wife's cousin was singing off-key, and it rained the whole afternoon.” He laughs, once, wetly. “I remember the rain.”''',
        ),
        const LoreBlock(
          r'''The machine prints one last page and then goes dark. Nobody reads it. There is nothing left to collect.''',
        ),
      ],
      if (ending == 'keeper') ...[
        const LoreBlock(
          r'''THE LEDGER CHANGES HANDS''',
          kind: LoreBlockKind.reveal,
        ),
        const LoreBlock(
          r'''Mira signs. The pen is warm, and then it is not, and then it is her pen. Leela Vaz stands up, folds her grey coat over her arm, and walks out of Room 0 without looking back. At the door she pauses, as if she has forgotten something, then continues. Mira never sees her again.''',
        ),
        const LoreBlock(
          r'''The money arrives. Her mother walks. The physiotherapy department finds a permanent slot, and the hospital cashier stops squinting at her. For a while it is almost ordinary.''',
        ),
        const LoreBlock(
          r'''But the town stays eleven minutes fast. Mira learns to feel the difference the way a sailor feels weather. She learns which hours the ledger takes and from whom. It is never cruel. It takes a song from a man who has forgotten his mother's voice, an afternoon from a woman who works double shifts, a Tuesday from a girl who will not notice for a week. Mira writes them all down.''',
        ),
        const LoreBlock(
          r'''She is careful. She is, she tells herself, the most careful adjuster the Kattur branch has ever had.''',
        ),
        const LoreBlock(
          r'''On her twenty-third birthday, Anu brings the map to the Xerox room. It is a good map. It shows the ward, the laundry, the corridor, Room 0. In the corner, in Anu's blocky hand, the date is next year.''',
        ),
        const LoreBlock(
          r'''“Come out,” Anu says. “It's my birthday too, technically. We can get dinner.”''',
        ),
        const LoreBlock(r'''“At 3:17,” Mira says. “I have an appointment.”'''),
        const LoreBlock(
          r'''The grey coat fits her better than she expected.''',
          kind: LoreBlockKind.aside,
        ),
      ],
      if (ending == 'burn') ...[
        const LoreBlock(
          r'''THE BOOK IS NOT CLOSED. IT IS SCATTERED.''',
          kind: LoreBlockKind.reveal,
        ),
        const LoreBlock(
          r'''Mira takes the ledger down to the service lift, where the metal bin is, and sets it alight. It burns the colour of a hospital corridor at night: green, then white, then nothing.''',
        ),
        const LoreBlock(r'''The hours come back all at once.'''),
        const LoreBlock(
          r'''For eleven minutes, everyone in the Annex remembers everything. A nurse remembers her daughter's first word and the exact shape of her mouth around it. Devraj remembers his wedding, the rain, the harmonium, his wife's cousin singing off-key, the rice on the floor. Mr. Iyer remembers every Sunday his son ever called. Mira remembers the tiffin box, the platform, her mother's hands, all of it, and then she remembers every other thing the ledger has ever taken from anyone in Kattur, as if the whole town has been poured through her at once.''',
        ),
        const LoreBlock(r'''Then it stops.'''),
        const LoreBlock(
          r'''The clocks stop at 3:17. Not eleven minutes fast. Not eleven minutes slow. Stopped. The east wing loses power and does not get it back for two days. In the morning, people remember that they remembered something, but not what. The hospital buys battery clocks. The town starts using its phones.''',
        ),
        const LoreBlock(
          r'''The debt is not settled. It is only no longer organised.''',
        ),
        const LoreBlock(
          r'''Mira keeps the coin. It stays warm. She is never sure whether it is a scar or a promise.''',
        ),
      ],
      if (ending != null) ...[
        const LoreBlock(
          r'''Outside, the rain thins to nothing. Somewhere in the Annex, a trolley goes past. The building is only a building again, which is a sentence Mira will not understand for several weeks.''',
        ),
      ],
    ],
    choice: ending == null
        ? const LoreChoice(
            prompt: 'The ledger is open. Choose.',
            options: [
              LoreOption(
                id: 'return',
                label: 'Return the token. Give one hour.',
                detail: 'The ledger closes. You keep everything except one remembered hour.',
                flags: {'ending': 'return', 'offered': 'true'},
              ),
              LoreOption(
                id: 'keeper',
                label: 'Take her place.',
                detail: 'The town keeps its time. The money arrives. You keep the ledger.',
                flags: {'ending': 'keeper', 'advance': 'true'},
              ),
              LoreOption(
                id: 'burn',
                label: 'Burn the ledger.',
                detail: 'Every borrowed hour returns at once. No one controls where they land.',
                flags: {'ending': 'burn'},
              ),
            ],
          )
        : null,
  );
}

LoreChapter _chapterSeven(LoreContext c) {
  final ending = c.flag('ending');
  return LoreChapter(
    number: 7,
    title: 'The Ordinary Ledger',
    epigraph: 'Most chapters are not mysteries. They are just months.',
    blocks: [
      const LoreBlock(
        r'''Three weeks later, the canteen is serving something that is technically a sandwich, and Anu is arguing with a structural engineer on speakerphone about the load-bearing properties of a wall that does not exist.''',
        kind: LoreBlockKind.reveal,
      ),
      if (ending == 'return') ...[
        const LoreBlock(
          r'''Kamala's physiotherapy is approved by the hospital hardship committee on a Wednesday. There is no magic in it. Mr. Iyer writes a letter. A clerk finds a form. Two people sign it and one of them is on leave and has to sign it again when he returns. It takes eleven days and three phone calls, and on the last call Mira sits on the floor of the hostel corridor because there is nowhere else quiet.''',
        ),
        const LoreBlock(
          r'''Devraj remembers his wedding. He remembers it constantly, at the gate, in the lift, at the tea stall, to anyone who will listen. His wife pretends to be annoyed. She is not annoyed.''',
        ),
        const LoreBlock(
          r'''Anu's map is now pinned above Mira's desk. It shows Room 0 as a store room with a broken chair and a bucket. Anu has drawn a small plant in the corner, because she is an optimist.''',
        ),
        const LoreBlock(
          r'''Mira cannot remember the tiffin box. She can remember that it was steel with a blue lid, because she wrote it down. The drawing Anu made of that first morning is not accurate, either: Anu was not there. But it has the bus, and the wet stone, and two figures walking, and Mira looks at it more often than she would admit.''',
        ),
      ],
      if (ending == 'keeper') ...[
        const LoreBlock(
          r'''Kamala walks without the rail now. She has started taking the stairs to the tailor shop because the lift is slow, and because she can.''',
        ),
        const LoreBlock(
          r'''Mira works nights. The Xerox room is busier than it has ever been. Students come at 2 a.m. with dissertations and broken phones and the particular panic of people who have one hour left. Mira copies their pages, takes their coins, and listens for the eleven minutes.''',
        ),
        const LoreBlock(
          r'''Anu still brings the map. She has started adding rooms Mira has not seen yet, which is either a gift or a warning. The plant she drew in Room 0 has grown a second leaf.''',
        ),
        const LoreBlock(
          r'''Devraj has stopped asking Mira what happens at 3:17. He brings her tea instead, and leaves it on the radiator, and she drinks it before it becomes syrup. This is how they say it.''',
        ),
      ],
      if (ending == 'burn') ...[
        const LoreBlock(
          r'''The east wing is repaired. The hospital buys battery clocks and then replaces them with ordinary ones. Nobody talks about the night the clocks stopped, although everybody remembers that something happened, the way people remember a dream they did not write down.''',
        ),
        const LoreBlock(
          r'''Kamala's physiotherapy is approved eventually. The delay is a form, then another form, then a clerk who is on leave. Mira pays for the first two sessions with the money she has, and the hospital waives the third, and it is fine. It is not magic. It is just slow.''',
        ),
        const LoreBlock(
          r'''Devraj still cannot remember his wedding. He has stopped pretending that he can. But sometimes, at the gate, he hums a tune he cannot name, and his wife looks up from her phone and smiles at him.''',
        ),
        const LoreBlock(
          r'''The coin is warm in Mira's pocket. She has stopped trying to explain it. Some days it is the only thing in Kattur that keeps the old time.''',
        ),
      ],
      const LoreBlock(
        r'''Mr. Iyer goes home in October. His son calls on Sundays. He still cannot remember the calls, but he has started writing them down in the green passbook, one line each, in his own hand: a Sunday, a Sunday, a Sunday.''',
      ),
      const LoreBlock(
        r'''Mira's notebook is ordinary again. It has coffee rings on the cover and a page for each month, and the numbers add up the way numbers do: badly, then eventually. She still writes down everything she spends. The month can still surprise her. She has decided that this is not the same as being ambushed.''',
      ),
      LoreBlock(
        r'''On the last night of the month, she buys a cold coffee she does not need, and logs it, and the page stays a page.''',
        when: (context) {
          if (!context.profile.hasHistory) return false;
          return context.profile.lateNights || context.profile.foodHeavy;
        },
      ),
      const LoreBlock(
        r'''At 3:17 she wakes. The room is only a room. The building is only a building. On the desk, the ledger is a notebook with a coffee ring on the cover, and the month ahead is not a mystery, only unfinished.''',
      ),
      const LoreBlock(r'''She turns the page.''', kind: LoreBlockKind.reveal),
    ],
  );
}
