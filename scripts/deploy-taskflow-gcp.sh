#!/bin/bash
# TaskFlow GCP Free Tier Deployment Script
# Run this script to deploy TaskFlow to GCP free tier automatically

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="taskflow-free-tier"
INSTANCE_NAME="taskflow-server"
ZONE="us-central1-a"
MACHINE_TYPE="e2-micro"
DISK_SIZE="30GB"
DOMAIN=""  # Set this if you have a domain (e.g., "taskflow.yourdomain.com")

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if gcloud is installed
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Install as part of gcloud CLI."
        exit 1
    fi

    log_info "Prerequisites check passed ✅"
}

# Initialize GCP project
init_project() {
    log_info "Initializing GCP project..."

    # Set project
    gcloud config set project $PROJECT_ID

    # Enable required APIs
    log_info "Enabling required APIs..."
    gcloud services enable compute.googleapis.com
    gcloud services enable storage.googleapis.com
    gcloud services enable secretmanager.googleapis.com

    log_info "Project initialized ✅"
}

# Create compute instance
create_instance() {
    log_info "Creating e2-micro instance..."

    # Check if instance already exists
    if gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &> /dev/null; then
        log_warn "Instance $INSTANCE_NAME already exists. Skipping creation."
        return
    fi

    # Create instance with startup script
    gcloud compute instances create $INSTANCE_NAME \
        --zone=$ZONE \
        --machine-type=$MACHINE_TYPE \
        --image-family=ubuntu-2304-amd64 \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=$DISK_SIZE \
        --boot-disk-type=pd-standard \
        --tags=http-server,https-server \
        --metadata-from-file=startup-script=<(cat <<'EOF'
#!/bin/bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
EOF
)

    log_info "Instance created ✅"
}

# Configure firewall rules
configure_firewall() {
    log_info "Configuring firewall rules..."

    # Allow HTTP
    gcloud compute firewall-rules create allow-http \
        --allow tcp:80 \
        --target-tags http-server \
        --description "Allow HTTP traffic" 2>/dev/null || log_warn "Firewall rule allow-http already exists"

    # Allow HTTPS
    gcloud compute firewall-rules create allow-https \
        --allow tcp:443 \
        --target-tags https-server \
        --description "Allow HTTPS traffic" 2>/dev/null || log_warn "Firewall rule allow-https already exists"

    # Allow TaskFlow API (optional)
    gcloud compute firewall-rules create allow-taskflow \
        --allow tcp:8081 \
        --description "Allow TaskFlow API access" 2>/dev/null || log_warn "Firewall rule allow-taskflow already exists"

    # Allow SSH from current IP
    YOUR_IP=$(curl -s ifconfig.me)
    gcloud compute firewall-rules create allow-ssh \
        --allow tcp:22 \
        --source-ranges $YOUR_IP/32 \
        --description "Allow SSH from $YOUR_IP" 2>/dev/null || log_warn "Firewall rule allow-ssh already exists"

    log_info "Firewall configured ✅"
}

