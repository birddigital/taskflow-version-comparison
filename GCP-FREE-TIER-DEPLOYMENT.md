# TaskFlow GCP Free Tier Deployment Plan

**Created**: 2026-01-29
**Status**: Planning Phase
**Target Cost**: $0/month (GCP Always Free Tier)

---

## 🎯 Architecture Overview

### All-in-One e2-micro Strategy

Deploy TaskFlow + PostgreSQL + Redis on a single GCP e2-micro instance (1GB RAM, 2 vCPU shared).

**Why This Works**:
- TaskFlow is personal/small-team software (not enterprise scale)
- PostgreSQL + Redis are I/O-bound, not CPU-bound
- Go's garbage collector and efficient runtime fit perfectly
- Single VM = zero network latency between services
- Shared CPU is sufficient for async workloads

**Resource Allocation**:
```
Total RAM: 1 GB
├── PostgreSQL: 400 MB (tuned with shared_buffers = 128MB)
├── Redis: 256 MB (maxmemory 256MB, allkeys-lru)
├── TaskFlow Server: 200 MB (Go runtime is efficient)
├── OS + Nginx: 100 MB
└── Headroom: 44 MB
```

---

## 🚀 Phase 1: GCP Infrastructure Setup

### 1.1 Create GCP Project

```bash
# Set project
gcloud init
PROJECT_ID="taskflow-free-tier"
gcloud config set project $PROJECT_ID

# Enable APIs
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable secretmanager.googleapis.com
```

### 1.2 Create e2-micro Instance

```bash
# Instance configuration
INSTANCE_NAME="taskflow-server"
ZONE="us-central1-a"  # Free tier eligible region
MACHINE_TYPE="e2-micro"
IMAGE_FAMILY="ubuntu-2304-amd64"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="30GB"
DISK_TYPE="pd-standard"

# Create instance
gcloud compute instances create $INSTANCE_NAME \
  --zone=$ZONE \
  --machine-type=$MACHINE_TYPE \
  --image-family=$IMAGE_FAMILY \
  --image-project=$IMAGE_PROJECT \
  --boot-disk-size=$DISK_SIZE \
  --boot-disk-type=$DISK_TYPE \
  --tags=http-server,https-server \
  --metadata=startup-script=#istio \
    #! /bin/bash
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
```

### 1.3 Configure Firewall Rules

```bash
# Allow HTTP/HTTPS
gcloud compute firewall-rules create allow-http \
  --allow tcp:80 --target-tags http-server

gcloud compute firewall-rules create allow-https \
  --allow tcp:443 --target-tags https-server

# Allow TaskFlow API (optional - for direct access)
gcloud compute firewall-rules create allow-taskflow \
  --allow tcp:8081 --source-ranges 0.0.0.0/0

# Allow SSH (restrict to your IP)
YOUR_IP=$(curl -s ifconfig.me)
gcloud compute firewall-rules create allow-ssh \
  --allow tcp:22 --source-ranges $YOUR_IP/32
```

### 1.4 Reserve Static IP (Free)

```bash
# Reserve static IP
gcloud compute addresses create taskflow-ip \
  --region us-central1

# Get IP address
STATIC_IP=$(gcloud compute addresses describe taskflow-ip \
  --region us-central1 \
  --format='get(address)')

echo "Static IP: $STATIC_IP"
```

---

## 🗄️ Phase 2: Database & Cache Setup

### 2.1 Install PostgreSQL (Tuned for 1GB RAM)

