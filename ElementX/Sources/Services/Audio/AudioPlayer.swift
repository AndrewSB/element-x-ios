//
// Copyright 2023 New Vector Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import AVFoundation
import Combine
import Foundation
import UIKit

private enum InternalAudioPlayerState {
    case none
    case loading
    case readyToPlay
    case playing
    case paused
    case stopped
    case finishPlaying
    case error(Error)
}

enum AudioPlayerError: Error {
    case genericError
}

class AudioPlayer: NSObject, AudioPlayerProtocol {
    private(set) var mediaSource: MediaSourceProxy?
    
    private var playerItem: AVPlayerItem?
    private var audioPlayer: AVQueuePlayer?
    
    private var cancellables = Set<AnyCancellable>()
    private let callbacksSubject: PassthroughSubject<AudioPlayerCallback, Never> = .init()
    var callbacks: AnyPublisher<AudioPlayerCallback, Never> {
        callbacksSubject.eraseToAnyPublisher()
    }
    
    private var internalState = InternalAudioPlayerState.none
    
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var playToEndObserver: NSObjectProtocol?
    private var appBackgroundObserver: NSObjectProtocol?
    
    var url: URL?
    
    var duration: TimeInterval {
        abs(CMTimeGetSeconds(audioPlayer?.currentItem?.duration ?? .zero))
    }
    
    var currentTime: TimeInterval {
        let currentTime = abs(CMTimeGetSeconds(audioPlayer?.currentTime() ?? .zero))
        return currentTime.isFinite ? currentTime : .zero
    }
    
    var state: MediaPlayerState {
        if case .loading = internalState {
            return .loading
        }
        if case .stopped = internalState {
            return .stopped
        }
        if case .playing = internalState {
            return .playing
        }
        if case .paused = internalState {
            return .paused
        }
        return .stopped
    }
    
    private var isStopped = true
    
    deinit {
        stop()
        unloadContent()
    }
    
    func load(mediaSource: MediaSourceProxy, mediaProvider: MediaProviderProtocol) async throws {
        if self.mediaSource == mediaSource {
            return
        }
        
        unloadContent()
        setInternalState(.loading)

        guard case .success(let fileHandle) = await mediaProvider.loadFileFromSource(mediaSource) else {
            throw AudioPlayerError.genericError
        }

        let audioConverter = AudioConverter()
        let url = try await audioConverter.convertAudioFileIfNeeded(mediaFileHandle: fileHandle, mediaSource: mediaSource)

        self.mediaSource = mediaSource
        self.url = url
        
        MXLog.error("[AudioPlayer] loading content at \(url.path())")

        playerItem = AVPlayerItem(url: url)
        audioPlayer = AVQueuePlayer(playerItem: playerItem)
        
        addObservers()
    }
    
    func unloadContent() {
        mediaSource = nil
        url = nil
        audioPlayer?.replaceCurrentItem(with: nil)
        removeObservers()
    }
    
    func play() async throws {
        isStopped = false

        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            MXLog.error("[AudioPlayer] Could not redirect audio playback to speakers.")
        }
        
        // If not paused, then the playback will start once the internal state is `.readyToPlay`
        if case .paused = internalState {
            audioPlayer?.play()
        }
    }
    
    func pause() {
        audioPlayer?.pause()
    }
    
    func stop() {
        if isStopped {
            return
        }
        
        isStopped = true
        audioPlayer?.pause()
        audioPlayer?.seek(to: .zero)
    }
    
    func seek(to progress: Double) async {
        MXLog.debug("[AudioPlayer] seek(to: \(progress)")
        let time = progress * duration
        guard let audioPlayer else { return }
        await audioPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 60000))
    }
    
    // MARK: - Private
    
    private func addObservers() {
        guard let audioPlayer, let playerItem else {
            return
        }
        
        statusObserver = playerItem.observe(\.status, options: [.old, .new]) { [weak self] _, _ in
            guard let self else { return }
            
            switch playerItem.status {
            case .failed:
                self.setInternalState(.error(playerItem.error ?? AudioPlayerError.genericError))
            case .readyToPlay:
                self.setInternalState(.readyToPlay)
            default:
                break
            }
        }
                
        rateObserver = audioPlayer.observe(\.rate, options: [.old, .new]) { [weak self] _, _ in
            guard let self else { return }
            
            if audioPlayer.rate == 0.0 {
                if self.isStopped {
                    self.setInternalState(.stopped)
                } else {
                    self.setInternalState(.paused)
                }
            } else {
                self.setInternalState(.playing)
            }
        }
                
        NotificationCenter.default.publisher(for: Notification.Name.AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setInternalState(.finishPlaying)
            }
            .store(in: &cancellables)
        
        // Request authorization uppon UIApplication.didBecomeActiveNotification notification
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.pause()
            }
            .store(in: &cancellables)
    }
    
    private func removeObservers() {
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        cancellables.removeAll()
    }
    
    private func setInternalState(_ state: InternalAudioPlayerState) {
        MXLog.debug("[AudioPlayer] setInternalState(\(state))")
        internalState = state
        switch state {
        case .none:
            break
        case .loading:
            dispatchCallback(.didStartLoading)
        case .readyToPlay:
            dispatchCallback(.didFinishLoading)
            audioPlayer?.play()
        case .playing:
            dispatchCallback(.didStartPlaying)
        case .paused:
            dispatchCallback(.didPausePlaying)
        case .stopped:
            dispatchCallback(.didStopPlaying)
        case .finishPlaying:
            dispatchCallback(.didFinishPlaying)
        case .error:
            dispatchCallback(.didFailWithError(error: AudioPlayerError.genericError))
        }
    }
    
    private func dispatchCallback(_ callback: AudioPlayerCallback) {
        MXLog.debug("[AudioPlayer] --> \(callback)")
        switch callback {
        case .didStartLoading, .didFinishLoading:
            break
        case .didStartPlaying:
            disableIdleTimer(true)
        case .didPausePlaying, .didStopPlaying, .didFinishPlaying:
            disableIdleTimer(false)
        case .didFailWithError(let error):
            MXLog.error("[AudioPlayer] audio player did fail. \(error)")
            disableIdleTimer(false)
        }
        callbacksSubject.send(callback)
    }
    
    private func disableIdleTimer(_ disabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }
}
