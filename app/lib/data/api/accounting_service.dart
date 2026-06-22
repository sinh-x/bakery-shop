import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/journal_entry.dart';
import 'api_client.dart';

class AccountingService {
  final Dio _dio;

  AccountingService(this._dio);

  Future<List<Account>> listAccounts() async {
    final response = await _dio.get('/api/accounts');
    final list = response.data as List;
    return list
        .map((json) => Account.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<JournalListResponse> listJournal({
    String? since,
    String? until,
    int? accountId,
    String? sourceType,
    int? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{};
    if (since != null && since.isNotEmpty) query['since'] = since;
    if (until != null && until.isNotEmpty) query['until'] = until;
    if (accountId != null) query['account_id'] = accountId;
    if (sourceType != null && sourceType.isNotEmpty) {
      query['source_type'] = sourceType;
    }
    if (sourceId != null) query['source_id'] = sourceId;
    query['limit'] = limit;
    query['offset'] = offset;
    final response = await _dio.get(
      '/api/accounts/journal',
      queryParameters: query,
    );
    return JournalListResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<AccountBalance>> getBalances() async {
    final response = await _dio.get('/api/accounts/balances');
    final list = response.data as List;
    return list
        .map((json) => AccountBalance.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<int> lockJournal({
    required String since,
    required String until,
    String lockedBy = '',
  }) async {
    final response = await _dio.post(
      '/api/accounts/journal/lock',
      data: {'since': since, 'until': until, 'lockedBy': lockedBy},
    );
    final data = response.data as Map<String, dynamic>;
    return (data['lockedCount'] as num?)?.toInt() ?? 0;
  }

  Future<JournalEntry> ownerCapital({
    required double amount,
    String method = 'cash',
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/accounts/owner-capital',
      data: {'amount': amount, 'method': method, 'note': note},
    );
    return JournalEntry.fromJson(response.data as Map<String, dynamic>);
  }

  Future<JournalEntry> ownerDraw({
    required double amount,
    String method = 'cash',
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/accounts/owner-draw',
      data: {'amount': amount, 'method': method, 'note': note},
    );
    return JournalEntry.fromJson(response.data as Map<String, dynamic>);
  }

  Future<JournalEntry> staffReimburse({
    required String staffName,
    required double amount,
    String method = 'cash',
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/accounts/staff-reimburse',
      data: {
        'staffName': staffName,
        'amount': amount,
        'method': method,
        'note': note,
      },
    );
    return JournalEntry.fromJson(response.data as Map<String, dynamic>);
  }
}

final accountingServiceProvider = Provider<AccountingService>((ref) {
  final dio = ref.watch(dioProvider);
  return AccountingService(dio);
});