# Reserve static IP
reserve_static_ip() {
    log_info "Reserving static IP..."

    if gcloud compute addresses describe taskflow-ip --region=us-central1 &> /dev/null; then
        log_warn "Static IP already reserved. Skipping."
        STATIC_IP=$(gcloud compute addresses describe taskflow-ip --region=us-central1 --format='get(address)')
    else
        gcloud compute addresses create taskflow-ip --region us-central1
        STATIC_IP=$(gcloud compute addresses describe taskflow-ip --region us-central1 --format='get(address)')
        log_info "Static IP reserved: $STATIC_IP ✅"
    fi
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."

    # SessionForge recordings bucket
    if ! gsutil ls gs://taskflow-session-forge &> /dev/null; then
        gsutil mb -p $PROJECT_ID gs://taskflow-session-forge
        log_info "Bucket taskflow-session-forge created ✅"
    else
        log_warn "Bucket taskflow-session-forge already exists"
    fi

    # Backups bucket
    if ! gsutil ls gs://taskflow-backups &> /dev/null; then
        gsutil mb -p $PROJECT_ID gs://taskflow-backups

        # Set lifecycle policy (30 days)
        cat > /tmp/lifecycle.json <<'EOL'
{
  "lifecycle": {
    "rule": [{
      "action": {"type": "Delete"},
      "condition": {
        "age": 30,
        "matchesStorageClass": ["STANDARD"]
      }
    }]
  }
}
EOL
        gsutil lifecycle set /tmp/lifecycle.json gs://taskflow-backups
        log_info "Bucket taskflow-backups created with lifecycle policy ✅"
    else
        log_warn "Bucket taskflow-backups already exists"
    fi

    # Create service account
    if ! gcloud iam service-accounts describe taskflow-sa@$PROJECT_ID.iam.gserviceaccount.com &> /dev/null; then
        gcloud iam service-accounts create taskflow-sa \
            --display-name "TaskFlow Service Account"
        log_info "Service account created ✅"
    else
        log_warn "Service account already exists"
    fi

    # Grant storage permissions
    gsutil iam ch serviceAccount:taskflow-sa@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin gs://taskflow-session-forge
    gsutil iam ch serviceAccount:taskflow-sa@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin gs://taskflow-backups
}

# Generate deployment package
generate_deployment_package() {
    log_info "Generating deployment package..."

    # Create tarball with setup scripts
    cd /tmp
    cat > taskflow-setup.sh <<'SETUP_EOF'
#!/bin/bash
# TaskFlow Server Setup Script
# Run this on the GCP instance after SSH

set -e

echo "=== TaskFlow Server Setup ==="

# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y postgresql postgresql-contrib redis-server nginx certbot python3-certbot-nginx git build-essential

# Install Go 1.21
echo "Installing Go..."
wget -q https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin
rm go1.21.6.linux-amd64.tar.gz

# Clone and build TaskFlow
echo "Cloning TaskFlow..."
cd /opt
sudo git clone https://github.com/birddigital/taskflow.git
cd taskflow
sudo make build-all

# Create taskflow user
echo "Creating taskflow user..."
sudo useradd -r -s /bin/false taskflow || true

# Create directories
sudo mkdir -p /etc/taskflow
sudo mkdir -p /var/lib/taskflow
sudo mkdir -p /var/log/taskflow
sudo mkdir -p /var/backups/taskflow
sudo chown -R taskflow:taskflow /opt/taskflow /var/lib/taskflow /var/log/taskflow /var/backups/taskflow

# Generate random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)

# Save passwords
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" | sudo tee -a /etc/environment
echo "REDIS_PASSWORD=$REDIS_PASSWORD" | sudo tee -a /etc/environment

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
sudo -u postgres psql <<EOF
CREATE DATABASE taskflow;
CREATE USER taskflow WITH PASSWORD '$POSTGRES_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE taskflow TO taskflow;
\c taskflow
GRANT ALL ON SCHEMA public TO taskflow;
EOF

# Tune PostgreSQL for 1GB RAM
sudo tee -a /etc/postgresql/15/main/postgresql.conf <<EOF
# Memory settings for 1GB VM
shared_buffers = 128MB
effective_cache_size = 256MB
maintenance_work_mem = 64MB
work_mem = 16MB
max_connections = 50
random_page_cost = 1.1
EOF
sudo systemctl restart postgresql

# Configure Redis
echo "Configuring Redis..."
sudo tee /etc/redis/redis.conf <<EOF
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly no
bind 127.0.0.1
requirepass $REDIS_PASSWORD
EOF
sudo systemctl restart redis-server

# Configure TaskFlow
echo "Configuring TaskFlow..."
sudo tee /etc/taskflow/config.yaml <<EOF
server:
  host: "0.0.0.0"
  port: 8081
  cors_enabled: true

storage:
  data_dir: "/var/lib/taskflow"
  auto_backup_enabled: true
  auto_backup_interval: "6h"

database:
  host: "localhost"
  port: 5432
  database: "taskflow"
  user: "taskflow"
  password: "$POSTGRES_PASSWORD"
  ssl_mode: "disable"
  max_connections: 25

redis:
  host: "localhost"
  port: 6379
  password: "$REDIS_PASSWORD"
  max_retries: 3

features:
  auto_doc_enabled: true
  git_monitoring_enabled: true
  file_watching_enabled: true
  websocket_enabled: true

logging:
  level: "info"
  format: "json"
  output: "/var/log/taskflow"
EOF

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/taskflow.service <<EOF
[Unit]
Description=TaskFlow Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=taskflow
WorkingDirectory=/opt/taskflow
Environment="CONFIG_PATH=/etc/taskflow/config.yaml"
ExecStart=/opt/taskflow/bin/taskflow-server
Restart=always
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/taskflow /var/log/taskflow

[Install]
WantedBy=multi-user.target
EOF

# Enable and start TaskFlow
sudo systemctl daemon-reload
sudo systemctl enable taskflow
sudo systemctl start taskflow

# Configure Nginx
echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/taskflow <<'NGINX_EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX_EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/taskflow /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Create health check script
echo "Creating health check script..."
sudo tee /usr/local/bin/taskflow-healthcheck <<'EOF'
#!/bin/bash
curl -f http://localhost:8081/health || exit 1
sudo -u postgres pg_isready || exit 1
redis-cli ping || exit 1
echo "All systems healthy"
EOF
sudo chmod +x /usr/local/bin/taskflow-healthcheck

# Create backup script
echo "Creating backup script..."
sudo tee /usr/local/bin/taskflow-backup <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/taskflow"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
sudo -u postgres pg_dump taskflow | gzip > $BACKUP_DIR/postgres_$DATE.sql.gz
tar -czf $BACKUP_DIR/taskflow_data_$DATE.tar.gz /var/lib/taskflow
echo "Backup completed: $DATE"
EOF
sudo chmod +x /usr/local/bin/taskflow-backup

# Add cron jobs
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/taskflow-healthcheck | logger -t taskflow-health") | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/taskflow-backup | logger -t taskflow-backup") | crontab -

