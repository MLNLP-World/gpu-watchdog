#!/usr/bin/env python3
import os, socket, smtplib, sys
from email.message import EmailMessage

def req(k: str) -> str:
    v = os.environ.get(k, "")
    if not v:
        raise RuntimeError(f"Missing env {k}")
    return v

def pick_ipv4(host: str) -> str:
    infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    if not infos:
        raise RuntimeError(f"No IPv4 A record for {host}")
    return infos[0][4][0]  # first IPv4

def main():
    host = req("SMTP_HOST")
    port = int(os.environ.get("SMTP_PORT", "587"))
    user = req("SMTP_USER")
    pw = req("SMTP_PASS").replace(" ", "")
    from_email = os.environ.get("FROM_EMAIL", user) or user
    to_email = req("TO_EMAIL")
    subject = req("SUBJECT")
    body = req("BODY")

    ip = pick_ipv4(host)

    msg = EmailMessage()
    msg["From"] = from_email
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.set_content(body)

    # Connect via IPv4 IP (avoid bad route/AAAA); STARTTLS on 587
    if port == 465:
        server = smtplib.SMTP_SSL(ip, port, timeout=25)
    else:
        server = smtplib.SMTP(ip, port, timeout=25)
        server.ehlo(host)
        server.starttls()
        server.ehlo(host)

    server.login(user, pw)
    server.send_message(msg)
    server.quit()

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[send_smtp.py ERROR] {e}", file=sys.stderr)
        sys.exit(1)
