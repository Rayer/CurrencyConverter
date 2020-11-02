//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI
import SafariServices

struct ContentView: View {
    
    @ObservedObject var dataset = ConvertHistoryDMCollection()
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
                        Button("Enable/Disable Extension") {
                            SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.rayer.CurrencyConverter-Extension") { error in
                                if let _ = error {
                                    // Insert code to inform the user that something went wrong.
                                }
                            }
                            
                        }.padding(.all, 5)
                    }
                }
            }.tabItem {
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
