import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AllowanceCycle {
  const AllowanceCycle({
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

/// The single local source of truth for Paisa. No account or network is needed.
class PaisaStore extends ChangeNotifier {
  static const _storageKey = 'paisa_flutter_ledger_v1';
  static const _legacyChannel = MethodChannel('com.paisaexe.app/legacy');

  final SharedPreferences _prefs;
  late List<Map<String, dynamic>> transactions;
  late Map<String, double> budgets;
  late List<Map<String, dynamic>> campusFood;
  late List<String> foodLikes;
  late Map<String, int> foodOrders;
  late List<String> messFavorites;
  late String messTodayMenu;
  late Map<String, dynamic> recurringIncome;
  late double openingBalance;
  late double monthlyIncome;
  late bool privacy;
  late String privacyStyle;
  late bool reduceMotion;
  late bool roast;
  late bool lightMode;
  late String palette;
  late bool demoSeeded;
  late bool financeDemoSeeded;

  PaisaStore._(this._prefs, Map<String, dynamic> data) {
    final defaults = _defaults();
    defaults.addAll(data);
    transactions = _maps(defaults['transactions']);
    budgets = (defaults['budgets'] as Map).map(
      (k, v) => MapEntry(k.toString(), _number(v)),
    );
    campusFood = _maps(defaults['campusFood']);
    foodLikes = List<String>.from(defaults['foodLikes'] ?? const []);
    foodOrders = (defaults['foodOrders'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k.toString(), _number(v).round()),
    );
    messFavorites = List<String>.from(defaults['messFavorites'] ?? const []);
    messTodayMenu = '${defaults['messTodayMenu'] ?? ''}';
    recurringIncome = Map<String, dynamic>.from(
      defaults['recurringIncome'] as Map? ?? const {},
    );
    openingBalance = _number(defaults['openingBalance']);
    monthlyIncome = _number(defaults['monthlyIncome'], fallback: 12000);
    privacy = defaults['privacy'] == true;
    privacyStyle = '${defaults['privacyStyle'] ?? 'blur'}';
    reduceMotion = defaults['reduceMotion'] == true;
    roast = defaults['roast'] != false;
    lightMode = defaults['theme'] == 'light';
    palette = '${defaults['palette'] ?? 'cherry'}';
    if (palette == 'crimson' || palette == 'toxic') palette = 'cherry';
    demoSeeded = defaults['campusDemoSeeded'] == true;
    financeDemoSeeded = defaults['financeDemoSeeded'] == true;
  }

  static Future<PaisaStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      } catch (_) {}
    } else {
      // The old Android build kept a native backup specifically for upgrades.
      // Read that backup before initializing a fresh Flutter ledger.
      try {
        final legacy = await _legacyChannel.invokeMethod<String>(
          'getLegacyData',
        );
        if (legacy != null && legacy.isNotEmpty) {
          data = Map<String, dynamic>.from(jsonDecode(legacy) as Map);
        }
      } catch (_) {}
    }
    final store = PaisaStore._(prefs, data);
    if (!store.demoSeeded && store.transactions.isEmpty) {
      store._seedDemoTransactions();
    }
    if (!store.financeDemoSeeded) store._seedCategoryDemoTransactions();
    await store.processDueIncome();
    await store._persist();
    return store;
  }

  static List<Map<String, dynamic>> _maps(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  static double _number(dynamic value, {double fallback = 0}) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  static double numberForUi(dynamic value) => _number(value);

  static Map<String, dynamic> _defaults() => {
    'transactions': <Map<String, dynamic>>[],
    'budgets': <String, double>{
      'Food & snacks': 3500,
      'Food delivery': 1200,
      'Transport': 1000,
      'College & printing': 700,
      'Shopping': 1000,
      'Subscriptions': 600,
      'Social & fun': 1200,
      'Personal care': 600,
      'Miscellaneous': 800,
    },
    'openingBalance': 0,
    'monthlyIncome': 12000,
    'privacy': false,
    'privacyStyle': 'blur',
    'reduceMotion': false,
    'roast': true,
    'theme': 'dark',
    'palette': 'cherry',
    'messFavorites': <String>[],
    'messTodayMenu': '',
    'campusFood': _sampleFood(),
    'foodLikes': <String>[],
    'foodOrders': <String, int>{},
    'recurringIncome': <String, dynamic>{
      'enabled': false,
      'amount': 0,
      'frequency': 'monthly',
      'nextDate': '',
      'autoAdd': false,
      'anchorDay': 1,
      'description': 'Pocket money',
    },
    'campusDemoSeeded': false,
    'financeDemoSeeded': false,
  };

  static List<Map<String, dynamic>> _sampleFood() => [
    _shop('KC Foods', 'Near KC', [
      ['Aloo paratha', 65],
      ['Paneer paratha', 85],
      ['Veg grilled sandwich', 70],
      ['Masala Maggi', 55],
      ['Cold coffee', 80],
    ]),
    _shop('Darling Bakery', 'VIT Main Gate', [
      ['Veg puff', 25],
      ['Paneer roll', 65],
      ['Brownie', 55],
      ['Lime soda', 45],
      ['Cheese sandwich', 75],
    ]),
    _shop('Foodys', 'Campus', [
      ['Veg burger', 90],
      ['Peri peri fries', 80],
      ['Paneer wrap', 110],
      ['Lemon iced tea', 60],
      ['Choco shake', 95],
    ]),
    _shop('Waffletime', 'Campus', [
      ['Classic waffle', 100],
      ['Chocolate waffle', 130],
      ['Nutella waffle', 160],
      ['Cold coffee', 90],
    ]),
    _shop('Sai Tiffins', 'Near VIT', [
      ['Masala dosa', 85],
      ['Idli (2 pcs)', 45],
      ['Veg fried rice', 100],
      ['Paneer dosa', 110],
      ['Filter coffee', 35],
    ]),
  ];

  static Map<String, dynamic> _shop(
    String name,
    String area,
    List<List<Object>> items,
  ) => {
    'shop': name,
    'area': area,
    'items': items.map((item) => {'name': item[0], 'price': item[1]}).toList(),
  };

  Future<void> _persist() async => _prefs.setString(
    _storageKey,
    jsonEncode({
      'transactions': transactions,
      'budgets': budgets,
      'openingBalance': openingBalance,
      'monthlyIncome': monthlyIncome,
      'privacy': privacy,
      'privacyStyle': privacyStyle,
      'reduceMotion': reduceMotion,
      'roast': roast,
      'theme': lightMode ? 'light' : 'dark',
      'palette': palette,
      'messFavorites': messFavorites,
      'messTodayMenu': messTodayMenu,
      'campusFood': campusFood,
      'foodLikes': foodLikes,
      'foodOrders': foodOrders,
      'recurringIncome': recurringIncome,
      'campusDemoSeeded': demoSeeded,
      'financeDemoSeeded': financeDemoSeeded,
    }),
  );

  Future<void> _saveAndNotify() async {
    await _persist();
    notifyListeners();
  }

  double get balance => openingBalance + total('income') - total('expense');
  DateTime get today => DateTime.now();
  int get daysRemaining =>
      DateTime(today.year, today.month + 1, 0).day - today.day + 1;

  int get daysUntilPocketMoney =>
      allowanceCycle(today, recurringIncome).daysUntil;

  static AllowanceCycle allowanceCycle(
    DateTime value,
    Map<String, dynamic> schedule,
  ) {
    final date = DateTime(value.year, value.month, value.day);
    if (schedule['enabled'] != true) {
      final nextMonth = DateTime(date.year, date.month + 1, 1);
      final monthDays = nextMonth
          .difference(DateTime(date.year, date.month, 1))
          .inDays;
      return AllowanceCycle(
        isPayday: false,
        progress: (date.day - 1) / (monthDays - 1),
        daysUntil: nextMonth.difference(date).inDays,
        payday: nextMonth,
      );
    }

    final frequency = '${schedule['frequency'] ?? 'monthly'}';
    if (frequency == 'weekly' || frequency == 'fortnightly') {
      final anchor = DateTime.tryParse('${schedule['nextDate']}');
      if (anchor != null) {
        final interval = frequency == 'weekly' ? 7 : 14;
        final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
        final delta = date.difference(anchorDay).inDays;
        final elapsed = ((delta % interval) + interval) % interval;
        final isPayday = elapsed == 0;
        final daysUntil = isPayday ? 0 : interval - elapsed;
        return AllowanceCycle(
          isPayday: isPayday,
          progress: isPayday ? 0 : (elapsed / (interval - 1)).clamp(0.0, 1.0),
          daysUntil: daysUntil,
          payday: date.add(Duration(days: daysUntil)),
        );
      }
    }

    final storedNext = DateTime.tryParse('${schedule['nextDate']}');
    final anchorDay = schedule['anchorDay'] is num
        ? (schedule['anchorDay'] as num).round().clamp(1, 31).toInt()
        : storedNext?.day ?? 1;
    DateTime paydayIn(int year, int month) {
      final monthDays = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, anchorDay.clamp(1, monthDays).toInt());
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
    return AllowanceCycle(
      isPayday: isPayday,
      progress: isPayday ? 0 : (elapsed / (cycleDays - 1)).clamp(0.0, 1.0),
      daysUntil: isPayday ? 0 : nextPayday.difference(date).inDays,
      payday: isPayday ? thisMonth : nextPayday,
    );
  }

  List<Map<String, dynamic>> get monthTransactions => transactions.where((t) {
    final date = DateTime.tryParse('${t['date']}');
    return date != null && date.year == today.year && date.month == today.month;
  }).toList();

  double total(String type, [Iterable<Map<String, dynamic>>? from]) =>
      (from ?? transactions)
          .where((t) => t['type'] == type)
          .fold<double>(0, (sum, t) => sum + _number(t['amount']));

  double categorySpend(String category) => monthTransactions
      .where((t) => t['category'] == category && t['type'] == 'expense')
      .fold<double>(0, (sum, t) => sum + _number(t['amount']));

  double get monthlyBudget => budgets.values.fold<double>(0, (a, b) => a + b);
  double get dailyPace =>
      balance > 0 ? balance / daysUntilPocketMoney.clamp(1, 365) : 0;
  List<Map<String, dynamic>> get sortedTransactions {
    final list = [...transactions];
    list.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return list;
  }

  Future<void> addTransaction(Map<String, dynamic> value) async {
    final t = Map<String, dynamic>.from(value);
    t['id'] ??= DateTime.now().microsecondsSinceEpoch.toString();
    t['created'] ??= DateTime.now().toIso8601String();
    t['description'] = '${t['description'] ?? ''}'.trim().isEmpty
        ? '${t['category'] ?? 'Transaction'}'
        : '${t['description']}'.trim();
    transactions.add(t);
    if (t['foodItem'] != null) {
      foodOrders['${t['foodItem']}'] =
          (foodOrders['${t['foodItem']}'] ?? 0) + 1;
    }
    await _saveAndNotify();
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> value) async {
    final index = transactions.indexWhere((t) => t['id'] == id);
    if (index < 0) return;
    transactions[index] = {...transactions[index], ...value};
    await _saveAndNotify();
  }

  Future<void> deleteTransaction(String id) async {
    transactions.removeWhere((t) => t['id'] == id);
    await _saveAndNotify();
  }

  Future<void> toggleFoodLike(String name) async {
    if (foodLikes.contains(name)) {
      foodLikes.remove(name);
    } else {
      foodLikes.add(name);
    }
    await _saveAndNotify();
  }

  Future<void> saveSettings({
    double? opening,
    double? income,
    bool? hideBalances,
    bool? roastMode,
    bool? light,
    String? selectedPalette,
    List<String>? favorites,
    String? messMenu,
    String? hiddenAmountStyle,
    bool? reduceAnimations,
  }) async {
    openingBalance = opening ?? openingBalance;
    monthlyIncome = income ?? monthlyIncome;
    privacy = hideBalances ?? privacy;
    privacyStyle = hiddenAmountStyle ?? privacyStyle;
    reduceMotion = reduceAnimations ?? reduceMotion;
    roast = roastMode ?? roast;
    lightMode = light ?? lightMode;
    palette = selectedPalette ?? palette;
    messFavorites = favorites ?? messFavorites;
    messTodayMenu = messMenu ?? messTodayMenu;
    await _saveAndNotify();
  }

  Future<void> saveBudget(String category, double amount) async {
    budgets[category] = amount;
    await _saveAndNotify();
  }

  Future<void> removeBudget(String category) async {
    budgets.remove(category);
    await _saveAndNotify();
  }

  Future<void> saveSchedule(Map<String, dynamic> schedule) async {
    recurringIncome = schedule;
    await processDueIncome();
    await _saveAndNotify();
  }

  DateTime _advance(DateTime from) {
    switch ('${recurringIncome['frequency']}') {
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'fortnightly':
        return from.add(const Duration(days: 14));
      default:
        final day = _number(
          recurringIncome['anchorDay'],
          fallback: from.day.toDouble(),
        ).round();
        final first = DateTime(from.year, from.month + 1, 1);
        final last = DateTime(first.year, first.month + 1, 0).day;
        return DateTime(first.year, first.month, day.clamp(1, last).toInt());
    }
  }

  Future<bool> addNextIncome({bool automatic = false}) async {
    if (recurringIncome['enabled'] != true ||
        _number(recurringIncome['amount']) <= 0)
      return false;
    final date = DateTime.tryParse('${recurringIncome['nextDate']}') ?? today;
    final amount = _number(recurringIncome['amount']);
    transactions.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'created': DateTime.now().toIso8601String(),
      'date': DateFormat('yyyy-MM-dd').format(date),
      'type': 'income',
      'amount': amount,
      'description': '${recurringIncome['description'] ?? 'Pocket money'}',
      'category': 'Income',
      'payment': '',
      'recurring': true,
      'notes': automatic
          ? 'Added automatically by Paisa'
          : 'Pocket money added manually',
    });
    recurringIncome['nextDate'] = DateFormat('yyyy-MM-dd')
        .format(_advance(date));
    await _saveAndNotify();
    return true;
  }

  Future<void> processDueIncome() async {
    if (recurringIncome['enabled'] != true ||
        recurringIncome['autoAdd'] != true)
      return;
    final parsedNext = DateTime.tryParse('${recurringIncome['nextDate']}');
    if (parsedNext == null) return;
    DateTime next = parsedNext;
    final todayDate = DateTime(today.year, today.month, today.day);
    var count = 0;
    while (!next.isAfter(todayDate) && count++ < 24) {
      transactions.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'created': DateTime.now().toIso8601String(),
        'date': DateFormat('yyyy-MM-dd').format(next),
        'type': 'income',
        'amount': _number(recurringIncome['amount']),
        'description': '${recurringIncome['description'] ?? 'Pocket money'}',
        'category': 'Income',
        'payment': '',
        'recurring': true,
        'notes': 'Added automatically by Paisa',
      });
      next = _advance(next);
      recurringIncome['nextDate'] = DateFormat('yyyy-MM-dd').format(next);
    }
  }

  Future<void> reset() async {
    final fresh = PaisaStore._(_prefs, _defaults());
    transactions = fresh.transactions;
    budgets = fresh.budgets;
    campusFood = fresh.campusFood;
    foodLikes = fresh.foodLikes;
    foodOrders = fresh.foodOrders;
    messFavorites = fresh.messFavorites;
    messTodayMenu = fresh.messTodayMenu;
    recurringIncome = fresh.recurringIncome;
    openingBalance = fresh.openingBalance;
    monthlyIncome = fresh.monthlyIncome;
    privacy = fresh.privacy;
    privacyStyle = fresh.privacyStyle;
    reduceMotion = fresh.reduceMotion;
    roast = fresh.roast;
    lightMode = fresh.lightMode;
    palette = fresh.palette;
    demoSeeded = true;
    financeDemoSeeded = true;
    await _saveAndNotify();
  }

  void _seedCategoryDemoTransactions() {
    final samples = <List<Object>>[
      ['expense', 185, 'DEMO · Late-night campus delivery', 'Food delivery', 1],
      ['expense', 48, 'DEMO · Auto to North Gate', 'Transport', 3],
      ['expense', 32, 'DEMO · Lab notes printout', 'College & printing', 5],
      ['expense', 329, 'DEMO · Charging cable', 'Shopping', 7],
      ['expense', 119, 'DEMO · Music plan', 'Subscriptions', 9],
      ['expense', 210, 'DEMO · Friday game night', 'Social & fun', 11],
      ['expense', 95, 'DEMO · Face wash', 'Personal care', 14],
      ['expense', 68, 'DEMO · Laundry token', 'Miscellaneous', 17],
      ['expense', 42, 'DEMO · Evening chai', 'Food & snacks', 20],
      ['income', 2400, 'DEMO · Pocket money', 'Income', 8],
      ['income', 650, 'DEMO · Shared notes refund', 'Income', 19],
    ];
    final now = today;
    for (final item in samples) {
      final day = (now.day - (item[4] as int)).clamp(1, now.day).toInt();
      final date = DateTime(now.year, now.month, day);
      transactions.add({
        'id':
            'demo-category-${date.millisecondsSinceEpoch}-${transactions.length}',
        'created': date.toIso8601String(),
        'date': DateFormat('yyyy-MM-dd').format(date),
        'type': item[0],
        'amount': item[1],
        'description': item[2],
        'category': item[3],
        'payment': 'UPI',
        'recurring': false,
        'notes': 'Sample transaction for testing · safe to delete',
        'demo': true,
      });
    }
    financeDemoSeeded = true;
  }

  void _seedDemoTransactions() {
    final samples = <List<Object>>[
      ['expense', 65, 'DEMO · KC Foods · Aloo paratha', 'Food & snacks', 0],
      ['expense', 85, 'DEMO · KC Foods · Paneer paratha', 'Food & snacks', 1],
      ['expense', 55, 'DEMO · KC Foods · Masala Maggi', 'Food & snacks', 2],
      ['expense', 25, 'DEMO · Darling Bakery · Veg puff', 'Food & snacks', 3],
      [
        'expense',
        65,
        'DEMO · Darling Bakery · Paneer roll',
        'Food & snacks',
        4,
      ],
      ['expense', 90, 'DEMO · Foodys · Veg burger', 'Food & snacks', 5],
      ['expense', 80, 'DEMO · Foodys · Peri peri fries', 'Food & snacks', 6],
      ['expense', 100, 'DEMO · Sai Tiffins · Masala dosa', 'Food & snacks', 7],
      ['expense', 45, 'DEMO · Sai Tiffins · Idli', 'Food & snacks', 8],
      [
        'expense',
        100,
        'DEMO · Waffletime · Classic waffle',
        'Food & snacks',
        9,
      ],
      ['expense', 60, 'DEMO · Foodys · Lemon iced tea', 'Food & snacks', 10],
      [
        'expense',
        75,
        'DEMO · KC Foods · Grilled sandwich',
        'Food & snacks',
        11,
      ],
      [
        'expense',
        35,
        'DEMO · Sai Tiffins · Filter coffee',
        'Food & snacks',
        12,
      ],
      ['expense', 55, 'DEMO · Darling Bakery · Brownie', 'Food & snacks', 13],
      ['expense', 110, 'DEMO · Sai Tiffins · Paneer dosa', 'Food & snacks', 14],
      ['income', 1500, 'DEMO · Pocket money', 'Income', 15],
      ['income', 1000, 'DEMO · Family transfer', 'Income', 17],
      ['income', 2000, 'DEMO · Pocket money', 'Income', 20],
    ];
    for (final item in samples) {
      final date = today.subtract(Duration(days: item[4] as int));
      transactions.add({
        'id': 'demo-${date.millisecondsSinceEpoch}-${transactions.length}',
        'created': date.toIso8601String(),
        'date': DateFormat('yyyy-MM-dd').format(date),
        'type': item[0],
        'amount': item[1],
        'description': item[2],
        'category': item[3],
        'payment': 'UPI',
        'recurring': false,
        'notes': 'Sample transaction for testing · safe to delete',
        'demo': true,
      });
    }
    demoSeeded = true;
  }
}
