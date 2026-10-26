import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BASE = "http://127.0.0.1:8080/litellm";

async function fetchModels() {
  try {
    const res = await fetch(`${BASE}/model_group/info`, { signal: AbortSignal.timeout(5000) });
    const { data = [] } = res.ok ? await res.json() : {};
    return data.map((g: any) => ({
      type: "chat" as const,
      id: g.model_group,
      name: g.model_group,
      contextWindow: g.max_input_tokens || 128_000,
      maxTokens: g.max_output_tokens || 16_384,
      reasoning: Boolean(g.supports_reasoning),
      input: g.supports_vision ? ["text", "image"] : ["text"],
      cost: {
        input: (g.input_cost_per_token || 0) * 1e6,
        output: (g.output_cost_per_token || 0) * 1e6,
        cacheRead: 0,
        cacheWrite: 0,
      },
      ...(g.model_group.toLowerCase().includes("deepseek") && {
        compat: { thinkingFormat: "deepseek", supportsReasoningEffort: false },
      }),
    }));
  } catch {
    return [];
  }
}

export default async function (pi: ExtensionAPI) {
  const models = await fetchModels();

  pi.registerProvider("litellm", {
    name: "LiteLLM",
    baseUrl: `${BASE}/v1`,
    apiKey: "placeholder",
    api: "openai-completions",
    models,
    refreshModels: fetchModels,
  });

  pi.registerMcpServer("litellm", { url: `${BASE}/mcp` });
}
