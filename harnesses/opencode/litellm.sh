#!/bin/sh
# Generates OpenCode LiteLLM provider config from the gateway's model catalog.
set -eu

GATEWAY="${GATEWAY:-http://127.0.0.1:8080/litellm}"
CONFIG="$HOME/.config/opencode/opencode.json"

catalog=$(curl -fsS --max-time 10 "$GATEWAY/model_group/info")

provider=$(printf '%s' "$catalog" | jq -c --arg base "$GATEWAY/v1" '
  {
    litellm: {
      name: "LiteLLM",
      env: ["LITELLM_API_KEY"],
      package: "@ai-sdk/openai-compatible",
      settings: { baseURL: $base },
      models: (
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
        | from_entries)
    }
  }')

mcp=$(jq -cn --arg gw "$GATEWAY" '{ litellm: { type: "remote", url: ($gw + "/mcp") } }')

mkdir -p "$(dirname "$CONFIG")"

if [ -f "$CONFIG" ] && jq -e . "$CONFIG" >/dev/null 2>&1; then
	merged=$(jq --argjson p "$provider" --argjson m "$mcp" '
    .providers = ((.providers // {}) + $p)
    | .mcp = ((.mcp // {}) | .servers = ((.servers // {}) + $m))
    | (if .model then . else .model = ("litellm/" + ($p.litellm.models | keys_unsorted[0])) end)
    | (if ."$schema" then . else ."$schema" = "https://opencode.ai/config.json" end)' "$CONFIG")
else
	merged=$(printf '%s' "$provider" | jq --argjson m "$mcp" '
    { "$schema": "https://opencode.ai/config.json",
      model: ("litellm/" + (.litellm.models | keys_unsorted[0])),
      mcp: { servers: $m },
      providers: . }')
fi

tmp=$(mktemp "$CONFIG.XXXXXX")
printf '%s\n' "$merged" >"$tmp"
mv "$tmp" "$CONFIG"

printf 'wrote %s (%s LiteLLM models)\n' \
	"$CONFIG" "$(printf '%s' "$merged" | jq '.providers.litellm.models | length')"
