import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/supabase/supabase_service.dart';
import 'package:photo_application/features/auth/providers/auth_providers.dart';

/// 로그인 / 가입 화면.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUpMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 모두 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      if (_signUpMode) {
        await auth.signUp(email: email, password: password);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가입 확인 메일을 보냈습니다. 메일함을 확인하세요.')),
        );
      } else {
        await auth.signIn(email: email, password: password);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('동기화')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              '백엔드가 설정되어 있지 않습니다.\n\n'
              '이 앱은 백엔드 없이도 완전히 동작합니다. 메모·태그·폴더를 '
              '여러 기기에서 함께 쓰고 싶을 때만 Supabase 설정이 필요합니다.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_signUpMode ? '가입' : '로그인')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '메모·태그·폴더를 다른 기기와 맞추려면 로그인하세요.\n'
            '사진 원본은 서버로 올라가지 않습니다.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '이메일'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_signUpMode ? '가입하기' : '로그인'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _signUpMode = !_signUpMode;
                      _error = null;
                    }),
            child: Text(_signUpMode ? '이미 계정이 있어요' : '계정 만들기'),
          ),
        ],
      ),
    );
  }
}
