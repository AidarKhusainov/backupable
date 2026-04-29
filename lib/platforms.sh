generate_password() {
    clear
    print "[PASSWORD PROTECTION]\n"
    print "You can set a password for the archive. The password must contain both letters and numbers, and be at least 8 characters long.\n"
    print "If you don't want a password, just press Enter.\n"

    COMPRESS="zip -9 -r"
    while true; do
        input "Enter the password for the archive (or press Enter to skip): " PASSWORD

        # If password is empty, skip password protection
        if [ -z "$PASSWORD" ]; then
            success "No password will be set for the archive."
            COMPRESS="zip -9 -r -s ${LIMITSIZE}m"
            break
        fi

        # Validate password
        if [[ ! "$PASSWORD" =~ ^[a-zA-Z0-9]{8,}$ ]]; then
            wrong "Password must be at least 8 characters long and contain only letters and numbers. Please try again."
            continue
        fi

        input "Confirm the password: " CONFIRM_PASSWORD

        if [ "$PASSWORD" == "$CONFIRM_PASSWORD" ]; then
            success "Password confirmed."
            COMPRESS="$COMPRESS -e -P $PASSWORD -s ${LIMITSIZE}m"
            break
        else
            wrong "Passwords do not match. Please try again."
        fi
    done
}

generate_platform() {
    clear
    print "[PLATFORM]\n"
    print "Select one platform to send your backup.\n"
    print "1) Telegram"
    print "2) Discord"
    print "3) Gmail"
    print ""

    while true; do
        input "Enter your choice : " choice

        case $choice in
            1)
                PLATFORM="telegram"
                telegram_progress
                break
                ;;
            2)
                PLATFORM="discord"
                discord_progress
                break
                ;;
            3)
                PLATFORM="gmail"
                gmail_progress
                break
                ;;
            *)
                wrong "Invalid option, Please select with number."
                ;;
        esac
    done
    sleep 1
}

