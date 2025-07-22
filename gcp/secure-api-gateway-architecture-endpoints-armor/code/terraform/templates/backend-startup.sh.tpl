#!/bin/bash
# Backend API Service Startup Script
# This script installs and configures a Flask API server on the backend instance

set -e

# Update system packages
apt-get update
apt-get install -y python3 python3-pip

# Install Flask and dependencies
pip3 install flask gunicorn

# Create the API server application
cat > /opt/api-server.py << 'EOF'
from flask import Flask, jsonify, request
import datetime
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint for load balancer monitoring"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.datetime.now().isoformat(),
        "service": "backend-api",
        "version": "1.0.0"
    })

@app.route("/api/v1/users", methods=["GET"])
def get_users():
    """Get users list endpoint - requires authentication"""
    logger.info("Users endpoint accessed")
    return jsonify({
        "users": [
            {"id": 1, "name": "Alice", "email": "alice@example.com"},
            {"id": 2, "name": "Bob", "email": "bob@example.com"},
            {"id": 3, "name": "Charlie", "email": "charlie@example.com"}
        ],
        "total": 3,
        "timestamp": datetime.datetime.now().isoformat()
    })

@app.route("/api/v1/data", methods=["POST"])
def create_data():
    """Create new data endpoint - requires authentication"""
    try:
        data = request.get_json()
        logger.info(f"Data creation requested: {data}")
        
        # Simulate data processing
        response_data = {
            "message": "Data received and processed successfully",
            "data": data,
            "id": 12345,
            "timestamp": datetime.datetime.now().isoformat(),
            "status": "created"
        }
        
        return jsonify(response_data), 201
    except Exception as e:
        logger.error(f"Error processing data: {str(e)}")
        return jsonify({
            "error": "Failed to process data",
            "message": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }), 400

@app.route("/api/v1/status", methods=["GET"])
def get_status():
    """System status endpoint"""
    return jsonify({
        "service": "backend-api",
        "status": "running",
        "uptime": "N/A",
        "timestamp": datetime.datetime.now().isoformat(),
        "environment": "production"
    })

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return jsonify({
        "error": "Not found",
        "message": "The requested endpoint does not exist",
        "timestamp": datetime.datetime.now().isoformat()
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    return jsonify({
        "error": "Internal server error",
        "message": "An unexpected error occurred",
        "timestamp": datetime.datetime.now().isoformat()
    }), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", ${backend_port}))
    app.run(host="0.0.0.0", port=port, debug=False)
EOF

# Create systemd service file for automatic startup
cat > /etc/systemd/system/api-server.service << 'EOF'
[Unit]
Description=Backend API Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt
Environment=PORT=${backend_port}
ExecStart=/usr/bin/python3 /opt/api-server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create www-data user if it doesn't exist
if ! id "www-data" &>/dev/null; then
    useradd -r -s /bin/false www-data
fi

# Set proper permissions
chown www-data:www-data /opt/api-server.py
chmod +x /opt/api-server.py

# Enable and start the service
systemctl daemon-reload
systemctl enable api-server.service
systemctl start api-server.service

# Create log rotation configuration
cat > /etc/logrotate.d/api-server << 'EOF'
/var/log/api-server.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 www-data www-data
}
EOF

# Verify service is running
sleep 5
if systemctl is-active --quiet api-server.service; then
    echo "Backend API server started successfully on port ${backend_port}"
    logger "Backend API server startup completed successfully"
else
    echo "Failed to start backend API server"
    logger "Backend API server startup failed"
    exit 1
fi