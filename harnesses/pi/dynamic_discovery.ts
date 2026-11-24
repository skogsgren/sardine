import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const GATEWAY = "http://127.0.0.1:8080";

async function checkRoute(path: string): Promise<boolean> {
  try {
    const res = await fetch(`${GATEWAY}${path}`, {
      signal: AbortSignal.timeout(3000),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function fetchLiteLLMModels() {
  try {
    const res = await fetch(`${GATEWAY}/litellm/model_group/info`, {
      signal: AbortSignal.timeout(5000),
    });
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
  const [hasLiteLLM, hasOpenAI, hasOpenRouter] = await Promise.all([
    checkRoute("/litellm/model_group/info"),
    checkRoute("/openai/v1/models"),
    checkRoute("/openrouter/v1/auth/key"),
  ]);

  if (hasLiteLLM) {
    const models = await fetchLiteLLMModels();
    pi.registerProvider("litellm", {
      name: "LiteLLM",
      baseUrl: `${GATEWAY}/litellm/v1`,
      apiKey: "placeholder",
      api: "openai-completions",
      models,
      refreshModels: fetchLiteLLMModels,
    });
    pi.registerMcpServer("litellm", { url: `${GATEWAY}/litellm/mcp` });
  }

  if (hasOpenAI) {
    pi.registerProvider("openai", {
      baseUrl: `${GATEWAY}/openai/v1`,
      apiKey: "placeholder",
    });
  }

  if (hasOpenRouter) {
    pi.registerProvider("openrouter", {
      baseUrl: `${GATEWAY}/openrouter/v1`,
      apiKey: "placeholder",
    });
  }
}
