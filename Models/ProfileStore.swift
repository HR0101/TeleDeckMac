//
//  ProfileStore.swift
//  TeleDeckMac
//
//  プロファイル・ボタン構成の本体（source of truth）。Application Support配下のJSONへ永続化し、
//  変更のたびにonChangeフックを呼ぶ（BonjourServerがこれを使って接続中のiPadへ`profileSync`を送る）。
//

import Foundation
import Observation
// 並び替えで使うArray.move(fromOffsets:toOffset:)はSwiftUIが提供している
import SwiftUI

@Observable
final class ProfileStore {
  private(set) var profiles: [ProfileConfig]
  private(set) var activeProfileId: UUID

  /// プロファイル一覧または選択中プロファイルが変わるたびに呼ばれる
  var onChange: (([ProfileConfig], UUID) -> Void)?

  /// activeProfileIdに一致するプロファイル。見つからなければ先頭のプロファイルを返す
  var activeProfile: ProfileConfig {
    profiles.first { $0.id == activeProfileId } ?? profiles[0]
  }

  private let fileURL: URL

  init() {
    let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TeleDeckMac", isDirectory: true)
    fileURL = supportURL.appendingPathComponent("profiles.json")

    let loaded = Self.loadFromDisk(at: fileURL)
    let resolvedProfiles = loaded ?? Self.defaultProfiles
    profiles = resolvedProfiles
    activeProfileId = resolvedProfiles[0].id

    if loaded == nil {
      save()
    }
  }

  // MARK: - iPadからの反映依頼・自動切替

  /// iPad側からの編集依頼、またはiPadとの再同期に使う。全面的に置き換えて保存する
  func replaceAll(profiles: [ProfileConfig], activeProfileId: UUID) {
    self.profiles = profiles
    self.activeProfileId = profiles.contains(where: { $0.id == activeProfileId }) ? activeProfileId : profiles[0].id
    save()
    onChange?(self.profiles, self.activeProfileId)
  }

  /// フォアグラウンドアプリのBundle IDに一致するプロファイルへ自動切替する
  func activateProfile(matchingBundleId bundleId: String) {
    let newActiveId: UUID
    if let matched = profiles.first(where: { $0.triggerAppBundleId == bundleId }) {
      newActiveId = matched.id
    } else if let defaultProfile = profiles.first(where: { $0.triggerAppBundleId == nil }) {
      newActiveId = defaultProfile.id
    } else {
      return
    }

    guard newActiveId != activeProfileId else { return }
    activeProfileId = newActiveId
    save()
    onChange?(profiles, activeProfileId)
  }

  // MARK: - Mac側編集ウィンドウからの操作

  func addProfile(_ profile: ProfileConfig) {
    profiles.append(profile)
    notifyChange()
  }

  func updateProfile(_ profile: ProfileConfig) {
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles[index] = profile
    notifyChange()
  }

  func deleteProfile(id: UUID) {
    guard profiles.count > 1 else { return }
    profiles.removeAll { $0.id == id }
    if activeProfileId == id {
      activeProfileId = profiles[0].id
    }
    notifyChange()
  }

  /// プロファイルを丸ごと複製する。ボタンのidも振り直さないと元のプロファイルと
  /// 同じidが複数存在してしまうため、フォルダーの親子関係を保ったまま新しいidへ写し替える。
  /// 複製したプロファイルを返し、呼び出し側が選択状態を移せるようにする
  @discardableResult
  func duplicateProfile(id: UUID) -> ProfileConfig? {
    guard let source = profiles.first(where: { $0.id == id }) else { return nil }

    // 旧id → 新idの対応表を先に作り、folderIdの参照を新しいidへ張り替える
    var idMapping: [UUID: UUID] = [:]
    for button in source.buttons {
      idMapping[button.id] = UUID()
    }

    let copiedButtons = source.buttons.map { button -> ButtonConfig in
      var copy = button
      copy.id = idMapping[button.id] ?? UUID()
      copy.folderId = button.folderId.flatMap { idMapping[$0] }
      return copy
    }

    var duplicated = source
    duplicated.id = UUID()
    duplicated.name = Self.duplicatedName(for: source.name, existing: profiles.map(\.name))
    duplicated.buttons = copiedButtons
    // 自動切替の対象アプリが重複すると、どちらが選ばれるか予測できなくなるため引き継がない
    duplicated.triggerAppBundleId = nil

    let insertIndex = (profiles.firstIndex(where: { $0.id == id }).map { $0 + 1 }) ?? profiles.count
    profiles.insert(duplicated, at: insertIndex)
    notifyChange()
    return duplicated
  }

