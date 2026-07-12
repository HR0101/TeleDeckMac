//
//  PairingManager.swift
//  TeleDeckMac
//
//  PINベースのペアリングと、信頼済みデバイスのセッショントークンを管理する。
//

import Foundation
import Observation

@Observable
final class PairingManager {
  private static let tokenDefaultsKey = "TeleDeck.issuedToken"
  private static let deviceNameDefaultsKey = "TeleDeck.trustedDeviceName"

  /// Mac側に表示する現在有効なPIN
  private(set) var currentPIN: String = ""

  /// 現在信頼されているデバイス名（未ペアリング時はnil）
  private(set) var trustedDeviceName: String?

  /// Mac再起動をまたいでも信頼関係を維持するため、UserDefaultsへ永続化する
  private var issuedToken: String? {
    didSet {
      UserDefaults.standard.set(issuedToken, forKey: Self.tokenDefaultsKey)
    }
  }

  struct VerificationResult {
    let success: Bool
    let token: String?
    let errorMessage: String?
  }

  init() {
    issuedToken = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey)
    trustedDeviceName = UserDefaults.standard.string(forKey: Self.deviceNameDefaultsKey)
    regeneratePIN()
  }

  /// 新しい6桁PINを生成する（起動時・手動再発行時に呼び出す）
  func regeneratePIN() {
    currentPIN = String(format: "%06d", Int.random(in: 0..<1_000_000))
  }

  /// iPadから届いたPINを検証し、成功時はセッショントークンを発行して信頼済みデバイスとして記録する
  func verify(pin: String, deviceName: String) -> VerificationResult {
    guard pin == currentPIN else {
      return VerificationResult(success: false, token: nil, errorMessage: "PINが一致しません")
    }
    let token = UUID().uuidString
    issuedToken = token
    trustedDeviceName = deviceName
    UserDefaults.standard.set(deviceName, forKey: Self.deviceNameDefaultsKey)
    return VerificationResult(success: true, token: token, errorMessage: nil)
  }

  /// 保存済みトークンでの再接続（PIN入力の省略）を検証する
  func verifyResume(token: String) -> Bool {
    issuedToken != nil && token == issuedToken
  }

  /// 信頼済みデバイスの登録を解除する（メニューバーの「ペアリング解除」から呼ばれる）
  func revokeTrustedDevice() {
    issuedToken = nil
    trustedDeviceName = nil
    UserDefaults.standard.removeObject(forKey: Self.deviceNameDefaultsKey)
    regeneratePIN()
  }
}
