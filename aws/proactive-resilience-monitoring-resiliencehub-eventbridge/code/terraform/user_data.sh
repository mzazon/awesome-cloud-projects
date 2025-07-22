#!/bin/bash

# User data script for EC2 instance setup
# This script configures the instance with necessary components for resilience monitoring

# Set variables
REGION="${region}"
LOG_FILE="/var/log/user-data.log"

# Redirect all output to log file
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "Starting user data script execution at $(date)"

# Update system packages
echo "Updating system packages..."
yum update -y

# Install essential packages
echo "Installing essential packages..."
yum install -y \
    wget \
    curl \
    htop \
    net-tools \
    telnet \
    nc \
    mysql \
    jq \
    unzip

# Install and configure CloudWatch agent
echo "Installing CloudWatch agent..."
yum install -y amazon-cloudwatch-agent

# Download CloudWatch agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "ResilienceDemo/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": true
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
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
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
                        "file_path": "/var/log/messages",
                        "log_group_name": "ResilienceDemo/var/log/messages",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "ResilienceDemo/var/log/secure",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "ResilienceDemo/user-data",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
echo "Starting CloudWatch agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Enable CloudWatch agent to start on boot
systemctl enable amazon-cloudwatch-agent

# Install and configure collectd for additional system metrics
echo "Installing collectd..."
yum install -y collectd

# Configure collectd
cat > /etc/collectd.conf << 'EOF'
Hostname "localhost"
FQDNLookup true
Interval 60
Timeout 2
ReadThreads 5
WriteThreads 5

LoadPlugin cpu
LoadPlugin df
LoadPlugin disk
LoadPlugin interface
LoadPlugin load
LoadPlugin memory
LoadPlugin network
LoadPlugin processes
LoadPlugin swap
LoadPlugin uptime

<Plugin df>
    Device "/dev/xvda1"
    MountPoint "/"
    FSType "ext4"
    IgnoreSelected false
    ReportReserved true
    ReportInodes true
</Plugin>

<Plugin disk>
    Disk "/^[hsv]d[a-z]$/"
    IgnoreSelected false
</Plugin>

<Plugin interface>
    Interface "eth0"
    IgnoreSelected false
</Plugin>

<Plugin processes>
    ProcessMatch "httpd" "httpd"
    ProcessMatch "sshd" "sshd"
    ProcessMatch "cloudwatch" "amazon-cloudwatch-agent"
    ProcessMatch "ssm" "amazon-ssm-agent"
</Plugin>
EOF

# Start and enable collectd
systemctl start collectd
systemctl enable collectd

# Install Apache web server for demo application
echo "Installing Apache web server..."
yum install -y httpd

# Create a simple demo web application
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resilience Monitoring Demo Application</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #232F3E;
            border-bottom: 3px solid #FF9900;
            padding-bottom: 10px;
        }
        .status {
            background-color: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            border: 1px solid #c3e6cb;
        }
        .info {
            background-color: #d1ecf1;
            color: #0c5460;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            border: 1px solid #bee5eb;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .metric-card {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            border: 1px solid #dee2e6;
            text-align: center;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
        }
        .metric-label {
            color: #6c757d;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ AWS Resilience Monitoring Demo</h1>
        
        <div class="status">
            <strong>✅ Application Status:</strong> Running and monitored by AWS Resilience Hub
        </div>
        
        <div class="info">
            <strong>ℹ️ About:</strong> This is a demo application for testing AWS Resilience Hub 
            proactive monitoring capabilities with EventBridge automation.
        </div>
        
        <h2>📊 Application Metrics</h2>
        <div class="metrics">
            <div class="metric-card">
                <div class="metric-value" id="uptime">--</div>
                <div class="metric-label">Uptime (minutes)</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" id="timestamp">--</div>
                <div class="metric-label">Last Check</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">Multi-AZ</div>
                <div class="metric-label">RDS Deployment</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">Encrypted</div>
                <div class="metric-label">Data Protection</div>
            </div>
        </div>
        
        <h2>🔧 Resilience Features</h2>
        <ul>
            <li><strong>AWS Resilience Hub:</strong> Continuous resilience assessment</li>
            <li><strong>EventBridge:</strong> Real-time event processing</li>
            <li><strong>Lambda:</strong> Automated response to resilience events</li>
            <li><strong>CloudWatch:</strong> Comprehensive monitoring and alerting</li>
            <li><strong>Multi-AZ RDS:</strong> Database high availability</li>
            <li><strong>Encrypted Storage:</strong> Data protection at rest</li>
            <li><strong>SNS Notifications:</strong> Proactive alerting</li>
        </ul>
        
        <h2>📈 Monitoring Dashboard</h2>
        <p>View real-time resilience metrics and alerts in the CloudWatch dashboard.</p>
        
        <div class="info">
            <strong>🚀 Next Steps:</strong> Register this application with AWS Resilience Hub 
            and configure resilience policies to enable automated monitoring and response.
        </div>
    </div>
    
    <script>
        // Simple JavaScript to show current time and basic uptime simulation
        function updateMetrics() {
            const now = new Date();
            const uptimeMinutes = Math.floor((now.getTime() - performance.timeOrigin) / 60000);
            
            document.getElementById('uptime').textContent = uptimeMinutes;
            document.getElementById('timestamp').textContent = now.toLocaleTimeString();
        }
        
        // Update metrics every 30 seconds
        updateMetrics();
        setInterval(updateMetrics, 30000);
    </script>
</body>
</html>
EOF

# Create health check endpoint
cat > /var/www/html/health << 'EOF'
{
    "status": "healthy",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "service": "resilience-demo-app",
    "version": "1.0.0",
    "checks": {
        "database": "connected",
        "filesystem": "healthy",
        "memory": "normal"
    }
}
EOF

# Create a simple API endpoint for health checks
cat > /var/www/html/api.php << 'EOF'
<?php
header('Content-Type: application/json');

$endpoint = $_SERVER['REQUEST_URI'];

switch($endpoint) {
    case '/api.php?health':
        echo json_encode([
            'status' => 'healthy',
            'timestamp' => date('c'),
            'service' => 'resilience-demo-app',
            'version' => '1.0.0',
            'uptime' => round(microtime(true) - $_SERVER['REQUEST_TIME_FLOAT'], 2),
            'server' => [
                'hostname' => gethostname(),
                'php_version' => phpversion(),
                'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'unknown'
            ]
        ], JSON_PRETTY_PRINT);
        break;
        
    case '/api.php?metrics':
        echo json_encode([
            'cpu_usage' => sys_getloadavg()[0] ?? 0,
            'memory_usage' => round(memory_get_usage(true) / 1024 / 1024, 2),
            'disk_free' => round(disk_free_space('/') / 1024 / 1024 / 1024, 2),
            'connections' => 1,
            'timestamp' => date('c')
        ], JSON_PRETTY_PRINT);
        break;
        
    default:
        http_response_code(404);
        echo json_encode(['error' => 'Endpoint not found']);
}
?>
EOF

# Install PHP for API endpoints
yum install -y php

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Configure firewall (if enabled)
if systemctl is-active --quiet firewalld; then
    echo "Configuring firewall..."
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
fi

# Install AWS CLI v2 (latest version)
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create a script for manual resilience testing
cat > /usr/local/bin/test-resilience.sh << 'EOF'
#!/bin/bash

# Simple script to test application resilience
echo "=== Resilience Test Script ==="
echo "Testing application components..."

# Test web server
echo -n "Web server: "
if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200"; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test health endpoint
echo -n "Health endpoint: "
if curl -s http://localhost/health | grep -q "healthy"; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test CloudWatch agent
echo -n "CloudWatch agent: "
if systemctl is-active --quiet amazon-cloudwatch-agent; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test SSM agent
echo -n "SSM agent: "
if systemctl is-active --quiet amazon-ssm-agent; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Check disk space
echo -n "Disk space: "
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 90 ]; then
    echo "✅ OK ($DISK_USAGE% used)"