# Create logrotate config
sudo tee /etc/logrotate.d/taskflow <<'EOF'
/var/log/taskflow/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 taskflow taskflow
}
EOF

echo ""
echo "=== TaskFlow Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Test locally: curl http://localhost:8081/health"
echo "2. Configure SSL: sudo certbot --nginx -d YOUR_DOMAIN"
echo "3. Check logs: sudo journalctl -u taskflow -f"
echo "4. View dashboard: http://$(curl -s ifconfig.me)/dashboard"
echo ""

SETUP_EOF

    chmod +x taskflow-setup.sh
    log_info "Deployment package generated ✅"
}

# Print next steps
print_next_steps() {
    STATIC_IP=$(gcloud compute addresses describe taskflow-ip --region=us-central1 --format='get(address)')

    echo ""
    log_info "=== Deployment Complete ==="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. SSH into the instance:"
    echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    echo ""
    echo "2. Upload and run the setup script:"
    echo "   gcloud compute scp taskflow-setup.sh $INSTANCE_NAME:~"
    echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command '~/taskflow-setup.sh'"
    echo ""
    echo "3. Configure SSL (if you have a domain):"
    echo "   sudo certbot --nginx -d taskflow.yourdomain.com"
    echo ""
    echo "4. Access TaskFlow:"
    echo "   HTTP:  http://$STATIC_IP"
    echo "   HTTPS: https://taskflow.yourdomain.com (after SSL)"
    echo ""
    echo "5. Test API:"
    echo "   curl http://$STATIC_IP/health"
    echo ""
    echo "6. Configure DNS (if using domain):"
    echo "   Type: A"
    echo "   Name: taskflow"
    echo "   Value: $STATIC_IP"
    echo ""
}

# Main deployment flow
main() {
    log_info "Starting TaskFlow GCP deployment..."

    check_prerequisites
    init_project
    create_instance
    configure_firewall
    reserve_static_ip
    create_storage_buckets
    generate_deployment_package

    print_next_steps

    log_info "Deployment script complete! 🎉"
    log_warn "Remember to run the setup script on the instance after SSH."
}

# Run main function
main
