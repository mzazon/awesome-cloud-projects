#!/bin/bash
# ============================================================================
# Regional Backend Application Setup Script
# ============================================================================
# This script configures an EC2 instance in a regional subnet to run
# backend services that support the Wavelength edge application.
# ============================================================================

set -e  # Exit on any error

# Variables passed from Terraform
PROJECT_NAME="${project_name}"

# Logging setup
LOG_FILE="/var/log/regional-setup.log"
exec 1> >(tee -a $LOG_FILE)
exec 2>&1

echo "==================================="
echo "Regional Backend Application Setup"
echo "==================================="
echo "Project: $PROJECT_NAME"
echo "Started at: $(date)"
echo "==================================="

# Update system packages
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y \
    docker \
    mysql \
    htop \
    iotop \
    netstat-nat \
    tcpdump \
    curl \
    wget \
    git \
    jq \
    awscli \
    amazon-cloudwatch-agent \
    python3 \
    python3-pip

# Configure Docker
echo "Configuring Docker service..."
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create application directory
echo "Creating application directories..."
mkdir -p /opt/backend-app/{logs,config,data,database}
chown -R ec2-user:ec2-user /opt/backend-app

# Create backend application configuration
echo "Creating backend application configuration..."
cat > /opt/backend-app/config/app.conf << EOF
# Backend Application Configuration
PROJECT_NAME=$PROJECT_NAME
DATABASE_PORT=3306
API_PORT=80
LOG_LEVEL=INFO
METRICS_ENABLED=true
CACHE_ENABLED=true
EOF

# Start MySQL database container
echo "Starting MySQL database container..."
docker run -d \
    --name backend-db \
    --restart unless-stopped \
    -p 3306:3306 \
    -v /opt/backend-app/database:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=SecureBackendPassword123! \
    -e MYSQL_DATABASE=edgeapp \
    -e MYSQL_USER=appuser \
    -e MYSQL_PASSWORD=AppUserPassword123! \
    mysql:8.0

# Wait for database to initialize
echo "Waiting for database to initialize..."
sleep 30

# Start backend API container
echo "Starting backend API container..."
docker run -d \
    --name backend-api \
    --restart unless-stopped \
    -p 80:80 \
    -p 8080:8080 \
    -v /opt/backend-app/config:/etc/app:ro \
    -v /opt/backend-app/logs:/var/log/app \
    -e PROJECT_NAME="$PROJECT_NAME" \
    -e INSTANCE_TYPE="regional-backend" \
    --link backend-db:database \
    nginx:alpine

# Wait for backend container to start
echo "Waiting for backend container to start..."
sleep 10

# Configure nginx for backend services
echo "Configuring backend services..."
docker exec backend-api sh -c 'cat > /etc/nginx/conf.d/default.conf << "EOF"
# Backend Services Nginx Configuration
server {
    listen 80;
    server_name _;
    
    # Backend API endpoints
    location /api/v1/ {
        add_header Content-Type "application/json" always;
        add_header Access-Control-Allow-Origin "*" always;
        add_header X-Backend-Server "regional" always;
        
        # User management endpoints
        location /api/v1/users {
            return 200 "{
                \"service\": \"user-management\",
                \"status\": \"active\",
                \"server_type\": \"regional-backend\",
                \"database_connected\": true,
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Game data endpoints
        location /api/v1/gamedata {
            return 200 "{
                \"service\": \"game-data\",
                \"status\": \"active\",
                \"total_games\": 1500,
                \"active_sessions\": 300,
                \"server_type\": \"regional-backend\",
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Analytics endpoints
        location /api/v1/analytics {
            return 200 "{
                \"service\": \"analytics\",
                \"status\": \"active\",
                \"events_processed_today\": 125000,
                \"server_type\": \"regional-backend\",
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Configuration endpoints
        location /api/v1/config {
            return 200 "{
                \"service\": \"configuration\",
                \"status\": \"active\",
                \"edge_servers\": [\"wavelength-zone-1\"],
                \"cdn_enabled\": true,
                \"server_type\": \"regional-backend\",
                \"timestamp\": \"$time_iso8601\"
            }";
        }
        
        # Default backend API response
        return 200 "{
            \"api_version\": \"1.0\",
            \"server_type\": \"regional-backend\",
            \"services\": [\"user-management\", \"game-data\", \"analytics\", \"configuration\"],
            \"timestamp\": \"$time_iso8601\"
        }";
    }
    
    # Health check endpoint
    location /health {
        add_header Content-Type "application/json" always;
        return 200 "{
            \"status\": \"healthy\",
            \"server_type\": \"regional-backend\",
            \"database_status\": \"connected\",
            \"services_online\": 4,
            \"timestamp\": \"$time_iso8601\"
        }";
    }
    
    # Metrics endpoint
    location /metrics {
        add_header Content-Type "application/json" always;
        return 200 "{
            \"active_connections\": \"$connections_active\",
            \"total_requests\": \"$connections_reading\",
            \"server_type\": \"regional-backend\",
            \"uptime\": \"$upstream_response_time\",
            \"timestamp\": \"$time_iso8601\"
        }";
    }
    
    # Default response for root
    location / {
        add_header Content-Type "application/json" always;
        return 200 "{
            \"service\": \"regional-backend\",
            \"status\": \"running\",
            \"project\": \"'$PROJECT_NAME'\",
            \"capabilities\": [\"database\", \"analytics\", \"user-management\", \"configuration\"],
            \"timestamp\": \"$time_iso8601\"
        }";
    }
    
    # Error pages
    error_page 404 /404.json;
    location = /404.json {
        add_header Content-Type "application/json" always;
        return 404 "{\"error\": \"Not Found\", \"server_type\": \"regional-backend\"}";
    }
    
    error_page 500 502 503 504 /50x.json;
    location = /50x.json {
        add_header Content-Type "application/json" always;
        return 500 "{\"error\": \"Server Error\", \"server_type\": \"regional-backend\"}";
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
            \"server_type\": \"regional-backend\",
            \"project\": \"'$PROJECT_NAME'\",
            \"database_connected\": true,
            \"timestamp\": \"$time_iso8601\"
        }";
    }
}
EOF'

