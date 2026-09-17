import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'app_config.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.code);
  final String code;
  @override
  String toString() => code.replaceAll('_', ' ').toLowerCase();
}

class ApiClient {
  ApiClient(this.auth, {Dio? transport})
    : _dio =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.endpoint,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              contentType: 'application/json',
            ),
          );
  final FirebaseAuth auth;
  final Dio _dio;
  Future<String?>? _refresh;
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
  }) async {
    final user = auth.currentUser;
    if (user == null) throw const ApiFailure('AUTH_REQUIRED');
    final uid = user.uid;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await user.getIdToken();
      final check = AppConfig.emulators
          ? null
          : await FirebaseAppCheck.instance.getToken();
      if (auth.currentUser?.uid != uid) {
        throw const ApiFailure('ACCOUNT_CHANGED');
      }
      try {
        final response = await _dio.request<Map<String, dynamic>>(
          path,
          data: data,
          options: Options(
            method: method,
            headers: {
              'Authorization': 'Bearer $token',
              'X-Firebase-AppCheck': ?check,
            },
          ),
        );
        if (auth.currentUser?.uid != uid) {
          throw const ApiFailure('ACCOUNT_CHANGED');
        }
        return Map<String, dynamic>.from(response.data!['data'] as Map);
      } on DioException catch (error) {
        if (error.response?.statusCode == 401 && attempt == 0) {
          _refresh ??= user.getIdToken(true);
          try {
            await _refresh;
          } finally {
            _refresh = null;
          }
          continue;
        }
        final body = error.response?.data;
        throw ApiFailure(
          body is Map && body['error'] is Map
              ? body['error']['code'] as String
              : 'OFFLINE',
        );
      }
    }
    throw const ApiFailure('AUTH_REQUIRED');
  }

  void close() => _dio.close(force: true);
}
