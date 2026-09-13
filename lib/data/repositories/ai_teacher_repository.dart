import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/supabase_service.dart';
import '../../core/validation/ai_teacher_validation.dart';
import '../models/ai_conversation.dart';
import '../models/ai_message.dart';

class AiTeacherResponse {
  final String conversationId;
  final AiMessage assistantMessage;

  const AiTeacherResponse({required this.conversationId, required this.assistantMessage});
}

/// Talks only to the `ai-teacher` Edge Function — never to an AI provider
/// directly, and never holds a provider API key or the service-role key.
/// See docs/AI_TEACHER_GUIDE.md.
class AiTeacherRepository {
  Future<AiTeacherResponse> sendMessage({
    required AiTeacherAction action,
    required String message,
    String language = 'en',
    String? conversationId,
    String? paperId,
    String? questionId,
  }) async {
    AiPromptValidator.validate(message);

    try {
      final response = await SupabaseService.client.functions.invoke(
        'ai-teacher',
        body: {
          'action': action.dbValue,
          'message': message,
          'language': language,
          if (conversationId != null) 'conversationId': conversationId,
          if (paperId != null) 'paperId': paperId,
          if (questionId != null) 'questionId': questionId,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw AppException.server();
      }

      final error = data['error'] as String?;
      if (error != null) {
        throw AiTeacherErrorMapper.mapErrorCode(error, data['message'] as String?);
      }

      final newConversationId = data['conversationId'] as String;
      final assistantMessage = AiMessage(
        id: data['messageId'] as String? ?? '',
        conversationId: newConversationId,
        role: AiMessageRole.assistant,
        content: data['content'] as String,
        contentKind: AiContentKindX.fromString(data['contentKind'] as String?),
        createdAt: DateTime.now(),
      );
      return AiTeacherResponse(conversationId: newConversationId, assistantMessage: assistantMessage);
    } on FunctionException catch (e) {
      throw _mapFunctionException(e);
    }
  }

  AppException _mapFunctionException(FunctionException e) {
    final data = e.details;
    if (data is Map && data['error'] != null) {
      return AiTeacherErrorMapper.mapErrorCode(data['error'] as String, data['message'] as String?);
    }
    return AiTeacherErrorMapper.mapHttpStatus(e.status);
  }

  Future<List<AiConversation>> getConversations() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw AppException.sessionExpired();
    final rows = await SupabaseService.client
        .from('ai_conversations')
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return rows.map((r) => AiConversation.fromJson(r)).toList();
  }

  Future<List<AiMessage>> getMessages(String conversationId) async {
    final rows = await SupabaseService.client
        .from('ai_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.map((r) => AiMessage.fromJson(r)).toList();
  }

  Future<void> deleteConversation(String conversationId) async {
    await SupabaseService.client.from('ai_conversations').delete().eq('id', conversationId);
  }
}
