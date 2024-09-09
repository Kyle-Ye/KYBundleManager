//
//  BundleInfo.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation

public struct BundleInfo: Codable, Hashable {
    var name: String
    var version: Int
    var url: URL
    var md5: String
    var deprecated: Bool = false
    var patchURL: URL?
    var patchVersionRange: VersionRange?
    
    enum CodingKeys: String, CodingKey {
        case name = "bundle_name"
        case version = "bundle_version"
        case url = "bundle_url"
        case md5 = "bundle_md5"
        case deprecated = "deprecated"
        case patchURL = "patch_url"
        case patchVersionRange = "patch_version_range"
    }
    
    struct VersionRange: Codable, Hashable, CustomStringConvertible {
        var from: Int
        var to: Int
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(description)
        }
        
        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let result = try container.decode(String.self)
            let components = result.split(separator: "-").compactMap {
                Int($0)
            }
            guard components.count == 2
            else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid version range")
            }
            from = components[0]
            to = components[1]
            
        }
        
        init?(_ value: String) {
            let components = value.split(separator: "-").compactMap {
                Int($0)
            }
            guard components.count == 2
            else { return nil }
            from = components[0]
            to = components[1]
        }
        
        var description: String {
            "\(from)-\(to)"
        }
    }
}
