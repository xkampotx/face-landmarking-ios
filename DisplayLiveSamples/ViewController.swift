//
//  ViewController.swift
//  DisplayLiveSamples
//
//  Created by Luis Reisewitz on 15.05.16.
//  Copyright © 2016 ZweiGraf. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    let sessionHandler = SessionHandler()
    
    @IBOutlet weak var preview: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("didload")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionHandler.openSession()
        let layer = sessionHandler.layer
        layer.frame = preview.bounds
        sessionHandler.shapeLayer.frame = preview.bounds
        print(preview.bounds)
        preview.layer.addSublayer(layer)
        preview.layer.addSublayer(sessionHandler.shapeLayer)
        view.layoutIfNeeded()
        print(preview.bounds)
        print("didappear")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
//        sessionHandler.layer.frame = preview.bounds
    }
}
