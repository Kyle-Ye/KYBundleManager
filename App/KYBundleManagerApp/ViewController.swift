//
//  ViewController.swift
//  KYBundleManagerApp
//
//  Created by Kyle on 2024/6/13.
//

import UIKit
import KYBundleManager

class ViewController: UIViewController {
    override func viewDidLoad() {        
        Task.detached {
            let downloadResults = try await BundleManager.shared.request(
                bundleNames: ["emoji"]
            )
            print(downloadResults)
        }
    }
}

#if DEBUG

import SwiftUI

@available(iOS 17, *)
#Preview {
    ViewController()
}

#endif
