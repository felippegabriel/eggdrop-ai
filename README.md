# Soonyo AI - LLM Gateway for Eggdrop IRC Bot

A minimal, production-ready system that lets your Eggdrop IRC bot respond intelligently using OpenRouter's LLM API.

## Architecture

```
IRC User → Eggdrop Bot → Local Gateway (Node/TS) → OpenRouter API
                    ↓
                  IRC Channel (bot replies)
```

**Flow:**
1. User mentions `@soonyo` or `soonyo:` in IRC
2. Eggdrop Tcl script POSTs message to local gateway
3. Gateway forwards to OpenRouter with concise system prompt
4. LLM generates 1-2 sentence reply
5. Gateway returns plain text to Eggdrop
6. Bot prints reply to channel

**Features:**
- Per-user rate limiting (10s cooldown)
- Error handling at every layer
- Free tier model by default (qwen/qwen-2.5-7b-instruct:free)
- Minimal dependencies
- Plain text responses for easy Tcl parsing

---

## Installation

### 1. Gateway Setup

```bash
cd gateway
npm install
cp .env.example .env
```

Edit `.env` and add your OpenRouter API key:
```bash
OPENROUTER_API_KEY=sk-or-v1-...
```

Get your API key from: https://openrouter.ai/keys

### 2. Run the Gateway

**Development (with auto-reload):**
```bash
npm run dev
```

**Production:**
```bash
npm start
```

The gateway listens on `http://127.0.0.1:3042` by default.

**Health check:**
```bash
curl http://127.0.0.1:3042/health
# Should return: OK
```

### 3. Eggdrop Setup

**Requirements:**
- Eggdrop 1.8.0+ with `http` package (standard in modern builds)

**Installation:**
```bash
# Copy the Tcl script to your Eggdrop scripts directory
cp eggdrop/soonyo.tcl /path/to/eggdrop/scripts/

# Add to eggdrop.conf
echo 'source scripts/soonyo.tcl' >> /path/to/eggdrop/eggdrop.conf

# Rehash or restart
# In IRC: .rehash
# Or restart: ./eggdrop -m eggdrop.conf
```

---

## Usage

### In IRC:

```
<user> @soonyo what is TCP?
<bot> Transmission Control Protocol - reliable, ordered data delivery over networks.

<user> soonyo: explain quantum computing
<bot> Computers using quantum mechanics for parallel computation. Still mostly experimental.

<user> @soonyo
<bot> user: yes?
```

### Rate Limiting:

```
<user> @soonyo test
<bot> Sure!
<user> @soonyo another test
<bot> user: please wait 8s
```

---

## Configuration

### Gateway (`gateway/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENROUTER_API_KEY` | _(required)_ | Your OpenRouter API key |
| `PORT` | `3042` | Gateway HTTP port |
| `MODEL` | `qwen/qwen-2.5-7b-instruct:free` | OpenRouter model ID |

**Popular free models:**
- `qwen/qwen-2.5-7b-instruct:free` (default, very fast)
- `meta-llama/llama-3.2-3b-instruct:free`
- `google/gemma-2-9b-it:free`

See all models: https://openrouter.ai/models?order=newest&supported_parameters=tools

### Eggdrop Script (`eggdrop/soonyo.tcl`)

Edit these variables at the top of the script:

```tcl
set soonyo_gateway "http://127.0.0.1:3042/soonyo"
set soonyo_timeout 15000                    ;# 15 seconds
set soonyo_rate_limit 10                    ;# 10 seconds between requests
```

---

## Testing

### Test the gateway directly:

```bash
curl -X POST http://127.0.0.1:3042/soonyo \
  -H "Content-Type: application/json" \
  -d '{"message":"what is IRC?","user":"testuser","channel":"#test"}'
```

Expected response (plain text):
```
Internet Relay Chat - real-time text messaging protocol from 1988.
```

### Test from Eggdrop:

In IRC DCC chat or partyline:
```tcl
.tcl soonyo_query "testuser" "#test" "hello"
```

---

## Troubleshooting

### Bot doesn't respond

