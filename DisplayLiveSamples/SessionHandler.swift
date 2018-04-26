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
    private let session = AVCaptureSession()
    let layer = AVSampleBufferDisplayLayer()
    private let sampleQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.sampleQueue", attributes: [])
    private let faceQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.faceQueue", attributes: [])
    private let wrapper = DlibWrapper()
    private var currentMetadata: [AVMetadataObject] = []

    func openSession() {
        let device = AVCaptureDevice.devices(for: .video).filter { $0.position == .front } .first!
        let input = try! AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        let metaOutput = AVCaptureMetadataOutput()

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(output) {
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
            session.addOutput(output)
        }

        if session.canAddOutput(metaOutput) {
            metaOutput.setMetadataObjectsDelegate(self, queue: faceQueue)
            session.addOutput(metaOutput)
        }

        session.commitConfiguration()

        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        metaOutput.metadataObjectTypes = [.face]
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        currentMetadata = metadataObjects
    }
}
