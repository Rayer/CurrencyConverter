//
//  UserDefaultsView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/14.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct APISyncInfoView: View {
    @ObservedObject var host : APISyncInfoDataModel
    var body: some View {
        VStack {
            HStack {
                Text("Last updated : ")
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                Text(host.lastUpdate ?? "----")
                Spacer()
            }.frame(alignment: .leading)
            HStack {
                Text("Parsed data time stamp : ")
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                Text(host.parsedPayloadUpdate ?? "----")
                Spacer()
            }.frame(alignment: .leading)
            HStack {
                Text("Raw Data : ")
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                ScrollView {
                    Text(host.rawData ?? "----")
                }
            }.frame(alignment: .leading)
            Spacer()
            HStack {
                Button("Reload from API") {
                    host.sync()
                }
                Button("Copy Raw Data to Clipboard") {
                    let pasteBoard = NSPasteboard.general
                    pasteBoard.clearContents()
                    if let rawData = host.rawData {
                        pasteBoard.setString(rawData, forType: .string)
                    }
                }
            }.frame(alignment: .leading)
        }
    }
}

struct APISyncInfoView_Previews: PreviewProvider {
    static var previews: some View {
        APISyncInfoView(host: APISyncInfoDataModel(sharedUserDefaults))
    }
}
