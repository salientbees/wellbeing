enum EntryKind {
  weight('weight-logs', 'Weight'),
  measurements('body-measurements', 'Measurements'),
  food('food-logs', 'Food'),
  hydration('hydration-logs', 'Hydration'),
  activity('activity-logs', 'Activity & steps'),
  exercise('exercise-logs', 'Exercise'),
  sleep('sleep-logs', 'Sleep'),
  mood('mood-logs', 'Mood'),
  goals('goals', 'Goals'),
  habits('habits', 'Habits'),
  habitLogs('habit-logs', 'Habit check-off'),
  checkIn('daily-check-ins', 'Daily check-in'),
  schedules('schedules', 'Schedules'),
  reminders('reminders', 'Reminders'),
  savedFoods('saved-foods', 'Saved foods');

  const EntryKind(this.route, this.label);
  final String route;
  final String label;
  bool get isLog => index <= EntryKind.mood.index || this == habitLogs;
  static EntryKind fromRoute(String route) =>
      values.firstWhere((kind) => kind.route == route);
}

class Entry {
  Entry({
    required this.id,
    required this.kind,
    required this.payload,
    this.revision = 0,
    this.deleted = false,
    this.state = 'synced',
    this.server,
  });
  final String id;
  final EntryKind kind;
  final Map<String, dynamic> payload;
  final int revision;
  final bool deleted;
  final String state;
  final Map<String, dynamic>? server;
  String get date =>
      payload['localDate'] as String? ?? payload['startDate'] as String? ?? '';
  Map<String, dynamic> toJson() => {
    'kind': 'entry',
    'id': id,
    'entityType': kind.route,
    'payload': payload,
    'revision': revision,
    'deleted': deleted,
    'state': state,
    if (server != null) 'server': server,
  };
  factory Entry.fromJson(Map<String, dynamic> data) => Entry(
    id: data['id'] as String,
    kind: EntryKind.fromRoute(data['entityType'] as String),
    payload: Map<String, dynamic>.from(data['payload'] as Map),
    revision: data['revision'] as int? ?? 0,
    deleted: data['deleted'] == true || data['deletedAt'] != null,
    state: data['state'] as String? ?? 'synced',
    server: data['server'] == null
        ? null
        : Map<String, dynamic>.from(data['server'] as Map),
  );
}
