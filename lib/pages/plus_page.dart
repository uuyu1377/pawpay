import 'package:flutter/material.dart';

class PlusPage extends StatelessWidget {
  const PlusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新增記帳')),
      body: const Center(
        child: Text(
          'Plus 頁面 (記帳)',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}