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
    
    init() {
        NotificationCenter.default.addObserver(dataset, selector: #selector(type(of: dataset).reload), name: .NSPersistentStoreRemoteChange, object: sharedPersistentContainer.persistentStoreCoordinator)
//        checkExtInstall()
        dataset.reload()
    }

//    func checkExtInstall() {
//        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: "com.rayer.CurrencyConverter-Extension") { (state, error) in
//            if let state = state {
//                self.showInstallButton = !state.isEnabled
//                print("State enabled : \(state.isEnabled)")
//                print("State enabled2 : \(!state.isEnabled)")
//                print("Will install button show : \(self.showInstallButton)")
//            }
//        }
//    }
    
    var body: some View {
        
        VStack {
            //https://stackoverflow.com/questions/60994255/swiftui-get-toggle-state-from-items-inside-a-list
            List(dataset.data.indices, id:\.self) { index in
                Toggle("", isOn: self.$dataset.data[index].isChecked)
                EntityDetailRow(self.dataset.data[index])
            }
            HStack {
//                Button("Reload(For debugging)") {
//                    dataset.reload()
//                }
                HStack {
                    Button("Wipe all") {
                        dataset.wipe()
                        //wipeAll()
                    }
                    Button("Wipe selected") {
                        dataset.wipeChecked()
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
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .center)
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
