#!/usr/bin/env python3
"""Sends a fake incoming SMS to the local n8n webhook, signed like Twilio signs it, to test without a phone.

Usage: python scripts/simulate-sms.py "Hi, do you take Cigna?" [--from +15550000000] [--bad-signature]

The reply is sent through the Twilio API, so with fake credentials it fails at that last step: read the agent's
answer in the n8n executions or in dental_clinic.chat_history. Standard library only.
"""
import argparse
import base64
import hashlib
import hmac
import pathlib
import secrets
import urllib.error
import urllib.parse
import urllib.request


def read_env(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def twilio_signature(auth_token, url, params):
    # base64(HMAC-SHA1(Auth Token, URL + every parameter name and value, sorted by name))
    signed = url + "".join(key + params[key] for key in sorted(params))
    return base64.b64encode(hmac.new(auth_token.encode(), signed.encode(), hashlib.sha1).digest()).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("text")
    parser.add_argument("--from", dest="sender", default="+15550000000", help="patient's number (fake by default)")
    parser.add_argument("--bad-signature", action="store_true", help="sign with a wrong token: expect 403")
    parser.add_argument("--message-sid", help="reuse a MessageSid to test duplicate deliveries")
    args = parser.parse_args()

    env = read_env(pathlib.Path(__file__).resolve().parent.parent / ".env")
    # Twilio signs the public URL it calls; the request itself goes straight to the local n8n
    public_url = env["N8N_WEBHOOK_URL"].rstrip("/") + "/webhook/twilio/sms"
    local_url = f"http://localhost:{env.get('N8N_HOST_PORT', '5680')}/webhook/twilio/sms"

    params = {
        "AccountSid": env.get("TWILIO_ACCOUNT_SID", ""),
        "MessageSid": args.message_sid or "SM" + secrets.token_hex(16),
        "From": args.sender,
        "To": "+15551230000",
        "Body": args.text,
        "NumMedia": "0",
    }
    token = "wrong-token" if args.bad_signature else env["TWILIO_AUTH_TOKEN"]
    request = urllib.request.Request(
        local_url,
        data=urllib.parse.urlencode(params).encode(),
        headers={"X-Twilio-Signature": twilio_signature(token, public_url, params),
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print(response.status, response.read().decode(), params["MessageSid"])
    except urllib.error.HTTPError as error:
        print(error.code, error.read().decode(), params["MessageSid"])


if __name__ == "__main__":
    main()
