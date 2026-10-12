import 'dart:async';

import 'package:flutter/services.dart';

/// Лёгкая вибрация после успешного сохранения операции, перевода и
/// «Оплачено» (ADR 0013, п. 7). Выключенный тактильный отклик система
/// учитывает сама; сбой канала ни на что не влияет — запись уже сделана.
void savedHaptic() =>
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
