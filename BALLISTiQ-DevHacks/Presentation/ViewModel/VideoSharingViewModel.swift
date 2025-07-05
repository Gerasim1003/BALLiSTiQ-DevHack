//
//  DetectionView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 05.07.25.
//

import SwiftUI
import MultipeerConnectivity
import AVFoundation
import Combine

// MARK: - Models and Enums

enum PeerConnectionState {
    case notConnected
    case connecting
    case connected
}

struct PeerInfo: Identifiable {
    let id = UUID()
    let peerID: MCPeerID
    let state: MCSessionState
}

struct DetectionData: Codable {
    let bulletHoles: [TrackedObjectData]
    let targets: [TrackedObjectData]
    let centers: [TrackedObjectData]
    let latestBulletHole: TrackedObjectData?
    let shotResult: ShotResultData?
}

struct TrackedObjectData: Codable {
    let id: Int
    let boundingBox: CGRect
    let confidence: Float
    let className: String
    let targetType: String // We'll convert TargetType to String for transmission
    
    init(from trackedObject: TrackedObject) {
        self.id = trackedObject.id
        self.boundingBox = trackedObject.boundingBox
        self.confidence = trackedObject.confidence
        self.className = trackedObject.className
        self.targetType = String(describing: trackedObject.targetType)
    }
    
    func toTrackedObject() -> TrackedObject {
        let type: TargetType
        switch targetType {
        case "bullet_hole":
            type = .bullet_hole
        case "target":
            type = .target
        case "center":
            type = .center
        default:
            type = .bullet_hole
        }
        
        return TrackedObject(
            id: id,
            boundingBox: boundingBox,
            confidence: confidence,
            className: className,
            targetType: type
        )
    }
}

struct ShotResultData: Codable {
    let bulletHoleId: Int
    let closestTargetClassName: String
    let distance: Double
    let clockRegion: Int
    
    init(from shotResult: ShotResult) {
        self.bulletHoleId = shotResult.bulletHole.id
        self.closestTargetClassName = shotResult.closestTarget.className
        self.distance = shotResult.distance
        self.clockRegion = shotResult.clockRegion
    }
}

struct FrameWithDetection: Codable {
    let imageData: Data
    let detectionData: DetectionData?
}

// MARK: - VideoSharingViewModel

@MainActor
class VideoSharingViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isStreaming = false
    @Published var connectionState: PeerConnectionState = .notConnected
    @Published var peers: [PeerInfo] = []
    @Published var localFrame: UIImage?
    @Published var remoteFrame: UIImage?
    @Published var isInitialized = false
    
    // Detection system integration
    @Published var localBulletHoles: [TrackedObject] = []
    @Published var localTargets: [TrackedObject] = []
    @Published var localCenters: [TrackedObject] = []
    @Published var localLatestBulletHole: TrackedObject?
    @Published var localShotResult: ShotResult?
    
    @Published var remoteBulletHoles: [TrackedObject] = []
    @Published var remoteTargets: [TrackedObject] = []
    @Published var remoteCenters: [TrackedObject] = []
    @Published var remoteLatestBulletHole: TrackedObject?
    @Published var remoteShotResult: ShotResult?
    
    // MARK: - Private Properties
    private let serviceType = "ballistiq-p2p"
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // Camera components
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoQueue = DispatchQueue(label: "video.queue")
    
    // Video simulation components
    private var simulationPlayer: AVPlayer?
    private var simulationPlayerItem: AVPlayerItem?
    private var simulationVideoOutput: AVPlayerItemVideoOutput?
    private var simulationTimer: Timer?
    
    // Frame processing
    private var frameTimer: Timer?
    nonisolated(unsafe) private var lastFrameTime: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 15.0 // 15 FPS
    
    // Detection system components
    @Published private var shotDetector = ShotDetector()
    @Published private var objectTracker = ObjectTracker()
    @Published private var errorCalculator = ErrorCalculator()
    private var speechManager = SpeechManager()
    @Published var detectedHoleIDs: [Int] = []
    @Published var detectedTargetIDs: [Int] = []
    
    // Orientation testing - using UI rotation instead of backend rotation
    private let useImageRotation = false // Disabled - using UI rotation instead
    private let cameraOrientation: AVCaptureVideoOrientation = .portrait // Default orientation
    
    // Video simulation for simulator testing
    private let simulationVideoPath = "test_target2.mp4" // Change this to your video file name
    private var isUsingVideoSimulation: Bool {
        true
//        #if targetEnvironment(simulator)
//        return true
//        #else
//        return false
//        #endif
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupMultipeerConnectivity()
        setupCamera()
        print("🎥 [VideoSharing] Initialized - Mode: \(isUsingVideoSimulation ? "Video Simulation" : "Real Camera")")
    }
    
