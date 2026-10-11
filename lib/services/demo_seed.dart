import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';

/// Populates a realistic local ledger for visual review, in US terms (USD,
/// US banks and merchants) to match the App Store screenshots. Rows carry a
/// `sample` tag rather than a "(sample)" suffix so they read naturally.
///
/// This is only called when the app is launched with
/// `--dart-define=EXPND_SEED_DEMO=true`; normal and release builds never touch
/// the user's data.
void seedDemoData(AppStore store, SettingsStore settings) {
  // Sample data is additive and seeded once, never a reset of an existing ledger.
  if (store.accounts.any((a) => a.id == 'expnd-demo-checking')) {
    _seedMoneyTools(store);
    return;
  }
  final code = settings.currencyCode;
  if (settings.userName.trim().isEmpty || settings.userName == 'Your Name') {
    settings.userName = 'Travis';
  }
  if (settings.monthlyBudget == 0) settings.monthlyBudget = 3000;
  settings.hasCompletedAccountSetup = true;

  final now = DateTime.now();
  DateTime daysAgo(int days, [int hour = 12]) => DateTime(
    now.year,
    now.month,
    now.day,
    hour,
  ).subtract(Duration(days: days));

  final checking = Account(
    id: 'expnd-demo-checking',
    name: 'Chase Checking',
    type: AccountType.bank,
    currencyCode: code,
    balance: 6400,
  );
  final savings = Account(
    id: 'expnd-demo-savings',
    name: 'Emergency Fund',
    type: AccountType.savings,
    currencyCode: code,
    balance: 11200,
  );
  final cash = Account(
    id: 'expnd-demo-cash',
    name: 'Cash',
    type: AccountType.cash,
    currencyCode: code,
    balance: 320,
  );
  final card = Account(
    id: 'expnd-demo-card',
    name: 'Amex Gold',
    type: AccountType.credit,
    currencyCode: code,
    balance: 1840,
    creditLimit: 15000,
    cardDigits: '4519280734',
  );
  for (final account in [checking, savings, cash, card]) {
    store.addAccount(account);
  }

  void add(
    String note,
    double amount,
    TransactionCategory category,
    TransactionType type,
    int days, {
    Account? account,
  }) {
    store.addTransaction(
      Transaction(
        note: note,
        amount: amount,
        category: category,
        type: type,
        date: daysAgo(days),
        accountId: (account ?? checking).id,
        tags: const ['sample'],
      ),
    );
  }

  add('Salary', 5450, TransactionCategory.salary, TransactionType.income, 7);
  add(
    'Freelance project',
    850,
    TransactionCategory.freelance,
    TransactionType.income,
    18,
  );
  add('Rent', 1200, TransactionCategory.rent, TransactionType.expense, 3);
  add(
    'Whole Foods',
    186.40,
    TransactionCategory.groceries,
    TransactionType.expense,
    0,
  );
  add('Uber', 31.56, TransactionCategory.transport, TransactionType.expense, 0);
  add(
    'Coffee',
    8.75,
    TransactionCategory.food,
    TransactionType.expense,
    1,
    account: cash,
  );
  add(
    'Amazon',
    246.90,
    TransactionCategory.shopping,
    TransactionType.expense,
    2,
    account: card,
  );
  add(
    'Electricity',
    112.30,
    TransactionCategory.utilities,
    TransactionType.expense,
    5,
  );
  add(
    'Cinema',
    42,
    TransactionCategory.entertainment,
    TransactionType.expense,
    6,
    account: card,
  );
  add(
    'Pharmacy',
    64.20,
    TransactionCategory.medical,
    TransactionType.expense,
    9,
  );
  add(
    'Dinner',
    74.50,
    TransactionCategory.food,
    TransactionType.expense,
    12,
    account: card,
  );
  add(
    'Internet',
    59,
    TransactionCategory.utilities,
    TransactionType.expense,
    14,
  );

  final rent = Transaction(
    note: 'Rent',
    amount: 1200,
    category: TransactionCategory.rent,
    type: TransactionType.expense,
    date: daysAgo(27),
    isRecurring: true,
    recurrenceRule: RecurrenceRule.monthly,
    accountId: checking.id,
  )..nextDueDate = now.add(const Duration(days: 4));
  final salary = Transaction(
    note: 'Salary',
    amount: 4200,
    category: TransactionCategory.salary,
    type: TransactionType.income,
    date: daysAgo(20),
    isRecurring: true,
    recurrenceRule: RecurrenceRule.monthly,
    accountId: checking.id,
  )..nextDueDate = now.add(const Duration(days: 11));
  final gym = Transaction(
    note: 'Gym',
    amount: 22,
    category: TransactionCategory.medical,
    type: TransactionType.expense,
    date: daysAgo(6),
    isRecurring: true,
    recurrenceRule: RecurrenceRule.weekly,
    accountId: checking.id,
  )..nextDueDate = now.add(const Duration(days: 1));
  for (final transaction in [rent, salary, gym]) {
    store.addTransaction(transaction);
  }

  for (final entry in {
    TransactionCategory.groceries: 600.0,
    TransactionCategory.food: 400.0,
    TransactionCategory.transport: 250.0,
    TransactionCategory.shopping: 500.0,
  }.entries) {
    if (!store.budgets.any((b) => b.category == entry.key)) {
      store.setBudget(entry.key, entry.value);
    }
  }
  store.addGoal(
    SavingsGoal(
      name: 'Japan trip',
      targetAmount: 6000,
      allocatedAmount: 2350,
      iconName: 'airplane',
      colorHex: '1A56DB',
      accountId: savings.id,
      createdDate: daysAgo(90),
    ),
  );

  // Keep the current-month view useful even during the first days of a month.
  add(
    'Salary',
    5450,
    TransactionCategory.salary,
    TransactionType.income,
    now.day - 1,
  );
  add(
    'Lunch',
    24.50,
    TransactionCategory.food,
    TransactionType.expense,
    0,
  );
  store.addEmi(
    Emi(
      accountId: card.id,
      name: 'Laptop',
      principal: 1800,
      annualRate: 5.9,
      tenureMonths: 12,
      startDate: daysAgo(40),
    ),
  );
  store.addDebt(
    Debt(
      person: 'Jordan',
      amount: 250,
      theyOweMe: true,
      accountId: checking.id,
      date: daysAgo(3),
      dueDate: now.add(const Duration(days: 10)),
      monthlyRepayment: 50,
      note: 'Shared trip costs',
    ),
  );
  store.addPendingCaptures([
    PendingCapture(
      id: 'expnd-demo-capture',
      amount: 12.50,
      note: 'Cafe',
      capturedAt: now,
      source: 'demo',
    ),
  ]);
  _seedMoneyTools(store);
}

