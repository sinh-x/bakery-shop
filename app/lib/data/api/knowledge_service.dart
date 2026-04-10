import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge_entry.dart';
import 'api_client.dart';

class KnowledgeService {
  final Dio _dio;

  KnowledgeService(this._dio);

  // POST /api/knowledge
  Future<KnowledgeEntry> createEntry({
    required String title,
    String content = '',
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'content': content,
      'type': type,
      'tags': tags,
      'logged_by': loggedBy,
    };
    final response = await _dio.post('/api/knowledge', data: body);
    return KnowledgeEntry.fromJson(response.data as Map<String, dynamic>);
  }

  // GET /api/knowledge?type=&tag=&search=&limit=
  Future<List<KnowledgeEntry>> listEntries({
    String? type,
    String? tag,
    String? search,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (type != null) params['type'] = type;
    if (tag != null) params['tag'] = tag;
    if (search != null) params['search'] = search;

    final response = await _dio.get('/api/knowledge', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => KnowledgeEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // GET /api/knowledge/{id}
  Future<KnowledgeEntry> getEntry(int id) async {
    final response = await _dio.get('/api/knowledge/$id');
    return KnowledgeEntry.fromJson(response.data as Map<String, dynamic>);
  }

  // PATCH /api/knowledge/{id}
  Future<KnowledgeEntry> updateEntry(
    int id, {
    String? title,
    String? content,
    String? type,
    List<String>? tags,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;
    if (type != null) body['type'] = type;
    if (tags != null) body['tags'] = tags;

    final response = await _dio.patch('/api/knowledge/$id', data: body);
    return KnowledgeEntry.fromJson(response.data as Map<String, dynamic>);
  }

  // DELETE /api/knowledge/{id}
  Future<void> deleteEntry(int id) async {
    await _dio.delete('/api/knowledge/$id');
  }

  // POST /api/knowledge/{id}/photos (multipart with file)
  Future<KnowledgePhoto> attachPhoto(
    int id, {
    required String filePath,
    String caption = '',
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final filename = filePath.split('/').last;
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'caption': caption,
    });
    final response = await _dio.post(
      '/api/knowledge/$id/photos',
      data: formData,
    );
    return KnowledgePhoto.fromJson(response.data as Map<String, dynamic>);
  }

  // GET /api/knowledge/{id}/photos
  Future<List<KnowledgePhoto>> listPhotos(int id) async {
    final response = await _dio.get('/api/knowledge/$id/photos');
    final list = response.data as List;
    return list
        .map((json) => KnowledgePhoto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // DELETE /api/knowledge/{id}/photos/{photoHash}
  Future<void> detachPhoto(int id, String photoHash) async {
    await _dio.delete('/api/knowledge/$id/photos/$photoHash');
  }
}

final knowledgeServiceProvider = Provider<KnowledgeService>((ref) {
  final dio = ref.watch(dioProvider);
  return KnowledgeService(dio);
});
