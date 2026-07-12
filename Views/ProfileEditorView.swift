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
        selectedProfileId = profileStore.activeProfileId
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
        HStack(spacing: 9) {
          Image(systemName: profile.id == profileStore.activeProfileId ? "circle.inset.filled" : "circle")
            .font(.caption)
            .foregroundStyle(profile.id == profileStore.activeProfileId ? Color.accentColor : Color.secondary.opacity(0.55))

          VStack(alignment: .leading, spacing: 3) {
            Text(profile.name)
              .fontWeight(profile.id == profileStore.activeProfileId ? .semibold : .regular)
            Text(profile.triggerAppBundleId ?? "手動切り替え")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
          Text("\(profile.buttons.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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
    .safeAreaInset(edge: .bottom) {
      Text("● は現在iPadで使用中のプロファイル")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }
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
  @State private var buttonPendingDeletion: ButtonConfig?

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible()), count: profile.gridColumns)
  }

  private var profile: ProfileConfig {
    profileStore.profiles.first(where: { $0.id == profileId }) ?? ProfileConfig(name: "", buttons: [])
  }

  private var visibleButtons: [ButtonConfig] {
    profile.buttons.filter { $0.folderId == folderStack.last }
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
    .confirmationDialog(
      "「\(buttonPendingDeletion?.label ?? "ボタン")」を削除しますか？",
      isPresented: Binding(
        get: { buttonPendingDeletion != nil },
        set: { if !$0 { buttonPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("削除", role: .destructive) {
        if let button = buttonPendingDeletion {
          profileStore.deleteButton(id: button.id, fromProfile: profileId)
        }
        buttonPendingDeletion = nil
      }
      Button("キャンセル", role: .cancel) {
        buttonPendingDeletion = nil
      }
    }
  }

  // MARK: - プロファイル情報

  private var profileInfoSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text("プロファイル設定")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField("プロファイル名", text: $nameDraft)
            .font(.title2.bold())
            .textFieldStyle(.plain)
            .focused($isNameFieldFocused)
            .onSubmit { commitNameIfNeeded() }
            .onChange(of: isNameFieldFocused) { _, focused in
              if !focused { commitNameIfNeeded() }
            }
        }

        Spacer()

        if profileStore.activeProfileId == profileId {
          Label("使用中", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.green.opacity(0.1), in: Capsule())
        } else {
          Button("iPadで使用") {
            profileStore.setActiveProfile(id: profileId)
          }
          .buttonStyle(.borderedProminent)
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "app.badge")
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text("自動切り替え")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(profile.triggerAppBundleId ?? "未設定（手動で切り替え）")
        }
        Spacer()
        Button("アプリを選択…") { chooseTriggerApp() }
        if profile.triggerAppBundleId != nil {
          Button("クリア") { clearTriggerApp() }
        }
      }
    }
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
        VStack(alignment: .leading, spacing: 4) {
          Text("パネル")
            .font(.headline)
          Text("ボタンをクリックして編集。フォルダーはクリックして開きます。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      gridSizeControls

      folderBreadcrumb

      LazyVGrid(columns: columns, spacing: 12) {
        let gridColumns = profile.gridColumns
        ForEach(0..<(profile.gridRows * gridColumns), id: \.self) { index in
          let row = index / gridColumns
          let col = index % gridColumns
          gridCell(row: row, col: col)
        }
      }
    }
    .padding(16)
    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
  }

  private var gridSizeControls: some View {
    HStack(spacing: 20) {
      Stepper(
        "行数: \(profile.gridRows)",
        value: Binding(
          get: { profile.gridRows },
          set: { updateGridSize(rows: $0, columns: profile.gridColumns) }
        ),
        in: Self.gridRowsRange
      )
      Stepper(
        "列数: \(profile.gridColumns)",
        value: Binding(
          get: { profile.gridColumns },
          set: { updateGridSize(rows: profile.gridRows, columns: $0) }
        ),
        in: Self.gridColumnsRange
      )
      Spacer()
    }
    .font(.caption)
  }

  private static let gridRowsRange = 1...8
  private static let gridColumnsRange = 1...10

  private func updateGridSize(rows: Int, columns: Int) {
    var updated = profile
    updated.gridRows = rows
    updated.gridColumns = columns
    profileStore.updateProfile(updated)
  }

  private var folderBreadcrumb: some View {
    HStack(spacing: 5) {
      Button {
        folderStack = []
      } label: {
        Label("ルート", systemImage: "square.grid.3x3")
      }
      .disabled(folderStack.isEmpty)

      ForEach(Array(folderStack.enumerated()), id: \.offset) { index, folderId in
        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Button(profile.buttons.first(where: { $0.id == folderId })?.label ?? "フォルダー") {
          folderStack = Array(folderStack.prefix(index + 1))
        }
        .disabled(index == folderStack.count - 1)
      }
    }
    .font(.caption)
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
        if button.action.type == .openFolder {
          folderStack.append(button.id)
        } else {
          editingButton = button
        }
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
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .macStreamDeckGlassTile(isHovered: hoveredButtonId == button.id)
        .overlay(alignment: .bottomTrailing) {
          if button.action.type == .openFolder {
            Image(systemName: "chevron.right.circle.fill")
              .foregroundStyle(.secondary)
              .padding(7)
          }
        }
      }
      .buttonStyle(.plain)

      if hoveredButtonId == button.id {
        HStack(spacing: 5) {
          Button {
            editingButton = button
          } label: {
            Image(systemName: "pencil.circle.fill")
          }
          .help("ボタンを編集")

          Button {
            buttonPendingDeletion = button
          } label: {
            Image(systemName: "trash.circle.fill")
              .foregroundStyle(.red)
          }
          .help("ボタンを削除")
        }
        .buttonStyle(.plain)
        .padding(6)
      }
    }
    .onHover { hovering in
      hoveredButtonId = hovering ? button.id : nil
    }
  }

  @ViewBuilder
  private func iconView(for button: ButtonConfig) -> some View {
    if button.action.type == .launchApp,
       let target = button.action.target,
       let icon = applicationIcon(for: target) {
      Image(nsImage: icon)
        .resizable()
        .scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    } else if button.iconKind == .sfSymbol {
      Image(systemName: button.iconName)
    } else {
      // 画像/GIFアイコンはiPad専用機能のため、Mac側では代替アイコンのみ表示する
      Image(systemName: "photo")
    }
  }

  private func applicationIcon(for target: String) -> NSImage? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }

    let applicationName = target.hasSuffix(".app") ? target : "\(target).app"
    let searchDirectories = [
      "/Applications",
      "/System/Applications",
      "/System/Applications/Utilities",
      (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
    ]
    for directory in searchDirectories {
      let candidate = (directory as NSString).appendingPathComponent(applicationName)
      if FileManager.default.fileExists(atPath: candidate) {
        return NSWorkspace.shared.icon(forFile: candidate)
      }
    }
    return nil
  }

  private func addCell(row: Int, col: Int) -> some View {
    Button {
      newButtonPosition = GridPosition(row: row, col: col)
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .macStreamDeckGlassTile(isHovered: false, isEmpty: true)
    }
    .buttonStyle(.plain)
  }
}

