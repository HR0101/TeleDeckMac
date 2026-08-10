//
//  TabInspector.swift
//  TeleDeckMac
//
//  Google Chrome / SafariのタブをAppleScript経由で取得・操作する。
//

import Foundation

final class TabInspector {

  enum TabError: LocalizedError {
    case unsupportedBrowser(String)
    case tabNotSpecified
    case appleScriptFailed(String)

    var errorDescription: String? {
      switch self {
      case .unsupportedBrowser(let name):
        return "対応していないブラウザです: \(name)"
      case .tabNotSpecified:
        return "対象のタブが指定されていません"
      case .appleScriptFailed(let message):
        return "AppleScriptの実行に失敗しました: \(message)"
      }
    }
  }

  /// 対応しているブラウザ名の一覧
  private static let supportedBrowsers = ["Google Chrome", "Safari"]
  /// tabId = winIndex * tabIdWindowMultiplier + tabIndex という合成規則の係数
  private static let tabIdWindowMultiplier = 1000
  /// AppleScript側の出力を項目ごとに区切る区切り文字（タイトルにカンマが含まれてもパースが壊れないようにするため）
  private static let fieldSeparator = "|||"

  // MARK: - タブ一覧取得

  /// Chrome・Safari両方のタブを取得して集計する。片方が未起動などで失敗しても、もう片方の結果は返す
  func getAllTabs(completion: @escaping ([TabInfo]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      var allTabs: [TabInfo] = []
      for browser in Self.supportedBrowsers {
        allTabs.append(contentsOf: self.fetchTabs(of: browser))
      }
      DispatchQueue.main.async {
        completion(allTabs)
      }
    }
  }

  /// 指定ブラウザのタブ一覧を取得する。ブラウザが未起動などでAppleScriptが失敗した場合は例外にせず0件として扱う
  private func fetchTabs(of browser: String) -> [TabInfo] {
    guard let script = Self.listTabsScript(for: browser),
          let appleScript = NSAppleScript(source: script) else {
      return []
    }

    var errorDict: NSDictionary?
    let result = appleScript.executeAndReturnError(&errorDict)

    if errorDict != nil {
      return []
    }

    guard let output = result.stringValue else { return [] }
    return parseTabs(from: output, browser: browser)
  }

  private func parseTabs(from output: String, browser: String) -> [TabInfo] {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    var tabs: [TabInfo] = []

    for line in lines {
      let parts = line.components(separatedBy: Self.fieldSeparator)
      guard parts.count >= 4,
            let winIndex = Int(parts[0]),
            let tabIndex = Int(parts[1]) else {
        continue
      }
      // タイトル自体に区切り文字が含まれるケースに備え、4番目以降を結合し直す
      let title = parts[3...].joined(separator: Self.fieldSeparator)
      let isActive = parts[2] == "true"
      let tabId = winIndex * Self.tabIdWindowMultiplier + tabIndex
      tabs.append(TabInfo(browser: browser, tabId: tabId, title: title, active: isActive))
    }

    return tabs
  }

  // MARK: - タブ操作

  func activateTab(browser: String?, tabId: Int?, completion: @escaping (Result<Void, Error>) -> Void) {
    performTabAction(browser: browser, tabId: tabId, scriptBuilder: Self.activateScript, completion: completion)
  }

  func closeTab(browser: String?, tabId: Int?, completion: @escaping (Result<Void, Error>) -> Void) {
    performTabAction(browser: browser, tabId: tabId, scriptBuilder: Self.closeScript, completion: completion)
  }

  private func performTabAction(
    browser: String?,
    tabId: Int?,
    scriptBuilder: @escaping (String, Int, Int) -> String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let browser, Self.supportedBrowsers.contains(browser) else {
      completion(.failure(TabError.unsupportedBrowser(browser ?? "(未指定)")))
      return
    }
    guard let tabId else {
      completion(.failure(TabError.tabNotSpecified))
      return
    }

    let winIndex = tabId / Self.tabIdWindowMultiplier
    let tabIndex = tabId % Self.tabIdWindowMultiplier
    let script = scriptBuilder(browser, winIndex, tabIndex)

    DispatchQueue.global(qos: .userInitiated).async {
      guard let appleScript = NSAppleScript(source: script) else {
        DispatchQueue.main.async {
          completion(.failure(TabError.appleScriptFailed("スクリプトの生成に失敗しました")))
        }
        return
      }

      var errorDict: NSDictionary?
      appleScript.executeAndReturnError(&errorDict)

      DispatchQueue.main.async {
        if let errorDict {
          let message = errorDict[NSAppleScript.errorMessage] as? String ?? "不明なエラー"
          completion(.failure(TabError.appleScriptFailed(message)))
        } else {
          completion(.success(()))
        }
      }
    }
  }

  // MARK: - AppleScriptソース生成

  /// タブ一覧を「ウィンドウ番号|||タブ番号|||アクティブか|||タイトル」の行の並びとして取得するスクリプト
  private static func listTabsScript(for browser: String) -> String? {
    switch browser {
    case "Google Chrome":
      return """
      tell application "Google Chrome"
        set output to ""
        set winIndex to 0
        repeat with w in windows
          set winIndex to winIndex + 1
          set tabIndex to 0
          repeat with t in tabs of w
            set tabIndex to tabIndex + 1
            set isActive to (tabIndex is (active tab index of w))
            set output to output & winIndex & "\(fieldSeparator)" & tabIndex & "\(fieldSeparator)" & isActive & "\(fieldSeparator)" & (title of t) & linefeed
          end repeat
        end repeat
        return output
      end tell
      """
    case "Safari":
      return """
      tell application "Safari"
        set output to ""
        set winIndex to 0
        repeat with w in windows
          set winIndex to winIndex + 1
          set tabIndex to 0
          set activeTab to current tab of w
          repeat with t in tabs of w
            set tabIndex to tabIndex + 1
            set isActive to (t is activeTab)
            set output to output & winIndex & "\(fieldSeparator)" & tabIndex & "\(fieldSeparator)" & isActive & "\(fieldSeparator)" & (name of t) & linefeed
          end repeat
        end repeat
        return output
      end tell
      """
    default:
      return nil
    }
  }

  /// 対象タブをアクティブ化し、そのウィンドウを最前面にするスクリプト
  private static func activateScript(browser: String, winIndex: Int, tabIndex: Int) -> String {
    switch browser {
    case "Google Chrome":
      return """
      tell application "Google Chrome"
        set targetWindow to window \(winIndex)
        set active tab index of targetWindow to \(tabIndex)
        set index of targetWindow to 1
        activate
      end tell
      """
    case "Safari":
      return """
      tell application "Safari"
        set targetWindow to window \(winIndex)
        set current tab of targetWindow to tab \(tabIndex) of targetWindow
        set index of targetWindow to 1
        activate
      end tell
      """
    default:
      return ""
    }
  }

  /// 対象タブを閉じるスクリプト
  private static func closeScript(browser: String, winIndex: Int, tabIndex: Int) -> String {
    switch browser {
    case "Google Chrome":
      return """
      tell application "Google Chrome"
        close tab \(tabIndex) of window \(winIndex)
      end tell
      """
    case "Safari":
      return """
      tell application "Safari"
        close tab \(tabIndex) of window \(winIndex)
      end tell
      """
    default:
      return ""
    }
  }
}
