//
//  BarcodeService.swift
//  PriceRadar
//
//  Service for barcode scanning using AVFoundation and Vision
//

import Foundation
import AVFoundation
import Vision
import Combine

class BarcodeService: NSObject, ObservableObject {
    @Published var detectedBarcode: String?
    @Published var error: BarcodeError?
    @Published var isAuthorized = false

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // PERFORMANCE: Frame dropping to reduce CPU usage
    private var lastProcessedTime: Date = .distantPast
    private let processingInterval: TimeInterval = 0.5 // Process 2 frames/second max

    // PERFORMANCE: Reuse Vision request instead of creating new one per frame
    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest { [weak self] request, visionError in
            guard let self = self else { return }

            if visionError != nil {
                DispatchQueue.main.async {
                    self.error = .scanningFailed
                }
                return
            }

            guard let results = request.results as? [VNBarcodeObservation],
                  let firstBarcode = results.first,
                  let payloadString = firstBarcode.payloadStringValue else {
                return
            }

            // Only process if we haven't detected a barcode yet
            if self.detectedBarcode == nil {
                DispatchQueue.main.async {
                    self.detectedBarcode = payloadString
                    self.stopScanning()
                }
            }
        }
        return request
    }()

    // Check camera authorization status
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            requestAuthorization()
        case .denied, .restricted:
            isAuthorized = false
            error = .permissionDenied
        @unknown default:
            isAuthorized = false
        }
    }

    // Request camera permission
    private func requestAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if !granted {
                    self?.error = .permissionDenied
                }
            }
        }
    }

    // Setup capture session
    func setupCaptureSession() -> AVCaptureSession? {
        // PERFORMANCE: Only create session once, reuse existing
        if let existingSession = captureSession {
            return existingSession
        }

        let session = AVCaptureSession()

        // CRITICAL: Begin configuration before making changes
        session.beginConfiguration()

        // PERFORMANCE: Use photo preset instead of high - reduces heat
        session.sessionPreset = .photo

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            error = .cameraUnavailable
            return nil
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            session.commitConfiguration()
            self.error = .cameraUnavailable
            return nil
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            session.commitConfiguration()
            error = .sessionConfigurationFailed
            return nil
        }

        let videoOutput = AVCaptureVideoDataOutput()
        // PERFORMANCE: Use utility queue with QoS to prevent queue buildup
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .utility)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        // PERFORMANCE: Drop frames if processing falls behind
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // CRITICAL: Set video settings for proper camera initialization
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            session.commitConfiguration()
            error = .sessionConfigurationFailed
            return nil
        }

        // CRITICAL: Commit configuration changes
        session.commitConfiguration()

        self.captureSession = session
        return session
    }

    // Start scanning
    func startScanning() {
        guard let session = captureSession else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // Only start if not already running
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    // Stop scanning
    func stopScanning() {
        guard let session = captureSession else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // Only stop if currently running
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    // Reset detected barcode
    func resetBarcode() {
        detectedBarcode = nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension BarcodeService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // PERFORMANCE: Frame dropping - only process 2 frames per second
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processingInterval else {
            return // Skip this frame to reduce CPU usage
        }
        lastProcessedTime = now

        // PERFORMANCE: Don't process if we already have a barcode
        guard detectedBarcode == nil else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            // PERFORMANCE: Reuse the Vision request instead of creating new one
            try requestHandler.perform([barcodeRequest])
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.error = .scanningFailed
            }
        }
    }
}

// MARK: - Barcode Errors
enum BarcodeError: LocalizedError {
    case permissionDenied
    case cameraUnavailable
    case sessionConfigurationFailed
    case scanningFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access denied. Please enable camera access in Settings."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .sessionConfigurationFailed:
            return "Failed to configure camera session."
        case .scanningFailed:
            return "Failed to scan barcode. Please try again."
        }
    }
}
