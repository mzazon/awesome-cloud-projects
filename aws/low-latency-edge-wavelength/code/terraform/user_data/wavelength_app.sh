#!/bin/bash
# ============================================================================
# Wavelength Edge Application Setup Script
# ============================================================================
# This script configures an EC2 instance in AWS Wavelength Zone to run
# a low-latency edge application optimized for mobile 5G connectivity.
# ============================================================================

set -e  # Exit on any error

# Variables passed from Terraform
APPLICATION_PORT="${application_port}"
HEALTH_CHECK_PORT="${health_check_port}"
PROJECT_NAME="${project_name}"

# Logging setup
LOG_FILE="/var/log/wavelength-setup.log"
exec 1> >(tee -a $LOG_FILE)
exec 2>&1

echo "==================================="
echo "Wavelength Edge Application Setup"
echo "==================================="
echo "Project: $PROJECT_NAME"
echo "Application Port: $APPLICATION_PORT"
echo "Health Check Port: $HEALTH_CHECK_PORT"
echo "Started at: $(date)"
echo "==================================="

# Update system packages
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y \
    docker \
    htop \
    iotop \
    netstat-nat \
    tcpdump \
    iftop \
    curl \
    wget \
    git \
    jq \
    awscli \
    amazon-cloudwatch-agent

# Configure Docker
echo "Configuring Docker service..."
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create application directory
echo "Creating application directories..."
mkdir -p /opt/edge-app/{logs,config,data}
chown -R ec2-user:ec2-user /opt/edge-app

# Create edge application configuration
echo "Creating edge application configuration..."
cat > /opt/edge-app/config/app.conf << EOF
# Edge Application Configuration
PROJECT_NAME=$PROJECT_NAME
APPLICATION_PORT=$APPLICATION_PORT
HEALTH_CHECK_PORT=$HEALTH_CHECK_PORT
LOG_LEVEL=INFO
METRICS_ENABLED=true
LATENCY_MONITORING=true
EOF

# Create Docker container for edge application
echo "Starting edge application container..."
docker run -d \
    --name edge-app \
    --restart unless-stopped \
    -p $APPLICATION_PORT:80 \
    -p $HEALTH_CHECK_PORT:8080 \
    -v /opt/edge-app/config:/etc/app:ro \
    -v /opt/edge-app/logs:/var/log/app \
    -e PROJECT_NAME="$PROJECT_NAME" \
    -e INSTANCE_TYPE="wavelength-edge" \
    nginx:alpine

# Wait for Docker container to start
echo "Waiting for application container to start..."
sleep 10

# Configure nginx inside container for edge application
echo "Configuring edge application..."
docker exec edge-app sh -c 'cat > /etc/nginx/conf.d/default.conf << "EOF"
# Edge Application Nginx Configuration
server {
    listen 80;
    server_name _;
    
    # Enable keep-alive connections for better performance
    keepalive_timeout 65;
    keepalive_requests 1000;
    
    # Optimize for low latency
    tcp_nodelay on;
    tcp_nopush on;
    
    # Main application endpoint
    location / {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        
        return 200 "{
            \"status\": \"success\",
            \"message\": \"Edge Server Response\",
            \"timestamp\": \"$time_iso8601\",
            \"server_type\": \"wavelength-edge\",
            \"project\": \"'$PROJECT_NAME'\",
            \"location\": \"wavelength-zone\",
            \"latency_optimized\": true,
            \"response_time_ms\": \"$request_time\"
        }";
    }
    
    # API endpoints for mobile applications
    location /api/ {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header X-Edge-Server "wavelength" always;
        
        # Simulate game server or real-time application
        location /api/game {
            return 200 "{
                \"game_state\": \"active\",
                \"players_online\": 1500,
                \"server_region\": \"wavelength-edge\",
                \"latency_ms\": 2,
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Health endpoint for load balancer
        location /api/health {
            access_log off;
            return 200 "{
                \"status\": \"healthy\",
                \"uptime\": \"$upstream_response_time\",
                \"timestamp\": \"$time_iso8601\",
                \"server_type\": \"wavelength-edge\"
            }";
        }
        
        # Metrics endpoint
        location /api/metrics {
            return 200 "{
                \"active_connections\": \"$connections_active\",
                \"total_requests\": \"$connections_reading\",
                \"server_type\": \"wavelength-edge\",
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Default API response
        return 200 "{
            \"api_version\": \"1.0\",
            \"server_type\": \"wavelength-edge\",
            \"capabilities\": [\"low-latency\", \"5g-optimized\", \"mobile-gaming\"],
            \"timestamp\": \"$time_iso8601\"
        }";
    }
    
    # Error pages
    error_page 404 /404.json;
    location = /404.json {
        add_header Content-Type "application/json" always;
        return 404 "{\"error\": \"Not Found\", \"server_type\": \"wavelength-edge\"}";
    }
    
    error_page 500 502 503 504 /50x.json;
    location = /50x.json {
        add_header Content-Type "application/json" always;
        return 500 "{\"error\": \"Server Error\", \"server_type\": \"wavelength-edge\"}";
    }
}

