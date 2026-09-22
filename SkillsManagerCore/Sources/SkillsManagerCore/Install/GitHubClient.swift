import Foundation

public struct GitHubRepo: Sendable, Equatable {
    public let description: String?
    public let defaultBranch: String
    public let htmlURL: URL
    public let ownerURL: URL?
    public init(description: String?, defaultBranch: String, htmlURL: URL, ownerURL: URL?) {
        self.description = description; self.defaultBranch = defaultBranch; self.htmlURL = htmlURL; self.ownerURL = ownerURL
    }
}

/// The three GitHub reads the resolver needs. Unauthenticated (60 req/h).
public protocol GitHubClient: Sendable {
    func repo(owner: String, repo: String) async throws -> GitHubRepo
    func treePaths(owner: String, repo: String, branch: String) async throws -> [String]
    func raw(owner: String, repo: String, branch: String, path: String) async throws -> String
}

public struct URLSessionGitHubClient: GitHubClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func repo(owner: String, repo: String) async throws -> GitHubRepo {
        let json = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)")
        guard let branch = json["default_branch"] as? String,
              let html = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw InstallError.other("Unexpected reply from GitHub.")
        }
        let ownerURL = ((json["owner"] as? [String: Any])?["html_url"] as? String).flatMap(URL.init(string:))
        return GitHubRepo(description: json["description"] as? String, defaultBranch: branch, htmlURL: html, ownerURL: ownerURL)
    }

    public func treePaths(owner: String, repo: String, branch: String) async throws -> [String] {
        let json = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1")
        let tree = json["tree"] as? [[String: Any]] ?? []
        return tree.compactMap { $0["path"] as? String }
    }

    public func raw(owner: String, repo: String, branch: String, path: String) async throws -> String {
        let (data, _) = try await get("https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)")
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: plumbing

    private func getJSON(_ url: String) async throws -> [String: Any] {
        let (data, _) = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.other("Unexpected reply from GitHub.")
        }
        return json
    }

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw InstallError.other("Bad URL.") }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsManager", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw InstallError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw InstallError.network("No response.") }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 404: throw InstallError.repoNotFound
        case 403, 429: throw InstallError.rateLimited
        default: throw InstallError.other("GitHub replied with status \(http.statusCode).")
        }
    }
}
