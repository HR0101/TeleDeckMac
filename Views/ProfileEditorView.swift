//
//  ProfileEditorView.swift
//  TeleDeckMac
//
//  プロファイル・ボタン設定を編集するウィンドウ。Macが本体（source of truth）として
//  プロファイル一覧・トリガーアプリ・ボタングリッドを直接編集できるようにする。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
  let profileStore: ProfileStore

  /// サイドバーで選択中のプロファイル（表示専用の選択状態。setActiveProfileとは独立している）
  @State private var selectedProfileId: UUID?
  @State private var profileIdPendingDeletion: UUID?

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      if let profile = selectedProfile {
        ProfileDetailView(profileStore: profileStore, profileId: profile.id)
          .id(profile.id)
      } else {
        ContentUnavailableView("プロファイルを選択してください", systemImage: "square.grid.3x2")
      }
    }
    .frame(minWidth: 820, minHeight: 560)
    .onAppear {
      if selectedProfileId == nil {
        selectedProfileId = profileStore.profiles.first?.id
      }
    }
    // プロファイルが削除された場合など、選択中idが一覧から消えたら先頭を選び直す
    .onChange(of: profileStore.profiles.map(\.id)) { _, ids in
      if let current = selectedProfileId, !ids.contains(current) {
        selectedProfileId = ids.first
      }
    }
    .confirmationDialog(
      "このプロファイルを削除しますか？",
      isPresented: Binding(
        get: { profileIdPendingDeletion != nil },
        set: { if !$0 { profileIdPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("削除", role: .destructive) {
        if let id = profileIdPendingDeletion {
          profileStore.deleteProfile(id: id)
        }
        profileIdPendingDeletion = nil
      }
      Button("キャンセル", role: .cancel) {
        profileIdPendingDeletion = nil
      }
    } message: {
      Text("ボタン設定も含めて削除されます。この操作は取り消せません。")
    }
  }

  private var selectedProfile: ProfileConfig? {
    guard let id = selectedProfileId else { return nil }
    return profileStore.profiles.first(where: { $0.id == id })
  }

  private var sidebar: some View {
    List(selection: $selectedProfileId) {
      ForEach(profileStore.profiles) { profile in
        VStack(alignment: .leading, spacing: 2) {
          Text(profile.name)
          if let bundleId = profile.triggerAppBundleId {
            Text(bundleId)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .tag(profile.id)
        .contextMenu {
          Button("削除", role: .destructive) {
            profileIdPendingDeletion = profile.id
          }
        }
      }
    }
    .navigationTitle("プロファイル")
    .toolbar {
      ToolbarItem {
        Button {
          addProfile()
        } label: {
          Label("新規プロファイル", systemImage: "plus")
        }
      }
    }
  }

  private func addProfile() {
    let newProfile = ProfileConfig(name: "新規プロファイル", triggerAppBundleId: nil, buttons: [])
    profileStore.addProfile(newProfile)
    selectedProfileId = newProfile.id
  }
}

// MARK: - 選択中プロファイルの詳細（名前・トリガーアプリ・ボタングリッド編集）

private struct ProfileDetailView: View {
  let profileStore: ProfileStore
  let profileId: UUID

  @State private var nameDraft: String = ""
  @FocusState private var isNameFieldFocused: Bool

  /// 空 = プロファイル直下。末尾の要素が現在いるフォルダーのid（無限階層に対応するためスタックで管理）
  @State private var folderStack: [UUID] = []
  @State private var editingButton: ButtonConfig?
  @State private var newButtonPosition: GridPosition?
  @State private var hoveredButtonId: UUID?

  private let columns = Array(repeating: GridItem(.flexible()), count: ProfileStore.gridCols)

  private var profile: ProfileConfig {
    profileStore.profiles.first(where: { $0.id == profileId }) ?? ProfileConfig(name: "", buttons: [])
  }

  private var visibleButtons: [ButtonConfig] {
    profile.buttons.filter { $0.folderId == folderStack.last }
  }

  private var currentFolderLabel: String? {
    guard let currentId = folderStack.last else { return nil }
    return profile.buttons.first(where: { $0.id == currentId })?.label
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        profileInfoSection
        Divider()
        buttonGridSection
      }
      .padding(20)
    }
    .navigationTitle(profile.name)
    .onAppear {
      nameDraft = profile.name
    }
    .sheet(item: $editingButton) { button in
      ButtonEditorView(button: button) { updated in
        profileStore.updateButton(updated, inProfile: profileId)
      }
    }
    .sheet(item: $newButtonPosition) { position in
      ButtonEditorView(
        button: ButtonConfig(
          row: position.row,
          col: position.col,
          label: "新しいボタン",
          iconName: "square.grid.2x2",
          action: ActionPayload(type: .launchApp, target: ""),
          folderId: folderStack.last
        )
      ) { created in
        profileStore.addButton(created, toProfile: profileId)
      }
    }
  }

  // MARK: - プロファイル情報

  private var profileInfoSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField("プロファイル名", text: $nameDraft)
        .font(.title2.bold())
        .textFieldStyle(.plain)
        .focused($isNameFieldFocused)
        .onSubmit { commitNameIfNeeded() }
        .onChange(of: isNameFieldFocused) { _, focused in
          if !focused { commitNameIfNeeded() }
        }

      HStack(spacing: 8) {
        Text("トリガーアプリ:")
          .foregroundStyle(.secondary)
        Text(profile.triggerAppBundleId ?? "未設定（デフォルトプロファイル）")
        Spacer()
        Button("アプリを選択...") { chooseTriggerApp() }
        if profile.triggerAppBundleId != nil {
          Button("クリア") { clearTriggerApp() }
        }
      }

      HStack {
        if profileStore.activeProfileId == profileId {
          Label("アクティブ", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Button("このプロファイルをアクティブにする") {
            profileStore.setActiveProfile(id: profileId)
          }
        }
      }
    }
  }

  private func commitNameIfNeeded() {
    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      // 空文字での上書きは許容しない
      nameDraft = profile.name
      return
    }
    guard trimmed != profile.name else { return }
    var updated = profile
    updated.name = trimmed
    profileStore.updateProfile(updated)
  }

  /// NSOpenPanelで.appを選ばせ、そのBundle IDをtriggerAppBundleIdへ反映する
  private func chooseTriggerApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let bundleId = Bundle(url: url)?.bundleIdentifier else { return }
    var updated = profile
    updated.triggerAppBundleId = bundleId
    profileStore.updateProfile(updated)
  }

  private func clearTriggerApp() {
    var updated = profile
    updated.triggerAppBundleId = nil
    profileStore.updateProfile(updated)
  }

  // MARK: - ボタングリッド

  private var buttonGridSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("ボタン" + (currentFolderLabel.map { " – \($0)" } ?? ""))
          .font(.headline)
        Spacer()
        if !folderStack.isEmpty {
          Button {
            folderStack.removeLast()
          } label: {
            Label("戻る", systemImage: "chevron.left")
          }
        }
      }

      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(0..<(ProfileStore.gridRows * ProfileStore.gridCols), id: \.self) { index in
          let row = index / ProfileStore.gridCols
          let col = index % ProfileStore.gridCols
          gridCell(row: row, col: col)
        }
      }
    }
  }

  @ViewBuilder
  private func gridCell(row: Int, col: Int) -> some View {
    if let button = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
      buttonCell(button)
    } else {
      addCell(row: row, col: col)
    }
  }

  private func buttonCell(_ button: ButtonConfig) -> some View {
    ZStack(alignment: .topTrailing) {
      Button {
        editingButton = button
      } label: {
        VStack(spacing: 6) {
          iconView(for: button)
            .font(.system(size: 22))
            .frame(width: 28, height: 28)
          Text(button.label)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
      }
      .buttonStyle(.plain)

      if hoveredButtonId == button.id {
        Button {
          profileStore.deleteButton(id: button.id, fromProfile: profileId)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
      }

      if button.action.type == .openFolder {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Button {
              folderStack.append(button.id)
            } label: {
              Image(systemName: "chevron.right.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("フォルダーを開く")
          }
        }
        .padding(4)
      }
    }
    .onHover { hovering in
      hoveredButtonId = hovering ? button.id : nil
    }
  }

  @ViewBuilder
  private func iconView(for button: ButtonConfig) -> some View {
    if button.iconKind == .sfSymbol {
      Image(systemName: button.iconName)
    } else {
      // 画像/GIFアイコンはiPad専用機能のため、Mac側では代替アイコンのみ表示する
      Image(systemName: "photo")
    }
  }

  private func addCell(row: Int, col: Int) -> some View {
    Button {
      newButtonPosition = GridPosition(row: row, col: col)
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }
    .buttonStyle(.plain)
  }
}

/// 新規ボタンを追加する先のグリッド座標（シート表示の`item:`にはIdentifiableが必要なため用意）
private struct GridPosition: Identifiable {
  let row: Int
  let col: Int
  var id: String { "\(row)-\(col)" }
}

#Preview {
  ProfileEditorView(profileStore: ProfileStore())
}
