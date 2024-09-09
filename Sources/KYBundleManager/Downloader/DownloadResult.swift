//
//  DownloadResult.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation

public struct DownloadResult: Codable {
    public let bundle: BundleInfo
    public let url: URL
    
    public var name: String { bundle.name }
}
