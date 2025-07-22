#!/usr/bin/env python3
"""
Secure API Application with Secret Manager Integration
This Flask application demonstrates secure configuration management using Google Cloud Secret Manager.
"""

import json
import os
import logging
from flask import Flask, jsonify, request
from google.cloud import secretmanager
from google.auth.exceptions import GoogleAuthError
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize Secret Manager client
try:
    client = secretmanager.SecretManagerServiceClient()
    logger.info("Secret Manager client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Secret Manager client: {e}")
    client = None

# Get project ID from environment
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# Secret names from environment variables
SECRET_NAMES = {
    'database': os.environ.get('DB_SECRET_NAME', '${secrets.database}'),
    'api_keys': os.environ.get('KEYS_SECRET_NAME', '${secrets.api_keys}'),
    'application': os.environ.get('CONFIG_SECRET_NAME', '${secrets.application}')
}

# Cache for secrets to reduce API calls
secret_cache = {}
cache_ttl = 300  # 5 minutes


def get_secret(secret_name, use_cache=True):
    """
    Retrieve secret from Secret Manager with caching and error handling
    
    Args:
        secret_name: Name of the secret to retrieve
        use_cache: Whether to use cached values
        
    Returns:
        dict: Parsed secret data or None if error
    """
    try:
        current_time = time.time()
        
        # Check cache first
        if use_cache and secret_name in secret_cache:
            cached_data, cached_time = secret_cache[secret_name]
            if current_time - cached_time < cache_ttl:
                logger.debug(f"Using cached secret: {secret_name}")
                return cached_data
        
        if not client:
            logger.error("Secret Manager client not initialized")
            return None
            
        # Construct the resource name
        name = f"projects/{PROJECT_ID}/secrets/{secret_name}/versions/latest"
        
        # Access the secret version
        response = client.access_secret_version(request={"name": name})
        secret_data = response.payload.data.decode("UTF-8")
        
        # Parse JSON data
        parsed_data = json.loads(secret_data)
        
        # Update cache
        if use_cache:
            secret_cache[secret_name] = (parsed_data, current_time)
            
        logger.info(f"Successfully retrieved secret: {secret_name}")
        return parsed_data
        
    except GoogleAuthError as e:
        logger.error(f"Authentication error accessing secret {secret_name}: {e}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON for secret {secret_name}: {e}")
        return None
    except Exception as e:
        logger.error(f"Failed to retrieve secret {secret_name}: {e}")
        return None


