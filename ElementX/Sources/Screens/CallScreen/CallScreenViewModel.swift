//
// Copyright 2022 New Vector Ltd
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
import CallKit
import Combine
import SwiftUI

typealias CallScreenViewModelType = StateStoreViewModel<CallScreenViewState, CallScreenViewAction>

class CallScreenViewModel: CallScreenViewModelType, CallScreenViewModelProtocol {
    private let callController = CXCallController()
    private let callProvider = CXProvider(configuration: .init())
    
    private var callIdentifier: UUID?
    
    private var actionsSubject: PassthroughSubject<CallScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<CallScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    deinit {
        tearDownVoipSession(callIdentifier: callIdentifier)
    }
    
    init() {
//        let testURL = URL(string: "https://call.element.io/stefanTestsThings")!
//        let testURL = URL(string: Self.initialURLString)!
        let testURL = URL(string: "http://192.168.0.109:8000/#/?widgetId=stefan&userId=%40stefan.ceriu%3Amatrix.org")!
        
        super.init(initialViewState: CallScreenViewState(initialURL: testURL,
                                                         messageHandler: Self.eventHandlerName,
                                                         script: Self.eventHandlerInjectionScript))
                
        state.bindings.javaScriptMessageHandler = { message in
            MXLog.info("Received message: \(message)")
            
            let script = "postMessage({'requestId': '123', 'widgetId': '123', api: 'toWidget', 'action': 'capabilities', 'data': {}}, '*')"
            
            Task {
                await MXLog.info("JavaScript result: \(String(describing: self.evaluateJavaScript(script)))")
                MXLog.info("Done")
            }
        }
        
        Task {
            do {
                try await setupVoipSession()
            } catch {
                MXLog.error("")
            }
        }
    }
    
    override func process(viewAction: CallScreenViewAction) {
        switch viewAction {
        case .urlChanged(let url):
            guard let url else { return }
            MXLog.info("URL changed to: \(url)")
        }
    }
    
    // MARK: - CXCallObserverDelegate
    
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        MXLog.info("Call changed: \(call)")
    }
    
    // MARK: - CXProviderDelegate
    
    func providerDidReset(_ provider: CXProvider) {
        MXLog.info("Call provider did reset: \(provider)")
    }
    
    // MARK: - Private

    private static let eventHandlerName = "elementx"
    
    private static var eventHandlerInjectionScript: String {
        """
        window.addEventListener(
            "message",
            (event) => {
                let message = {data: event.data, origin: event.origin}
                if (message.data.response && message.data.api == "toWidget"
                || !message.data.response && message.data.api == "fromWidget") {
                  window.webkit.messageHandlers.\(eventHandlerName).postMessage(JSON.stringify(message.data));
                }else{
                  console.log("-- skipped event handling by the client because it is send from the client itself.");
                }
            },
            false,
          );
        """
    }
    
    private static var initialURLString: String {
        """
        https://element-call-livekit.netlify.app/room?\
        widgetId=stefan\
        &parentUrl=*\
        &embed=\
        &preload=\
        &hideHeader=\
        &userId=%40stefan.ceriu%3Amatrix.org\
        &deviceId=1234\
        &roomId=%21vkibNVqwhZVOaNskRU%3Amatrix.org\
        &baseUrl=https%3A%2F%2Fmatrix-client.matrix.org\
        &lang=en-us\
        &fontScale=1\
        &analyticsID=12345
        """
    }
    
    private func evaluateJavaScript(_ script: String) async -> String? {
        guard let evaluator = state.bindings.javaScriptEvaluator else {
            fatalError("Invalid javaScriptEvaluator")
        }
        
        do {
            return try await evaluator(script) as? String
        } catch {
            MXLog.error("Failed evaluating javaScript with error: \(error)")
            return nil
        }
    }
    
    private func setupVoipSession() async throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoChat, options: [])
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        
        let callIdentifier = UUID()
        
        let handle = CXHandle(type: .generic, value: state.initialURL.absoluteString)
        let startCallAction = CXStartCallAction(call: callIdentifier, handle: handle)
        startCallAction.isVideo = true
        
        let transaction = CXTransaction(action: startCallAction)
        
        try await callController.request(transaction)
        
        self.callIdentifier = callIdentifier
    }
    
    private nonisolated func tearDownVoipSession(callIdentifier: UUID?) {
        guard let callIdentifier else {
            return
        }
        
        try? AVAudioSession.sharedInstance().setActive(false)
            
        let endCallAction = CXEndCallAction(call: callIdentifier)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error {
                MXLog.error("Failed transaction with error: \(error)")
            } else {
                MXLog.error("Failed transaction")
            }
        }
    }
}
