# GPU Watchdog 🐩

A tiny GPU usage watcher and email notifier (SMTP or Gmail API), designed for HPC usage.

## What it does

- Watches your GPU usage (polling `nvidia-smi`)
- Sends an email with subject prefix [GPU Watchdog] to `TO_EMAIL` when triggers fire
- Notifier options:
  - Gmail API (recommended when SMTP is blocked; HTTPS 443)
  - SMTP (when available)

---


## Quickstart

```bash
git clone <this-repo>
cd <repo-dir>

# 1) local configs (copy from examples)
cp config/gpu-watch.env.example config/gpu-watch.env
cp config/notify.env.example    config/notify.env   # recommended

# 2) dry run: prints the message payload without sending
bash bin/gpu_watch.sh --dry-run

# 3) test mail: force send
bash bin/gpu_watch.sh --test-mail
```

*Tip: To verify SMTP works on your cluster, run `bash bin/gpu_watch.sh --test-mail` and confirm you actually receive the email.*

---

## Gmail API setup (recommended)

#### 1) Enable Gmail API
In Google Cloud Console (same Project):
- APIs & Services → Library → Gmail API → Enable

#### 2) Create OAuth client (Desktop)
- APIs & Services → Credentials → Create credentials → OAuth client ID
- Application type: Desktop app
- Download the JSON and save as:
  - `secret/credentials.json`

#### 3) Configure OAuth consent and test user
In Google Auth Platform:
- Configure OAuth consent screen (External is fine)
- Add your Gmail address to Test users

#### 4) Generate `secret/token.json` on the cluster
Install deps once (in your env):

```bash
python -m pip install --user google-auth-oauthlib google-api-python-client
```

Run OAuth (on a login node where you can open a browser on your laptop via SSH port forwarding):

```bash
BASE="$(pwd)"
python - <<'PY'
import os
from google_auth_oauthlib.flow import InstalledAppFlow

BASE = os.environ.get("BASE", ".")
creds = f"{BASE}/secret/credentials.json"
token = f"{BASE}/secret/token.json"
scopes = ["https://www.googleapis.com/auth/gmail.send"]

flow = InstalledAppFlow.from_client_secrets_file(creds, scopes=scopes)
creds_obj = flow.run_local_server(
    host="127.0.0.1",
    port=8765,
    open_browser=False,
    authorization_prompt_message="Open this URL in your browser:\n{url}\n",
    success_message="✅ Auth OK. You can close this tab.",
)

with open(token, "w") as f:
    f.write(creds_obj.to_json())
print("Wrote token:", token)
PY
```

If you are using SSH, in a separate terminal on your laptop:

```bash
ssh -L 8765:127.0.0.1:8765 <user>@<cluster-host>
```

Then open the printed URL in your laptop browser, approve, and return to the terminal.

### 5) Fill `config/notify.env`
Edit `config/notify.env`:

```bash
NOTIFY_METHOD="gmail_api"
GMAIL_API_CREDENTIALS="/ABS/PATH/TO/gpu-watch/secret/credentials.json"
GMAIL_API_TOKEN="/ABS/PATH/TO/gpu-watch/secret/token.json"
FROM_EMAIL="your_gmail@gmail.com"
```

Test:

```bash
bash bin/gpu_watch.sh --test-mail
```

---

## SMTP setup (alternative)

Edit `config/notify.env`:

```bash
NOTIFY_METHOD="smtp"
SMTP_HOST="smtp.example.com"
SMTP_PORT="587"
SMTP_USER="..."
SMTP_PASS="..."
FROM_EMAIL="..."
TO_EMAIL="..."
```

Test:

```bash
bash bin/gpu_watch.sh --test-mail
```

---

## Notes

- `config/*.env` are local runtime configs, examples live in `config/*.env.example`.
- `secret/` stores per-user OAuth files on your machine.
- `cache/` is runtime state, including last sent signature, etc.


## Contact

- For bugs or feature requests, please open an Issue.
- For other questions, feel free to reach out: yolandachen0313@gmail.com