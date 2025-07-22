#!/bin/bash

# VM Initialization Script for Azure Infrastructure Lifecycle Management
# This script sets up the web server and monitoring components on each VM instance

set -e

# Variables
CUSTOM_SCRIPT_URI="${custom_script_uri}"
LOG_FILE="/var/log/vm-init.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting VM initialization script"

# Update system packages
log "Updating system packages"
apt-get update -y

# Install required packages
log "Installing required packages"
apt-get install -y nginx curl wget unzip jq htop net-tools

# Configure nginx
log "Configuring nginx web server"
systemctl enable nginx
systemctl start nginx

# Create custom index page
log "Creating custom web page"
HOSTNAME=$(hostname)
INSTANCE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text" || echo "unknown")
INSTANCE_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text" || echo "unknown")

cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Infrastructure Lifecycle Management Demo</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078D4;
            text-align: center;
        }
        .info {
            background-color: #e8f4f8;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .status {
            background-color: #d4edda;
            color: #155724;
            padding: 10px;
            border-radius: 5px;
            margin: 10px 0;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Infrastructure Lifecycle Management Demo</h1>
        
        <div class="status">
            ✅ Web Server Status: Running
        </div>
        
        <div class="info">
            <h3>Server Information</h3>
            <p><strong>Hostname:</strong> $HOSTNAME</p>
            <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
            <p><strong>Instance Name:</strong> $INSTANCE_NAME</p>
            <p><strong>Deployment Time:</strong> $(date)</p>
        </div>
        
        <div class="info">
            <h3>Azure Services</h3>
            <p>✅ Azure Deployment Stacks - Managing infrastructure as atomic units</p>
            <p>✅ Azure Update Manager - Automated patch management</p>
            <p>✅ Azure Monitor - Comprehensive monitoring and logging</p>
            <p>✅ Azure Policy - Governance and compliance</p>
        </div>
        
        <div class="info">
            <h3>Features Enabled</h3>
            <p>🔧 Automated patch management with weekly maintenance windows</p>
            <p>🛡️ Resource protection through deployment stack deny settings</p>
            <p>📊 Real-time monitoring and compliance reporting</p>
            <p>🔄 Infrastructure lifecycle management</p>
        </div>
        
        <div class="footer">
            <p>Powered by Azure Deployment Stacks and Azure Update Manager</p>
            <p>Deployed via Terraform Infrastructure as Code</p>
        </div>
    </div>
</body>
</html>
EOF

# Configure nginx for better performance
log "Optimizing nginx configuration"
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Server status endpoint
    location /status {
        access_log off;
        return 200 '{"status":"healthy","hostname":"'$HOSTNAME'","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}';
        add_header Content-Type application/json;
    }
}
EOF

# Restart nginx to apply configuration
log "Restarting nginx service"
systemctl restart nginx

# Install and configure Azure CLI (for maintenance operations)
log "Installing Azure CLI"
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Configure automatic updates to work with Azure Update Manager
log "Configuring automatic updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "0";
EOF

# Install monitoring agent (if not already installed by VMSS extension)
log "Configuring monitoring"
systemctl enable rsyslog
systemctl start rsyslog

# Create monitoring script
cat > /usr/local/bin/system-monitor.sh << 'EOF'
#!/bin/bash
# System monitoring script for Azure Monitor integration

# Get system metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | cut -d'%' -f1)

# Log metrics
logger "SYSTEM_METRICS: CPU=$CPU_USAGE%, Memory=$MEMORY_USAGE%, Disk=$DISK_USAGE%"

# Check nginx status
if systemctl is-active --quiet nginx; then
    logger "SERVICE_STATUS: nginx=active"
else
    logger "SERVICE_STATUS: nginx=inactive"
fi
EOF

chmod +x /usr/local/bin/system-monitor.sh

# Set up cron job for monitoring
log "Setting up monitoring cron job"
echo "*/5 * * * * /usr/local/bin/system-monitor.sh" | crontab -

# Run custom script if provided
if [ -n "$CUSTOM_SCRIPT_URI" ] && [ "$CUSTOM_SCRIPT_URI" != "" ]; then
    log "Downloading and executing custom script from: $CUSTOM_SCRIPT_URI"
    wget -O /tmp/custom-script.sh "$CUSTOM_SCRIPT_URI"
    chmod +x /tmp/custom-script.sh
    /tmp/custom-script.sh
else
    log "No custom script URI provided, skipping custom script execution"
fi

# Configure log rotation
log "Configuring log rotation"
cat > /etc/logrotate.d/vm-init << 'EOF'
/var/log/vm-init.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

# Enable and start services
log "Enabling and starting services"
systemctl enable nginx
systemctl enable cron
systemctl start cron

# Final system check
log "Performing final system check"
if systemctl is-active --quiet nginx; then
    log "✅ Nginx is running successfully"
else
    log "❌ Nginx failed to start"
    exit 1
fi

if systemctl is-active --quiet cron; then
    log "✅ Cron service is running"
else
    log "❌ Cron service failed to start"
fi

# Log completion
log "✅ VM initialization completed successfully"
log "🌐 Web server is accessible on port 80"
log "📊 Monitoring is configured and running"
log "🔄 System is ready for Azure Update Manager"

exit 0
EOF