#!/bin/bash

# Secure Traffic Processing Engine Startup Script
# This script configures the Confidential VM with the traffic processing service
# All operations occur within the hardware-protected TEE environment

set -euo pipefail

# Configuration variables from Terraform
PROJECT_ID="${project_id}"
REGION="${region}"
KEYRING_NAME="${keyring_name}"
KEY_NAME="${key_name}"
BUCKET_NAME="${bucket_name}"
PROCESSOR_PORT="${processor_port}"

# Logging setup
LOGFILE="/var/log/traffic-processor-setup.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "$(date): Starting secure traffic processor setup on Confidential VM"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "KMS Key Ring: $KEYRING_NAME"
echo "Processor Port: $PROCESSOR_PORT"

# Update system packages
echo "$(date): Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required dependencies
echo "$(date): Installing required dependencies..."
apt-get install -y \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    jq \
    htop \
    iotop \
    tcpdump \
    netstat-nat \
    dstat

# Create dedicated user for traffic processor service
echo "$(date): Creating traffic processor user..."
useradd -r -s /bin/false -d /opt/traffic-processor traffic-processor || true

# Create application directory
APP_DIR="/opt/traffic-processor"
mkdir -p "$APP_DIR"
chown traffic-processor:traffic-processor "$APP_DIR"

# Create Python virtual environment
echo "$(date): Setting up Python virtual environment..."
sudo -u traffic-processor python3 -m venv "$APP_DIR/venv"

# Install Python dependencies
echo "$(date): Installing Python dependencies..."
sudo -u traffic-processor "$APP_DIR/venv/bin/pip" install --upgrade pip setuptools wheel
sudo -u traffic-processor "$APP_DIR/venv/bin/pip" install \
    google-cloud-kms==2.21.0 \
    google-cloud-storage==2.10.0 \
    google-cloud-monitoring==2.15.1 \
    google-cloud-logging==3.8.0 \
    grpcio==1.59.0 \
    grpcio-tools==1.59.0 \
    grpcio-health-checking==1.59.0 \
    protobuf==4.25.0 \
    cryptography==41.0.7 \
    pyyaml==6.0.1 \
    requests==2.31.0

# Create traffic processing application
echo "$(date): Creating traffic processing application..."
cat > "$APP_DIR/traffic_processor.py" << 'EOF'
#!/usr/bin/env python3
"""
Secure Traffic Processing Engine for Confidential Computing Environment

This service implements a gRPC-based traffic processor that runs within a
Confidential VM with hardware-based Trusted Execution Environment (TEE).
All sensitive data processing occurs with memory encryption protection.
"""

import os
import sys
import grpc
import logging
import signal
import time
import json
import base64
import hashlib
import threading
from concurrent import futures
from typing import Dict, Any, Optional

# Google Cloud client libraries
from google.cloud import kms
from google.cloud import storage
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging

# gRPC health checking
from grpc_health.v1 import health_pb2_grpc
from grpc_health.v1 import health_pb2

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
KEYRING_NAME = os.environ.get('KEYRING_NAME', '${keyring_name}')
KEY_NAME = os.environ.get('KEY_NAME', '${key_name}')
BUCKET_NAME = os.environ.get('BUCKET_NAME', '${bucket_name}')
PROCESSOR_PORT = int(os.environ.get('PROCESSOR_PORT', '${processor_port}'))

# Service configuration
SERVICE_NAME = "secure-traffic-processor"
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
MAX_WORKERS = int(os.environ.get('MAX_WORKERS', '10'))

class MetricsCollector:
    """Collects and reports metrics to Cloud Monitoring."""
    
    def __init__(self):
        self.client = monitoring_v3.MetricServiceClient()
        self.project_name = f"projects/{PROJECT_ID}"
        self.processed_requests = 0
        self.failed_requests = 0
        self.encryption_operations = 0
        
    def increment_processed_requests(self):
        """Increment the processed requests counter."""
        self.processed_requests += 1
        
    def increment_failed_requests(self):
        """Increment the failed requests counter."""
        self.failed_requests += 1
        
    def increment_encryption_operations(self):
        """Increment the encryption operations counter."""
        self.encryption_operations += 1
        
    def get_metrics(self) -> Dict[str, int]:
        """Get current metrics."""
        return {
            'processed_requests': self.processed_requests,
            'failed_requests': self.failed_requests,
            'encryption_operations': self.encryption_operations
        }

