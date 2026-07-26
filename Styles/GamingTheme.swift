//
//  GamingTheme.swift
//  TeleDeckMac
//
//  iPad版（TeleDeck/Styles/GamingTheme.swift）と世界観を揃えるための、
//  紫ベースのゲーミングデバイス風ビジュアル（ダーク背景・グロー・グラスカード）。
//  Mac側はテーマ選択機能を持たないため、アクセントカラーは紫で固定する。
//

import SwiftUI

/// アプリ全体で固定のダークトーンとアクセントカラー
enum GamingPalette {
  static let background = Color(hex: 0x0F0F23)
  static let backgroundElevated = Color(hex: 0x1A1830)
  static let card = Color(hex: 0x1E1C35)
  static let muted = Color(hex: 0x27273B)
  static let foreground = Color(hex: 0xE2E8F0)
  static let mutedForeground = Color(hex: 0x94A3B8)
  static let destructive = Color(hex: 0xEF4444)
  static let success = Color(hex: 0x22C55E)
  /// iPad側の既定アクセント（AccentColorOption.purple）と同じ紫
  static let accent = Color(hex: 0x7C3AED)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

/// 画面全体に敷く、紫を基調にしたダークグラデーション背景。
/// 中央付近にアクセントカラーのグロー（ぼかし光）を淡く配置し、単調な単色背景にならないようにする。
/// モーション低減設定が有効な場合はグローのアニメーションを止める。
struct GamingBackground: View {
  var accentColor: Color = GamingPalette.accent
  /// falseにするとグローを静止させる。小さく情報密度の高いメニューバーのポップオーバーなどでは、
  /// 常時動き続ける背景が「ウインドウ自体が動いている」ように見えて操作の邪魔になるため
  var animated: Bool = true

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animate = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [GamingPalette.background, GamingPalette.backgroundElevated],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(accentColor.opacity(0.24))
        .frame(width: 420, height: 420)
        .blur(radius: 120)
        .offset(x: animate ? -80 : -140, y: animate ? -220 : -180)

      Circle()
        .fill(accentColor.opacity(0.16))
        .frame(width: 360, height: 360)
        .blur(radius: 120)
        .offset(x: animate ? 140 : 100, y: animate ? 260 : 300)
    }
    .ignoresSafeArea()
    .onAppear {
      guard animated, !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
        animate = true
      }
    }
  }
}

/// カード状の面（ボタン・行など）に共通のガラス風グロー装飾を与えるモディファイア
private struct GamingCardModifier: ViewModifier {
  var accentColor: Color
  var cornerRadius: CGFloat
  var isEmphasized: Bool

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(.ultraThinMaterial)
      )
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(GamingPalette.card.opacity(0.55))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(accentColor.opacity(isEmphasized ? 0.9 : 0.4), lineWidth: isEmphasized ? 1.5 : 1)
      )
      .shadow(color: accentColor.opacity(isEmphasized ? 0.4 : 0.18), radius: isEmphasized ? 14 : 8)
  }
}

extension View {
  /// ゲーミングデバイス風のガラスカード装飾を適用する
  func gamingCard(accentColor: Color = GamingPalette.accent, cornerRadius: CGFloat = 14, isEmphasized: Bool = false) -> some View {
    modifier(GamingCardModifier(accentColor: accentColor, cornerRadius: cornerRadius, isEmphasized: isEmphasized))
  }

  /// TextFieldなどの入力欄を、ダークテーマに馴染むガラス面に載せる
  func gamingField(cornerRadius: CGFloat = 10) -> some View {
    self
      .textFieldStyle(.plain)
      .foregroundStyle(GamingPalette.foreground)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(GamingPalette.muted.opacity(0.6))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(GamingPalette.accent.opacity(0.3), lineWidth: 1)
      )
  }
}

/// ボタン全般に使う、押下時にグローが強まるゲーミング風ButtonStyle
struct GamingButtonStyle: ButtonStyle {
  var accentColor: Color = GamingPalette.accent
  var cornerRadius: CGFloat = 12
  /// trueにするとアクセントカラーで塗りつぶした主要ボタンになる
  var isProminent: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isProminent ? Color.white : GamingPalette.foreground)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(fillColor(isPressed: configuration.isPressed))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(accentColor.opacity(configuration.isPressed ? 0.95 : (isProminent ? 0.0 : 0.5)), lineWidth: 1.2)
      )
      .shadow(color: accentColor.opacity(configuration.isPressed ? 0.55 : (isProminent ? 0.4 : 0.22)), radius: configuration.isPressed ? 12 : 6)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }

  private func fillColor(isPressed: Bool) -> Color {
    if isProminent {
      return accentColor.opacity(isPressed ? 0.8 : 1)
    }
    return isPressed ? accentColor.opacity(0.35) : GamingPalette.muted.opacity(0.9)
  }
}
