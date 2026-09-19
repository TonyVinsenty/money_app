import 'package:flutter/material.dart';

/// Корневой виджет приложения. Пока это заглушка.
class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money App',
      home: Scaffold(
        appBar: AppBar(title: const Text('Money App')),
        body: const Center(child: Text('Здесь скоро появятся ваши расходы')),
      ),
    );
  }
}
