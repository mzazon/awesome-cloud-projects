#!/bin/bash

# Startup script for multi-region application instances
# This script configures a simple web server with region identification

set -e

# Log all output to startup script log
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting application server setup..."

# Update system packages
apt-get update
apt-get install -y nginx curl jq

# Get instance metadata from Google Cloud metadata service
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)
REGION=$(echo "$ZONE" | sed 's/-[a-z]$//')
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/project/project-id)

echo "Instance: $INSTANCE_NAME"
echo "Zone: $ZONE"
echo "Region: $REGION"
echo "Project: $PROJECT_ID"

# Create custom index page with regional information
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Traffic Optimization - $REGION</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
            border: 1px solid rgba(255, 255, 255, 0.18);
            max-width: 600px;
        }
        h1 {
            margin-bottom: 30px;
            font-size: 2.5rem;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin: 30px 0;
        }
        .info-item {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .info-label {
            font-size: 0.9rem;
            opacity: 0.8;
            margin-bottom: 5px;
        }
        .info-value {
            font-size: 1.2rem;
            font-weight: bold;
        }
        .status {
            margin-top: 30px;
            padding: 15px;
            background: rgba(72, 187, 120, 0.3);
            border-radius: 10px;
            border: 1px solid rgba(72, 187, 120, 0.5);
        }
        .footer {
            margin-top: 30px;
            font-size: 0.9rem;
            opacity: 0.7;
        }
        @media (max-width: 600px) {
            .info-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌍 Global Load Balancer</h1>
        
        <div class="info-grid">
            <div class="info-item">
                <div class="info-label">Instance Name</div>
                <div class="info-value">$INSTANCE_NAME</div>
            </div>
            <div class="info-item">
                <div class="info-label">Serving from Zone</div>
                <div class="info-value">$ZONE</div>
            </div>
            <div class="info-item">
                <div class="info-label">Region</div>
                <div class="info-value">$REGION</div>
            </div>
            <div class="info-item">
                <div class="info-label">Server Time</div>
                <div class="info-value" id="server-time">$(date '+%Y-%m-%d %H:%M:%S UTC')</div>
            </div>
        </div>
        
        <div class="status">
            ✅ Load balancer working correctly!
        </div>
        
        <div class="footer">
            Multi-Region Traffic Optimization Demo<br>
            Powered by Google Cloud Load Balancing & CDN
        </div>
    </div>
    
    <script>
        // Update time every second
        function updateTime() {
            const now = new Date();
            document.getElementById('server-time').textContent = 
                now.toISOString().replace('T', ' ').replace(/\..+/, '') + ' UTC';
        }
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
EOF

# Create a health check endpoint
cat > /var/www/html/health << EOF
{
    "status": "healthy",
    "instance": "$INSTANCE_NAME",
    "zone": "$ZONE",
    "region": "$REGION",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Create API endpoint for load balancer testing
mkdir -p /var/www/html/api
cat > /var/www/html/api/info << EOF
{
    "instance_name": "$INSTANCE_NAME",
    "zone": "$ZONE",
    "region": "$REGION",
    "project_id": "$PROJECT_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "server_type": "nginx",
    "load_balancer": "google-cloud-global-lb"
}
EOF

# Configure nginx to listen on port 8080 and serve content
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;
    
    # Add custom headers for load balancer identification
    add_header X-Served-By $INSTANCE_NAME;
    add_header X-Served-From $ZONE;
    add_header X-Region $REGION;
    add_header Cache-Control "public, max-age=3600" always;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Health check endpoint
    location /health {
        access_log off;
        add_header Content-Type application/json;
        try_files \$uri \$uri/ =404;
    }

    # API endpoints
    location /api/ {
        add_header Content-Type application/json;
        try_files \$uri \$uri/ =404;
    }

    # Enable gzip compression for better performance
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

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
}
EOF

# Test nginx configuration
nginx -t

# Start and enable nginx
systemctl restart nginx
systemctl enable nginx

# Configure firewall (if ufw is available)
if command -v ufw &> /dev/null; then
    ufw allow 8080/tcp
fi

# Install Cloud Monitoring agent for better observability
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure log collection for nginx
cat > /etc/google-cloud-ops-agent/config.yaml << EOF
logging:
  receivers:
    nginx_access:
      type: nginx_access
      include_paths:
        - /var/log/nginx/access.log
    nginx_error:
      type: nginx_error
      include_paths:
        - /var/log/nginx/error.log
  service:
    pipelines:
      default_pipeline:
        receivers: [nginx_access, nginx_error]
      
metrics:
  receivers:
    nginx:
      type: nginx
      stub_status_url: http://localhost:8080/nginx_status
  service:
    pipelines:
      default_pipeline:
        receivers: [nginx]
EOF

# Restart the ops agent
systemctl restart google-cloud-ops-agent

# Create a simple monitoring script
cat > /usr/local/bin/health-monitor.sh << 'EOF'
#!/bin/bash

# Simple health monitoring script
LOG_FILE="/var/log/health-monitor.log"

while true; do
    # Check nginx status
    if systemctl is-active --quiet nginx; then
        echo "$(date): Nginx is running - OK" >> "$LOG_FILE"
    else
        echo "$(date): Nginx is not running - CRITICAL" >> "$LOG_FILE"
        systemctl restart nginx
    fi
    
    # Check if port 8080 is listening
    if netstat -ln | grep -q ":8080 "; then
        echo "$(date): Port 8080 is listening - OK" >> "$LOG_FILE"
    else
        echo "$(date): Port 8080 is not listening - CRITICAL" >> "$LOG_FILE"
    fi
    
    # Sleep for 30 seconds
    sleep 30
done
EOF

chmod +x /usr/local/bin/health-monitor.sh

# Create systemd service for health monitoring
cat > /etc/systemd/system/health-monitor.service << EOF
[Unit]
Description=Application Health Monitor
After=network.target nginx.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/health-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the health monitor
systemctl daemon-reload
systemctl enable health-monitor.service
systemctl start health-monitor.service

# Create startup completion marker
touch /var/log/startup-complete

echo "Application server setup completed successfully!"
echo "Server is ready to serve traffic on port 8080"
echo "Health check endpoint: http://localhost:8080/health"
echo "API info endpoint: http://localhost:8080/api/info"

# Final verification
curl -s http://localhost:8080/health || echo "Warning: Health check failed"

echo "Startup script finished at $(date)"