  /// 「Excel用のコピー」「Excel用のコピー 2」…と、既存の名前と重複しない名前を作る
  private static func duplicatedName(for name: String, existing: [String]) -> String {
    let base = "\(name)のコピー"
    guard existing.contains(base) else { return base }

    var suffix = 2
    while existing.contains("\(base) \(suffix)") {
      suffix += 1
    }
    return "\(base) \(suffix)"
  }

  // MARK: - 書き出し・読み込み

  /// 指定したプロファイルをJSONへ書き出す。別のMacへ設定を持っていく用途を想定しているため、
  /// そのMacに存在しないアプリを指す可能性のあるアイコン画像データは載せない（ファイルサイズも抑えられる）
  func exportData(profileId: UUID) throws -> Data {
    guard let profile = profiles.first(where: { $0.id == profileId }) else {
      throw ProfileTransferError.profileNotFound
    }
    return try Self.encoder.encode(Self.strippingIconData(from: profile))
  }

  /// 全プロファイルをまとめてJSONへ書き出す
  func exportAllData() throws -> Data {
    try Self.encoder.encode(profiles.map(Self.strippingIconData(from:)))
  }

  /// 書き出したJSONを読み込んで追加する。単一プロファイル・複数プロファイルのどちらの形式も受け付ける。
  /// 既存のプロファイルは変更せず、常に新しいidを振って追加する（上書き事故を避けるため）。
  /// 追加した件数を返す
  @discardableResult
  func importProfiles(from data: Data) throws -> Int {
    let decoder = JSONDecoder()

    let imported: [ProfileConfig]
    if let many = try? decoder.decode([ProfileConfig].self, from: data) {
      imported = many
    } else if let one = try? decoder.decode(ProfileConfig.self, from: data) {
      imported = [one]
    } else {
      throw ProfileTransferError.unreadableFile
    }

    guard !imported.isEmpty else { throw ProfileTransferError.unreadableFile }

    for profile in imported {
      var copy = Self.reassigningIds(of: profile)
      copy.name = Self.uniqueName(for: copy.name, existing: profiles.map(\.name))
      // 自動切替の対象アプリが既存と重複すると、どちらが選ばれるか予測できなくなるため引き継がない
      if let triggerId = copy.triggerAppBundleId,
         profiles.contains(where: { $0.triggerAppBundleId == triggerId }) {
        copy.triggerAppBundleId = nil
      }
      profiles.append(copy)
    }

    notifyChange()
    return imported.count
  }

  enum ProfileTransferError: LocalizedError {
    case profileNotFound
    case unreadableFile

    var errorDescription: String? {
      switch self {
      case .profileNotFound:
        return "対象のプロファイルが見つかりませんでした"
      case .unreadableFile:
        return "TeleDeckのプロファイル書き出しファイルとして読み取れませんでした"
      }
    }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    // 書き出したファイルを人が開いて確認・編集できるように整形する
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  /// 別のMacでは意味を持たないアイコンのバイナリを取り除く
  private static func strippingIconData(from profile: ProfileConfig) -> ProfileConfig {
    var copy = profile
    copy.buttons = profile.buttons.map { button in
      var strippedButton = button
      strippedButton.applicationIconPNGData = nil
      return strippedButton
    }
    return copy
  }

  /// プロファイルとボタンのidを新しく振り直す。フォルダーの親子関係は対応表で保つ
  private static func reassigningIds(of profile: ProfileConfig) -> ProfileConfig {
    var idMapping: [UUID: UUID] = [:]
    for button in profile.buttons {
      idMapping[button.id] = UUID()
    }

    var copy = profile
    copy.id = UUID()
    copy.buttons = profile.buttons.map { button in
      var newButton = button
      newButton.id = idMapping[button.id] ?? UUID()
      newButton.folderId = button.folderId.flatMap { idMapping[$0] }
      return newButton
    }
    return copy
  }

  /// 既存の名前と衝突しない名前を作る
  private static func uniqueName(for name: String, existing: [String]) -> String {
    guard existing.contains(name) else { return name }

    var suffix = 2
    while existing.contains("\(name) \(suffix)") {
      suffix += 1
    }
    return "\(name) \(suffix)"
  }

