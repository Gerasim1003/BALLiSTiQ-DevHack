//
//  ClockLine.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//


import Foundation

struct ClockLine {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let clockPosition: Int
    let angle: Double
}

struct GridCell {
    let row: Int
    let column: Int
    let bounds: CGRect
    
    var identifier: String {
        let columnLetter = String(UnicodeScalar(65 + column)!) // A, B, C, etc.
        return "\(columnLetter)\(row + 1)" // A1, B2, etc.
    }
}

struct ShotResult {
    let bulletHole: TrackedObject
    let closestTarget: EnhancedTarget
    let distance: Double
    let centerType: TargetType
    let pixelError: CGPoint
    let gridCellError: (horizontalCells: Double, verticalCells: Double)
    let hitGridCell: GridCell?
    let clockRegion: Int
}

struct EnhancedTarget {
    let originalCenter: TrackedObject
    let physicalBoundingBox: CGRect
    let centerPoint: CGPoint
    let clockLines: [ClockLine]
    let radius: CGFloat
    let gridRows: Int
    let gridColumns: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    
    var id: Int { originalCenter.id }
    var confidence: Float { originalCenter.confidence }
    var className: String { originalCenter.className }
}

class ErrorCalculator {
    
    func calculateShotResult(centers: [TrackedObject], bulletHole: TrackedObject) -> ShotResult? {
        guard bulletHole.targetType == .bullet_hole else {
            print("ErrorCalculator: Provided object is not a bullet hole")
            return nil
        }
        
        let enhancedTargets = calculatePhysicalTargetBoxes(centers: centers)
        
        let bulletCenter = CGPoint(
            x: bulletHole.boundingBox.midX,
            y: bulletHole.boundingBox.midY
        )
        
        var closestTarget: EnhancedTarget?
        var minDistance: Double = Double.infinity
        
        for target in enhancedTargets {
            let distance = calculateDistance(from: bulletCenter, to: target.centerPoint)
            
            if distance < minDistance {
                minDistance = distance
                closestTarget = target
            }
        }
        
        guard let closest = closestTarget else {
            print("ErrorCalculator: Could not determine closest target")
            return nil
        }
        
        let pixelError = CGPoint(
            x: bulletCenter.x - closest.centerPoint.x,
            y: bulletCenter.y - closest.centerPoint.y
        )
        
        guard let gridError = calculateGridCellError(target: closest, hitPoint: bulletCenter) else {
            print("ErrorCalculator: Could not calculate grid cell error")
            return nil
        }
        
        let hitCell = getGridCell(target: closest, hitPoint: bulletCenter)
        
        let clockRegion = calculateClockRegion(target: closest, hitPoint: bulletCenter)
        
        return ShotResult(
            bulletHole: bulletHole,
            closestTarget: closest,
            distance: minDistance,
            centerType: closest.originalCenter.targetType,
            pixelError: pixelError,
            gridCellError: gridError,
            hitGridCell: hitCell,
            clockRegion: clockRegion
        )
    }
    
    private func calculateDistance(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(Double(dx * dx + dy * dy))
    }
    
    func calculatePhysicalTargetBoxes(centers: [TrackedObject]) -> [EnhancedTarget] {
        let sortedCenters = sortCentersIntoGrid(centers: centers)
        let (targetWidth, targetHeight) = calculateTargetDimensions(sortedCenters: sortedCenters)
        
        return sortedCenters.map { center in
            let centerPoint = CGPoint(
                x: center.boundingBox.midX,
                y: center.boundingBox.midY
            )
            
            let physicalBoundingBox = CGRect(
                x: centerPoint.x - targetWidth / 2,
                y: centerPoint.y - targetHeight / 2,
                width: targetWidth,
                height: targetHeight
            )
            
            let radius = min(targetWidth, targetHeight) / 2
            let clockLines = generateClockLines(center: centerPoint, radius: radius)
            var gridRows = 0
            var gridColumns = 0
            var cellWidth = 0.0
            var cellHeight = 0.0
            
            if (center.className.contains("2") || center.className.contains("3")) {
                gridRows = 9
                gridColumns = 9
                cellWidth = targetWidth / CGFloat(gridColumns)
                cellHeight = targetHeight / CGFloat(gridRows)
            } else {
                gridRows = 7
                gridColumns = 9
                cellWidth = targetWidth / CGFloat(gridColumns)
                cellHeight = targetHeight / CGFloat(gridRows)
            }
            
            return EnhancedTarget(
                originalCenter: center,
                physicalBoundingBox: physicalBoundingBox,
                centerPoint: centerPoint,
                clockLines: clockLines,
                radius: radius,
                gridRows: gridRows,
                gridColumns: gridColumns,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            )
        }
    }
    
    private func sortCentersIntoGrid(centers: [TrackedObject]) -> [TrackedObject] {
        return centers.sorted { first, second in
            let firstCenter = CGPoint(x: first.boundingBox.midX, y: first.boundingBox.midY)
            let secondCenter = CGPoint(x: second.boundingBox.midX, y: second.boundingBox.midY)
            
            if abs(firstCenter.y - secondCenter.y) < 50 {
                return firstCenter.x < secondCenter.x
            }
            return firstCenter.y < secondCenter.y
        }
    }
    
