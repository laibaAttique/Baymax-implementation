import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/activity_service.dart';
import '../../services/chat_history.dart';
import '../../services/chatbot_engine.dart';
import '../../services/food_database.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../allergy/allergy_scanner.dart';
import '../analytics/analytics_screen.dart';
import '../community/community_screen.dart';
import '../nutrition/calorie_target_screen.dart';
import '../diet/diet_tracker.dart';
import '../nutrition/nutrition_plan_screen.dart';
import '../profile/profile_screen.dart';
import '../specialists/specialists_screen.dart';
import '../profile/sources_screen.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import '../workout_and_exercise/workout_plan.dart';

class _Message {
  final String text;
  final bool fromBot;
  final List<ChatAction> actions;

  final DateTime time = DateTime.now();
  _Message(this.text, {required this.fromBot, this.actions = const []});
}

/// Module 12: AI chatbot UI. Answers come from [ChatbotEngine].
class ChatbotScreen extends StatefulWidget {
  /// Reads the user's own logs (meals, workouts, weigh-ins). Replaceable in tests.
  final Future<ChatHistory> Function()? historyLoader;
  const ChatbotScreen({Key? key, this.historyLoader}) : super(key: key);

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const _engine = ChatbotEngine();

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  FoodDatabase? _db;
  double _consumedToday = 0;
  bool _thinking = false;
  ChatHistory _history = ChatHistory.none;
  Future<void> _historyLoad = Future.value();

  @override
  void initState() {
    super.initState();
    final name = UserSession.instance.profile?.fullName.split(' ').first ?? '';
    _messages.add(_Message(
      'Hi${name.isEmpty ? '' : ' $name'}! I\'m Baymax, your AI health assistant. Ask me about your calories, workouts, meals or allergies.',
      fromBot: true,
    ));
    FoodDatabase.load().then((db) {
      if (mounted) setState(() => _db = db);
    });
    _refreshIntake();
    FoodLogService.instance.changes.addListener(_refreshIntake);
    for (final n in _logChanges) {
      n.addListener(_reloadHistory);
    }
    _reloadHistory();
  }

  /// Anything that changes what the chatbot knows about the user: a meal, a workout, a weigh-in.
  List<Listenable> get _logChanges => [FoodLogService.instance.changes, ActivityService.instance.changes, WeightService.instance.changes];

  void _reloadHistory() {
    _historyLoad = () async {
      final loader = widget.historyLoader ?? () => ChatHistory.load(UserSession.instance.plan);
      ChatHistory h;
      try {
        h = await loader();
      } catch (_) {
        h = ChatHistory.none;
      }
      if (!mounted) return;
      setState(() {
        _history = h;
        // The first message becomes a personal greeting ("Today so far: ...") once the user's data is in.
        if (_messages.length == 1) {
          _messages[0] = _Message(_engine.respond('hello', _context()).text, fromBot: true);
        }
      });
    }();
  }

  ChatContext _context() {
    final session = UserSession.instance;
    return ChatContext(
      profile: session.profile,
      classification: session.classification,
      plan: session.plan,
      db: _db,
      consumedKcal: _consumedToday,
      history: _history,
    );
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_refreshIntake);
    for (final n in _logChanges) {
      n.removeListener(_reloadHistory);
    }
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshIntake() async {
    try {
      final entries = await FoodLogService.instance.forDate(FoodLogService.dateKey(DateTime.now()));
      if (mounted) _consumedToday = FoodLogService.totalKcal(entries);
    } on ApiException {
      // Chat still works without today's intake.
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _thinking) return;
    setState(() {
      _messages.add(_Message(trimmed, fromBot: false));
      _controller.clear();
      _thinking = true;
    });
    _scrollToEnd();
    // The first question can arrive before the user's logs are read; wait briefly so the answer uses them.
    await _historyLoad.timeout(const Duration(seconds: 4), onTimeout: () {});
    if (!mounted) return;
    final ctx = _context();
    final reply = _engine.respond(trimmed, ctx);
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _messages.add(_Message(reply.text, fromBot: true, actions: reply.actions));
    });
    _scrollToEnd();
  }

  void _onAction(ChatAction a) {
    Widget? screen;
    switch (a.type) {
      case 'diet':
        screen = const DietTracker();
      case 'workout':
        screen = const WorkoutPlan();
      case 'nutrition':
        screen = const NutritionPlanScreen();
      case 'scanner':
        screen = const AllergyScanner();
      case 'progress':
        screen = const CommunityScreen();
      case 'analytics':
        screen = const AnalyticsScreen();
      case 'calorie':
        screen = const CalorieTargetScreen();
      case 'profile':
        screen = const ProfileScreen();
      case 'sources':
        screen = const SourcesScreen();
      case 'consult':
        screen = const SpecialistsScreen();
    }
    if (screen != null) Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 12, opacity: 0.3, offset: const Offset(0, 4))),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Baymax AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppTheme.textPrimary)),
            Text('Health assistant', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Voice assistant',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (context, i) => i == _messages.length ? _typing() : _bubble(_messages[i]),
            ),
          ),
          if (_messages.length <= 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in ChatbotEngine.suggestionsFor(_context()))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                        side: BorderSide(color: AppTheme.primary.withOpacity(0.35)),
                        backgroundColor: AppTheme.card,
                        onPressed: () => _send(s),
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything about your health…',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 14, opacity: 0.32, offset: const Offset(0, 5))),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                      tooltip: 'Send',
                      onPressed: () => _send(_controller.text),
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

  Widget _typing() {
    return Semantics(
      label: 'Baymax is typing',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: AppTheme.softShadow(),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(5), bottomRight: Radius.circular(20)),
          ),
          child: const _TypingDots(),
        ),
      ),
    );
  }

  Widget _bubble(_Message m) {
    final bot = m.fromBot;
    return Reveal(
      child: Align(
        alignment: bot ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          constraints: BoxConstraints(maxWidth: math.min(MediaQuery.of(context).size.width * 0.82, 520)),
          child: Column(
            crossAxisAlignment: bot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: bot ? null : AppTheme.buttonGradient,
                  color: bot ? Colors.white.withOpacity(0.82) : null,
                  border: bot ? Border.all(color: Colors.white, width: 1.2) : null,
                  boxShadow: bot ? AppTheme.softShadow() : AppTheme.glowShadow(blur: 14, opacity: 0.22, offset: const Offset(0, 5)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(bot ? 5 : 20),
                    bottomRight: Radius.circular(bot ? 20 : 5),
                  ),
                ),
                child: SelectableText(
                  m.text,
                  style: TextStyle(color: bot ? AppTheme.textPrimary : Colors.white, height: 1.45, fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
              ),
              if (m.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in m.actions)
                        ActionChip(
                          avatar: const Icon(Icons.arrow_outward_rounded, size: 16, color: AppTheme.primary),
                          label: Text(a.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                          side: const BorderSide(color: AppTheme.primary),
                          backgroundColor: AppTheme.background,
                          onPressed: () => _onAction(a),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(_time(m.time), style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots that rise and fall in turn.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
              child: Transform.translate(
                offset: Offset(0, -4 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) - i * 0.9))),
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.textSecondary, shape: BoxShape.circle)),
              ),
            ),
        ],
      ),
    );
  }
}
