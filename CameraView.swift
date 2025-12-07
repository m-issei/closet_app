import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    // completion(image, category)
    var onComplete: (_ image: UIImage?, _ category: String?) -> Void

    @State private var showPicker = true
    @State private var capturedImage: UIImage?
    @State private var maskedImage: UIImage?
    @State private var category: String = ""
    @State private var processing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let img = maskedImage ?? capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .padding()
                } else {
                    Spacer()
                    Text("写真を撮影してください")
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if processing {
                    ProgressView("背景を削除中...")
                        .padding()
                }

                HStack {
                    TextField("カテゴリ (例: tops) ", text: $category)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("再撮影") {
                        showPicker = true
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(action: {
                        // upload
                        onComplete(maskedImage ?? capturedImage, category.isEmpty ? "other" : category)
                        dismiss()
                    }) {
                        HStack { Spacer(); Text("アップロード").bold(); Spacer() }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        onComplete(nil, nil)
                        dismiss()
                    }) {
                        HStack { Spacer(); Text("キャンセル").bold(); Spacer() }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("写真を追加")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        onComplete(nil, nil)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                ImagePicker(sourceType: .camera) { image in
                    showPicker = false
                    guard let image = image else { return }
                    capturedImage = image
                    Task {
                        processing = true
                        maskedImage = await Self.removeBackground(from: image)
                        processing = false
                    }
                }
            }
        }
    }

    // Background removal using Vision's foreground instance mask request
//    static func removeBackground(from uiImage: UIImage) async -> UIImage? {
//         // 重い処理なのでDetached Taskで実行
//         return await Task.detached(priority: .userInitiated) {
//             guard let cgImage = uiImage.cgImage else { return nil }
            
//             // iOS 17 check
//             if #available(iOS 17.0, *) {
//                 let request = VNGenerateForegroundInstanceMaskRequest()
//                 let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
//                 do {
//                     try handler.perform([request])
//                     guard let result = request.results?.first else { return nil }
//                     let maskBuffer = result.pixelBuffer
                    
//                     // CoreImage処理 (以前のコードと同じロジック)
//                     let ciContext = CIContext()
//                     let ciImage = CIImage(cgImage: cgImage)
//                     let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                    
//                     // スケール合わせと合成
//                     let sx = ciImage.extent.width / maskCI.extent.width
//                     let sy = ciImage.extent.height / maskCI.extent.height
//                     let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    
//                     let filter = CIFilter.blendWithAlphaMask()
//                     filter.inputImage = ciImage
//                     filter.backgroundImage = CIImage(color: .clear).cropped(to: ciImage.extent)
//                     filter.maskImage = scaledMask
                    
//                     if let output = filter.outputImage,
//                        let resultCG = ciContext.createCGImage(output, from: output.extent) {
//                         return UIImage(cgImage: resultCG, scale: uiImage.scale, orientation: uiImage.imageOrientation)
//                     }
//                 } catch {
//                     print("Background removal failed: \(error)")
//                 }
//             }
//             // Fallback for older iOS or error
//             return uiImage
//         }.value
//     }
// }
static func removeBackground(from uiImage: UIImage) async -> UIImage? {
        // 重い処理なのでDetached Taskで実行
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = uiImage.cgImage else { return nil }
            
            // iOS 17 check
            if #available(iOS 17.0, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first else { return nil }
                    let maskBuffer = result.pixelBuffer
                    
                    // CoreImage処理 (以前のコードと同じロジック)
                    let ciContext = CIContext()
                    let ciImage = CIImage(cgImage: cgImage)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                    
                    // スケール合わせと合成
                    let sx = ciImage.extent.width / maskCI.extent.width
                    let sy = ciImage.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    
                    let filter = CIFilter.blendWithAlphaMask()
                    filter.inputImage = ciImage
                    filter.backgroundImage = CIImage(color: .clear).cropped(to: ciImage.extent)
                    filter.maskImage = scaledMask
                    
                    if let output = filter.outputImage,
                       let resultCG = ciContext.createCGImage(output, from: output.extent) {
                        return UIImage(cgImage: resultCG, scale: uiImage.scale, orientation: uiImage.imageOrientation)
                    }
                } catch {
                    print("Background removal failed: \(error)")
                }
            }
            // Fallback for older iOS or error
            return uiImage
        }.value
    }

// UIImagePicker wrapper
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .camera
    var completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var image: UIImage?
            if let edited = info[.editedImage] as? UIImage { image = edited }
            else if let original = info[.originalImage] as? UIImage { image = original }

            parent.completion(image)
            picker.dismiss(animated: true)
        }
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView { _,_ in }
    }
}
