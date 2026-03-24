import Testing
@testable import EMGit
import EMCore

@Suite("EMGit Tests")
struct EMGitTests {
    @Test("GitHubRepository is Identifiable and Hashable")
    func repositoryConformance() {
        let repo = GitHubRepository(
            id: 1,
            fullName: "user/repo",
            name: "repo",
            ownerLogin: "user",
            ownerAvatarURL: nil,
            isPrivate: false,
            repoDescription: "A test repo",
            updatedAt: nil,
            defaultBranch: "main"
        )
        #expect(repo.id == 1)
        #expect(repo.fullName == "user/repo")
        #expect(repo.name == "repo")
    }

    @Test("KeychainHelper saves and reads token")
    func keychainRoundTrip() throws {
        let keychain = KeychainHelper(service: "com.easymarkdown.test")
        let account = "test_token_\(UUID().uuidString)"

        // Clean up any leftover.
        keychain.delete(account: account)

        try keychain.save(token: "test-token-123", account: account)
        let read = keychain.read(account: account)
        #expect(read == "test-token-123")

        // Clean up.
        keychain.delete(account: account)
        let afterDelete = keychain.read(account: account)
        #expect(afterDelete == nil)
    }
}
