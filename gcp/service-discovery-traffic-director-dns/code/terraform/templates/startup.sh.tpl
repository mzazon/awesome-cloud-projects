#!/bin/bash
# ==============================================================================
# Service Discovery Startup Script Template for Compute Engine Instances
# ==============================================================================

set -e

# Log all output to startup script log
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting service discovery instance configuration..."
echo "Timestamp: $(date)"
echo "Instance: $(hostname)"
echo "Zone: $(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)"

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get install -y nginx curl jq

# Get instance metadata
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
INSTANCE_ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
SERVICE_NAME="${service_name}"

# Configure nginx as a simple web service
echo "Configuring nginx web service..."

# Create main service endpoint
cat > /var/www/html/index.html << EOF
{
  "service": "$${SERVICE_NAME}",
  "zone": "$${INSTANCE_ZONE}",
  "instance": "$${INSTANCE_NAME}",
  "internal_ip": "$${INTERNAL_IP}",
  "timestamp": "$(date -Iseconds)",
  "status": "healthy",
  "version": "1.0.0",
  "environment": "production"
}
EOF

# Create health check endpoint
cat > /var/www/html/health << EOF
{
  "status": "healthy",
  "timestamp": "$(date -Iseconds)",
  "instance": "$${INSTANCE_NAME}",
  "zone": "$${INSTANCE_ZONE}",
  "uptime": "$(uptime -p)",
  "checks": {
    "nginx": "$(systemctl is-active nginx)",
    "disk_space": "$(df -h / | awk 'NR==2{print $5}')",
    "memory": "$(free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2 }')"
  }
}
EOF

# Create version endpoint
cat > /var/www/html/version << EOF
{
  "service": "$${SERVICE_NAME}",
  "version": "1.0.0",
  "build": "$(date +%Y%m%d-%H%M%S)",
  "instance": "$${INSTANCE_NAME}",
  "zone": "$${INSTANCE_ZONE}"
}
EOF

# Configure nginx to serve JSON with proper content type
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    # Add security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Main service endpoint
    location / {
        add_header Content-Type application/json;
        try_files $uri $uri/ =404;
    }

    # Health check endpoint
    location /health {
        add_header Content-Type application/json;
        try_files $uri =404;
    }

    # Version endpoint
    location /version {
        add_header Content-Type application/json;
        try_files $uri =404;
    }

    # Status endpoint for monitoring
    location /status {
        add_header Content-Type application/json;
        return 200 '{"status":"ok","timestamp":"$time_iso8601"}';
    }
}
EOF

# Enable and start nginx
echo "Starting nginx service..."
systemctl enable nginx
systemctl restart nginx

# Wait for nginx to be ready
sleep 5

# Verify nginx is running and responding
echo "Verifying nginx configuration..."
if curl -f http://localhost/health > /dev/null 2>&1; then
    echo "✅ Nginx health check successful"
else
    echo "❌ Nginx health check failed"
    systemctl status nginx
    exit 1
fi

echo "Service discovery instance configuration completed successfully!"
echo "Instance: $${INSTANCE_NAME}"
echo "Zone: $${INSTANCE_ZONE}"
echo "Service: $${SERVICE_NAME}"
echo "Health check: http://$${INTERNAL_IP}/health"
echo "Timestamp: $(date)"

# Create completion marker
touch /var/log/startup-complete