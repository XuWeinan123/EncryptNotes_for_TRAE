import Foundation
import SwiftUI

struct PlainStatusBadge: View {
    let isEncrypted: Bool

    var body: some View {
        HStack(spacing: DS.s1) {
            Image(systemName: isEncrypted ? "lock.fill" : "doc.text")
                .font(.system(size: 10))
            Text(isEncrypted ? "加密" : "明文")
                .font(DS.caption())
        }
        .foregroundColor(isEncrypted ? DS.primary : DS.textSecondary)
        .padding(.horizontal, DS.s2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .fill(isEncrypted ? DS.primaryContainer : DS.surfaceSunken)
        )
    }
}
