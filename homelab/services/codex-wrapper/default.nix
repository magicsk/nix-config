{
  config,
  lib,
  pkgs,
  ...
}:
let
  service = "codex-wrapper";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  modelCatalogVersion = "gpt-5.5-only-xhigh-stream-v1";
  codexConfig = pkgs.writeText "codex-wrapper-config.toml" ''
    model = "${cfg.model}"
    model_reasoning_effort = "${cfg.reasoning}"
    web_search = "${cfg.webSearch}"
    personality = "${cfg.personality}"
    sandbox_mode = "read-only"
    approval_policy = "never"
  '';
  prepareCodexBridge = pkgs.writeShellScript "prepare-codexbridge" ''
    set -euo pipefail

    source_dir=${lib.escapeShellArg "${cfg.dataDir}/codexbridge"}
    npm_cache=${lib.escapeShellArg "${cfg.dataDir}/npm-cache"}
    marker=${lib.escapeShellArg "${cfg.dataDir}/.codexbridge-prepared"}
    desired_marker=${lib.escapeShellArg "rev=${cfg.sourceRev} sdk=${cfg.codexSdkVersion} model=${cfg.model} catalog=${modelCatalogVersion}"}
    default_model=${lib.escapeShellArg cfg.model}
    as_user=(runuser -u ${lib.escapeShellArg homelab.user} --)

    install -d -m 0750 -o ${homelab.user} -g ${homelab.group} ${cfg.dataDir}
    install -d -m 0750 -o ${homelab.user} -g ${homelab.group} ${cfg.dataDir}/codex
    install -d -m 0750 -o ${homelab.user} -g ${homelab.group} ${cfg.dataDir}/workspace
    install -d -m 0750 -o ${homelab.user} -g ${homelab.group} "$npm_cache"
    install -m 0640 -o ${homelab.user} -g ${homelab.group} ${codexConfig} ${cfg.dataDir}/codex/config.toml

    if [ ! -d "$source_dir/.git" ]; then
      rm -rf "$source_dir"
      "''${as_user[@]}" git clone --filter=blob:none https://github.com/begonia599/CodexBridge "$source_dir"
      rm -f "$marker"
    fi

    if [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$desired_marker" ]; then
      chown -R ${homelab.user}:${homelab.group} "$source_dir" "$npm_cache"

      "''${as_user[@]}" git -C "$source_dir" fetch --depth 1 origin ${lib.escapeShellArg cfg.sourceRev}
      "''${as_user[@]}" git -C "$source_dir" checkout --detach FETCH_HEAD
      "''${as_user[@]}" git -C "$source_dir" reset --hard FETCH_HEAD
      "''${as_user[@]}" git -C "$source_dir" clean -fd

      "''${as_user[@]}" npm --prefix "$source_dir" install --package-lock-only --ignore-scripts --no-audit --no-fund --cache "$npm_cache" @openai/codex-sdk@${lib.escapeShellArg cfg.codexSdkVersion}
      "''${as_user[@]}" npm --prefix "$source_dir" ci --omit=dev --ignore-scripts --no-audit --no-fund --cache "$npm_cache"

      if ! grep -Fq 'app.listen(PORT, "127.0.0.1", () => {' "$source_dir/server.js"; then
        sed -i 's/app.listen(PORT, () => {/app.listen(PORT, "127.0.0.1", () => {/' "$source_dir/server.js"
      fi
      "''${as_user[@]}" node - "$source_dir/server.js" "$default_model" <<'NODE'
    const fs = require("fs");

    const file = process.argv[2];
    const defaultModel = process.argv[3];
    let text = fs.readFileSync(file, "utf8");

    const modelPresets = [
      "const MODEL_PRESETS = [",
      "  {",
      "    id: \"" + defaultModel + "\",",
      "    label: \"GPT-5.5 Codex\",",
      "    description: \"Codex model for coding and agentic development tasks.\",",
      "    reasonings: [",
      "      { level: \"low\", label: \"Low\", description: \"Fastest responses for simple tasks.\" },",
      "      { level: \"medium\", label: \"Medium\", description: \"Balanced depth and speed.\" },",
      "      { level: \"high\", label: \"High\", description: \"Deeper reasoning for complex changes.\" },",
      "      { level: \"xhigh\", label: \"Extra High\", description: \"Maximum reasoning depth when available.\" },",
      "    ],",
      "    defaultReasoning: \"medium\",",
      "  },",
      "];",
    ].join("\n");

    const normalizeReasoning = [
      "function normalizeReasoning(value) {",
      "  if (!value) return null;",
      "  const lowered = String(value).trim().toLowerCase();",
      "  const aliases = {",
      "    \"extra-high\": \"xhigh\",",
      "    extra_high: \"xhigh\",",
      "    extrahigh: \"xhigh\",",
      "    \"x-high\": \"xhigh\",",
      "  };",
      "  const normalized = aliases[lowered] ?? lowered;",
      "  if ([\"low\", \"medium\", \"high\", \"xhigh\"].includes(normalized)) {",
      "    return normalized;",
      "  }",
      "  return null;",
      "}",
    ].join("\n");

    text = text.replace(
      /const MODEL_PRESETS = \[\n[\s\S]*?\n\];\n\nconst codex = new Codex\(\);/,
      modelPresets + "\n\nconst codex = new Codex();",
    );
    text = text.replace(
      /function normalizeReasoning\(value\) \{\n[\s\S]*?\n\}\n\nfunction buildConversationPrompt/,
      normalizeReasoning + "\n\nfunction buildConversationPrompt",
    );
    text = text.replace(
      "  const sendChunk = (payload) => {\n    res.write(`data: ''${JSON.stringify(payload)}\\n\\n`);\n  };\n  const sendDone = () => {\n    res.write(\"data: [DONE]\\n\\n\");\n  };\n",
      [
        "  const flush = () => {",
        "    if (typeof res.flush === \"function\") res.flush();",
        "  };",
        "  const sendChunk = (payload) => {",
        "    res.write(`data: ''${JSON.stringify(payload)}\\n\\n`);",
        "    flush();",
        "  };",
        "  const sendDone = () => {",
        "    res.write(\"data: [DONE]\\n\\n\");",
        "    flush();",
        "  };",
        "  const parsedHeartbeatMs = Number.parseInt(process.env.CODEX_STREAM_HEARTBEAT_MS ?? \"15000\", 10);",
        "  const heartbeatMs = Number.isFinite(parsedHeartbeatMs) ? Math.max(0, parsedHeartbeatMs) : 15000;",
        "  const heartbeat = heartbeatMs > 0",
        "    ? setInterval(() => {",
        "        if (!res.writableEnded) {",
        "          res.write(\": keep-alive\\n\\n\");",
        "          flush();",
        "        }",
        "      }, heartbeatMs)",
        "    : null;",
      ].join("\n") + "\n",
    );
    text = text.replace(
      "  const sendDelta = (delta, finishReason = null, usage = null, extra = {}) => {\n    const chunk = {\n      ...chunkBase,\n      choices: [\n        {\n          index: 0,\n          delta,\n          finish_reason: finishReason,\n        },\n      ],\n      ...extra,\n    };\n    if (usage) chunk.usage = usage;\n    sendChunk(chunk);\n  };\n",
      [
        "  const sendDelta = (delta, finishReason = null, usage = null, extra = {}) => {",
        "    const chunk = {",
        "      ...chunkBase,",
        "      choices: [",
        "        {",
        "          index: 0,",
        "          delta,",
        "          finish_reason: finishReason,",
        "        },",
        "      ],",
        "      ...extra,",
        "    };",
        "    if (usage) chunk.usage = usage;",
        "    sendChunk(chunk);",
        "  };",
        "",
        "  const parsedChunkSize = Number.parseInt(process.env.CODEX_STREAM_CHUNK_SIZE ?? \"48\", 10);",
        "  const streamChunkSize = Number.isFinite(parsedChunkSize) ? Math.max(1, parsedChunkSize) : 48;",
        "  const parsedChunkDelayMs = Number.parseInt(process.env.CODEX_STREAM_CHUNK_DELAY_MS ?? \"8\", 10);",
        "  const streamChunkDelayMs = Number.isFinite(parsedChunkDelayMs) ? Math.max(0, parsedChunkDelayMs) : 8;",
        "  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));",
        "  const streamContentDelta = async (content) => {",
        "    const chars = Array.from(content);",
        "    for (let index = 0; index < chars.length; index += streamChunkSize) {",
        "      sendDelta({ content: chars.slice(index, index + streamChunkSize).join(\"\") });",
        "      if (streamChunkDelayMs > 0 && index + streamChunkSize < chars.length) {",
        "        await sleep(streamChunkDelayMs);",
        "      }",
        "    }",
        "  };",
      ].join("\n") + "\n",
    );
    text = text.replace(
      "          sendDelta({ content: deltaContent });",
      "          await streamContentDelta(deltaContent);",
    );
    text = text.replace(
      "  } finally {\n    await cleanupAttachmentFiles(cleanupTasks);\n  }\n}",
      "  } finally {\n    if (heartbeat) clearInterval(heartbeat);\n    await cleanupAttachmentFiles(cleanupTasks);\n  }\n}",
    );

    fs.writeFileSync(file, text);
    NODE

      echo "$desired_marker" > "$marker"
      chown -R ${homelab.user}:${homelab.group} ${cfg.dataDir}
    fi
  '';
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-5.5";
    };
    reasoning = lib.mkOption {
      type = lib.types.enum [
        "low"
        "medium"
        "high"
        "xhigh"
      ];
      default = "medium";
    };
    webSearch = lib.mkOption {
      type = lib.types.enum [
        "cached"
        "live"
        "disabled"
      ];
      default = "live";
      description = "Codex web search mode written to config.toml.";
    };
    networkAccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow Codex sandboxed commands to use network access where the sandbox mode supports it.";
    };
	    personality = lib.mkOption {
	      type = lib.types.enum [
	        "friendly"
	        "pragmatic"
	      ];
	      default = "pragmatic";
	      description = "Default Codex communication style.";
	    };
    sourceRev = lib.mkOption {
      type = lib.types.str;
      default = "dea9bd729a379882119754a6d50a2c02951b582b";
      description = "Pinned CodexBridge Git revision to install in persistent storage.";
    };
    codexSdkVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.135.0";
      description = "Pinned @openai/codex-sdk version to use with CodexBridge.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.${service} = {
      description = "OpenAI-compatible Codex bridge for Open WebUI";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        PORT = toString cfg.port;
        CODEX_MODEL = cfg.model;
        CODEX_REASONING = cfg.reasoning;
        CODEX_BRIDGE_API_KEY = "";
        CODEX_SKIP_GIT_CHECK = "true";
        CODEX_SANDBOX_MODE = "read-only";
        CODEX_WORKDIR = "${cfg.dataDir}/workspace";
        CODEX_APPROVAL_POLICY = "never";
        CODEX_LOG_REQUESTS = "false";
        CODEX_REQUIRE_SESSION_ID = "false";
        CODEX_STREAM_CHUNK_DELAY_MS = "8";
        CODEX_STREAM_CHUNK_SIZE = "48";
        CODEX_STREAM_HEARTBEAT_MS = "15000";
        CODEX_HOME = "${cfg.dataDir}/codex";
        CODEX_STATE_DIR = "${cfg.dataDir}/codex";
        CODEX_BRIDGE_STATE_FILE = "${cfg.dataDir}/.codex_threads.json";
        HOME = cfg.dataDir;
        NODE_ENV = "production";
      }
      // lib.optionalAttrs cfg.networkAccess {
        CODEX_NETWORK_ACCESS = "true";
      }
      // lib.optionalAttrs (!cfg.networkAccess) {
        CODEX_NETWORK_ACCESS = "false";
      }
      // lib.optionalAttrs (cfg.webSearch == "live") {
        CODEX_WEB_SEARCH = "true";
      }
      // lib.optionalAttrs (cfg.webSearch == "disabled") {
        CODEX_WEB_SEARCH = "false";
      };
      path = [
        pkgs.bubblewrap
        pkgs.codex
        pkgs.git
        pkgs.gnused
        pkgs.nodejs
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "simple";
        User = homelab.user;
        Group = homelab.group;
        ExecStartPre = "+${prepareCodexBridge}";
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${lib.getExe pkgs.nodejs} ${cfg.dataDir}/codexbridge/server.js";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "10min";
      };
    };

    environment.persistence."/" = {
      directories = [
        {
          directory = cfg.dataDir;
          user = homelab.user;
          group = homelab.group;
          mode = "0750";
        }
      ];
    };
  };
}
