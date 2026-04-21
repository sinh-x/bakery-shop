import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import 'api_client.dart';

class EventService {
  final Dio _dio;

  EventService(this._dio);

  Future<BakeryEvent> createEvent({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
    Map<String, dynamic> data = const {},
    String source = 'app',
  }) async {
    final body = <String, dynamic>{
      'summary': summary,
      'type': type,
      'tags': tags,
      'logged_by': loggedBy,
      'data': data,
      'source': source,
    };
    final response = await _dio.post('/api/events', data: body);
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BakeryEvent>> listEvents({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
    String? loggedBy,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (type != null) params['type'] = type;
    if (tag != null) params['tag'] = tag;
    if (search != null) params['search'] = search;
    if (since != null) params['since'] = since;
    if (until != null) params['until'] = until;
    if (loggedBy != null) params['logged_by'] = loggedBy;

    final response = await _dio.get('/api/events', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => BakeryEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<BakeryEvent> getEvent(int id) async {
    final response = await _dio.get('/api/events/$id');
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BakeryEvent>> getOrderEvents(String orderRef) async {
    final response = await _dio.get('/api/orders/$orderRef/events');
    final list = response.data as List;
    return list
        .map((json) => BakeryEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<BakeryEvent> updateEvent(
    int id, {
    String? summary,
    String? type,
    List<String>? tags,
    String? loggedBy,
  }) async {
    final body = <String, dynamic>{};
    if (summary != null) body['summary'] = summary;
    if (type != null) body['type'] = type;
    if (tags != null) body['tags'] = tags;
    if (loggedBy != null) body['logged_by'] = loggedBy;
    final response = await _dio.patch('/api/events/$id', data: body);
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }
}

final eventServiceProvider = Provider<EventService>((ref) {
  final dio = ref.watch(dioProvider);
  return EventService(dio);
});
