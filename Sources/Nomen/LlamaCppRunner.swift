import Darwin
import Foundation
import LlamaSwift

enum LlamaCppError: LocalizedError {
    case loadFailed
    case contextFailed
    case notLoaded
    case tokenizeFailed
    case promptExceedsContext(promptTokens: Int, maxBatch: Int, nCtx: Int)
    case samplerFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "GGUF-Modell konnte nicht geladen werden."
        case .contextFailed:
            return "Llama-Kontext konnte nicht erstellt werden."
        case .notLoaded:
            return "Llama-Modell ist nicht geladen."
        case .tokenizeFailed:
            return "Tokenisierung fehlgeschlagen."
        case .promptExceedsContext(let p, let b, let c):
            return "Prompt zu lang für den Llama-Kontext (\(p) Tokens, max. Batch \(b), Kontext \(c))."
        case .samplerFailed:
            return "Sampler konnte nicht initialisiert werden."
        case .decodeFailed:
            return "Inferenz (llama_decode) fehlgeschlagen."
        }
    }
}

/// Chat-Vorlage wie in `tokenizer_config.json` (Qwen2.5-Instruct).
enum Qwen25InstructChatTemplate {
    private static let imStart = "<|im_start|>"
    /// EOS laut Tokenizer (151645).
    private static let imEnd = String(decoding: [0x3C, 0x7C, 0x69, 0x6D, 0x5F, 0x65, 0x6E, 0x64, 0x7C, 0x3E], as: UTF8.self)

    static func buildPrompt(
        systemInstructions: String,
        userContent: String,
        assistantPrefill: String = ""
    ) -> String {
        if assistantPrefill.isEmpty {
            return """
            \(imStart)system
            \(systemInstructions)\(imEnd)
            \(imStart)user
            \(userContent)\(imEnd)
            \(imStart)assistant

            """
        }
        return """
        \(imStart)system
        \(systemInstructions)\(imEnd)
        \(imStart)user
        \(userContent)\(imEnd)
        \(imStart)assistant
        \(assistantPrefill)
        """
    }
}

