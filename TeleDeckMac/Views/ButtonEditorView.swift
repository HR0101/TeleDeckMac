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

/// クイック選択できるSF Symbolsの一覧。ここに無いものは下の直接入力欄で指定する。
/// カテゴリーごとにまとめ、よく使うボタンの用途を一通りタップだけで選べるようにしている
private let commonSFSymbols = EditorIconCatalog.commonSFSymbols

private let modifierKeys = ["cmd", "shift", "opt", "ctrl"]

/// AppKitの`sendEvent`より前でキーを観測する低レベルのフォールバック。
/// ローカルNSEvent monitorはメニュー/Controlのネストしたtracking loopでは呼ばれないため、
/// 記録中だけlisten-onlyのCGEvent tapを併用する。
private final class HotkeyCGEventMonitor {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var handler: ((NSEvent) -> Void)?

  func start(handler: @escaping (NSEvent) -> Void) {
    stop()
    self.handler = handler

    let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: eventMask,
      callback: Self.eventTapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else { return }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    self.eventTap = eventTap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
    }
    runLoopSource = nil
    eventTap = nil
    handler = nil
  }

  deinit {
    stop()
  }

  private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyCGEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap = monitor.eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .flagsChanged,
          let nsEvent = NSEvent(cgEvent: event) else {
      return Unmanaged.passUnretained(event)
    }
    DispatchQueue.main.async { [weak monitor] in
      monitor?.handler?(nsEvent)
    }
    return Unmanaged.passUnretained(event)
  }
}

/// ホットキー登録のキー選択グリッドの1キー分の定義
private struct HotkeyPickerKey: Identifiable {
  let id = UUID()
  let label: String
  /// ActionExecutor.keyCodesに対応するキー名
  let keyName: String
  /// 通常キーに対する相対幅（1が標準キー1つ分）
  var widthWeight: CGFloat = 1
}

private enum ButtonEditorStep {
  case action
  /// アクションを選んだ直後に表示する、そのアクション専用の入力画面
  /// （選択画面とURL入力等を同じ画面に詰め込むと見落とされやすいため分離している）
  case parameters
  case appearance
}

private struct ActionChoice: Identifiable {
  let type: ActionType
  /// mediaKey用。同じActionType内で複数の選択肢（音量を上げる/下げる等）を区別するためのキー
  let mediaKey: String?
  /// systemAction用。同じActionType内で複数の選択肢（スリープ/ロック等）を区別するためのキー
  let systemAction: String?
  let title: String
  let description: String
  let systemImage: String

  init(
    type: ActionType,
    mediaKey: String? = nil,
    systemAction: String? = nil,
    title: String,
    description: String,
    systemImage: String
  ) {
    self.type = type
    self.mediaKey = mediaKey
    self.systemAction = systemAction
    self.title = title
    self.description = description
    self.systemImage = systemImage
  }

  var id: String {
    let suffix = mediaKey ?? systemAction
    return suffix.map { "\(type.rawValue)-\($0)" } ?? type.rawValue
  }
}

private struct ActionChoiceGroup: Identifiable {
  let title: String
  let choices: [ActionChoice]

  var id: String { title }
}

