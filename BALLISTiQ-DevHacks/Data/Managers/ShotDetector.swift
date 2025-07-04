//
//  ShotDetector.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation
import UIKit
import YOLO

actor ShotDetector {
    private var yoloModel: YOLO?
    private var latestDetections: YOLOResult?
    private var isModelLoaded = false
    private var isRunning = false
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        let _ = YOLO("yolo11m", task: .detect) { [weak self] result in
            Task {
                await self?.handleModelLoad(result: result)
            }
        }
    }
    
    private func handleModelLoad(result: Result<YOLO, Error>) {
        switch result {
        case .success(let model):
            self.yoloModel = model
            self.isModelLoaded = true
        case .failure(let error):
            print("Failed to load YOLO model: \(error)")
        }
    }
    
    private func updateResults(_ result: YOLOResult) {
        self.latestDetections = result
        self.isRunning = false
    }
    
    func submitFrame(_ frame: UIImage, frameId: Int) async {
        guard let model = self.yoloModel else { return }
        
        self.isRunning = true
        
        Task.detached { [weak self] in
            let detectionResult = model(frame)
            await self?.updateResults(detectionResult)
        }
    }
    
    func getLatestDetections() -> YOLOResult? {
        guard let result = latestDetections else { return nil }
        latestDetections = nil
        return result
    }
    
    func isReady() -> Bool {
        return isModelLoaded
    }
    
    func getIsRunning() -> Bool {
        return isRunning
    }

}
