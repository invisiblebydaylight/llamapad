import SwiftUI

struct SystemMessageConfigTab: View {
    @ObservedObject var appState: AppState
    @Binding var systemMessage: String
    @Binding var tokenCount: Int
    
    var body: some View {
        Form {
            Section("System Message") {
                TextEditor(text: $systemMessage)
                    .frame(height: 400)
                    .listRowSeparator(.hidden)
                    .scrollContentBackground(.hidden)
                    .onChange(of: systemMessage) {
                        Task {
                            tokenCount = await appState.backend?.countTokens(for: systemMessage) ?? 0
                        }
                    }
                    .onAppear(){
                        Task {
                            tokenCount = await appState.backend?.countTokens(for: systemMessage) ?? 0
                        }
                    }
                
                if tokenCount > 0 {
                    Text("\(tokenCount) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
