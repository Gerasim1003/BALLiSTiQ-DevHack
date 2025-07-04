//
//  DetectionView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import SwiftUI
import AVFoundation
import AVKit
import PhotosUI

struct DetectionView: View {
    @StateObject private var viewModel: DetectionViewModel
    @State private var selectedVideo: PhotosPickerItem?
    @State private var showingError = false
    @Environment(\.dismiss) var dismiss
    
    init(_ source: InputSource) {
        _viewModel = StateObject(wrappedValue: DetectionViewModel(source))
    }
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with back button and title
                HeaderView()
                
                // Input source selector
//                InputSourceSelector()
                
                // Main preview area
                PreviewArea()
                    .frame(maxHeight: .infinity)
                //
                //                // Detection results overlay
                //                //                if !viewModel.currentResults.detections.isEmpty {
                //                //                    DetectionResultsOverlay()
                //                //                        .transition(.opacity)
                //                //                }
                //
                // Control panel
                ControlPanel()
                
                // Statistics panel
                StatisticsPanel()
            }
        }
        .onAppear(perform: viewModel.onAppear)
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            if case .error(let error) = viewModel.detectionState {
                Text(error.localizedDescription)
            }
        }
        .onChange(of: viewModel.detectionState) { state in
            if case .error = state {
                showingError = true
            }
        }
        .onChange(of: selectedVideo) { newItem in
            handleVideoSelection(newItem)
        }
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private func HeaderView() -> some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Status indicator
                StatusIndicator()
            }
            
            HStack {
                Image(.appicon)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
                    .padding(6)
                    .background(
                        Capsule()
                            .fill(Color.appBackground.opacity(0.5))
                    )
            }
            .background(Color.appPrimary)
            
