import AppKit
import CoreGraphics

// MARK: - Protocol

/// Protocol for thumbnail capture, enabling mock injection in tests.
protocol ThumbnailCapturing {
    /// Capture a cached thumbnail for a given macOS Space ID.
    func captureThumbnail(for spaceID: Int) -> NSImage?

    /// Capture a screenshot of the current workspace.
    func captureCurrentWorkspace() -> NSImage?
}

// MARK: - ThumbnailCapture

/// Captures and caches workspace thumbnails using CGWindowListCreateImage.
///
/// Future enhancement: use ScreenCaptureKit's SCStream for live video
/// thumbnails instead of static screenshots.
final class ThumbnailCapture: ThumbnailCapturing {

    // MARK: - Properties

    /// Cached thumbnails keyed by macOS Space ID.
    private var cache: [Int: NSImage] = [:]

    /// Serial queue for thread-safe cache access.
    private let cacheQueue = DispatchQueue(label: "com.nirvana.thumbnailCache")

    /// Whether the user has granted Screen Recording permission.
    private(set) var hasPermission: Bool = false

    // MARK: - Init

    init() {
        checkPermission()
        observeWorkspaceChanges()
    }

    // MARK: - Permission

    /// Check if Screen Recording permission is granted.
    func checkPermission() {
        if #available(macOS 15.0, *) {
            // CGPreflightScreenCaptureAccess is available on macOS 10.15+
            // but the semantics improved in later versions
            hasPermission = CGPreflightScreenCaptureAccess()
        } else {
            hasPermission = CGPreflightScreenCaptureAccess()
        }
    }

    /// Request Screen Recording permission from the user.
    /// This opens the System Preferences pane if not already granted.
    func requestPermission() {
        if !hasPermission {
            hasPermission = CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - ThumbnailCapturing

    func captureThumbnail(for spaceID: Int) -> NSImage? {
        cacheQueue.sync {
            cache[spaceID]
        }
    }

    func captureCurrentWorkspace() -> NSImage? {
        guard hasPermission else { return nil }

        // Capture the entire main display.
        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,                           // null = entire display
            .optionOnScreenOnly,                   // only visible windows
            kCGNullWindowID,                       // all windows
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))
        return image
    }

    // MARK: - Cache Management

    /// Capture and cache a thumbnail for the given Space ID.
    func updateCache(for spaceID: Int) {
        guard let image = captureCurrentWorkspace() else { return }
        cacheQueue.sync {
            cache[spaceID] = image
        }
    }

    /// Remove a cached thumbnail.
    func invalidateCache(for spaceID: Int) {
        cacheQueue.sync {
            _ = cache.removeValue(forKey: spaceID)
        }
    }

    /// Clear the entire cache.
    func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
        }
    }

    /// Returns the number of cached thumbnails.
    var cacheCount: Int {
        cacheQueue.sync { cache.count }
    }

    // MARK: - Workspace Observation

    /// Observe workspace switch notifications to cache the outgoing workspace.
    private func observeWorkspaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // After a space change, re-check permission in case it was revoked.
            self?.checkPermission()
        }
    }

    // MARK: - TODO: ScreenCaptureKit Live Streaming
    //
    // For future live video thumbnails:
    //   1. Create an SCShareableContent to enumerate windows/displays
    //   2. Set up an SCContentFilter for each Space's display
    //   3. Create an SCStream with SCStreamConfiguration (scaled-down resolution)
    //   4. Implement SCStreamOutput to receive CMSampleBuffers
    //   5. Convert sample buffers to NSImage for the pager grid
    //
    // This would replace the static CGWindowListCreateImage approach with
    // real-time ~5fps thumbnail streams per workspace.
}

// MARK: - MockThumbnailCapture (for tests)

/// A mock implementation for unit testing views without Screen Recording.
final class MockThumbnailCapture: ThumbnailCapturing {
    var thumbnails: [Int: NSImage] = [:]
    var currentWorkspaceImage: NSImage?

    func captureThumbnail(for spaceID: Int) -> NSImage? {
        thumbnails[spaceID]
    }

    func captureCurrentWorkspace() -> NSImage? {
        currentWorkspaceImage
    }
}
