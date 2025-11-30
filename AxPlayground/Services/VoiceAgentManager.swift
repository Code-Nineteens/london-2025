//
//  VoiceAgentManager.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 30/11/2025.
//

@preconcurrency import AVFoundation
import Combine
import ElevenLabs
import LiveKit

@MainActor
final class VoiceAgentManager: ObservableObject {
    static let shared = VoiceAgentManager()
    
    // MARK: - State
    
    private(set) var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var connectionStatus: String = "Disconnected"
    @Published var startupState: ConversationStartupState = .idle
    @Published var startupMetrics: ConversationStartupMetrics?
    @Published var eventLogs: [String] = []
    
    private var lastLoggedMessageCount = 0
    
    // MARK: - Computed Properties
    
    var isConnected: Bool {
        guard let conversation else { return false }
        switch conversation.state {
        case .active: return true
        default: return false
        }
    }
    
    var isListening: Bool {
        conversation?.agentState == .listening
    }
    
    var isSpeaking: Bool {
        conversation?.agentState == .speaking
    }
    
    var isMuted: Bool {
        conversation?.isMuted ?? true
    }
    
    var messages: [Message] {
        conversation?.messages ?? []
    }
    
    var agentAudioTrack: RemoteAudioTrack? {
        conversation?.agentAudioTrack
    }
    
    private var agentId: String? {
        EnvManager.shared.getValue(for: "ELEVENLABS_AGENT_ID")
    }
    
    // MARK: - Init
    
    private init() {}
    
    // MARK: - Connection
    
    func startConversation() async {
        guard let agentId = agentId, !agentId.isEmpty else {
            connectionStatus = "Agent ID not configured"
            log("❌ ELEVENLABS_AGENT_ID not set")
            return
        }
        
        // Request microphone permission if needed
        let micPermission = await requestMicrophonePermission()
        guard micPermission else {
            connectionStatus = "Microphone access denied"
            log("❌ Microphone permission denied")
            return
        }
        
        resetState()
        
        do {
            let auth = ElevenLabsConfiguration.publicAgent(id: agentId)
            let config = makeConversationConfig()
            let newConversation = try await ElevenLabs.startConversation(auth: auth, config: config)
            conversation = newConversation
            
            setupObservers(for: newConversation)
            log("✅ Conversation started successfully")
        } catch {
            log("❌ Failed to start conversation: \(error.localizedDescription)")
            connectionStatus = "Failed to connect"
        }
    }
    
    func endConversation() async {
        await conversation?.endConversation()
        resetState()
        log("📴 Conversation ended")
    }
    
    func toggleMicrophone() async {
        do {
            try await conversation?.toggleMute()
        } catch {
            log("❌ Failed to toggle mute: \(error.localizedDescription)")
        }
    }
    
