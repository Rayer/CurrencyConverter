//
//  UserDefaultsView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/14.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct APISyncInfoView: View {
    @ObservedObject var host : ApiSyncInfoViewModel
    var body: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("Last updated : ", comment: "API sync row label"))
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                Text(host.lastUpdate ?? "----")
                Spacer()
            }.frame(alignment: .leading)
            HStack {
                Text(NSLocalizedString("Parsed data time stamp : ", comment: "API sync row label"))
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                Text(host.parsedPayloadUpdate ?? "----")
                Spacer()
            }.frame(alignment: .leading)
            HStack {
                Text(NSLocalizedString("Rate status : ", comment: "API sync row label"))
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                Text(host.rateStatus.message)
                Spacer()
            }.frame(alignment: .leading)
            HStack {
                Text(NSLocalizedString("Raw Data : ", comment: "API sync row label"))
                    .font(.system(.body, design: Font.Design.rounded))
                    .frame(width: 200, alignment: .leading)
                ScrollView {
                    Text(host.rawData ?? "----")
                }
            }.frame(alignment: .leading)
            Spacer()
            HStack {
                Button(NSLocalizedString("Reload from API", comment: "API sync button")) {
                    host.sync()
                }
                Button(NSLocalizedString("Copy Raw Data to Clipboard", comment: "API sync button")) {
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
        APISyncInfoView(host: ApiSyncInfoViewModel(sharedUserDefaults))
    }
}
