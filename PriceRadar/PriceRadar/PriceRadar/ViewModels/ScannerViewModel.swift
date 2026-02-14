//
//  ScannerViewModel.swift
//  PriceRadar
//
//  ViewModel for barcode scanner functionality
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

class ScannerViewModel: ObservableObject {
    @Published var scanState: ScanState = .idle
    @Published var detectedBarcode: String?
    @Published var errorMessage: String?

    private let barcodeService = BarcodeService()
    private var cancellables = Set<AnyCancellable>()

    // PERFORMANCE: Store session as property instead of computing each time
    private var _captureSession: AVCaptureSession?

    var captureSession: AVCaptureSession? {
        return _captureSession
    }

    init() {
        setupObservers()
    }

    // PERFORMANCE: Setup camera once, reuse session
    func setupCamera() {
        guard _captureSession == nil else { return } // Only create once
        _captureSession = barcodeService.setupCaptureSession()
    }

    // PERFORMANCE: Clean up resources when ViewModel is destroyed
    deinit {
        _captureSession?.stopRunning()
        cancellables.removeAll()
    }

    private func setupObservers() {
        // Observe barcode detection
        barcodeService.$detectedBarcode
            .sink { [weak self] barcode in
                guard let self = self, let barcode = barcode else { return }
                self.detectedBarcode = barcode
                self.scanState = .success
            }
            .store(in: &cancellables)

        // Observe errors
        barcodeService.$error
            .sink { [weak self] error in
                guard let self = self, let error = error else { return }
                self.errorMessage = error.localizedDescription
                self.scanState = .error
            }
            .store(in: &cancellables)

        // Observe authorization
        barcodeService.$isAuthorized
            .sink { [weak self] isAuthorized in
                guard let self = self else { return }
                // Only show error if explicitly denied (error will be set by BarcodeService)
                // Don't show error on initial false state
            }
            .store(in: &cancellables)
    }

    func checkCameraPermission() {
        barcodeService.checkAuthorization()
    }

    func startScanning() {
        guard barcodeService.isAuthorized else {
            errorMessage = "Camera access denied"
            scanState = .error
            return
        }

        // Ensure camera session is set up before starting
        if _captureSession == nil {
            setupCamera()
        }

        guard _captureSession != nil else {
            errorMessage = "Failed to initialize camera"
            scanState = .error
            return
        }

        scanState = .scanning
        barcodeService.startScanning()
    }

    func stopScanning() {
        barcodeService.stopScanning()
        scanState = .idle
    }

    func resetScan() {
        barcodeService.resetBarcode()
        detectedBarcode = nil
        errorMessage = nil
        scanState = .idle
    }
}

// MARK: - Scan State
enum ScanState {
    case idle
    case scanning
    case success
    case error

    var description: String {
        switch self {
        case .idle:
            return "Tap to scan"
        case .scanning:
            return "Scanning..."
        case .success:
            return "Barcode detected!"
        case .error:
            return "Error occurred"
        }
    }
}
