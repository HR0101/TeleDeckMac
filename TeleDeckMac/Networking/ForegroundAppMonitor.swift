//
//  ForegroundAppMonitor.swift
//  TeleDeckMac
//
//  フォアグラウンドアプリの切替をNSWorkspace経由で監視し、iPad側のプロファイル自動切替に使う。
//

import AppKit
import Foundation

final class ForegroundAppMonitor {
  var onForegroundAppChanged: ((String) -> Void)?

  private var observerToken: NSObjectProtocol?

  /// フォアグラウンドアプリ切替の監視を開始する
  func start() {
    guard observerToken == nil else { return }
    observerToken = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleActivation(notification)
    }
  }

  /// 監視を停止し、オブザーバーを解除する
  func stop() {
    guard let observerToken else { return }
    NSWorkspace.shared.notificationCenter.removeObserver(observerToken)
    self.observerToken = nil
  }

  private func handleActivation(_ notification: Notification) {
    guard
      let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      let bundleId = runningApp.bundleIdentifier
    else { return }
    onForegroundAppChanged?(bundleId)
  }
}