1. **Check gateway is running:**
   ```bash
   curl http://127.0.0.1:3042/health
   ```

2. **Check Eggdrop loaded the script:**
   ```
   .tcl info loaded
   # Should list soonyo.tcl
   ```

3. **Check Eggdrop console:**
   ```
   .console +d
   # Watch for error messages
   ```

4. **Test trigger patterns:**
   The bot only responds to:
   - `@soonyo <message>`
   - `soonyo: <message>`
   
   Not: `soonyo <message>` (no colon)

### Gateway errors

**"Gateway not configured":**
- Missing `OPENROUTER_API_KEY` in `.env`

**"LLM service error":**
- Check OpenRouter API status: https://status.openrouter.ai/
- Verify API key is valid
- Check gateway console for error details

**"Empty response from LLM":**
- Try a different model in `.env`
- Check OpenRouter rate limits

### Rate limit issues

Edit `soonyo_rate_limit` in `soonyo.tcl`:
```tcl
set soonyo_rate_limit 5  ;# Reduce to 5 seconds
```

---

## System Prompt

The bot's personality is defined in `gateway/server.ts`:

```typescript
const SYSTEM_PROMPT = `You are Soonyo, an IRC bot assistant. Your core traits:

- Only respond when directly addressed
- Extremely concise: 1-2 sentences maximum
- High signal, zero fluff
- No greetings, no emojis, no verbosity
- Direct answers only
- Skip politeness - just deliver information
- If you don't know, say so in 5 words or less

You're in an IRC channel where bandwidth and attention are precious. Every word counts.`;
```

Edit this to customize the bot's behavior.

---

## Production Deployment

### Using PM2 (recommended):

```bash
npm install -g pm2
cd gateway
pm2 start npm --name soonyo-gateway -- start
pm2 save
pm2 startup  # Auto-start on reboot
```

### Using systemd:

Create `/etc/systemd/system/soonyo-gateway.service`:

```ini
[Unit]
Description=Soonyo LLM Gateway
After=network.target

[Service]
Type=simple
User=eggdrop
WorkingDirectory=/path/to/soonyo-ai/gateway
ExecStart=/usr/bin/npm start
Restart=on-failure
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable soonyo-gateway
sudo systemctl start soonyo-gateway
sudo systemctl status soonyo-gateway
```

### Security considerations:

- Gateway binds to `127.0.0.1` only (localhost)
- No authentication needed - only accessible locally
- Keep `OPENROUTER_API_KEY` secret
- Monitor token usage on OpenRouter dashboard
- Consider setting up firewall rules

---

## Cost Monitoring

Free tier models are rate-limited by OpenRouter. Monitor usage at:
https://openrouter.ai/activity

**Tips for staying in free tier:**
- Use `qwen/qwen-2.5-7b-instruct:free` (default)
- Keep `max_tokens` low (currently 100)
- Rate limiting in Tcl script helps prevent abuse

**Paid models:**
Update `MODEL` in `.env` to any OpenRouter model. Costs typically $0.001-0.01 per request.

---

## Development

### Project structure:

```
soonyo-ai/
├── eggdrop/
│   └── soonyo.tcl          # Eggdrop Tcl script
├── gateway/
│   ├── server.ts           # Express gateway service
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   └── .env                # Your config (gitignored)
└── README.md
```

### Extending the gateway:

The gateway is intentionally minimal. To add features:

1. **Logging:** Add Winston or Pino for structured logs
2. **Metrics:** Add Prometheus endpoint for monitoring
3. **Caching:** Add Redis for response caching
4. **Multiple models:** Route different triggers to different models
5. **Context memory:** Store recent messages per channel

### Testing new models:

```bash
# In gateway/.env
MODEL=anthropic/claude-3-haiku

# Restart gateway
npm start
```

See model list: https://openrouter.ai/models

---

## License

MIT

---

## Support

- OpenRouter Docs: https://openrouter.ai/docs
- Eggdrop Wiki: https://docs.eggheads.org/
- Issues: https://github.com/splinesreticulating/soonyo-ai/issues
