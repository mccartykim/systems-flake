# Email Digest Agent
#
# Twice-daily email summary DM'd to Kimb on Discord.
# Syncs mail via mbsync (pull-only), summarizes with Claude (sonnet),
# sends via Discord bot API.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDir = "/var/lib/email-digest";
  mailDir = "${stateDir}/Mail";
  orgNotesDir = "/home/kimb/shared_projects/org_crm/notes";
  discordUserId = "366455267673636866";

  mbsyncrc = pkgs.writeText "email-digest-mbsyncrc" ''
    # ========================================
    # Zoho Account Configuration
    # ========================================

    IMAPAccount zoho
    Host imap.zoho.com
    Port 993
    User mccartykim@zoho.com
    PassCmd "cat ${config.age.secrets.mail-zoho-password.path}"
    TLSType IMAPS
    CertificateFile /etc/ssl/certs/ca-certificates.crt
    AuthMechs LOGIN
    PipelineDepth 50

    IMAPStore zoho-remote
    Account zoho

    MaildirStore zoho-local
    Path ${mailDir}/zoho/
    Inbox ${mailDir}/zoho/INBOX
    SubFolders Verbatim

    Channel zoho
    Far :zoho-remote:
    Near :zoho-local:
    Patterns *
    Create Near
    SyncState *
    Sync Pull

    # ========================================
    # Gmail Account Configuration
    # ========================================

    IMAPAccount gmail
    Host imap.gmail.com
    Port 993
    User mccarty.tim@gmail.com
    PassCmd "cat ${config.age.secrets.mail-gmail-password.path}"
    TLSType IMAPS
    CertificateFile /etc/ssl/certs/ca-certificates.crt
    AuthMechs LOGIN
    PipelineDepth 50

    IMAPStore gmail-remote
    Account gmail

    MaildirStore gmail-local
    Path ${mailDir}/gmail/
    Inbox ${mailDir}/gmail/INBOX
    SubFolders Verbatim

    Channel gmail
    Far :gmail-remote:
    Near :gmail-local:
    Patterns "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/Starred"
    Create Near
    SyncState *
    Sync Pull

    # ========================================
    # Fastmail Account Configuration
    # ========================================

    IMAPAccount fastmail
    Host imap.fastmail.com
    Port 993
    User kimb@kimb.dev
    PassCmd "cat ${config.age.secrets.mail-fastmail-password.path}"
    TLSType IMAPS
    CertificateFile /etc/ssl/certs/ca-certificates.crt
    AuthMechs LOGIN
    PipelineDepth 50

    IMAPStore fastmail-remote
    Account fastmail

    MaildirStore fastmail-local
    Path ${mailDir}/fastmail/
    Inbox ${mailDir}/fastmail/INBOX
    SubFolders Verbatim

    Channel fastmail
    Far :fastmail-remote:
    Near :fastmail-local:
    Patterns *
    Create Near
    SyncState *
    Sync Pull
  '';

  systemPrompt = pkgs.writeText "email-digest-system-prompt" ''
    You are Kimb's email digest assistant. Summarize new emails into a Discord DM.

    ## Output format
    - Discord markdown: **bold**, *italic*, `code`, > quotes
    - Group by importance, then by account (Zoho/Gmail/Fastmail)
    - Each notable email: sender, subject, 1-2 sentence summary
    - Flag urgent or time-sensitive items (DOL, medical, legal, bills) with a warning
    - Skip spam, marketing, automated notifications unless actionable
    - Keep total output under 5000 characters

    ## Context
    - mccartykim@zoho.com = primary personal email
    - mccarty.tim@gmail.com = legacy Gmail
    - kimb@kimb.dev = professional/domain email
    - You may Read files from ${orgNotesDir} for sender context
    - Do NOT suggest replying, forwarding, or acting on emails
  '';

  digestScript = pkgs.writeShellScript "email-digest" ''
        set -euo pipefail

        export PATH="${lib.makeBinPath [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.jq
      pkgs.curl
      pkgs.isync
      pkgs.mu
      pkgs.findutils
      pkgs.claude-code
    ]}:$PATH"

        MBSYNCRC="${mbsyncrc}"
        STATE_DIR="${stateDir}"
        MAIL_DIR="${mailDir}"
        DISCORD_TOKEN_FILE="${config.age.secrets.discord-email-digest-token.path}"
        DISCORD_USER_ID="${discordUserId}"
        ORG_NOTES_DIR="${orgNotesDir}"

        # Read last-run timestamp; default to 24 hours ago
        LAST_RUN_FILE="$STATE_DIR/last-run"
        NOW=$(date +%s)
        if [ -f "$LAST_RUN_FILE" ]; then
          LAST_RUN=$(cat "$LAST_RUN_FILE")
        else
          LAST_RUN=$((NOW - 86400))
        fi

        # Format date for mu query
        SINCE_DATE=$(date -d "@$LAST_RUN" +%Y%m%d)

        # Ensure Maildir structure exists for mbsync
        for acct in zoho gmail fastmail; do
          mkdir -p "$MAIL_DIR/$acct/INBOX/cur" "$MAIL_DIR/$acct/INBOX/new" "$MAIL_DIR/$acct/INBOX/tmp"
        done

        # Clean stale lock files from interrupted runs
        find "$MAIL_DIR" -name '.lock' -delete 2>/dev/null || true

        # Sync mail (continue on failure for each account)
        for account in zoho gmail fastmail; do
          mbsync -c "$MBSYNCRC" "$account" 2>&1 || echo "WARNING: $account sync failed" >&2
        done

        # Index mail (only init if database doesn't exist)
        if [ ! -d "$HOME/.cache/mu/xapian" ]; then
          mu init --maildir="$MAIL_DIR" --my-address=mccartykim@zoho.com --my-address=mccarty.tim@gmail.com --my-address=kimb@kimb.dev 2>&1
        fi
        mu index 2>&1

        # Find new messages
        MESSAGES=$(mu find "date:$SINCE_DATE.." --fields='d f s l' --sortfield=date 2>/dev/null || true)

        # Read Discord token
        DISCORD_TOKEN=$(cat "$DISCORD_TOKEN_FILE")

        # Helper: send Discord DM
        send_discord_dm() {
          local content="$1"

          # Create/get DM channel
          local channel_id
          channel_id=$(curl -sf \
            -X POST \
            -H "Authorization: Bot $DISCORD_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"recipient_id\":\"$DISCORD_USER_ID\"}" \
            "https://discord.com/api/v10/users/@me/channels" | jq -r '.id')

          if [ -z "$channel_id" ] || [ "$channel_id" = "null" ]; then
            echo "ERROR: Failed to create DM channel" >&2
            return 1
          fi

          # Split content at ~1990 char newline boundaries and send chunks
          local chunk=""
          while IFS= read -r line; do
            if [ $(( ''${#chunk} + ''${#line} + 1 )) -gt 1990 ]; then
              curl -sf \
                -X POST \
                -H "Authorization: Bot $DISCORD_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg c "$chunk" '{content: $c}')" \
                "https://discord.com/api/v10/channels/$channel_id/messages" > /dev/null
              chunk=""
            fi
            if [ -n "$chunk" ]; then
              chunk="$chunk"$'\n'"$line"
            else
              chunk="$line"
            fi
          done <<< "$content"

          # Send remaining chunk
          if [ -n "$chunk" ]; then
            curl -sf \
              -X POST \
              -H "Authorization: Bot $DISCORD_TOKEN" \
              -H "Content-Type: application/json" \
              -d "$(jq -n --arg c "$chunk" '{content: $c}')" \
              "https://discord.com/api/v10/channels/$channel_id/messages" > /dev/null
          fi
        }

        # If no new messages, send brief notification
        if [ -z "$MESSAGES" ]; then
          LAST_RUN_PRETTY=$(date -d "@$LAST_RUN" '+%b %d %H:%M')
          send_discord_dm "No new mail since $LAST_RUN_PRETTY"
          echo "$NOW" > "$LAST_RUN_FILE"
          exit 0
        fi

        # Build email content for Claude
        EMAIL_CONTENT=""
        TOTAL_SIZE=0
        MAX_SIZE=80000

        while IFS= read -r line; do
          # Extract file path (last field)
          MSG_PATH=$(echo "$line" | awk '{print $NF}')
          if [ -f "$MSG_PATH" ]; then
            MSG_BODY=$(mu view "$MSG_PATH" 2>/dev/null || echo "[could not read message]")
            ENTRY="---
    $line

    $MSG_BODY
    "
            ENTRY_SIZE=''${#ENTRY}
            if [ $((TOTAL_SIZE + ENTRY_SIZE)) -gt $MAX_SIZE ]; then
              EMAIL_CONTENT="$EMAIL_CONTENT
    ---
    [Remaining messages truncated due to size limits]"
              break
            fi
            EMAIL_CONTENT="$EMAIL_CONTENT$ENTRY"
            TOTAL_SIZE=$((TOTAL_SIZE + ENTRY_SIZE))
          fi
        done <<< "$MESSAGES"

        # Build user prompt
        CURRENT_DATE=$(date '+%A, %B %d, %Y')
        USER_PROMPT="Current date: $CURRENT_DATE

    Here are the new emails since $(date -d "@$LAST_RUN" '+%b %d %H:%M'):

    $EMAIL_CONTENT"

        # Invoke Claude for summary
        SUMMARY=""
        if command -v claude >/dev/null 2>&1; then
          SUMMARY=$(echo "$USER_PROMPT" | claude -p \
            --system-prompt "$(cat ${systemPrompt})" \
            --model sonnet \
            --max-turns 1 \
            --allowedTools Read \
            --no-session-persistence \
            --output-format text 2>/dev/null || true)
        fi

        # Fallback: raw subject lines if Claude fails
        if [ -z "$SUMMARY" ]; then
          SUBJECT_LINES=$(mu find "date:$SINCE_DATE.." --fields='d f s' --sortfield=date 2>/dev/null || true)
          SUMMARY="**Email Digest** (Claude unavailable, raw subjects):
    \`\`\`
    $SUBJECT_LINES
    \`\`\`"
        fi

        # Send to Discord
        send_discord_dm "$SUMMARY"

        # Write last-run timestamp
        echo "$NOW" > "$LAST_RUN_FILE"
  '';
in {
  # User and group
  users.users.email-digest = {
    isSystemUser = true;
    group = "email-digest";
    home = stateDir;
  };
  users.groups.email-digest = {};

  # Agenix secrets
  age.secrets.mail-zoho-password = {
    file = ../../secrets/mail-zoho-password.age;
    owner = "email-digest";
    mode = "0400";
  };
  age.secrets.mail-gmail-password = {
    file = ../../secrets/mail-gmail-password.age;
    owner = "email-digest";
    mode = "0400";
  };
  age.secrets.mail-fastmail-password = {
    file = ../../secrets/mail-fastmail-password.age;
    owner = "email-digest";
    mode = "0400";
  };
  age.secrets.discord-email-digest-token = {
    file = ../../secrets/discord-life-coach-token.age;
    owner = "email-digest";
    mode = "0400";
  };

  # State directory
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 email-digest email-digest -"
    "d ${mailDir} 0750 email-digest email-digest -"
  ];

  # Oneshot service
  systemd.services.email-digest = {
    description = "Email Digest Agent";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = ["/run/current-system/sw"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${digestScript}";
      User = "email-digest";
      Group = "email-digest";
      TimeoutStartSec = "30min";
      ProtectHome = "read-only";
      ProtectSystem = "strict";
      ReadWritePaths = [stateDir];
      PrivateTmp = true;
      NoNewPrivileges = true;
      StateDirectory = "email-digest";
    };
  };

  # Timer: 8am and 9pm Eastern
  systemd.timers.email-digest = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = [
        "*-*-* 08:00:00 America/New_York"
        "*-*-* 21:00:00 America/New_York"
      ];
      Persistent = true;
    };
  };
}
