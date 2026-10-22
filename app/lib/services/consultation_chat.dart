import 'package:firebase_database/firebase_database.dart';
import '../models/consultation.dart';
import 'realtime_db.dart';

/// One message of a consultation conversation (`chats/{appointmentId}/{key}`).
class ChatMessage {
  final String id;

  /// True when the signed-in member wrote it.
  final bool mine;
  final String text;
  final DateTime at;
  const ChatMessage({required this.id, required this.mine, required this.text, required this.at});
}

/// Client messages between a member and the specialist of an accepted appointment: the same rules as the specialist portal
/// (`baymax-api/src/lib/chat.js`) and the database rules (`database.rules.json`, `chats`).
class ChatRules {
  ChatRules._();

  static const maxLength = 1000;

  /// A conversation stays open for new messages this long after the slot ends.
  static const grace = Duration(hours: 24);

  /// Only an accepted appointment has a conversation: not a request waiting for an answer, a declined or a cancelled one.
  static bool hasConversation(Appointment a) =>
      a.status == AppointmentStatus.confirmed || a.status == AppointmentStatus.completed || a.status == AppointmentStatus.noShow;

  static bool canSend(Appointment a, DateTime now) => hasConversation(a) && now.isBefore(a.endAt.add(grace));

  /// What to tell the member when they cannot write, or null when they can.
  static String? closedReason(Appointment a, DateTime now) {
    if (a.status == AppointmentStatus.requested) return 'You can message ${a.specialistName} once they accept your request.';
    if (!hasConversation(a)) return 'There is no conversation for this appointment.';
    if (!canSend(a, now)) return 'This conversation is closed. It stays open for 24 hours after the session.';
    return null;
  }

  static final _control = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');

  /// Why [text] cannot be sent, or null: 1 to 1000 characters of plain text.
  static String? problem(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Write a message first.';
    if (t.length > maxLength) return 'A message can be at most $maxLength characters.';
    if (_control.hasMatch(t)) return 'The message has characters that are not allowed.';
    return null;
  }

  /// The stored messages as a clean, ordered list. Anything malformed is dropped. [myId] marks which ones are the member's own.
  static List<ChatMessage> parse(Object? raw, {required String myId}) {
    if (raw is! Map) return const [];
    final out = <ChatMessage>[];
    for (final e in raw.entries) {
      final m = e.value;
      if (m is! Map) continue;
      final text = m['text'];
      final at = m['at'];
      final side = m['side'];
      if (text is! String || text.isEmpty || at is! num || (side != 'patient' && side != 'specialist')) continue;
      out.add(ChatMessage(
        id: e.key.toString(),
        mine: side == 'patient' && m['from'] == myId,
        text: text.length > maxLength ? text.substring(0, maxLength) : text,
        at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      ));
    }
    out.sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return out;
  }
}

/// Reads and writes the conversation in the Realtime Database. The member writes only their own messages; the specialist's arrive
/// from the portal's server.
class ConsultationChat {
  ConsultationChat._();
  static final ConsultationChat instance = ConsultationChat._();

  /// Live messages of one appointment (the newest 200).
  Stream<List<ChatMessage>> watch(String appointmentId) {
    final me = RealtimeDb.uid;
    return RealtimeDb.db.ref('chats/$appointmentId').limitToLast(200).onValue.map((e) => ChatRules.parse(RealtimeDb.plain(e.snapshot.value), myId: me));
  }

  Future<void> send(Appointment a, String text) {
    final problem = ChatRules.problem(text);
    if (problem != null) throw ArgumentError(problem);
    return RealtimeDb.guard(() => RealtimeDb.db.ref('chats/${a.id}').push().set({
          'from': RealtimeDb.uid,
          'side': 'patient',
          'text': text.trim(),
          'at': ServerValue.timestamp,
        }));
  }

  /// Marks the conversation as read by the member, so the specialist can see it was seen. A failure here is not worth showing.
  Future<void> markRead(Appointment a) async {
    try {
      await RealtimeDb.guard(() => RealtimeDb.db.ref('chatRead/${a.id}/${RealtimeDb.uid}').set(ServerValue.timestamp));
    } catch (_) {}
  }
}
