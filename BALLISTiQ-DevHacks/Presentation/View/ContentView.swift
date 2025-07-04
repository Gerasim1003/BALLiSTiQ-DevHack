//
//  ContentView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//

import SwiftUI

enum MainRoute: Hashable {
    case camerDetection
    case videoDetection
}

struct ContentView: View {
    @StateObject private var mainRouter = Router<MainRoute>()
    
    var body: some View {
        NavigationStack(path: $mainRouter.path) {
            MainContentView()
                .navigationBarHidden(true)
                .navigationDestination(for: MainRoute.self) { path in
                    switch path {
                    case .camerDetection:
                        DetectionView(.camera)
                    case .videoDetection:
                        DetectionView(.videoFile)
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
                
                // Main Content
                VStack(spacing: 32) {
                    Spacer()
                    
                    // App Title and Subtitle
                    TitleSection()
                    
                    // Feature Cards
                    FeatureCards()
                    
                    // Main Action Button
                    MainActionButton(image: .init(systemName: "target"), title: "Camera") {
                        mainRouter.push(.camerDetection)
                    }
                    
                    MainActionButton(image: .init(systemName: "target"), title: "Video") {
                        mainRouter.push(.videoDetection)
                    }
                    
                    Spacer()
                    
                    // Footer
                    FooterSection()
                }
                .padding(.horizontal, 24)
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
        .padding(.vertical, 24)
        .background(Color.appPrimary)
    }
    
    // MARK: - Title Section
    
    @ViewBuilder
    private func TitleSection() -> some View {
        VStack(spacing: 12) {
            Text("Assistant Stream")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Advanced Bullet Hole Detection Technology")
                .font(.subheadline)
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
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.caption2)
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
                    .font(.title3)
                    .fontWeight(.semibold)
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
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private func InfoItem(label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
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