//    deinit {
//        stop()
//    }
    
    // MARK: - Public Methods
    
    func start() {
        guard !isStreaming else { return }
        
        print("🎥 [VideoSharing] Starting video streaming")
        
        startAdvertising()
        startBrowsing()
        startCamera()
        startFrameCapture()
        
        isStreaming = true
        isInitialized = true
    }
    
    func stop() {
        print("🎥 [VideoSharing] Stopping video streaming")
        
        stopFrameCapture()
        stopCamera()
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        
        // Clean up simulation components
        if isUsingVideoSimulation {
            cleanupVideoSimulation()
        }
        
        isStreaming = false
        connectionState = .notConnected
        localFrame = nil
        remoteFrame = nil
        peers.removeAll()
    }
    
    private func cleanupVideoSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simulationPlayer?.pause()
        simulationPlayer = nil
        simulationPlayerItem = nil
        simulationVideoOutput = nil
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    func invitePeer(_ peer: PeerInfo) {
        print("🎥 [VideoSharing] Inviting peer: \(peer.peerID.displayName)")
        browser.invitePeer(peer.peerID, to: session, withContext: nil, timeout: 10)
    }
    
    // MARK: - Private Methods
    
    private func setupMultipeerConnectivity() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
    }
    
    private func setupCamera() {
        if isUsingVideoSimulation {
            setupVideoSimulation()
        } else {
            setupRealCamera()
        }
    }
    
    private func setupRealCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ [VideoSharing] Failed to setup camera")
            return
        }
        
        captureSession.addInput(input)
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        captureSession.addOutput(videoOutput)
        
        // Fix video orientation after adding output
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = cameraOrientation
                print("🎥 [VideoSharing] Set camera orientation to: \(cameraOrientation)")
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        
        print("🎥 [VideoSharing] Real camera setup complete")
    }
    
    private func setupVideoSimulation() {
        print("🎥 [VideoSharing] Setting up video simulation with: \(simulationVideoPath)")
        
        // Try to find the video file in the bundle
        guard let videoURL = Bundle.main.url(forResource: simulationVideoPath.replacingOccurrences(of: ".mp4", with: ""), withExtension: "mp4") else {
            print("❌ [VideoSharing] Simulation video file not found: \(simulationVideoPath)")
            print("ℹ️ [VideoSharing] Please add your video file to the app bundle")
            return
        }
        
        // Create player item and player
        simulationPlayerItem = AVPlayerItem(url: videoURL)
        simulationPlayer = AVPlayer(playerItem: simulationPlayerItem)
        
        // Create video output for frame extraction
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        simulationVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        simulationPlayerItem?.add(simulationVideoOutput!)
        
        // Set up looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: simulationPlayerItem
        )
        
        print("🎥 [VideoSharing] Video simulation setup complete")
    }
    
    private func startCamera() {
        if isUsingVideoSimulation {
            startVideoSimulation()
        } else {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    private func stopCamera() {
        if isUsingVideoSimulation {
            stopVideoSimulation()
        } else {
            captureSession?.stopRunning()
        }
    }
    
    private func startVideoSimulation() {
        guard let player = simulationPlayer else { return }
        
        // Start playing the video
        player.play()
        
        // Start timer to extract frames
        simulationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.extractSimulationFrame()
        }
        
        print("🎥 [VideoSharing] Video simulation started")
    }
    
    private func stopVideoSimulation() {
        simulationPlayer?.pause()
        simulationTimer?.invalidate()
        simulationTimer = nil
        print("🎥 [VideoSharing] Video simulation stopped")
    }
    
    @objc private func playerItemDidReachEnd() {
        // Loop the video
        simulationPlayer?.seek(to: .zero)
        simulationPlayer?.play()
    }
    
    private func extractSimulationFrame() {
        guard let videoOutput = simulationVideoOutput,
              let player = simulationPlayer else { return }
        
        let currentTime = player.currentTime()
        
        if videoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
            guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
                return
            }
            
            // Convert pixel buffer to UIImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            let uiImage = UIImage(cgImage: cgImage)
            
            // Process the frame like we do with camera frames
            Task { @MainActor in
                let finalImage = self.useImageRotation ? self.fixImageOrientation(uiImage) : uiImage
                
                self.localFrame = finalImage
                self.lastFrameTime = CACurrentMediaTime()
                
                // Run detection on the frame
                await self.processDetection(finalImage, frameID: Int(CACurrentMediaTime() * 1000))
                
                // Send frame to connected peers
                if self.isStreaming {
                    self.sendFrame(finalImage)
                }
            }
        }
    }
    
    private func startAdvertising() {
        advertiser.startAdvertisingPeer()
        print("🎥 [VideoSharing] Started advertising")
    }
    
    private func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        print("🎥 [VideoSharing] Stopped advertising")
    }
    
    private func startBrowsing() {
        browser.startBrowsingForPeers()
        print("🎥 [VideoSharing] Started browsing")
    }
    
    private func stopBrowsing() {
        browser.stopBrowsingForPeers()
        print("🎥 [VideoSharing] Stopped browsing")
    }
    
    private func startFrameCapture() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            // Timer is just for pacing, actual frame capture happens in delegate
        }
    }
    
    private func stopFrameCapture() {
        frameTimer?.invalidate()
        frameTimer = nil
    }
    
    private func sendFrame(_ image: UIImage) {
        guard session.connectedPeers.count > 0 else { return }
        
        // Compress image for network transmission
        guard let imageData = image.jpegData(compressionQuality: 0.3) else { return }
        
        // Create detection data
        let detectionData = DetectionData(
            bulletHoles: localBulletHoles.map { TrackedObjectData(from: $0) },
            targets: localTargets.map { TrackedObjectData(from: $0) },
            centers: localCenters.map { TrackedObjectData(from: $0) },
            latestBulletHole: localLatestBulletHole.map { TrackedObjectData(from: $0) },
            shotResult: localShotResult.map { ShotResultData(from: $0) }
        )
        
        // Create frame with detection data
        let frameWithDetection = FrameWithDetection(
            imageData: imageData,
            detectionData: detectionData
        )
        
        // Encode and send
        do {
            let encodedData = try JSONEncoder().encode(frameWithDetection)
            try session.send(encodedData, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("❌ [VideoSharing] Failed to send frame with detection: \(error)")
        }
    }
    
    private func processReceivedFrame(_ data: Data) {
        do {
            // Try to decode as FrameWithDetection
            let frameWithDetection = try JSONDecoder().decode(FrameWithDetection.self, from: data)
            guard let image = UIImage(data: frameWithDetection.imageData) else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.remoteFrame = image
                
                // Update remote detection data
                if let detectionData = frameWithDetection.detectionData {
                    self?.remoteBulletHoles = detectionData.bulletHoles.map { $0.toTrackedObject() }
                    self?.remoteTargets = detectionData.targets.map { $0.toTrackedObject() }
                    self?.remoteCenters = detectionData.centers.map { $0.toTrackedObject() }
                    self?.remoteLatestBulletHole = detectionData.latestBulletHole?.toTrackedObject()
                    
                    // For shot result, we'll create a simple representation
                    // Note: We can't recreate the full ShotResult object without all the enhanced target data
                    if let shotResultData = detectionData.shotResult {
                        print("🎯 [VideoSharing] Remote shot result - Target: \(shotResultData.closestTargetClassName), Distance: \(shotResultData.distance), Clock: \(shotResultData.clockRegion)")
                    }
                } else {
                    // Clear remote detection data if none received
                    self?.remoteBulletHoles = []
                    self?.remoteTargets = []
                    self?.remoteCenters = []
                    self?.remoteLatestBulletHole = nil
                    self?.remoteShotResult = nil
                }
            }
        } catch {
            // Fallback: try to decode as plain image data (backward compatibility)
            guard let image = UIImage(data: data) else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.remoteFrame = image
                // Clear detection data for plain frames
                self?.remoteBulletHoles = []
                self?.remoteTargets = []
                self?.remoteCenters = []
                self?.remoteLatestBulletHole = nil
                self?.remoteShotResult = nil
            }
        }
    }
    
    private func updateConnectionState() {
        if session.connectedPeers.count > 0 {
            connectionState = .connected
        } else {
            connectionState = .notConnected
        }
    }
    
    private func updatePeersList() {
        let currentPeers = session.connectedPeers.map { peerID in
            PeerInfo(peerID: peerID, state: .connected)
        }
        peers = currentPeers
    }
    
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // Rotate the image 90 degrees counter-clockwise to fix orientation
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create context with swapped dimensions for 90-degree rotation
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: height,
            height: width,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        
        // Apply rotation transform (90 degrees clockwise)
        context.translateBy(x: 0, y: CGFloat(width))
        context.rotate(by: -.pi / 2)
        
        // Draw the image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let rotatedCGImage = context.makeImage() else { return image }
        
        return UIImage(cgImage: rotatedCGImage)
    }
    
    // MARK: - Detection Processing
    
    private func processDetection(_ frame: UIImage, frameID: Int) async {
        let isDetectorRunning = await shotDetector.getIsRunning()
        if !isDetectorRunning {
            await shotDetector.submitFrame(frame, frameId: frameID)
        }
        
        if let result = await shotDetector.getLatestDetections() {
            let updatedTrackedObjects = await objectTracker.update(with: result)
            let bulletHole = await objectTracker.getLatestBulletHole()
            
            let filteredBulletHoles = updatedTrackedObjects.filter { $0.targetType == .bullet_hole }
            let filteredTargets = updatedTrackedObjects.filter { $0.targetType == .target }
            let filteredCenters = updatedTrackedObjects.filter { $0.targetType == .center }
            
            await MainActor.run {
                self.localBulletHoles = filteredBulletHoles
                self.localTargets = filteredTargets
                self.localCenters = filteredCenters
                self.localLatestBulletHole = bulletHole
                
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
                        print("🎯 [VideoSharing] Local Shot Result - ID: \(shotResult.bulletHole.id), distance: \(shotResult.distance), clock: \(shotResult.clockRegion)")
                    }
                    
                    self.localShotResult = shotResult
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
        
//        let announcement = "Target detected: \(targetName)"
//        print("🎯 [VideoSharing] \(announcement)")
//        speechManager.speak(text: announcement)
    }
    
    private func announceBulletHole(_ bulletHole: TrackedObject) {
//        let announcement = "Bullet hole detected"
//        print("🎯 [VideoSharing] \(announcement)")
//        speechManager.speak(text: announcement)
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
        
//        // Add accuracy assessment
//        if shotResult.distance < 10 {
//            announcement += ". Excellent shot!"
//        } else if shotResult.distance < 20 {
//            announcement += ". Good shot!"
//        } else if shotResult.distance < 30 {
//            announcement += ". Fair shot."
//        } else {
//            announcement += ". Keep practicing!"
//        }
        
        print("🎯 [VideoSharing] \(announcement)")
        speechManager.speak(text: announcement)
    }
    
    // MARK: - Helper Methods for Detection Overlays
    
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoSharingViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        
        // Rate limiting to maintain target FPS
        if currentTime - lastFrameTime < frameInterval {
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Create UIImage
        let rawImage = UIImage(cgImage: cgImage)
        
        Task { @MainActor in
            // Apply rotation if enabled
            let finalImage = self.useImageRotation ? self.fixImageOrientation(rawImage) : rawImage
            
            self.localFrame = finalImage
            self.lastFrameTime = currentTime
            
            // Run detection on the frame
            await self.processDetection(finalImage, frameID: Int(currentTime * 1000))
            
            // Send frame to connected peers
            if self.isStreaming {
                self.sendFrame(finalImage)
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension VideoSharingViewModel: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🎥 [VideoSharing] Peer \(peerID.displayName) changed state to: \(state.rawValue)")
        
        Task { @MainActor in
            self.updateConnectionState()
            self.updatePeersList()
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Received frame data from peer
        Task { @MainActor in
            self.processReceivedFrame(data)
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension VideoSharingViewModel: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("🎥 [VideoSharing] Received invitation from: \(peerID.displayName)")
        
        // Auto-accept invitations for hackathon demo
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension VideoSharingViewModel: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🎥 [VideoSharing] Found peer: \(peerID.displayName)")
        
        Task { @MainActor in
            let newPeer = PeerInfo(peerID: peerID, state: .notConnected)
            if !self.peers.contains(where: { $0.peerID == peerID }) {
                self.peers.append(newPeer)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("🎥 [VideoSharing] Lost peer: \(peerID.displayName)")
        
        Task { @MainActor in
            self.peers.removeAll { $0.peerID == peerID }
        }
    }
}
