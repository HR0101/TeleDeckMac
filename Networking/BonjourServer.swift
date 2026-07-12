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

  private var listener: NWListener?
  private var activeConnection: NWConnection?

  private let pairingManager: PairingManager
  private let actionExecutor: ActionExecutor
  private let tabInspector = TabInspector()
  private let foregroundAppMonitor = ForegroundAppMonitor()
  private let trackpadController = TrackpadController()
  private let profileStore: ProfileStore

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
      case .failure(let error):
        response = AckMessage(requestId: request.requestId, success: false, errorMessage: error.localizedDescription)
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

  private func sendProfileSync(on connection: NWConnection) {
    send(ProfileSyncMessage(profiles: profileStore.profiles, activeProfileId: profileStore.activeProfileId), on: connection)
  }

  private func broadcastProfileSync(profiles: [ProfileConfig], activeProfileId: UUID) {
    guard let connection = activeConnection, connectedDeviceName != nil else { return }
    send(ProfileSyncMessage(profiles: profiles, activeProfileId: activeProfileId), on: connection)
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