def validate_api_key(auth_header, api_keys):
    """
    Validate API key from Authorization header
    
    Args:
        auth_header: Authorization header value
        api_keys: Dictionary containing API keys
        
    Returns:
        bool: True if valid, False otherwise
    """
    if not auth_header or not api_keys:
        return False
        
    # Extract Bearer token
    if not auth_header.startswith('Bearer '):
        return False
        
    token = auth_header[7:]  # Remove 'Bearer ' prefix
    expected_key = api_keys.get('external_api_key')
    
    return token == expected_key


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return jsonify({
        "error": "Not found",
        "message": "The requested endpoint does not exist"
    }), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error(f"Internal server error: {error}")
    return jsonify({
        "error": "Internal server error",
        "message": "An unexpected error occurred"
    }), 500


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for load balancer and monitoring"""
    try:
        # Basic health check
        health_status = {
            "status": "healthy",
            "service": "secure-api",
            "environment": ENVIRONMENT,
            "timestamp": time.time(),
            "version": "1.0.0"
        }
        
        # Test Secret Manager connectivity
        if client:
            try:
                # Quick test to ensure Secret Manager is accessible
                test_secret = get_secret(SECRET_NAMES['application'], use_cache=True)
                health_status["secret_manager"] = "accessible" if test_secret else "error"
            except Exception as e:
                logger.warning(f"Secret Manager health check failed: {e}")
                health_status["secret_manager"] = "error"
        else:
            health_status["secret_manager"] = "not_initialized"
            
        return jsonify(health_status), 200
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 503


@app.route('/config', methods=['GET'])
def get_configuration():
    """
    Return non-sensitive application configuration
    Demonstrates safe exposure of configuration data
    """
    try:
        config = get_secret(SECRET_NAMES['application'])
        if not config:
            return jsonify({
                "error": "Configuration unavailable",
                "message": "Unable to retrieve application configuration"
            }), 500
        
        # Return only non-sensitive configuration
        safe_config = {
            "debug_mode": config.get("debug_mode", False),
            "rate_limit": config.get("rate_limit", 1000),
            "cache_ttl": config.get("cache_ttl", 3600),
            "log_level": config.get("log_level", "INFO"),
            "session_timeout": config.get("session_timeout", 1800),
            "environment": ENVIRONMENT,
            "retrieved_at": time.time()
        }
        
        return jsonify(safe_config), 200
        
    except Exception as e:
        logger.error(f"Failed to get configuration: {e}")
        return jsonify({
            "error": "Configuration error",
            "message": "An error occurred while retrieving configuration"
        }), 500


@app.route('/database/status', methods=['GET'])
def database_status():
    """
    Check database connectivity status using secrets
    Demonstrates secure database configuration retrieval
    """
    try:
        db_config = get_secret(SECRET_NAMES['database'])
        if not db_config:
            return jsonify({
                "error": "Database configuration unavailable",
                "message": "Unable to retrieve database configuration"
            }), 500
        
        # Return connection status (simulate database check)
        status_info = {
            "database": "connected",
            "host": db_config.get("host"),
            "port": db_config.get("port"),
            "database": db_config.get("database"),
            "ssl_mode": db_config.get("ssl_mode"),
            "connection_pool": "healthy",
            "last_check": time.time()
        }
        
        return jsonify(status_info), 200
        
    except Exception as e:
        logger.error(f"Database status check failed: {e}")
        return jsonify({
            "error": "Database status error",
            "message": "Unable to check database status"
        }), 500


@app.route('/api/data', methods=['GET'])
def get_secure_data():
    """
    Sample API endpoint with authentication
    Demonstrates API key validation using secrets
    """
    try:
        # Get API keys from Secret Manager
        api_keys = get_secret(SECRET_NAMES['api_keys'])
        if not api_keys:
            return jsonify({
                "error": "API keys unavailable",
                "message": "Unable to retrieve API keys for authentication"
            }), 500
        
        # Validate Authorization header
        auth_header = request.headers.get('Authorization')
        if not validate_api_key(auth_header, api_keys):
            return jsonify({
                "error": "Unauthorized",
                "message": "Invalid or missing API key"
            }), 401
        
        # Return secure data
        secure_data = {
            "data": "sensitive_api_data",
            "timestamp": time.time(),
            "source": "secure-api",
            "environment": ENVIRONMENT,
            "user_agent": request.headers.get('User-Agent', 'unknown'),
            "request_id": f"req_{int(time.time())}"
        }
        
        logger.info("Secure data accessed successfully")
        return jsonify(secure_data), 200
        
    except Exception as e:
        logger.error(f"Secure data access failed: {e}")
        return jsonify({
            "error": "Data access error",
            "message": "An error occurred while accessing secure data"
        }), 500


@app.route('/secrets/rotate', methods=['POST'])
def rotate_secrets():
    """
    Endpoint to trigger secret cache refresh
    This would typically be called by a secret rotation webhook
    """
    try:
        # Clear the secret cache to force refresh
        global secret_cache
        secret_cache.clear()
        
        logger.info("Secret cache cleared for rotation")
        return jsonify({
            "message": "Secret cache refreshed successfully",
            "timestamp": time.time()
        }), 200
        
    except Exception as e:
        logger.error(f"Secret rotation failed: {e}")
        return jsonify({
            "error": "Rotation error",
            "message": "Failed to refresh secret cache"
        }), 500


@app.route('/metrics', methods=['GET'])
def get_metrics():
    """
    Basic application metrics endpoint
    """
    try:
        metrics = {
            "cache_size": len(secret_cache),
            "environment": ENVIRONMENT,
            "uptime": time.time(),
            "secret_names": list(SECRET_NAMES.keys()),
            "client_initialized": client is not None
        }
        
        return jsonify(metrics), 200
        
    except Exception as e:
        logger.error(f"Metrics collection failed: {e}")
        return jsonify({
            "error": "Metrics error",
            "message": "Failed to collect metrics"
        }), 500


if __name__ == '__main__':
    # Log startup information
    logger.info(f"Starting Secure API application in {ENVIRONMENT} environment")
    logger.info(f"Project ID: {PROJECT_ID}")
    logger.info(f"Secret names configured: {list(SECRET_NAMES.keys())}")
    
    # Get port from environment (Cloud Run provides PORT)
    port = int(os.environ.get('PORT', 8080))
    
    # Run the application
    app.run(
        host='0.0.0.0',
        port=port,
        debug=(ENVIRONMENT == 'dev'),
        threaded=True
    )