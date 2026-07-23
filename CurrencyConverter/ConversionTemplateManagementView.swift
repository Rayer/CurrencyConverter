//
//  ConversionTemplateManagementView.swift
//  CurrencyConverter
//

import SwiftUI

final class ConversionTemplateManagementViewModel: ObservableObject {
    @Published private(set) var templates: [ConversionTemplate] = []
    @Published private(set) var selectedID: UUID?
    @Published var input = ""
    @Published private(set) var preview = ""
    @Published private(set) var errorMessage: String?

    private let manager: FormatStringDataManager

    init(manager: FormatStringDataManager = .shared) {
        self.manager = manager
        refresh()
    }

    func updateInput(_ value: String) {
        input = value
        switch ConversionTemplateFormatter.preview(value) {
        case .success(let value):
            preview = value
            errorMessage = nil
        case .failure(let error):
            preview = ""
            errorMessage = error.errorDescription
        }
    }

    func refresh() {
        switch manager.availableTemplates() {
        case .success(let templates):
            switch manager.selectedTemplate() {
            case .success(let selected):
                self.templates = templates
                selectedID = selected.id
                errorMessage = nil
            case .failure(let error):
                self.templates = []
                selectedID = nil
                preview = ""
                errorMessage = error.errorDescription
            }
        case .failure(let error):
            templates = []
            selectedID = nil
            preview = ""
            errorMessage = error.errorDescription
        }
    }

    func add() {
        switch manager.add(template: input) {
        case .success:
            input = ""
            preview = ""
            refresh()
        case .failure(let error):
            handle(error)
        }
    }

    func select(_ id: UUID) {
        switch manager.select(id: id) {
        case .success(let selected):
            selectedID = selected.id
            errorMessage = nil
        case .failure(let error):
            handle(error)
        }
    }

    func delete(_ id: UUID) {
        switch manager.delete(id: id) {
        case .success(let selected):
            selectedID = selected.id
            refresh()
        case .failure(let error):
            handle(error)
        }
    }

    func reset() {
        switch manager.reset() {
        case .success:
            input = ""
            preview = ""
            refresh()
        case .failure(let error):
            handle(error)
        }
    }

    private func handle(_ error: ConversionTemplateOperationError) {
        if case .repository = error {
            templates = []
            selectedID = nil
            preview = ""
        }
        errorMessage = error.errorDescription
    }
}

struct ConversionTemplateManagementView: View {
    @ObservedObject var model: ConversionTemplateManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Conversion formats", comment: "Conversion template section title"))
                .font(.headline)

            List {
                ForEach(model.templates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.text)
                                .lineLimit(2)
                            if model.selectedID == template.id {
                                Text(NSLocalizedString("Selected", comment: "Conversion template selection badge"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(model.selectedID == template.id
                            ? NSLocalizedString("Selected", comment: "Conversion template selected button state")
                            : NSLocalizedString("Use", comment: "Conversion template default action")) {
                            model.select(template.id)
                        }
                        .disabled(model.selectedID == template.id)
                        .accessibility(label: Text(NSLocalizedString("Select conversion format", comment: "Template action accessibility")))
                        Button(NSLocalizedString("Delete", comment: "Template action")) {
                            model.delete(template.id)
                        }
                        .disabled(ConversionTemplateCatalog.defaultIDs.contains(template.id))
                        .accessibility(label: Text(NSLocalizedString("Delete conversion format", comment: "Template action accessibility")))
                    }
                }
            }

            TextField(NSLocalizedString("New format", comment: "Template input placeholder"), text: Binding(
                get: { model.input },
                set: { model.updateInput($0) }
            ))
            .accessibility(label: Text(NSLocalizedString("New conversion format", comment: "Template input accessibility")))

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Preview", comment: "Template preview title"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(model.preview.isEmpty
                    ? NSLocalizedString("Enter a valid format to preview it.", comment: "Template preview guidance")
                    : model.preview
                )
                    .foregroundColor(model.preview.isEmpty ? .secondary : .primary)
                    .accessibility(label: Text(NSLocalizedString("Conversion format preview", comment: "Template preview accessibility")))
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .accessibility(label: Text(NSLocalizedString("Conversion format error", comment: "Template error accessibility")))
            }

            HStack {
                Button(NSLocalizedString("Add", comment: "Template action")) { model.add() }
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.preview.isEmpty)
                Button(NSLocalizedString("Reset defaults", comment: "Template action")) { model.reset() }
                Spacer()
            }
        }
        .padding()
        .onAppear { model.refresh() }
    }
}
