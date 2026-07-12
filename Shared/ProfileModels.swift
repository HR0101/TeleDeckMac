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
  /// launchAppアクションの対象アプリからMac側で取得した64px PNGアイコン
  var applicationIconPNGData: Data?

  init(
    id: UUID = UUID(),
    row: Int,
    col: Int,
    label: String,
    iconName: String,
    action: ActionPayload,
    folderId: UUID? = nil,
    iconKind: IconKind = .sfSymbol,
    iconImageFileName: String? = nil,
    applicationIconPNGData: Data? = nil
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
    self.applicationIconPNGData = applicationIconPNGData
  }

  private enum CodingKeys: String, CodingKey {
    case id, row, col, label, iconName, action, folderId, iconKind, iconImageFileName, applicationIconPNGData
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
    applicationIconPNGData = try container.decodeIfPresent(Data.self, forKey: .applicationIconPNGData)
  }
}

/// 1つのプロファイル（ボタン構成のセット）を表す設定
struct ProfileConfig: Codable, Identifiable {
  var id: UUID = UUID()
  var name: String
  /// このBundle IDのアプリがフォアグラウンドになった時に自動切替される。nilならデフォルトプロファイル
  var triggerAppBundleId: String?
  var buttons: [ButtonConfig]
  /// パネルグリッドの行数・列数。プロファイルごとに変更できる
  var gridRows: Int = 3
  var gridColumns: Int = 5

  init(
    id: UUID = UUID(),
    name: String,
    triggerAppBundleId: String? = nil,
    buttons: [ButtonConfig],
    gridRows: Int = 3,
    gridColumns: Int = 5
  ) {
    self.id = id
    self.name = name
    self.triggerAppBundleId = triggerAppBundleId
    self.buttons = buttons
    self.gridRows = gridRows
    self.gridColumns = gridColumns
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, triggerAppBundleId, buttons, gridRows, gridColumns
  }

  // gridRows/gridColumnsは後から追加したフィールドのため、
  // それらを持たない旧バージョンで保存されたJSONでもデコードできるよう、
  // decodeIfPresentでデフォルト値（3行5列）にフォールバックさせる
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    triggerAppBundleId = try container.decodeIfPresent(String.self, forKey: .triggerAppBundleId)
    buttons = try container.decode([ButtonConfig].self, forKey: .buttons)
    gridRows = try container.decodeIfPresent(Int.self, forKey: .gridRows) ?? 3
    gridColumns = try container.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 5
  }
}
