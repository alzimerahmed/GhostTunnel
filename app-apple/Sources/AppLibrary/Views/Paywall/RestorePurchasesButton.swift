// SPDX-FileCopyrightText: 2026 Davide De Rosa
//
// SPDX-License-Identifier: GPL-3.0

import CommonLibrary
import SwiftUI

struct RestorePurchasesButton: View {
    @Environment(IAPObservable.self)
    private var iapObservable

    private let errorHandler: ErrorHandler

    init(errorHandler: ErrorHandler) {
        self.errorHandler = errorHandler
    }

    var body: some View {
        Button(title) {
            Task {
                do {
                    try await iapObservable.restorePurchases()
                } catch {
                    errorHandler.handle(error, title: title)
                }
            }
        }
    }
}

private extension RestorePurchasesButton {
    var title: String {
        Strings.Views.Paywall.Rows.restorePurchases
    }
}
