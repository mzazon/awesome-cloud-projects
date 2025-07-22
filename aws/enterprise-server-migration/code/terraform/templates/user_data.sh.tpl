#!/bin/bash
# user_data.sh.tpl - User data script template for MGN post-launch actions
# This script runs on migrated instances to perform post-launch configuration

# Exit on any error
set -e

# Variables from Terraform
CLOUDWATCH_LOG_GROUP="${cloudwatch_log_group}"
S3_BUCKET="${s3_bucket}"
S3_PREFIX="${s3_prefix}"
AWS_REGION="${region}"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/mgn-post-launch.log
}

# Function to send logs to CloudWatch (if enabled)
send_to_cloudwatch() {
    if [ -n "$CLOUDWATCH_LOG_GROUP" ]; then
        aws logs put-log-events \
            --log-group-name "$CLOUDWATCH_LOG_GROUP" \
            --log-stream-name "$(hostname)-post-launch" \
            --log-events timestamp=$(date +%s)000,message="$1" \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
}

# Function to upload logs to S3
upload_to_s3() {
    if [ -n "$S3_BUCKET" ]; then
        aws s3 cp /var/log/mgn-post-launch.log \
            "s3://$S3_BUCKET/$S3_PREFIX$(hostname)-post-launch-$(date +%Y%m%d-%H%M%S).log" \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
}

# Start post-launch actions
log_message "Starting MGN post-launch actions on $(hostname)"
send_to_cloudwatch "Starting MGN post-launch actions on $(hostname)"

# Update system packages
log_message "Updating system packages..."
yum update -y || apt-get update -y || true

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    log_message "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
fi

# Install CloudWatch agent if CloudWatch logging is enabled
if [ -n "$CLOUDWATCH_LOG_GROUP" ]; then
    log_message "Installing CloudWatch agent..."
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    rpm -U ./amazon-cloudwatch-agent.rpm || true
    
    # Configure CloudWatch agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/mgn-post-launch.log",
                        "log_group_name": "$CLOUDWATCH_LOG_GROUP",
                        "log_stream_name": "$(hostname)-post-launch"
                    }
                ]
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
        -s || true
fi

# Install Systems Manager agent if not present
if ! systemctl is-active --quiet amazon-ssm-agent; then
    log_message "Installing Systems Manager agent..."
    yum install -y amazon-ssm-agent || snap install amazon-ssm-agent --classic || true
    systemctl enable amazon-ssm-agent || true
    systemctl start amazon-ssm-agent || true
fi

# Configure hostname resolution
log_message "Configuring hostname resolution..."
echo "127.0.0.1 $(hostname)" >> /etc/hosts

# Set timezone to UTC
log_message "Setting timezone to UTC..."
timedatectl set-timezone UTC || true

# Configure NTP for time synchronization
log_message "Configuring NTP synchronization..."
yum install -y ntp || apt-get install -y ntp || true
systemctl enable ntpd || systemctl enable ntp || true
systemctl start ntpd || systemctl start ntp || true

# Configure log rotation for MGN logs
log_message "Configuring log rotation..."
cat > /etc/logrotate.d/mgn-post-launch << EOF
/var/log/mgn-post-launch.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Run instance-specific post-launch actions
log_message "Running instance-specific configurations..."

# Check if this is a web server (example - customize as needed)
if systemctl is-active --quiet httpd || systemctl is-active --quiet apache2 || systemctl is-active --quiet nginx; then
    log_message "Web server detected - applying web server configurations..."
    # Add web server specific configurations here
fi

# Check if this is a database server (example - customize as needed)
if systemctl is-active --quiet mysqld || systemctl is-active --quiet postgresql || systemctl is-active --quiet mariadb; then
    log_message "Database server detected - applying database configurations..."
    # Add database specific configurations here
fi

# Configure security settings
log_message "Applying security configurations..."

# Disable root login via SSH if enabled
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config || true
    systemctl restart sshd || true
fi

# Configure firewall (basic example)
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=ssh || true
    firewall-cmd --reload || true
fi

# Set up monitoring and alerting
log_message "Setting up monitoring and alerting..."

# Create a health check script
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Basic health check script for migrated instances

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "WARNING: Disk usage is at $DISK_USAGE%"
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEM_USAGE -gt 80 ]; then
    echo "WARNING: Memory usage is at $MEM_USAGE%"
fi

# Check system load
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
if [ $(echo "$LOAD_AVG > 2.0" | bc -l) ]; then
    echo "WARNING: System load is high: $LOAD_AVG"
fi

echo "Health check completed at $(date)"
EOF

chmod +x /usr/local/bin/health-check.sh

# Set up cron job for health checks
echo "*/5 * * * * root /usr/local/bin/health-check.sh >> /var/log/health-check.log 2>&1" >> /etc/crontab

# Final steps
log_message "Performing final post-launch configurations..."

# Upload final logs to S3
upload_to_s3

# Send completion notification
log_message "MGN post-launch actions completed successfully on $(hostname)"
send_to_cloudwatch "MGN post-launch actions completed successfully on $(hostname)"

# Create completion marker file
echo "$(date): MGN post-launch actions completed" > /var/log/mgn-post-launch-complete.marker

log_message "Post-launch script execution finished"