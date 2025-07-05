//
//  FrameProvider.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation
import UIKit
import CoreImage
import AVFoundation

protocol FrameProvider {
    var isReady: Bool { get }
    var currentFrame: UIImage? { get }
    var currentFrameId: Int { get }
    
    func start()
    func stop()
    func getLatestFrame() -> UIImage?
    func getLatestFrameId() -> Int
}

class VideoFrameProvider: FrameProvider {
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var _currentFrame: UIImage?
    private var _isReady = false
    private var _frameId: Int = 0
    
    // Playback speed multiplier (e.g. 0.5 = half‑speed, 2.0 = double‑speed)
    private var playbackSpeed: Float = 1.0
    
    private let videoURL: URL
    private let processingQueue = DispatchQueue(label: "video.processing", qos: .userInteractive)
    
    var isReady: Bool {
        return _isReady
    }
    
    var currentFrame: UIImage? {
        return _currentFrame
    }
    
    var currentFrameId: Int {
        return _frameId
    }
    
    init(videoURL: URL) {
        self.videoURL = videoURL
        setupPlayer()
    }
    
    deinit {
        stop()
    }
    
    private func setupPlayer() {
        let asset = AVURLAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(videoOutput!)
        
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        _isReady = true
    }
    
    @objc private func playerItemDidReachEnd() {
        player?.seek(to: CMTime.zero)
        player?.play()
        _frameId = 0
        print("[VideoFrameProvider] Video loop reset, frameId reset to 0")
    }
    
    func start() {
        guard let player = player else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .default)
        
        player.playImmediately(atRate: playbackSpeed)
        print("[VideoFrameProvider] Started playing video")
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        player?.pause()
        print("[VideoFrameProvider] Stopped video playback")
    }
    
    @objc private func updateFrame() {
        guard let videoOutput = videoOutput,
              let player = player else { return }
        
        let currentTime = player.currentTime()
        
        if videoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
            guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
                return
            }
            
            // Move heavy processing to background queue
            processingQueue.async { [weak self] in
                // Much faster approach - direct pixel buffer to UIImage
                if let uiImage = self?.pixelBufferToUIImage(pixelBuffer) {
                    // Update cached frame on main thread
                    DispatchQueue.main.async {
                        self?._currentFrame = uiImage
                        self?._frameId += 1
                    }
                }
            }
        }
    }
    
    func getLatestFrame() -> UIImage? {
        return _currentFrame
    }
    
    func getLatestFrameId() -> Int {
        return _frameId
    }
    
    // MARK: - Playback Speed Control
    /// Sets the playback speed.  Pass 1.0 for normal speed, 0.5 for half‑speed,
    /// 2.0 for double‑speed, etc.  Values are clamped to a reasonable range.
    func setPlaybackSpeed(_ speed: Float) {
        // Clamp speed between 0.1× and 4×
        let clamped = max(0.1, min(speed, 4.0))
        playbackSpeed = clamped
        
        // If the player is already running, update its rate immediately
        if let player = player, player.timeControlStatus == .playing {
            player.rate = clamped
        }
    }
    
    /// Returns the current playback speed multiplier.
    func getPlaybackSpeed() -> Float {
        return playbackSpeed
    }
    
    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(data: baseAddress,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorspace,
                                    bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

class CameraFrameProvider: NSObject, FrameProvider {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var _currentFrame: UIImage?
    private var _isReady = false
    private var _frameId: Int = 0
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var _zoomFactor: CGFloat = 1.0
    private var minZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat = 1.0
    private var captureDevice: AVCaptureDevice?
    private var setupCompletion: (() -> Void)?
    
    var isReady: Bool {
        return _isReady
    }
    
    var currentFrame: UIImage? {
        return _currentFrame
    }
    
    var currentFrameId: Int {
        return _frameId
    }
    
    override init() {
        super.init()
        setupCamera()
    }
    
    convenience init(completion: @escaping () -> Void) {
        self.init()
        setupCompletion = completion
    }
    
    deinit {
        stop()
    }
    
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        captureDevice = device
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = device.maxAvailableVideoZoomFactor
        _zoomFactor = device.videoZoomFactor
        
        print("[CameraFrameProvider] Zoom range: \(minZoomFactor) - \(maxZoomFactor), current: \(_zoomFactor)")
        
        do {
            let captureSession = AVCaptureSession()
            captureSession.beginConfiguration()
            
            captureSession.sessionPreset = .high
            
            // Configure camera for 30fps
            try device.lockForConfiguration()
            for format in device.formats {
                let ranges = format.videoSupportedFrameRateRanges
                for range in ranges {
                    if range.maxFrameRate >= 30.0 && range.minFrameRate <= 30.0 {
                        device.activeFormat = format
                        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
                        device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
                        break
                    }
                }
            }
            device.unlockForConfiguration()
            
            let deviceInput = try AVCaptureDeviceInput(device: device)
            
            if captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Set the video orientation to portrait
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            captureSession.commitConfiguration()
            
            self.captureSession = captureSession
            self.videoOutput = videoOutput
            
            DispatchQueue.main.async {
                self._isReady = true
                self.setupCompletion?()
            }
            
            print("[CameraFrameProvider] Camera configured for 30fps")
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    func start() {
        sessionQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    func getLatestFrame() -> UIImage? {
        return _currentFrame
    }
    
    func getLatestFrameId() -> Int {
        return _frameId
    }
    
    // MARK: - Zoom Control
    func setZoom(factor: CGFloat, completion: ((CGFloat) -> Void)? = nil) {
        print("[CameraFrameProvider] setZoom called with factor: \(factor)")
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.captureDevice else {
                print("[CameraFrameProvider] setZoom failed: no device")
                return
            }
            let clamped = max(self.minZoomFactor, min(factor, self.maxZoomFactor))
            print("[CameraFrameProvider] Setting zoom from \(device.videoZoomFactor) to \(clamped)")
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                self._zoomFactor = clamped
                print("[CameraFrameProvider] Zoom set successfully to \(clamped)")
                if let completion = completion {
                    DispatchQueue.main.async {
                        completion(clamped)
                    }
                }
            } catch {
                print("Failed to set zoom: \(error)")
                if let completion = completion {
                    DispatchQueue.main.async {
                        completion(self._zoomFactor)
                    }
                }
            }
        }
    }
    func getZoom() -> CGFloat {
        return _zoomFactor
    }
    func getMinZoom() -> CGFloat {
        return minZoomFactor
    }
    func getMaxZoom() -> CGFloat {
        return maxZoomFactor
    }
}

extension CameraFrameProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            
            DispatchQueue.main.async { [weak self] in
                self?._currentFrame = uiImage
                self?._frameId += 1
            }
        }
    }
}
