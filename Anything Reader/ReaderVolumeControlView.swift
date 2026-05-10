//
//  ReaderVolumeControlView.swift
//  Anything Reader
//
//  A compact player volume control that keeps the player bar focused on
//  transport actions while volume stays easy to discover and adjust.
//

import SwiftUI

struct ReaderVolumeControlView: View {
    @Binding var volume: Double
    let preferredMode: AppearanceMode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volumeSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 18)

            Slider(value: $volume, in: 0...1)
                .tint(ReaderStyle.accentColor(named: "emerald"))
                .readerPointerCursor()

            Text("\(Int((volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondaryTextColor)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(surfaceColor, in: RoundedRectangle(cornerRadius: 8))
    }

    private var volumeSymbolName: String {
        switch volume {
        case 0:
            return "speaker.slash.fill"
        case ..<0.34:
            return "speaker.wave.1.fill"
        case ..<0.67:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    private var surfaceColor: Color {
        preferredMode == .light ? Color.white.opacity(0.56) : Color.white.opacity(0.07)
    }

    private var secondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.60) : Color.white.opacity(0.72)
    }
}

struct ReaderPlaybackSpeedControlView: View {
    @Binding var playbackSpeed: Double
    let preferredMode: AppearanceMode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 18)

            Slider(value: $playbackSpeed, in: 0.5...2.0, step: 0.1)
                .tint(ReaderStyle.accentColor(named: "amber"))
                .readerPointerCursor()

            Text("\(playbackSpeed, specifier: "%.1fx")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondaryTextColor)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(surfaceColor, in: Rectangle())
    }

    private var surfaceColor: Color {
        preferredMode == .light ? Color.white.opacity(0.56) : Color.white.opacity(0.07)
    }

    private var secondaryTextColor: Color {
        preferredMode == .light ? Color.black.opacity(0.60) : Color.white.opacity(0.72)
    }
}