```bash
# SSH into instance
gcloud compute ssh taskflow-server --zone us-central1-a

# Install PostgreSQL 15
sudo apt update
sudo apt install -y postgresql postgresql-contrib

# Tune PostgreSQL for 1GB RAM
sudo tee -a /etc/postgresql/15/main/postgresql.conf <<EOF
# Memory settings for 1GB VM
shared_buffers = 128MB
effective_cache_size = 256MB
maintenance_work_mem = 64MB
work_mem = 16MB
max_connections = 50

# Performance tuning
random_page_cost = 1.1  # SSD storage
effective_io_concurrency = 200
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 2GB
checkpoint_completion_target = 0.9
EOF

# Restart PostgreSQL
sudo systemctl restart postgresql

# Create database and user
sudo -u postgres psql <<EOF
CREATE DATABASE taskflow;
CREATE USER taskflow WITH PASSWORD 'CHANGE_THIS_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE taskflow TO taskflow;
\c taskflow
GRANT ALL ON SCHEMA public TO taskflow;
EOF
```

### 2.2 Install Redis (Tuned for 1GB RAM)

```bash
# Install Redis
sudo apt install -y redis-server

# Tune Redis for 1GB RAM
sudo tee /etc/redis/redis.conf <<EOF
# Memory limit
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistence (disable AOF to save RAM)
save 900 1
save 300 10
save 60 10000
appendonly no

# Security
bind 127.0.0.1
protected-mode yes
requirepass CHANGE_THIS_PASSWORD
EOF

# Restart Redis
sudo systemctl restart redis-server

# Verify
redis-cli ping  # Should return PONG
```

---

## 🐳 Phase 3: TaskFlow Deployment

### 3.1 Install TaskFlow Dependencies

```bash
# Install Go 1.21
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Clone TaskFlow
cd /opt
sudo git clone https://github.com/birddigital/taskflow.git
cd taskflow

# Build
sudo make build-all
```

### 3.2 Configure TaskFlow

```bash
# Create config directory
sudo mkdir -p /etc/taskflow
sudo chown $USER:$USER /etc/taskflow

# Create production config
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
  password: "${POSTGRES_PASSWORD}"
  ssl_mode: "disable"
  max_connections: 25

redis:
  host: "localhost"
  port: 6379
  password: "${REDIS_PASSWORD}"
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

# Set environment variables
echo "export POSTGRES_PASSWORD='CHANGE_THIS_PASSWORD'" | sudo tee -a /etc/environment
echo "export REDIS_PASSWORD='CHANGE_THIS_PASSWORD'" | sudo tee -a /etc/environment

# Create data directory
sudo mkdir -p /var/lib/taskflow
sudo mkdir -p /var/log/taskflow
sudo chown $USER:$USER /var/lib/taskflow
sudo chown $USER:$USER /var/log/taskflow
```

### 3.3 Create Systemd Service

```bash
# Create systemd service for TaskFlow server
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

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/taskflow /var/log/taskflow

[Install]
WantedBy=multi-user.target
EOF

# Create taskflow user
sudo useradd -r -s /bin/false taskflow
sudo chown -R taskflow:taskflow /opt/taskflow /var/lib/taskflow /var/log/taskflow

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable taskflow
sudo systemctl start taskflow

# Check status
sudo systemctl status taskflow
```

---

## 🌐 Phase 4: Nginx Reverse Proxy + SSL

### 4.1 Install Nginx

```bash
# Install Nginx
sudo apt install -y nginx

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default
```

