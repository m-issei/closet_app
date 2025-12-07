import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // First view: large weather
                if let weather = vm.weather {
                    VStack(spacing: 8) {
                        Text(weather.weather)
                            .font(.largeTitle)
                            .bold()
                        Text(String(format: "%.0f°C", weather.tempC))
                            .font(.system(size: 48, weight: .heavy))
                    }
                    .padding()
                } else {
                    Text("天気情報を取得中...")
                        .font(.title2)
                        .padding()
                }

                // Main content
                VStack(spacing: 12) {
                    Button(action: {
                        Task { await vm.refresh() }
                    }) {
                        HStack {
                            Spacer()
                            Text("今日のコーデを提案")
                                .bold()
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    if vm.state == .loading {
                        // skeleton / indicator
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    }

                    if let rec = vm.recommendation {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(rec.clothes, id: \.id) { cloth in
                                    AsyncImage(url: URL(string: cloth.imageURL)) { phase in
                                        switch phase {
                                        case .empty:
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 140, height: 200)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 200)
                                                .clipped()
                                        case .failure:
                                            Rectangle()
                                                .fill(Color.red.opacity(0.2))
                                                .frame(width: 140, height: 200)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Text("選定理由")
                            .font(.headline)
                            .padding(.top, 8)

                        Text(rec.reason)
                            .font(.body)
                            .padding(.horizontal)
                            .multilineTextAlignment(.leading)

                        Button(action: {
                            Task { await vm.confirmWear() }
                        }) {
                            HStack {
                                Spacer()
                                Text("これを着る")
                                    .bold()
                                Spacer()
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 8)
                    }

                    if case let .error(msg) = vm.state {
                        Text("エラー: \(msg)")
                            .foregroundColor(.red)
                    }
                }

                Spacer()
            }
            .navigationTitle("ホーム")
            .onAppear {
                vm.start()
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
