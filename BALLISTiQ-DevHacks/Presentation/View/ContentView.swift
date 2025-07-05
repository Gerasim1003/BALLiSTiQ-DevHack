//
//  ContentView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//

import SwiftUI

enum MainRoute: Hashable {
    case camera
    case video
    case image
    case test
    case videoSharing
}

struct ContentView: View {
    @StateObject private var mainRouter = Router<MainRoute>()
    
    var body: some View {
        NavigationStack(path: $mainRouter.path) {
            MainContentView()
                .navigationBarHidden(true)
                .navigationDestination(for: MainRoute.self) { path in
                    switch path {
                    case .camera:
                        DetectionView(.camera)
                    case .video:
                        DetectionView(.videoFile)
                    case .image:
                        DetectionView(.image)
                    case .test:
                        ErrorCalculatorTestView()
                    case .videoSharing:
                        VideoSharingView()
                    }
                }
                .navigationViewStyle(.stack)
                .environmentObject(mainRouter)
        }
    }
    
    func MainContentView() -> some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Section
                HeaderSection()
                
                ScrollView(.vertical, showsIndicators: false) {
                    
                    // Main Content
                    VStack(spacing: 32) {
                        Spacer()
                        
                        // App Title and Subtitle
                        TitleSection()
                        
                        // Feature Cards
                        FeatureCards()
                        
                        VStack(spacing: 16) {
                            
                            MainActionButton(image: .init(systemName: "camera.fill"), title: "Camera") {
                                mainRouter.push(.camera)
                            }
                            
                            MainActionButton(image: .init(systemName: "video.fill"), title: "Video") {
                                mainRouter.push(.video)
                            }
                            
                            MainActionButton(image: .init(systemName: "photo.fill"), title: "Image") {
                                mainRouter.push(.image)
                            }
                            
                            MainActionButton(image: .init(systemName: "scope"), title: "Test") {
                                mainRouter.push(.test)
                            }
                            
                            MainActionButton(image: .init(systemName: "video.bubble.left"), title: "P2P Streaming") {
                                mainRouter.push(.videoSharing)
                            }
                            
                        }
                        
                        Spacer()
                        
                        // Footer
                        FooterSection()
                    }
                    .padding(.horizontal, 24)
                    
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    @ViewBuilder
    private func HeaderSection() -> some View {
        HStack {
            Image(.appicon)
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .padding(8)
                .background(
                    Capsule()
                        .fill(Color.appBackground.opacity(0.5))
                )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.appPrimary)
    }
    
    // MARK: - Title Section
    
    @ViewBuilder
    private func TitleSection() -> some View {
        VStack(spacing: 12) {
            Text("Shooters Assistant")
                .poppinsFont(size: 32, style: .bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Advanced Bullet Hole Detection Technology")
                .poppinsFont(size: 18, style: .regular)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Feature Cards
    
    @ViewBuilder
    private func FeatureCards() -> some View {
        HStack(spacing: 16) {
            FeatureCard(
                icon: "camera.fill",
                title: "Live Camera",
                subtitle: "Real-time detection"
            )
            
            FeatureCard(
                icon: "video.fill",
                title: "Video Files",
                subtitle: "Frame analysis"
            )
            
            FeatureCard(
                icon: "brain.head.profile",
                title: "YOLO11m",
                subtitle: "AI-powered"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private func FeatureCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.appPrimary)
            
            Text(title)
                .poppinsFont(size: 16, style: .semiBold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .poppinsFont(size: 14, style: .regular)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Main Action Button
    
    @ViewBuilder
    private func MainActionButton(image: Image, title: String, _ action: @escaping () -> ()) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                image
                    .font(.system(size: 20, weight: .medium))
                
                Text(title)
                    .poppinsFont(size: 18, style: .semiBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appPrimary)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PrimaryButtonStyle())
    }
    
    // MARK: - Footer Section
    
    @ViewBuilder
    private func FooterSection() -> some View {
        VStack(spacing: 8) {
            InfoItem(label: "Version", value: "1.0.0")
            
            Text("© 2024 BALLISTiQ")
                .poppinsFont(size: 16, style: .regular)
                .foregroundColor(.gray)
        }
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private func InfoItem(label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .poppinsFont(size: 14, style: .regular)
                .foregroundColor(.gray)
            
            Text(value)
                .poppinsFont(size: 14, style: .medium)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Button Styles
    
    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

#Preview {
    ContentView()
}