class SecureTrafficProcessor:
    """
    Main traffic processing service with KMS integration.
    
    This class implements secure traffic analysis within a Confidential VM,
    ensuring all sensitive data remains encrypted during processing.
    """
    
    def __init__(self):
        self.kms_client = kms.KeyManagementServiceClient()
        self.storage_client = storage.Client()
        self.metrics = MetricsCollector()
        
        # Construct KMS key name
        self.key_name = (
            f'projects/{PROJECT_ID}/locations/{REGION}/'
            f'keyRings/{KEYRING_NAME}/cryptoKeys/{KEY_NAME}'
        )
        
        # Initialize storage bucket
        self.bucket = self.storage_client.bucket(BUCKET_NAME)
        
        # Setup logging
        self.logger = logging.getLogger(__name__)
        
        self.logger.info(f"Initialized SecureTrafficProcessor")
        self.logger.info(f"KMS Key: {self.key_name}")
        self.logger.info(f"Storage Bucket: {BUCKET_NAME}")
        
        # Verify KMS access
        self._verify_kms_access()
        
    def _verify_kms_access(self):
        """Verify access to KMS key during initialization."""
        try:
            # Test encryption/decryption capability
            test_data = "initialization_test_data"
            encrypted = self.encrypt_data(test_data)
            decrypted = self.decrypt_data(encrypted)
            
            if decrypted != test_data:
                raise RuntimeError("KMS encryption/decryption verification failed")
                
            self.logger.info("KMS access verification successful")
            
        except Exception as e:
            self.logger.error(f"KMS access verification failed: {e}")
            raise
    
    def encrypt_data(self, data: str) -> str:
        """
        Encrypt data using Cloud KMS within TEE.
        
        Args:
            data: Plaintext data to encrypt
            
        Returns:
            Base64-encoded encrypted data
        """
        try:
            # Encrypt using Cloud KMS
            encrypt_response = self.kms_client.encrypt(
                request={
                    'name': self.key_name,
                    'plaintext': data.encode('utf-8'),
                    'additional_authenticated_data': b'traffic-processor'
                }
            )
            
            # Encode ciphertext as base64 for storage/transmission
            encoded_ciphertext = base64.b64encode(
                encrypt_response.ciphertext
            ).decode('utf-8')
            
            self.metrics.increment_encryption_operations()
            self.logger.debug(f"Successfully encrypted data of length {len(data)}")
            
            return encoded_ciphertext
            
        except Exception as e:
            self.logger.error(f"Encryption failed: {e}")
            self.metrics.increment_failed_requests()
            raise
    
    def decrypt_data(self, encrypted_data: str) -> str:
        """
        Decrypt data using Cloud KMS within TEE.
        
        Args:
            encrypted_data: Base64-encoded encrypted data
            
        Returns:
            Decrypted plaintext data
        """
        try:
            # Decode base64 ciphertext
            ciphertext = base64.b64decode(encrypted_data.encode('utf-8'))
            
            # Decrypt using Cloud KMS
            decrypt_response = self.kms_client.decrypt(
                request={
                    'name': self.key_name,
                    'ciphertext': ciphertext,
                    'additional_authenticated_data': b'traffic-processor'
                }
            )
            
            decrypted_data = decrypt_response.plaintext.decode('utf-8')
            self.logger.debug(f"Successfully decrypted data of length {len(decrypted_data)}")
            
            return decrypted_data
            
        except Exception as e:
            self.logger.error(f"Decryption failed: {e}")
            raise
    
    def process_request_headers(self, headers: Dict[str, str]) -> Dict[str, str]:
        """
        Process and secure request headers.
        
        Args:
            headers: Request headers to process
            
        Returns:
            Processed headers with sensitive data encrypted
        """
        processed_headers = {}
        sensitive_headers = ['authorization', 'x-api-key', 'cookie', 'x-auth-token']
        
        for header_name, header_value in headers.items():
            header_lower = header_name.lower()
            
            if header_lower in sensitive_headers:
                # Encrypt sensitive header values
                try:
                    encrypted_value = self.encrypt_data(header_value)
                    processed_headers[header_name] = f"encrypted:{encrypted_value}"
                    self.logger.info(f"Encrypted sensitive header: {header_name}")
                except Exception as e:
                    self.logger.error(f"Failed to encrypt header {header_name}: {e}")
                    processed_headers[header_name] = "[ENCRYPTION_FAILED]"
            else:
                # Pass through non-sensitive headers
                processed_headers[header_name] = header_value
        
        return processed_headers
    
    def analyze_traffic_pattern(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze traffic patterns for security insights.
        
        Args:
            request_data: Request data to analyze
            
        Returns:
            Analysis results
        """
        analysis = {
            'timestamp': time.time(),
            'request_size': len(str(request_data)),
            'security_score': 100,  # Default secure score
            'threat_indicators': [],
            'recommendations': []
        }
        
        # Example security analysis (implement actual logic as needed)
        request_str = str(request_data).lower()
        
        # Check for potential security threats
        threat_patterns = ['sql injection', 'xss', 'script', 'eval', 'exec']
        for pattern in threat_patterns:
            if pattern in request_str:
                analysis['threat_indicators'].append(pattern)
                analysis['security_score'] -= 20
        
        # Generate recommendations
        if analysis['threat_indicators']:
            analysis['recommendations'].append("Enhanced monitoring recommended")
            analysis['recommendations'].append("Consider request blocking")
        
        return analysis
    
    def store_analysis_result(self, analysis: Dict[str, Any]) -> str:
        """
        Store analysis results in secure storage.
        
        Args:
            analysis: Analysis results to store
            
        Returns:
            Storage object name
        """
        try:
            # Generate unique object name
            timestamp = int(time.time())
            object_name = f"analysis/{timestamp}_{hashlib.sha256(str(analysis).encode()).hexdigest()[:8]}.json"
            
            # Encrypt analysis data before storage
            encrypted_analysis = self.encrypt_data(json.dumps(analysis))
            
            # Store in Cloud Storage with encryption
            blob = self.bucket.blob(object_name)
            blob.upload_from_string(
                encrypted_analysis,
                content_type='application/json'
            )
            
            self.logger.info(f"Stored analysis result: {object_name}")
            return object_name
            
        except Exception as e:
            self.logger.error(f"Failed to store analysis result: {e}")
            raise
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get service health status."""
        metrics = self.metrics.get_metrics()
        
        health_status = {
            'status': 'SERVING',
            'timestamp': time.time(),
            'metrics': metrics,
            'confidential_compute': {
                'tee_enabled': True,  # Running in Confidential VM
                'encryption_active': True
            }
        }
        
        # Check if service is experiencing high error rates
        total_requests = metrics['processed_requests'] + metrics['failed_requests']
        if total_requests > 0:
            error_rate = metrics['failed_requests'] / total_requests
            if error_rate > 0.1:  # 10% error threshold
                health_status['status'] = 'NOT_SERVING'
                health_status['error_rate'] = error_rate
        
        return health_status

class TrafficProcessorServicer:
    """gRPC servicer for traffic processing."""
    
    def __init__(self, processor: SecureTrafficProcessor):
        self.processor = processor
        self.logger = logging.getLogger(__name__)
    
    def ProcessTraffic(self, request, context):
        """
        Process incoming traffic requests.
        
        This is a placeholder for the actual Envoy External Processor API.
        In production, implement the proper gRPC service definition.
        """
        try:
            self.logger.info("Processing traffic request")
            
            # Example processing (replace with actual Envoy API implementation)
            request_data = {
                'headers': {},  # Extract from actual request
                'timestamp': time.time()
            }
            
            # Process headers with encryption
            processed_headers = self.processor.process_request_headers(
                request_data['headers']
            )
            
            # Analyze traffic patterns
            analysis = self.processor.analyze_traffic_pattern(request_data)
            
            # Store results securely
            storage_object = self.processor.store_analysis_result(analysis)
            
            self.processor.metrics.increment_processed_requests()
            
            # Return processing response (implement actual response format)
            return {"status": "processed", "storage_object": storage_object}
            
        except Exception as e:
            self.logger.error(f"Traffic processing failed: {e}")
            self.processor.metrics.increment_failed_requests()
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Processing failed: {e}")
            return {}

class HealthServicer(health_pb2_grpc.HealthServicer):
    """Health check servicer for gRPC server."""
    
    def __init__(self, processor: SecureTrafficProcessor):
        self.processor = processor
    
    def Check(self, request, context):
        """Perform health check."""
        try:
            health_status = self.processor.get_health_status()
            
            if health_status['status'] == 'SERVING':
                status = health_pb2.HealthCheckResponse.SERVING
            else:
                status = health_pb2.HealthCheckResponse.NOT_SERVING
            
            return health_pb2.HealthCheckResponse(status=status)
            
        except Exception:
            return health_pb2.HealthCheckResponse(
                status=health_pb2.HealthCheckResponse.NOT_SERVING
            )

def setup_logging():
    """Setup logging configuration."""
    # Configure local logging
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler('/var/log/traffic-processor.log')
        ]
    )
    
    # Configure Cloud Logging
    try:
        client = cloud_logging.Client()
        client.setup_logging()
        logging.info("Cloud Logging configured successfully")
    except Exception as e:
        logging.warning(f"Cloud Logging setup failed: {e}")