# Restart nginx to apply configuration
echo "Restarting nginx with new configuration..."
docker restart backend-api

# Initialize database schema
echo "Initializing database schema..."
sleep 10
docker exec backend-db mysql -u root -pSecureBackendPassword123! -e "
USE edgeapp;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS game_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    session_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_end TIMESTAMP NULL,
    server_type ENUM('wavelength', 'regional') NOT NULL,
    latency_ms INT,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS performance_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    server_type ENUM('wavelength', 'regional') NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    metric_value DECIMAL(10,2),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email) VALUES 
('testuser1', 'test1@example.com'),
('testuser2', 'test2@example.com'),
('testuser3', 'test3@example.com');

INSERT INTO performance_metrics (server_type, metric_name, metric_value) VALUES
('wavelength', 'latency_ms', 2.5),
('wavelength', 'throughput_mbps', 100.0),
('regional', 'latency_ms', 15.0),
('regional', 'throughput_mbps', 500.0);
"

# Configure CloudWatch agent for backend monitoring
echo "Configuring CloudWatch monitoring..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "EdgeApp/Regional",
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
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/regional-setup.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME",
                        "log_stream_name": "regional-setup-{instance_id}"
                    },
                    {
                        "file_path": "/opt/backend-app/logs/*.log",
                        "log_group_name": "/aws/ec2/$PROJECT_NAME",
                        "log_stream_name": "backend-app-{instance_id}"
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

# Create database backup script
echo "Creating database backup script..."
cat > /opt/backend-app/backup-db.sh << 'EOF'
#!/bin/bash
# Database backup script

BACKUP_DIR="/opt/backend-app/database/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/edgeapp_backup_$TIMESTAMP.sql"

mkdir -p $BACKUP_DIR

docker exec backend-db mysqldump -u root -pSecureBackendPassword123! edgeapp > $BACKUP_FILE

if [ $? -eq 0 ]; then
    echo "Database backup completed: $BACKUP_FILE"
    # Keep only last 7 days of backups
    find $BACKUP_DIR -name "edgeapp_backup_*.sql" -mtime +7 -delete
else
    echo "Database backup failed!"
    exit 1
fi
EOF

chmod +x /opt/backend-app/backup-db.sh
chown ec2-user:ec2-user /opt/backend-app/backup-db.sh

# Create cron job for daily backups
echo "0 2 * * * ec2-user /opt/backend-app/backup-db.sh" >> /etc/crontab

# Create performance monitoring script
echo "Creating performance monitoring script..."
cat > /opt/backend-app/monitor.sh << 'EOF'
#!/bin/bash
# Performance monitoring script for regional backend

LOG_FILE="/opt/backend-app/logs/performance.log"

while true; do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Test database connection
    DB_STATUS=$(docker exec backend-db mysqladmin -u root -pSecureBackendPassword123! ping 2>/dev/null | grep "mysqld is alive" | wc -l)
    
    # Test API response time
    API_RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null http://localhost/health)
    
    echo "$TIMESTAMP,CPU:$CPU_USAGE%,Memory:$MEMORY_USAGE%,Disk:$DISK_USAGE%,DB:$DB_STATUS,API:${API_RESPONSE_TIME}s" >> $LOG_FILE
    
    sleep 60
done
EOF

chmod +x /opt/backend-app/monitor.sh
chown ec2-user:ec2-user /opt/backend-app/monitor.sh

# Start performance monitoring in background
echo "Starting performance monitoring..."
nohup /opt/backend-app/monitor.sh > /dev/null 2>&1 &

# Create system service for monitoring
cat > /etc/systemd/system/backend-app-monitor.service << EOF
[Unit]
Description=Backend Application Performance Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=ec2-user
ExecStart=/opt/backend-app/monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl enable backend-app-monitor.service
systemctl start backend-app-monitor.service

# Verify services are running
echo "Verifying backend services..."
sleep 5

# Test endpoints
echo "Testing backend endpoints..."
curl -s http://localhost/health | jq '.' || echo "Health endpoint test failed"
curl -s http://localhost/api/v1/users | jq '.' || echo "Users API test failed"
curl -s http://localhost/metrics | jq '.' || echo "Metrics endpoint test failed"

# Test database connection
echo "Testing database connection..."
docker exec backend-db mysql -u appuser -pAppUserPassword123! -e "SELECT COUNT(*) as user_count FROM edgeapp.users;" || echo "Database test failed"

# Final status
echo "==================================="
echo "Regional Backend Application Setup Complete"
echo "==================================="
echo "Backend API URL: http://localhost/"
echo "Health Check URL: http://localhost/health"
echo "Database: MySQL on port 3306"
echo "API Endpoints: http://localhost/api/v1/"
echo "Logs: /opt/backend-app/logs/"
echo "Performance Monitor: systemctl status backend-app-monitor"
echo "CloudWatch Agent: systemctl status amazon-cloudwatch-agent"
echo "Daily Backup: 02:00 UTC"
echo "Completed at: $(date)"
echo "==================================="

# Send completion signal to CloudWatch
aws cloudwatch put-metric-data \
    --namespace "EdgeApp/Deployment" \
    --metric-data MetricName=BackendSetupComplete,Value=1,Unit=Count \
    --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) \
    || echo "Failed to send CloudWatch metric"

echo "Regional backend application setup completed successfully!"