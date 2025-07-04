//
//  ObjectTracker.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation
import YOLO

actor ObjectTracker {
    private var trackedObjects: [Int: TrackedObject] = [:]
    private var historicalBulletHoles: [TrackedObject] = []
    private var nextObjectId: Int = 1
    private var bulletHoleId: Int = 1
    private let iouThreshold: Float = 0.4
    private let centerIouThreshold: Float = 0.2
    private let maxFramesWithoutDetection: Int = 10
    private let bulletHoleUpscaleFactor: CGFloat = 3.0
    private let historicalMatchThreshold: Float = 0.4
    
    func update(with detections: YOLOResult) -> [TrackedObject] {
        let matches = matchDetections(detections.boxes)
        
        for (detection, objectId) in matches {
            if let id = objectId {
                updateExistingObject(id: id, with: detection)
            } else {
                let newObject = createNewObject(from: detection, targetType: TargetType.from(className: detection.cls))
                trackedObjects[newObject.id] = newObject
            }
        }
        
        assignCenterIndices()
        
        pruneStaleObjects()
        return Array(trackedObjects.values.filter { $0.isActive })
    }
    
    func getActiveObjects() -> [TrackedObject] {
        return Array(trackedObjects.values.filter { $0.isActive })
    }
    
    func getObjectById(_ id: Int) -> TrackedObject? {
        return trackedObjects[id]
    }
    
    func getAndConsumeNewBulletHole() -> TrackedObject? {
        let undeliveredBulletHoles = trackedObjects.values
            .filter { $0.isActive && $0.targetType == .bullet_hole && !$0.hasBeenDelivered }
        
        guard let mostRecent = undeliveredBulletHoles.max(by: { $0.id < $1.id }) else {
            return nil
        }
        
        trackedObjects[mostRecent.id]?.hasBeenDelivered = true
        return mostRecent
    }

    func getCenters() -> [TrackedObject] {
        return trackedObjects.values
            .filter { $0.isActive && $0.targetType == .center }
    }
    
    func getLatestBulletHole() -> TrackedObject? {
        return trackedObjects.values
            .filter { $0.isActive && $0.targetType == .bullet_hole }
            .max(by: { $0.id < $1.id })
    }

    func resetBulletHoles() {
        let currentBulletHoles = trackedObjects.values.filter { $0.targetType == .bullet_hole }
        historicalBulletHoles.append(contentsOf: currentBulletHoles)
        
        trackedObjects = trackedObjects.filter { $0.value.targetType != .bullet_hole }
        bulletHoleId = 1
    }
    
    func reset() {
        trackedObjects.removeAll()
        historicalBulletHoles.removeAll()
        nextObjectId = 1
        bulletHoleId = 1
    }
    
    private func upscaleBoundingBox(_ bbox: CGRect, scaleFactor: CGFloat) -> CGRect {
        let centerX = bbox.midX
        let centerY = bbox.midY
        let newWidth = bbox.width * scaleFactor
        let newHeight = bbox.height * scaleFactor
        
        return CGRect(
            x: centerX - newWidth / 2,
            y: centerY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
    }
    
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect, targetType: TargetType = .INVALID) -> Float {
        let processedBox1: CGRect
        let processedBox2: CGRect
        
        if targetType == .bullet_hole {
            processedBox1 = upscaleBoundingBox(box1, scaleFactor: bulletHoleUpscaleFactor)
            processedBox2 = upscaleBoundingBox(box2, scaleFactor: bulletHoleUpscaleFactor)
        } else {
            processedBox1 = box1
            processedBox2 = box2
        }
        
        let intersection = processedBox1.intersection(processedBox2)
        if intersection.isNull {
            return 0.0
        }
        
        let intersectionArea = intersection.width * intersection.height
        let box1Area = processedBox1.width * processedBox1.height
        let box2Area = processedBox2.width * processedBox2.height
        let unionArea = box1Area + box2Area - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    private func isHistoricalBulletHole(_ detection: Box) -> Bool {
        guard TargetType.from(className: detection.cls) == .bullet_hole else {
            return false
        }
        
        for historicalHole in historicalBulletHoles {
            let iou = calculateIoU(detection.xywh, historicalHole.boundingBox, targetType: .bullet_hole)
            if iou >= historicalMatchThreshold {
                return true
            }
        }
        
        return false
    }
    
    private func matchDetections(_ detections: [Box]) -> [(detection: Box, objectId: Int?)] {
        var matches: [(detection: Box, objectId: Int?)] = []
        var usedObjectIds: Set<Int> = []
        
        for detection in detections {
            if isHistoricalBulletHole(detection) {
                continue
            }
            
            var bestMatch: (id: Int, iou: Float)?
            let detectionTargetType = TargetType.from(className: detection.cls)
            
            for (id, trackedObject) in trackedObjects {
                guard !usedObjectIds.contains(id) && trackedObject.isActive else { continue }
                
                let classNamesMatch: Bool
                if detection.cls.contains("center") && trackedObject.className.contains("center_") {
                    classNamesMatch = true
                } else {
                    classNamesMatch = trackedObject.className == detection.cls
                }
                
                guard classNamesMatch else { continue }
                
                let iou = calculateIoU(detection.xywh, trackedObject.boundingBox, targetType: detectionTargetType)
                let threshold = detectionTargetType == .center ? centerIouThreshold : iouThreshold
                if iou >= threshold {
                    if bestMatch == nil || iou > bestMatch!.iou {
                        bestMatch = (id: id, iou: iou)
                    }
                }
            }
            
            if let match = bestMatch {
                matches.append((detection: detection, objectId: match.id))
                usedObjectIds.insert(match.id)
            } else {
                matches.append((detection: detection, objectId: nil))
            }
        }
        
        return matches
    }
    
    private func updateExistingObject(id: Int, with detection: Box) {
        guard var object = trackedObjects[id] else { return }
        
        object.update(boundingBox: detection.xywh, confidence: detection.conf)
        trackedObjects[id] = object
    }
    
    private func createNewObject(from detection: Box, targetType: TargetType) -> TrackedObject {
        let objectId: Int
        if targetType == .bullet_hole {
            objectId = bulletHoleId
            bulletHoleId += 1
        } else {
            objectId = nextObjectId
            nextObjectId += 1
        }
        
        return TrackedObject(
            id: objectId,
            boundingBox: detection.xywh,
            confidence: detection.conf,
            className: detection.cls
        )
    }
    
    private func pruneStaleObjects() {
        for (id, var object) in trackedObjects {
            if object.isActive {
                object.framesSinceLastSeen += 1
                
                if object.framesSinceLastSeen >= maxFramesWithoutDetection {
                    object.isActive = false
                }
                
                trackedObjects[id] = object
            }
        }
        trackedObjects = trackedObjects.filter { $0.value.isActive }
    }
    
    private func assignCenterIndices() {
        let centerObjects = trackedObjects.values.filter { $0.isActive && $0.targetType == .center }
        
        guard !centerObjects.isEmpty else { return }
        
        let sortedCenters = centerObjects.sorted { (first, second) in
            let firstY = first.boundingBox.midY
            let secondY = second.boundingBox.midY
            let firstX = first.boundingBox.midX
            let secondX = second.boundingBox.midX
            
            if abs(firstY - secondY) < 50.0 {
                return firstX < secondX
            } else {
                return firstY < secondY
            }
        }
        
        for (centerIndex, centerObject) in sortedCenters.enumerated() {
            let newClassName = "center_\(centerIndex)"
            if var object = trackedObjects[centerObject.id] {
                object.className = newClassName
                trackedObjects[centerObject.id] = object
            }
        }
    }
}
