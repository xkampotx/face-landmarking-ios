//
//  SessionHandler.swift
//  DisplayLiveSamples
//
//  Created by Luis Reisewitz on 15.05.16.
//  Copyright © 2016 ZweiGraf. All rights reserved.
//

import AVFoundation
import UIKit

class SessionHandler : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate {
    var session = AVCaptureSession()
    let layer = AVSampleBufferDisplayLayer()
    let sampleQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.sampleQueue", attributes: [])
    let faceQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.faceQueue", attributes: [])
    let wrapper = DlibWrapper()
    let shapeLayer = CAShapeLayer()
    var currentMetadata: [AVMetadataObject]
    
    override init() {
        currentMetadata = []
//        layer.addSublayer(shapeLayer)
        super.init()
    }
    
    func openSession() {
        let device = AVCaptureDevice.devices(for: .video)
            .map { $0 }
            .filter { $0.position == .front }
            .first!
        
        let input = try! AVCaptureDeviceInput(device: device)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        
        let metaOutput = AVCaptureMetadataOutput()
        metaOutput.setMetadataObjectsDelegate(self, queue: faceQueue)
    
        session.beginConfiguration()

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        if session.canAddOutput(metaOutput) {
            session.addOutput(metaOutput)
        }

        session.sessionPreset = .vga640x480
        session.commitConfiguration()
        
        let settings: [AnyHashable: Any] = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: Int(kCVPixelFormatType_32BGRA)]
        output.videoSettings = settings as! [String : Any]
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        // availableMetadataObjectTypes change when output is added to session.
        // before it is added, availableMetadataObjectTypes is empty
        metaOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
        
        wrapper?.prepare()
        
        session.startRunning()
    }

    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        shapeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        defer { layer.enqueue(sampleBuffer) }
        guard !currentMetadata.isEmpty else {
            return
        }

        let boundsArray: [NSValue] = currentMetadata.compactMap {
            guard
                let faceObject = $0 as? AVMetadataFaceObject,
                let bounds = output.transformedMetadataObject(for: faceObject, connection: connection)?.bounds
            else {
                return nil
            }
            return NSValue(cgRect: bounds)
        }
        wrapper?.doWork(on: sampleBuffer, inRects: boundsArray)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("DidDropSampleBuffer")
    }
    
    // MARK: AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        currentMetadata = metadataObjects
    }
}

extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        return CGRect(
            x: self.origin.x * size.width,
            y: self.origin.y * size.height,
            width: self.size.width * size.width,
            height: self.size.height * size.height
        )
    }
}
