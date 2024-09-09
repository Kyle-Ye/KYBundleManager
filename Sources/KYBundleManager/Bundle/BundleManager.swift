//
//  BundleManager.swift
//
//
//  Created by Kyle on 2024/9/5.
//

import Foundation
import os.log

public final actor BundleManager {
    // MARK: - Init and static methods
    
    private static let logger = Logger(
        subsystem: (Bundle.main.bundleIdentifier.map { $0 + "." } ?? "") + "KYBundleManager",
        category: "BundleManager"
    )
    
    public static let shared = BundleManager()
    
    private static let rootDirectory: URL = {
        let manager = FileManager.default
        let directory = {
            guard let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                let temporaryDirectory = manager.temporaryDirectory
                logger.error("Failed to get applicationSupportDirectory, fallack to use temporaryDirectory at \(temporaryDirectory)")
                return temporaryDirectory
            }
            return directory
        }()
        let rootDirectory = directory.appendingPathComponent("BundleManager", isDirectory: true)
        if !manager.fileExists(atPath: rootDirectory.path) {
            do {
                try manager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create root directory: \(rootDirectory), error: \(error)")
            }
        }
        logger.debug("Root directory: \(rootDirectory)")
        return rootDirectory
    }()
    
    private static var packageInfoURL: URL {
        rootDirectory.appendingPathComponent("package_info.plist")
    }
    
    private init() {
        let packageInfoURL = Self.packageInfoURL
        localPackageInfo = (try? packageInfoURL.decodeFromPlist()) ?? PackageInfo()
        downloader = Downloader(directory: BundleManager.rootDirectory)
    }
    
    // MARK: - Properties
    
    private var localPackageInfo: PackageInfo
    private let downloader: Downloader
    
    // MARK: - Public API
    
    public func request(bundleName: String) async throws -> DownloadResult? {
        try await request(bundleNames: [bundleName]).first
    }
    
    public func request(bundleNames: [String]) async throws -> [DownloadResult] {
        let requestInfos = bundleNames.map { name in
            if let info = localPackageInfo.bundles.first(where: { $0.name == name }) {
                return BundleRequestInfo(name: info.name, version: info.version)
            } else {
                return BundleRequestInfo(name: name)
            }
        }
        let newBundleInfo = try await BundleAPI.getOfflineBundle(requestInfos)
        let newPackageInfo = PackageInfo(
            bundles: newBundleInfo.bundles,
            config: localPackageInfo.config
        )
        let results = try await downloader.download(packageInfo: newPackageInfo)
        Task.detached { [weak self] in
            guard let self else { return }
            await updateLocalBundleInfo(bundles: results.map(\.bundle))
        }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            try await cleanup(bundleNames: bundleNames)
        }
        return results
    }
    
    private func updateLocalBundleInfo(bundles: [BundleInfo]) {
        var localBundles = localPackageInfo.bundles
        for bundle in bundles {
            if let index = localBundles.firstIndex(where: { $0.name == bundle.name }) {
                localBundles[index] = bundle
            } else {
                localBundles.append(bundle)
            }
        }
        localPackageInfo.bundles = localBundles
        let packageInfoURL = Self.packageInfoURL
        do {
            try packageInfoURL.encodeIntoPlist(localPackageInfo)
        } catch {
            Self.logger.error("Failed to save new package info file: \(packageInfoURL)")
        }
    }
    
    private func cleanup(bundleNames: [String]) async throws {
        try await downloader.cleanup(bundleNames: bundleNames)
    }
}