    func sendMessage(_ text: String) async {
        do {
            try await conversation?.sendMessage(text)
            log("📤 Sent message: \(text.prefix(50))...")
        } catch {
            log("❌ Failed to send message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private
    
    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            log("🎤 Microphone already authorized")
            return true
        case .notDetermined:
            log("🎤 Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                log("🎤 Microphone permission granted")
            } else {
                log("🎤 Microphone permission denied by user")
            }
            return granted
        case .denied, .restricted:
            log("🎤 Microphone permission denied/restricted")
            return false
        @unknown default:
            return false
        }
    }
    
    private func resetState() {
        cancellables.removeAll()
        conversation = nil
        lastLoggedMessageCount = 0
        startupState = .idle
        startupMetrics = nil
    }
    
    private func setupObservers(for newConversation: Conversation) {
        // State changes
        newConversation.$state.sink { [weak self] state in
            guard let self else { return }
            objectWillChange.send()
            
            switch state {
            case .idle:
                connectionStatus = "Disconnected"
            case .connecting:
                connectionStatus = "Connecting..."
            case .active:
                connectionStatus = "Connected"
            case .ended:
                connectionStatus = "Ended"
            case .error:
                connectionStatus = "Error"
            @unknown default:
                connectionStatus = "Unknown"
            }
            log("State -> \(String(describing: state))")
        }.store(in: &cancellables)
        
        // Messages
        newConversation.$messages.sink { [weak self] messages in
            guard let self else { return }
            objectWillChange.send()
            
            if messages.count != lastLoggedMessageCount {
                lastLoggedMessageCount = messages.count
                if let last = messages.last {
                    log("💬 [\(last.role)] \(last.content.prefix(80))...")
                }
            }
        }.store(in: &cancellables)
        
        // Agent state
        newConversation.$agentState.sink { [weak self] state in
            guard let self else { return }
            objectWillChange.send()
            
            switch state {
            case .listening:
                log("👂 Agent is listening")
            case .speaking:
                log("🗣️ Agent is speaking")
            @unknown default:
                break
            }
        }.store(in: &cancellables)
        
        // Mute state
        newConversation.$isMuted.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Startup metrics
        newConversation.$startupMetrics
            .sink { [weak self] metrics in
                self?.startupMetrics = metrics
                self?.log("📊 Startup metrics: attempts=\(metrics?.conversationInitAttempts ?? 0)")
            }
            .store(in: &cancellables)
        
        // Tool calls from agent
        newConversation.$pendingToolCalls
            .sink { [weak self] toolCalls in
                for toolCall in toolCalls {
                    self?.log("🔧 Tool call received: \(toolCall.toolName)")
                    Task {
                        await self?.handleToolCall(toolCall)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Tool Call Handling
    
    private func handleToolCall(_ toolCall: ClientToolCallEvent) async {
        do {
            let parameters = try toolCall.getParameters()
            log("🔧 Tool: \(toolCall.toolName), params: \(parameters)")
            
            switch toolCall.toolName {
            case "create_email", "compose_email", "write_email", "send_email":
                await handleCreateEmailTool(toolCall: toolCall, parameters: parameters)
                
            default:
                log("⚠️ Unknown tool: \(toolCall.toolName)")
                try await conversation?.sendToolResult(
                    for: toolCall.toolCallId,
                    result: "Unknown tool: \(toolCall.toolName)",
                    isError: true
                )
            }
        } catch {
            log("❌ Tool call error: \(error.localizedDescription)")
            try? await conversation?.sendToolResult(
                for: toolCall.toolCallId,
                result: error.localizedDescription,
                isError: true
            )
        }
    }
    
    private func handleCreateEmailTool(toolCall: ClientToolCallEvent, parameters: [String: Any]) async {
        let recipient = parameters["recipient"] as? String ?? parameters["to"] as? String
        let subject = parameters["subject"] as? String ?? "New Email"
        let body = parameters["body"] as? String ?? parameters["message"] as? String ?? parameters["content"] as? String ?? ""
        
        log("📧 Creating email:")
        log("   To: \(recipient ?? "none")")
        log("   Subject: \(subject)")
        log("   Body: \(body.prefix(50))...")
        
        // Open Mail app with the composed email
        MailHelper.compose(to: recipient, subject: subject, body: body)
        
        // Send success result back to agent
        do {
            try await conversation?.sendToolResult(
                for: toolCall.toolCallId,
                result: "Email draft opened in Mail app with subject: '\(subject)'"
            )
            log("📧 ✅ Email created successfully")
        } catch {
            log("📧 ❌ Failed to send tool result: \(error.localizedDescription)")
        }
    }
    
    private func makeConversationConfig() -> ConversationConfig {
        ConversationConfig(
            onStartupStateChange: { [weak self] state in
                Task { @MainActor in
                    self?.startupState = state
                    self?.log("🚀 Startup state -> \(String(describing: state))")
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.log("⚠️ SDK ERROR: \(error.localizedDescription)")
                }
            },
            onAgentResponse: { [weak self] _, eventId in
                Task { @MainActor in
                    self?.log("🤖 Agent response eventId=\(eventId)")
                }
            },
            onUserTranscript: { [weak self] transcript, _ in
                Task { @MainActor in
                    self?.log("👤 User transcript: \(transcript.prefix(80))...")
                }
            }
        )
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"
        print("[VoiceAgent] \(entry)")
        eventLogs.append(entry)
        if eventLogs.count > 30 {
            eventLogs.removeFirst(eventLogs.count - 30)
        }
    }
}
