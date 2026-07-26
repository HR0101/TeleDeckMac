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
  @State private var isShowingNewProfileAlert = false
  @State private var newProfileNameDraft = ""
  @State private var hoveredProfileId: UUID?

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      if let profile = selectedProfile {
        ProfileDetailView(profileStore: profileStore, profileId: profile.id)
          .id(profile.id)
      } else {
        ZStack {
          GamingBackground(animated: false)
          ContentUnavailableView("プロファイルを選択してください", systemImage: "square.grid.3x2")
            .foregroundStyle(GamingPalette.mutedForeground)
        }
      }
    }
    .tint(GamingPalette.accent)
    .frame(minWidth: 900, minHeight: 620)
    .preferredColorScheme(.dark)
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
      Text(profileDeletionWarning)
    }
    .alert("新規プロファイル", isPresented: $isShowingNewProfileAlert) {
      TextField("プロファイル名", text: $newProfileNameDraft)
      Button("作成") { addProfile() }
      Button("キャンセル", role: .cancel) { newProfileNameDraft = "" }
    } message: {
      Text("プロファイルの名前を入力してください。後から変更できます。")
    }
  }

  private var selectedProfile: ProfileConfig? {
    guard let id = selectedProfileId else { return nil }
    return profileStore.profiles.first(where: { $0.id == id })
  }

  private var profileDeletionWarning: String {
    guard let id = profileIdPendingDeletion else {
      return "ボタン設定も含めて削除されます。この操作は取り消せません。"
    }
    if id == profileStore.activeProfileId {
      return "現在iPadで使用中のプロファイルです。削除すると、別のプロファイルへ切り替わります。ボタン設定も含めて削除され、この操作は取り消せません。"
    }
    return "ボタン設定も含めて削除されます。この操作は取り消せません。"
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Label("プロファイル", systemImage: "square.grid.3x3.fill")
          .font(.title3.weight(.bold))
          .foregroundStyle(GamingPalette.foreground)
        Text("iPadに表示するパネルを管理")
          .font(.caption)
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .padding(.horizontal, 16)
      .padding(.top, 18)
      .padding(.bottom, 14)

      newProfileButton
        .padding(.horizontal, 12)
        .padding(.bottom, 12)

      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(profileStore.profiles) { profile in
            profileRow(profile)
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }

      HStack(spacing: 7) {
        Circle()
          .fill(GamingPalette.success)
          .frame(width: 7, height: 7)
          .shadow(color: GamingPalette.success.opacity(0.75), radius: 3)
        Text("現在iPadで使用中")
          .font(.caption2)
          .foregroundStyle(GamingPalette.mutedForeground)
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .background(.ultraThinMaterial)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(GamingPalette.accent.opacity(0.25))
          .frame(height: 1)
      }
    }
    .background(
      LinearGradient(
        colors: [
          GamingPalette.background.opacity(0.96),
          GamingPalette.backgroundElevated.opacity(0.94)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 300)
  }

  private func profileRow(_ profile: ProfileConfig) -> some View {
    let isSelected = selectedProfileId == profile.id
    let isActive = profile.id == profileStore.activeProfileId

    return Button {
      selectedProfileId = profile.id
    } label: {
      HStack(spacing: 11) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? GamingPalette.accent.opacity(0.28) : GamingPalette.muted.opacity(0.72))
          Image(systemName: profile.triggerAppBundleId == nil ? "square.grid.3x3" : "app.badge")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? GamingPalette.accent : GamingPalette.mutedForeground)
        }
        .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(profile.name)
              .font(.subheadline.weight(isSelected || isActive ? .semibold : .medium))
              .foregroundStyle(GamingPalette.foreground)
              .lineLimit(1)

            if isActive {
              Circle()
                .fill(GamingPalette.success)
                .frame(width: 7, height: 7)
                .shadow(color: GamingPalette.success.opacity(0.7), radius: 3)
            }
          }
          Text(profile.triggerAppBundleId ?? "手動切り替え")
            .font(.caption2)
            .foregroundStyle(GamingPalette.mutedForeground)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer(minLength: 8)

        Text("\(profile.buttons.count)")
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(isSelected ? GamingPalette.accent : GamingPalette.mutedForeground)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(GamingPalette.muted.opacity(0.7), in: Capsule())
      }
      .padding(10)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            isSelected
              ? GamingPalette.accent.opacity(0.16)
              : GamingPalette.card.opacity(hoveredProfileId == profile.id ? 0.72 : 0.42)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(
            GamingPalette.accent.opacity(isSelected ? 0.72 : (hoveredProfileId == profile.id ? 0.34 : 0.16)),
            lineWidth: isSelected ? 1.2 : 1
          )
      )
    }
    .buttonStyle(ProfileSidebarButtonStyle())
    .onHover { hovering in
      hoveredProfileId = hovering ? profile.id : nil
    }
    .contextMenu {
      Button("削除", role: .destructive) {
        profileIdPendingDeletion = profile.id
      }
      // プロファイルが1つしかない場合は削除できないため、操作自体を無効化する
      .disabled(profileStore.profiles.count <= 1)
    }
    .accessibilityLabel(profile.name)
    .accessibilityValue(isActive ? "現在iPadで使用中" : "")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var newProfileButton: some View {
    Button {
      newProfileNameDraft = ""
      isShowingNewProfileAlert = true
    } label: {
      Label("新規プロファイル", systemImage: "plus.circle.fill")
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(GamingButtonStyle(isProminent: true))
  }

  private func addProfile() {
    let trimmedName = newProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let newProfile = ProfileConfig(
      name: trimmedName.isEmpty ? "新規プロファイル" : trimmedName,
      triggerAppBundleId: nil,
      buttons: []
    )
    profileStore.addProfile(newProfile)
    selectedProfileId = newProfile.id
    newProfileNameDraft = ""
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
  @State private var hoveredEmptyCellId: String?
  @State private var buttonPendingDeletion: ButtonConfig?
  @State private var dropErrorMessage: String?

  private var columns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 64, maximum: 112), spacing: 12),
      count: profile.gridColumns
    )
  }

  private var profile: ProfileConfig {
    profileStore.profiles.first(where: { $0.id == profileId }) ?? ProfileConfig(name: "", buttons: [])
  }

  private var visibleButtons: [ButtonConfig] {
    profile.buttons.filter { $0.folderId == folderStack.last }
  }

  var body: some View {
    ZStack {
      GamingBackground(animated: false)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          profileInfoSection
          buttonGridSection
        }
        .padding(24)
        .frame(maxWidth: 980)
        .frame(maxWidth: .infinity)
      }
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
    } message: {
      Text(buttonDeletionWarningMessage)
    }
    .alert("配置できません", isPresented: Binding(
      get: { dropErrorMessage != nil },
      set: { if !$0 { dropErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { dropErrorMessage = nil }
    } message: {
      Text(dropErrorMessage ?? "")
    }
  }

  /// フォルダーボタンを削除する場合、中の子ボタンも一緒に削除されることを事前に警告する
  private var buttonDeletionWarningMessage: String {
    guard let button = buttonPendingDeletion, button.action.type == .openFolder else {
      return "この操作は取り消せません。"
    }
    let childCount = profile.buttons.filter { $0.folderId == button.id }.count
    guard childCount > 0 else {
      return "この操作は取り消せません。"
    }
    return "フォルダー内の\(childCount)個のボタンも一緒に削除されます。この操作は取り消せません。"
  }

  // MARK: - プロファイル情報

  private var profileInfoSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .center, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(GamingPalette.accent.opacity(0.22))
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(GamingPalette.accent.opacity(0.55), lineWidth: 1)
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(GamingPalette.accent)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 4) {
          Text("プロファイル設定")
            .font(.headline)
            .foregroundStyle(GamingPalette.foreground)
          Text("名前、自動切り替え、iPadで使うパネルを管理します")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
        }

        Spacer()

        if profileStore.activeProfileId == profileId {
          Label("使用中", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(GamingPalette.success)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(GamingPalette.success.opacity(0.12), in: Capsule())
            .overlay(
              Capsule()
                .stroke(GamingPalette.success.opacity(0.38), lineWidth: 1)
            )
        } else {
          Button {
            profileStore.setActiveProfile(id: profileId)
          } label: {
            Label("iPadで使用", systemImage: "ipad.and.arrow.forward")
              .font(.subheadline.weight(.semibold))
          }
          .buttonStyle(GamingButtonStyle(isProminent: true))
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("プロファイル名")
          .font(.caption.weight(.medium))
          .foregroundStyle(GamingPalette.mutedForeground)
        TextField("プロファイル名", text: $nameDraft)
          .font(.title3.weight(.semibold))
          .gamingField(cornerRadius: 11)
          .focused($isNameFieldFocused)
          .onSubmit { commitNameIfNeeded() }
          .onChange(of: isNameFieldFocused) { _, focused in
            if !focused { commitNameIfNeeded() }
          }
      }

      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(GamingPalette.muted.opacity(0.75))
          Image(systemName: "app.badge")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(GamingPalette.accent)
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: 3) {
          Text("アプリに合わせて自動切り替え")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(GamingPalette.foreground)
          Text(profile.triggerAppBundleId ?? "未設定 — 手動で切り替えます")
            .font(.caption)
            .foregroundStyle(GamingPalette.mutedForeground)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Button {
          chooseTriggerApp()
        } label: {
          Label("アプリを選択", systemImage: "plus.app")
        }
        .buttonStyle(GamingButtonStyle())

        if profile.triggerAppBundleId != nil {
          Button {
            clearTriggerApp()
          } label: {
            Image(systemName: "xmark")
              .frame(width: 16, height: 16)
          }
          .buttonStyle(GamingButtonStyle())
          .help("自動切り替えを解除")
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(GamingPalette.muted.opacity(0.42))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(GamingPalette.accent.opacity(0.2), lineWidth: 1)
      )
    }
    .padding(18)
    .gamingCard(cornerRadius: 16)
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
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        HStack(spacing: 11) {
          ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(GamingPalette.accent.opacity(0.2))
            Image(systemName: "square.grid.3x3.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(GamingPalette.accent)
          }
          .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 3) {
            Text("パネル")
              .font(.headline)
              .foregroundStyle(GamingPalette.foreground)
            Text("クリックで編集、ドラッグで並べ替え。Finderからも追加できます")
              .font(.caption)
              .foregroundStyle(GamingPalette.mutedForeground)
          }
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
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(GamingPalette.background.opacity(0.48))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(GamingPalette.accent.opacity(0.18), lineWidth: 1)
      )
    }
    .padding(18)
    .gamingCard(cornerRadius: 16)
  }

  private var gridSizeControls: some View {
    HStack(spacing: 10) {
      gridSizeControl(
        title: "行",
        systemImage: "rectangle.split.3x1",
        value: Binding(
          get: { profile.gridRows },
          set: { updateGridSize(rows: $0, columns: profile.gridColumns) }
        ),
        range: Self.gridRowsRange
      )

      gridSizeControl(
        title: "列",
        systemImage: "rectangle.split.1x2",
        value: Binding(
          get: { profile.gridColumns },
          set: { updateGridSize(rows: profile.gridRows, columns: $0) }
        ),
        range: Self.gridColumnsRange
      )

      Spacer()

      Text("\(profile.gridRows) × \(profile.gridColumns)  •  \(profile.buttons.count) ボタン")
        .font(.caption.monospacedDigit())
        .foregroundStyle(GamingPalette.mutedForeground)
    }
  }

  private func gridSizeControl(
    title: String,
    systemImage: String,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(GamingPalette.accent)
      Stepper(value: value, in: range) {
        Text("\(title) \(value.wrappedValue)")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(GamingPalette.foreground)
      }
      .fixedSize()
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 36)
    .background(GamingPalette.muted.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(GamingPalette.accent.opacity(0.22), lineWidth: 1)
    )
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
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 5) {
        Button {
          folderStack = []
        } label: {
          Label("ルート", systemImage: "house.fill")
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(folderStack.isEmpty ? GamingPalette.mutedForeground : GamingPalette.accent)
        .disabled(folderStack.isEmpty)

        ForEach(Array(folderStack.enumerated()), id: \.offset) { index, folderId in
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(GamingPalette.mutedForeground)
          Button {
            folderStack = Array(folderStack.prefix(index + 1))
          } label: {
            Text(profile.buttons.first(where: { $0.id == folderId })?.label ?? "フォルダー")
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(maxWidth: 180, alignment: .leading)
          }
          .buttonStyle(.plain)
          .foregroundStyle(index == folderStack.count - 1 ? GamingPalette.mutedForeground : GamingPalette.accent)
          .disabled(index == folderStack.count - 1)
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 10)
      .frame(minHeight: 34)
      .background(GamingPalette.muted.opacity(0.4), in: Capsule())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.caption.weight(.medium))
  }

  @ViewBuilder
  private func gridCell(row: Int, col: Int) -> some View {
    Group {
      if let button = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
        buttonCell(button)
      } else {
        addCell(row: row, col: col)
      }
    }
    // ドラッグしてきたボタンをこのマスへドロップして移動できるようにする
    .dropDestination(for: String.self) { items, _ in
      guard let draggedIdString = items.first else { return false }
      moveButton(withIdString: draggedIdString, toRow: row, col: col)
      return true
    }
    // Finderからアプリ・ファイル・フォルダをドロップしたら、その場所に対応するボタンを作成する
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first else { return false }
      if visibleButtons.contains(where: { $0.row == row && $0.col == col }) {
        dropErrorMessage = "このマスには既にボタンがあります。空きマスにドロップしてください。"
        return false
      }
      return createButton(fromDropped: url, row: row, col: col)
    }
  }

  /// Finderからドロップされたアプリ・ファイル・フォルダから、そのマス用のボタンを作成する。
  /// 既にボタンがあるマスへのドロップは、並べ替えとの混同を避けるため無視する
  private func createButton(fromDropped url: URL, row: Int, col: Int) -> Bool {
    guard !visibleButtons.contains(where: { $0.row == row && $0.col == col }) else { return false }

    let newButton: ButtonConfig
    if url.pathExtension.lowercased() == "app" {
      let bundleId = Bundle(url: url)?.bundleIdentifier
      newButton = ButtonConfig(
        row: row,
        col: col,
        label: url.deletingPathExtension().lastPathComponent,
        iconName: "app.fill",
        action: ActionPayload(type: .launchApp, target: bundleId ?? url.deletingPathExtension().lastPathComponent),
        folderId: folderStack.last
      )
    } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
      newButton = ButtonConfig(
        row: row,
        col: col,
        label: url.lastPathComponent,
        iconName: "folder",
        action: ActionPayload(type: .openFinderFolder, target: url.path),
        folderId: folderStack.last
      )
    } else {
      newButton = ButtonConfig(
        row: row,
        col: col,
        label: url.deletingPathExtension().lastPathComponent,
        iconName: "doc",
        action: ActionPayload(type: .openURL, target: url.absoluteString),
        folderId: folderStack.last
      )
    }

    profileStore.addButton(newButton, toProfile: profileId)
    return true
  }

  /// ドラッグされたボタンを指定マスへ移動する。移動先に既にボタンがある場合は元の位置と入れ替える
  private func moveButton(withIdString draggedIdString: String, toRow row: Int, col: Int) {
    guard let draggedId = UUID(uuidString: draggedIdString),
          let draggedButton = visibleButtons.first(where: { $0.id == draggedId }),
          draggedButton.row != row || draggedButton.col != col
    else { return }

    if let targetButton = visibleButtons.first(where: { $0.row == row && $0.col == col }) {
      var swappedTarget = targetButton
      swappedTarget.row = draggedButton.row
      swappedTarget.col = draggedButton.col
      profileStore.updateButton(swappedTarget, inProfile: profileId)
    }

    var movedButton = draggedButton
    movedButton.row = row
    movedButton.col = col
    profileStore.updateButton(movedButton, inProfile: profileId)
  }

  private func buttonCell(_ button: ButtonConfig) -> some View {
    GeometryReader { proxy in
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
              .foregroundStyle(GamingPalette.foreground)
              .frame(width: 28, height: 28)
            Text(button.label)
              .font(.caption.weight(.medium))
              .lineLimit(1)
              .foregroundStyle(GamingPalette.foreground)
          }
          .padding(8)
          .frame(width: proxy.size.width, height: proxy.size.height)
          .macStreamDeckGlassTile(isHovered: hoveredButtonId == button.id)
          .overlay(alignment: .bottomTrailing) {
            if button.action.type == .openFolder {
              Image(systemName: "chevron.right.circle.fill")
                .foregroundStyle(GamingPalette.accent)
                .padding(7)
            }
          }
        }
        .buttonStyle(MacPanelGridButtonStyle())
        .draggable(button.id.uuidString)

        if hoveredButtonId == button.id {
          HStack(spacing: 5) {
            Button {
              editingButton = button
            } label: {
              Image(systemName: "pencil.circle.fill")
                .foregroundStyle(GamingPalette.accent)
            }
            .help("ボタンを編集")

            Button {
              buttonPendingDeletion = button
            } label: {
              Image(systemName: "trash.circle.fill")
                .foregroundStyle(GamingPalette.destructive)
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
    .aspectRatio(1, contentMode: .fit)
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
    let cellId = "\(row)-\(col)"

    return GeometryReader { proxy in
      Button {
        newButtonPosition = GridPosition(row: row, col: col)
      } label: {
        VStack(spacing: 7) {
          ZStack {
            Circle()
              .fill(GamingPalette.accent.opacity(0.16))
            Image(systemName: "plus")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(GamingPalette.accent)
          }
          .frame(width: 36, height: 36)

          Text("アクションを追加")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(GamingPalette.mutedForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(8)
        .frame(width: proxy.size.width, height: proxy.size.height)
        .macStreamDeckGlassTile(
          isHovered: hoveredEmptyCellId == cellId,
          isEmpty: true
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(MacPanelGridButtonStyle())
      .onHover { hovering in
        hoveredEmptyCellId = hovering ? cellId : nil
      }
      .help("この位置にアクションを追加")
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityLabel("アクションを追加")
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
                  GamingPalette.card.opacity(isEmpty ? 0.34 : 0.86),
                  GamingPalette.background.opacity(isEmpty ? 0.42 : 0.76)
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
                GamingPalette.accent.opacity(isHovered ? 0.9 : 0.28),
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
      .shadow(color: GamingPalette.accent.opacity(isHovered ? 0.3 : 0.1), radius: 10)
  }
}

private struct ProfileSidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.88 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct MacPanelGridButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
