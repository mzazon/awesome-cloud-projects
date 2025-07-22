#!/bin/bash
# User data script for web server instances
# This script installs and configures Apache HTTP Server with a sample application

# Exit on any error
set -e

# Update system packages
yum update -y

# Install Apache HTTP Server
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create a simple web page with instance information
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Terraform Infrastructure Demo</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
            backdrop-filter: blur(4px);
            border: 1px solid rgba(255, 255, 255, 0.18);
        }
        h1 {
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .info-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .info-card h3 {
            margin-top: 0;
            color: #ffd700;
        }
        .status {
            text-align: center;
            font-size: 1.2em;
            margin: 20px 0;
            padding: 15px;
            background: rgba(0, 255, 0, 0.2);
            border-radius: 10px;
            border: 1px solid rgba(0, 255, 0, 0.3);
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 0.9em;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Terraform Infrastructure as Code Demo</h1>
        
        <div class="status">
            ✅ Application Running Successfully
        </div>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>🏗️ Project Info</h3>
                <p><strong>Project:</strong> ${project_name}</p>
                <p><strong>Environment:</strong> ${environment}</p>
                <p><strong>Managed By:</strong> Terraform</p>
            </div>
            
            <div class="info-card">
                <h3>🖥️ Instance Details</h3>
                <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
                <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
                <p><strong>Availability Zone:</strong> <span id="availability-zone">Loading...</span></p>
            </div>
            
            <div class="info-card">
                <h3>🌐 Network Info</h3>
                <p><strong>Private IP:</strong> <span id="private-ip">Loading...</span></p>
                <p><strong>Public IP:</strong> <span id="public-ip">Loading...</span></p>
                <p><strong>Region:</strong> <span id="region">Loading...</span></p>
            </div>
            
            <div class="info-card">
                <h3>⏰ Deployment Info</h3>
                <p><strong>Server Time:</strong> <span id="server-time"></span></p>
                <p><strong>Uptime:</strong> <span id="uptime">Loading...</span></p>
                <p><strong>Load Average:</strong> <span id="load-avg">Loading...</span></p>
            </div>
        </div>
        
        <div class="footer">
            <p>This instance is part of an Auto Scaling Group managed by Terraform</p>
            <p>Infrastructure as Code Recipe: infrastructure-as-code-terraform-aws</p>
        </div>
    </div>

    <script>
        // Function to fetch instance metadata
        async function fetchMetadata(endpoint) {
            try {
                const response = await fetch('http://169.254.169.254/latest/meta-data/' + endpoint);
                return await response.text();
            } catch (error) {
                return 'Error loading';
            }
        }

        // Function to update page with instance information
        async function updateInstanceInfo() {
            // Update instance details
            document.getElementById('instance-id').textContent = await fetchMetadata('instance-id');
            document.getElementById('instance-type').textContent = await fetchMetadata('instance-type');
            document.getElementById('availability-zone').textContent = await fetchMetadata('placement/availability-zone');
            document.getElementById('private-ip').textContent = await fetchMetadata('local-ipv4');
            document.getElementById('public-ip').textContent = await fetchMetadata('public-ipv4');
            
            // Extract region from availability zone
            const az = await fetchMetadata('placement/availability-zone');
            const region = az.slice(0, -1);
            document.getElementById('region').textContent = region;
            
            // Update server time
            document.getElementById('server-time').textContent = new Date().toLocaleString();
            
            // These would need server-side scripts to work properly, showing placeholders
            document.getElementById('uptime').textContent = 'Available via /proc/uptime';
            document.getElementById('load-avg').textContent = 'Available via /proc/loadavg';
        }

        // Update info when page loads
        updateInstanceInfo();
        
        // Update time every second
        setInterval(() => {
            document.getElementById('server-time').textContent = new Date().toLocaleString();
        }, 1000);
    </script>
</body>
</html>
EOF

# Create a health check endpoint
cat > /var/www/html/health << 'EOF'
OK
EOF

# Create a more detailed status page
cat > /var/www/html/status.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Server Status</title>
    <meta http-equiv="refresh" content="5">
</head>
<body>
    <h1>Server Status</h1>
    <p>Status: Healthy</p>
    <p>Last Updated: $(date)</p>
    <p>Uptime: $(uptime)</p>
</body>
</html>
EOF

# Set proper permissions
chmod 644 /var/www/html/index.html
chmod 644 /var/www/html/health
chmod 644 /var/www/html/status.html

# Configure Apache to start on boot
chkconfig httpd on

# Create a simple log rotation for application logs
cat > /etc/logrotate.d/webapp << 'EOF'
/var/log/httpd/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 apache apache
    sharedscripts
    postrotate
        /bin/systemctl reload httpd.service > /dev/null 2>/dev/null || true
    endscript
}
EOF

# Install CloudWatch agent for monitoring (optional)
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "Terraform/Demo",
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
            "mem": {
                "measurement": [
                    "mem_used_percent"
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
                        "log_group_name": "terraform-demo-apache-access",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "terraform-demo-apache-error",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Enable and start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Ensure Apache is running
systemctl restart httpd

# Final verification
if systemctl is-active --quiet httpd; then
    echo "Apache HTTP Server installation completed successfully"
    logger "Terraform demo web server setup completed successfully"
else
    echo "Apache HTTP Server failed to start"
    logger "Terraform demo web server setup failed"
    exit 1
fi

# Signal that the instance is ready
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} 2>/dev/null || echo "CFN signal not available"