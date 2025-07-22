#!/bin/bash
#
# Content Server Startup Script
# This script configures nginx and sets up monitoring for the content delivery infrastructure
#
# Template variables:
# - region_name: The region where this server is deployed
# - zone_name: The specific zone for this server
# - server_role: The role of this server (primary, secondary, tertiary)
# - bucket_name: The name of the Cloud Storage bucket
# - environment: The deployment environment

set -euo pipefail

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/content-server-startup.log
}

log "Starting content server configuration for ${server_role} region: ${region_name}"

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing required packages..."
apt-get install -y \
    nginx \
    curl \
    wget \
    unzip \
    jq \
    htop \
    vim \
    git \
    python3 \
    python3-pip \
    google-cloud-sdk

# Configure nginx
log "Configuring nginx web server..."

# Create custom nginx configuration
cat > /etc/nginx/sites-available/content-delivery << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    root /var/www/html;
    index index.html index.htm;
    
    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Add headers for caching and performance
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Server-Region "${region_name}";
    add_header X-Server-Zone "${zone_name}";
    add_header X-Server-Role "${server_role}";
    add_header X-Cache-Status "MISS";
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
        add_header X-Server-Status "healthy";
    }
    
    # Status endpoint with server information
    location /status {
        access_log off;
        return 200 '{"status":"healthy","region":"${region_name}","zone":"${zone_name}","role":"${server_role}","timestamp":"$time_iso8601"}';
        add_header Content-Type application/json;
    }
    
    # Main location block
    location / {
        try_files $uri $uri/ =404;
        
        # Cache static assets
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt|dat)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            add_header X-Cache-Control "static-asset";
        }
    }
    
    # Nginx status for monitoring
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;
    }
}
EOF

# Enable the new site and disable default
ln -sf /etc/nginx/sites-available/content-delivery /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t
if [ $? -eq 0 ]; then
    log "Nginx configuration is valid"
else
    log "ERROR: Nginx configuration is invalid"
    exit 1
fi

