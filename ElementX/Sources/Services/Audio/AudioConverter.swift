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
import Foundation
import SwiftOGG

enum AudioConverterError: Error {
    case conversionFailed(Error?)
    case getDurationFailed(Error?)
    case cancelled
}

struct AudioConverter {
    private var temporaryFilesFolderURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("media")
    }
    
    init() {
        try? setupTemporaryFilesFolder()
    }

    func convertAudioFileIfNeeded(mediaFileHandle: MediaFileHandleProxy, mediaSource: MediaSourceProxy) async throws -> URL {
        // Convert from ogg if needed
        if mediaFileHandle.url.hasSupportedAudioExtension {
            return mediaFileHandle.url
        } else {
            var newURL = temporaryFilesFolderURL.appendingPathComponent(mediaSource.url.lastPathComponent).deletingPathExtension()
            let fileExtension = "m4a"
            newURL.appendPathExtension(fileExtension)

            // Do we already have a converted version?
            if !FileManager.default.fileExists(atPath: newURL.path()) {
                MXLog.debug("[AudioPlayer] conversion is needed")

                do {
                    try await convertToMPEG4AACIfNeeded(sourceURL: mediaFileHandle.url, destinationURL: newURL)
                } catch {
                    MXLog.error("[AudioPlayer] failed to convert to MPEG4AAC: \(error)")
                    throw AudioPlayerError.genericError
                }
            }
            return newURL
        }
    }
    
    private func convertToOpusOgg(sourceURL: URL, destinationURL: URL) async throws {
        do {
            try OGGConverter.convertM4aFileToOpusOGG(src: sourceURL, dest: destinationURL)
        } catch {
            throw AudioConverterError.conversionFailed(error)
        }
    }
    
    private func convertToMPEG4AACIfNeeded(sourceURL: URL, destinationURL: URL) async throws {
        let start = Date()
        MXLog.debug("[AudioConverter] converting audio file from \(sourceURL.absoluteString) to \(destinationURL.absoluteString)")
        do {
            if sourceURL.hasSupportedAudioExtension {
                try FileManager.default.copyItem(atPath: sourceURL.path, toPath: destinationURL.path)
            } else {
                try OGGConverter.convertOpusOGGToM4aFile(src: sourceURL, dest: destinationURL)
            }
        } catch {
            throw AudioConverterError.conversionFailed(error)
        }
        MXLog.debug("[AudioConverter] converting audio file done in \(Date().timeIntervalSince(start))")
    }
    
    private func mediaDurationAt(_ sourceURL: URL) async throws -> TimeInterval {
        let audioAsset = AVURLAsset(url: sourceURL, options: nil)

        do {
            let duration = try await audioAsset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            throw AudioConverterError.getDurationFailed(error)
        }
    }
    
    
    // MARK: - Cache
    
    private func setupTemporaryFilesFolder() throws {
        let url = temporaryFilesFolderURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func clearCache() {
        if FileManager.default.fileExists(atPath: temporaryFilesFolderURL.path) {
            do {
                try FileManager.default.removeItem(at: temporaryFilesFolderURL)
            } catch {
                MXLog.error("[MediaPlayerProvider] Failed clearing cached disk files", context: error)
            }
        }
    }
}

extension URL {
    /// Returns true if the URL has a supported audio extension
    var hasSupportedAudioExtension: Bool {
        let supportedExtensions = ["mp3", "mp4", "m4a", "wav", "aac"]
        return supportedExtensions.contains(pathExtension.lowercased())
    }
}

