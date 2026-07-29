//
//  BonjourServer.swift
//  TeleDeckMac
//
//  iPadからのWebSocket接続を受け付け、Bonjourで自身を公開するサーバー。
//

import Foundation
import AppKit
import Network
import Observation

@Observable
final class BonjourServer {
  private(set) var isRunning = false
  private(set) var connectedDeviceName: String?

  /// 直近に実行したアクションの結果。失敗の記録がどこにも残らないと
  /// 「押したのに動かない」原因をMac側から追えないため、メニューバーへ出せるよう保持する
  private(set) var lastExecutionLog: ExecutionLogEntry?

  struct ExecutionLogEntry {
    let actionType: ActionType
    let succeeded: Bool
    let errorMessage: String?
    let timestamp: Date

    /// メニューバーに1行で表示するための説明
    var summary: String {
      let name = Self.displayName(for: actionType)
      guard !succeeded else { return "\(name)を実行しました" }
      return "\(name): \(errorMessage ?? "失敗しました")"
    }

    private static func displayName(for type: ActionType) -> String {
      switch type {
      case .launchApp: return "アプリを起動"
      case .openURL: return "URLを開く"
      case .hotkey: return "ショートカット"
      case .typeText: return "文字入力"
      case .setVolume: return "音量変更"
      case .multiAction: return "マルチアクション"
      case .delay: return "待機"
      case .openFolder: return "フォルダーを開く"
      case .activateTab: return "タブを切り替え"
      case .closeTab: return "タブを閉じる"
      case .activateApplication: return "アプリを切り替え"
      case .windowLayout: return "ウィンドウ配置"
      case .mediaKey: return "メディアキー"
      case .quitApplication: return "アプリを終了"
      case .openFinderFolder: return "Finderで開く"
      case .systemAction: return "システム操作"
      }
    }
  }

  private var listener: NWListener?
  private var activeConnection: NWConnection?

  private let pairingManager: PairingManager
  private let actionExecutor: ActionExecutor
  private let tabInspector = TabInspector()
  private let foregroundAppMonitor = ForegroundAppMonitor()
  private let trackpadController = TrackpadController()
  private let profileStore: ProfileStore
  private let clipboardHistoryStore = ClipboardHistoryStore()
  private var applicationIconCache: [String: Data] = [:]
  /// ホスト名(favicon取得先)ごとのキャッシュ。取得失敗時は空のDataを入れて無限リトライを防ぐ
  private var websiteIconCache: [String: Data] = [:]
  private var pendingWebsiteIconFetches: Set<String> = []

  private static let serviceType = "_teledeck._tcp"

  init(pairingManager: PairingManager, actionExecutor: ActionExecutor, profileStore: ProfileStore) {
    self.pairingManager = pairingManager
    self.actionExecutor = actionExecutor
    self.profileStore = profileStore

    // プロファイル自動切替の判定はMac自身が持つprofileStoreで完結させる
    foregroundAppMonitor.onForegroundAppChanged = { [weak self] bundleId in
      self?.profileStore.activateProfile(matchingBundleId: bundleId)
    }
    foregroundAppMonitor.start()

    // profileStoreが変化したら（自動切替・Mac側編集・iPad側からの反映依頼のいずれでも）iPadへ同期する
    profileStore.onChange = { [weak self] profiles, activeProfileId in
      self?.broadcastProfileSync(profiles: profiles, activeProfileId: activeProfileId)
    }

    // コピー履歴が変化したら（新規コピー検知のたび）接続中のiPadへ同期する
    clipboardHistoryStore.onChange = { [weak self] entries in
      self?.broadcastClipboardHistory(entries: entries)
    }
    clipboardHistoryStore.start()
  }

  /// サーバーを起動し、Bonjourで公開を開始する
  func start() {
    do {
      let webSocketOptions = NWProtocolWebSocket.Options()
      webSocketOptions.autoReplyPing = true

      let parameters = NWParameters.tcp
      parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

      let newListener = try NWListener(using: parameters)
      newListener.service = NWListener.Service(
        name: Host.current().localizedName ?? "TeleDeckMac",
        type: Self.serviceType
      )

      newListener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          self?.isRunning = true
        case .failed, .cancelled:
          self?.isRunning = false
        default:
          break
        }
      }