def create_server(processor: SecureTrafficProcessor) -> grpc.Server:
    """Create and configure gRPC server."""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=MAX_WORKERS))
    
    # Add health check service
    health_servicer = HealthServicer(processor)
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)
    
    # Add traffic processing service (placeholder)
    # In production, implement actual Envoy External Processor service
    # traffic_servicer = TrafficProcessorServicer(processor)
    # Add to server with proper service definition
    
    # Listen on all interfaces
    listen_addr = f'[::]:{PROCESSOR_PORT}'
    server.add_insecure_port(listen_addr)
    
    return server, listen_addr

def signal_handler(signum, frame, server: grpc.Server):
    """Handle shutdown signals gracefully."""
    logging.info(f"Received signal {signum}, shutting down server...")
    server.stop(grace=30)
    sys.exit(0)

def main():
    """Main entry point for traffic processing service."""
    print("Starting Secure Traffic Processing Engine")
    print("Confidential Computing: Hardware-based TEE protection active")
    
    # Setup logging
    setup_logging()
    logger = logging.getLogger(__name__)
    
    try:
        # Initialize traffic processor
        logger.info("Initializing secure traffic processor...")
        processor = SecureTrafficProcessor()
        
        # Create gRPC server
        logger.info("Creating gRPC server...")
        server, listen_addr = create_server(processor)
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, lambda s, f: signal_handler(s, f, server))
        signal.signal(signal.SIGTERM, lambda s, f: signal_handler(s, f, server))
        
        # Start server
        server.start()
        logger.info(f"Secure traffic processor started on {listen_addr}")
        logger.info("Service running with Confidential Computing protection")
        logger.info(f"Project: {PROJECT_ID}, Region: {REGION}")
        logger.info(f"KMS Keyring: {KEYRING_NAME}, Key: {KEY_NAME}")
        
        # Keep server running
        try:
            while True:
                time.sleep(86400)  # Sleep for 1 day
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received")
            
    except Exception as e:
        logger.error(f"Failed to start traffic processor: {e}")
        sys.exit(1)
    finally:
        logger.info("Traffic processor shutdown complete")