    private func calculateTargetDimensions(sortedCenters: [TrackedObject]) -> (width: CGFloat, height: CGFloat) {
        let centers = sortedCenters.map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY) }
        
        var horizontalDistances: [CGFloat] = []
        for i in stride(from: 0, to: 6, by: 2) {
            if i + 1 < centers.count {
                let distance = abs(centers[i].x - centers[i + 1].x)
                horizontalDistances.append(distance)
            }
        }
        
        var verticalDistances: [CGFloat] = []
        for i in 0..<2 {
            if i + 2 < centers.count {
                let distance = abs(centers[i].y - centers[i + 2].y)
                verticalDistances.append(distance)
            }
            if i + 4 < centers.count {
                let distance = abs(centers[i + 2].y - centers[i + 4].y)
                verticalDistances.append(distance)
            }
        }
        
        let averageWidth = horizontalDistances.reduce(0, +) / CGFloat(horizontalDistances.count)
        let averageHeight = verticalDistances.reduce(0, +) / CGFloat(verticalDistances.count)
        
        return (width: averageWidth, height: averageHeight)
    }
    
    private func generateClockLines(center: CGPoint, radius: CGFloat) -> [ClockLine] {
        var clockLines: [ClockLine] = []
        
        for clockPosition in 1...12 {
            let angle = (Double(clockPosition - 3) * 30.0 + 15.0) * .pi / 180.0
            
            let endX = center.x + radius * cos(angle)
            let endY = center.y + radius * sin(angle)
            let endPoint = CGPoint(x: endX, y: endY)
            
            let clockLine = ClockLine(
                startPoint: center,
                endPoint: endPoint,
                clockPosition: clockPosition,
                angle: angle
            )
            
            clockLines.append(clockLine)
        }
        
        return clockLines
    }
    
    func calculateGridCellError(target: EnhancedTarget, hitPoint: CGPoint) -> (horizontalCells: Double, verticalCells: Double)? {
        let targetBounds = target.physicalBoundingBox
        
        guard targetBounds.contains(hitPoint) else {
            print("Hit point is outside target bounds")
            return nil
        }
        
        let relativeX = hitPoint.x - targetBounds.minX
        let relativeY = hitPoint.y - targetBounds.minY
        
        let hitColumn = Int(relativeX / target.cellWidth)
        let hitRow = Int(relativeY / target.cellHeight)
        
        let centerColumn = target.gridColumns / 2
        let centerRow = target.gridRows / 2
        
        let horizontalCells = Double(centerColumn - hitColumn)
        let verticalCells = Double(centerRow - hitRow)
        
        return (horizontalCells: horizontalCells, verticalCells: verticalCells)
    }
    
    func getGridCell(target: EnhancedTarget, hitPoint: CGPoint) -> GridCell? {
        let targetBounds = target.physicalBoundingBox
        
        guard targetBounds.contains(hitPoint) else {
            return nil
        }
        
        let relativeX = hitPoint.x - targetBounds.minX
        let relativeY = hitPoint.y - targetBounds.minY
        
        let column = Int(relativeX / target.cellWidth)
        let row = Int(relativeY / target.cellHeight)
        
        guard row >= 0 && row < target.gridRows && column >= 0 && column < target.gridColumns else {
            return nil
        }
        
        let cellBounds = CGRect(
            x: targetBounds.minX + CGFloat(column) * target.cellWidth,
            y: targetBounds.minY + CGFloat(row) * target.cellHeight,
            width: target.cellWidth,
            height: target.cellHeight
        )
        
        return GridCell(row: row, column: column, bounds: cellBounds)
    }
    
    func calculateClockRegion(target: EnhancedTarget, hitPoint: CGPoint) -> Int {
        let center = target.centerPoint
        
        // Calculate angle from center to hit point
        let dx = hitPoint.x - center.x
        let dy = hitPoint.y - center.y
        var hitAngle = atan2(dy, dx)
        
        // Normalize angle to be between 0 and 2π
        if hitAngle < 0 {
            hitAngle += 2 * .pi
        }
        
        // Convert to degrees for easier comparison
        let hitAngleDegrees = hitAngle * 180.0 / .pi
        
        // Clock positions start at 3 o'clock (0°) and go clockwise
        // Each clock position is 30° apart
        // We want to find which region (between two adjacent positions) the hit falls into
        
        // Adjust angle to match clock coordinate system (3 o'clock = 0°, 12 o'clock = 270°)
        var adjustedAngle = hitAngleDegrees
        
        // Convert to clock angle system where 12 o'clock is 0°
        adjustedAngle = adjustedAngle + 90.0
        if adjustedAngle >= 360.0 {
            adjustedAngle -= 360.0
        }
        
        // Calculate which 30° sector this falls into (0-11)
        let sector = Int(adjustedAngle / 30.0)
        
        // Convert sector to clock position (1-12)
        let clockPosition = (sector % 12) + 1
        
        // For points exactly on the boundary, choose the "right" clock position
        // (as user requested to give the right one when between two hours)
        let boundary = adjustedAngle.truncatingRemainder(dividingBy: 30.0)
        if boundary > 15.0 {
            // Point is in the second half of the sector, so return next clock position
            return (clockPosition % 12) + 1
        } else {
            // Point is in the first half of the sector
            return clockPosition
        }
    }
}
