//
//  ReceiptScannerView.swift
//  PriceRadar
//
//  View for capturing receipt photos and processing with OCR
//

import SwiftUI
import PhotosUI

struct ReceiptScannerView: View {
    @StateObject private var viewModel = ReceiptScannerViewModel()
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showReview = false
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isProcessing {
                    processingView
                } else if viewModel.selectedImage == nil {
                    welcomeView
                } else {
                    imagePreviewView
                }
            }
            .navigationTitle("Receipt Scanner")
            .navigationBarTitleDisplayMode(.large)
            .photosPicker(isPresented: $showImagePicker, selection: $photoPickerItem)
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.selectedImage = image
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(image: $viewModel.selectedImage, sourceType: .camera)
            }
            .navigationDestination(isPresented: $showReview) {
                if viewModel.receipt != nil {
                    ReceiptReviewView(viewModel: viewModel)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Welcome Screen

    private var welcomeView: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 100))
                .foregroundColor(.blue)

            // Title and description
            VStack(spacing: 12) {
                Text("Scan Receipt")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Upload a photo of your receipt to submit prices for all items at once")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                // Camera button
                Button(action: { showCamera = true }) {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(Constants.cornerRadius)
                }

                // Photo library button
                Button(action: { showImagePicker = true }) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(Constants.cornerRadius)
                }
            }
            .padding(.horizontal, 40)

            // Gamification teaser
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Earn up to 200 points per receipt!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(Constants.cornerRadius)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Image Preview Screen

    private var imagePreviewView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Selected image
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .cornerRadius(Constants.cornerRadius)
                    .shadow(radius: 5)
                    .padding()
            }

            // Instructions
            VStack(spacing: 8) {
                Text("Receipt image ready")
                    .font(.headline)

                Text("Tap 'Process Receipt' to extract prices")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button(action: processReceipt) {
                    Text("Process Receipt")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(Constants.cornerRadius)
                }

                Button(action: { viewModel.reset() }) {
                    Text("Choose Different Image")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Processing Screen

    private var processingView: some View {
        VStack(spacing: 30) {
            ProgressView()
                .scaleEffect(2)

            VStack(spacing: 12) {
                Text("Processing Receipt...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Extracting items and matching products")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("This may take 5-10 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func processReceipt() {
        Task {
            await viewModel.processReceipt()
            if viewModel.receipt != nil {
                showReview = true
            }
        }
    }
}

// MARK: - Image Picker for Camera

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ReceiptScannerView()
}
