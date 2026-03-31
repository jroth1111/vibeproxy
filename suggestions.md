# VibeProxy Mitigation Strategy for NVIDIA & Z.AI Backends

To ensure robust handling of MiniMax-M2.5, Kimi-K2.5, and GLM-5 models via NVIDIA and Z.AI, we must shift from reactive shimming to a structured, policy-driven mitigation layer.

## 1. Identified Mitigation Cases

| Model | Provider | Primary Issues |
| :--- | :--- | :--- |
| `minimax-m2.5-nvidia` | NVIDIA | Needs `max_tokens` floor (128), strip `reasoning_effort`, `response_format`, `stop`. |
| `kimi-k2.5-nvidia` | NVIDIA | Needs strip `reasoning_effort`. |
| `glm5` / `z-ai/glm5` | NVIDIA | Needs strip `reasoning_effort`. |
| `glm-5` | Z.AI | Potential raw state leakage/encoding issues. |

## 2. Recommended Architectural Changes

### A. Formal Policy Registry
Instead of a hardcoded dictionary in `ThinkingProxy`, define a formal `RequestPolicy` registry that can be tested independently.

### B. Response Buffering & Repair Layer
The current streaming logic in `ThinkingProxy` lacks a "correction" hook for generic responses. 
- **Action:** Implement a buffered response handler for identified sensitive models.
- **Workflow:** 
    1. Intercept `URLSession` data task.
    2. Buffer the full JSON response.
    3. Run `evaluateNvidiaReasoningResponse` (and analogous Z.AI inspectors).
    4. If repairs are needed (e.g., stripping `<think>` tags), rewrite the JSON body *before* streaming to the requester.

### C. Rigorous Testing Suite
Create a dedicated spec file `src/Verification/RigorousModelMitigationSpec.swift` that runs against the production-like shim logic to ensure zero-regression on:
1. **Request Shaping**: Verify all stripped fields are removed and mandatory floors (like 128 tokens) are applied.
2. **Raw State Leakage**: Inject known "poisoned" responses (e.g., `<think> content </think>` blocks or empty bodies) and assert they are normalized before reaching the client.

## 3. Immediate Implementation Priorities

1.  **Refactor `OpenAICompatTemporaryShim`**: Extract the policies into a struct-based configuration that defines `requiredTransformations` and `responseRepairHooks`.
2.  **Unify Backend Callers**: Consolidate `forwardNvidiaReasoningRequestWithRetry` and potential Z.AI equivalent logic into a single generic `ProtectedBackendForwarder`.
3.  **Cross-Model Verification**: Add the requested test cases for `MiniMax-M2.5`, `Kimi-K2.5`, `zai/glm5`, and `glm-5` to ensure the mitigation layer handles them uniformly.
