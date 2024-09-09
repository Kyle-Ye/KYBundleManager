//
//  URL+Extension.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation
import CryptoKit
import os.log

enum URLDecodePlistError: Error {
    case fileNotExist
}

enum URLEncodePlistError: Error {
    case createFileFailed
}

extension URL {
    func decodeFromPlist<D: Decodable>() throws -> D {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else {
            throw URLDecodePlistError.fileNotExist
        }
        let data = try Data(contentsOf: self)
        let decoder = PropertyListDecoder()
        do {
            return try decoder.decode(D.self, from: data)
        } catch {
            try manager.removeItem(at: self)
            throw error
        }
    }
    
    func encodeIntoPlist<E: Encodable>(_ value: E) throws {
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(value)
        let manager = FileManager.default
        guard manager.createFile(atPath: path, contents: data) else {
            throw URLEncodePlistError.createFileFailed
        }
    }
    
    var md5String: String {
        get throws {
            let data = try Data(contentsOf: self)
            let md5Digest = Insecure.MD5.hash(data: data)
            let md5String = md5Digest.map { String(format: "%02hhx", $0) }.joined()
            return md5String
        }
    }
}
