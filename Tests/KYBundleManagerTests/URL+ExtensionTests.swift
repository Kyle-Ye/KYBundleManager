//
//  URL+ExtensionTests.swift
//  KYBundleManager
//
//  Created by Kyle on 2024/9/7.
//

import Foundation
@testable import KYBundleManager
import XCTest

final class URL_ExtensionTests: XCTestCase {
    func testMD5() async throws {
        let testFile = try XCTUnwrap(Bundle.module.url(forResource: "test", withExtension: "txt"))
        let md5String = try testFile.md5String
        XCTAssertEqual(md5String, "e59ff97941044f85df5297e1c302d260")
    }
}