else
    echo "⚠️  WARNING ($DISK_USAGE% used)"
fi

# Check memory usage
echo -n "Memory usage: "
MEM_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
if [ "$MEM_USAGE" -lt 90 ]; then
    echo "✅ OK ($MEM_USAGE% used)"
else
    echo "⚠️  WARNING ($MEM_USAGE% used)"
fi

echo "=== Test Complete ==="
EOF

chmod +x /usr/local/bin/test-resilience.sh

# Create log rotation for application logs
cat > /etc/logrotate.d/resilience-demo << 'EOF'
/var/log/resilience-demo/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 apache apache
    postrotate
        systemctl reload httpd > /dev/null 2>&1 || true
    endscript
}
EOF

# Create application log directory
mkdir -p /var/log/resilience-demo
chown apache:apache /var/log/resilience-demo

# Set up cron job for health checks
cat > /etc/cron.d/resilience-health << 'EOF'
# Health check every 5 minutes
*/5 * * * * apache /usr/local/bin/test-resilience.sh >> /var/log/resilience-demo/health-check.log 2>&1

# Send CloudWatch custom metric every minute
* * * * * root /usr/local/bin/send-custom-metrics.sh >> /var/log/resilience-demo/metrics.log 2>&1
EOF

# Create custom metrics script
cat > /usr/local/bin/send-custom-metrics.sh << EOF
#!/bin/bash

# Send custom metrics to CloudWatch
REGION="${region}"
INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Get system metrics
CPU_USAGE=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | sed 's/%us,//')
MEM_USAGE=\$(free | awk 'NR==2{printf "%.1f", \$3*100/\$2}')
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')

# Send metrics to CloudWatch
aws cloudwatch put-metric-data \
    --region \$REGION \
    --namespace "ResilienceDemo/Application" \
    --metric-data \
    MetricName=CPUUtilization,Value=\$CPU_USAGE,Unit=Percent,Dimensions=InstanceId=\$INSTANCE_ID \
    MetricName=MemoryUtilization,Value=\$MEM_USAGE,Unit=Percent,Dimensions=InstanceId=\$INSTANCE_ID \
    MetricName=DiskUtilization,Value=\$DISK_USAGE,Unit=Percent,Dimensions=InstanceId=\$INSTANCE_ID \
    > /dev/null 2>&1
EOF

chmod +x /usr/local/bin/send-custom-metrics.sh

# Final system optimization
echo "Performing final system optimization..."

# Update system limits
cat >> /etc/security/limits.conf << 'EOF'
# Resilience demo application limits
apache soft nofile 65536
apache hard nofile 65536
apache soft nproc 4096
apache hard nproc 4096
EOF

# Optimize kernel parameters
cat >> /etc/sysctl.conf << 'EOF'
# Network optimizations for resilience demo
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = cubic
EOF

sysctl -p

# Ensure all services are running
echo "Starting and enabling services..."
systemctl restart httpd
systemctl restart amazon-cloudwatch-agent
systemctl restart amazon-ssm-agent

# Create completion marker
touch /var/log/user-data-complete
echo "User data script completed successfully at $(date)"

# Send notification that instance is ready
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws cloudwatch put-metric-data \
    --region $REGION \
    --namespace "ResilienceDemo/Deployment" \
    --metric-data MetricName=InstanceInitialized,Value=1,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID

echo "=== EC2 Instance Setup Complete ==="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "Web Server: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/"
echo "Health Check: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/health"
echo "Test Script: /usr/local/bin/test-resilience.sh"
EOF