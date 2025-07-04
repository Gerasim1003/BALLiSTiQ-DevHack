//
//  TrackedObject.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation

struct TrackedObject {
    let id: Int
    var boundingBox: CGRect
    var confidence: Float
    var className: String
    var targetType: TargetType
    var lastSeen: Date
    var framesSinceLastSeen: Int
    var isActive: Bool
    var hasBeenDelivered: Bool
    var trackingHistory: [CGRect]
    
    init(id: Int, boundingBox: CGRect, confidence: Float, className: String) {
        self.id = id
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.className = className
        self.targetType = TargetType.from(className: className)
        self.lastSeen = Date()
        self.framesSinceLastSeen = 0
        self.isActive = true
        self.hasBeenDelivered = false
        self.trackingHistory = [boundingBox]
    }
    
    mutating func update(boundingBox: CGRect, confidence: Float) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.lastSeen = Date()
        self.framesSinceLastSeen = 0
        self.isActive = true
        self.trackingHistory.append(boundingBox)
    }
}

enum TargetType {
    case target
    case center
    case bullet_hole
    case INVALID
    
    static func from(className: String) -> TargetType {
        if className.contains("center") {
            return .center
        } else if className.contains("bullet") {
            return .bullet_hole
        } else if className.contains("target") {
            return .target
        }
        return .INVALID
    }
}
