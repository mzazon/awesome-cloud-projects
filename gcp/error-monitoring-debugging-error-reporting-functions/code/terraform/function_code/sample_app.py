import json
import random
import time
from datetime import datetime
from google.cloud import error_reporting
from google.cloud import logging as cloud_logging
from flask import Flask, request, jsonify
import functions_framework

# Initialize error reporting client
error_client = error_reporting.Client()
logging_client = cloud_logging.Client()

app = Flask(__name__)

@functions_framework.http
def sample_app(request):
    """Sample application that generates various errors"""
    try:
        # Parse request
        request_json = request.get_json(silent=True)
        error_type = request_json.get('error_type', 'none') if request_json else 'none'
        
        # Generate different types of errors based on request
        if error_type == 'critical':
            simulate_critical_error()
        elif error_type == 'database':
            simulate_database_error()
        elif error_type == 'timeout':
            simulate_timeout_error()
        elif error_type == 'null_pointer':
            simulate_null_pointer_error()
        elif error_type == 'memory':
            simulate_memory_error()
        elif error_type == 'random':
            simulate_random_error()
        else:
            return jsonify({'status': 'success', 'message': 'No error generated'})
            
    except Exception as e:
        # Report error to Cloud Error Reporting
        error_client.report_exception()
        return jsonify({'status': 'error', 'message': str(e)}), 500

def simulate_critical_error():
    """Simulate a critical system error"""
    error_client.report(
        "CRITICAL: Payment processing system failure - Unable to process transactions",
        service="payment-service",
        version="1.2.0",
        user="user123"
    )
    raise Exception("Payment processing system failure")

def simulate_database_error():
    """Simulate a database connection error"""
    error_client.report(
        "Database connection failed: Connection timeout to primary database",
        service="user-service",
        version="2.1.0",
        user="system"
    )
    raise Exception("Database connection failed")

def simulate_timeout_error():
    """Simulate a timeout error"""
    error_client.report(
        "Request timeout: External API call exceeded 30 second timeout",
        service="api-gateway",
        version="1.0.5",
        user="anonymous"
    )
    raise Exception("Request timeout")

def simulate_null_pointer_error():
    """Simulate a null pointer error"""
    error_client.report(
        "NullPointerException: User object is null in session management",
        service="session-service",
        version="3.0.1",
        user="user456"
    )
    raise Exception("NullPointerException")

def simulate_memory_error():
    """Simulate a memory error"""
    error_client.report(
        "OutOfMemoryError: Java heap space exceeded during data processing",
        service="data-processor",
        version="2.3.0",
        user="system"
    )
    raise Exception("OutOfMemoryError")

def simulate_random_error():
    """Simulate a random error"""
    error_types = [
        ("Service temporarily unavailable", "load-balancer"),
        ("Invalid input format", "validation-service"),
        ("Authentication token expired", "auth-service"),
        ("File not found", "file-service"),
        ("Network connection lost", "network-service")
    ]
    
    error_msg, service = random.choice(error_types)
    error_client.report(
        error_msg,
        service=service,
        version="1.0.0",
        user=f"user{random.randint(100, 999)}"
    )
    raise Exception(error_msg)