//
//  ErrorCalculatorTestView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 05.07.25.
//

import SwiftUI
import UIKit

struct ErrorCalculatorTestView: View {
    @State private var shotResult: ShotResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var enhancedTargets: [EnhancedTarget] = []
    @State private var selectedTargetIndex: Int = 0
    @Environment(\.dismiss) var dismiss
    
    private let testImage = UIImage(named: "test_img2")
    private let errorCalculator = ErrorCalculator()
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with back button and title
                HeaderView()
                
                ScrollView {
                    VStack(spacing: 16) {
                        if let image = testImage {
                            // Main image analysis section
                            ImageAnalysisSection(image: image)
                            
                            // Control buttons
                            ControlButtonsSection()
                            
                            // Results section
                            if let result = shotResult {
                                ResultsSection(result: result)
                            }
                            
                            // Target detail section
                            if !enhancedTargets.isEmpty {
                                TargetDetailSection()
                            }
                            
                            // Error message
                            if let errorMessage = errorMessage {
                                ErrorMessageSection(message: errorMessage)
                            }
                        } else {
                            NoImageSection()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            calculatePhysicalBoxes()
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.appPrimary)
    }
    
    @ViewBuilder
    private func StatusIndicator() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLoading ? .orange : (shotResult != nil ? .green : .gray))
                .frame(width: 8, height: 8)
                .scaleEffect(isLoading ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLoading)
            
            Text(isLoading ? "Calculating..." : (shotResult != nil ? "Analyzed" : "Ready"))
                .poppinsFont(size: 12, style: .regular)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Image Analysis Section
    
