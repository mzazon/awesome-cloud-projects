#!/bin/bash

# User Data Script for EC2 Instance Monitoring Setup
# This script installs monitoring tools and configures the instance

# Update system packages
yum update -y

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Install stress testing tools for CPU load testing
yum install -y stress-ng htop

# Install Systems Manager agent (should be pre-installed on AL2023)
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

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
                        "file_path": "/var/log/messages",
                        "log_group_name": "${log_group_name}",
                        "log_stream_name": "{instance_id}/var/log/messages",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "${log_group_name}",
                        "log_stream_name": "{instance_id}/var/log/secure",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ],
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
                    "mem_used_percent",
                    "mem_available_percent"
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

# Start CloudWatch agent with the configuration
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable CloudWatch agent to start on boot
systemctl enable amazon-cloudwatch-agent

# Create a simple monitoring script
cat > /home/ec2-user/cpu-stress-test.sh << 'EOF'
#!/bin/bash

echo "Starting CPU stress test..."
echo "This will generate high CPU load for 10 minutes to trigger CloudWatch alarms"
echo "Press Ctrl+C to stop the test early"

# Run stress test for 10 minutes (600 seconds)
stress-ng --cpu 2 --timeout 600s --metrics-brief

echo "CPU stress test completed"
EOF

# Make the script executable
chmod +x /home/ec2-user/cpu-stress-test.sh

# Create a system information script
cat > /home/ec2-user/system-info.sh << 'EOF'
#!/bin/bash

echo "=== System Information ==="
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo ""
echo "=== Current CPU Usage ==="
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1 "%"}'
echo ""
echo "=== Memory Usage ==="
free -h
echo ""
echo "=== Disk Usage ==="
df -h /
echo ""
echo "=== Recent CloudWatch Agent Logs ==="
tail -n 10 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log 2>/dev/null || echo "CloudWatch agent logs not available"
EOF

# Make the script executable
chmod +x /home/ec2-user/system-info.sh

# Create a MOTD (Message of the Day) to display helpful information
cat > /etc/motd << 'EOF'

  ███╗   ███╗ ██████╗ ███╗   ██╗██╗████████╗ ██████╗ ██████╗ ██╗███╗   ██╗ ██████╗ 
  ████╗ ████║██╔═══██╗████╗  ██║██║╚══██╔══╝██╔═══██╗██╔══██╗██║████╗  ██║██╔════╝ 
  ██╔████╔██║██║   ██║██╔██╗ ██║██║   ██║   ██║   ██║██████╔╝██║██╔██╗ ██║██║  ███╗
  ██║╚██╔╝██║██║   ██║██║╚██╗██║██║   ██║   ██║   ██║██╔══██╗██║██║╚██╗██║██║   ██║
  ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██║   ██║   ╚██████╔╝██║  ██║██║██║ ╚████║╚██████╔╝
  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                                                                                     
  📊 Simple Resource Monitoring Demo Instance
  
  Available commands:
  • ./system-info.sh      - Display current system information
  • ./cpu-stress-test.sh  - Generate CPU load to test alarms
  • htop                   - Interactive process viewer
  • stress-ng --help       - CPU stress testing tool help
  
  CloudWatch Monitoring:
  • CPU utilization alarms are configured
  • System status checks are monitored
  • Custom metrics are collected via CloudWatch agent
  
  📧 Check your email for alarm notifications when CPU > 70%
  
EOF

# Set correct ownership for user scripts
chown ec2-user:ec2-user /home/ec2-user/*.sh

# Log completion
echo "$(date): User data script completed successfully" >> /var/log/user-data.log

# Signal that user data is complete
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource MonitoringInstance --region ${AWS::Region} 2>/dev/null || true