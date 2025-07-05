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
    case image
}

enum DetectionState: Equatable {
    case idle
    case cameraReady  // New state: camera is ready but model not loaded
    case initializing
    case running
    case paused
    case error(DetectionError)
    
    var mainControlIcon: String {
        switch self {
        case .idle, .cameraReady, .paused:
            return "play.fill"
        case .running:
            return "stop.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var mainControlTitle: String {
        switch self {
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
    
    var mainControlColor: Color {
        switch self {
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

// MARK: - ViewModel

@MainActor
class DetectionViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var currentInputSource: InputSource = .camera
    @Published var detectionState: DetectionState = .idle
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
    
    private var speechManager = SpeechManager()
    
    @Published var detectedHoleIDs: [Int] = []
    @Published var detectedTargetIDs: [Int] = []
    
    // MARK: - Private Properties
    
    private let timer = Timer.publish(every: 1.0/10.0, on: .main, in: .common).autoconnect()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(_ source: InputSource) {
        super.init()
        self.setInputSource(source)
        logInfo("BALLISTiQ DetectionViewModel initialized")
        // Model loading is now deferred until startDetection() is called
        
        if currentInputSource != .image {
            timer
                .sink { [weak self] _ in
                    print("BALLISTiQ Timer tick")
                    guard let self = self, (self.detectionState == .cameraReady && self.currentInputSource == .camera) || self.detectionState == .running else { return }
                    
                    print("BALLISTiQ Processing frame...")
                    
                    Task { await self.processFrame() }
                }
                .store(in: &cancellables)
        }
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
        cleanup()
        currentInputSource = source
//        currentResults = DetectionResults()
        
        detectionState = .cameraReady
        
        switch source {
        case .camera:
            frameProvider = CameraFrameProvider()
        case .videoFile, .image:
            detectionState = .idle
        }
    }
    
    func startDetection() {
        guard detectionState != .running else { return }
        
        logInfo("BALLISTiQ starting detection")
        
        detectionState = .running
        
        startProcessing()
    }
    
    func stopDetection() {
        detectionState = .paused
        cleanup()
    }
    
    func selectVideoFile(_ url: URL) {
        logInfo("BALLISTiQ selected video file: \(url.lastPathComponent)")
        
        selectedVideoURL = url
        
        frameProvider = VideoFrameProvider(videoURL: url)
    }
    
    func selectImageFile(_ url: URL) {
        logInfo("BALLISTiQ selected image file: \(url.lastPathComponent)")
        
        // get uiimage from url
        guard let image = UIImage(contentsOfFile: url.path) else {
            detectionState = .error(.videoFileInvalid)
            return
        }
        
        self.currentFrame = image
        self.detectionState = .running
        
        Task {
            await submitFrame(image, frameID: 0)
            
            // Call again after a 2‑second delay
            try? await Task.sleep(for: .seconds(2))
            await submitFrame(image, frameID: 0)
        }
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
        
        await submitFrame(frame, frameID: frameId)
    }
    
    func submitFrame(_ frame: UIImage, frameID: Int?) async {
        if detectionState == .running {
            let isDetectorRunning = await shotDetector.getIsRunning()
            if !isDetectorRunning {
                await shotDetector.submitFrame(frame, frameId: frameID ?? 0)
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
                    
                    // Announce new targets detected
                    self.announceNewTargets(filteredTargets)
                    
                    // Announce new bullet holes and calculate shot results
                    if let bulletHole = bulletHole, !filteredCenters.isEmpty {
                        let shotResult = self.errorCalculator.calculateShotResult(centers: filteredCenters, bulletHole: bulletHole)
                        
                        if let shotResult {
                            if !detectedHoleIDs.contains(shotResult.bulletHole.id) {
                                detectedHoleIDs.append(shotResult.bulletHole.id)
                                self.announceShotResult(shotResult)
                            }
                            print("🎯 [BALLISTiQ] Shot Result - ID: \(shotResult.bulletHole.id), distance: \(shotResult.distance), row: \(shotResult.hitGridCell?.row ?? -1), col: \(shotResult.hitGridCell?.column ?? -1)")
                        }
                        
                        self.shotResult = shotResult
                    } else if let bulletHole = bulletHole {
                        // Announce bullet hole detected even without targets
                        if !detectedHoleIDs.contains(bulletHole.id) {
                            detectedHoleIDs.append(bulletHole.id)
                            self.announceBulletHole(bulletHole)
                        }
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
    
    // MARK: - Speech Synthesis Methods
    
    private func announceNewTargets(_ targets: [TrackedObject]) {
        for target in targets {
            if !detectedTargetIDs.contains(target.id) {
                detectedTargetIDs.append(target.id)
                announceTarget(target)
            }
        }
    }
    
    private func announceTarget(_ target: TrackedObject) {
        let targetName = target.className
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        
        let announcement = "Target detected: \(targetName)"
        print("🎯 [BALLISTiQ] \(announcement)")
        speechManager.speak(text: announcement)
    }
    
    private func announceBulletHole(_ bulletHole: TrackedObject) {
        let announcement = "Bullet hole detected"
        print("🎯 [BALLISTiQ] \(announcement)")
        speechManager.speak(text: announcement)
    }
    
    private func announceShotResult(_ shotResult: ShotResult) {
        let targetNumber = shotResult.closestTarget.className
            .split(separator: "_").last.map(String.init) ?? ""
        
        let clockRegion = shotResult.clockRegion
        let distance = String(format: "%.1f", shotResult.distance)
        
        var announcement = "Shot detected"
        
        if !targetNumber.isEmpty {
            announcement += " at target \(targetNumber)"
        }
        
        if clockRegion > 0 {
            announcement += " at \(clockRegion) o'clock"
        }
        
        if shotResult.distance > 0 {
            announcement += ", distance \(distance) units"
        }
        
        // Add accuracy assessment
        if shotResult.distance < 10 {
            announcement += ". Excellent shot!"
        } else if shotResult.distance < 20 {
            announcement += ". Good shot!"
        } else if shotResult.distance < 30 {
            announcement += ". Fair shot."
        } else {
            announcement += ". Keep practicing!"
        }
        
        print("🎯 [BALLISTiQ] \(announcement)")
        speechManager.speak(text: announcement)
    }
    
    // MARK: - Logging
    
    nonisolated private func logInfo(_ message: String) {
        print("ℹ️ [BALLISTiQ] \(message)")
    }
    
    nonisolated private func logError(_ message: String) {
        print("❌ [BALLISTiQ] ERROR: \(message)")
    }
}