telegram_progress() {
    clear
    print "[TELEGRAM]\n"
    print "To use Telegram, you need to provide a bot token and a chat ID.\n"

    while true; do
        # Get bot token
        while true; do
            input "Enter the bot token: " BOT_TOKEN
            if [[ -z "$BOT_TOKEN" ]]; then
                wrong "Bot token cannot be empty!"
            elif [[ ! "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]{35}$ ]]; then
                wrong "Invalid bot token format!"
            else
                break
            fi
        done

        # Get chat ID
        while true; do
            input "Enter the chat ID: " CHAT_ID
            if [[ -z "$CHAT_ID" ]]; then
                wrong "Chat ID cannot be empty!"
            elif [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
                wrong "Invalid chat ID format!"
            else
                break
            fi
        done

        while true; do
            input "Enter the topic ID (Press Enter to skip): " TOPIC_ID
            if [[ -z "$TOPIC_ID" ]]; then
                success "No topic ID provided. Messages will be sent to the main chat."
                TOPIC_ID=""
                break
            elif [[ ! "$TOPIC_ID" =~ ^[0-9]+$ ]]; then
                wrong "Invalid topic ID format! Must be a number."
            else
                success "Topic ID set: $TOPIC_ID"
                break
            fi
        done

        # Validate bot token and chat ID
        log "Checking Telegram bot..."
        if [[ -n "$TOPIC_ID" ]]; then
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d message_thread_id="$TOPIC_ID" -d text="Hi, Backupable Test Message!")
        else
            response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="Hi, Backupable Test Message!")
        fi

        if [[ "$response" -ne 200 ]]; then
            wrong "Invalid bot token, chat ID, topic ID, or Telegram API error! [tip: start bot]"
        else
            success "Bot token and chat ID are valid."
            break
        fi
    done

    # Set the platform command for sending files
    if [[ -n "$TOPIC_ID" ]]; then
        PLATFORM_COMMAND="curl -s -F \"chat_id=$CHAT_ID\" -F \"message_thread_id=$TOPIC_ID\" -F \"document=@\$FILE\" -F \"caption=\$CAPTION\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$BOT_TOKEN/sendDocument\""
    else
        PLATFORM_COMMAND="curl -s -F \"chat_id=$CHAT_ID\" -F \"document=@\$FILE\" -F \"caption=\$CAPTION\" -F \"parse_mode=HTML\" \"https://api.telegram.org/bot$BOT_TOKEN/sendDocument\""
    fi

    CAPTION="
📦 <b>From </b><code>\${ip}</code>
<b>➖➖➖➖Sponsor➖➖➖➖</b>
<a href='${SPONSORLINK}'>${SPONSORTEXT}</a>"
    success "Telegram configuration completed successfully."
    LIMITSIZE=49
    sleep 1
}

discord_progress() {
    clear
    print "[DISCORD]\n"
    print "To use Discord, you need to provide a Webhook URL.\n"

    while true; do
        # Get Discord Webhook URL
        while true; do
            input "Enter the Discord Webhook URL: " DISCORD_WEBHOOK
            if [[ -z "$DISCORD_WEBHOOK" ]]; then
                wrong "Webhook URL cannot be empty!"
            elif [[ ! "$DISCORD_WEBHOOK" =~ ^https://discord\.com/api/webhooks/ ]]; then
                wrong "Invalid Discord Webhook URL format!"
            else
                break
            fi
        done
        # Validate Webhook
        log "Checking Discord Webhook..."
        response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$DISCORD_WEBHOOK" -H "Content-Type: application/json" -d '{"content": "Hi, Backupable Test Message!"}')

        if [[ "$response" -ne 204 ]]; then
            wrong "Invalid Webhook URL or Discord API error!"
        else
            success "Webhook URL is valid."
            break
        fi
    done

    # Set the platform command for sending files
    PLATFORM_COMMAND="curl -s -F \"file=@\$FILE\" -F \"payload_json={\\\"content\\\": \\\"\$CAPTION\\\"}\" \"$DISCORD_WEBHOOK\""
    CAPTION="📦 **From** \`${ip}\`\n➖➖➖➖**Sponsor**➖➖➖➖\n[${SPONSORTEXT}](${SPONSORLINK})"
    LIMITSIZE=24
    success "Discord configuration completed successfully."
    sleep 1
}


gmail_progress() {
    clear
    print "[GMAIL]\n"
    print "To use Gmail, you need to provide your email and an app password.\n"
    print "🔴 Do NOT use your real password! Generate an 'App Password' from Google settings.\n"

    while true; do
        while true; do
            input "Enter your Gmail address: " GMAIL_ADDRESS
            if [[ -z "$GMAIL_ADDRESS" ]]; then
                wrong "Email cannot be empty!"
            elif [[ ! "$GMAIL_ADDRESS" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                wrong "Invalid email format!"
            else
                break
            fi
        done

        while true; do
            input "Enter your Gmail app password: " GMAIL_PASSWORD
            if [[ -z "$GMAIL_PASSWORD" ]]; then
                wrong "Password cannot be empty!"
            else
                break
            fi
        done

        log "Testing Gmail SMTP authentication..."

        echo -e "Subject: Test Email\n\nThis is a test message." | msmtp \
            --host=smtp.gmail.com \
            --port=587 \
            --tls=on \
            --auth=on \
            --user="$GMAIL_ADDRESS" \
            --passwordeval="echo '$GMAIL_PASSWORD'" \
            -f "$GMAIL_ADDRESS" \
            "$GMAIL_ADDRESS"

        if [[ $? -eq 0 ]]; then
            success "Authentication successful! Configuring msmtp and mutt..."

            cat > ~/.msmtprc <<EOF
account gmail
host smtp.gmail.com
port 587
auth on
tls on
tls_starttls on
user $GMAIL_ADDRESS
password $GMAIL_PASSWORD
from $GMAIL_ADDRESS
logfile ~/.msmtp.log
account default : gmail
EOF

            chmod 600 ~/.msmtprc

            cat > ~/.muttrc <<EOF
set sendmail="/usr/bin/msmtp"
set use_from=yes
set realname="Backup System"
set from="$GMAIL_ADDRESS"
set envelope_from=yes
EOF

            chmod 600 ~/.muttrc
            CAPTION="<html><body><p><b>📦 From </b><code>\${ip}</code></p><p><b>➖➖➖➖Sponsor➖➖➖➖</b></p><p><a href='${SPONSORLINK}'>${SPONSORTEXT}</a></p></body></html>"
            PLATFORM_COMMAND="echo \$CAPTION | mutt -e 'set content_type=text/html' -s 'Backupable' -a \"\$FILE\" -- \"$GMAIL_ADDRESS\""
            LIMITSIZE=24
            break
        else
            wrong "Authentication failed! Check your email or app password and try again."
            sleep 3
            clear
        fi
    done

    sleep 1
}