### 4.2 Configure Nginx with SSL

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Create Nginx config (before SSL)
sudo tee /etc/nginx/sites-available/taskflow <<'EOF'
server {
    listen 80;
    server_name taskflow.yourdomain.com;

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
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/taskflow /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Get SSL certificate (replace email and domain)
sudo certbot --nginx -d taskflow.yourdomain.com \
  --email your@email.com \
  --agree-tos \
  --non-interactive \
  --redirect

# Auto-renewal (configured by certbot)
sudo certbot renew --dry-run
```

### 4.3 Configure DNS

```
# Add A record at your DNS provider
Type: A
Name: taskflow
Value: YOUR_STATIC_IP
TTL: 300
```

---

## ☁️ Phase 5: Cloud Storage Integration

### 5.1 Create Cloud Storage Bucket

```bash
# Create bucket (5GB free)
BUCKET_NAME="taskflow-session-forge"
gsutil mb -p $PROJECT_ID gs://$BUCKET_NAME

# Set lifecycle policy (delete files after 30 days)
cat > lifecycle.json <<EOF
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
gsutil lifecycle set lifecycle.json gs://$BUCKET_NAME

# Create service account for TaskFlow
gcloud iam service-accounts create taskflow-sa \
  --display-name "TaskFlow Service Account"

# Grant storage admin
gsutil iam ch serviceAccount:taskflow-sa@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin \
  gs://$BUCKET_NAME

# Download key
gcloud iam service-accounts keys create key.json \
  --iam-account=taskflow-sa@$PROJECT_ID.iam.gserviceaccount.com

# Copy to instance
gcloud compute scp key.json taskflow-server:/etc/taskflow/gcs-key.json
```

---

## 🔧 Phase 6: Monitoring & Maintenance

### 6.1 Setup Monitoring

```bash
# Install monitoring tools
sudo apt install -y htop iotop

# Create health check script
sudo tee /usr/local/bin/taskflow-healthcheck <<'EOF'
#!/bin/bash
# Check TaskFlow API
curl -f http://localhost:8081/health || exit 1

# Check PostgreSQL
sudo -u postgres pg_isready || exit 1

# Check Redis
redis-cli ping || exit 1

echo "All systems healthy"
EOF

chmod +x /usr/local/bin/taskflow-healthcheck

# Add to crontab (every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/taskflow-healthcheck | logger -t taskflow-health") | crontab -
```

### 6.2 Setup Automatic Backups

```bash
# Create backup script
sudo tee /usr/local/bin/taskflow-backup <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/taskflow"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup PostgreSQL
sudo -u postgres pg_dump taskflow | gzip > $BACKUP_DIR/postgres_$DATE.sql.gz

# Backup TaskFlow data
tar -czf $BACKUP_DIR/taskflow_data_$DATE.tar.gz /var/lib/taskflow

# Upload to Cloud Storage (keep last 7 days)
gsutil cp $BACKUP_DIR/postgres_$DATE.sql.gz gs://taskflow-backups/postgres/
gsutil cp $BACKUP_DIR/taskflow_data_$DATE.tar.gz gs://taskflow-backups/data/

# Clean local backups older than 7 days
find $BACKUP_DIR -name "*.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x /usr/local/bin/taskflow-backup

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/taskflow-backup | logger -t taskflow-backup") | crontab -
```

### 6.3 Log Rotation

```bash
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
    sharedscripts
    postrotate
        systemctl reload taskflow > /dev/null 2>&1 || true
    endscript
}
EOF
```

---

## ✅ Phase 7: Testing & Verification

### 7.1 Health Checks

```bash
# Check TaskFlow API
curl http://localhost:8081/health

# Expected response:
# {"status":"healthy","service":"taskflow","version":"1.0.0",...}

# Check PostgreSQL
sudo -u postgres psql -c "SELECT version();"

# Check Redis
redis-cli info server

# Check Nginx
sudo nginx -t

# Check all services
sudo systemctl status taskflow postgresql redis-server nginx
```

### 7.2 Access TaskFlow

```bash
# Local access
curl http://localhost:8081/api/tasks

# Remote access (via domain)
curl https://taskflow.yourdomain.com/api/tasks

