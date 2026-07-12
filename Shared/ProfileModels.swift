//
//  ProfileModels.swift
//  TeleDeck / TeleDeckMac 共通
//
//  プロファイル・ボタンの構成データ。Macが本体（source of truth）としてこれを保持・永続化し、
//  iPadは`profileSync`/`updateProfiles`メッセージ（Shared/TeleDeckProtocol.swift）を介して同期する。
//  Mac側・iPad側の両プロジェクトに同一内容を配置している。
//

import Foundation

/// ボタンアイコンの種別（SF SymbolsかDocuments配下に保存した画像/GIFか）
enum IconKind: String, Codable {
  case sfSymbol
  case image
}

/// パネル上の1ボタン分の設定
struct ButtonConfig: Codable, Identifiable {
  var id: UUID
  var row: Int
  var col: Int
  var label: String
  var iconName: String
  var action: ActionPayload
  /// 所属するフォルダーボタンのid。nilならプロファイル直下に配置される
  var folderId: UUID?
  /// アイコンの種別。sfSymbolのときはiconNameをSF Symbol名として使う
  var iconKind: IconKind
  /// iconKind == .imageのとき、iPadのDocuments/Icons/配下に保存された画像（GIFを含む）のファイル名。
  /// 画像バイナリ自体はMac・iPad間で同期しない
  var iconImageFileName: String?

  init(
    id: UUID = UUID(),
    row: Int,
    col: Int,
    label: String,
    iconName: String,
    action: ActionPayload,
    folderId: UUID? = nil,
    iconKind: IconKind = .sfSymbol,
    iconImageFileName: String? = nil
  ) {
    self.id = id
    self.row = row
    self.col = col
    self.label = label
    self.iconName = iconName
    self.action = action
    self.folderId = folderId
    self.iconKind = iconKind
    self.iconImageFileName = iconImageFileName
  }

  private enum CodingKeys: String, CodingKey {
    case id, row, col, label, iconName, action, folderId, iconKind, iconImageFileName
  }

  // iconKind/iconImageFileNameは後から追加したフィールドのため、
  // それらを持たない旧バージョンで保存されたJSONでもデコードできるよう、
  // 追加フィールドはdecodeIfPresentでデフォルト値にフォールバックさせる
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    row = try container.decode(Int.self, forKey: .row)
    col = try container.decode(Int.self, forKey: .col)
    label = try container.decode(String.self, forKey: .label)
    iconName = try container.decode(String.self, forKey: .iconName)
    action = try container.decode(ActionPayload.self, forKey: .action)
    folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
    iconKind = try container.decodeIfPresent(IconKind.self, forKey: .iconKind) ?? .sfSymbol
    iconImageFileName = try container.decodeIfPresent(String.self, forKey: .iconImageFileName)
  }
}

/// 1つのプロファイル（ボタン構成のセット）を表す設定
struct ProfileConfig: Codable, Identifiable {
  var id: UUID = UUID()
  var name: String
  /// このBundle IDのアプリがフォアグラウンドになった時に自動切替される。nilならデフォルトプロファイル
  var triggerAppBundleId: String?
  var buttons: [ButtonConfig]
}
