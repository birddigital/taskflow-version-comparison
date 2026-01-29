#!/bin/bash
# TaskFlow Client Connection Script
# This script connects local machines to the GCP TaskFlow instance

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Configuration
TASKFLOW_SERVER_HOST=""  # Set to your domain or IP (e.g., "taskflow.example.com" or "34.123.45.67")
TASKFLOW_SERVER_PORT="8081"

# Check if host is set
if [ -z "$TASKFLOW_SERVER_HOST" ]; then
    log_warn "Please edit this script and set TASKFLOW_SERVER_HOST to your domain or IP"
    exit 1
fi

# Update TaskFlow client config
log_info "Configuring TaskFlow client to connect to $TASKFLOW_SERVER_HOST..."

# Create or update client config
mkdir -p ~/.taskflow
cat > ~/.taskflow/client-config.yaml <<EOF
server:
  url: "http://$TASKFLOW_SERVER_HOST:$TASKFLOW_SERVER_PORT"
  health_check_interval: "30s"
  sync_interval: "1m"

storage:
  local_cache: "~/.taskflow/tasks/"
  sync_enabled: true

authentication:
  method: "token"  # or "magic-link"
  token_path: "~/.taskflow/token"

features:
  auto_doc_enabled: true
  git_monitoring_enabled: true
  file_watching_enabled: true
EOF

# Test connection
log_info "Testing connection to TaskFlow server..."
if curl -f -s http://$TASKFLOW_SERVER_HOST:$TASKFLOW_SERVER_PORT/health > /dev/null; then
    log_info "Connection successful! ✅"
else
    log_warn "Connection failed. Please check:"
    log_warn "1. Server is running on GCP instance"
    log_warn "2. Firewall allows port $TASKFLOW_SERVER_PORT"
    log_warn "3. Server URL is correct"
    exit 1
fi

# Create systemd service for background sync (Linux)
if [ "$(uname)" == "Linux" ]; then
    log_info "Creating systemd service for TaskFlow client..."

    cat > ~/.config/systemd/user/taskflow-client.service <<EOF
[Unit]
Description=TaskFlow Client
After=network.target

[Service]
Type=simple
ExecStart=$(which taskflow-client) -config ~/.taskflow/client-config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable taskflow-client
    systemctl --user start taskflow-client

    log_info "TaskFlow client service started ✅"
fi

# Create launchd plist for macOS
if [ "$(uname)" == "Darwin" ]; then
    log_info "Creating launchd agent for TaskFlow client..."

    cat > ~/Library/LaunchAgents/com.taskflow.client.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.taskflow.client</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which taskflow-client)</string>
        <string>-config</string>
        <string>~/.taskflow/client-config.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>~/.taskflow/client.log</string>
    <key>StandardErrorPath</key>
    <string>~/.taskflow/client-error.log</string>
</dict>
</plist>
EOF

    launchctl load ~/Library/LaunchAgents/com.taskflow.client.plist
    log_info "TaskFlow client agent started ✅"
fi

log_info ""
log_info "=== Client Configuration Complete ==="
log_info ""
log_info "Your local machine is now connected to the TaskFlow cloud server!"
log_info ""
log_info "Next steps:"
log_info "1. Test sync: taskflow-client -oneshot"
log_info "2. Fetch tasks: taskflow list"
log_info "3. Activate a task: taskflow activate <id>"
log_info "4. Check status: taskflow active"
log_info ""
