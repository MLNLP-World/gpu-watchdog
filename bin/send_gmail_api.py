#!/usr/bin/env python3
import base64, os, sys
from email.message import EmailMessage

SCOPES = ["https://www.googleapis.com/auth/gmail.send"]

def req(k: str) -> str:
    v = os.environ.get(k, "")
    if not v:
        raise RuntimeError(f"Missing env {k}")
    return v

def main():
    creds_path = os.environ.get("GMAIL_API_CREDENTIALS", "")
    token_path = os.environ.get("GMAIL_API_TOKEN", "")
    if not creds_path or not os.path.exists(creds_path):
        raise RuntimeError("Missing GMAIL_API_CREDENTIALS (credentials.json).")
    if not token_path:
        raise RuntimeError("Missing GMAIL_API_TOKEN path (token.json).")

    to_email = req("TO_EMAIL")
    subject  = req("SUBJECT")
    body     = req("BODY")
    from_email = os.environ.get("FROM_EMAIL", "")  # optional

    msg = EmailMessage()
    if from_email:
        msg["From"] = from_email
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.set_content(body)

    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode("utf-8")

    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build

    creds = None
    if os.path.exists(token_path):
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(creds_path, SCOPES)
            # first run will open a browser for OAuth
            creds = flow.run_local_server(port=0)
        os.makedirs(os.path.dirname(token_path) or ".", exist_ok=True)
        with open(token_path, "w") as f:
            f.write(creds.to_json())

    service = build("gmail", "v1", credentials=creds)
    service.users().messages().send(userId="me", body={"raw": raw}).execute()

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[send_gmail_api.py ERROR] {e}", file=sys.stderr)
        sys.exit(1)
