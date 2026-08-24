import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/app.dart';
import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/core/storage/local_storage.dart';
import 'package:photo_application/core/supabase/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 는 없을 수도 있습니다 (백엔드를 안 쓰는 빌드). 이때도 앱은 떠야
  // 하므로 실패를 삼키고 빈 환경으로 초기화합니다.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    dotenv.testLoad(fileInput: '');
  }

  // 자격증명이 없으면 내부에서 알아서 건너뜁니다.
  try {
    await SupabaseService.initialize();
  } catch (error, stack) {
    debugPrint('Supabase 초기화 실패: $error\n$stack');
  }

  final localStorage = await LocalStorage.getInstance();
  final database = await AppDatabase.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const PhotoApp(),
    ),
  );
}
