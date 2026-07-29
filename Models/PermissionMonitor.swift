//
//  PermissionMonitor.swift
//  TeleDeckMac
//
//  アクセシビリティ権限の許可状態を監視し、UI表示とアクション実行の双方から参照できるようにする。
//  CGEventによるキー送信・ウィンドウ操作は、権限が無くてもエラーを返さないまま何も起こらないため
//  （＝iPad側には「成功」と表示されてしまうため）、実行前の判定とメニューバーでの状態表示の
//  両方でこの型を経由させる。
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class PermissionMonitor {

  /// アクセシビリティ権限が許可されているか
  private(set) var isAccessibilityTrusted: Bool

  /// 未許可の間は、ユーザーがシステム設定で許可した瞬間をすぐ反映したいため短い間隔で確認する
  private static let untrustedPollInterval: TimeInterval = 2
  /// 許可済みの間は、後から取り消された場合に気づくことが目的のため長い間隔で十分
  private static let trustedPollInterval: TimeInterval = 10

  private var pollingTimer: Timer?
  private var activationObserver: NSObjectProtocol?

  init() {
    isAccessibilityTrusted = Self.checkAccessibilityTrusted()
    startMonitoring()
  }

  deinit {
    stopMonitoring()
  }

  // MARK: - 状態の取得

  /// 権限リクエストのダイアログを出さずに、現在の許可状態だけを取得する。
  /// アクション実行時は状態がキャッシュで古くならないよう、この静的メソッドを直接使う
  static func checkAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  /// 許可状態を今すぐ読み直す。変化していた場合は監視間隔も切り替える
  func refresh() {
    let trusted = Self.checkAccessibilityTrusted()
    guard trusted != isAccessibilityTrusted else { return }
    isAccessibilityTrusted = trusted
    scheduleTimer()
  }

  // MARK: - 権限のリクエスト

  /// macOS標準の権限リクエストダイアログを表示する。
  /// 一度拒否された後はmacOSがこのダイアログを出さなくなるため、
  /// 呼び出し側では必ず`openAccessibilitySettings()`への導線も併せて用意する
  func requestAccess() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を直接開く
  static func openAccessibilitySettings() {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ) else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - 監視

  private func startMonitoring() {
    scheduleTimer()

    // ユーザーがシステム設定で許可を与えてMacの操作へ戻ってきた瞬間に、
    // ポーリングの間隔を待たずに反映する
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refresh()
    }
  }

  private func stopMonitoring() {
    pollingTimer?.invalidate()
    pollingTimer = nil

    if let activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
      self.activationObserver = nil
    }
  }

  /// 現在の許可状態に応じた間隔でポーリングタイマーを張り直す。
  /// アクセシビリティ権限の変化を通知する公開APIが無いため、確認は定期的なポーリングで行う
  private func scheduleTimer() {
    pollingTimer?.invalidate()

    let interval = isAccessibilityTrusted ? Self.trustedPollInterval : Self.untrustedPollInterval
    pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.refresh()
    }
  }
}
