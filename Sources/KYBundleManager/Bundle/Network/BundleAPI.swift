//
//  BundleAPI.swift
//  
//
//  Created by Kyle on 2024/9/5.
//

import Foundation

struct BundleResponse: Codable {
    var bundles: [BundleInfo]
}

struct BundleRequestInfo: Codable {
    var name: String
    var version: Int?
    
    init(name: String, version: Int? = nil) {
        self.name = name
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        case name = "bundle_name"
        case version = "bundle_version"
    }
    
    var dictionary: [String: Any] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = try? JSONSerialization.jsonObject(with: data, options: .allowFragments),
              let dict = json as? [String: Any]
        else { return [:] }
        return dict
    }
}



enum BundleAPI {
    static func getOfflineBundle(_ infos: [BundleRequestInfo]) async throws -> BundleResponse {
        #if DEBUG && SHELL_APP
        let resource: String
        if  infos.contains(where: { ($0.version ?? 0) > 0 }) {
            resource = "bundle_patch"
        } else {
            resource = "bundle_test2"
        }
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
              let mockData = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: mockData, options: .allowFragments) as? [String: Any],
              let response = GetOfflineBundleResp.deserialize(from: dict)
        else {
            return GetOfflineBundleResp()
        }
        return response
        #else
        
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = URLRequest(url: URL(string: "https://www.example.com/get_offline_bundle")!)
            URLSession.shared.dataTask(with: request) { data, _, error in
                guard error == nil,
                      let data,
                      let response = try? JSONDecoder().decode(BundleResponse.self, from: data)
                else {
                    continuation.resume(throwing: error ?? BundleError.unknown)
                    return
                }
                continuation.resume(returning: response)
            }.resume()
        }
        #endif
    }
    
    enum BundleError: Error {
        case unknown
    }
}
