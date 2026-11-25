#!/bin/sh
# Generates OpenCode provider config from the gateway's model catalogs.
set -eu

GATEWAY="${GATEWAY:-http://127.0.0.1:8080}"
GATEWAY="${GATEWAY%/litellm}"
GATEWAY="${GATEWAY%/}"
CONFIG="${CONFIG:-$HOME/.config/opencode/opencode.json}"

has_litellm=0
litellm_p="{}"
litellm_m="{}"
if [ "${SARDINE_LITELLM_ENABLED:-}" = "1" ] && curl -fsS -o /dev/null --max-time 3 "$GATEWAY/litellm/model_group/info" 2>/dev/null; then
  catalog=$(curl -fsS --max-time 5 "$GATEWAY/litellm/model_group/info" 2>/dev/null || echo '{"data":[]}')
  models=$(printf '%s' "$catalog" | jq -c '
    [.data[]
      | select((.mode // "chat") == "chat")
      | select(.model_group != null)]
    | unique_by(.model_group)
    | map({
        key: .model_group,
        value: ({
          name: .model_group,
          capabilities: ({
            tools: (.supports_function_calling // false),
            input: (["text"] + (if .supports_vision then ["image"] else [] end)),
            reasoning: (
              if .supports_reasoning then
                ({ supported: true }
                 + (if (.supported_reasoning_efforts // []) | length > 0
                    then { effort: .supported_reasoning_efforts }
                    else {} end))
              else { supported: false } end)
          })
        }
        + (if (.max_input_tokens // 0) > 0 and (.max_output_tokens // 0) > 0
           then { limit: {
                    context: (.max_input_tokens | floor),
                    output: (.max_output_tokens | floor) } }
           else {} end))
      })
    | from_entries')
  if [ "$(printf '%s' "$models" | jq 'length')" -gt 0 ]; then
    has_litellm=1
    litellm_p=$(jq -cn --arg base "$GATEWAY/litellm/v1" --argjson m "$models" '
      {
        name: "LiteLLM",
        env: ["LITELLM_API_KEY"],
        package: "@ai-sdk/openai-compatible",
        options: { baseURL: $base, apiKey: "placeholder" },
        models: $m
      }')
    litellm_m=$(jq -cn --arg gw "$GATEWAY" '{ type: "remote", url: ($gw + "/litellm/mcp") }')
  fi
fi

has_openai=0
openai_p="{}"
if [ "${SARDINE_OPENAI_ENABLED:-}" = "1" ] && curl -fsS -o /dev/null --max-time 3 "$GATEWAY/openai/v1/models" 2>/dev/null; then
  catalog=$(curl -fsS --max-time 5 "$GATEWAY/openai/v1/models" 2>/dev/null || echo '{"data":[]}')
  models=$(printf '%s' "$catalog" | jq -c '
    [.data[]
      | select(.id != null)
      | select(.id | test("^(gpt|o[0-9]|chat)"))]
    | unique_by(.id)
    | map({
        key: .id,
        value: {
          name: .id,
          capabilities: {
            tools: true,
            input: (if (.id | test("audio|transcribe|whisper")) then ["text"] else ["text", "image"] end),
            reasoning: {
              supported: (.id | test("^(o[0-9]|gpt-5)"))
            }
          }
        }
      })
    | from_entries')
  if [ "$(printf '%s' "$models" | jq 'length')" -gt 0 ]; then
    has_openai=1
    openai_p=$(jq -cn --arg base "$GATEWAY/openai/v1" --argjson m "$models" '
      {
        name: "OpenAI",
        env: ["OPENAI_API_KEY"],
        package: "@ai-sdk/openai-compatible",
        options: { baseURL: $base, apiKey: "placeholder" },
        models: $m
      }')
  fi
fi

has_openrouter=0
openrouter_p="{}"
if [ "${SARDINE_OPENROUTER_ENABLED:-}" = "1" ] && curl -fsS -o /dev/null --max-time 3 "$GATEWAY/openrouter/v1/auth/key" 2>/dev/null; then
  catalog=$(curl -fsS --max-time 5 "$GATEWAY/openrouter/v1/models" 2>/dev/null || echo '{"data":[]}')
  models=$(printf '%s' "$catalog" | jq -c '
    [.data[]
      | select(.id != null)]
    | unique_by(.id)
    | map({
        key: .id,
        value: ({
          name: (.name // .id),
          capabilities: {
            tools: true,
            input: ["text", "image"]
          }
        }
        + (if (.context_length // 0) > 0 then { limit: { context: .context_length } } else {} end))
      })
    | from_entries')
  if [ "$(printf '%s' "$models" | jq 'length')" -gt 0 ]; then
    has_openrouter=1
    openrouter_p=$(jq -cn --arg base "$GATEWAY/openrouter/v1" --argjson m "$models" '
      {
        name: "OpenRouter",
        env: ["OPENROUTER_API_KEY"],
        package: "@ai-sdk/openai-compatible",
        options: { baseURL: $base, apiKey: "placeholder" },
        models: $m
      }')
  fi
fi

mkdir -p "$(dirname "$CONFIG")"

base_config="{}"
if [ -f "$CONFIG" ] && jq -e . "$CONFIG" >/dev/null 2>&1; then
  base_config=$(cat "$CONFIG")
fi

merged=$(printf '%s' "$base_config" | jq \
  --argjson has_litellm "$has_litellm" \
  --argjson litellm_p "$litellm_p" \
  --argjson litellm_m "$litellm_m" \
  --argjson has_openai "$has_openai" \
  --argjson openai_p "$openai_p" \
  --argjson has_openrouter "$has_openrouter" \
  --argjson openrouter_p "$openrouter_p" '
  .providers = (.providers // {})
  | .mcp = (.mcp // {})
  | .mcp.servers = (.mcp.servers // {})
  | (if $has_litellm == 1 then .providers.litellm = $litellm_p | .mcp.servers.litellm = $litellm_m else del(.providers.litellm) | del(.mcp.servers.litellm) end)
  | (if $has_openai == 1 then .providers.openai = $openai_p else del(.providers.openai) end)
  | (if $has_openrouter == 1 then .providers.openrouter = $openrouter_p else del(.providers.openrouter) end)
  | (if (.mcp.servers | length) == 0 then del(.mcp.servers) else . end)
  | (if (.mcp | length) == 0 then del(.mcp) else . end)
  | . as $root
  | ($root.providers | keys) as $active_providers
  | (if $root.model and (($active_providers | index(($root.model | split("/")[0]))) != null) then . else
       (if ($active_providers | length) > 0 then
          ($active_providers[0]) as $p |
          .model = ($p + "/" + (.providers[$p].models | keys_unsorted[0]))
        else
          del(.model)
        end)
     end)
  | (if ."$schema" then . else ."$schema" = "https://opencode.ai/config.json" end)')

tmp=$(mktemp "$CONFIG.XXXXXX")
printf '%s\n' "$merged" >"$tmp"
mv "$tmp" "$CONFIG"

summary=""
[ "$has_litellm" = "1" ] && summary="${summary} LiteLLM"
[ "$has_openai" = "1" ] && summary="${summary} OpenAI"
[ "$has_openrouter" = "1" ] && summary="${summary} OpenRouter"
summary="${summary# }"
if [ -n "$summary" ]; then
  printf 'wrote %s (enabled: %s)\n' "$CONFIG" "$summary"
else
  printf 'wrote %s (no providers enabled)\n' "$CONFIG"
fi
