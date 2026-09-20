import 'package:flutter/material.dart';

/// Заголовок экрана управления категориями.
const categoriesScreenTitle = 'Категории';

/// Пока в экране только заглушка: списки, архив и правка — шаги 2.32–2.34.
const categoriesScreenPlaceholder = 'Управление категориями — в разработке';

/// Экран «Категории» (открывается из «Настроек» по именованному маршруту).
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(categoriesScreenTitle)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(categoriesScreenPlaceholder, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