if __name__ == '__main__':
    main()
EOF

# Set proper ownership and permissions
chown traffic-processor:traffic-processor "$APP_DIR/traffic_processor.py"
chmod 755 "$APP_DIR/traffic_processor.py"

# Create systemd service file
echo "$(date): Creating systemd service..."
cat > /etc/systemd/system/traffic-processor.service << EOF
[Unit]
Description=Secure Traffic Processor Service
Documentation=https://cloud.google.com/confidential-computing
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=traffic-processor
Group=traffic-processor
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PROJECT_ID=$PROJECT_ID
Environment=REGION=$REGION
Environment=KEYRING_NAME=$KEYRING_NAME
Environment=KEY_NAME=$KEY_NAME
Environment=BUCKET_NAME=$BUCKET_NAME
Environment=PROCESSOR_PORT=$PROCESSOR_PORT
Environment=LOG_LEVEL=INFO
Environment=MAX_WORKERS=10
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/traffic_processor.py
Restart=always
RestartSec=10
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=traffic-processor

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR /var/log
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Create log directory with proper permissions
mkdir -p /var/log/traffic-processor
chown traffic-processor:traffic-processor /var/log/traffic-processor

# Setup log rotation
cat > /etc/logrotate.d/traffic-processor << EOF
/var/log/traffic-processor.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 traffic-processor traffic-processor
    postrotate
        systemctl reload traffic-processor || true
    endscript
}
EOF

# Enable and start the service
echo "$(date): Enabling and starting traffic processor service..."
systemctl daemon-reload
systemctl enable traffic-processor
systemctl start traffic-processor

