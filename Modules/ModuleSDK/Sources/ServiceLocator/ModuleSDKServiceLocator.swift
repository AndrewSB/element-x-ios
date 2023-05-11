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

public final class ModuleSDKServiceLocator {
    public static let shared = ModuleSDKServiceLocator()

    private lazy var registry: [ModuleSDKServiceKey: ModuleSDKService] = [:]

    public func registerService<T: ModuleSDKService>(_ service: T) {
        let key = service.key
        registry[key] = service
    }

    // Note: should really be `T: ModuleSDKService` but it makes Swift unhappy.
    public func getService<T>(_ key: ModuleSDKServiceKey) -> T? {
        registry[key] as? T
    }

    private init() { }
}
