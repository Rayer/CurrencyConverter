//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var dataset = ConvertHistoryDMCollection()
    @ObservedObject private var extensionSettings = SafariExtensionSettingsViewModel()
    @State var showInstallButton = true
    @State var currentTab = 0
    
    init() {
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
                        Button("Wipe all") {
                            dataset.wipe()
                            //wipeAll()
                        }
                        Button("Wipe selected") {
                            dataset.wipeChecked()
                        }
                        Button("Renew currency exchange rate") {
                            dataset.renewFx()
                        }
                    }.padding(.all, 5)
                    Spacer()
                    if self.showInstallButton {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(extensionSettings.copy.statusText)
                                .font(.caption)
                                .multilineTextAlignment(.trailing)
                                .accessibility(label: Text("Safari extension status"))
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
            .tabItem {
                Text("Stored Records")
                
            }.tag(0)
            .onAppear() {
                self.currentTab = 0
            }
            
            ScrollView(.vertical, showsIndicators: true, content: {
                CreditCardManageView()
            })
            .tabItem { Text("Credit Cards") }.tag(1)
            .onAppear() {
                self.currentTab = 1
            }
            
            #if DEBUG
            APISyncInfoView(host: ApiSyncInfoViewModel(sharedUserDefaults))
                .tabItem { Text("API Sync Records") }.tag(2)
                .onAppear() {
                    self.currentTab = 2
                }
            #endif
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity, alignment: .center)
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
