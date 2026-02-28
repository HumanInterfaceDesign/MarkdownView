//
//  ImageLoader.swift
//  MarkdownView
//
//  Async image loader with memory cache for markdown image rendering.
//

import Foundation
import os.log

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public final class ImageLoader {
    public static let shared = ImageLoader()

    /// Posted on the main thread when an image finishes loading.
    /// The `object` is the URL string (`String`).
    public static let imageDidLoadNotification = Notification.Name("ImageLoader.imageDidLoad")

    private let cache = NSCache<NSString, PlatformImage>()
    private let session: URLSession
    private var inFlightTasks: [URL: URLSessionDataTask] = [:]
    private let lock = NSLock()
    private static let log = Logger(subsystem: "MarkdownView", category: "ImageLoader")

    private init() {
        cache.countLimit = 128
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        session = URLSession(configuration: config)
    }

    /// Load an image from URL. Returns cached image synchronously if available,
    /// otherwise fetches asynchronously and calls completion on main thread.
    public func loadImage(
        from urlString: String,
        completion: @escaping (PlatformImage?) -> Void
    ) {
        let cacheKey = urlString as NSString

        // Check memory cache
        if let cached = cache.object(forKey: cacheKey) {
            #if DEBUG
                Self.log.info("cache hit: \(urlString)")
            #endif
            completion(cached)
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        // Check for local file URLs
        if url.isFileURL {
            if let image = PlatformImage(contentsOfFile: url.path) {
                cache.setObject(image, forKey: cacheKey)
                completion(image)
            } else {
                completion(nil)
            }
            return
        }

        lock.lock()
        if inFlightTasks[url] != nil {
            lock.unlock()
            return // Already fetching
        }
        lock.unlock()

        #if DEBUG
            Self.log.info("downloading: \(urlString)")
        #endif
        let task = session.dataTask(with: url) { [weak self] data, _, error in
            defer {
                self?.lock.lock()
                self?.inFlightTasks.removeValue(forKey: url)
                self?.lock.unlock()
            }

            guard error == nil, let data, let image = PlatformImage(data: data) else {
                #if DEBUG
                    Self.log.warning("failed: \(urlString) error=\(error?.localizedDescription ?? "bad data")")
                #endif
                DispatchQueue.main.async { completion(nil) }
                return
            }

            #if DEBUG
                Self.log.info("loaded: \(urlString) size=\(image.size.width)x\(image.size.height)")
            #endif
            self?.cache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async {
                completion(image)
                NotificationCenter.default.post(
                    name: ImageLoader.imageDidLoadNotification,
                    object: urlString
                )
            }
        }

        lock.lock()
        inFlightTasks[url] = task
        lock.unlock()

        task.resume()
    }

    /// Synchronously check if an image is cached.
    public func cachedImage(for urlString: String) -> PlatformImage? {
        cache.object(forKey: urlString as NSString)
    }
}
