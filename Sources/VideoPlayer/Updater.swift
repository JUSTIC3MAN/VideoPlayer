import AppKit
import Foundation

/// Checks GitHub for a newer build of VideoPlayer and installs it in place.
/// Every push to main makes a release tagged v1.0.<build>; the app compares that build number to its own.
final class Updater {
    static let repo = "JUSTIC3MAN/VideoPlayer"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/JUSTIC3MAN/VideoPlayer/main/install.sh | bash"

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    /// The build number of this copy (0 when built by hand with build.sh).
    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private var isChecking = false

    /// userInitiated = chosen from the menu (always answers). At launch it only speaks up when there is an update.
    func check(userInitiated: Bool) {
        if !userInitiated && currentBuild == 0 { return }   // hand-built copy: don't nag
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VideoPlayer-updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                guard let data,
                      let release = try? JSONDecoder().decode(Release.self, from: data),
                      let asset = release.assets.first(where: { $0.name == "VideoPlayer.zip" }) else {
                    if userInitiated {
                        self.showAlert("Couldn't check for updates",
                                       error?.localizedDescription ?? "No release was found on GitHub yet.")
                    }
                    return
                }
                let latestBuild = Int(release.tag_name.split(separator: ".").last.map(String.init) ?? "") ?? 0
                if latestBuild > self.currentBuild {
                    self.offerUpdate(version: release.tag_name, from: asset.browser_download_url)
                } else if userInitiated {
                    self.showAlert("VideoPlayer is up to date", "You have the latest version (\(release.tag_name)).")
                }
            }
        }.resume()
    }

    private func offerUpdate(version: String, from url: URL) {
        let alert = NSAlert()
        alert.messageText = "VideoPlayer \(version) is available"
        alert.informativeText = "Update now? VideoPlayer will restart. Your setlist is kept."
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        download(from: url)
    }

    private func download(from url: URL) {
        URLSession.shared.downloadTask(with: url) { [weak self] tempFile, _, error in
            // The downloaded file is deleted when this handler returns, so unpack it right here.
            let result: Result<URL, Error>
            if let tempFile {
                result = Result { try Self.unpack(tempFile) }
            } else {
                result = .failure(error ?? UpdateError.message("The download failed."))
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let newApp): self?.replaceAndRelaunch(with: newApp)
                case .failure(let error): self?.showFailure(error)
                }
            }
        }.resume()
    }

    private static func unpack(_ zipFile: URL) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("VideoPlayerUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("VideoPlayer.zip")
        try fm.moveItem(at: zipFile, to: zip)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = work.appendingPathComponent("VideoPlayer.app")
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: app.path) else {
            throw UpdateError.message("The downloaded update could not be unpacked.")
        }
        return app
    }

    private func replaceAndRelaunch(with newApp: URL) {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else {
            showFailure(UpdateError.message("Updates only work from the installed app."))
            return
        }
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        } catch {
            showFailure(error)
            return
        }
        // Open the new copy a moment after this one quits.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    private func showFailure(_ error: Error) {
        showAlert("The update didn't install",
                  "\(error.localizedDescription)\n\nYou can also update by pasting this into Terminal:\n\(Self.installCommand)")
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
