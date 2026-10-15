
import SwiftUI

struct AttachmentChipView: View {
    let attachment: Attachment
    var onRemove: () -> Void
    
    @State private var showingPreview = false
    #if os(macOS)
    @State private var isHovering = false
    #endif
    
    private var fileIcon: String {
        switch attachment.contentType {
        case .text: return "doc.text"
        case .image: return "photo"
        }
    }
    
    private var previewText: String {
        guard let content = attachment.textContent else { return "(no text content)" }
        let lines = content.components(separatedBy: "\n")
        if lines.count > 50 {
            return lines.prefix(50).joined(separator: "\n") + "\n\n... (\(lines.count - 50) more lines)"
        }
        return content
    }
    
    @ViewBuilder
    private var chipIcon: some View {
        if attachment.contentType == .image, let imageData = attachment.imageData {
            #if os(macOS)
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
            }
            #else
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
            }
            #endif
        } else {
            Image(systemName: fileIcon)
                .font(.caption)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            chipIcon
            
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.secondary.opacity(0.15))
        )
        .overlay(
            Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture { showingPreview = true }
        .popover(isPresented: $showingPreview) {
            if attachment.contentType == .image, let imageData = attachment.imageData {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(attachment.filename).font(.headline)
                        Spacer()
                        Text("~\(attachment.tokenEstimate) tokens")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 300)
                    }
                    #else
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 300)
                    }
                    #endif
                }
                .padding()
                .frame(maxWidth: 450, maxHeight: 350)
            } else {
                // text preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(attachment.filename).font(.headline)
                        Spacer()
                        Text("~\(attachment.tokenEstimate) tokens")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(previewText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                }
                .padding()
                .frame(minWidth: 400, idealWidth: 500, minHeight: 200, idealHeight: 300)
            }
        }
        #if os(macOS)
        .onHover { hovering in withAnimation { isHovering = hovering } }
        #endif
    }
}
