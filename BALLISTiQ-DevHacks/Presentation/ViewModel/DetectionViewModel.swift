//
//  InputSource.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation
import SwiftUI
@preconcurrency import AVFoundation
import CoreML
import Combine

// MARK: - Models and Enums

enum InputSource: CaseIterable {
    case camera
    case videoFile
    
    var title: String {
        switch self {
        case .camera:
            return "Live Camera"
        case .videoFile:
            return "Video File"
        }
    }
    
    var iconName: String {
        switch self {
        case .camera:
            return "camera.fill"
        case .videoFile:
            return "video.fill"
        }
    }
}

enum DetectionState: Equatable {
    case idle
    case cameraReady  // New state: camera is ready but model not loaded
    case initializing
    case running
    case paused
    case error(DetectionError)
}

enum DetectionError: LocalizedError, Equatable {
    case cameraPermissionDenied
    case cameraNotAvailable
    case videoFileNotFound
    case videoFileInvalid
    case modelLoadingFailed
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .cameraNotAvailable:
            return "Camera is not available on this device."
        case .videoFileNotFound:
            return "Selected video file could not be found."
        case .videoFileInvalid:
            return "Selected video file format is not supported."
        case .modelLoadingFailed:
            return "Failed to load BALLISTiQ detection model."
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        }
    }
}

struct BulletHoleDetection: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: Date
    
    var confidencePercentage: Int {
        Int(confidence * 100)
    }
}

// MARK: - Detection Results

struct DetectionResults {
    var detections: [BulletHoleDetection] = []
    var frameCount: Int = 0
    var processingTime: TimeInterval = 0
    
    var averageConfidence: Float {
        guard !detections.isEmpty else { return 0 }
        return detections.reduce(0) { $0 + $1.confidence } / Float(detections.count)
    }
}

// MARK: - ViewModel

@MainActor
class DetectionViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var currentInputSource: InputSource = .camera
    @Published var detectionState: DetectionState = .idle
    @Published var currentResults = DetectionResults()
    @Published var isPlaying = false
    @Published var selectedVideoURL: URL?
    
    @Published private var shotDetector = ShotDetector()
    @Published private var objectTracker = ObjectTracker()
    @Published private var frameProvider: FrameProvider?
    @Published private var errorCalculator = ErrorCalculator()
    @Published var currentFrame: UIImage?
    
    @Published var trackedObjects: [TrackedObject] = []
    @Published var bulletHoles: [TrackedObject] = []
    @Published var targets: [TrackedObject] = []
    @Published var centers: [TrackedObject] = []
    @Published var latestBulletHole: TrackedObject?
    @Published var shotResult: ShotResult?
    
    // MARK: - Private Properties
    
    private let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(_ source: InputSource) {
        super.init()
        self.setInputSource(source)
        logInfo("BALLISTiQ DetectionViewModel initialized")
        // Model loading is now deferred until startDetection() is called
        
        timer
            .sink { [weak self] _ in
                print("BALLISTiQ Timer tick")
                guard let self = self, (self.detectionState == .cameraReady && self.currentInputSource == .camera) || self.detectionState == .running else { return }
                
                print("BALLISTiQ Processing frame...")
                
                Task { await self.processFrame() }
            }
            .store(in: &cancellables)
    }
    
    
    //    deinit {
    //        cleanup()
    //        logInfo("BALLISTiQ DetectionViewModel deinitialized")
    //    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        if currentInputSource == .camera {
            frameProvider?.start()            
        }
    }
    
    func setInputSource(_ source: InputSource) {
        logInfo("BALLISTiQ switching input source from \(currentInputSource.title) to \(source.title)")
        
        cleanup()
        currentInputSource = source
        currentResults = DetectionResults()
        
        detectionState = .cameraReady
        
        switch source {
        case .camera:
            frameProvider = CameraFrameProvider()
        case .videoFile:
            detectionState = .idle
        }
    }
    
    func startDetection() {
        guard detectionState != .running else { return }
        
        logInfo("BALLISTiQ starting detection with \(currentInputSource.title)")
        
        startProcessing()
    }
    
    func stopDetection() {
        cleanup()
    }
    
    func selectVideoFile(_ url: URL) {
        logInfo("BALLISTiQ selected video file: \(url.lastPathComponent)")
        
        selectedVideoURL = url
        
        frameProvider = VideoFrameProvider(videoURL: url)
    }
    
    func transformRect(from rect: CGRect, in imageSize: CGSize, to viewSize: CGSize) -> CGRect {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        
        let offsetX = (viewSize.width - scaledImageWidth) / 2
        let offsetY = (viewSize.height - scaledImageHeight) / 2
        
        let transformedX = rect.origin.x * scale + offsetX
        let transformedY = rect.origin.y * scale + offsetY
        let transformedWidth = rect.size.width * scale
        let transformedHeight = rect.size.height * scale
        
        return CGRect(x: transformedX, y: transformedY, width: transformedWidth, height: transformedHeight)
    }
    
    // MARK: - Private Methods
    
    nonisolated private func cleanup() {
        Task { @MainActor in
            frameProvider?.stop()
            
//            cancellables.removeAll()
        }
    }
    
    private func processFrame() async {
        guard let provider = frameProvider,
              let frame = provider.getLatestFrame() else {
            return
        }
        
        let frameId = provider.getLatestFrameId()
        
        await MainActor.run {
            currentFrame = frame
        }
        
        if detectionState == .running {
            let isDetectorRunning = await shotDetector.getIsRunning()
            if !isDetectorRunning {
                await shotDetector.submitFrame(frame, frameId: frameId)
            }
            
            if let result = await shotDetector.getLatestDetections() {
                let updatedTrackedObjects = await objectTracker.update(with: result)
                let bulletHole = await objectTracker.getLatestBulletHole()
                
                let filteredBulletHoles = updatedTrackedObjects.filter { $0.targetType == .bullet_hole }
                let filteredTargets = updatedTrackedObjects.filter { $0.targetType == .target }
                let filteredCenters = updatedTrackedObjects.filter { $0.targetType == .center }
                
                await MainActor.run {
                    self.trackedObjects = updatedTrackedObjects
                    self.bulletHoles = filteredBulletHoles
                    self.targets = filteredTargets
                    self.centers = filteredCenters
                    self.latestBulletHole = bulletHole
                    
                    if let bulletHole = bulletHole, !filteredCenters.isEmpty {
                        self.shotResult = self.errorCalculator.calculateShotResult(centers: filteredCenters, bulletHole: bulletHole)
                    }
                }
            }
        }
    }
    
    private func startProcessing() {
        guard let provider = frameProvider else {
//            errorMessage = "Frame provider not initialized"
            return
        }
        
        if !provider.isReady {
//            errorMessage = "Frame provider not ready"
            return
        }
        
        provider.start()
//        isRunning = true
//        errorMessage = nil
//        updateStatus()
//        print("[VideoDetectionView] Started processing")
    }
    
    // MARK: - Logging
    
    nonisolated private func logInfo(_ message: String) {
        print("ℹ️ [BALLISTiQ] \(message)")
    }
    
    nonisolated private func logError(_ message: String) {
        print("❌ [BALLISTiQ] ERROR: \(message)")
    }
}
