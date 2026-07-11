//
//  PairingManager.swift
//  TeleDeckMac
//
//  PINベースのペアリングとセッショントークン発行を管理する。
//

import Foundation
import Observation

@Observable
final class PairingManager {
  /// Mac側に表示する現在有効なPIN
  private(set) var currentPIN: String = ""

  private var issuedToken: String?

  struct VerificationResult {
    let success: Bool
    let token: String?
    let errorMessage: String?
  }

  init() {
    regeneratePIN()
  }

  /// 新しい6桁PINを生成する（起動時・手動再発行時に呼び出す）
  func regeneratePIN() {
    currentPIN = String(format: "%06d", Int.random(in: 0..<1_000_000))
    issuedToken = nil
  }

  /// iPadから届いたPINを検証し、成功時はセッショントークンを発行する
  func verify(pin: String) -> VerificationResult {
    guard pin == currentPIN else {
      return VerificationResult(success: false, token: nil, errorMessage: "PINが一致しません")
    }
    let token = UUID().uuidString
    issuedToken = token
    return VerificationResult(success: true, token: token, errorMessage: nil)
  }
}