  /// サイドバーのドラッグによる並び替えを反映する
  func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
    profiles.move(fromOffsets: source, toOffset: destination)
    notifyChange()
  }

  /// 削除を取り消せるようにするため、削除前のプロファイル一覧をそのまま書き戻す
  func restoreProfiles(_ snapshot: [ProfileConfig], activeProfileId restoredActiveId: UUID) {
    profiles = snapshot
    activeProfileId = snapshot.contains(where: { $0.id == restoredActiveId }) ? restoredActiveId : snapshot[0].id
    notifyChange()
  }

  /// 指定プロファイルのボタン一覧のみを書き戻す（ボタン削除の取り消しに使う）
  func restoreButtons(_ snapshot: [ButtonConfig], inProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    profiles[profileIndex].buttons = snapshot
    notifyChange()
  }

  func setActiveProfile(id: UUID) {
    guard profiles.contains(where: { $0.id == id }) else { return }
    activeProfileId = id
    notifyChange()
  }

  func addButton(_ button: ButtonConfig, toProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    profiles[profileIndex].buttons.append(button)
    notifyChange()
  }

  func updateButton(_ button: ButtonConfig, inProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    guard let buttonIndex = profiles[profileIndex].buttons.firstIndex(where: { $0.id == button.id }) else { return }
    profiles[profileIndex].buttons[buttonIndex] = button
    notifyChange()
  }

  /// ボタンを削除する。フォルダーボタンの場合、中の子ボタン（さらにその中の孫ボタン…）も
  /// 再帰的に削除しないと、到達手段を失ったまま永久に残り続けてしまうため、まとめて削除する
  func deleteButton(id: UUID, fromProfile profileId: UUID) {
    guard let profileIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
    let idsToDelete = Self.collectIdsToDelete(startingAt: id, in: profiles[profileIndex].buttons)
    profiles[profileIndex].buttons.removeAll { idsToDelete.contains($0.id) }
    notifyChange()
  }

  /// 指定したidと、そのidをfolderIdとして持つ子ボタン・孫ボタン…を再帰的に集める
  private static func collectIdsToDelete(startingAt id: UUID, in buttons: [ButtonConfig]) -> Set<UUID> {
    var idsToDelete: Set<UUID> = [id]
    var frontier: [UUID] = [id]
    while !frontier.isEmpty {
      let children = buttons.filter { button in
        guard let folderId = button.folderId else { return false }
        return frontier.contains(folderId)
      }
      frontier = children.map(\.id)
      idsToDelete.formUnion(frontier)
    }
    return idsToDelete
  }

  private func notifyChange() {
    save()
    onChange?(profiles, activeProfileId)
  }

  // MARK: - 永続化

  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(profiles)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("プロファイルの保存に失敗しました: \(error.localizedDescription)")
    }
  }

  private static func loadFromDisk(at url: URL) -> [ProfileConfig]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode([ProfileConfig].self, from: data)
  }

  private static let defaultButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome")),
    ButtonConfig(row: 0, col: 1, label: "Safari", iconName: "safari", action: ActionPayload(type: .launchApp, target: "Safari")),
    ButtonConfig(row: 0, col: 2, label: "リンクを開く", iconName: "link", action: ActionPayload(type: .openURL, target: "https://example.com")),
    ButtonConfig(row: 0, col: 3, label: "コピー", iconName: "doc.on.doc", action: ActionPayload(type: .hotkey, keys: ["cmd", "c"])),
    ButtonConfig(row: 0, col: 4, label: "ペースト", iconName: "clipboard", action: ActionPayload(type: .hotkey, keys: ["cmd", "v"]))
  ]

  private static let chromeProfileButtons: [ButtonConfig] = [
    ButtonConfig(row: 0, col: 0, label: "新しいタブ", iconName: "plus.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "t"])),
    ButtonConfig(row: 0, col: 1, label: "タブを閉じる", iconName: "xmark.square", action: ActionPayload(type: .hotkey, keys: ["cmd", "w"]))
  ]

  private static let defaultProfiles: [ProfileConfig] = [
    ProfileConfig(name: "デフォルト", triggerAppBundleId: nil, buttons: defaultButtons),
    ProfileConfig(name: "Chrome用", triggerAppBundleId: "com.google.Chrome", buttons: chromeProfileButtons)
  ]
}