# Health check server on separate port
server {
    listen 8080;
    server_name _;
    access_log off;
    
    location /health {
        add_header Content-Type "text/plain" always;
        return 200 "healthy";
    }
    
    location /status {
        add_header Content-Type "application/json" always;
        return 200 "{
            \"status\": \"healthy\",
            \"server_type\": \"wavelength-edge\",
            \"project\": \"'$PROJECT_NAME'\",
            \"timestamp\": \"$time_iso8601\"
        }";
    }
}
EOF'

# Restart nginx to apply configuration
echo "Restarting nginx with new configuration..."
docker restart edge-app

# Configure CloudWatch agent for monitoring
echo "Configuring CloudWatch monitoring..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "EdgeApp/Wavelength",
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
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/wavelength-setup.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME",
                        "log_stream_name": "wavelength-setup-{instance_id}"
                    },
                    {
                        "file_path": "/opt/edge-app/logs/*.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME",
                        "log_stream_name": "edge-app-{instance_id}"
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

# Create performance monitoring script
echo "Creating performance monitoring script..."
cat > /opt/edge-app/monitor.sh << 'EOF'
#!/bin/bash
# Performance monitoring script for Wavelength edge application

LOG_FILE="/opt/edge-app/logs/performance.log"

while true; do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')
    NETWORK_CONNECTIONS=$(netstat -an | grep ":$APPLICATION_PORT " | wc -l)
    
    # Test application response time
    RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null http://localhost:$APPLICATION_PORT/api/health)
    
    echo "$TIMESTAMP,CPU:$CPU_USAGE%,Memory:$MEMORY_USAGE%,Connections:$NETWORK_CONNECTIONS,ResponseTime:${RESPONSE_TIME}s" >> $LOG_FILE
    
    sleep 60
done
EOF

chmod +x /opt/edge-app/monitor.sh
chown ec2-user:ec2-user /opt/edge-app/monitor.sh

# Start performance monitoring in background
echo "Starting performance monitoring..."
nohup /opt/edge-app/monitor.sh > /dev/null 2>&1 &

# Create system service for monitoring
cat > /etc/systemd/system/edge-app-monitor.service << EOF
[Unit]
Description=Edge Application Performance Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=ec2-user
ExecStart=/opt/edge-app/monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl enable edge-app-monitor.service
systemctl start edge-app-monitor.service

# Configure network optimizations for low latency
echo "Configuring network optimizations..."
cat >> /etc/sysctl.conf << EOF

# Network optimizations for low latency edge applications
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.route.flush = 1
EOF

sysctl -p

# Verify application is running
echo "Verifying application deployment..."
sleep 5

# Test application endpoints
echo "Testing application endpoints..."
curl -s http://localhost:$APPLICATION_PORT/ | jq '.' || echo "Main endpoint test failed"
curl -s http://localhost:$APPLICATION_PORT/api/health | jq '.' || echo "Health endpoint test failed"
curl -s http://localhost:$HEALTH_CHECK_PORT/health || echo "Load balancer health check test failed"

# Final status
echo "==================================="
echo "Wavelength Edge Application Setup Complete"
echo "==================================="
echo "Application URL: http://localhost:$APPLICATION_PORT"
echo "Health Check URL: http://localhost:$HEALTH_CHECK_PORT/health"
echo "API Endpoints: http://localhost:$APPLICATION_PORT/api/"
echo "Logs: /opt/edge-app/logs/"
echo "Performance Monitor: systemctl status edge-app-monitor"
echo "CloudWatch Agent: systemctl status amazon-cloudwatch-agent"
echo "Completed at: $(date)"
echo "==================================="

# Send completion signal to CloudWatch
aws cloudwatch put-metric-data \
    --namespace "EdgeApp/Deployment" \
    --metric-data MetricName=SetupComplete,Value=1,Unit=Count \
    --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) \
    || echo "Failed to send CloudWatch metric"

echo "Wavelength edge application setup completed successfully!"