//            Text("BALLISTiQ")
//                .font(.title2)
//                .fontWeight(.semibold)
//                .foregroundColor(.white)
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.appPrimary)
    }
    
    @ViewBuilder
    private func StatusIndicator() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(viewModel.detectionState == .running ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.detectionState == .running)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    
    private var statusColor: Color {
        switch viewModel.detectionState {
        case .idle:
            return .gray
        case .cameraReady:
            return .blue
        case .initializing:
            return .orange
        case .running:
            return .green
        case .paused:
            return .yellow
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch viewModel.detectionState {
        case .idle:
            return "Ready"
        case .cameraReady:
            return "Camera Ready"
        case .initializing:
            return "Loading..."
        case .running:
            return "Active"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }
    
    // MARK: - Input Source Selector
    
    @ViewBuilder
    private func InputSourceSelector() -> some View {
        
        HStack(spacing: 16) {
            ForEach(InputSource.allCases, id: \.self) { source in
                Button(action: { viewModel.setInputSource(source) }) {
                    HStack(spacing: 8) {
                        Image(systemName: source.iconName)
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(source.title)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(viewModel.currentInputSource == source ? .white : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.currentInputSource == source ? Color.appPrimary : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appPrimary, lineWidth: 1)
                            )
                    )
                }
                .disabled(viewModel.detectionState == .running)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Preview Area
    
    @ViewBuilder
    private func PreviewArea() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            switch viewModel.currentInputSource {
            case .camera:
                CameraPreviewView()
            case .videoFile:
                VideoPreviewView()
            }
            
            // Detection overlays
            DetectionOverlaysView()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private func CameraPreviewView() -> some View {
        if let frame = viewModel.currentFrame {
            FrameView(frame)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                
                Text("Camera Preview")
                    .font(.title3)
                    .foregroundColor(.gray)
                
                if viewModel.detectionState == .initializing {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .fixedSize()
        }
    }
    
    @ViewBuilder
    private func VideoPreviewView() -> some View {
        if let frame = viewModel.currentFrame {
            FrameView(frame)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                
                Text("Select Video File")
                    .font(.title3)
                    .foregroundColor(.gray)
                
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Text("Choose Video")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.appPrimary, lineWidth: 1)
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private func FrameView(_ frame: UIImage) -> some View {
        ZStack {
            Image(uiImage: frame)
                .resizable()
                .scaledToFit()
                .clipped()

            GeometryReader { geometry in
                ForEach(Array(viewModel.bulletHoles.indices), id: \.self) { index in
                    let bulletHole = viewModel.bulletHoles[index]
                    let transformedRect = viewModel.transformRect(
                        from: bulletHole.boundingBox,
                        in: frame.size,
                        to: geometry.size
                    )
                    
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: transformedRect.width, height: transformedRect.height)
                        .position(x: transformedRect.midX, y: transformedRect.midY)
                    
                    Text("ID:\(bulletHole.id)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red)
                        .position(x: transformedRect.midX, y: transformedRect.minY - 10)
                }
                
                if let latestBullet = viewModel.latestBulletHole {
                    let transformedRect = viewModel.transformRect(
                        from: latestBullet.boundingBox,
                        in: frame.size,
                        to: geometry.size
                    )
                    
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                        .position(x: transformedRect.midX, y: transformedRect.midY)
                }
                
                ForEach(Array(viewModel.targets.indices), id: \.self) { index in
                    let target = viewModel.targets[index]
                    let transformedRect = viewModel.transformRect(
                        from: target.boundingBox,
                        in: frame.size,
                        to: geometry.size
                    )
                    
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: transformedRect.width, height: transformedRect.height)
                        .position(x: transformedRect.midX, y: transformedRect.midY)
                    
                    Text("ID:\(target.className)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.green)
                        .position(x: transformedRect.midX, y: transformedRect.minY - 10)
                }
                
//                    ForEach(Array(viewModel.centers.indices), id: \.self) { index in
//                        let center = viewModel.centers[index]
//                        let transformedRect = viewModel.transformRect(
//                            from: center.boundingBox,
//                            in: frame.size,
//                            to: geometry.size
//                        )
//
//                        Rectangle()
//                            .stroke(Color.blue, lineWidth: 2)
//                            .frame(width: transformedRect.width, height: transformedRect.height)
//                            .position(x: transformedRect.midX, y: transformedRect.midY)
//
//                        Text("ID:\(center.className)")
//                            .font(.caption)
//                            .foregroundColor(.white)
//                            .padding(4)
//                            .background(Color.blue)
//                            .position(x: transformedRect.midX, y: transformedRect.minY - 10)
//                    }
            }
        }
    }
    
    @ViewBuilder
    private func DetectionOverlaysView() -> some View {
        GeometryReader { geometry in
            ForEach(viewModel.currentResults.detections) { detection in
                DetectionBoundingBox(
                    detection: detection,
                    frameSize: geometry.size
                )
            }
        }
    }
    
    // MARK: - Detection Results Overlay
    
    @ViewBuilder
    private func DetectionResultsOverlay() -> some View {
        VStack {
            Spacer()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🎯 Detections: \(viewModel.currentResults.detections.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    if !viewModel.currentResults.detections.isEmpty {
                        Text("Avg Confidence: \(Int(viewModel.currentResults.averageConfidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Control Panel
    
    @ViewBuilder
    private func ControlPanel() -> some View {
        HStack(spacing: 20) {
            // Main control button
            Button(action: mainControlAction) {
                HStack(spacing: 8) {
                    Image(systemName: mainControlIcon)
                        .font(.system(size: 18, weight: .medium))
                    
                    Text(mainControlTitle)
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mainControlColor)
                )
            }
            .disabled(!canControlDetection)
            
            // Secondary controls
//            if viewModel.detectionState == .running {
//                Button(action: { viewModel.pauseDetection() }) {
//                    Image(systemName: "pause.fill")
//                        .font(.system(size: 18, weight: .medium))
//                        .foregroundColor(.white)
//                        .padding(12)
//                        .background(
//                            Circle()
//                                .fill(Color.orange)
//                        )
//                }
//            }
            
            if viewModel.currentInputSource == .videoFile && viewModel.selectedVideoURL != nil {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Text("Select Different Video")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.appPrimary, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var mainControlAction: () -> Void {
        switch viewModel.detectionState {
        case .idle, .cameraReady, .paused:
            return { viewModel.startDetection() }
        case .running:
            return { viewModel.stopDetection() }
        default:
            return { }
        }
    }
    
    private var mainControlIcon: String {
        switch viewModel.detectionState {
        case .idle, .cameraReady, .paused:
            return "play.fill"
        case .running:
            return "stop.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var mainControlTitle: String {
        switch viewModel.detectionState {
        case .idle, .cameraReady:
            return "Start"
        case .paused:
            return "Resume"
        case .running:
            return "Stop"
        case .initializing:
            return "Loading..."
        case .error:
            return "Error"
        }
    }
    
    private var mainControlColor: Color {
        switch viewModel.detectionState {
        case .idle, .cameraReady, .paused:
            return .green
        case .running:
            return .red
        case .initializing:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var canControlDetection: Bool {
        switch viewModel.detectionState {
        case .idle, .cameraReady, .running, .paused:
            return viewModel.currentInputSource == .camera || viewModel.selectedVideoURL != nil
        default:
            return false
        }
    }
    
    // MARK: - Statistics Panel
    
    @ViewBuilder
    private func StatisticsPanel() -> some View {
        HStack(spacing: 24) {
            StatItem(
                title: "Frames",
                value: "\(viewModel.currentResults.frameCount)",
                icon: "camera.viewfinder"
            )
            
            StatItem(
                title: "Processing",
                value: String(format: "%.1fms", viewModel.currentResults.processingTime * 1000),
                icon: "timer"
            )
            
            StatItem(
                title: "FPS",
                value: viewModel.currentResults.processingTime > 0 ? String(format: "%.1f", 1.0 / viewModel.currentResults.processingTime) : "0",
                icon: "speedometer"
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
    }
    
    @ViewBuilder
    private func StatItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Supporting Views
    
    struct CameraPreview: UIViewRepresentable {
        let previewLayer: AVCaptureVideoPreviewLayer
        
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.layer.addSublayer(previewLayer)
            return view
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    struct DetectionBoundingBox: View {
        let detection: BulletHoleDetection
        let frameSize: CGSize
        
        var body: some View {
            let box = convertBoundingBox(detection.boundingBox, to: frameSize)
            
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
        }
        
        private func convertBoundingBox(_ boundingBox: CGRect, to frameSize: CGSize) -> CGRect {
            // Vision framework uses normalized coordinates (0-1)
            // Convert to actual pixel coordinates
            let x = boundingBox.minX * frameSize.width
            let y = (1 - boundingBox.maxY) * frameSize.height // Flip Y coordinate
            let width = boundingBox.width * frameSize.width
            let height = boundingBox.height * frameSize.height
            
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
    
    // MARK: - Button Styles
    
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.appPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appPrimary, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleVideoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            do {
                guard let movieData = try await item.loadTransferable(type: VideoFile.self) else {
                    print("❌ [BALLISTiQ] Failed to load video from PhotosPicker")
                    return
                }
                
                await MainActor.run {
                    viewModel.selectVideoFile(movieData.url)
                }
            } catch {
                print("❌ [BALLISTiQ] Video selection failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - VideoFile Transferable

struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let fileName = received.file.lastPathComponent
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoFile(url: tempURL)
        }
    }
}

//#Preview {
//    DetectionView()
//}