/// Sample rows for the money tools (subscriptions, trials, annual bills,
/// refunds and reimbursements). Seeded separately, under its own marker, so a
/// simulator seeded before these tools existed still gets them.
void _seedMoneyTools(AppStore store) {
  if (store.transactions.any((t) => t.id == 'expnd-demo-netflix')) return;
  final checking = store.accountFor('expnd-demo-checking');
  if (checking == null) return;
  final card = store.accounts
      .where((a) => a.type == AccountType.credit)
      .firstOrNull;
  final now = DateTime.now();
  DateTime daysAgo(int days) =>
      DateTime(now.year, now.month, now.day, 12).subtract(Duration(days: days));

  Transaction subscription(
    String id,
    String note,
    double amount,
    RecurrenceRule rule,
    int startedDaysAgo,
    Duration nextDue, {
    DateTime? trialEnds,
    bool tracked = true,
  }) => Transaction(
    id: id,
    note: note,
    amount: amount,
    category: TransactionCategory.subscription,
    type: TransactionType.expense,
    date: daysAgo(startedDaysAgo),
    isRecurring: true,
    recurrenceRule: rule,
    accountId: (card ?? checking).id,
    tags: [if (tracked) 'subscription', 'sample'],
    subscriptionTrialEndDate: trialEnds,
  )..nextDueDate = now.add(nextDue);

  for (final t in [
    subscription(
      'expnd-demo-netflix',
      'Netflix',
      15.49,
      RecurrenceRule.monthly,
      20,
      const Duration(days: 10),
    ),
    subscription(
      'expnd-demo-icloud',
      'iCloud+',
      2.99,
      RecurrenceRule.monthly,
      12,
      const Duration(days: 18),
    ),
    subscription(
      'expnd-demo-duolingo',
      'Duolingo Super',
      12.99,
      RecurrenceRule.monthly,
      3,
      const Duration(days: 4),
      trialEnds: now.add(const Duration(days: 4)),
    ),
    // Yearly bills feed both Subscriptions and the Monthly review.
    subscription(
      'expnd-demo-prime',
      'Amazon Prime',
      139,
      RecurrenceRule.yearly,
      300,
      const Duration(days: 65),
    ),
    subscription(
      'expnd-demo-insurance',
      'Car insurance',
      780,
      RecurrenceRule.yearly,
      200,
      const Duration(days: 165),
      tracked: false,
    ),
  ]) {
    store.addTransaction(t);
  }

  // Three untagged, evenly spaced charges so the manager has a suggestion.
  for (final days in [62, 32, 2]) {
    store.addTransaction(
      Transaction(
        note: 'Spotify',
        amount: 10.99,
        category: TransactionCategory.subscription,
        type: TransactionType.expense,
        date: daysAgo(days),
        accountId: checking.id,
        tags: const ['sample'],
      ),
    );
  }

  // A work trip awaiting reimbursement, partly paid back.
  final hotel = Transaction(
    note: 'Client trip flights',
    amount: 340,
    category: TransactionCategory.transport,
    type: TransactionType.expense,
    date: daysAgo(9),
    accountId: (card ?? checking).id,
    tags: const ['sample'],
  );
  store.addTransaction(hotel);
  store.trackReimbursement(hotel, expected: 340, from: 'Employer');
  store.recordPurchaseReturn(
    hotel,
    amount: 120,
    accountId: hotel.accountId!,
    kind: 'reimbursement',
  );

  // A returned purchase with a partial refund.
  final headphones = Transaction(
    note: 'Headphones',
    amount: 89,
    category: TransactionCategory.shopping,
    type: TransactionType.expense,
    date: daysAgo(15),
    accountId: checking.id,
    tags: const ['sample'],
  );
  store.addTransaction(headphones);
  store.recordPurchaseReturn(
    headphones,
    amount: 45,
    accountId: checking.id,
    kind: 'refund',
  );
}