# Dashboard
# Open: https://taskflow.yourdomain.com/dashboard
```

---

## 🎉 Post-Deployment Checklist

### ✅ Configuration

- [ ] PostgreSQL tuned for 1GB RAM
- [ ] Redis maxmemory set to 256MB
- [ ] TaskFlow config in `/etc/taskflow/config.yaml`
- [ ] SSL certificate installed (Let's Encrypt)
- [ ] Static IP reserved
- [ ] DNS A record configured
- [ ] Firewall rules configured
- [ ] Cloud Storage bucket created
- [ ] Backup cron jobs configured
- [ ] Log rotation configured

### ✅ Security

- [ ] PostgreSQL password changed from default
- [ ] Redis password configured
- [ ] Firewall restricted to necessary ports
- [ ] SSH restricted to your IP
- [ ] SSL/TLS enabled
- [ ] GCS key permissions set correctly
- [ ] Service account principle of least privilege

### ✅ Monitoring

- [ ] Health check script running
- [ ] Backup script scheduled
- [ ] Log rotation configured
- [ ] Logs in `/var/log/taskflow/`
- [ ] Cloud Storage backups working

---

## 📊 Performance Optimization

### PostgreSQL Tuning (Already Applied)

```conf
shared_buffers = 128MB        # 12.5% of RAM
effective_cache_size = 256MB  # 25% of RAM
work_mem = 16MB               # Per-operation memory
max_connections = 50          # Concurrent connections
```

### Redis Tuning (Already Applied)

```conf
maxmemory 256mb              # 25% of RAM
maxmemory-policy allkeys-lru # Evict least recently used
appendonly no                # Disable AOF (saves RAM/CPU)
```

### TaskFlow Tuning

```yaml
database:
  max_connections: 25        # Limit connection pool

features:
  file_watching_batch_size: 100  # Batch file events
  git_polling_interval: "5m"     # Reduce git polling frequency
```

---

## 💰 Cost Management

### Monitoring Free Tier Usage

```bash
# Check current billing
gcloud billing accounts list

# Set budget alert ($0 target)
gcloud billing budgets create \
  --billing-account=YOUR_BILLING_ID \
  --display-usage="Free Tier Monitor" \
  --amount=0

# Monitor VM usage
gcloud compute instances describe taskflow-server \
  --zone us-central1-a \
  --format='table(name,machineType,status)'
```

### Staying Within Free Limits

| Resource | Free Limit | Current Usage | Status |
|----------|-----------|---------------|--------|
| e2-micro VM | 720 hrs/month | ~730 hrs/month | ✅ Safe (continuous) |
| Persistent Disk | 30 GB | 30 GB | ✅ At limit |
| Cloud Storage | 5 GB | ~2 GB (backups) | ✅ Safe |
| Network Egress | 200 GB/region | ~10 GB | ✅ Safe |

**WARNING**: Creating additional VMs or using >30GB disk will incur charges.

---

## 🚨 Troubleshooting

### Out of Memory (OOM)

If you see OOM errors in `/var/log/syslog`:

```bash
# Check memory usage
free -h

# If PostgreSQL is using too much, reduce shared_buffers
sudo nano /etc/postgresql/15/main/postgresql.conf
# Set: shared_buffers = 96MB
sudo systemctl restart postgresql

# If Redis is using too much, reduce maxmemory
sudo nano /etc/redis/redis.conf
# Set: maxmemory 192mb
sudo systemctl restart redis-server
```

### High CPU Usage

```bash
# Check top processes
htop

# If TaskFlow is using too much CPU, check configuration
cat /etc/taskflow/config.yaml

# Reduce file watching frequency
yaml:
  git_polling_interval: "10m"  # Increase from 5m
```

### Database Connection Errors

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Check connection count
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"

# If near max_connections (50), increase in postgresql.conf
# max_connections = 100
sudo systemctl restart postgresql
```

---

## 📚 Additional Resources

- [GCP Free Tier Documentation](https://cloud.google.com/free/docs/free-cloud-features)
- [PostgreSQL Tuning Guide](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)
- [Redis Memory Optimization](https://redis.io/topics/lru-cache)
- [TaskFlow GitHub Repository](https://github.com/birddigital/taskflow)

---

## 🎯 Next Steps

1. **Deploy this architecture** to GCP free tier
2. **Test all TaskFlow features** (auto-doc, git monitoring, multi-machine sync)
3. **Implement project registration** (Task #14 from version comparison)
4. **Connect local machines** to cloud instance for sync
5. **Demo the full system** with SessionForge integration

**Total Monthly Cost: $0.00** ✅
