#!/bin/bash
# ==============================================================================
# Service Discovery Startup Script for Compute Engine Instances
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
  "service": "${SERVICE_NAME}",
  "zone": "${INSTANCE_ZONE}",
  "instance": "${INSTANCE_NAME}",
  "internal_ip": "${INTERNAL_IP}",
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
  "instance": "${INSTANCE_NAME}",
  "zone": "${INSTANCE_ZONE}",
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
  "service": "${SERVICE_NAME}",
  "version": "1.0.0",
  "build": "$(date +%Y%m%d-%H%M%S)",
  "instance": "${INSTANCE_NAME}",
  "zone": "${INSTANCE_ZONE}"
}
EOF

# Create info endpoint with detailed instance information
cat > /var/www/html/info << EOF
{
  "service": "${SERVICE_NAME}",
  "instance": "${INSTANCE_NAME}",
  "zone": "${INSTANCE_ZONE}",
  "internal_ip": "${INTERNAL_IP}",
  "machine_type": "$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/machine-type | cut -d/ -f4)",
  "cpu_platform": "$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/cpu-platform)",
  "image": "$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/image | cut -d/ -f5)",
  "startup_time": "$(date -Iseconds)",
  "uptime": "$(uptime -p)"
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

    # Info endpoint
    location /info {
        add_header Content-Type application/json;
        try_files $uri =404;
    }

    # Metrics endpoint (simple)
    location /metrics {
        add_header Content-Type text/plain;
        return 200 "# HELP nginx_requests_total Total requests\n# TYPE nginx_requests_total counter\nnginx_requests_total 1\n";
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

# Create log rotation for nginx
cat > /etc/logrotate.d/nginx-service << EOF
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi \
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF

# Create monitoring script for ongoing health checks
cat > /usr/local/bin/health-monitor.sh << 'EOF'
#!/bin/bash
# Health monitoring script for service discovery

LOG_FILE="/var/log/health-monitor.log"
HEALTH_URL="http://localhost/health"

while true; do
    if curl -f "$HEALTH_URL" > /dev/null 2>&1; then
        echo "$(date): Health check passed" >> "$LOG_FILE"
    else
        echo "$(date): Health check failed - restarting nginx" >> "$LOG_FILE"
        systemctl restart nginx
    fi
    sleep 30
done
EOF

chmod +x /usr/local/bin/health-monitor.sh

# Create systemd service for health monitoring
cat > /etc/systemd/system/health-monitor.service << EOF
[Unit]
Description=Health Monitor for Service Discovery
After=nginx.service
Wants=nginx.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/health-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable health monitoring service
systemctl daemon-reload
systemctl enable health-monitor.service
systemctl start health-monitor.service

# Install and configure Envoy proxy for advanced service mesh features (optional)
echo "Installing Envoy proxy for service mesh capabilities..."
curl -L https://getenvoy.io/install.sh | bash -s -- -b /usr/local/bin
/usr/local/bin/envoy --version || echo "Envoy installation failed, continuing without it"

# Create simple Envoy configuration for future use
mkdir -p /etc/envoy
cat > /etc/envoy/envoy.yaml << EOF
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901

static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: service_cluster
          http_filters:
          - name: envoy.filters.http.router
  clusters:
  - name: service_cluster
    connect_timeout: 30s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: service_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 80
EOF

# Set up firewall rules (if ufw is available)
if command -v ufw >/dev/null 2>&1; then
    echo "Configuring UFW firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 8080/tcp
    ufw allow 9901/tcp
    ufw --force enable
fi

# Final health check and status report
echo "Performing final health checks..."

# Test all endpoints
echo "Testing service endpoints:"
for endpoint in "/" "/health" "/version" "/info" "/status"; do
    if curl -f "http://localhost${endpoint}" > /dev/null 2>&1; then
        echo "✅ ${endpoint} - OK"
    else
        echo "❌ ${endpoint} - FAILED"
    fi
done

# Check services
echo "Checking service status:"
for service in nginx health-monitor; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ ${service} - ACTIVE"
    else
        echo "❌ ${service} - INACTIVE"
    fi
done

echo "Service discovery instance configuration completed successfully!"
echo "Instance: ${INSTANCE_NAME}"
echo "Zone: ${INSTANCE_ZONE}"
echo "Service: ${SERVICE_NAME}"
echo "Health check: http://${INTERNAL_IP}/health"
echo "Service info: http://${INTERNAL_IP}/info"
echo "Timestamp: $(date)"

# Create completion marker
touch /var/log/startup-complete