/// Serielle GGUF-Inferenz (llama.cpp via LlamaSwift); ein geladenes Modell wird zwischen Aufrufen wiederverwendet.
actor LlamaCppRunner {
    static let shared = LlamaCppRunner()

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var loadedPath: String?
    private var backendBootstrapped = false

    private init() {}

    /// Modell aus dem Speicher nehmen (z. B. Backend gewechselt); llama-Backend bleibt aktiv.
    func unload() {
        if let ctx {
            llama_free(ctx)
            self.ctx = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        loadedPath = nil
    }

    func ensureLoaded(modelPath: String) throws {
        if loadedPath == modelPath, model != nil, ctx != nil { return }
        unload()

        if !backendBootstrapped {
            backendBootstrapped = true
            llama_backend_init()
            ggml_backend_load_all()
        }

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = llama_supports_gpu_offload() ? 99 : 0

        guard let m = modelPath.withCString({ llama_model_load_from_file($0, mparams) }) else {
            throw LlamaCppError.loadFailed
        }
        model = m

        // n_batch: max. Tokens pro llama_decode — der gesamte Prompt wird in einem Batch gefüttert (siehe generateContinuation).
        // Zu kleines n_batch (z. B. 2048) bei langem Prompt → undefiniertes Verhalten / Absturz in llama.cpp.
        // n_ctx: muss Prompt + max. neue Tokens abdecken, sonst scheitert llama_decode in der Generierungsphase.
        var cparams = llama_context_default_params()
        cparams.n_ctx = 12288
        cparams.n_batch = 8192
        cparams.no_perf = true

        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            model = nil
            throw LlamaCppError.contextFailed
        }
        ctx = c
        loadedPath = modelPath
    }

    /// `llama_token_to_piece` liefert bei zu kleinem Puffer eine negative Länge — dann vergrößern (verhindert Abstürze/Truncation).
    private static func utf8Piece(for token: llama_token, vocab: OpaquePointer?) -> String {
        guard let vocab else { return "" }
        var buffer = [CChar](repeating: 0, count: 256)
        while true {
            let needed = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
                guard let b = buf.baseAddress else { return 0 }
                return llama_token_to_piece(vocab, token, b, Int32(buf.count), 0, true)
            }
            if needed >= 0 {
                let n = min(Int(needed), buffer.count)
                let utf8Slice = buffer.prefix(n).map { UInt8(bitPattern: $0) }
                return String(decoding: utf8Slice, as: UTF8.self)
            }
            let required = Int(-needed)
            if required <= buffer.count {
                return ""
            }
            buffer = [CChar](repeating: 0, count: min(required + 8, 65_536))
        }
    }

    /// - Parameter jsonLeadIn: Text, der bereits im Prompt als Assistenten-Prefill steht (z. B. `{"date":"`), damit die JSON-Stop-Erkennung den vollen Inhalt sieht.
    func generateContinuation(
        afterFullPrompt fullPrompt: String,
        jsonLeadIn: String = "",
        maxNewTokens: Int32 = 512
    ) throws -> String {
        guard let model, let ctx else { throw LlamaCppError.notLoaded }

        llama_memory_clear(llama_get_memory(ctx), true)

        let vocab = llama_model_get_vocab(model)

        let nPrompt: Int = fullPrompt.withCString { cPtr in
            let len = Int32(strlen(cPtr))
            let neg = llama_tokenize(vocab, cPtr, len, nil, 0, true, true)
            guard neg < 0 else { return 0 }
            return Int(-neg)
        }
        guard nPrompt > 0 else { throw LlamaCppError.tokenizeFailed }

        var promptTokens = [llama_token](repeating: 0, count: nPrompt)
        let tokOK: Bool = fullPrompt.withCString { cPtr in
            let len = Int32(strlen(cPtr))
            let r = promptTokens.withUnsafeMutableBufferPointer { buf -> Int32 in
                guard let b = buf.baseAddress else { return -1 }
                return llama_tokenize(vocab, cPtr, len, b, Int32(buf.count), true, true)
            }
            return r >= 0
        }
        guard tokOK else { throw LlamaCppError.tokenizeFailed }

        let nCtx = Int(llama_n_ctx(ctx))
        let nBatch = Int(llama_n_batch(ctx))
        guard nPrompt <= nBatch else {
            throw LlamaCppError.promptExceedsContext(promptTokens: nPrompt, maxBatch: nBatch, nCtx: nCtx)
        }
        guard nPrompt + Int(maxNewTokens) <= nCtx else {
            throw LlamaCppError.promptExceedsContext(promptTokens: nPrompt, maxBatch: nBatch, nCtx: nCtx)
        }

        var sparams = llama_sampler_chain_default_params()
        sparams.no_perf = true
        guard let smpl = llama_sampler_chain_init(sparams) else {
            throw LlamaCppError.samplerFailed
        }
        defer { llama_sampler_free(smpl) }
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy())

        var batch = promptTokens.withUnsafeMutableBufferPointer { buf -> llama_batch in
            llama_batch_get_one(buf.baseAddress!, Int32(buf.count))
        }

        if llama_model_has_encoder(model) {
            if llama_encode(ctx, batch) != 0 {
                throw LlamaCppError.decodeFailed
            }
            var decoderStart = llama_model_decoder_start_token(model)
            if decoderStart == LLAMA_TOKEN_NULL {
                decoderStart = llama_vocab_bos(vocab)
            }
            batch = llama_batch_get_one(&decoderStart, 1)
        }

        var output = ""
        var nPos = 0
        let limit = nPrompt + Int(maxNewTokens)

        while nPos + Int(batch.n_tokens) < limit {
            let dec = llama_decode(ctx, batch)
            if dec < 0 {
                throw LlamaCppError.decodeFailed
            }
            nPos += Int(batch.n_tokens)

            let newTokenId = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, newTokenId) {
                break
            }

            output.append(Self.utf8Piece(for: newTokenId, vocab: vocab))

            var single = newTokenId
            batch = llama_batch_get_one(&single, 1)

            if output.count > 8192 { break }
            if DocumentNamingPipeline.ggufShouldStopGeneration(leadIn: jsonLeadIn, generatedSuffix: output) {
                break
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
