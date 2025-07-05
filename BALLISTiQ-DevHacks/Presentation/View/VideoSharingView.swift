//
//  DetectionView.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 05.07.25.
//

import SwiftUI

struct VideoSharingView: View {
    @StateObject private var viewModel = VideoSharingViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with back button and title
                HeaderView()
                
                // Main video area
                VideoDisplayArea()
                    .frame(maxHeight: .infinity)
                
                // Connection status
                ConnectionStatusView()
                
                // Control panel
                ControlPanel()
                
                // Detection Statistics
                DetectionStatisticsPanel()
                
                // Peer list
                PeerListView()
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            viewModel.stop()
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
                
                // Connection indicator
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
        VStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(viewModel.isStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.isStreaming)
            
            Text(statusText)
                .poppinsFont(size: 12, style: .regular)
                .foregroundColor(.white)
        }
    }
    
    private var statusColor: Color {
        switch viewModel.connectionState {
        case .notConnected:
            return viewModel.isStreaming ? .orange : .gray
        case .connecting:
            return .yellow
        case .connected:
            return .green
        }
    }
    
    private var statusText: String {
        switch viewModel.connectionState {
        case .notConnected:
            return viewModel.isStreaming ? "Searching..." : "Ready"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        }
    }
    
    // MARK: - Video Display Area
    
    @ViewBuilder
    private func VideoDisplayArea() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Remote video (main view)
            if let remoteFrame = viewModel.remoteFrame {
                ZStack {
                    Image(uiImage: remoteFrame)
                        .resizable()
                        .scaledToFit()
                        .clipped()
                        .cornerRadius(12)
                    
                    // Remote detection overlays
                    GeometryReader { geometry in
                        RemoteDetectionOverlays(geometry: geometry, frame: remoteFrame)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("Waiting for remote video...")
                        .poppinsFont(size: 18, style: .regular)
                        .foregroundColor(.gray)
                    
                    if viewModel.isStreaming {
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                }
            }
            
            // Local video (Picture-in-Picture)
            if let localFrame = viewModel.localFrame {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Image(uiImage: localFrame)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 160)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appPrimary, lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            // Local detection overlays
                            GeometryReader { geometry in
                                LocalDetectionOverlays(geometry: geometry, frame: localFrame)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .frame(width: 120, height: 160)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Connection Status View
    
    @ViewBuilder
    private func ConnectionStatusView() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connection Status")
                    .poppinsFont(size: 14, style: .medium)
                    .foregroundColor(.gray)
                
                Text(viewModel.connectionState.description)
                    .poppinsFont(size: 16, style: .semiBold)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Connected Peers")
                    .poppinsFont(size: 14, style: .medium)
                    .foregroundColor(.gray)
                
                Text("\(viewModel.peers.count)")
                    .poppinsFont(size: 16, style: .semiBold)
                    .foregroundColor(.appPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - Detection Statistics Panel
    
    @ViewBuilder
    private func DetectionStatisticsPanel() -> some View {
        HStack(spacing: 24) {
            // Local detection stats
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Detection")
                    .poppinsFont(size: 12, style: .medium)
                    .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                    StatBadge(
                        value: "\(viewModel.localBulletHoles.count)",
                        label: "Holes",
                        color: .red
                    )
                    
                    StatBadge(
                        value: "\(viewModel.localTargets.count)",
                        label: "Targets",
                        color: .green
                    )
                    
                    if let shotResult = viewModel.localShotResult {
                        Text("Clock: \(shotResult.clockRegion)")
                            .poppinsFont(size: 10, style: .regular)
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            
            Spacer()
            
            // Remote detection stats
            VStack(alignment: .trailing, spacing: 4) {
                Text("Remote Detection")
                    .poppinsFont(size: 12, style: .medium)
                    .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                    StatBadge(
                        value: "\(viewModel.remoteBulletHoles.count)",
                        label: "Holes",
                        color: .red
                    )
                    
                    StatBadge(
                        value: "\(viewModel.remoteTargets.count)",
                        label: "Targets",
                        color: .green
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }
    
    @ViewBuilder
    private func StatBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .poppinsFont(size: 12, style: .semiBold)
                .foregroundColor(color)
            
            Text(label)
                .poppinsFont(size: 8, style: .regular)
                .foregroundColor(.gray)
        }
        .frame(minWidth: 24)
    }
    
    // MARK: - Control Panel
    
    @ViewBuilder
    private func ControlPanel() -> some View {
        HStack(spacing: 16) {
            // Main control button
            Button(action: toggleStreaming) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .medium))
                    
                    Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
                        .poppinsFont(size: 16, style: .medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.isStreaming ? .red : .green)
                )
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Peer List View
    
    @ViewBuilder
    private func PeerListView() -> some View {
        if !viewModel.peers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Peers")
                    .poppinsFont(size: 16, style: .semiBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.peers) { peer in
                            PeerRow(peer: peer) {
                                viewModel.invitePeer(peer)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 120)
            }
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private func PeerRow(peer: PeerInfo, onInvite: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.peerID.displayName)
                    .poppinsFont(size: 14, style: .medium)
                    .foregroundColor(.white)
                
                Text(peer.state == .connected ? "Connected" : "Available")
                    .poppinsFont(size: 12, style: .regular)
                    .foregroundColor(peer.state == .connected ? .green : .gray)
            }
            
            Spacer()
            
            if peer.state != .connected {
                Button("Invite") {
                    onInvite()
                }
                .poppinsFont(size: 14, style: .medium)
                .foregroundColor(.appPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appPrimary, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    // MARK: - Helper Methods
    
    private func toggleStreaming() {
        if viewModel.isStreaming {
            viewModel.stop()
        } else {
            viewModel.start()
        }
    }
    
    // MARK: - Button Styles
    
    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    // MARK: - Detection Overlay Views
    
    @ViewBuilder
    private func LocalDetectionOverlays(geometry: GeometryProxy, frame: UIImage) -> some View {
        ForEach(Array(viewModel.localBulletHoles.indices), id: \.self) { index in
            let bulletHole = viewModel.localBulletHoles[index]
            let transformedRect = viewModel.transformRect(
                from: bulletHole.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.red, lineWidth: 1)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(bulletHole.id)")
                .poppinsFont(size: 6, style: .regular)
                .foregroundColor(.white)
                .padding(1)
                .background(Color.red)
                .position(x: transformedRect.midX, y: max(5, transformedRect.minY - 5))
        }
        
        if let latestBullet = viewModel.localLatestBulletHole {
            let transformedRect = viewModel.transformRect(
                from: latestBullet.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Circle()
                .fill(Color.yellow)
                .frame(width: 3, height: 3)
                .position(x: transformedRect.midX, y: transformedRect.midY)
        }
        
        ForEach(Array(viewModel.localTargets.indices), id: \.self) { index in
            let target = viewModel.localTargets[index]
            let transformedRect = viewModel.transformRect(
                from: target.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.green, lineWidth: 1)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(target.className)")
                .poppinsFont(size: 6, style: .regular)
                .foregroundColor(.white)
                .padding(1)
                .background(Color.green)
                .position(x: transformedRect.midX, y: max(5, transformedRect.minY - 5))
        }
        
        ForEach(Array(viewModel.localCenters.indices), id: \.self) { index in
            let center = viewModel.localCenters[index]
            let transformedRect = viewModel.transformRect(
                from: center.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.blue, lineWidth: 1)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(center.className)")
                .poppinsFont(size: 6, style: .regular)
                .foregroundColor(.white)
                .padding(1)
                .background(Color.blue)
                .position(x: transformedRect.midX, y: max(5, transformedRect.minY - 5))
        }
    }
    
    @ViewBuilder
    private func RemoteDetectionOverlays(geometry: GeometryProxy, frame: UIImage) -> some View {
        ForEach(Array(viewModel.remoteBulletHoles.indices), id: \.self) { index in
            let bulletHole = viewModel.remoteBulletHoles[index]
            let transformedRect = viewModel.transformRect(
                from: bulletHole.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(bulletHole.id)")
                .poppinsFont(size: 8, style: .regular)
                .foregroundColor(.white)
                .padding(2)
                .background(Color.red)
                .position(x: transformedRect.midX, y: transformedRect.minY - 10)
        }
        
        if let latestBullet = viewModel.remoteLatestBulletHole {
            let transformedRect = viewModel.transformRect(
                from: latestBullet.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)
                .position(x: transformedRect.midX, y: transformedRect.midY)
        }
        
        ForEach(Array(viewModel.remoteTargets.indices), id: \.self) { index in
            let target = viewModel.remoteTargets[index]
            let transformedRect = viewModel.transformRect(
                from: target.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(target.className)")
                .poppinsFont(size: 16, style: .regular)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.green)
                .position(x: transformedRect.midX, y: transformedRect.minY - 10)
        }
        
        ForEach(Array(viewModel.remoteCenters.indices), id: \.self) { index in
            let center = viewModel.remoteCenters[index]
            let transformedRect = viewModel.transformRect(
                from: center.boundingBox,
                in: frame.size,
                to: geometry.size
            )
            
            Rectangle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: transformedRect.width, height: transformedRect.height)
                .position(x: transformedRect.midX, y: transformedRect.midY)
            
            Text("\(center.className)")
                .poppinsFont(size: 8, style: .regular)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.blue)
                .position(x: transformedRect.midX, y: transformedRect.minY - 10)
        }
    }
}

extension PeerConnectionState {
    var description: String {
        switch self {
        case .notConnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        }
    }
}

struct VideoSharingView_Previews: PreviewProvider {
    static var previews: some View {
        VideoSharingView()
    }
}
