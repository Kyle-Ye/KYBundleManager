//
//  PatchTask.swift
//
//
//  Created by Kyle on 2024/9/7.
//

import Foundation
import BSDiffSwift

public protocol PatchTaskDelegate: AnyObject {}

public struct PatchTask {
    public init(delegate: (any PatchTaskDelegate)? = nil) {
        self.delegate = delegate
    }
    
    weak var delegate: (any PatchTaskDelegate)?
        
    public func patch(old: URL, patch: URL, new: URL) -> Bool {
        Data.applyDiff(oldFile: old, patchFile: patch, newFile: new)
    }
}

