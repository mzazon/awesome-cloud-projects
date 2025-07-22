#!/bin/bash
# User data script for EC2 instances in global load balancing demo
# This script installs and configures a simple web application

# Update system packages
yum update -y

# Install Apache HTTP Server
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create simple web application
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Global Load Balancer Demo</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            padding: 50px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            margin: 0;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
            backdrop-filter: blur(4px);
            border: 1px solid rgba(255, 255, 255, 0.18);
            margin: 20px auto;
            max-width: 800px;
        }
        .region { 
            background: rgba(255,255,255,0.2);
            padding: 20px; 
            border-radius: 10px; 
            margin: 20px auto; 
            max-width: 600px;
        }
        .healthy { 
            color: #4caf50; 
            font-weight: bold; 
            font-size: 18px;
        }
        .metadata {
            background: rgba(0,0,0,0.2);
            padding: 15px;
            border-radius: 8px;
            margin: 10px 0;
            font-family: monospace;
        }
        .timestamp {
            font-size: 12px;
            opacity: 0.8;
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
    </style>
    <script>
        function updateTimestamp() {
            document.getElementById('timestamp').innerHTML = new Date().toLocaleString();
        }
        setInterval(updateTimestamp, 1000);
        window.onload = updateTimestamp;
    </script>
</head>
<body>
    <div class="container">
        <h1>🌍 Global Load Balancer Demo</h1>
        <div class="region">
            <h2>Hello from ${region}!</h2>
            <p class="healthy">✅ Status: Healthy</p>
            
            <div class="metadata">
                <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
                <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
                <p><strong>Region:</strong> ${region}</p>
                <p><strong>Public IP:</strong> <span id="public-ip">Loading...</span></p>
                <p><strong>Private IP:</strong> <span id="private-ip">Loading...</span></p>
            </div>
            
            <div class="timestamp">
                <p><strong>Current Time:</strong> <span id="timestamp"></span></p>
                <p><strong>Server Time:</strong> $(date)</p>
            </div>
        </div>
        
        <div style="margin-top: 30px; font-size: 14px; opacity: 0.8;">
            <p>This instance is part of a global load balancing demonstration using:</p>
            <p>Route53 Health Checks • CloudFront Distribution • Application Load Balancer</p>
        </div>
    </div>

    <script>
        // Fetch instance metadata
        function fetchMetadata() {
            fetch('http://169.254.169.254/latest/meta-data/instance-id')
                .then(response => response.text())
                .then(data => document.getElementById('instance-id').innerHTML = data)
                .catch(error => document.getElementById('instance-id').innerHTML = 'Unable to fetch');
                
            fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
                .then(response => response.text())
                .then(data => document.getElementById('az').innerHTML = data)
                .catch(error => document.getElementById('az').innerHTML = 'Unable to fetch');
                
            fetch('http://169.254.169.254/latest/meta-data/public-ipv4')
                .then(response => response.text())
                .then(data => document.getElementById('public-ip').innerHTML = data)
                .catch(error => document.getElementById('public-ip').innerHTML = 'N/A');
                
            fetch('http://169.254.169.254/latest/meta-data/local-ipv4')
                .then(response => response.text())
                .then(data => document.getElementById('private-ip').innerHTML = data)
                .catch(error => document.getElementById('private-ip').innerHTML = 'Unable to fetch');
        }
        
        // Only fetch metadata if we're actually on an EC2 instance
        if (window.location.protocol === 'http:' || window.location.protocol === 'https:') {
            fetchMetadata();
        }
    </script>
</body>
</html>
EOF

# Create health check endpoint (JSON format)
cat > /var/www/html${health_check_path} << 'EOF'
{
    "status": "healthy",
    "region": "${region}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')",
    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'unknown')",
    "public_ip": "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'none')",
    "private_ip": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo 'unknown')",
    "server_time": "$(date)",
    "uptime": "$(uptime | awk '{print $3,$4}' | sed 's/,//')",
    "load_average": "$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1,$2,$3}' | sed 's/,//g')"
}
EOF

# Make health endpoint executable and set proper content type
echo "AddType application/json .health" >> /etc/httpd/conf/httpd.conf

# Create a dynamic health endpoint that updates in real-time
cat > /var/www/html/health-dynamic << 'EOF'
#!/bin/bash
echo "Content-Type: application/json"
echo ""
cat << JSON
{
    "status": "healthy",
    "region": "${region}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')",
    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'unknown')",
    "public_ip": "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'none')",
    "private_ip": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo 'unknown')",
    "server_time": "$(date)",
    "uptime": "$(uptime | awk '{print $3,$4}' | sed 's/,//')",
    "load_average": "$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1,$2,$3}' | sed 's/,//g')",
    "memory_usage": "$(free -m | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')",
    "disk_usage": "$(df -h / | awk 'NR==2{printf "%s", $5}')",
    "connections": "$(netstat -an | grep :80 | wc -l)"
}
JSON
EOF

chmod +x /var/www/html/health-dynamic

# Configure Apache to serve health-dynamic as CGI
echo "ScriptAlias /health-live /var/www/html/health-dynamic" >> /etc/httpd/conf/httpd.conf

# Install CloudWatch agent for monitoring
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent config
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "GlobalLoadBalancer/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "/aws/ec2/global-lb/apache/access",
                        "log_stream_name": "{instance_id}-${region}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/ec2/global-lb/apache/error",
                        "log_stream_name": "{instance_id}-${region}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable detailed monitoring for HTTP requests
cat > /etc/httpd/conf.d/monitoring.conf << 'EOF'
# Log format for detailed monitoring
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" %D" detailed
CustomLog logs/access_log detailed

# Server status page (for monitoring)
<Location "/server-status">
    SetHandler server-status
    Require ip 127.0.0.1
    Require ip 10.0.0.0/8
    Require ip 172.16.0.0/12
    Require ip 192.168.0.0/16
</Location>
ExtendedStatus On

# Server info page (for debugging)
<Location "/server-info">
    SetHandler server-info
    Require ip 127.0.0.1
    Require ip 10.0.0.0/8
    Require ip 172.16.0.0/12
    Require ip 192.168.0.0/16
</Location>
EOF

# Restart Apache to apply all configurations
systemctl restart httpd

# Create a simple monitoring script
cat > /usr/local/bin/health-monitor.sh << 'EOF'
#!/bin/bash
# Simple health monitoring script

LOG_FILE="/var/log/health-monitor.log"

while true; do
    # Check Apache status
    if systemctl is-active --quiet httpd; then
        APACHE_STATUS="healthy"
    else
        APACHE_STATUS="unhealthy"
        systemctl restart httpd
    fi
    
    # Check disk space
    DISK_USAGE=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
    if [ $DISK_USAGE -gt 90 ]; then
        DISK_STATUS="warning"
    else
        DISK_STATUS="healthy"
    fi
    
    # Log status
    echo "$(date): Apache: $APACHE_STATUS, Disk: $DISK_STATUS ($DISK_USAGE%)" >> $LOG_FILE
    
    # Sleep for 30 seconds
    sleep 30
done
EOF

chmod +x /usr/local/bin/health-monitor.sh

# Create systemd service for health monitoring
cat > /etc/systemd/system/health-monitor.service << 'EOF'
[Unit]
Description=Health Monitor Service
After=httpd.service
Requires=httpd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/health-monitor.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the health monitor service
systemctl daemon-reload
systemctl enable health-monitor
systemctl start health-monitor

# Log completion
echo "$(date): User data script completed successfully" >> /var/log/user-data.log
echo "Instance is ready for global load balancing in region: ${region}" >> /var/log/user-data.log