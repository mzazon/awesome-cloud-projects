#!/bin/bash
# Startup script for security monitoring test VM instance
# This script installs Apache web server and basic monitoring tools

set -e

# Update package list
apt-get update

# Install required packages
apt-get install -y \
    apache2 \
    netcat \
    curl \
    wget \
    htop \
    iptraf-ng \
    tcpdump

# Start and enable Apache web server
systemctl start apache2
systemctl enable apache2

# Create a custom index page for testing
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Security Monitoring Test Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { color: #4285F4; }
        .status { background-color: #E8F5E8; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1 class="header">Security Monitoring Test Server</h1>
    <div class="status">
        <p><strong>Status:</strong> Server is running and generating network traffic for monitoring</p>
        <p><strong>Project ID:</strong> ${project_id}</p>
        <p><strong>Instance:</strong> $(hostname)</p>
        <p><strong>Timestamp:</strong> $(date)</p>
    </div>
    <h2>Network Monitoring Features</h2>
    <ul>
        <li>VPC Flow Logs enabled</li>
        <li>Security Command Center integration</li>
        <li>Cloud Monitoring alerts configured</li>
        <li>BigQuery analytics ready</li>
    </ul>
</body>
</html>
EOF

# Configure Apache to log more detailed information
cat > /etc/apache2/conf-available/security-monitoring.conf << 'EOF'
# Custom logging format for security monitoring
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" %D" security_monitoring
CustomLog /var/log/apache2/security_monitoring.log security_monitoring
EOF

# Enable the custom logging configuration
a2enconf security-monitoring
systemctl reload apache2

# Create a simple monitoring script that generates network activity
cat > /usr/local/bin/generate-test-traffic.sh << 'EOF'
#!/bin/bash
# Generate test network traffic for monitoring validation

echo "Generating test network traffic for security monitoring..."

# Internal connectivity test
ping -c 3 8.8.8.8 > /dev/null 2>&1 || true

# DNS lookups
nslookup google.com > /dev/null 2>&1 || true
nslookup cloudflare.com > /dev/null 2>&1 || true

# HTTP requests to external sites
curl -s --max-time 5 http://www.google.com > /dev/null 2>&1 || true
curl -s --max-time 5 https://www.github.com > /dev/null 2>&1 || true

# Local HTTP requests to generate internal traffic
curl -s http://localhost/ > /dev/null 2>&1 || true

echo "Test traffic generation completed"
EOF

chmod +x /usr/local/bin/generate-test-traffic.sh

# Create a systemd service for periodic traffic generation
cat > /etc/systemd/system/test-traffic-generator.service << 'EOF'
[Unit]
Description=Test Traffic Generator for Security Monitoring
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/generate-test-traffic.sh
User=www-data
EOF

cat > /etc/systemd/system/test-traffic-generator.timer << 'EOF'
[Unit]
Description=Run test traffic generator every 5 minutes
Requires=test-traffic-generator.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# Enable and start the traffic generator timer
systemctl daemon-reload
systemctl enable test-traffic-generator.timer
systemctl start test-traffic-generator.timer

# Install Google Cloud Ops Agent for enhanced monitoring
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure the Ops Agent to collect Apache logs
cat > /etc/google-cloud-ops-agent/config.yaml << 'EOF'
logging:
  receivers:
    apache_access:
      type: apache_access
      include_paths:
        - /var/log/apache2/access.log
        - /var/log/apache2/security_monitoring.log
    apache_error:
      type: apache_error
      include_paths:
        - /var/log/apache2/error.log
    syslog:
      type: files
      include_paths:
        - /var/log/syslog
  service:
    pipelines:
      default_pipeline:
        receivers: [apache_access, apache_error, syslog]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
EOF

# Restart the Ops Agent to pick up the new configuration
systemctl restart google-cloud-ops-agent

# Create a script to simulate various network patterns for testing
cat > /usr/local/bin/simulate-security-events.sh << 'EOF'
#!/bin/bash
# Simulate various network patterns for security monitoring testing

echo "Simulating security monitoring events..."

# Simulate port scanning (safe internal testing)
for port in 21 22 23 25 53 80 110 143 443 993 995; do
    nc -z -w1 localhost $port 2>/dev/null || true
done

# Simulate failed SSH attempts (local only)
echo "Testing SSH connectivity patterns..."
timeout 2 nc -z localhost 22 || true

# Generate some DNS queries
for domain in example.com test.local internal.corp; do
    nslookup $domain 2>/dev/null || true
done

# Test HTTP methods
curl -s -X GET http://localhost/ > /dev/null 2>&1 || true
curl -s -X POST http://localhost/ > /dev/null 2>&1 || true
curl -s -X PUT http://localhost/ > /dev/null 2>&1 || true

echo "Security event simulation completed"
EOF

chmod +x /usr/local/bin/simulate-security-events.sh

# Log the completion of startup script
echo "$(date): Security monitoring test VM startup completed successfully" >> /var/log/startup-script.log

# Generate initial test traffic
/usr/local/bin/generate-test-traffic.sh
/usr/local/bin/simulate-security-events.sh

echo "Security monitoring test VM setup completed successfully"