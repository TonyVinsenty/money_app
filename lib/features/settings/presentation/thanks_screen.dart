import 'package:flutter/material.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/core/ui/zuno_mark.dart';
import 'package:money_app/features/settings/domain/thanks.dart';
import 'package:money_app/features/settings/presentation/group_header.dart';

/// Тексты экрана «Спасибо» (решения пользователя 2026-10-14). Слов о деньгах
/// и об оплате нет.
const thanksTitle = 'Спасибо';
const thanksIntro = 'Эти люди помогают Zuno становиться лучше';
const thanksEmptyText = 'Здесь будут имена тех, кто помогает Zuno';

/// Подзаголовки уровней — латиницей, как на Boosty (решение пользователя).
const thanksTier3Title = 'Tier 3';
const thanksTier2Title = 'Tier 2';
const thanksTier1Title = 'Tier 1';

/// Разделитель имён в абзаце Tier 2 и Tier 1; скринридер его не читает.
const thanksNameSeparator = ' · ';

/// Экран «Спасибо» (шаг 8.32): имена тех, кто помогает Zuno, от старшего
/// уровня к младшему. Tier 3 — карточка, имя на строку; Tier 2 и Tier 1 —
/// абзацем через « · ». Пустой уровень скрыт вместе с подзаголовком; если
/// пусты все — по центру мягкая надпись-заглушка.
class ThanksScreen extends StatefulWidget {
  const ThanksScreen({required this.load, super.key});

  /// Читает список имён (в приложении — из `assets/thanks.json`).
  final Future<Thanks> Function() load;

  @override
  State<ThanksScreen> createState() => _ThanksScreenState();
}

class _ThanksScreenState extends State<ThanksScreen> {
  late final Future<Thanks> _thanks = widget.load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(thanksTitle)),
      body: FutureBuilder<Thanks>(
        future: _thanks,
        builder: (context, snapshot) {
          // Файл в ресурсах читается мгновенно: пока ждём — пустой экран,
          // без индикатора, чтобы он не мелькал.
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final thanks = snapshot.data ?? Thanks.empty;
          return thanks.isEmpty ? const _EmptyThanks() : _ThanksList(thanks);
        },
      ),
    );
  }
}

/// Знак Zuno и фраза под ним — вверху списка и в заглушке.
class _MarkWithText extends StatelessWidget {
  const _MarkWithText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const ZunoMark(),
        const SizedBox(height: AppSpacing.m),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyThanks extends StatelessWidget {
  const _EmptyThanks();

  @override
  Widget build(BuildContext context) {
    // По центру экрана, а при крупном шрифте на низком экране — прокрутка.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: _MarkWithText(thanksEmptyText),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThanksList extends StatelessWidget {
  const _ThanksList(this.thanks);

  final Thanks thanks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.xl,
            AppSpacing.l,
            0,
          ),
          child: _MarkWithText(thanksIntro),
        ),
        if (thanks.tier3.isNotEmpty) ...[
          const GroupHeader(thanksTier3Title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, name) in thanks.tier3.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.s),
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (thanks.tier2.isNotEmpty) ...[
          const GroupHeader(thanksTier2Title),
          _NamesParagraph(thanks.tier2),
        ],
        if (thanks.tier1.isNotEmpty) ...[
          const GroupHeader(thanksTier1Title),
          _NamesParagraph(thanks.tier1),
        ],
      ],
    );
  }
}

/// Имена абзацем через « · »: каждое имя — свой узел для скринридера,
/// точки только для глаз.
class _NamesParagraph extends StatelessWidget {
  const _NamesParagraph(this.names);

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Wrap(
        children: [
          for (final (index, name) in names.indexed) ...[
            if (index > 0)
              ExcludeSemantics(child: Text(thanksNameSeparator, style: style)),
            Text(name, style: style),
          ],
        ],
      ),
    );
  }
}
