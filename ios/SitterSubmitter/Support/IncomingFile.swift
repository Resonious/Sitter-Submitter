import Foundation
import UIKit

enum IncomingFile {
    /// PDFs opened in the app from elsewhere arrive as copies in an inbox folder inside the app's container
    /// (tmp/<bundle ID>-Inbox on recent iOS versions, Documents/Inbox on older ones). The repository keeps its
    /// own copy, so the incoming one can go.
    static func removeIfInboxCopy(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
        guard url.isFileURL,
              folder.lastPathComponent == "Inbox" || folder.lastPathComponent.hasSuffix("-Inbox"),
              folder.resolvingSymlinksInPath().path.hasPrefix(container)
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Runs `work`, asking iOS to keep the app running for a while if the user switches away meanwhile:
    /// reading a receipt waits on OpenAI, and the Android app carries on in the background too.
    @MainActor
    static func withBackgroundTime(_ work: () async -> Void) async {
        let backgroundTask = BackgroundTask()
        await work()
        backgroundTask.end()
    }
}

@MainActor
private final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Add receipt") { [weak self] in
            // Out of time: end the task, or iOS terminates the app.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
