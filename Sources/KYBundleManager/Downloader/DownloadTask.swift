//
//  DownloadTask.swift
//
//
//  Created by Kyle on 2024/9/5.
//

import Foundation

public protocol DownloadTaskDelegate: URLSessionTaskDelegate {}

public struct DownloadTask {
    init(delegate: (any DownloadTaskDelegate)? = nil) {
        self.delegate = delegate
    }
    
    weak var delegate: (any DownloadTaskDelegate)?
    
    public func download(url: URL) async throws -> (URL, URLResponse) {
        let request = URLRequest(url: url)
        return try await download(request: request)
        
    }
    
    public func download(request: URLRequest) async throws -> (URL, URLResponse) {
        if #available(iOS 15.0, *) {
            try await URLSession.shared.download(for: request, delegate: delegate)
        } else {
            try await URLSession.shared._download(for: request)
        }
    }
}

@available(iOS, deprecated: 15.0)
extension URLSession {
    func _download(for request: URLRequest) async throws -> (URL, URLResponse) {
        var downloadTask: URLSessionDownloadTask?
        let onCancel = { downloadTask?.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation -> Void in
                let task = self.downloadTask(with: request) { url, response, error in
                    guard let url, let response else {
                        return continuation.resume(throwing: error ?? URLError(.unknown))
                    }
                    continuation.resume(returning: (url, response))
                }
                task.resume()
                downloadTask = task
                return
            }
        } onCancel: {
            onCancel()
        }
    }
}
