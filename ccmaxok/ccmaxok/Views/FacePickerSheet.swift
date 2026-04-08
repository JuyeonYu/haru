import SwiftUI

struct FacePickerData: Identifiable {
    let id = UUID()
    let candidates: [NSImage]
}

struct FacePickerSheet: View {
    let candidates: [NSImage]
    let onSelect: (NSImage) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("얼굴을 선택하세요")
                .font(.headline)

            Text("\(candidates.count)개의 얼굴이 감지되었습니다")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { index, image in
                        Button {
                            onSelect(image)
                        } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    )
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            Button("취소") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(minWidth: 300, minHeight: 180)
    }
}
