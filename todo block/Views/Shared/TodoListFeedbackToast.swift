import SwiftUI

struct TodoListFeedbackToast: View {
    let feedback: TodoListFeedback?

    var body: some View {
        ZStack {
            if let feedback {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text(feedback.message)
                        .lineLimit(2)
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.78))
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedback.message)
            }
        }
        .animation(.easeOut(duration: 0.18), value: feedback?.id)
        .allowsHitTesting(false)
    }
}
