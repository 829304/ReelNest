import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appearanceProvider = NotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);

class AppearanceController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setMode(ThemeMode mode) => state = mode;
}
