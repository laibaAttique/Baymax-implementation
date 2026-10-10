import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/chatbot_engine.dart';
import '../../services/food_database.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../allergy/allergy_scanner.dart';
import '../diet/diet_tracker.dart';
import '../nutrition/nutrition_plan_screen.dart';
import '../profile/profile_screen.dart';
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
  const ChatbotScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    final name = UserSession.instance.profile?.fullName.split(' ').first ?? '';
    _messages.add(_Message(
      'Hi${name.isEmpty ? '' : ' $name'}! 👋 I\'m Baymax, your AI health assistant. Ask me about your calories, workouts, meals or allergies.',
      fromBot: true,
    ));
    FoodDatabase.load().then((db) {
      if (mounted) setState(() => _db = db);
    });
    _refreshIntake();
    FoodLogService.instance.changes.addListener(_refreshIntake);
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_refreshIntake);
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

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final session = UserSession.instance;
    final reply = _engine.respond(
      trimmed,
      ChatContext(
        profile: session.profile,
        classification: session.classification,
        plan: session.plan,
        db: _db,
        consumedKcal: _consumedToday,
      ),
    );
    setState(() {
      _messages.add(_Message(trimmed, fromBot: false));
      _messages.add(_Message(reply.text, fromBot: true, actions: reply.actions));
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
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
      case 'profile':
        screen = const ProfileScreen();
      case 'sources':
        screen = const SourcesScreen();
      case 'consult':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Online consultations are coming in a later update. Please contact your doctor directly for now.')),
        );
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
        title: const Text('Baymax AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice assistant',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _bubble(_messages[i]),
            ),
          ),
          if (_messages.length <= 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in ChatbotEngine.suggestions)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => _send(s)),
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(hintText: 'Ask me anything about your health…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
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

  Widget _bubble(_Message m) {
    final bot = m.fromBot;
    return Align(
      alignment: bot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: bot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bot ? AppTheme.card : AppTheme.primary,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(bot ? 4 : 18),
                  bottomRight: Radius.circular(bot ? 18 : 4),
                ),
              ),
              child: SelectableText(
                m.text,
                style: TextStyle(color: bot ? AppTheme.textPrimary : Colors.white, height: 1.4),
              ),
            ),
            if (m.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in m.actions)
                      ActionChip(
                        label: Text(a.label, style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
                        side: const BorderSide(color: AppTheme.primary),
                        backgroundColor: AppTheme.background,
                        onPressed: () => _onAction(a),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_time(m.time), style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
