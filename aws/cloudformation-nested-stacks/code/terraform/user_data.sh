#!/bin/bash

# ==============================================================================
# EC2 Instance User Data Script
# This script configures EC2 instances with web server, monitoring, and
# application-specific setup for the nested stacks demonstration.
# ==============================================================================

set -e

# ==============================================================================
# Variables and Environment Setup
# ==============================================================================

# Template variables (substituted by Terraform)
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"

# System configuration
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "Starting user data script execution at $(date)"
echo "Environment: $ENVIRONMENT"
echo "Project: $PROJECT_NAME"

# ==============================================================================
# System Updates and Package Installation
# ==============================================================================

echo "Updating system packages..."
yum update -y

echo "Installing required packages..."
yum install -y \
    httpd \
    amazon-cloudwatch-agent \
    awslogs \
    curl \
    wget \
    unzip \
    htop \
    tree \
    jq

# ==============================================================================
# Web Server Configuration
# ==============================================================================

echo "Configuring Apache web server..."

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
LOCAL_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "N/A")
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Create main application page
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$PROJECT_NAME - $ENVIRONMENT</title>
    <style>
        body {
            font-family: 'Arial', sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        h1 {
            text-align: center;
            color: #fff;
            margin-bottom: 30px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .status {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .info-item {
            background: rgba(255, 255, 255, 0.15);
            padding: 15px;
            border-radius: 8px;
        }
        .label {
            font-weight: bold;
            color: #e0e0e0;
            font-size: 0.9em;
        }
        .value {
            font-size: 1.1em;
            margin-top: 5px;
        }
        .health-status {
            text-align: center;
            font-size: 1.2em;
            font-weight: bold;
            color: #4CAF50;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 $PROJECT_NAME Application</h1>
        
        <div class="status">
            <div class="health-status">✅ Application is Running Successfully</div>
        </div>
        
        <div class="info-grid">
            <div class="info-item">
                <div class="label">Environment</div>
                <div class="value">$ENVIRONMENT</div>
            </div>
            <div class="info-item">
                <div class="label">Instance ID</div>
                <div class="value">$INSTANCE_ID</div>
            </div>
            <div class="info-item">
                <div class="label">Instance Type</div>
                <div class="value">$INSTANCE_TYPE</div>
            </div>
            <div class="info-item">
                <div class="label">Availability Zone</div>
                <div class="value">$AVAILABILITY_ZONE</div>
            </div>
            <div class="info-item">
                <div class="label">Region</div>
                <div class="value">$REGION</div>
            </div>
            <div class="info-item">
                <div class="label">Private IP</div>
                <div class="value">$LOCAL_IPV4</div>
            </div>
            <div class="info-item">
                <div class="label">Public IP</div>
                <div class="value">$PUBLIC_IPV4</div>
            </div>
            <div class="info-item">
                <div class="label">Deployment Time</div>
                <div class="value">$(date)</div>
            </div>
        </div>
        
        <div class="status">
            <h3>Architecture Overview</h3>
            <p>This application demonstrates a modular multi-tier architecture equivalent to CloudFormation nested stacks:</p>
            <ul>
                <li><strong>Network Layer:</strong> VPC with public/private subnets across multiple AZs</li>
                <li><strong>Security Layer:</strong> IAM roles and security groups with least privilege access</li>
                <li><strong>Application Layer:</strong> Auto Scaling Groups with Application Load Balancer</li>
                <li><strong>Database Layer:</strong> RDS MySQL with enhanced monitoring and backups</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

# Create health check endpoint
echo 'OK' > /var/www/html/health

# Create application info endpoint for monitoring
cat > /var/www/html/info << EOF
{
  "status": "healthy",
  "environment": "$ENVIRONMENT",
  "project": "$PROJECT_NAME",
  "instance_id": "$INSTANCE_ID",
  "instance_type": "$INSTANCE_TYPE",
  "availability_zone": "$AVAILABILITY_ZONE",
  "region": "$REGION",
  "local_ipv4": "$LOCAL_IPV4",
  "public_ipv4": "$PUBLIC_IPV4",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "uptime": "$(uptime -p)"
}
EOF

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 644 /var/www/html

echo "Web server configuration completed"

# ==============================================================================
# CloudWatch Agent Configuration
# ==============================================================================

echo "Configuring CloudWatch agent..."

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT/httpd/access",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC",
            "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT/httpd/error",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/ec2/$PROJECT_NAME-$ENVIRONMENT/system/user-data",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "$PROJECT_NAME/$ENVIRONMENT",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
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
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

echo "CloudWatch agent configuration completed"

# ==============================================================================
# System Service Configuration
# ==============================================================================

echo "Configuring system services..."

# Enable and start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Configure log rotation for application logs
cat > /etc/logrotate.d/webapp << EOF
/var/log/webapp/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 apache apache
}
EOF

# Create application log directory
mkdir -p /var/log/webapp
chown apache:apache /var/log/webapp

echo "System service configuration completed"

# ==============================================================================
# Security Hardening
# ==============================================================================

echo "Applying security hardening..."

# Update file permissions
chmod 644 /var/www/html/*
chown -R apache:apache /var/www/html

# Configure firewall (basic iptables rules)
# Note: Security groups provide primary network security
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Save iptables rules
service iptables save

echo "Security hardening completed"

# ==============================================================================
# Application Health Monitoring
# ==============================================================================

echo "Setting up health monitoring..."

# Create health check script
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash

# Health check script for application monitoring
HEALTH_FILE="/var/www/html/health"
STATUS_FILE="/var/www/html/status"
LOG_FILE="/var/log/webapp/health-check.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Check if Apache is running
if systemctl is-active --quiet httpd; then
    APACHE_STATUS="healthy"
else
    APACHE_STATUS="unhealthy"
fi

# Check disk space (alert if > 80%)
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    DISK_STATUS="warning"
else
    DISK_STATUS="healthy"
fi

# Check memory usage
MEM_USAGE=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
if (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
    MEM_STATUS="warning"
else
    MEM_STATUS="healthy"
fi

# Update health status
if [ "$APACHE_STATUS" = "healthy" ] && [ "$DISK_STATUS" = "healthy" ]; then
    echo "OK" > $HEALTH_FILE
    OVERALL_STATUS="healthy"
else
    echo "DEGRADED" > $HEALTH_FILE
    OVERALL_STATUS="degraded"
fi

# Create detailed status report
cat > $STATUS_FILE << EOL
{
  "overall_status": "$OVERALL_STATUS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checks": {
    "apache": "$APACHE_STATUS",
    "disk_usage": {
      "status": "$DISK_STATUS",
      "usage_percent": $DISK_USAGE
    },
    "memory_usage": {
      "status": "$MEM_STATUS", 
      "usage_percent": $MEM_USAGE
    }
  },
  "instance_info": {
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
    "uptime": "$(uptime -p)"
  }
}
EOL

log_message "Health check completed - Status: $OVERALL_STATUS"
EOF

chmod +x /usr/local/bin/health-check.sh

# Set up health check cron job (every 5 minutes)
echo "*/5 * * * * /usr/local/bin/health-check.sh" | crontab -

# Run initial health check
/usr/local/bin/health-check.sh

echo "Health monitoring setup completed"

# ==============================================================================
# Final Configuration and Cleanup
# ==============================================================================

echo "Performing final configuration..."

# Create application startup script
cat > /usr/local/bin/webapp-startup.sh << EOF
#!/bin/bash

# Application startup script
echo "Starting $PROJECT_NAME application..."

# Ensure Apache is running
systemctl start httpd

# Ensure CloudWatch agent is running
systemctl start amazon-cloudwatch-agent

# Run health check
/usr/local/bin/health-check.sh

echo "$PROJECT_NAME application startup completed"
EOF

chmod +x /usr/local/bin/webapp-startup.sh

# Add startup script to rc.local for boot-time execution
echo "/usr/local/bin/webapp-startup.sh" >> /etc/rc.local
chmod +x /etc/rc.local

# Clean up package cache
yum clean all

# Update system clock
ntpdate -s time.nist.gov

echo "User data script execution completed successfully at $(date)"
echo "Application is ready and accessible"

# ==============================================================================
# Signal Completion
# ==============================================================================

# Signal that user data execution is complete
touch /var/log/user-data-complete

# Log final status
echo "=== User Data Execution Summary ===" >> $LOG_FILE
echo "Environment: $ENVIRONMENT" >> $LOG_FILE
echo "Project: $PROJECT_NAME" >> $LOG_FILE
echo "Instance ID: $INSTANCE_ID" >> $LOG_FILE
echo "Instance Type: $INSTANCE_TYPE" >> $LOG_FILE
echo "Completion Time: $(date)" >> $LOG_FILE
echo "Status: SUCCESS" >> $LOG_FILE
echo "=====================================" >> $LOG_FILE

exit 0