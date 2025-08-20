import 'package:flutter/foundation.dart';

class FirestoreDebugHelper {
  static void logQuery(String queryDescription, Map<String, dynamic> params) {
    if (kDebugMode) {
      print('🔍 Firestore Query: $queryDescription');
      print('   Parameters: $params');
      print('   Time: ${DateTime.now().toIso8601String()}');
    }
  }

  static void logQueryResult(
    String queryDescription,
    int resultCount, {
    String? error,
  }) {
    if (kDebugMode) {
      if (error != null) {
        print('❌ Query Failed: $queryDescription');
        print('   Error: $error');
      } else {
        print('✅ Query Success: $queryDescription');
        print('   Results: $resultCount items');
      }
      print('   Time: ${DateTime.now().toIso8601String()}');
      print('---');
    }
  }

  static void logIndexRequirement(
    String collection,
    List<String> fields,
    String operation,
  ) {
    if (kDebugMode) {
      print('🔧 Index Required:');
      print('   Collection: $collection');
      print('   Fields: ${fields.join(', ')}');
      print('   Operation: $operation');
      print(
        '   Create at: https://console.firebase.google.com/project/smart-agri-15432/firestore/indexes',
      );
      print('---');
    }
  }
}
