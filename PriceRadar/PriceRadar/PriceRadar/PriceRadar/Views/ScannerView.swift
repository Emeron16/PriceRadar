//
//  ScannerView.swift
//  PriceRadar
//
//  Barcode scanner view with camera preview
//

import SwiftUI
import AVFoundation

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @ObservedObject var priceComparisonViewModel: PriceComparisonViewModel
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                if viewModel.scanState == .scanning {
                    CameraPreview(session: viewModel.captureSession)
                        .ignoresSafeArea()

                    // Scanning overlay
                    VStack {
                        Spacer()

                        Text("Point camera at barcode")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(Constants.cornerRadius)
                            .padding()

                        Spacer()
                    }
                } else {
                    // Idle state
                    VStack(spacing: 20) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 100))
                            .foregroundColor(.blue)

                        Text("Scan Product Barcode")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Point your camera at a product barcode to find better prices nearby")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: startScanning) {
                            Text("Start Scanning")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(Constants.cornerRadius)
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                }

                // Error message
                if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(Constants.cornerRadius)
                        .padding()
                    }
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.setupCamera() // PERFORMANCE: Setup camera once
                viewModel.checkCameraPermission()
            }
            .onDisappear {
                // PERFORMANCE: Stop camera when leaving scanner view
                viewModel.stopScanning()
            }
            .onChange(of: viewModel.detectedBarcode) { barcode in
                if let barcode = barcode {
                    handleBarcodeDetected(barcode)
                }
            }
            .onChange(of: priceComparisonViewModel.priceComparison) { comparison in
                if comparison != nil {
                    showingResults = true
                }
            }
            .onChange(of: priceComparisonViewModel.errorMessage) { error in
                if error != nil && !priceComparisonViewModel.isLoading {
                    showingResults = true
                }
            }
            .navigationDestination(isPresented: $showingResults) {
                PriceComparisonView(viewModel: priceComparisonViewModel)
            }
        }
    }

    private func startScanning() {
        viewModel.startScanning()
    }

    private func handleBarcodeDetected(_ barcode: String) {
        // Fetch price comparison (navigation happens via onChange)
        Task {
            await priceComparisonViewModel.fetchPriceComparison(for: barcode)
        }

        // Reset scanner for next scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.resetScan()
        }
    }
}

// MARK: - Camera Preview
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Session is already set in makeUIView
        if uiView.session !== session {
            uiView.session = session
        }
    }

    // PERFORMANCE: Clean up preview layer when view is removed
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.session = nil
    }
}

// Custom UIView subclass that manages AVCaptureVideoPreviewLayer
class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get {
            return previewLayer.session
        }
        set {
            previewLayer.session = newValue
            previewLayer.videoGravity = .resizeAspectFill
        }
    }
}

#Preview {
    ScannerView(priceComparisonViewModel: PriceComparisonViewModel())
}
