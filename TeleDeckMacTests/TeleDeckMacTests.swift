//
//  TeleDeckMacTests.swift
//  TeleDeckMacTests
//
//  Created by hara ryuto   on 2026/07/12.
//

import Foundation
import Testing
@testable import TeleDeckMac

@MainActor
struct TeleDeckMacTests {

    @Test func createFinderFolderCreatesFolderInsideSelectedDestination() async throws {
        let parentURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parentURL) }

        let result = await execute(ActionPayload(
            type: .createFinderFolder,
            target: parentURL.path,
            folderName: "TeleDeck Created Folder"
        ))

        if case .failure(let error) = result {
            Issue.record("Folder creation failed: \(error.localizedDescription)")
        }
        let createdURL = parentURL.appendingPathComponent("TeleDeck Created Folder", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: createdURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func createFinderFolderRejectsExistingFolder() async throws {
        let parentURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let existingURL = parentURL.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: false)

        let result = await execute(ActionPayload(
            type: .createFinderFolder,
            target: parentURL.path,
            folderName: "Existing"
        ))

        guard case .failure(let error) = result,
              let executionError = error as? ActionExecutor.ExecutionError else {
            Issue.record("An existing folder should be rejected")
            return
        }
        guard case .folderAlreadyExists(let path) = executionError else {
            Issue.record("Expected folderAlreadyExists, got \(executionError)")
            return
        }
        #expect(path == existingURL.path)
    }

    @Test func createFinderFolderRejectsPathComponentsInName() async throws {
        let parentURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parentURL) }

        let result = await execute(ActionPayload(
            type: .createFinderFolder,
            target: parentURL.path,
            folderName: "nested/folder"
        ))

        guard case .failure(let error) = result,
              let executionError = error as? ActionExecutor.ExecutionError else {
            Issue.record("A folder name containing a path separator should be rejected")
            return
        }
        guard case .invalidFolderName = executionError else {
            Issue.record("Expected invalidFolderName, got \(executionError)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: parentURL.appendingPathComponent("nested").path))
    }

    private func execute(_ action: ActionPayload) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            ActionExecutor().execute(action) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeleDeckMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

}