      newListener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }

      newListener.start(queue: .main)
      listener = newListener
    } catch {
      print("サーバーの起動に失敗しました: \(error.localizedDescription)")
      isRunning = false
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    activeConnection?.cancel()
    activeConnection = nil
    isRunning = false
    connectedDeviceName = nil
    foregroundAppMonitor.stop()
    clipboardHistoryStore.stop()
  }

  // MARK: - 接続処理

  private func accept(_ connection: NWConnection) {
    // フェーズ1は同時1台のみ対応。既存接続があれば切断して新しい接続に置き換える
    activeConnection?.cancel()
    activeConnection = connection

    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.handleDisconnect(connection)
      default:
        break
      }
    }

    connection.start(queue: .main)
    receiveNextMessage(on: connection)
  }

  private func handleDisconnect(_ connection: NWConnection) {
    guard connection === activeConnection else { return }
    activeConnection = nil
    connectedDeviceName = nil
  }

  private func receiveNextMessage(on connection: NWConnection) {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }

      if let error {
        print("受信エラー: \(error.localizedDescription)")
        return
      }

      if let data, !data.isEmpty {
        self.handleIncoming(data: data, connection: connection)
      }

      if connection.state == .ready {
        self.receiveNextMessage(on: connection)
      }
    }
  }

  // MARK: - メッセージ処理

  private func handleIncoming(data: Data, connection: NWConnection) {
    do {
      let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
      switch envelope.type {
      case "pair":
        let request = try JSONDecoder().decode(PairMessage.self, from: data)
        handlePair(request, on: connection)
      case "resumeSession":
        let request = try JSONDecoder().decode(ResumeSessionMessage.self, from: data)
        handleResumeSession(request, on: connection)
      case "execute":
        let request = try JSONDecoder().decode(ExecuteMessage.self, from: data)
        handleExecute(request, on: connection)
      case "getTabs":
        handleGetTabs(on: connection)
      case "getApplications":
        handleGetApplications(on: connection)
      case "pickFolder":
        handlePickFolder(on: connection)
      case "updateProfiles":
        let request = try JSONDecoder().decode(UpdateProfilesMessage.self, from: data)
        profileStore.replaceAll(profiles: request.profiles, activeProfileId: request.activeProfileId)
      case "trackpadMove":
        let request = try JSONDecoder().decode(TrackpadMoveMessage.self, from: data)
        guard connectedDeviceName != nil else { return }
        trackpadController.move(dx: request.dx, dy: request.dy)
      case "trackpadClick":
        let request = try JSONDecoder().decode(TrackpadClickMessage.self, from: data)
        guard connectedDeviceName != nil else { return }
        trackpadController.click(button: request.button)
      case "trackpadScroll":
        let request = try JSONDecoder().decode(TrackpadScrollMessage.self, from: data)
        guard connectedDeviceName != nil else { return }
        trackpadController.scroll(dx: request.dx, dy: request.dy)
      case "getClipboardHistory":
        guard connectedDeviceName != nil else { return }
        send(ClipboardHistoryMessage(items: clipboardHistoryStore.networkEntries), on: connection)
      case "pasteClipboardItem":
        let request = try JSONDecoder().decode(PasteClipboardItemMessage.self, from: data)
        handlePasteClipboardItem(request, on: connection)
      default:
        print("未知のメッセージ種別を受信しました: \(envelope.type)")
      }
    } catch {
      print("メッセージの解析に失敗しました: \(error.localizedDescription)")
    }
  }

  private func handlePair(_ request: PairMessage, on connection: NWConnection) {
    let result = pairingManager.verify(pin: request.pin, deviceName: request.deviceName)
    if result.success {
      connectedDeviceName = request.deviceName
    }
    let response = PairResultMessage(success: result.success, token: result.token, errorMessage: result.errorMessage)
    send(response, on: connection)
    if result.success {
      sendProfileSync(on: connection)
      send(ClipboardHistoryMessage(items: clipboardHistoryStore.networkEntries), on: connection)
    }
  }

  private func handleResumeSession(_ request: ResumeSessionMessage, on connection: NWConnection) {
    guard pairingManager.verifyResume(token: request.token) else {
      let response = PairResultMessage(success: false, token: nil, errorMessage: "セッションが無効です。PINで再ペアリングしてください")
      send(response, on: connection)
      return
    }
    connectedDeviceName = pairingManager.trustedDeviceName
    let response = PairResultMessage(success: true, token: request.token, errorMessage: nil)
    send(response, on: connection)
    sendProfileSync(on: connection)
    send(ClipboardHistoryMessage(items: clipboardHistoryStore.networkEntries), on: connection)
  }

  private func handleExecute(_ request: ExecuteMessage, on connection: NWConnection) {
    // ペアリング未完了の接続からのアクション実行は拒否する
    guard connectedDeviceName != nil else {
      let response = AckMessage(requestId: request.requestId, success: false, errorMessage: "ペアリングが完了していません")
      send(response, on: connection)
      return
    }

    let completion: (Result<Void, Error>) -> Void = { [weak self] result in
      let response: AckMessage
      switch result {
      case .success:
        response = AckMessage(requestId: request.requestId, success: true)
        self?.recordExecution(type: request.action.type, succeeded: true, errorMessage: nil)
      case .failure(let error):
        response = AckMessage(requestId: request.requestId, success: false, errorMessage: error.localizedDescription)
        self?.recordExecution(type: request.action.type, succeeded: false, errorMessage: error.localizedDescription)
      }
      self?.send(response, on: connection)
    }

    switch request.action.type {
    case .activateTab:
      tabInspector.activateTab(browser: request.action.browser, tabId: request.action.tabId, completion: completion)
    case .closeTab:
      tabInspector.closeTab(browser: request.action.browser, tabId: request.action.tabId, completion: completion)
    case .activateApplication:
      activateApplication(bundleIdentifier: request.action.target, completion: completion)
    default:
      actionExecutor.execute(request.action, completion: completion)
    }
  }

  /// 直近の実行結果を記録する。UIから参照するプロパティのためメインスレッドで更新する
  private func recordExecution(type: ActionType, succeeded: Bool, errorMessage: String?) {
    DispatchQueue.main.async { [weak self] in
      self?.lastExecutionLog = ExecutionLogEntry(
        actionType: type,
        succeeded: succeeded,
        errorMessage: errorMessage,
        timestamp: Date()
      )
    }
  }

  private func handleGetTabs(on connection: NWConnection) {
    tabInspector.getAllTabs { [weak self] tabs in
      guard let self else { return }
      self.send(TabsListMessage(tabs: tabs, applications: self.runningApplications()), on: connection)
    }
  }

  private func handleGetApplications(on connection: NWConnection) {
    let applications = runningApplications()
    print("起動中アプリ一覧を送信: \(applications.count)件")
    send(ApplicationsListMessage(applications: applications), on: connection)
  }

  private func handlePickFolder(on connection: NWConnection) {
    guard connectedDeviceName != nil else {
      send(FolderSelectionMessage(path: nil), on: connection)
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let panel = NSOpenPanel()
      panel.title = "TeleDeckで開くフォルダーを選択"
      panel.prompt = "選択"
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.begin { response in
        let path = response == .OK ? panel.url?.path : nil
        self.send(FolderSelectionMessage(path: path), on: connection)
      }
    }
  }

  private func runningApplications() -> [MacApplicationInfo] {
    NSWorkspace.shared.runningApplications
      .filter { application in
        application.activationPolicy == .regular
          && application.bundleIdentifier != Bundle.main.bundleIdentifier
      }
      .compactMap { application -> MacApplicationInfo? in
        guard let bundleIdentifier = application.bundleIdentifier,
              let name = application.localizedName else { return nil }
        return MacApplicationInfo(
          bundleIdentifier: bundleIdentifier,
          name: name,
          active: application.isActive,
          iconPNGData: pngData(for: application.icon)
        )
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func pngData(for icon: NSImage?) -> Data? {
    guard let icon else { return nil }

    let targetSize = NSSize(width: 64, height: 64)
    let resizedIcon = NSImage(size: targetSize)
    resizedIcon.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    icon.draw(
      in: NSRect(origin: .zero, size: targetSize),
      from: NSRect(origin: .zero, size: icon.size),
      operation: .copy,
      fraction: 1
    )
    resizedIcon.unlockFocus()

    guard let tiffData = resizedIcon.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
  }

  private func activateApplication(
    bundleIdentifier: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let bundleIdentifier else {
      completion(.failure(NSError(
        domain: "TeleDeckMac",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "アプリケーションが指定されていません"]
      )))
      return
    }

    let options: NSApplication.ActivationOptions = [.activateAllWindows, .activateIgnoringOtherApps]

    if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
      if application.isHidden {
        application.unhide()
      }
      if application.activate(options: options) {
        print("アプリを前面化: \(bundleIdentifier)")
        completion(.success(()))
        return
      }
    }

    // 実行中アプリのactivateが失敗した場合や、一覧取得後に終了していた場合は、
    // LaunchServices経由でアプリを開き直して前面化する。
    guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
      completion(.failure(NSError(
        domain: "TeleDeckMac",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "アプリケーションが見つかりません: \(bundleIdentifier)"]
      )))
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
      if let error {
        completion(.failure(error))
      } else if let application {
        _ = application.activate(options: options)
        print("アプリを開いて前面化: \(bundleIdentifier)")
        completion(.success(()))
      } else {
        completion(.failure(NSError(
          domain: "TeleDeckMac",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "アプリケーションを前面化できませんでした"]
        )))
      }
    }
  }

  private func handlePasteClipboardItem(_ request: PasteClipboardItemMessage, on connection: NWConnection) {
    // クリップボードへの書き込み・貼り付けは機微な操作のため、ペアリング済みの接続のみ許可する
    guard connectedDeviceName != nil else {
      let response = AckMessage(requestId: request.itemId.uuidString, success: false, errorMessage: "ペアリングが完了していません")
      send(response, on: connection)
      return
    }

    clipboardHistoryStore.pasteItem(id: request.itemId) { [weak self] result in
      switch result {
      case .success:
        self?.actionExecutor.execute(ActionPayload(type: .hotkey, keys: ["cmd", "v"])) { pasteResult in
          let response: AckMessage
          switch pasteResult {
          case .success:
            response = AckMessage(requestId: request.itemId.uuidString, success: true)
          case .failure(let error):
            response = AckMessage(requestId: request.itemId.uuidString, success: false, errorMessage: error.localizedDescription)
          }
          self?.send(response, on: connection)
        }
      case .failure(let error):
        let response = AckMessage(requestId: request.itemId.uuidString, success: false, errorMessage: error.localizedDescription)
        self?.send(response, on: connection)
      }
    }
  }

  private func broadcastClipboardHistory(entries: [ClipboardHistoryEntry]) {
    guard let connection = activeConnection, connectedDeviceName != nil else { return }
    send(ClipboardHistoryMessage(items: entries), on: connection)
  }

  private func sendProfileSync(on connection: NWConnection) {
    send(
      ProfileSyncMessage(
        profiles: profilesWithApplicationIcons(profileStore.profiles),
        activeProfileId: profileStore.activeProfileId
      ),
      on: connection
    )
  }

  private func broadcastProfileSync(profiles: [ProfileConfig], activeProfileId: UUID) {
    guard let connection = activeConnection, connectedDeviceName != nil else { return }
    send(
      ProfileSyncMessage(
        profiles: profilesWithApplicationIcons(profiles),
        activeProfileId: activeProfileId
      ),
      on: connection
    )
  }

  private func profilesWithApplicationIcons(_ profiles: [ProfileConfig]) -> [ProfileConfig] {
    var enrichedProfiles = profiles
    for profileIndex in enrichedProfiles.indices {
      for buttonIndex in enrichedProfiles[profileIndex].buttons.indices {
        let action = enrichedProfiles[profileIndex].buttons[buttonIndex].action
        switch action.type {
        case .launchApp:
          guard let target = action.target, !target.isEmpty else {
            enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = nil
            continue
          }
          enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = applicationIconData(for: target)
        case .openURL:
          guard let target = action.target, let host = faviconHost(for: target) else {
            enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = nil
            continue
          }
          if let cached = websiteIconCache[host], !cached.isEmpty {
            enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = cached
          } else {
            enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = nil
            if websiteIconCache[host] == nil {
              fetchWebsiteIcon(host: host)
            }
          }
        default:
          enrichedProfiles[profileIndex].buttons[buttonIndex].applicationIconPNGData = nil
        }
      }
    }
    return enrichedProfiles
  }

  /// "https://example.com/path" のようなURL文字列からfavicon取得用のホスト名を取り出す。
  /// スキームが省略された入力（例: "example.com"）にも https:// を補って対応する
  private func faviconHost(for target: String) -> String? {
    if let host = URL(string: target)?.host {
      return host
    }
    return URL(string: "https://\(target)")?.host
  }

  /// Googleのfaviconサービス経由でサイトのアイコンを取得し、キャッシュに保存後iPadへ再同期する。
  /// 取得に失敗した場合も空のDataをキャッシュし、同期のたびに再取得を繰り返さないようにする
  private func fetchWebsiteIcon(host: String) {
    guard !pendingWebsiteIconFetches.contains(host) else { return }
    pendingWebsiteIconFetches.insert(host)

    guard let faviconURL = URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)") else {
      pendingWebsiteIconFetches.remove(host)
      return
    }

    URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        self.pendingWebsiteIconFetches.remove(host)
        self.websiteIconCache[host] = data ?? Data()
        guard let data, !data.isEmpty else { return }
        self.broadcastProfileSync(profiles: self.profileStore.profiles, activeProfileId: self.profileStore.activeProfileId)
      }
    }.resume()
  }

  private func applicationIconData(for target: String) -> Data? {
    let cacheKey = target.lowercased()
    if let cached = applicationIconCache[cacheKey] {
      return cached
    }
    guard let applicationURL = applicationURL(for: target) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    guard let data = pngData(for: icon) else { return nil }
    applicationIconCache[cacheKey] = data
    return data
  }

  private func applicationURL(for target: String) -> URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
      return url
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
        return URL(fileURLWithPath: candidate)
      }
    }
    return nil
  }

  private func send<T: Encodable>(_ message: T, on connection: NWConnection) {
    do {
      let data = try JSONEncoder().encode(message)
      let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
      let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
      connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
        if let error {
          print("送信エラー: \(error.localizedDescription)")
        }
      })
    } catch {
      print("メッセージのエンコードに失敗しました: \(error.localizedDescription)")
    }
  }
}
