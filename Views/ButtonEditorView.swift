//
//  ButtonEditorView.swift
//  TeleDeckMac
//
//  パネルのボタン1つを編集するシート（Mac版）。iPad版 Views/ButtonEditView.swift の編集体験を移植したもの。
//  Mac側はアイコンとしてSF Symbolsのみ対応し、画像/GIFアイコン（iPad専用機能）はここでは編集しない。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let commonSFSymbols = [
  "globe", "safari", "link", "doc.on.doc", "clipboard", "terminal", "folder",
  "message", "envelope", "music.note", "play.fill", "speaker.wave.2",
  "text.cursor", "keyboard", "gearshape", "star", "bolt", "square.grid.2x2"
]

private let modifierKeys = ["cmd", "shift", "opt", "ctrl"]

/// ウィンドウ配置アクションのプリセット。rawValueはMac側WindowLayoutManagerが解釈する文字列と一致させる
private enum WindowLayoutPreset: String, CaseIterable, Identifiable {
  case leftHalf = "left-half"
  case rightHalf = "right-half"
  case maximize = "maximize"
  case centered = "centered"
  case threeSplit = "three-split"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .leftHalf: return "左半分"
    case .rightHalf: return "右半分"
    case .maximize: return "最大化"
    case .centered: return "中央寄せ"
    case .threeSplit: return "3分割"
    }
  }
}

struct ButtonEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ButtonConfig

  let onSave: (ButtonConfig) -> Void

  init(button: ButtonConfig, onSave: @escaping (ButtonConfig) -> Void) {
    _draft = State(initialValue: button)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("表示") {
          TextField("ラベル", text: $draft.label)
          iconSection
        }

        Section("アクション") {
          Picker("種別", selection: $draft.action.type) {
            Text("アプリ起動").tag(ActionType.launchApp)
            Text("URLを開く").tag(ActionType.openURL)
            Text("ホットキー").tag(ActionType.hotkey)
            Text("定型文入力").tag(ActionType.typeText)
            Text("音量調整").tag(ActionType.setVolume)
            Text("マルチアクション").tag(ActionType.multiAction)
            Text("フォルダー").tag(ActionType.openFolder)
            Text("ウィンドウ配置").tag(ActionType.windowLayout)
          }
          .onChange(of: draft.action.type) { _, newType in
            // 初めてウィンドウ配置に切り替えた時点でプリセットを既定値に確定させ、保存時にnilのままにならないようにする
            if newType == .windowLayout, draft.action.preset == nil {
              draft.action.preset = WindowLayoutPreset.leftHalf.rawValue
            }
          }

          actionParameterFields
        }
      }
      .formStyle(.grouped)
      .navigationTitle("ボタン編集")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            onSave(draft)
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 480, minHeight: 520)
  }

  // MARK: - アイコン選択

  @ViewBuilder
  private var iconSection: some View {
    if draft.iconKind == .image {
      // iPad側で設定された画像/GIFアイコンはMac側では変更できないため、説明表示のみに留める
      Text("画像アイコン（iPad側で設定）")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
          Image(systemName: draft.iconName.isEmpty ? "questionmark.square.dashed" : draft.iconName)
            .font(.system(size: 22))
            .frame(width: 32, height: 32)
          Text(draft.iconName.isEmpty ? "未選択" : draft.iconName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
          ForEach(commonSFSymbols, id: \.self) { symbol in
            let isSelected = draft.iconName == symbol
            Image(systemName: symbol)
              .font(.system(size: 16))
              .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
              .frame(width: 32, height: 32)
              .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 8)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.2)
              )
              .onTapGesture {
                draft.iconKind = .sfSymbol
                draft.iconName = symbol
              }
          }
        }

        TextField("SF Symbol名を直接入力", text: $draft.iconName)
          .font(.caption)
      }
    }
  }

  // MARK: - アクション種別ごとの入力欄

  @ViewBuilder
  private var actionParameterFields: some View {
    switch draft.action.type {
    case .launchApp:
      launchAppFields
    case .openURL:
      TextField("URL", text: targetBinding)
    case .hotkey:
      hotkeyFields
    case .typeText:
      TextField("入力するテキスト", text: textBinding, axis: .vertical)
        .lineLimit(3...6)
    case .setVolume:
      Stepper("音量: \(draft.action.volume ?? 50)", value: volumeBinding, in: 0...100, step: 5)
    case .multiAction:
      MultiActionStepsEditor(steps: stepsBinding)
    case .delay:
      Stepper("待機時間: \(draft.action.ms ?? 500) ms", value: msBinding, in: 0...10000, step: 100)
    case .openFolder:
      Text("このボタンをタップすると中のボタン一覧を開きます")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .activateTab, .closeTab, .activateApplication:
      // タブ一覧画面から生成されるアクションのため、この汎用エディタでは編集項目を出さない
      Text("タブ一覧から設定されるアクションです")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .activateApplication:
      launchAppFields
    case .windowLayout:
      windowLayoutFields
    }
  }

  private var launchAppFields: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("アプリ名 または Bundle ID", text: targetBinding)
      Button("アプリを選択...") {
        chooseApplication()
      }
    }
  }

  /// NSOpenPanelで.appを選ばせ、Bundle IDをtargetへ自動入力する
  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if let bundleId = Bundle(url: url)?.bundleIdentifier {
      draft.action.target = bundleId
    } else {
      // Bundle IDが取得できない場合は拡張子を除いたアプリ名をフォールバックとして使う
      draft.action.target = url.deletingPathExtension().lastPathComponent
    }
  }

  private var windowLayoutFields: some View {
    Picker("配置プリセット", selection: presetBinding) {
      ForEach(WindowLayoutPreset.allCases) { preset in
        Text(preset.displayName).tag(preset.rawValue)
      }
    }
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { draft.action.preset ?? WindowLayoutPreset.leftHalf.rawValue },
      set: { draft.action.preset = $0 }
    )
  }

  private var hotkeyFields: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        ForEach(modifierKeys, id: \.self) { modifier in
          let isSelected = (draft.action.keys ?? []).contains(modifier)
          Button(modifier) {
            toggleModifier(modifier)
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .foregroundStyle(isSelected ? Color.white : Color.primary)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
          )
        }
      }
      TextField("キー（例: c）", text: keyBinding)
    }
  }

  private func toggleModifier(_ modifier: String) {
    var keys = draft.action.keys ?? []
    if let index = keys.firstIndex(of: modifier) {
      keys.remove(at: index)
    } else {
      keys.append(modifier)
    }
    draft.action.keys = keys
  }

  // MARK: - Optionalフィールド用のBinding

  private var targetBinding: Binding<String> {
    Binding(get: { draft.action.target ?? "" }, set: { draft.action.target = $0 })
  }

  private var textBinding: Binding<String> {
    Binding(get: { draft.action.text ?? "" }, set: { draft.action.text = $0 })
  }

  private var volumeBinding: Binding<Int> {
    Binding(get: { draft.action.volume ?? 50 }, set: { draft.action.volume = $0 })
  }

  private var msBinding: Binding<Int> {
    Binding(get: { draft.action.ms ?? 500 }, set: { draft.action.ms = $0 })
  }

  private var stepsBinding: Binding<[ActionPayload]> {
    Binding(get: { draft.action.steps ?? [] }, set: { draft.action.steps = $0 })
  }

  private var keyBinding: Binding<String> {
    Binding(
      get: {
        (draft.action.keys ?? []).first { !modifierKeys.contains($0) } ?? ""
      },
      set: { newKey in
        let currentModifiers = (draft.action.keys ?? []).filter { modifierKeys.contains($0) }
        draft.action.keys = currentModifiers + (newKey.isEmpty ? [] : [newKey.lowercased()])
      }
    )
  }
}

