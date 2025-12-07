import SwiftUI

struct WardrobeView: View {
    @StateObject private var vm = WardrobeViewModel()
    @State private var showingCamera = false
    @State private var isUploading = false

    var body: some View {
        NavigationView {
            Group {
                if vm.state == .loading && vm.clothes.isEmpty {
                    ProgressView()
                } else if vm.clothes.isEmpty {
                    Text("まだ服が登録されていません")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(vm.clothes, id: \.id) { cloth in
                                AsyncImage(url: URL(string: cloth.imageURL)) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 160)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 160)
                                            .clipped()
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.red.opacity(0.2))
                                            .frame(height: 160)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("クローゼット")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCamera = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView { image, category in
                    // callback after capture + mask
                    showingCamera = false
                    guard let img = image else { return }
                    Task {
                        isUploading = true
                        await vm.addCloth(image: img, category: category ?? "other")
                        isUploading = false
                    }
                }
            }
            .onAppear {
                Task { await vm.loadClothes() }
            }
        }
    }
}

struct WardrobeView_Previews: PreviewProvider {
    static var previews: some View {
        WardrobeView()
    }
}
