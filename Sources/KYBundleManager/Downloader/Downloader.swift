//
//  Downloader.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation
import Zip
import os.log
import Algorithms

/// Download Manager
///
/// Layout:
/// - rootDirectory
///  - offline_package.json
///  - [D]zipDirectory
///   - a_v1.zip
///   - a_v2.zip
///  - [D]patchDirectory
///  - [D]destinationDirectory
///   - [D]a
///    - bundle_info.plist (record the latest information)
///    - [D]v1 (unzipped_content of a_1.zip)
///    - [D]v2 (unzipped_content of a_2.zip)
actor Downloader {
    private static let logger = Logger(
        subsystem: (Bundle.main.bundleIdentifier.map { $0 + "." } ?? "") + "KYBundleManager",
        category: "Downloader"
    )
    
    nonisolated
    private var logger: Logger { Downloader.logger }
    
    private let manager = FileManager.default
    
    let rootDirectory: URL
    let zipDirectory: URL
    let patchDirectory: URL
    let destinationDirectory: URL
    
    init(directory: URL, delegate: (any DownloadTaskDelegate)? = nil) {
        rootDirectory = directory
        zipDirectory = directory.appendingPathComponent("zips", isDirectory: true)
        patchDirectory = directory.appendingPathComponent("patchs", isDirectory: true)
        destinationDirectory = directory.appendingPathComponent("destinations", isDirectory: true)
        self.delegate = delegate
        
        createDirectoryIfNeeded(rootDirectory)
        createDirectoryIfNeeded(zipDirectory)
        createDirectoryIfNeeded(patchDirectory)
        createDirectoryIfNeeded(destinationDirectory)
    }
    
    nonisolated
    private func createDirectoryIfNeeded(_ directory: URL) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create directory: \(directory), error: \(error)")
            }
        }
    }
    
    weak var delegate: (any DownloadTaskDelegate)?
    
    func download(packageInfo: PackageInfo) async throws -> [DownloadResult] {
        let bundles = packageInfo.bundles
        let config = packageInfo.config
        let results = try await withThrowingTaskGroup(of: DownloadResult?.self) { group in
            var results: [DownloadResult] = []
            for bundle in bundles {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        return try await download(bundle: bundle, config: config)
                    } catch {
                        logger.error("\(error.localizedDescription)")
                        return nil
                    }
                }
            }
            for try await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }
        return results
    }
    
    private func download(bundle: BundleInfo, config: BundleConfig) async throws -> DownloadResult? {
        try prepareBundleFolderStep(bundle: bundle)
        if let localBundle = checkLocalBundleStep(name: bundle.name) {
            let destination = bundleURL(name: localBundle.name, version: localBundle.version)
            if manager.fileExists(atPath: destination.path) {
                if localBundle.version < bundle.version {
                    Task.detached(priority: .background) { [self] in // NOTE: capture self strongly on purpose here
                        do {
                            _ = try await _downloadOrUpdating(bundle: bundle, config: config)
                        } catch {
                            logger.error("\(error.localizedDescription)")
                        }
                    }
                }
                return DownloadResult(bundle: localBundle, url: destination)
            }
        }
        return try await _downloadOrUpdating(bundle: bundle, config: config)
    }
    
    private func _downloadOrUpdating(bundle: BundleInfo, config: BundleConfig) async throws ->DownloadResult? {
        let latestBundle = bundle
        let destination = bundleURL(name: latestBundle.name, version: latestBundle.version)
        if let result = bundleCheckStep(bundle: latestBundle, destination: destination) {
            return result
        }
        let zipURL = zipFileURL(name: latestBundle.name, version: latestBundle.version)
        if let result = try zipFileCheckStep(bundle: latestBundle, zipURL: zipURL, destination: destination, enableMD5Check: config.enableMD5Check) {
            return result
        }
        let patchResult: Bool
        if config.enableBSPatch {
            patchResult = try await tryToPatchStep(bundle: latestBundle, enableMD5Check: config.enableMD5Check)
        } else {
            patchResult = false            
        }
        if !patchResult {
            guard let temporaryZipURL = try await downloadStep(bundle: latestBundle, enableMD5Check: config.enableMD5Check) else {
                return nil
            }
            try moveStep(at: temporaryZipURL, to: zipURL)
        }
        try unzipStep(zipURL: zipURL, destination: destination)
        try updateBundleInfoStep(bundle: latestBundle)
        return DownloadResult(bundle: latestBundle, url: destination)
    }
    
    // MARK: - Steps method
    
    private func prepareBundleFolderStep(bundle: BundleInfo) throws {
        let bundleFolderURL = destinationDirectory.appendingPathComponent(bundle.name, isDirectory: true)
        try manager.createDirectory(at: bundleFolderURL, withIntermediateDirectories: true)
        logger.debug("\(#function) Original bundle \(bundle.name) v\(bundle.version).")
    }
    
    private func checkLocalBundleStep(name: String) -> BundleInfo? {
        let bundleInfoPlistURL = bundleInfoPlistURL(name: name)
        return try? bundleInfoPlistURL.decodeFromPlist()
    }
    
    private func bundleCheckStep(bundle: BundleInfo, destination: URL) -> DownloadResult? {
        guard !manager.fileExists(atPath: destination.path) else {
            logger.debug("\(#function) Bundle is already unzipped into destination. [End]")
            return DownloadResult(bundle: bundle, url: destination)
        }
        logger.debug("\(#function) Bundle is not yet unzipped into destination.")
        return nil
    }
    
    private func zipFileCheckStep(bundle: BundleInfo, zipURL: URL, destination: URL, enableMD5Check: Bool = true) throws -> DownloadResult? {
        guard manager.fileExists(atPath: zipURL.path) else {
            logger.debug("\(#function) Zip file is not downloaded. Continue.")
            return nil
        }
        if enableMD5Check {
            guard let md5String = try? zipURL.md5String, md5String == bundle.md5 else {
                try manager.removeItem(at: zipURL)
                logger.debug("\(#function) Zip file is downloaded but md5 value does not match. Delete old zip file and continue.")
                return nil
            }
            logger.debug("\(#function) Zip file is downloaded and md5 value matches. Start to unzip.")
        } else {
            logger.debug("\(#function) Zip file is downloaded and ignore md5 check. Start to unzip.")
        }
        try unzipStep(zipURL: zipURL, destination: destination)
        try updateBundleInfoStep(bundle: bundle)
        return DownloadResult(bundle: bundle, url: destination)
    }
    
    private func tryToPatchStep(bundle: BundleInfo, enableMD5Check: Bool) async throws -> Bool {
        guard let patchURL = bundle.patchURL,
              let patchVersionRange = bundle.patchVersionRange
        else {
            logger.debug("\(#function) Invalid patchURL or patchVersionRange. Patch skip.")
            return false
        }
        
        let fromZipURL = zipFileURL(name: bundle.name, version: patchVersionRange.from)
        let toZipURL = zipFileURL(name: bundle.name, version: patchVersionRange.to)
        let patchVersionURL = patchFileURL(name: bundle.name, versionRange: patchVersionRange)
        guard manager.fileExists(atPath: fromZipURL.path) else {
            logger.debug("\(#function) Patch file's from zip is not downloaded. Patch skip.")
            return false
        }
        if manager.fileExists(atPath: patchVersionURL.path) {
            logger.debug("\(#function) Patch file is already downloaded. Start to patch.")
        } else {
            let temporaryPatchURL = try await downloadPatchStep(patchURL: patchURL)
            try moveStep(at: temporaryPatchURL, to: patchVersionURL)
        }
        defer {
            do {
                logger.debug("\(#function) Remove patch file \(patchVersionURL) begin.")
                try manager.removeItem(at: patchVersionURL)
                logger.debug("\(#function) Remove patch file \(patchVersionURL) success.")
            } catch {
                logger.error("\(#function) Failed to remove patch file: \(patchVersionURL)")
            }
        }
        let patchTask = PatchTask()
        let result = patchTask.patch(old: fromZipURL, patch: patchVersionURL, new: toZipURL)
        if result {
            logger.debug("\(#function) Patch success.")
            if enableMD5Check {
                guard let md5String = try? toZipURL.md5String, md5String == bundle.md5 else {
                    try manager.removeItem(at: toZipURL)
                    logger.debug("\(#function) Patch zip result md5 value does not match. Delete zip file and continue.")
                    return false
                }
                logger.debug("\(#function) Zip file patched and md5 value matches. Start to unzip.")
            } else {
                logger.debug("\(#function) Zip file patched and ignore md5 check. Start to unzip.")
            }
            return true
        } else {
            logger.error("\(#function) Patch failed.")
            return false
        }
    }
    
    private func cacheFileCheckStep(bundle: BundleInfo, zipURL: URL, destination: URL) throws -> DownloadResult? {
        guard manager.fileExists(atPath: zipURL.path) else {
            logger.debug("\(#function) Zip file is not downloaded. Continue.")
            return nil
        }
        logger.debug("\(#function) Zip file is downloaded and ignore md5 check. Start to unzip.")
        try unzipStep(zipURL: zipURL, destination: destination)
        try updateBundleInfoStep(bundle: bundle)
        return DownloadResult(bundle: bundle, url: destination)
    }
    
    /// 下载 Patch 文件
    /// - Parameter url: The patch to download
    /// - Returns: The local file URL of the downloaded patch
    private func downloadPatchStep(patchURL url: URL) async throws -> URL {
        let downloadTask = DownloadTask(delegate: delegate)
        let (temporaryPatchURL, _) = try await downloadTask.download(url: url)
        logger.debug("\(#function) Download patch file complete.")
        return temporaryPatchURL
    }
    
    private func downloadStep(bundle: BundleInfo, enableMD5Check: Bool = true) async throws -> URL? {
        let downloadTask = DownloadTask(delegate: delegate)
        let (temporaryZipURL, _) = try await downloadTask.download(url: bundle.url)
        
        if enableMD5Check {
            guard let md5String = try? temporaryZipURL.md5String, md5String == bundle.md5 else {
                // Delete the zip file
                try manager.removeItem(at: temporaryZipURL)
                logger.debug("\(#function) Downloaded zip file md5 value does not match. Delete and return nil. [End]")
                return nil
            }
            logger.debug("\(#function) Download zip file complete and md5 value matches.")
        } else {
            logger.debug("\(#function) Download zip file complete and ignore md5 check.")
        }
        return temporaryZipURL
    }
    
    private func moveStep(at: URL, to: URL) throws {
        try manager.moveItem(at: at, to: to)
        logger.debug("\(#function) Move zip file into zip directory.")
    }
    
    private func unzipStep(zipURL: URL, destination: URL) throws {
        try Zip.unzipFile(zipURL, destination: destination, overwrite: true, password: nil)
        logger.debug("\(#function) Unzip complete.")
    }
    
    private func updateBundleInfoStep(bundle: BundleInfo) throws {
        let bundleInfoPlistURL = bundleInfoPlistURL(name: bundle.name)
        try bundleInfoPlistURL.encodeIntoPlist(bundle)
        logger.debug("\(#function) Update bundle info success. [End]")
    }
    
    // MARK: - URL + Helper method
    
    private func bundleFolderURL(name: String) -> URL {
        destinationDirectory
            .appendingPathComponent(name, isDirectory: true)
    }
    
    private func bundleInfoPlistURL(name: String) -> URL {
        bundleFolderURL(name: name)
            .appendingPathComponent("bundle_info.plist")
    }
    
    private func bundleURL(name: String, version: Int) -> URL {
        bundleFolderURL(name: name)
            .appendingPathComponent("v\(version)", isDirectory: true)
    }
    
    private func zipFileURL(name: String, version: Int) -> URL {
        zipDirectory
            .appendingPathComponent("\(name)_v\(version).zip")
    }
    
    private func patchFileURL(name: String, versionRange: BundleInfo.VersionRange) -> URL {
        patchDirectory
            .appendingPathComponent("\(name)_v\(versionRange).patch")
    }
    
    // MARK: - Clean Up
    
    func cleanup(bundleNames: [String]) throws {
        try cleanupZips(bundleNames: bundleNames)
        try cleanupPatches(bundleNames: bundleNames)
        try cleanupDestinations(bundleNames: bundleNames)
    }
    
    private func cleanupZips(bundleNames: [String]) throws {
        let files = try manager.contentsOfDirectory(atPath: zipDirectory.path)
        
        func extractBaseNameAndVersion(from filename: String) -> (baseName: String, version: Int)? {
            let nameWithoutExtension = filename.replacingOccurrences(of: ".zip", with: "")
            
            if let lastUnderscoreRange = nameWithoutExtension.range(of: "_", options: .backwards) {
                let baseName = String(nameWithoutExtension[..<lastUnderscoreRange.lowerBound])
                let versionString = String(nameWithoutExtension[lastUnderscoreRange.upperBound...].dropFirst())
                if let version = Int(versionString) {
                    return (baseName, version)
                }
            }
            return nil
        }

        let bundleVersionGroup = files
            .lazy
            .compactMap(extractBaseNameAndVersion(from:))
            .filter { bundleNames.contains($0.baseName) }
            .grouped(by: { $0.baseName })
            .mapValues { $0.map { $0.version }.sorted(by: >) }
        logger.debug("\(#function) Bundle Versions Group detected \(bundleVersionGroup)")
        for (baseName, versions) in bundleVersionGroup {
            guard versions.count >= 2 else { continue }
            let deleteVersions = versions.dropFirst()
            for version in deleteVersions {
                let url = zipDirectory.appendingPathComponent("\(baseName)_v\(version).zip")
                do {
                    try manager.removeItem(at: url)
                } catch {
                    logger.error("\(#function) Failed to remove zip file: \(url), error: \(error)")
                }
            }
        }
    }
    
    private func cleanupPatches(bundleNames: [String]) throws {
        let files = try manager.contentsOfDirectory(atPath: patchDirectory.path)
        for file in files {
            let url = patchDirectory.appendingPathComponent(file)
            do {
                try manager.removeItem(at: url)
            } catch {
                logger.error("\(#function) Failed to remove patch file: \(url), error: \(error)")
            }
        }
    }
    
    private func cleanupDestinations(bundleNames: [String]) throws {
        try bundleNames.forEach { try cleanupDestinations(bundleName: $0) }
    }
    
    private func cleanupDestinations(bundleName: String) throws {
        let files = try manager.contentsOfDirectory(atPath: destinationDirectory.appendingPathComponent(bundleName).path)
        let versions = files
            .lazy
            .compactMap { Int($0.dropFirst()) }
            .sorted(by: >)
        
        guard versions.count >= 3 else { return }
        let deleteVersions = versions.dropFirst(2)
        for version in deleteVersions {
            let url = destinationDirectory.appendingPathComponent(bundleName).appendingPathComponent("v\(version)")
            do {
                try manager.removeItem(at: url)
            } catch {
                logger.error("\(#function)  Failed to remove destination file: \(url), error: \(error)")
            }
        }
    }
}
