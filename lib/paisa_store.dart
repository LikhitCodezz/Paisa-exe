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

class PrivacyPinAttempt {
  const PrivacyPinAttempt({
    required this.success,
    this.retryAfterSeconds = 0,
    this.attemptsRemaining = 0,
  });

  final bool success;
  final int retryAfterSeconds;
  final int attemptsRemaining;

  factory PrivacyPinAttempt.fromPlatform(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid secure PIN response.');
    }
    final result = Map<Object?, Object?>.from(value);
    return PrivacyPinAttempt(
      success: result['success'] == true,
      retryAfterSeconds: (result['retryAfterSeconds'] as num? ?? 0).toInt(),
      attemptsRemaining: (result['attemptsRemaining'] as num? ?? 0).toInt(),
    );
  }
}

/// Cached month-to-date ledger totals so list screens do not re-scan every
/// transaction during each rebuild.
class _MonthTotals {
  const _MonthTotals(
    this.visibleIncome,
    this.visibleExpense,
    this.hiddenExpense,
  );

  final double visibleIncome;
  final double visibleExpense;
  final double hiddenExpense;
}

/// A grouped view over the user's opted-in/identified expense records.
/// The underlying transactions remain the source of truth.
class PriceMemoryEntry {
  const PriceMemoryEntry({
    required this.item,
    required this.place,
    required this.category,
    required this.transactions,
  });

  final String item;
  final String place;
  final String category;
  final List<Map<String, dynamic>> transactions;

  Map<String, dynamic> get latest => transactions.first;
  Map<String, dynamic>? get previous =>
      transactions.length > 1 ? transactions[1] : null;
  String get identity => '${_normalize(item)}|${_normalize(place)}';

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// The single local source of truth for Paisa. No account or network is needed.
class PaisaStore extends ChangeNotifier {
  static const _storageKey = 'paisa_flutter_ledger_v1';
  static const _loreKey = 'paisa_lore_v1';
  static const _legacyChannel = MethodChannel('com.paisaexe.app/legacy');
  static const _privacyChannel = MethodChannel('com.paisaexe.app/privacy');

  static bool get _usesAndroidSecureStorage =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
  Map<String, dynamic> loreState = const <String, dynamic>{};
  bool privateVaultAvailable = true;

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
    var vaultLoaded = true;
    if (_usesAndroidSecureStorage) {
      String encrypted;
      try {
        encrypted =
            await _privacyChannel.invokeMethod<String>(
              'loadHiddenTransactions',
            ) ??
            '[]';
      } on PlatformException catch (error) {
        debugPrint('Paisa private vault load failed: ${error.code}');
        vaultLoaded = false;
        encrypted = '[]';
      }
      final hidden = _maps(jsonDecode(encrypted));
      final byId = <String, Map<String, dynamic>>{
        for (final transaction in store.transactions)
          if (transaction['id'] != null) '${transaction['id']}': transaction,
      };
      for (final transaction in hidden) {
        final id = transaction['id'];
        if (id != null) {
          transaction['hidden'] = true;
          byId['$id'] = transaction;
        }
      }
      store.transactions = byId.values.toList();
    }
    store.privateVaultAvailable = vaultLoaded;
    // Older builds seeded sample rows. They were always marked demo and were
    // never real user data, so a normal launch quietly clears them out.
    store.transactions.removeWhere(
      (transaction) => transaction['demo'] == true,
    );
    final savedLore = prefs.getString(_loreKey);
    if (savedLore != null) {
      try {
        store.loreState = Map<String, dynamic>.from(
          jsonDecode(savedLore) as Map,
        );
      } catch (_) {
        store.loreState = const <String, dynamic>{};
      }
    }
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
    'campusFood': _campusFood(),
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
  };