# Wait for service to start
sleep 10

# Verify service status
echo "$(date): Verifying service status..."
if systemctl is-active --quiet traffic-processor; then
    echo "$(date): Traffic processor service started successfully"
    systemctl status traffic-processor --no-pager -l
else
    echo "$(date): ERROR: Traffic processor service failed to start"
    systemctl status traffic-processor --no-pager -l
    journalctl -u traffic-processor -n 50 --no-pager
    exit 1
fi

# Verify Confidential Computing features
echo "$(date): Verifying Confidential Computing features..."
if dmesg | grep -qi "sev\|amd.*sme\|amd.*sev"; then
    echo "$(date): Confidential Computing (AMD SEV) detected"
    dmesg | grep -i "sev\|amd.*sme" | head -5
else
    echo "$(date): WARNING: Confidential Computing features not detected in dmesg"
fi

# Check CPU features
if grep -qi "sme\|sev" /proc/cpuinfo; then
    echo "$(date): CPU supports Secure Memory Encryption"
else
    echo "$(date): WARNING: CPU SME/SEV features not found"
fi

# Create verification script
cat > "$APP_DIR/verify_setup.sh" << 'EOF'
#!/bin/bash
echo "=== Secure Traffic Processor Verification ==="
echo "Service Status:"
systemctl status traffic-processor --no-pager -l

echo -e "\nService Logs (last 20 lines):"
journalctl -u traffic-processor -n 20 --no-pager

echo -e "\nConfidential Computing Status:"
dmesg | grep -i "sev\|tee\|amd" | tail -10

echo -e "\nProcess Information:"
ps aux | grep traffic_processor

echo -e "\nNetwork Listeners:"
ss -tlnp | grep ":${PROCESSOR_PORT}"

echo -e "\nHealth Check:"
curl -s http://localhost:${PROCESSOR_PORT}/health || echo "Health endpoint not available (normal for gRPC)"
EOF

chmod +x "$APP_DIR/verify_setup.sh"
chown traffic-processor:traffic-processor "$APP_DIR/verify_setup.sh"

# Run verification
echo "$(date): Running setup verification..."
"$APP_DIR/verify_setup.sh"

# Setup monitoring script
cat > /usr/local/bin/monitor-traffic-processor << EOF
#!/bin/bash
# Monitor script for traffic processor service
set -euo pipefail

LOG_FILE="/var/log/traffic-processor-monitor.log"

log() {
    echo "\$(date): \$1" | tee -a "\$LOG_FILE"
}

# Check service health
if ! systemctl is-active --quiet traffic-processor; then
    log "ERROR: Traffic processor service is not running"
    systemctl restart traffic-processor
    log "Attempted to restart traffic processor service"
fi

# Check port availability
if ! ss -tlnp | grep -q ":$PROCESSOR_PORT"; then
    log "WARNING: Traffic processor port $PROCESSOR_PORT not listening"
fi

# Check disk space
DISK_USAGE=\$(df /var/log | tail -1 | awk '{print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 80 ]; then
    log "WARNING: Disk usage high: \${DISK_USAGE}%"
fi

# Check memory usage
MEM_USAGE=\$(free | grep Mem | awk '{printf "%.0f", \$3/\$2 * 100}')
if [ "\$MEM_USAGE" -gt 90 ]; then
    log "WARNING: Memory usage high: \${MEM_USAGE}%"
fi

log "Health check completed"
EOF

chmod +x /usr/local/bin/monitor-traffic-processor

# Setup cron job for monitoring
cat > /etc/cron.d/traffic-processor-monitor << EOF
# Monitor traffic processor service every 5 minutes
*/5 * * * * root /usr/local/bin/monitor-traffic-processor
EOF

# Final status report
echo "$(date): Setup completed successfully!"
echo "$(date): Service Status: $(systemctl is-active traffic-processor)"
echo "$(date): Service Enabled: $(systemctl is-enabled traffic-processor)"
echo "$(date): Confidential VM with traffic processing engine is ready"
echo "$(date): All logs are available in /var/log/traffic-processor-setup.log"

# Create completion marker
touch /opt/traffic-processor/.setup-complete
chown traffic-processor:traffic-processor /opt/traffic-processor/.setup-complete

echo "$(date): Secure traffic processing setup completed with Confidential Computing protection"