private struct MacStreamDeckGlassTileModifier: ViewModifier {
  let isHovered: Bool
  let isEmpty: Bool

  func body(content: Content) -> some View {
    content
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(isEmpty ? 0.035 : 0.12),
                  Color(nsColor: .controlBackgroundColor).opacity(isEmpty ? 0.35 : 0.82),
                  Color.black.opacity(isEmpty ? 0.18 : 0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(isEmpty ? 0.12 : 0.28)
          LinearGradient(
            colors: [.white.opacity(isEmpty ? 0.04 : 0.18), .clear],
            startPoint: .top,
            endPoint: .center
          )
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [
                .white.opacity(isEmpty ? 0.16 : 0.48),
                Color.accentColor.opacity(isHovered ? 0.9 : 0.28),
                .black.opacity(0.55)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1, dash: isEmpty ? [4, 4] : [])
          )
      }
      .overlay(alignment: .top) {
        Capsule()
          .fill(.white.opacity(isEmpty ? 0.07 : 0.3))
          .frame(width: 26, height: 1.5)
          .padding(.top, 4)
      }
      .shadow(color: .black.opacity(isEmpty ? 0.12 : 0.34), radius: 7, y: 4)
      .shadow(color: Color.accentColor.opacity(isHovered ? 0.22 : 0.08), radius: 10)
  }
}

private extension View {
  func macStreamDeckGlassTile(isHovered: Bool, isEmpty: Bool = false) -> some View {
    modifier(MacStreamDeckGlassTileModifier(isHovered: isHovered, isEmpty: isEmpty))
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
