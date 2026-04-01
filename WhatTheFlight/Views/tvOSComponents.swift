import SwiftUI

#if os(tvOS)
import UIKit
struct FlightCardView: View {
    let flight: FlightData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(flight.airline.name) \(flight.flightNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(flight.aircraft.model)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(6)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FROM")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(flight.route.origin)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Image(systemName: "airplane")
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TO")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(flight.route.destination)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Altitude")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(flight.position.altitude) ft")
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(flight.position.speed) kts")
                        .font(.body)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Heading")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(flight.position.heading)°")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .focusable()
    }
}

struct FlightGridView: View {
    let flights: [FlightData]
    let columns = [
        GridItem(.adaptive(minimum: 400, maximum: 500), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(flights, id: \.id) { flight in
                    FlightCardView(flight: flight)
                }
            }
            .padding(40)
        }
    }
}

struct StatusIndicatorView: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 16, height: 16)
            
            Text(statusText)
                .font(.headline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(25)
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        }
    }
}

struct TVMainView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                
                if viewModel.flights.isEmpty && viewModel.connectionStatus == .connected {
                    emptyStateView
                } else {
                    FlightGridView(flights: viewModel.flights)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("WhatTheFlight")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Aircraft Overhead")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                StatusIndicatorView(status: viewModel.connectionStatus)
                
                if !viewModel.flights.isEmpty {
                    Text("\(viewModel.flights.count) flights")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(40)
        .background(Color.primary.opacity(0.02))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No flights overhead")
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("Looking for aircraft in your area...")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(60)
    }
}
#endif