private let actionChoiceGroups = [
  ActionChoiceGroup(title: "システム", choices: [
    ActionChoice(type: .openURL, title: "Webサイト", description: "指定したURLをブラウザで開きます", systemImage: "globe"),
    ActionChoice(type: .hotkey, title: "ホットキー", description: "キーボードショートカットを送信します", systemImage: "keyboard"),
    ActionChoice(type: .launchApp, title: "アプリケーションを開く", description: "Macのアプリケーションを起動します", systemImage: "macwindow"),
    ActionChoice(type: .quitApplication, title: "アプリケーションを終了", description: "起動中のMacアプリケーションを終了します", systemImage: "xmark.app"),
    ActionChoice(type: .typeText, title: "テキスト", description: "登録したテキストを入力します", systemImage: "text.cursor"),
    ActionChoice(type: .openFinderFolder, title: "Finderでフォルダを開く", description: "指定したフォルダをFinderで開きます", systemImage: "folder")
  ]),
  ActionChoiceGroup(title: "オーディオ・画面", choices: [
    ActionChoice(type: .setVolume, title: "音量を設定", description: "Macの出力音量を変更します", systemImage: "speaker.wave.2"),
    ActionChoice(type: .mediaKey, mediaKey: "volumeUp", title: "音量を上げる", description: "1段階、音量を上げます", systemImage: "speaker.wave.3"),
    ActionChoice(type: .mediaKey, mediaKey: "volumeDown", title: "音量を下げる", description: "1段階、音量を下げます", systemImage: "speaker.wave.1"),
    ActionChoice(type: .mediaKey, mediaKey: "mute", title: "ミュート切り替え", description: "出力音量のミュートを切り替えます", systemImage: "speaker.slash"),
    ActionChoice(type: .mediaKey, mediaKey: "brightnessUp", title: "画面を明るく", description: "1段階、画面の明るさを上げます", systemImage: "sun.max"),
    ActionChoice(type: .mediaKey, mediaKey: "brightnessDown", title: "画面を暗く", description: "1段階、画面の明るさを下げます", systemImage: "sun.min"),
    ActionChoice(type: .mediaKey, mediaKey: "keyboardBacklightUp", title: "キーボードを明るく", description: "キーボードバックライトを明るくします", systemImage: "keyboard.badge.ellipsis"),
    ActionChoice(type: .mediaKey, mediaKey: "keyboardBacklightDown", title: "キーボードを暗く", description: "キーボードバックライトを暗くします", systemImage: "keyboard"),
    ActionChoice(type: .mediaKey, mediaKey: "micMute", title: "マイクをミュート", description: "システム全体でマイクの入力をミュート/解除します（どのアプリ使用中でも効きます）", systemImage: "mic.slash")
  ]),
  ActionChoiceGroup(title: "メディア再生", choices: [
    ActionChoice(type: .mediaKey, mediaKey: "playPause", title: "再生/一時停止", description: "再生中のメディアを再生・一時停止します", systemImage: "playpause.fill"),
    ActionChoice(type: .mediaKey, mediaKey: "nextTrack", title: "次のトラック", description: "次のトラックにスキップします", systemImage: "forward.end.fill"),
    ActionChoice(type: .mediaKey, mediaKey: "previousTrack", title: "前のトラック", description: "前のトラックに戻ります", systemImage: "backward.end.fill")
  ]),
  ActionChoiceGroup(title: "電源・画面キャプチャ", choices: [
    ActionChoice(type: .systemAction, systemAction: "sleep", title: "スリープ", description: "Macをスリープさせます", systemImage: "moon.fill"),
    ActionChoice(type: .systemAction, systemAction: "lockScreen", title: "画面をロック", description: "画面をロックします", systemImage: "lock.fill"),
    ActionChoice(type: .systemAction, systemAction: "screenSaver", title: "スクリーンセーバーを開始", description: "スクリーンセーバーをすぐに開始します", systemImage: "sparkles"),
    ActionChoice(type: .systemAction, systemAction: "screenshotFull", title: "スクリーンショット（全画面）", description: "画面全体のスクリーンショットを撮ります", systemImage: "camera.viewfinder"),
    ActionChoice(type: .systemAction, systemAction: "screenshotSelection", title: "スクリーンショット（範囲選択）", description: "選択した範囲のスクリーンショットを撮ります", systemImage: "crop")
  ]),
  ActionChoiceGroup(title: "操作", choices: [
    ActionChoice(type: .multiAction, title: "マルチアクション", description: "複数の操作を順番に実行します", systemImage: "list.number"),
    ActionChoice(type: .openFolder, title: "フォルダを作成", description: "パネル内にボタンの階層を作ります", systemImage: "folder"),
    ActionChoice(type: .windowLayout, title: "ウィンドウ配置", description: "前面のウィンドウを指定位置へ移動します", systemImage: "rectangle.split.2x1")
  ])
]

