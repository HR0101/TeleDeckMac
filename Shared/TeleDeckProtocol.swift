//
//  TeleDeckProtocol.swift
//  TeleDeck / TeleDeckMac 共通
//
//  iPadとMac間で送受信するメッセージのプロトコル定義。
//  設計書8章のフォーマットに準拠し、Mac側・iPad側の両プロジェクトに同一内容を配置している。
//

import Foundation

// MARK: - アクション定義

/// アクションの種別
enum ActionType: String, Codable {
  case launchApp
  case openURL
  case hotkey
  case typeText
  case setVolume
  case multiAction
  case delay
}

/// 実行するアクションの内容
struct ActionPayload: Codable {
  var type: ActionType
  /// launchApp: アプリ名またはBundle ID / openURL: URL文字列
  var target: String?
  /// hotkey: 送信するキーの組み合わせ（例: ["cmd", "c"]）
  var keys: [String]?
  /// typeText: 入力する定型文
  var text: String?
  /// setVolume: 設定する音量（0〜100）
  var volume: Int?
  /// delay: 待機時間（ミリ秒）
  var ms: Int?
  /// multiAction: 順番に実行する子アクション列
  var steps: [ActionPayload]?
}

// MARK: - メッセージ定義（設計書8章準拠）

/// iPad → Mac: アクション実行要求
struct ExecuteMessage: Codable {
  var type: String = "execute"
  let requestId: String
  let action: ActionPayload
}

/// Mac → iPad: 実行結果の応答
struct AckMessage: Codable {
  var type: String = "ack"
  let requestId: String
  let success: Bool
  var errorMessage: String?
}

/// iPad → Mac: ペアリング要求（PINコードを提示）
struct PairMessage: Codable {
  var type: String = "pair"
  let deviceName: String
  let pin: String
}

/// Mac → iPad: ペアリング結果（成功時はセッショントークンを発行）
struct PairResultMessage: Codable {
  var type: String = "pairResult"
  let success: Bool
  var token: String?
  var errorMessage: String?
}

/// 受信したJSONの `type` フィールドだけを覗き見るための最小デコード用の型
struct MessageEnvelope: Decodable {
  let type: String
}