    @ViewBuilder
    private func ImageAnalysisSection(image: UIImage) -> some View {
        VStack(spacing: 12) {
            Text("Target Analysis")
                .poppinsFont(size: 18, style: .semiBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                GeometryReader { geometry in
                    ImageOverlaysView(geometry: geometry, image: image)
                }
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private func ImageOverlaysView(geometry: GeometryProxy, image: UIImage) -> some View {
        // Display original center boxes in blue
        ForEach(Array(groundTruthCenters.indices), id: \.self) { index in
            let center = groundTruthCenters[index]
            let transformedRect = transformRect(
                from: center.boundingBox,
                in: image.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(center.className)")
                .poppinsFont(size: 8, style: .regular)
                .foregroundColor(.white)
                .padding(2)
                .background(Color.blue)
                .position(x: transformedRect.midX, y: transformedRect.minY - 10)
        }
        
        // Display enhanced targets with clock lines
        ForEach(Array(enhancedTargets.indices), id: \.self) { index in
            let enhancedTarget = enhancedTargets[index]
            let transformedRect = transformRect(
                from: enhancedTarget.physicalBoundingBox,
                in: image.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("target_\(enhancedTarget.id)")
                .poppinsFont(size: 8, style: .regular)
                .foregroundColor(.white)
                .padding(2)
                .background(Color.green)
                .position(x: transformedRect.midX, y: transformedRect.maxY + 10)
            
            // Draw clock lines
            ForEach(Array(enhancedTarget.clockLines.indices), id: \.self) { lineIndex in
                let clockLine = enhancedTarget.clockLines[lineIndex]
                let transformedStart = transformPoint(
                    point: clockLine.startPoint,
                    from: image.size,
                    to: geometry.size
                )
                let transformedEnd = transformPoint(
                    point: clockLine.endPoint,
                    from: image.size,
                    to: geometry.size
                )
                
                Path { path in
                    path.move(to: transformedStart)
                    path.addLine(to: transformedEnd)
                }
                .stroke(Color.orange, lineWidth: 1)
                
                Text("\(clockLine.clockPosition)")
                    .poppinsFont(size: 6, style: .regular)
                    .foregroundColor(.white)
                    .padding(1)
                    .background(Color.orange)
                    .position(transformedEnd)
            }
        }
        
        // Display bullet hole in red
        let bullet = groundTruthBullet
        let transformedBulletRect = transformRect(
            from: bullet.boundingBox,
            in: image.size,
            to: geometry.size
        )
        
        Rectangle()
            .stroke(Color.red, lineWidth: 3)
            .frame(width: transformedBulletRect.width, height: transformedBulletRect.height)
            .position(x: transformedBulletRect.midX, y: transformedBulletRect.midY)
        
        Text("bullet")
            .poppinsFont(size: 8, style: .regular)
            .foregroundColor(.white)
            .padding(2)
            .background(Color.red)
            .position(x: transformedBulletRect.midX, y: transformedBulletRect.minY - 10)
        
        // Display line to closest center if shot result exists
        if let result = shotResult {
            let closestCenterPoint = transformPoint(
                point: result.closestTarget.centerPoint,
                from: image.size,
                to: geometry.size
            )
            
            Path { path in
                path.move(to: CGPoint(x: transformedBulletRect.midX, y: transformedBulletRect.midY))
                path.addLine(to: closestCenterPoint)
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, dash: [5]))
        }
    }
    
    // MARK: - Control Buttons Section
    
    @ViewBuilder
    private func ControlButtonsSection() -> some View {
        HStack(spacing: 16) {
            Button(action: calculatePhysicalBoxes) {
                HStack(spacing: 8) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Calculate Boxes")
                        .poppinsFont(size: 14, style: .medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green)
                )
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button(action: calculateError) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Calculate Error")
                        .poppinsFont(size: 14, style: .medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appPrimary)
                )
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
    
    // MARK: - Results Section
    
    @ViewBuilder
    private func ResultsSection(result: ShotResult) -> some View {
        VStack(spacing: 12) {
            Text("Shot Analysis Results")
                .poppinsFont(size: 18, style: .semiBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 8) {
                ResultRow(
                    icon: "target",
                    label: "Distance to Center",
                    value: "\(String(format: "%.2f", result.distance)) px",
                    color: .appPrimary
                )
                
                ResultRow(
                    icon: "clock",
                    label: "Clock Region",
                    value: "\(result.clockRegion) o'clock",
                    color: .orange
                )
                
                ResultRow(
                    icon: "grid",
                    label: "Grid Cell Error",
                    value: "\(String(format: "%.1f", result.gridCellError.horizontalCells))h, \(String(format: "%.1f", result.gridCellError.verticalCells))v",
                    color: .blue
                )
                
                if let hitCell = result.hitGridCell {
                    ResultRow(
                        icon: "scope",
                        label: "Hit Grid Cell",
                        value: hitCell.identifier,
                        color: .green
                    )
                } else {
                    ResultRow(
                        icon: "xmark.circle",
                        label: "Hit Grid Cell",
                        value: "Outside target",
                        color: .red
                    )
                }
                
                ResultRow(
                    icon: "location",
                    label: "Closest Target",
                    value: result.closestTarget.className,
                    color: .purple
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    @ViewBuilder
    private func ResultRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .poppinsFont(size: 14, style: .regular)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .poppinsFont(size: 14, style: .semiBold)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Target Detail Section
    
    @ViewBuilder
    private func TargetDetailSection() -> some View {
        VStack(spacing: 12) {
            Text("Target Detail View")
                .poppinsFont(size: 18, style: .semiBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Target selector
            VStack(spacing: 8) {
                Text("Select Target")
                    .poppinsFont(size: 14, style: .medium)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Picker("Select Target", selection: $selectedTargetIndex) {
                    ForEach(Array(enhancedTargets.indices), id: \.self) { index in
                        Text("Target \(enhancedTargets[index].id)")
                            .poppinsFont(size: 14, style: .regular)
                            .tag(index)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(.appPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            // Cropped target view
            if selectedTargetIndex < enhancedTargets.count {
                CroppedTargetView(enhancedTarget: enhancedTargets[selectedTargetIndex])
            }
        }
    }
    
    @ViewBuilder
    private func CroppedTargetView(enhancedTarget: EnhancedTarget) -> some View {
        VStack(spacing: 8) {
            Text("Target \(enhancedTarget.className)")
                .poppinsFont(size: 16, style: .semiBold)
                .foregroundColor(.white)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                croppedTargetView(enhancedTarget: enhancedTarget)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(height: 250)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Error Message Section
    
    @ViewBuilder
    private func ErrorMessageSection(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .poppinsFont(size: 14, style: .regular)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - No Image Section
    
    @ViewBuilder
    private func NoImageSection() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Image 'new_test_img' not found")
                .poppinsFont(size: 18, style: .semiBold)
                .foregroundColor(.white)
            
            Text("Please add the test image to your Asset Catalog")
                .poppinsFont(size: 14, style: .regular)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var groundTruthCenters: [TrackedObject] {
        let centersData = [
            [[398.33333333333337, 981.1827956989247], [367.6881720430108, 950.5376344086021]],
            [[694.0322580645161, 963.9784946236558], [664.4623655913979, 934.4086021505376]],
            [[419.3010752688172, 1295.6989247311826], [385.9677419354839, 1266.1290322580644]],
            [[723.0645161290323, 1274.1935483870966], [689.7311827956989, 1243.5483870967741]],
            [[442.4193548387097, 1612.9032258064515], [406.3978494623656, 1578.494623655914]],
            [[742.4193548387096, 1599.4623655913977], [712.3118279569893, 1566.6666666666665]]
        ]
        
        return centersData.enumerated().map { index, points in
            let xmin = min(points[0][0], points[1][0])
            let ymin = min(points[0][1], points[1][1])
            let xmax = max(points[0][0], points[1][0])
            let ymax = max(points[0][1], points[1][1])
            
            let boundingBox = CGRect(
                x: xmin,
                y: ymin,
                width: xmax - xmin,
                height: ymax - ymin
            )
            
            return TrackedObject(
                id: index + 1,
                boundingBox: boundingBox,
                confidence: 1.0,
                className: "center_\(index)"
            )
        }
    }
    
    private var groundTruthBullet: TrackedObject {
        let bulletPoints = [[637.1428571428571, 851.4285714285713], [666.4285714285713, 878.5714285714284]]
        
        let xmin = min(bulletPoints[0][0], bulletPoints[1][0])
        let ymin = min(bulletPoints[0][1], bulletPoints[1][1])
        let xmax = max(bulletPoints[0][0], bulletPoints[1][0])
        let ymax = max(bulletPoints[0][1], bulletPoints[1][1])
        
        let boundingBox = CGRect(
            x: xmin,
            y: ymin,
            width: xmax - xmin,
            height: ymax - ymin
        )
        
        return TrackedObject(
            id: 100,
            boundingBox: boundingBox,
            confidence: 1.0,
            className: "bullet"
        )
    }
    
    private func calculatePhysicalBoxes() {
        let centers = groundTruthCenters
        enhancedTargets = errorCalculator.calculatePhysicalTargetBoxes(centers: centers)
        errorMessage = nil
    }
    
    private func calculateError() {
        let bullet = groundTruthBullet
        let centers = groundTruthCenters
        
        let result = errorCalculator.calculateShotResult(centers: centers, bulletHole: bullet)
        
        if let result = result {
            shotResult = result
            errorMessage = nil
        } else {
            errorMessage = "Failed to calculate shot error"
        }
    }
    
    private func transformRect(from rect: CGRect, in imageSize: CGSize, to viewSize: CGSize) -> CGRect {
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
    
    private func transformPoint(point: CGPoint, from imageSize: CGSize, to viewSize: CGSize) -> CGPoint {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        
        let offsetX = (viewSize.width - scaledImageWidth) / 2
        let offsetY = (viewSize.height - scaledImageHeight) / 2
        
        let transformedX = point.x * scale + offsetX
        let transformedY = point.y * scale + offsetY
        
        return CGPoint(x: transformedX, y: transformedY)
    }
    
    private func croppedTargetView(enhancedTarget: EnhancedTarget) -> some View {
        ZStack {
            if let image = testImage {
                let croppedImage = cropImageToTarget(image: image, target: enhancedTarget)
                
                Image(uiImage: croppedImage)
                    .resizable()
                    .scaledToFit()
                
                GeometryReader { geometry in
                    let viewSize = geometry.size
                    let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                    
                    // Draw grid lines
                    let cellWidth = viewSize.width / CGFloat(enhancedTarget.gridColumns)
                    let cellHeight = viewSize.height / CGFloat(enhancedTarget.gridRows)
                    
                    // Vertical grid lines
                    ForEach(0..<enhancedTarget.gridColumns + 1, id: \.self) { column in
                        let x = CGFloat(column) * cellWidth
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: viewSize.height))
                        }
                        .stroke(Color.cyan.opacity(0.6), lineWidth: 1)
                    }
                    
                    // Horizontal grid lines
                    ForEach(0..<enhancedTarget.gridRows + 1, id: \.self) { row in
                        let y = CGFloat(row) * cellHeight
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: viewSize.width, y: y))
                        }
                        .stroke(Color.cyan.opacity(0.6), lineWidth: 1)
                    }
                    
                    // Draw clock lines from center
                    let radius = min(viewSize.width, viewSize.height) / 2.2
                    ForEach(Array(enhancedTarget.clockLines.indices), id: \.self) { index in
                        let clockLine = enhancedTarget.clockLines[index]
                        let angle = clockLine.angle
                        let endX = center.x + radius * cos(angle)
                        let endY = center.y + radius * sin(angle)
                        let endPoint = CGPoint(x: endX, y: endY)
                        
                        Path { path in
                            path.move(to: center)
                            path.addLine(to: endPoint)
                        }
                        .stroke(Color.orange.opacity(0.8), lineWidth: 1.5)
                        
                        Text("\(clockLine.clockPosition)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(Color.orange)
                            )
                            .position(endPoint)
                    }
                    
                    // Center point
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(center)
                    
                    // Draw bullet hole if it's within this target
                    if let bulletPosition = getBulletPositionInCroppedView(target: enhancedTarget, viewSize: viewSize) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .position(bulletPosition)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 12, height: 12)
                                    .position(bulletPosition)
                            )
                        
                        Text("●")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .position(x: bulletPosition.x, y: bulletPosition.y - 20)
                        
                        if let result = shotResult, result.closestTarget.id == enhancedTarget.id {
                            Text("Grid: \(String(format: "%.1f", result.gridCellError.horizontalCells))h, \(String(format: "%.1f", result.gridCellError.verticalCells))v")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .padding(2)
                                .background(Color.black.opacity(0.7))
                                .position(x: bulletPosition.x, y: bulletPosition.y + 25)
                        }
                    }
                    
                    // Target info overlay
                    VStack {
                        Text("Target \(enhancedTarget.className)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                        
                        Spacer()
                        
                        HStack {
                            Text("Grid: \(enhancedTarget.gridRows)x\(enhancedTarget.gridColumns)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Color.black.opacity(0.7))
                            
                            if let bulletPosition = getBulletPositionInCroppedView(target: enhancedTarget, viewSize: viewSize) {
                                Text("● Hit")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                    .padding(3)
                                    .background(Color.black.opacity(0.7))
                            }
                        }
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                Text("No Image")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func cropImageToTarget(image: UIImage, target: EnhancedTarget) -> UIImage {
        let targetBounds = target.physicalBoundingBox
        
        // Add some padding around the target
        let padding: CGFloat = 20
        let expandedBounds = CGRect(
            x: max(0, targetBounds.minX - padding),
            y: max(0, targetBounds.minY - padding),
            width: min(image.size.width - max(0, targetBounds.minX - padding), targetBounds.width + 2 * padding),
            height: min(image.size.height - max(0, targetBounds.minY - padding), targetBounds.height + 2 * padding)
        )
        
        guard let cgImage = image.cgImage else { return image }
        
        // Convert to CGRect for cropping (flip Y coordinate)
        let cropRect = CGRect(
            x: expandedBounds.minX,
            y: expandedBounds.minY,
            width: expandedBounds.width,
            height: expandedBounds.height
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    private func getBulletPositionInCroppedView(target: EnhancedTarget, viewSize: CGSize) -> CGPoint? {
        let targetBounds = target.physicalBoundingBox
        
        // Add some padding around the target
        let padding: CGFloat = 20
        let expandedBounds = CGRect(
            x: max(0, targetBounds.minX - padding),
            y: max(0, targetBounds.minY - padding),
            width: min(testImage!.size.width - max(0, targetBounds.minX - padding), targetBounds.width + 2 * padding),
            height: min(testImage!.size.height - max(0, targetBounds.minY - padding), targetBounds.height + 2 * padding)
        )
        
        let bulletHole = groundTruthBullet.boundingBox
        let bulletCenter = CGPoint(x: bulletHole.midX, y: bulletHole.midY)
        
        // Check if the bullet hole is within the expanded bounds
        if expandedBounds.contains(bulletCenter) {
            // Convert bullet position relative to the cropped area (0.0 to 1.0)
            let relativeX = (bulletCenter.x - expandedBounds.minX) / expandedBounds.width
            let relativeY = (bulletCenter.y - expandedBounds.minY) / expandedBounds.height
            
            // Convert to view coordinates
            return CGPoint(x: relativeX * viewSize.width, y: relativeY * viewSize.height)
        }
        
        return nil
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ErrorCalculatorTestView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorCalculatorTestView()
    }
}
