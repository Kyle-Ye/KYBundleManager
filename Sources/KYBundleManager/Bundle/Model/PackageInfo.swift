//
//  PackageInfo.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation

struct PackageInfo: Codable {
    var bundles: [BundleInfo]
    let config: BundleConfig
    
    init(bundles: [BundleInfo] = [], config: BundleConfig = BundleConfig()) {
        self.bundles = bundles
        self.config = config
    }
}
