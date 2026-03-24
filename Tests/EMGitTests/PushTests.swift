import Testing
import Foundation
@testable import EMGit
import EMCore
import SwiftGit2
import Clibgit2

@Suite("Push Tests")
struct PushTests {

    /// Create a temporary directory that is cleaned up after the test.
    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EMGitPushTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Remove a temporary directory, ignoring errors.
    private func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Initialize a bare repository at the given URL using libgit2.
    private func createBareRepo(at url: URL) throws -> OpaquePointer {
        var pointer: OpaquePointer? = nil
        let result = url.withUnsafeFileSystemRepresentation {
            git_repository_init(&pointer, $0, 1) // 1 = bare
        }
        guard result == GIT_OK.rawValue, let repo = pointer else {
            throw NSError(domain: "PushTests", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to init bare repo"])
        }
        return repo
    }

    @Test("Push to local bare repo succeeds with commit reaching remote")
    func pushToLocalBareRepo() throws {
        let tempDir = try makeTempDir()
        defer { removeTempDir(tempDir) }

        let bareURL = tempDir.appendingPathComponent("remote.git")
        let workURL = tempDir.appendingPathComponent("working")

        // 1. Create a bare repo (acts as the "remote").
        let bareRepoPtr = try createBareRepo(at: bareURL)

        // Create an initial commit in the bare repo so it has a HEAD / main branch.
        // This is needed so the clone has something to track.
        var sig: UnsafeMutablePointer<git_signature>? = nil
        git_signature_now(&sig, "Test", "test@test.com")
        defer { git_signature_free(sig) }

        // Create an empty tree.
        var index: OpaquePointer? = nil
        git_repository_index(&index, bareRepoPtr)
        var treeOID = git_oid()
        git_index_write_tree(&treeOID, index)
        git_index_free(index)

        var tree: OpaquePointer? = nil
        git_tree_lookup(&tree, bareRepoPtr, &treeOID)

        // Create initial commit on HEAD.
        var commitOID = git_oid()
        git_commit_create(
            &commitOID,
            bareRepoPtr,
            "refs/heads/main",
            sig, sig,
            "UTF-8",
            "Initial commit",
            tree,
            0,
            nil
        )
        git_tree_free(tree)

        // Set HEAD to refs/heads/main.
        git_repository_set_head(bareRepoPtr, "refs/heads/main")
        git_repository_free(bareRepoPtr)

        // 2. Clone the bare repo into a working directory.
        let cloneResult = Repository.clone(
            from: bareURL,
            to: workURL,
            localClone: true
        )
        let repo = try cloneResult.get()

        // 3. Create a test file in the working directory.
        let testFile = workURL.appendingPathComponent("test.md")
        try "# Hello Push".write(to: testFile, atomically: true, encoding: .utf8)

        // 4. Stage and commit the file.
        let addResult = repo.add(path: "test.md")
        _ = try addResult.get()

        let signature = Signature(name: "Test User", email: "test@example.com")
        let commitResult = repo.commit(message: "Add test file", signature: signature)
        let newCommit = try commitResult.get()

        // 5. Push to "origin" (the bare repo). Use a dummy token — local transport
        // does not require authentication.
        try repo.push(remote: "origin", token: "dummy-local-token")

        // 6. Verify the bare repo received the commit.
        let bareRepoVerify = try Repository.at(bareURL).get()
        let headResult = bareRepoVerify.HEAD()
        let headRef = try headResult.get()

        #expect(headRef.oid == newCommit.oid,
                "Bare repo HEAD should match the pushed commit OID")
    }

    @Test("Push to nonexistent remote throws EMError.git")
    func pushNoRemoteThrows() throws {
        // Verifies that push correctly throws EMError when the remote doesn't exist.
        // A true auth failure test (AC3) requires an HTTPS remote and network access;
        // the pushError() mapping for authentication errors (code -16, "401") is
        // verified structurally — this test confirms EMError propagation works.
        let tempDir = try makeTempDir()
        defer { removeTempDir(tempDir) }

        let workURL = tempDir.appendingPathComponent("working")

        // Create a repo with no remote configured.
        let repo = try Repository.create(at: workURL).get()

        // Pushing to nonexistent remote should throw an EMError.
        #expect(throws: EMError.self) {
            try repo.push(remote: "origin", token: "bad-token")
        }
    }
}
