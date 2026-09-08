# GLMAdapter

Run **Together AI models** — **GLM-5.2** (Z.AI's 744B reasoning model, FP8),
**GLM-5.3** (Z.AI's current flagship, 1M context, same price as GLM-5.2),
**GLM-5.3-Flash** (Z.AI's 320B-A18B multimodal reasoning model, 1M context, ~1/10th
GLM-5.2's price), **DeepSeek-V4-Pro-0813** (DeepSeek, 1M context) and **Kimi-K3**
(Moonshot AI, 1M context) — behind one local
[LiteLLM](https://docs.litellm.ai/) proxy, so **any OpenAI-compatible client**
*and* **Claude Code** can use them, with your Together key kept in the OS
secret store and never written to disk. One proxy, one key, N models: clients
pick by model name (`glm-5.2`, `glm-5.3`, `glm-5.3-flash`, `deepseek-v4-pro`, `kimi-k3`).

```
OpenAI clients (codex, aider, scripts) ──► http://localhost:4000/v1  ─┐
                                                                      ├─► LiteLLM ─► Together AI (glm-5.2 · glm-5.3 · glm-5.3-flash · deepseek-v4-pro · kimi-k3)
Claude Code (`glm` / `kimi` commands)  ──► Anthropic-format ─────────┘
```

Battle-tested facts baked into this setup:

| Fact | Value |
|---|---|
| Models | `zai-org/GLM-5.2` (FP8 — best available serverless precision) · `zai-org/GLM-5.3` · `zai-org/GLM-5.3-Flash` · `deepseek-ai/DeepSeek-V4-Pro-0813` (the 0813 build; the un-suffixed `DeepSeek-V4-Pro` is a different 512K listing) · `moonshotai/Kimi-K3` |
| Context / max output | GLM-5.2: 256K / 131,072 tokens · GLM-5.3: 1M context · GLM-5.3-Flash: 1M context · DeepSeek-V4-Pro-0813: 1M context · Kimi-K3: 1M context (Together catalog) |
| Pricing (per 1M) | GLM-5.2: $1.40 in ($0.26 cached) / $4.40 out · GLM-5.3: $1.40 in / $4.40 out · GLM-5.3-Flash: $0.15 in ($0.03 cached) / $0.50 out · DeepSeek-V4-Pro-0813: $1.32 in / $3.96 out · Kimi-K3: $3 in ($0.30 cached) / $15 out (Together catalog, 2026-09-08) |
| Reasoning models | Spend completion tokens on reasoning **before** the answer — small `max_tokens` returns *empty* content. Config defaults: 4096 (GLM-5.2), 16384 (GLM-5.3, GLM-5.3-Flash, DeepSeek-V4-Pro-0813), 32768 (Kimi-K3). GLM-5.3 and GLM-5.3-Flash honour `reasoning_effort: low\|high\|max` (default max; verified to suppress reasoning at `low`) — allowed through via `allowed_openai_params`. DeepSeek-V4-Pro-0813 *accepts* the parameter (HTTP 200) but `low` did not observably suppress reasoning in a one-shot probe — passed through, not relied on. |
| Claude Code compat | Text ✅ and agentic tool-use ✅ through LiteLLM's OpenAI→Anthropic translation (verified on GLM-5.2; note: the same translation *crashes* on DeepInfra FP4 — stick with Together) |
| Anthropic endpoint | Together has **none** (`/v1/messages` → 404). The proxy provides it. |

## Prerequisites

- Python 3.10+ and `pip install 'litellm[proxy]'`
- A [Together AI](https://api.together.ai/) account + API key
- Optional, for the `glm` command: [Claude Code](https://claude.com/claude-code)
  (`npm install -g @anthropic-ai/claude-code`)

## Quickstart

```bash
git clone https://github.com/exquest/GLMAdapter.git && cd GLMAdapter

# 1. Store your Together key in the OS secret store (preferred — never on disk)
#    macOS:
security add-generic-password -U -s TOGETHER_API_KEY -a "$USER" -w 'YOUR_KEY'
#    Linux (libsecret / GNOME Keyring):
echo -n 'YOUR_KEY' | secret-tool store --label='Together AI' service TOGETHER_API_KEY
#    Fallback (headless boxes): cp .env.example .env  # then edit — .env is gitignored

# 2. Start the proxy
./run.sh                      # serves http://localhost:4000  (GLM_PORT=4123 ./run.sh to change)

# 3. Test it
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-anything" -H "Content-Type: application/json" \
  -d '{"model":"glm-5.2","messages":[{"role":"user","content":"hi"}],"max_tokens":512}'
```

Any OpenAI-compatible tool works by pointing its base URL at
`http://localhost:4000/v1` with any bearer token (e.g. `sk-anything`) —
the proxy holds the real key; clients never see it.

## Claude Code on GLM-5.2

Add the helpers to your shell (zsh or bash):

```bash
echo "source $(pwd)/shell/glm.sh" >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
```

Then:

```bash
glm "explain FP8 quantization in two sentences"   # text
glm --allowedTools Bash -p "use Bash to count files here"   # agentic tool-use
glm-health                                        # full stack check, incl. live generation
```

`glm` scopes `ANTHROPIC_BASE_URL`/`ANTHROPIC_API_KEY` to that one invocation —
your normal `claude` keeps using your real account. (Claude Code prints a
one-line "connectors are disabled" warning under `glm`; that's this scoping
working as intended.)

## Always-on service

```bash
./install-service.sh
```

- **macOS** → launchd LaunchAgent `com.glmadapter.litellm` (starts at login,
  self-heals via KeepAlive, logs to `proxy.log`). Runs in your GUI session, so
  it can read the Keychain.
- **Linux** → systemd user unit `glmadapter-litellm` (`Restart=always`,
  logs via `journalctl --user -u glmadapter-litellm`). Uses libsecret if your
  login unlocks the keyring; otherwise use the `.env` fallback.

Re-run the script any time — it re-renders and restarts.

## Rotating the key

Nothing on disk depends on the key's value, so rotation is two commands:

```bash
# macOS
security add-generic-password -U -s TOGETHER_API_KEY -a "$USER" -w 'NEW_KEY'
launchctl kickstart -k gui/$(id -u)/com.glmadapter.litellm

# Linux
echo -n 'NEW_KEY' | secret-tool store --label='Together AI' service TOGETHER_API_KEY
systemctl --user restart glmadapter-litellm
```

## Security notes

- The key lives **only** in the OS secret store (or an untracked `.env` as a
  last resort). It is never inlined in configs, logs, or commits —
  `litellm.config.yaml` uses `os.environ/` indirection and `.gitignore`
  blocks `.env`/`*.log`.
- The proxy sets no `master_key`, so it accepts any bearer **on localhost**.
  Don't expose port 4000 beyond your machine without setting
  `general_settings.master_key` in `litellm.config.yaml`.
- If a key ever leaks, **rotate it at Together** — don't try to scrub git
  history.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Reply has empty `content` | Reasoning model ate the budget — raise `max_tokens` (config default 4096 is safe) |
| `litellm: command not found` under the service | The installer bakes your litellm path into the service; re-run `./install-service.sh` after moving Python envs |
| `TOGETHER_API_KEY not found` | Store the key (see Quickstart step 1); on Linux, `secret-tool` needs an unlocked keyring |
| Port 4000 busy | `GLM_PORT=4123 ./run.sh` and `export GLM_PORT=4123` before using `glm`/`glm-health` |
| Claude Code errors mid-tool-use | Make sure the model is Together (`together_ai/…`) — DeepInfra FP4 breaks the OpenAI→Anthropic translation |

## License

[MIT](LICENSE)