// MARK: - マルチアクションのステップ編集

private struct MultiActionStepsEditor: View {
  @Binding var steps: [ActionPayload]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(steps.indices, id: \.self) { index in
        StepRow(step: $steps[index]) {
          steps.remove(at: index)
        }
      }

      Button {
        steps.append(ActionPayload(type: .launchApp, target: ""))
      } label: {
        Label("ステップを追加", systemImage: "plus.circle")
      }
    }
  }
}

private struct StepRow: View {
  @Binding var step: ActionPayload
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker("", selection: $step.type) {
          Text("アプリ起動").tag(ActionType.launchApp)
          Text("URLを開く").tag(ActionType.openURL)
          Text("ホットキー").tag(ActionType.hotkey)
          Text("定型文入力").tag(ActionType.typeText)
          Text("音量調整").tag(ActionType.setVolume)
          Text("待機").tag(ActionType.delay)
        }
        .labelsHidden()
        .pickerStyle(.menu)

        Spacer()

        Button(role: .destructive) {
          onDelete()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
      }

      stepParameterField
    }
    .padding(8)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var stepParameterField: some View {
    switch step.type {
    case .launchApp:
      TextField("アプリ名", text: targetBinding)
    case .openURL:
      TextField("URL", text: targetBinding)
    case .hotkey:
      TextField("キー（例: cmd,c）", text: keysBinding)
    case .typeText:
      TextField("入力するテキスト", text: textBinding)
    case .setVolume:
      Stepper("音量: \(step.volume ?? 50)", value: volumeBinding, in: 0...100, step: 5)
    case .delay:
      Stepper("待機: \(step.ms ?? 500) ms", value: msBinding, in: 0...10000, step: 100)
    case .multiAction, .openFolder, .activateTab, .closeTab, .activateApplication, .windowLayout:
      // マルチアクションのステップにはフォルダー・タブ操作・アプリ切替・ウィンドウ配置・入れ子のマルチアクションを登録できない
      Text("マルチアクション内には登録できません")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var targetBinding: Binding<String> {
    Binding(get: { step.target ?? "" }, set: { step.target = $0 })
  }

  private var textBinding: Binding<String> {
    Binding(get: { step.text ?? "" }, set: { step.text = $0 })
  }

  private var volumeBinding: Binding<Int> {
    Binding(get: { step.volume ?? 50 }, set: { step.volume = $0 })
  }

  private var msBinding: Binding<Int> {
    Binding(get: { step.ms ?? 500 }, set: { step.ms = $0 })
  }

  private var keysBinding: Binding<String> {
    Binding(
      get: { (step.keys ?? []).joined(separator: ",") },
      set: { step.keys = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    )
  }
}

#Preview {
  ButtonEditorView(
    button: ButtonConfig(row: 0, col: 0, label: "Chrome", iconName: "globe", action: ActionPayload(type: .launchApp, target: "Google Chrome"))
  ) { _ in }
}