  static List<Map<String, dynamic>> _campusFood() => [
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

  /// Persists the ledger. The encrypted hidden-transaction vault is written
  /// before the visible ledger so a failed secure write leaves both copies
  /// unchanged instead of half-applied.
  Future<void> _persist({bool persistHiddenTransactions = false}) async {
    final visibleTransactions = transactions
        .where((transaction) => transaction['hidden'] != true)
        .toList();
    final hiddenTransactions = persistHiddenTransactions
        ? transactions
              .where((transaction) => transaction['hidden'] == true)
              .toList()
        : null;
    final data = jsonEncode({
      'transactions': visibleTransactions,
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
    });

    Future<void> saveVisible() async {
      await _prefs.setString(_storageKey, data);
    }

    Future<void> saveHiddenSecurely() async {
      if (!persistHiddenTransactions) return;
      if (_usesAndroidSecureStorage) {
        await _privacyChannel.invokeMethod<void>(
          'saveHiddenTransactions',
          jsonEncode(hiddenTransactions),
        );
      } else if (hiddenTransactions!.isNotEmpty) {
        throw UnsupportedError(
          'Hidden transactions require Android secure storage.',
        );
      }
    }

    await saveHiddenSecurely();
    await saveVisible();
  }

  Future<void> _saveAndNotify({bool persistHiddenTransactions = false}) async {
    await _persist(persistHiddenTransactions: persistHiddenTransactions);
    _cachedPriceMemoryEntries = null;
    _cachedMonthTotals = null;
    notifyListeners();
  }

  double get balance => openingBalance + total('income') - total('expense');
  DateTime get today => DateTime.now();
  int get daysRemaining =>
      DateTime(today.year, today.month + 1, 0).day - today.day + 1;

  int get daysUntilPocketMoney =>
      allowanceCycle(today, recurringIncome).daysUntil;

  double get hiddenMonthlyExpenseTotal => _monthTotals.hiddenExpense;
  double get visibleMonthlyIncomeTotal => _monthTotals.visibleIncome;
  double get visibleMonthlyExpenseTotal => _monthTotals.visibleExpense;

  _MonthTotals? _cachedMonthTotals;
  _MonthTotals get _monthTotals => _cachedMonthTotals ??= _buildMonthTotals();

  _MonthTotals _buildMonthTotals() {
    final now = today;
    var visibleIncome = 0.0;
    var visibleExpense = 0.0;
    var hiddenExpense = 0.0;
    for (final transaction in transactions) {
      final date = DateTime.tryParse('${transaction['date']}');
      if (date == null || date.year != now.year || date.month != now.month) {
        continue;
      }
      final amount = _number(transaction['amount']);
      if (transaction['type'] == 'income' && transaction['hidden'] != true) {
        visibleIncome += amount;
      } else if (transaction['type'] == 'expense') {
        if (transaction['hidden'] == true) {
          hiddenExpense += amount;
        } else {
          visibleExpense += amount;
        }
      }
    }
    return _MonthTotals(visibleIncome, visibleExpense, hiddenExpense);
  }

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
      progress: isPayday
          ? 0
          : ((elapsed / (cycleDays - 1)).clamp(0.0, 1.0) as num).toDouble(),
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
      .where(
        (t) =>
            t['hidden'] != true &&
            t['category'] == category &&
            t['type'] == 'expense',
      )
      .fold<double>(0, (sum, t) => sum + _number(t['amount']));

  double get monthlyBudget => budgets.values.fold<double>(0, (a, b) => a + b);
  double get dailyPace =>
      balance > 0 ? balance / daysUntilPocketMoney.clamp(1, 365) : 0;
  List<Map<String, dynamic>> get sortedTransactions =>
      sortTransactions(transactions);

  static List<Map<String, dynamic>> sortTransactions(
    Iterable<Map<String, dynamic>> source,
  ) {
    final list = [...source];
    list.sort((a, b) {
      final dateOrder = '${b['date']}'.compareTo('${a['date']}');
      if (dateOrder != 0) return dateOrder;
      return '${b['created'] ?? b['id']}'.compareTo(
        '${a['created'] ?? a['id']}',
      );
    });
    return list;
  }

  List<PriceMemoryEntry>? _cachedPriceMemoryEntries;
  List<PriceMemoryEntry> get priceMemoryEntries =>
      _cachedPriceMemoryEntries ??= buildPriceMemoryEntries(transactions);

  List<Map<String, dynamic>> get hiddenTransactions => transactions
      .where((transaction) => transaction['hidden'] == true)
      .toList();

  Future<bool> hasPrivacyPin() async {
    if (!_usesAndroidSecureStorage) return false;
    return await _privacyChannel.invokeMethod<bool>('hasPrivacyPin') ?? false;
  }

  Future<void> setPrivacyPin(String pin) async {
    if (!_usesAndroidSecureStorage) {
      throw UnsupportedError('Privacy PINs are available on Android.');
    }
    await _privacyChannel.invokeMethod<void>('setPrivacyPin', {'pin': pin});
  }

  Future<PrivacyPinAttempt> verifyPrivacyPin(String pin) async {
    if (!_usesAndroidSecureStorage) {
      throw UnsupportedError('Privacy PINs are available on Android.');
    }
    final result = await _privacyChannel.invokeMethod<Object?>(
      'verifyPrivacyPin',
      {'pin': pin},
    );
    return PrivacyPinAttempt.fromPlatform(result);
  }

  Future<PrivacyPinAttempt> changePrivacyPin(
    String oldPin,
    String newPin,
  ) async {
    if (!_usesAndroidSecureStorage) {
      throw UnsupportedError('Privacy PINs are available on Android.');
    }
    final result = await _privacyChannel.invokeMethod<Object?>(
      'changePrivacyPin',
      {'oldPin': oldPin, 'newPin': newPin},
    );
    return PrivacyPinAttempt.fromPlatform(result);
  }

  Future<void> setTransactionHidden(String id, bool hidden) async {
    final index = transactions.indexWhere(
      (transaction) => '${transaction['id']}' == id,
    );
    if (index < 0 || (transactions[index]['hidden'] == true) == hidden) return;
    if (!privateVaultAvailable) {
      throw StateError(
        'The encrypted hidden-transaction vault could not be opened. '
        'Restart the app or contact support; protected data was left intact.',
      );
    }
    final transaction = transactions[index];
    if (hidden && !_usesAndroidSecureStorage) {
      throw UnsupportedError(
        'Hidden transactions require Android secure storage.',
      );
    }
    final previousFoodOrders = Map<String, int>.from(foodOrders);
    transaction['hidden'] = hidden;
    final foodItem = transaction['foodItem'];
    if (foodItem != null) {
      final name = '$foodItem';
      final count = (foodOrders[name] ?? 0) + (hidden ? -1 : 1);
      if (count <= 0) {
        foodOrders.remove(name);
      } else {
        foodOrders[name] = count;
      }
    }
    try {
      await _persist(persistHiddenTransactions: true);
    } catch (_) {
      transaction['hidden'] = !hidden;
      foodOrders
        ..clear()
        ..addAll(previousFoodOrders);
      try {
        await _persist(persistHiddenTransactions: true);
      } catch (_) {
        // Keep the original failure; the in-memory transaction is restored.
      }
      rethrow;
    }
    _cachedPriceMemoryEntries = null;
    _cachedMonthTotals = null;
    notifyListeners();
  }

  static List<PriceMemoryEntry> buildPriceMemoryEntries(
    Iterable<Map<String, dynamic>> source,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final labels = <String, (String, String)>{};
    for (final transaction in source) {
      if (transaction['type'] != 'expense' ||
          transaction['hidden'] == true ||
          transaction['demo'] == true ||
          transaction['priceMemoryIgnored'] == true ||
          _number(transaction['amount']) <= 0 ||
          DateTime.tryParse('${transaction['date']}') == null) {
        continue;
      }
      final item =
          '${transaction['priceMemoryItem'] ?? transaction['foodItem'] ?? ''}'
              .trim();
      final place =
          '${transaction['priceMemoryPlace'] ?? transaction['foodShop'] ?? ''}'
              .trim();
      if (item.isEmpty) continue;
      final identity =
          '${_priceMemoryNormalize(item)}|${_priceMemoryNormalize(place)}';
      grouped.putIfAbsent(identity, () => []).add(transaction);
      labels.putIfAbsent(identity, () => (item, place));
    }

    final entries = <PriceMemoryEntry>[];
    for (final group in grouped.entries) {
      group.value.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
      final (item, place) = labels[group.key]!;
      entries.add(
        PriceMemoryEntry(
          item: item,
          place: place,
          category: '${group.value.first['category'] ?? 'Miscellaneous'}',
          transactions: List.unmodifiable(group.value),
        ),
      );
    }
    entries.sort(
      (a, b) => '${b.latest['date']}'.compareTo('${a.latest['date']}'),
    );
    return entries;
  }

  Future<void> renamePriceMemoryEntry(
    Iterable<String> transactionIds, {
    required String item,
    required String place,
  }) async {
    final ids = transactionIds.toSet();
    final cleanItem = item.trim();
    final cleanPlace = place.trim();
    if (cleanItem.isEmpty || cleanItem.length > 80 || cleanPlace.length > 80) {
      return;
    }
    for (final transaction in transactions) {
      if (ids.contains('${transaction['id']}')) {
        transaction['priceMemoryItem'] = cleanItem;
        transaction['priceMemoryPlace'] = cleanPlace;
        transaction['priceMemoryIgnored'] = false;
      }
    }
    await _saveAndNotify();
  }

  Future<void> removePriceMemoryEntry(Iterable<String> transactionIds) async {
    final ids = transactionIds.toSet();
    for (final transaction in transactions) {
      if (ids.contains('${transaction['id']}')) {
        transaction['priceMemoryIgnored'] = true;
      }
    }
    await _saveAndNotify();
  }

  static String _priceMemoryNormalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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
    await _saveAndNotify(persistHiddenTransactions: t['hidden'] == true);
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> value) async {
    final index = transactions.indexWhere((t) => t['id'] == id);
    if (index < 0) return;
    final wasHidden = transactions[index]['hidden'] == true;
    transactions[index] = {...transactions[index], ...value};
    final isHidden = transactions[index]['hidden'] == true;
    await _persist(persistHiddenTransactions: wasHidden || isHidden);
    _cachedPriceMemoryEntries = null;
    _cachedMonthTotals = null;
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    final wasHidden = transactions.any(
      (transaction) =>
          '${transaction['id']}' == id && transaction['hidden'] == true,
    );
    transactions.removeWhere((t) => t['id'] == id);
    await _saveAndNotify(persistHiddenTransactions: wasHidden);
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

  /// Persists the story's small state map separately from the ledger so a
  /// scroll update never re-encodes every transaction.
  Future<void> saveLoreState(Map<String, dynamic> next) async {
    loreState = Map<String, dynamic>.unmodifiable(next);
    await _prefs.setString(_loreKey, jsonEncode(next));
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
    loreState = const <String, dynamic>{};
    await _prefs.remove(_loreKey);
    await _saveAndNotify(persistHiddenTransactions: true);
  }
}
