#!/bin/bash
# Startup script for gaming backend servers
# This script configures the instance to serve as a game server with Redis connectivity

set -euo pipefail

# Configuration variables from Terraform
REDIS_HOST="${redis_host}"
REDIS_PORT="${redis_port}"
BUCKET_NAME="${bucket_name}"
PROJECT_ID="${project_id}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/game-server-setup.log
}

log "Starting game server setup..."

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing required packages..."
apt-get install -y \
    redis-tools \
    nginx \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    jq \
    htop \
    netstat-nat \
    dstat \
    iotop

# Install Google Cloud SDK if not present
if ! command -v gcloud &> /dev/null; then
    log "Installing Google Cloud SDK..."
    curl https://sdk.cloud.google.com | bash
    source /root/.bashrc
fi

# Configure nginx for game server
log "Configuring nginx..."
cat > /etc/nginx/sites-available/game-server << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
    
    # Game API endpoints
    location /api/ {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for real-time gaming
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Static game files (fallback if not served by CDN)
    location /static/ {
        alias /var/www/game-static/;
        expires 1h;
        add_header Cache-Control "public, immutable";
    }
    
    # Default response for other requests
    location / {
        return 200 '{"status": "Game Server Running", "version": "1.0.0"}';
        add_header Content-Type application/json;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/game-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t

# Create static files directory
mkdir -p /var/www/game-static
chown -R www-data:www-data /var/www/game-static

# Create a simple game server application
log "Creating game server application..."
mkdir -p /opt/game-server
cd /opt/game-server

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install flask redis python-socketio eventlet gunicorn

# Create the game server application
cat > app.py << 'EOF'
#!/usr/bin/env python3
"""
Simple game server application with Redis integration
Provides basic gaming functionality like leaderboards and player sessions
"""

import os
import json
import time
import logging
import redis
from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = 'gaming-secret-key'
socketio = SocketIO(app, cors_allowed_origins="*")

# Redis connection configuration
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
REDIS_AUTH = os.environ.get('REDIS_AUTH', '')

try:
    # Initialize Redis connection
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        password=REDIS_AUTH,
        decode_responses=True,
        socket_keepalive=True,
        socket_keepalive_options={},
        health_check_interval=30
    )
    
    # Test Redis connection
    redis_client.ping()
    logger.info(f"Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
    
except Exception as e:
    logger.error(f"Failed to connect to Redis: {e}")
    redis_client = None

@app.route('/health')
def health_check():
    """Health check endpoint for load balancer"""
    redis_status = "connected" if redis_client and redis_client.ping() else "disconnected"
    return jsonify({
        "status": "healthy",
        "timestamp": int(time.time()),
        "redis": redis_status,
        "version": "1.0.0"
    })

@app.route('/api/player/<player_id>', methods=['GET', 'POST'])
def player_data(player_id):
    """Handle player data operations"""
    if not redis_client:
        return jsonify({"error": "Redis not available"}), 503
    
    if request.method == 'GET':
        # Get player data
        player_data = redis_client.hgetall(f"player:{player_id}")
        if not player_data:
            return jsonify({"error": "Player not found"}), 404
        return jsonify(player_data)
    
    elif request.method == 'POST':
        # Update player data
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        # Store player data with timestamp
        data['last_updated'] = int(time.time())
        redis_client.hmset(f"player:{player_id}", data)
        
        # Update leaderboard if score provided
        if 'score' in data:
            redis_client.zadd('global_leaderboard', {player_id: float(data['score'])})
        
        return jsonify({"status": "success", "player_id": player_id})

@app.route('/api/leaderboard')
def get_leaderboard():
    """Get global leaderboard"""
    if not redis_client:
        return jsonify({"error": "Redis not available"}), 503
    
    # Get top 10 players
    top_players = redis_client.zrevrange('global_leaderboard', 0, 9, withscores=True)
    
    leaderboard = []
    for rank, (player_id, score) in enumerate(top_players, 1):
        player_data = redis_client.hgetall(f"player:{player_id}")
        leaderboard.append({
            "rank": rank,
            "player_id": player_id,
            "score": int(score),
            "name": player_data.get('name', f'Player{player_id}')
        })
    
    return jsonify({
        "leaderboard": leaderboard,
        "total_players": redis_client.zcard('global_leaderboard')
    })

@app.route('/api/session/<session_id>', methods=['GET', 'POST', 'DELETE'])
def game_session(session_id):
    """Handle game session operations"""
    if not redis_client:
        return jsonify({"error": "Redis not available"}), 503
    
    session_key = f"session:{session_id}"
    
    if request.method == 'GET':
        # Get session data
        session_data = redis_client.hgetall(session_key)
        if not session_data:
            return jsonify({"error": "Session not found"}), 404
        return jsonify(session_data)
    
    elif request.method == 'POST':
        # Create or update session
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        data['created_at'] = int(time.time())
        redis_client.hmset(session_key, data)
        redis_client.expire(session_key, 3600)  # 1 hour TTL
        
        return jsonify({"status": "success", "session_id": session_id})
    
    elif request.method == 'DELETE':
        # Delete session
        redis_client.delete(session_key)
        return jsonify({"status": "deleted", "session_id": session_id})

@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connections for real-time gaming"""
    logger.info('Client connected')
    emit('status', {'msg': 'Connected to game server'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnections"""
    logger.info('Client disconnected')

@socketio.on('game_event')
def handle_game_event(data):
    """Handle real-time game events"""
    logger.info(f'Game event received: {data}')
    
    # Process game event and broadcast to other players
    emit('game_update', data, broadcast=True, include_self=False)

if __name__ == '__main__':
    # Start the game server
    socketio.run(app, host='0.0.0.0', port=8080, debug=False)
EOF

# Create systemd service for the game server
cat > /etc/systemd/system/game-server.service << 'EOF'
[Unit]
Description=Game Server Application
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/game-server
Environment=PATH=/opt/game-server/venv/bin
Environment=REDIS_HOST=${REDIS_HOST}
Environment=REDIS_PORT=${REDIS_PORT}
ExecStart=/opt/game-server/venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Make the app executable
chmod +x app.py

# Create environment file with Redis connection details
cat > .env << EOF
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
BUCKET_NAME=${BUCKET_NAME}
PROJECT_ID=${PROJECT_ID}
EOF

# Change ownership to www-data
chown -R www-data:www-data /opt/game-server

log "Testing Redis connectivity..."
# Test Redis connection
if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ping > /dev/null 2>&1; then
    log "Redis connection successful"
    
    # Initialize some sample data
    log "Initializing sample game data..."
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" << 'REDIS_EOF'
HSET player:demo name "DemoPlayer" level 10 score 5000 created_at 1640995200
ZADD global_leaderboard 5000 "demo"
SET game:config:initialized "true"
SET game:config:version "1.0.0"
REDIS_EOF
else
    log "Warning: Could not connect to Redis at ${REDIS_HOST}:${REDIS_PORT}"
fi

# Enable and start services
log "Starting services..."
systemctl enable nginx
systemctl enable game-server

systemctl restart nginx
systemctl start game-server

# Verify services are running
sleep 5
if systemctl is-active --quiet nginx; then
    log "Nginx started successfully"
else
    log "Error: Nginx failed to start"
fi

if systemctl is-active --quiet game-server; then
    log "Game server started successfully"
else
    log "Error: Game server failed to start"
    # Show logs for debugging
    journalctl -u game-server --no-pager -n 20
fi

# Create monitoring script
cat > /opt/monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for game server

echo "=== Game Server Status ==="
echo "Nginx: $(systemctl is-active nginx)"
echo "Game Server: $(systemctl is-active game-server)"
echo ""

echo "=== Resource Usage ==="
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $5}')"
echo ""

echo "=== Network Connections ==="
netstat -tuln | grep -E ':(80|8080) '
echo ""

echo "=== Redis Status ==="
if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ping > /dev/null 2>&1; then
    echo "Redis: Connected"
    echo "Players in leaderboard: $(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ZCARD global_leaderboard)"
else
    echo "Redis: Disconnected"
fi
EOF

chmod +x /opt/monitor.sh

log "Game server setup completed successfully!"
log "Services status:"
systemctl status nginx --no-pager -l
systemctl status game-server --no-pager -l

log "Setup log saved to /var/log/game-server-setup.log"
log "Monitor script available at /opt/monitor.sh"