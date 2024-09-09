//
//  BundleConfig.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation

struct BundleConfig: Codable {
    public var enableMD5Check: Bool = true
    public var enableBSPatch: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case enableMD5Check = "enable_md5_check"
        case enableBSPatch = "enable_bspatch"
    }
}
