import 'package:flutter/material.dart';

// Source mapping and intentional adaptations: docs/design/SOURCE_MAPPING.md.
abstract final class DesignTokens {
  // DesignSystemTokens.swift / AppSpacing.
  static const pageHorizontal = 32.0;
  static const pageVertical = 28.0;
  static const pageHeaderHorizontal = 4.0;
  static const pageHeaderVertical = 6.0;
  static const headerToControls = 16.0;
  static const cardSpacing = 14.0;

  // DesignSystemTokens.swift / AppRadius.
  static const controlRadius = 12.0;
  static const controlGroupRadius = 16.0;
  static const cardRadius = 16.0;
  static const panelRadius = 22.0;
  static const heroRadius = 24.0;
  static const sheetRadius = 22.0;

  // DesignSystemTokens.swift / AppTypeScale.
  static const largeTitle = 30.0;
  static const sectionTitle = 17.0;
  static const body = 13.0;
  static const callout = 12.0;
  static const caption = 11.0;

  // ContentView.swift / SidebarMetrics.
  static const sidebarMinWidth = 236.0;
  static const sidebarIdealWidth = 252.0;
  static const sidebarMaxWidth = 272.0;
  static const sidebarChildIndent = 22.0;
  static const sidebarRowGap = 11.0;
  static const sidebarRowHorizontal = 10.0;
  static const sidebarRowVertical = 9.0;
  static const sidebarSectionLeading = 10.0;
  static const sidebarItemFont = 13.5;
  static const sidebarPillRadius = 12.0;

  // DesignSystemTokens.swift / AppControlMetrics.
  static const defaultButtonHeight = 38.0;
  static const prominentButtonHeight = 41.0;
  static const searchFieldHeight = 41.0;
  static const disabledControlOpacity = 0.5;

  // AppMotion.swift. Flutter cannot reproduce SwiftUI's response-based spring
  // exactly; these durations retain the original interaction hierarchy.
  static const fastMotion = Duration(milliseconds: 180);
  static const sidebarMotion = Duration(milliseconds: 240);
  static const sidebarSelectionMotion = Duration(milliseconds: 100);
  static const sidebarHoverEnterMotion = Duration(milliseconds: 140);
  static const sidebarHoverExitMotion = Duration(milliseconds: 110);
  static const contentCrossfadeMotion = Duration(milliseconds: 180);

  static const blue = Color(0xFF2E90FA);
  static const cyan = Color(0xFF36BFFA);
  static const pink = Color(0xFFFF5C8A);
  static const orange = Color(0xFFFF9F45);
  static const titleText = Color(0xFF1D1D1F);
  static const secondaryText = Color(0xFF5A6478);
  static const border = Color(0xFFEDF0F5);
}
