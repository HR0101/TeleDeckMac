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
  /// フォルダーを開く（iPad内部でのみ使用し、通常Macへは送信されない）
  case openFolder
  /// ブラウザの指定タブをアクティブ化する
  case activateTab
  /// ブラウザの指定タブを閉じる
  case closeTab
  /// Macで起動中のアプリケーションを前面化する
  case activateApplication
  /// ウィンドウをプリセットのレイアウトへ配置する
  case windowLayout
}

/// 実行するアクションの内容
struct ActionPayload: Codable {
  var type: ActionType
  /// launchApp / activateApplication: アプリ名またはBundle ID / openURL: URL文字列
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
  /// activateTab / closeTab: 対象ブラウザ名（"Google Chrome" / "Safari"）
  var browser: String?
  /// activateTab / closeTab: 対象タブのID（TabInfo.tabIdと対応）
  var tabId: Int?
  /// windowLayout: プリセット名（"left-half" / "right-half" / "maximize" / "centered" / "three-split"）
  var preset: String?
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

/// Mac → iPad: 現在のプロファイル一覧の同期。Macがプロファイル設定の本体（source of truth）のため、
/// ペアリング直後・Mac側での編集時・フォアグラウンドアプリ切替による自動切替時に送信される
struct ProfileSyncMessage: Codable {
  var type: String = "profileSync"
  let profiles: [ProfileConfig]
  let activeProfileId: UUID
}

/// iPad → Mac: iPad側で行われた編集をMacへ反映依頼する。Mac側で保存後、
/// 確認のため`profileSync`が送り返される
struct UpdateProfilesMessage: Codable {
  var type: String = "updateProfiles"
  let profiles: [ProfileConfig]
  let activeProfileId: UUID
}

/// iPad → Mac: 開いているタブ一覧の取得要求
struct GetTabsMessage: Codable {
  var type: String = "getTabs"
}

/// iPad → Mac: 起動中のアプリケーション一覧の取得要求
struct GetApplicationsMessage: Codable {
  var type: String = "getApplications"
}

/// Mac上で起動中のユーザー向けアプリケーションの情報
struct MacApplicationInfo: Codable, Identifiable {
  let bundleIdentifier: String
  let name: String
  let active: Bool
  /// Mac側で64pxに縮小したアプリアイコンのPNG。旧エージェントとの互換性のため任意。
  var iconPNGData: Data? = nil

  var id: String { bundleIdentifier }
}

/// Mac → iPad: 起動中のアプリケーション一覧の応答
struct ApplicationsListMessage: Codable {
  var type: String = "applicationsList"
  let applications: [MacApplicationInfo]
}

/// 1つのブラウザタブの情報
struct TabInfo: Codable {
  /// "Google Chrome" / "Safari"
  let browser: String
  /// ウィンドウ番号とタブ番号から合成した識別子（activateTab/closeTabで使用）
  let tabId: Int
  let title: String
  let active: Bool
}

/// Mac → iPad: タブ一覧の応答
struct TabsListMessage: Codable {
  var type: String = "tabsList"
  let tabs: [TabInfo]
  /// 後方互換のため省略可能。新しいMacエージェントはアプリ一覧も同時に返す。
  var applications: [MacApplicationInfo]? = nil
}

/// iPad → Mac: 保存済みトークンでの再ペアリング要求（PIN入力を省略する）。応答は`PairResultMessage`を再利用する
struct ResumeSessionMessage: Codable {
  var type: String = "resumeSession"
  let token: String
}

/// iPad → Mac: トラックパッドのドラッグ移動量（一方向・Ackなし。移動は高頻度に送られるため往復待ちをしない）
struct TrackpadMoveMessage: Codable {
  var type: String = "trackpadMove"
  let dx: Double
  let dy: Double
}

/// iPad → Mac: トラックパッドのクリック（一方向・Ackなし）
struct TrackpadClickMessage: Codable {
  var type: String = "trackpadClick"
  /// "left" / "right"
  let button: String
}

/// iPad → Mac: トラックパッドの2本指スクロール（一方向・Ackなし）
struct TrackpadScrollMessage: Codable {
  var type: String = "trackpadScroll"
  let dx: Double
  let dy: Double
}

/// 受信したJSONの `type` フィールドだけを覗き見るための最小デコード用の型
struct MessageEnvelope: Decodable {
  let type: String
}
