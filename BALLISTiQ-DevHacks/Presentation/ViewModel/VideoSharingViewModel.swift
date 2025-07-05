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
    
    // Frame processing
    private var frameTimer: Timer?
    nonisolated(unsafe) private var lastFrameTime: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 15.0 // 15 FPS
    
    // Orientation testing - using UI rotation instead of backend rotation
    private let useImageRotation = false // Disabled - using UI rotation instead
    private let cameraOrientation: AVCaptureVideoOrientation = .portrait // Default orientation
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupMultipeerConnectivity()
        setupCamera()
        print("🎥 [VideoSharing] Initialized")
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
        
        isStreaming = false
        connectionState = .notConnected
        localFrame = nil
        remoteFrame = nil
        peers.removeAll()
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
        
        print("🎥 [VideoSharing] Camera setup complete")
    }
    
    private func startCamera() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    private func stopCamera() {
        captureSession.stopRunning()
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
        
        // Send to all connected peers
        do {
            try session.send(imageData, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("❌ [VideoSharing] Failed to send frame: \(error)")
        }
    }
    
    private func processReceivedFrame(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.remoteFrame = image
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
