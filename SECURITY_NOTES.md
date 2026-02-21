# Security Notes

This repository contains shell-heavy automation for rendering and optional delivery workflows.
Use these rules for local development, CI, and PR reviews.

## Reviewer Checklist (Quick)

- IDs are numeric-validated before any path construction or render/fetch execution.
- All `rm -rf` calls run through `safe_rm_dir`, which refuses empty paths and `/`.
- SMTP password flow uses short-lived file handoff (`SMTP_PASS_FILE`) with cleanup trap; no secret logging.

## 1) Secrets and Credentials

- Never commit real secrets (`SMTP_PASS`, API keys, private keys, tokens).
- Keep local credentials in ignored local files only (`.mail.env`, `.fax.env`, `.watch.env`, `.env`).
- Prefer macOS Keychain for SMTP credentials (`security` CLI, `USE_MACOS_KEYCHAIN=1`).
- If a script must pass a secret to a subprocess, prefer short-lived secret temp files (`mktemp` + `chmod 600` + `trap` cleanup) over plain CLI args or broad logs.

## 2) Logging Rules

- Never print secrets to stdout/stderr/log files.
- Mask recipients/identifiers in logs where possible (e.g. `ab***@domain.tld`).
- Keep watcher logs under controlled paths (`.tmp/watch_runs`, `watch_input_frames.log`).
- Treat generated dry-run fax/mail files as sensitive local artifacts.

## 3) Input Validation

- Vehicle IDs must be numeric only (`^[0-9]+$`).
- User-provided URLs must use `http://` or `https://`.
- Reject unsafe/ambiguous target paths (`..`, absolute override where not intended).
- Always quote variables in shell commands and path operations.

## 4) Temporary Files and Cleanup

- Use `mktemp` for temporary files.
- Register cleanup with `trap ... EXIT` and remove temp files on normal and error exits.
- For secret temp files: enforce restrictive permissions (`chmod 600`).
- Avoid predictable temp filenames for sensitive data.

## 5) Destructive Operations

- Protect `rm -rf` calls with guardrails:
  - never allow empty path or `/`
  - only allow deletes inside approved temp roots (`.tmp`)
- Avoid broad process kills; validate PID format before `kill`.

## 6) Dependency and Runtime Checks

- Validate required commands before execution (`ffmpeg`, `ffprobe`, `python3`).
- Provide actionable install hints (Homebrew command when available).
- Warn clearly when optional tools are missing (`qrencode`, `say`, printer tools).

## 7) Git Hygiene

- Ensure `.gitignore` covers local env files, temp files, logs, and metadata outputs.
- Do not check in generated runtime state (`.tmp`, local IDs, credential files).
- Review diffs for accidental credential leaks before commit/push.

## 8) SMTP and Keychain Handling

- Use app passwords where required by provider policy.
- Prefer Keychain retrieval over plaintext env values.
- If testing with temporary password input, do not persist password in project files.
- Keep SMTP sender/recipient values configurable and validated.
