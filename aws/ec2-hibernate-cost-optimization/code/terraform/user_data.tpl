#!/bin/bash

# User data script for EC2 hibernation demo instance
# This script runs on instance launch to set up the environment

# Update system packages
yum update -y

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Install AWS CLI v2 if not already installed
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -f awscliv2.zip
fi

# Create a test file to demonstrate hibernation state preservation
cat > /home/ec2-user/hibernation_test.txt << 'EOF'
This file was created during instance initialization.
Instance Name: ${instance_name}
Environment: ${environment}
Creation Time: $(date)

This file will persist through hibernation cycles, demonstrating
that the instance state is preserved when hibernating.
EOF

# Set proper permissions
chown ec2-user:ec2-user /home/ec2-user/hibernation_test.txt

# Create a simple script to monitor hibernation events
cat > /home/ec2-user/monitor_hibernation.sh << 'EOF'
#!/bin/bash
# Simple script to monitor hibernation events

echo "=== Hibernation Monitor Started at $(date) ===" >> /var/log/hibernation_monitor.log
echo "Instance Name: ${instance_name}" >> /var/log/hibernation_monitor.log
echo "Environment: ${environment}" >> /var/log/hibernation_monitor.log

# Monitor system events
journalctl -f -u systemd-hibernate.service >> /var/log/hibernation_monitor.log &

# Create a process that will help verify hibernation state preservation
nohup bash -c 'while true; do
    echo "$(date): Process still running (PID: $$)" >> /home/ec2-user/hibernation_process.log
    sleep 30
done' > /dev/null 2>&1 &

echo "Hibernation monitoring setup complete" >> /var/log/hibernation_monitor.log
EOF

# Make script executable
chmod +x /home/ec2-user/monitor_hibernation.sh
chown ec2-user:ec2-user /home/ec2-user/monitor_hibernation.sh

# Run the monitoring script
/home/ec2-user/monitor_hibernation.sh

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "EC2/Hibernation",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60,
                "resources": ["*"],
                "totalcpu": false
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/hibernation_monitor.log",
                        "log_group_name": "/aws/ec2/hibernation-demo/${instance_name}",
                        "log_stream_name": "hibernation-monitor"
                    },
                    {
                        "file_path": "/home/ec2-user/hibernation_process.log",
                        "log_group_name": "/aws/ec2/hibernation-demo/${instance_name}",
                        "log_stream_name": "hibernation-process"
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
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable CloudWatch agent service
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Create a simple web server to test hibernation (optional)
cat > /home/ec2-user/simple_server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import datetime
import os

PORT = 8000

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            html_content = f"""
            <html>
            <head><title>EC2 Hibernation Demo</title></head>
            <body>
                <h1>EC2 Hibernation Demo Server</h1>
                <p>Instance Name: ${instance_name}</p>
                <p>Environment: ${environment}</p>
                <p>Current Time: {datetime.datetime.now()}</p>
                <p>Server Started: {datetime.datetime.now()}</p>
                <p>This server demonstrates hibernation state preservation.</p>
                <p>When the instance hibernates and resumes, this server will continue running.</p>
            </body>
            </html>
            """
            self.wfile.write(html_content.encode())
        else:
            super().do_GET()

# Start server in background
if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), CustomHandler) as httpd:
        print(f"Server running on port {PORT}")
        httpd.serve_forever()
EOF

# Make server script executable
chmod +x /home/ec2-user/simple_server.py
chown ec2-user:ec2-user /home/ec2-user/simple_server.py

# Start the simple server in background (optional)
nohup python3 /home/ec2-user/simple_server.py > /home/ec2-user/server.log 2>&1 &

# Log completion
echo "$(date): User data script completed successfully" >> /var/log/user-data.log
echo "Instance ${instance_name} initialization complete" >> /var/log/user-data.log