struct ButtonEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ButtonConfig
  @State private var editStep: ButtonEditorStep = .action
  @State private var isRecordingHotkey = false
  @State private var hotkeyRecordingKeys: [String] = []
  @State private var hotkeyRecordingGeneration = 0
  /// 実キー入力の記録中だけ有効化するNSEventのローカル監視。
  /// AppKitの配送を迂回するケースはHotkeyCGEventMonitorが補完する。
  @State private var hotkeyKeyDownMonitor: Any?
  @State private var hotkeyCGEventMonitor = HotkeyCGEventMonitor()
  @State private var heldHotkeyModifierFlags: NSEvent.ModifierFlags = []
  @State private var automaticallyNamesButton: Bool
  @State private var isShowingApplicationPicker = false
  /// アイコンを未カスタマイズ（新規ボタンの初期値のまま）の間だけ、選んだアクションに合わせてアイコンを自動で変える
  @State private var automaticallyPicksIcon: Bool
  /// テスト実行の状態と直近の結果。Mac上での編集なので、iPadを介さず直接実行して確かめられる
  @State private var isTestRunning = false
  @State private var testResultMessage: String?
  @State private var testSucceeded = false
  private let testActionExecutor = ActionExecutor()

  let onSave: (ButtonConfig) -> Void

  init(button: ButtonConfig, onSave: @escaping (ButtonConfig) -> Void) {
    _draft = State(initialValue: button)
    _automaticallyNamesButton = State(
      initialValue: button.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || button.label == "新しいボタン"
    )
    _automaticallyPicksIcon = State(
      initialValue: button.iconKind == .sfSymbol
        && (button.iconName.isEmpty || button.iconName == "square.grid.2x2")
    )
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        switch editStep {
        case .action:
          actionSelectionSections

        case .parameters:
          Section("選択したアクション") {
            Label(selectedActionTitle, systemImage: selectedActionImage)
          }
          Section {
            actionParameterFields
          } header: {
            Text(parameterSectionTitle)
          } footer: {
            if let parameterSectionFooter {
              Text(parameterSectionFooter)
                .foregroundStyle(.secondary)
            }
          }

          testRunSection

        case .appearance:
          Section("表示") {
            TextField("ラベル", text: labelBinding)
            iconSection
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(
        LinearGradient(
          colors: [GamingPalette.background, GamingPalette.backgroundElevated],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
      )
      .tint(GamingPalette.accent)
      .navigationTitle(navigationTitleText)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(editStep == .action ? "キャンセル" : "戻る") {
            switch editStep {
            case .action:
              dismiss()
            case .parameters:
              editStep = .action
            case .appearance:
              editStep = .parameters
            }
          }
        }
        if editStep != .action {
          ToolbarItem(placement: .confirmationAction) {
            Button(editStep == .parameters ? "次へ" : "保存") {
              if editStep == .parameters {
                prepareAppearance()
                editStep = .appearance
              } else {
                onSave(draft)
                dismiss()
              }
            }
          }
        }
      }
    }
    .frame(minWidth: 480, minHeight: 520)
    .onChange(of: editStep) { _, _ in
      // 記録中に別のステップへ移動した場合、監視を外し忘れるとキー入力が
      // アプリ全体で消費され続けてしまうため、画面遷移のたびに必ず止める
      stopRecordingHotkey()
    }
    .onDisappear {
      // シート自体が閉じられた場合の保険として、監視を確実に解除する
      removeHotkeyMonitor()
    }
  }

  // MARK: - テスト実行

  /// 保存してiPadで押すまで動作を確認できないと、ホットキーやウィンドウ配置が正しいか
  /// 分からないまま往復することになるため、その場でMac上で試せるようにする
  @ViewBuilder
  private var testRunSection: some View {
    // フォルダーとタブ操作はパネル上・タブ画面上の文脈でしか意味を持たないため対象外
    if draft.action.type != .openFolder,
       draft.action.type != .activateTab,
       draft.action.type != .closeTab {
      Section {
        HStack(spacing: 10) {
          Button {
            runTest()
          } label: {
            Label(
              isTestRunning ? "実行中…" : "このアクションをテスト実行",
              systemImage: "play.circle"
            )
          }
          .buttonStyle(GamingButtonStyle())
          .disabled(isTestRunning)

          if let testResultMessage {
            Label(
              testResultMessage,
              systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(testSucceeded ? GamingPalette.success : GamingPalette.destructive)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      } header: {
        Text("動作確認")
      } footer: {
        Text("保存しなくても、今の設定のままこのMacで実行して確認できます")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func runTest() {
    isTestRunning = true
    testResultMessage = nil

    testActionExecutor.execute(draft.action) { result in
      DispatchQueue.main.async {
        isTestRunning = false
        switch result {
        case .success:
          testSucceeded = true
          testResultMessage = "実行しました"
        case .failure(let error):
          testSucceeded = false
          testResultMessage = error.localizedDescription
        }
      }
    }
  }

  private var navigationTitleText: String {
    switch editStep {
    case .action: return "アクションを選択"
    case .parameters: return selectedActionTitle
    case .appearance: return "表示を設定"
    }
  }

  @ViewBuilder
  private var actionSelectionSections: some View {
    ForEach(actionChoiceGroups) { group in
      Section(group.title) {
        ForEach(group.choices) { choice in
          Button {
            selectAction(choice)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: choice.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 3) {
                Text(choice.title)
                  .font(.body.weight(.medium))
                  .foregroundStyle(Color.primary)
                Text(choice.description)
                  .font(.caption)
                  .foregroundStyle(Color.secondary)
              }
              Spacer()
              if draft.action.type == choice.type,
                 draft.action.mediaKey == choice.mediaKey,
                 draft.action.systemAction == choice.systemAction {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(Color.accentColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var selectedActionChoice: ActionChoice? {
    actionChoiceGroups.flatMap(\.choices).first {
      $0.type == draft.action.type && $0.mediaKey == draft.action.mediaKey && $0.systemAction == draft.action.systemAction
    }
  }

  private var selectedActionTitle: String {
    selectedActionChoice?.title ?? "アクション"
  }

  private var selectedActionImage: String {
    selectedActionChoice?.systemImage ?? "bolt"
  }

  private func selectAction(_ choice: ActionChoice) {
    draft.action.type = choice.type
    draft.action.mediaKey = choice.mediaKey
    draft.action.systemAction = choice.systemAction
    if choice.type == .windowLayout, draft.action.preset == nil {
      draft.action.preset = WindowLayoutPreset.leftHalf.rawValue
    }
    if choice.type == .launchApp {
      automaticallyNamesButton = true
    }
    if automaticallyPicksIcon {
      draft.iconName = choice.systemImage
    }
    // 選択直後にそのアクション専用の入力画面へ進む（選択画面に埋もれてURL入力欄などが
    // 見落とされないようにするため）
    editStep = .parameters
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

        if !recommendedSFSymbols.isEmpty {
          Text("このアクションのおすすめ")
            .font(.caption2)
            .foregroundStyle(.secondary)
          iconGrid(recommendedSFSymbols)
        }

        Text("すべてのアイコン")
          .font(.caption2)
          .foregroundStyle(.secondary)
        iconGrid(commonSFSymbols)

        TextField("SF Symbol名を直接入力", text: iconNameBinding)
          .font(.caption)
      }
    }
  }

  private func iconGrid(_ symbols: [String]) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
      ForEach(symbols, id: \.self) { symbol in
        iconTile(symbol)
      }
    }
  }

  private func iconTile(_ symbol: String) -> some View {
    let isSelected = draft.iconName == symbol
    return Image(systemName: symbol)
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
        automaticallyPicksIcon = false
      }
  }

  private var iconNameBinding: Binding<String> {
    Binding(
      get: { draft.iconName },
      set: {
        draft.iconName = $0
        automaticallyPicksIcon = false
      }
    )
  }

  /// 選んでいるアクションの機能に合ったアイコン候補。アクションの種類ごとに、
  /// その機能を連想しやすいSF Symbolsだけを絞り込んで表示する
  private var recommendedSFSymbols: [String] {
    var candidates: [String] = []
    if let choiceImage = selectedActionChoice?.systemImage {
      candidates.append(choiceImage)
    }
    candidates.append(contentsOf: additionalRecommendedSFSymbols)

    var seen = Set<String>()
    return candidates.filter { seen.insert($0).inserted }
  }

  private var additionalRecommendedSFSymbols: [String] {
    switch draft.action.type {
    case .launchApp, .activateApplication:
      return ["macwindow", "app.fill", "desktopcomputer", "laptopcomputer", "bolt.fill"]
    case .quitApplication:
      return ["xmark.app", "power", "xmark.circle.fill"]
    case .openURL:
      return ["globe", "safari", "link", "network"]
    case .hotkey:
      return ["keyboard", "command"]
    case .typeText:
      return ["text.cursor", "textformat", "pencil"]
    case .openFinderFolder:
      return ["folder.fill", "folder", "tray.full"]
    case .openFolder:
      return ["folder.fill", "square.grid.2x2", "list.bullet"]
    case .setVolume:
      return ["speaker.wave.2", "speaker.wave.3", "speaker.wave.1"]
    case .multiAction:
      return ["list.number", "list.bullet", "square.stack"]
    case .windowLayout:
      return ["rectangle.split.2x1", "macwindow"]
    case .delay:
      return ["timer", "hourglass", "clock"]
    case .activateTab, .closeTab:
      return ["link", "xmark"]
    case .mediaKey:
      return recommendedMediaKeySymbols
    case .systemAction:
      return recommendedSystemActionSymbols
    }
  }

  private var recommendedMediaKeySymbols: [String] {
    switch draft.action.mediaKey {
    case "volumeUp": return ["speaker.wave.3", "speaker.wave.2"]
    case "volumeDown": return ["speaker.wave.1", "speaker.wave.2"]
    case "mute": return ["speaker.slash", "speaker.wave.2"]
    case "brightnessUp": return ["sun.max", "sun.max.fill"]
    case "brightnessDown": return ["sun.min"]
    case "keyboardBacklightUp", "keyboardBacklightDown": return ["keyboard", "keyboard.badge.ellipsis"]
    case "micMute": return ["mic.slash", "mic", "mic.fill"]
    case "playPause": return ["playpause.fill", "play.fill", "pause.fill"]
    case "nextTrack": return ["forward.end.fill", "forward.fill"]
    case "previousTrack": return ["backward.end.fill", "backward.fill"]
    default: return ["speaker.wave.2"]
    }
  }

  private var recommendedSystemActionSymbols: [String] {
    switch draft.action.systemAction {
    case "sleep": return ["moon.fill", "moon"]
    case "lockScreen": return ["lock.fill", "lock"]
    case "screenSaver": return ["sparkles"]
    case "screenshotFull": return ["camera.viewfinder", "camera.fill"]
    case "screenshotSelection": return ["crop", "camera.viewfinder"]
    default: return ["power"]
    }
  }

  // MARK: - アクション種別ごとの入力欄

  /// 「アクションの設定」セクションの見出し。何を入力すればいいかが一目でわかるよう、種別ごとに変える
  private var parameterSectionTitle: String {
    switch draft.action.type {
    case .launchApp, .activateApplication, .quitApplication: return "対象のアプリ"
    case .openURL: return "開くURL"
    case .openFinderFolder: return "対象のフォルダ"
    case .hotkey: return "送信するキー"
    case .typeText: return "入力するテキスト"
    case .setVolume: return "音量"
    case .delay: return "待機時間"
    case .windowLayout: return "配置プリセット"
    case .multiAction: return "実行するステップ"
    case .openFolder, .activateTab, .closeTab, .mediaKey, .systemAction: return "アクションの設定"
    }
  }

  /// 入力例や補足の説明。入力形式が分かりにくいものにのみ表示する
  private var parameterSectionFooter: String? {
    switch draft.action.type {
    case .launchApp, .activateApplication, .quitApplication:
      return "アプリ名（例: Google Chrome）またはBundle ID（例: com.google.Chrome）を入力するか、「アプリを選択...」から選んでください"
    case .openURL:
      return "例: https://www.google.com"
    case .openFinderFolder:
      return "Mac上の絶対パスを入力するか、「フォルダを選択...」から選んでください"
    default:
      return nil
    }
  }

  @ViewBuilder
  private var actionParameterFields: some View {
    switch draft.action.type {
    case .launchApp:
      launchAppFields
    case .openURL:
      TextField("https://example.com", text: targetBinding)
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
    case .activateTab, .closeTab:
      // タブ一覧画面から生成されるアクションのため、この汎用エディタでは編集項目を出さない
      Text("タブ一覧から設定されるアクションです")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .activateApplication, .quitApplication:
      launchAppFields
    case .windowLayout:
      windowLayoutFields
    case .mediaKey, .systemAction:
      Text("「\(selectedActionTitle)」を送信します")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .openFinderFolder:
      openFinderFolderFields
    }
  }

  private var launchAppFields: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("アプリ名 または Bundle ID", text: targetBinding)
      Button("アプリを選択...") {
        isShowingApplicationPicker = true
      }
    }
    .sheet(isPresented: $isShowingApplicationPicker) {
      ApplicationPickerView(
        onSelect: { applyChosenApplication(at: $0.url) },
        onChooseFromFinder: chooseApplication
      )
    }
  }

  private var openFinderFolderFields: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("フォルダのパス", text: targetBinding)
      Button("フォルダを選択...") {
        chooseFolder()
      }
    }
  }

  /// NSOpenPanelでフォルダを選ばせ、パスをtargetへ自動入力する
  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    draft.action.target = url.path
  }

  /// 標準的な場所にないアプリのための代替手段として、NSOpenPanelで.appを選ばせる
  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    applyChosenApplication(at: url)
  }

  /// 選ばれた.appのURLから、Bundle IDまたはアプリ名をtargetへ、表示名をlabelへ反映する
  private func applyChosenApplication(at url: URL) {
    let bundle = Bundle(url: url)
    if let bundleId = bundle?.bundleIdentifier {
      draft.action.target = bundleId
    } else {
      // Bundle IDが取得できない場合は拡張子を除いたアプリ名をフォールバックとして使う
      draft.action.target = url.deletingPathExtension().lastPathComponent
    }
    let applicationName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent
    draft.label = applicationName
    automaticallyNamesButton = true
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
    VStack(alignment: .leading, spacing: 10) {
      Button {
        startRecordingHotkey()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: isRecordingHotkey ? "record.circle.fill" : "keyboard.badge.ellipsis")
          VStack(alignment: .leading, spacing: 2) {
            Text(isRecordingHotkey ? "登録するキーを押してください" : "実際のキー入力を記録")
              .font(.body.weight(.semibold))
            Text(isRecordingHotkey ? recordingHotkeyDescription : recordedHotkeyDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .foregroundStyle(isRecordingHotkey ? Color.primary : Color.accentColor)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(isRecordingHotkey ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor.opacity(isRecordingHotkey ? 0.9 : 0.3), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)

      Text("修飾キー（任意）")
        .font(.caption)
        .foregroundStyle(.secondary)

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

      Text("キー（クリックして選択）")
        .font(.caption)
        .foregroundStyle(.secondary)

      // キー名を直接入力させると存在しないキー名を打ち込みやすく分かりにくいため、
      // 実際のキーボード配列をそのままクリックして選ばせることで登録ミスを防ぐ
      VStack(spacing: 4) {
        keyPickerRow(Self.numberRow)
        keyPickerRow(Self.qwertyRow)
        keyPickerRow(Self.homeRow)
        keyPickerRow(Self.bottomLetterKeys)
        keyPickerRow(Self.extraKeys)
      }
    }
  }

  private var recordedHotkeyDescription: String {
    let keys = draft.action.keys ?? []
    guard !keys.isEmpty else { return "押したキーの組み合わせをそのまま登録します" }
    return "現在: " + keys.map(hotkeyDisplayName).joined(separator: " + ")
  }

  private var recordingHotkeyDescription: String {
    guard !hotkeyRecordingKeys.isEmpty else { return "修飾キーと通常キーを同時に押します" }
    return "検出中: " + hotkeyRecordingKeys.map(hotkeyDisplayName).joined(separator: " + ")
  }

  private func hotkeyDisplayName(_ key: String) -> String {
    switch key {
    case "cmd": return "⌘"
    case "shift": return "⇧"
    case "opt": return "⌥"
    case "ctrl": return "⌃"
    case "return": return "Return"
    case "escape": return "Esc"
    case "delete": return "Delete"
    case "space": return "Space"
    case "tab": return "Tab"
    case "left": return "←"
    case "right": return "→"
    case "up": return "↑"
    case "down": return "↓"
    default: return key.uppercased()
    }
  }

  private func startRecordingHotkey() {
    isRecordingHotkey = true
    hotkeyRecordingKeys = []
    heldHotkeyModifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    hotkeyRecordingGeneration += 1
    installHotkeyMonitor()
  }

  private func stopRecordingHotkey() {
    isRecordingHotkey = false
    removeHotkeyMonitor()
  }

  /// アプリ内イベントはローカルmonitorで消費し、AppKitがmonitorへ渡さない配送経路は
  /// listen-onlyのCGEvent tapで観測する。
  private func installHotkeyMonitor() {
    removeHotkeyMonitor()
    hotkeyKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      guard isRecordingHotkey else { return event }
      observeHotkeyEvent(event)
      // 記録中はイベントを消費し、Cmd+Qなどのメニューショートカットが誤って発火しないようにする
      return event.type == .keyDown ? nil : event
    }
    hotkeyCGEventMonitor.start { event in
      guard isRecordingHotkey else { return }
      observeHotkeyEvent(event)
    }
  }

  private func removeHotkeyMonitor() {
    if let monitor = hotkeyKeyDownMonitor {
      NSEvent.removeMonitor(monitor)
      hotkeyKeyDownMonitor = nil
    }
    hotkeyCGEventMonitor.stop()
    heldHotkeyModifierFlags = []
  }

  private func observeHotkeyEvent(_ event: NSEvent) {
    if event.type == .flagsChanged {
      heldHotkeyModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    } else if event.type == .keyDown {
      recordHotkey(event)
    }
  }

  private func recordHotkey(_ event: NSEvent) {
    guard isRecordingHotkey, let key = recordedKeyName(for: event) else { return }

    // このイベント単体で押されている修飾キー（各フラグは独立してチェックするため、
    // cmd+optのような複数同時押しも正しく両方検出できる）
    // flagsChangedで追跡した状態と、イベント配送とは独立した現在のデバイス状態も合成する。
    // これにより複数修飾キーが同時に変化した直後でもkeyDown側のスナップショット欠落に依存しない。
    let flags = event.modifierFlags
      .union(heldHotkeyModifierFlags)
      .union(NSEvent.modifierFlags)
      .intersection(.deviceIndependentFlagsMask)
    var modifierSet = Set(hotkeyRecordingKeys.filter { modifierKeys.contains($0) })
    if flags.contains(.command) { modifierSet.insert("cmd") }
    if flags.contains(.shift) { modifierSet.insert("shift") }
    if flags.contains(.option) { modifierSet.insert("opt") }
    if flags.contains(.control) { modifierSet.insert("ctrl") }
    // 矢印キーなどはキーリピートで複数回keyDownが発火するため、後続イベントの時点で
    // 一部の修飾キーが（人間の指の動きの誤差で）先に離されていても、記録セッション中に
    // 一度でも検出した修飾キーは失わないようにこれまでの検出結果と合算する
    let modifiers = modifierKeys.filter { modifierSet.contains($0) }
    let existingRegularKeys = hotkeyRecordingKeys.filter { !modifierKeys.contains($0) }
    hotkeyRecordingKeys = modifiers + existingRegularKeys
    if !hotkeyRecordingKeys.contains(key) {
      hotkeyRecordingKeys.append(key)
    }

    hotkeyRecordingGeneration += 1
    let generation = hotkeyRecordingGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      guard generation == hotkeyRecordingGeneration, isRecordingHotkey else { return }
      draft.action.keys = hotkeyRecordingKeys
      stopRecordingHotkey()
    }
  }

  private func recordedKeyName(for event: NSEvent) -> String? {
    // Return/Tab/Space/Delete/Escape/矢印キーは文字を持たない（または制御文字になる）ため、
    // キーボードレイアウトに依存しない仮想キーコードで判定する
    switch Int(event.keyCode) {
    case 36, 76: return "return"    // kVK_Return, kVK_ANSI_KeypadEnter
    case 48: return "tab"           // kVK_Tab
    case 49: return "space"         // kVK_Space
    case 51, 117: return "delete"   // kVK_Delete, kVK_ForwardDelete
    case 53: return "escape"        // kVK_Escape
    case 123: return "left"         // kVK_LeftArrow
    case 124: return "right"        // kVK_RightArrow
    case 125: return "down"         // kVK_DownArrow
    case 126: return "up"           // kVK_UpArrow
    default:
      guard let character = event.charactersIgnoringModifiers?.lowercased(), character.count == 1 else { return nil }
      let supportedCharacters = "abcdefghijklmnopqrstuvwxyz0123456789-=[]\\;',./`"
      return supportedCharacters.contains(character) ? character : nil
    }
  }

  private func keyPickerRow(_ keys: [HotkeyPickerKey]) -> some View {
    HStack(spacing: 4) {
      ForEach(keys) { key in
        let isSelected = keyBinding.wrappedValue == key.keyName
        Button {
          keyBinding.wrappedValue = key.keyName
        } label: {
          Text(key.label)
            .font(.caption2)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.plain)
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
        )
        .layoutPriority(key.widthWeight)
        .frame(minWidth: 22 * key.widthWeight)
      }
    }
  }

  // MARK: - ホットキー選択グリッドのキー定義（US ANSI配列）

  private static let numberRow: [HotkeyPickerKey] = [
    HotkeyPickerKey(label: "`", keyName: "`"),
    HotkeyPickerKey(label: "1", keyName: "1"), HotkeyPickerKey(label: "2", keyName: "2"),
    HotkeyPickerKey(label: "3", keyName: "3"), HotkeyPickerKey(label: "4", keyName: "4"),
    HotkeyPickerKey(label: "5", keyName: "5"), HotkeyPickerKey(label: "6", keyName: "6"),
    HotkeyPickerKey(label: "7", keyName: "7"), HotkeyPickerKey(label: "8", keyName: "8"),
    HotkeyPickerKey(label: "9", keyName: "9"), HotkeyPickerKey(label: "0", keyName: "0"),
    HotkeyPickerKey(label: "-", keyName: "-"), HotkeyPickerKey(label: "=", keyName: "="),
    HotkeyPickerKey(label: "delete", keyName: "delete", widthWeight: 2)
  ]

  private static let qwertyRow: [HotkeyPickerKey] = [
    HotkeyPickerKey(label: "tab", keyName: "tab", widthWeight: 1.5),
    HotkeyPickerKey(label: "Q", keyName: "q"), HotkeyPickerKey(label: "W", keyName: "w"),
    HotkeyPickerKey(label: "E", keyName: "e"), HotkeyPickerKey(label: "R", keyName: "r"),
    HotkeyPickerKey(label: "T", keyName: "t"), HotkeyPickerKey(label: "Y", keyName: "y"),
    HotkeyPickerKey(label: "U", keyName: "u"), HotkeyPickerKey(label: "I", keyName: "i"),
    HotkeyPickerKey(label: "O", keyName: "o"), HotkeyPickerKey(label: "P", keyName: "p"),
    HotkeyPickerKey(label: "[", keyName: "["), HotkeyPickerKey(label: "]", keyName: "]"),
    HotkeyPickerKey(label: "\\", keyName: "\\", widthWeight: 1.5)
  ]

  private static let homeRow: [HotkeyPickerKey] = [
    HotkeyPickerKey(label: "caps", keyName: "capslock", widthWeight: 1.8),
    HotkeyPickerKey(label: "A", keyName: "a"), HotkeyPickerKey(label: "S", keyName: "s"),
    HotkeyPickerKey(label: "D", keyName: "d"), HotkeyPickerKey(label: "F", keyName: "f"),
    HotkeyPickerKey(label: "G", keyName: "g"), HotkeyPickerKey(label: "H", keyName: "h"),
    HotkeyPickerKey(label: "J", keyName: "j"), HotkeyPickerKey(label: "K", keyName: "k"),
    HotkeyPickerKey(label: "L", keyName: "l"), HotkeyPickerKey(label: ";", keyName: ";"),
    HotkeyPickerKey(label: "'", keyName: "'"),
    HotkeyPickerKey(label: "return", keyName: "return", widthWeight: 1.8)
  ]

  private static let bottomLetterKeys: [HotkeyPickerKey] = [
    HotkeyPickerKey(label: "Z", keyName: "z"), HotkeyPickerKey(label: "X", keyName: "x"),
    HotkeyPickerKey(label: "C", keyName: "c"), HotkeyPickerKey(label: "V", keyName: "v"),
    HotkeyPickerKey(label: "B", keyName: "b"), HotkeyPickerKey(label: "N", keyName: "n"),
    HotkeyPickerKey(label: "M", keyName: "m"), HotkeyPickerKey(label: ",", keyName: ","),
    HotkeyPickerKey(label: ".", keyName: "."), HotkeyPickerKey(label: "/", keyName: "/")
  ]

  private static let extraKeys: [HotkeyPickerKey] = [
    HotkeyPickerKey(label: "esc", keyName: "escape", widthWeight: 1.3),
    HotkeyPickerKey(label: "space", keyName: "space", widthWeight: 2.4),
    HotkeyPickerKey(label: "←", keyName: "left"),
    HotkeyPickerKey(label: "↑", keyName: "up"),
    HotkeyPickerKey(label: "↓", keyName: "down"),
    HotkeyPickerKey(label: "→", keyName: "right")
  ]

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

  private var labelBinding: Binding<String> {
    Binding(
      get: { draft.label },
      set: {
        draft.label = $0
        automaticallyNamesButton = false
      }
    )
  }

  // MARK: - ボタン名の自動命名

  /// 定型文からボタン名を作るときに残す最大文字数
  private static let maximumAutomaticNameLength = 12

  /// 自動命名が有効な間だけ、選んだアクションの内容に合わせてボタン名を決め直す
  private func prepareAppearance() {
    guard automaticallyNamesButton, let name = automaticButtonName() else { return }
    draft.label = name
  }

  /// 現在のアクション内容にふさわしいボタン名を返す（名前を決められない場合はnil）
  private func automaticButtonName() -> String? {
    switch draft.action.type {
    case .launchApp, .activateApplication:
      return draft.action.target.flatMap { applicationDisplayName(from: $0) } ?? selectedActionChoice?.title
    case .quitApplication:
      guard let applicationName = draft.action.target.flatMap({ applicationDisplayName(from: $0) }) else {
        return selectedActionChoice?.title
      }
      return "\(applicationName)を終了"
    case .openURL:
      return websiteDisplayName(from: draft.action.target) ?? selectedActionChoice?.title
    case .hotkey:
      let keys = draft.action.keys ?? []
      guard !keys.isEmpty else { return selectedActionChoice?.title }
      return keys.map(hotkeyDisplayName).joined(separator: " + ")
    case .typeText:
      return textDisplayName(from: draft.action.text) ?? selectedActionChoice?.title
    case .setVolume:
      // 既定値が二重定義にならないよう、入力欄と同じBindingから現在値を取る
      return "音量 \(volumeBinding.wrappedValue)%"
    case .delay:
      return "待機 \(msBinding.wrappedValue)ms"
    case .windowLayout:
      guard let preset = draft.action.preset.flatMap({ WindowLayoutPreset(rawValue: $0) }) else {
        return selectedActionChoice?.title
      }
      return preset.displayName
    case .openFinderFolder:
      return folderDisplayName(from: draft.action.target) ?? selectedActionChoice?.title
    case .multiAction, .openFolder, .mediaKey, .systemAction:
      return selectedActionChoice?.title
    case .activateTab, .closeTab:
      // タブ一覧画面から作られる際にタブのタイトルがラベルへ入るため、ここでは上書きしない
      return nil
    }
  }

  /// URLから「github.com」のような表示名を作る（先頭のwww.は省く）
  private func websiteDisplayName(from target: String?) -> String? {
    guard let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    // スキームを省略して入力されたURLでもホスト名を取り出せるようにする
    let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let host = URL(string: normalized)?.host else { return trimmed }
    let wwwPrefix = "www."
    return host.hasPrefix(wwwPrefix) ? String(host.dropFirst(wwwPrefix.count)) : host
  }

  /// 定型文の先頭だけを取り出してボタン名にする
  private func textDisplayName(from text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    // 複数行の定型文でもボタン名は1行に収める
    let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
    guard firstLine.count > Self.maximumAutomaticNameLength else { return firstLine }
    return String(firstLine.prefix(Self.maximumAutomaticNameLength)) + "…"
  }

  /// フォルダのパスから末尾のフォルダ名を取り出す
  private func folderDisplayName(from target: String?) -> String? {
    guard let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    let folderName = URL(fileURLWithPath: trimmed).lastPathComponent
    return folderName.isEmpty ? trimmed : folderName
  }

  private func applicationDisplayName(from target: String) -> String? {
    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.contains("/") {
      return URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
    }
    if trimmed.lowercased().hasSuffix(".app") {
      return String(trimmed.dropLast(4))
    }
    if trimmed.contains("."), let bundleName = trimmed.split(separator: ".").last {
      return String(bundleName)
    }
    return trimmed
  }

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
    case .multiAction, .openFolder, .activateTab, .closeTab, .activateApplication, .windowLayout, .mediaKey,
         .quitApplication, .openFinderFolder, .systemAction:
      // マルチアクションのステップには一部の高度なアクション・入れ子のマルチアクションを登録できない
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
