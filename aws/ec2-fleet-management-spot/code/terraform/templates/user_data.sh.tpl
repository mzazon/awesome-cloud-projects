#!/bin/bash
# User data script for EC2 Fleet Management instances
# This script configures a simple web server to demonstrate fleet functionality

# Update the system
yum update -y

# Install Apache web server
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create a simple HTML page with instance information
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>EC2 Fleet Instance</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #FF9900;
            text-align: center;
        }
        .info-box {
            background-color: #f8f9fa;
            padding: 15px;
            margin: 10px 0;
            border-left: 4px solid #FF9900;
        }
        .label {
            font-weight: bold;
            color: #232F3E;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 EC2 Fleet Instance</h1>
        <p>This instance is part of the <strong>${project_name}</strong> demonstration.</p>
        
        <div class="info-box">
            <div class="label">Instance ID:</div>
            <div id="instance-id">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Instance Type:</div>
            <div id="instance-type">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Availability Zone:</div>
            <div id="availability-zone">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Local IP Address:</div>
            <div id="local-ip">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Public IP Address:</div>
            <div id="public-ip">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Region:</div>
            <div id="region">Loading...</div>
        </div>
        
        <div class="info-box">
            <div class="label">Launch Time:</div>
            <div id="launch-time">Loading...</div>
        </div>
    </div>
    
    <script>
        // Function to fetch metadata from AWS instance metadata service
        async function fetchMetadata(endpoint) {
            try {
                const response = await fetch(`http://169.254.169.254/latest/meta-data/${endpoint}`);
                return response.ok ? await response.text() : 'Not available';
            } catch (error) {
                return 'Error fetching data';
            }
        }
        
        // Function to update all instance information
        async function updateInstanceInfo() {
            document.getElementById('instance-id').textContent = await fetchMetadata('instance-id');
            document.getElementById('instance-type').textContent = await fetchMetadata('instance-type');
            document.getElementById('availability-zone').textContent = await fetchMetadata('placement/availability-zone');
            document.getElementById('local-ip').textContent = await fetchMetadata('local-ipv4');
            document.getElementById('public-ip').textContent = await fetchMetadata('public-ipv4');
            document.getElementById('region').textContent = await fetchMetadata('placement/region');
            
            // Get launch time from instance metadata
            const launchTime = await fetchMetadata('instance-life-cycle');
            document.getElementById('launch-time').textContent = new Date().toLocaleString();
        }
        
        // Update instance information when page loads
        window.onload = updateInstanceInfo;
        
        // Refresh information every 30 seconds
        setInterval(updateInstanceInfo, 30000);
    </script>
</body>
</html>
EOF

# Create a simple API endpoint for health checks
cat > /var/www/html/health << 'EOF'
{
    "status": "healthy",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
    "instance_type": "$(curl -s http://169.254.169.254/latest/meta-data/instance-type)",
    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
}
EOF

# Create a simple script to update the health endpoint
cat > /usr/local/bin/update-health.sh << 'EOF'
#!/bin/bash
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > /var/www/html/health << EOL
{
    "status": "healthy",
    "timestamp": "${TIMESTAMP}",
    "instance_id": "${INSTANCE_ID}",
    "instance_type": "${INSTANCE_TYPE}",
    "availability_zone": "${AZ}",
    "uptime": "$(uptime -p)"
}
EOL
EOF

chmod +x /usr/local/bin/update-health.sh

# Create a cron job to update health status every minute
echo "* * * * * /usr/local/bin/update-health.sh" | crontab -

# Install and configure CloudWatch agent for monitoring
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "EC2Fleet/Instance",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_system", "cpu_usage_user"],
                "metrics_collection_interval": 60,
                "totalcpu": true
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": ["tcp_established", "tcp_time_wait"],
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
                        "log_group_name": "/aws/ec2/fleet/${project_name}",
                        "log_stream_name": "{instance_id}/httpd/access"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/ec2/fleet/${project_name}",
                        "log_stream_name": "{instance_id}/httpd/error"
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
    -s

# Create a simple monitoring script
cat > /usr/local/bin/instance-monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for fleet instances

LOG_FILE="/var/log/fleet-monitor.log"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Monitor system health
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
DISK_USAGE=$(df -h | grep '/dev/xvda1' | awk '{print $5}' | sed 's/%//')

log_message "Instance: $INSTANCE_ID, CPU: ${CPU_USAGE}%, Memory: ${MEMORY_USAGE}%, Disk: ${DISK_USAGE}%"

# Check if Apache is running
if systemctl is-active --quiet httpd; then
    log_message "Apache is running"
else
    log_message "Apache is not running - attempting restart"
    systemctl restart httpd
fi
EOF

chmod +x /usr/local/bin/instance-monitor.sh

# Add monitoring script to cron (every 5 minutes)
echo "*/5 * * * * /usr/local/bin/instance-monitor.sh" | crontab -

# Install additional useful tools
yum install -y htop iostat curl wget git

# Create a custom service for fleet management
cat > /etc/systemd/system/fleet-manager.service << 'EOF'
[Unit]
Description=Fleet Instance Manager Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=ec2-user
ExecStart=/usr/local/bin/instance-monitor.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the fleet manager service
systemctl enable fleet-manager
systemctl start fleet-manager

# Log the completion of user data script
echo "$(date '+%Y-%m-%d %H:%M:%S') - User data script completed successfully" >> /var/log/user-data.log

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${project_name} --resource AutoScalingGroup --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) || true