# Create main content page with region-specific information
log "Creating region-specific content page..."
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Content Server - ${server_role^} Region (${region_name})</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 40px 20px;
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .info-box {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 25px;
            margin: 20px 0;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .info-box h3 {
            margin-top: 0;
            color: #fff;
        }
        .server-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric {
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
        }
        .metric strong {
            display: block;
            font-size: 1.2em;
            margin-bottom: 5px;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            background: #4CAF50;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .timestamp {
            text-align: center;
            margin-top: 30px;
            opacity: 0.8;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌍 Content Server - ${server_role^} Region</h1>
            <p>Global Content Delivery Infrastructure</p>
        </div>

        <div class="info-box">
            <h3><span class="status-indicator"></span>Server Information</h3>
            <div class="server-info">
                <div class="metric">
                    <strong>Region</strong>
                    ${region_name}
                </div>
                <div class="metric">
                    <strong>Zone</strong>
                    ${zone_name}
                </div>
                <div class="metric">
                    <strong>Role</strong>
                    ${server_role^}
                </div>
                <div class="metric">
                    <strong>Environment</strong>
                    ${environment}
                </div>
            </div>
        </div>

        <div class="info-box">
            <h3>🏗️ Infrastructure Components</h3>
            <p>✅ <strong>Content Server:</strong> Nginx web server with performance optimizations</p>
            <p>⚡ <strong>Anywhere Cache:</strong> Local SSD-backed cache for ${bucket_name}</p>
            <p>🌐 <strong>Cloud WAN:</strong> Google's global backbone connectivity</p>
            <p>📊 <strong>Monitoring:</strong> Health checks and performance metrics</p>
        </div>

        <div class="info-box">
            <h3>🔗 Available Endpoints</h3>
            <p><strong>/health</strong> - Health check endpoint for load balancer</p>
            <p><strong>/status</strong> - JSON status information with server details</p>
            <p><strong>/nginx_status</strong> - Nginx server statistics (internal only)</p>
        </div>

        <div class="timestamp">
            Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
        </div>
    </div>

    <script>
        // Simple JavaScript to add interactivity
        document.addEventListener('DOMContentLoaded', function() {
            // Update timestamp every second
            function updateTime() {
                const timestampDiv = document.querySelector('.timestamp');
                if (timestampDiv) {
                    const now = new Date();
                    timestampDiv.innerHTML = 'Current Time: ' + now.toLocaleString() + 
                                           '<br>Page loaded: $(date "+%Y-%m-%d %H:%M:%S %Z")';
                }
            }
            
            setInterval(updateTime, 1000);
            
            // Add some visual feedback for metrics
            const metrics = document.querySelectorAll('.metric');
            metrics.forEach((metric, index) => {
                metric.style.opacity = '0';
                metric.style.transform = 'translateY(20px)';
                setTimeout(() => {
                    metric.style.transition = 'all 0.5s ease';
                    metric.style.opacity = '1';
                    metric.style.transform = 'translateY(0)';
                }, index * 100);
            });
        });
    </script>
</body>
</html>
EOF

# Create sample test files for performance testing
log "Creating sample test files..."
mkdir -p /var/www/html/static

# Create small test file (1MB)
dd if=/dev/zero of=/var/www/html/static/small-test.dat bs=1M count=1 2>/dev/null

# Create medium test file (10MB)
dd if=/dev/zero of=/var/www/html/static/medium-test.dat bs=1M count=10 2>/dev/null

# Create large test file (100MB)
dd if=/dev/zero of=/var/www/html/static/large-test.dat bs=1M count=100 2>/dev/null

# Set proper permissions
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

# Start and enable nginx
log "Starting nginx service..."
systemctl start nginx
systemctl enable nginx

# Check if nginx is running
if systemctl is-active --quiet nginx; then
    log "Nginx is running successfully"
else
    log "ERROR: Nginx failed to start"
    systemctl status nginx
    exit 1
fi

# Install and configure monitoring agent (optional)
log "Setting up monitoring..."

# Create a simple monitoring script
cat > /usr/local/bin/server-monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for content server

LOGFILE="/var/log/server-monitor.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check nginx status
if systemctl is-active --quiet nginx; then
    NGINX_STATUS="healthy"
else
    NGINX_STATUS="unhealthy"
fi

# Get system metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
DISK_USAGE=$(df -h / | awk 'NR==2{printf "%s", $5}')

# Log metrics
echo "[$TIMESTAMP] nginx=$NGINX_STATUS cpu=$CPU_USAGE% memory=$MEMORY_USAGE% disk=$DISK_USAGE" >> $LOGFILE

# Rotate log if it gets too large (keep last 1000 lines)
if [ $(wc -l < $LOGFILE) -gt 1000 ]; then
    tail -n 1000 $LOGFILE > $LOGFILE.tmp && mv $LOGFILE.tmp $LOGFILE
fi
EOF

chmod +x /usr/local/bin/server-monitor.sh

# Set up cron job for monitoring (every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/server-monitor.sh") | crontab -

# Configure log rotation for nginx
cat > /etc/logrotate.d/content-server << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 nginx nginx
    postrotate
        systemctl reload nginx
    endscript
}

/var/log/content-server-startup.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
}

/var/log/server-monitor.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
}
EOF

# Set up firewall rules (ufw)
log "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS (for future use)

# Create a final health check
log "Performing final health checks..."

# Test nginx configuration
nginx -t
if [ $? -ne 0 ]; then
    log "ERROR: Nginx configuration test failed"
    exit 1
fi

# Test HTTP response
curl -f http://localhost/health > /dev/null 2>&1
if [ $? -eq 0 ]; then
    log "Health check endpoint is responding correctly"
else
    log "WARNING: Health check endpoint is not responding"
fi

# Test status endpoint
STATUS_RESPONSE=$(curl -s http://localhost/status)
if [ $? -eq 0 ] && echo "$STATUS_RESPONSE" | jq . > /dev/null 2>&1; then
    log "Status endpoint is responding with valid JSON"
else
    log "WARNING: Status endpoint is not responding with valid JSON"
fi

# Final system status
log "=== Content Server Setup Complete ==="
log "Server Role: ${server_role}"
log "Region: ${region_name}"
log "Zone: ${zone_name}"
log "Environment: ${environment}"
log "Storage Bucket: ${bucket_name}"
log "Nginx Status: $(systemctl is-active nginx)"
log "Setup completed at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "============================================="

# Send final notification to system log
logger "Content server startup completed successfully for ${server_role} region (${region_name})"

exit 0