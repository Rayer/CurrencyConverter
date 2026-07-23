//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import AppKit
import SwiftUI

struct ContentView: View {
    
    @ObservedObject var dataset = ConvertHistoryDMCollection()
    @ObservedObject private var extensionSettings: SafariExtensionSettingsViewModel
    @ObservedObject private var templates: ConversionTemplateManagementViewModel
    @State var showInstallButton = true
    @State var currentTab = 0
    
    init(
        extensionSettings: SafariExtensionSettingsViewModel,
        templates: ConversionTemplateManagementViewModel = ConversionTemplateManagementViewModel()
    ) {
        _extensionSettings = ObservedObject(wrappedValue: extensionSettings)
        _templates = ObservedObject(wrappedValue: templates)
        NotificationCenter.default.addObserver(dataset, selector: #selector(type(of: dataset).reload), name: .NSPersistentStoreRemoteChange, object: sharedPersistentContainer.persistentStoreCoordinator)
        dataset.reload()
    }

    var body: some View {
        
        
        TabView(selection: self.$currentTab) {
            VStack {
                //https://stackoverflow.com/questions/60994255/swiftui-get-toggle-state-from-items-inside-a-list
                List(dataset.data.indices, id:\.self) { index in
                    Toggle("", isOn: self.$dataset.data[index].isChecked)
                    EntityDetailRow(self.dataset.data[index])
                }
                HStack {
                    HStack {
                        Button(NSLocalizedString("Wipe all", comment: "History action")) {
                            dataset.wipe()
                            //wipeAll()
                        }
                        Button(NSLocalizedString("Wipe selected", comment: "History action")) {
                            dataset.wipeChecked()
                        }
                        Button(NSLocalizedString("Renew currency exchange rate", comment: "History action")) {
                            dataset.renewFx()
                        }
                    }.padding(.all, 5)
                    Spacer()
                    if self.showInstallButton {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(extensionSettings.copy.statusText)
                                .font(.caption)
                                .multilineTextAlignment(.trailing)
                                .accessibility(label: Text(NSLocalizedString("Safari extension status", comment: "Accessibility label")))
                                .accessibility(value: Text(extensionSettings.copy.accessibilityValue))
                            Button(extensionSettings.copy.actionTitle) {
                                extensionSettings.openSettings()
                            }
                            .accessibility(hint: Text(extensionSettings.copy.accessibilityHint))
                        }
                        .padding(.all, 5)
                    }
                }
            }
            .onAppear {
                extensionSettings.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                extensionSettings.refresh()
            }
            .tabItem {
                Text(NSLocalizedString("Stored Records", comment: "Main tab title"))
                
            }.tag(0)
            .onAppear() {
                self.currentTab = 0
            }
            
            ScrollView(.vertical, showsIndicators: true, content: {
                CreditCardManageView()
            })
            .tabItem { Text(NSLocalizedString("Credit Cards", comment: "Main tab title")) }.tag(1)
            .onAppear() {
                self.currentTab = 1
            }
            
            #if DEBUG
            APISyncInfoView(host: ApiSyncInfoViewModel(sharedUserDefaults))
                .tabItem { Text(NSLocalizedString("API Sync Records", comment: "Main tab title")) }.tag(2)
                .onAppear() {
                    self.currentTab = 2
            }
            #endif

            ConversionTemplateManagementView(model: templates)
                .tabItem { Text(NSLocalizedString("Conversion Formats", comment: "Main tab title")) }
                .tag(3)
                .onAppear {
                    self.currentTab = 3
                }
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity, alignment: .center)
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView(extensionSettings: SafariExtensionSettingsViewModel(provider: PreviewSafariExtensionSettingsProvider()))
    }
}

private struct PreviewSafariExtensionSettingsProvider: SafariExtensionSettingsProviding {
    func fetchState(completion: @escaping (SafariExtensionSettingsResult) -> Void) {
        completion(.status(.unknown))
    }

    func openSettings(completion: @escaping (String?) -> Void) {
        completion(nil)
    }
}
