"""
Lambda function for generating operational log data for CloudWatch Insights analytics.

This function generates diverse, realistic log patterns that simulate production applications,
including various log levels, performance metrics, and business events. The generated logs
are designed to demonstrate CloudWatch Logs Insights capabilities for operational analytics.

Environment Variables:
    LOG_GROUP_NAME: CloudWatch log group where logs will be written
    ENVIRONMENT: Deployment environment (dev, staging, prod)
"""

import json
import random
import time
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Log patterns for realistic operational data
LOG_PATTERNS = [
    {
        "level": "INFO", 
        "message": "User authentication successful", 
        "user_id": lambda: f"user_{random.randint(1000, 9999)}", 
        "response_time": lambda: random.randint(100, 500),
        "endpoint": "/auth/login",
        "method": "POST"
    },
    {
        "level": "ERROR", 
        "message": "Database connection failed", 
        "error_code": "DB_CONN_ERR", 
        "retry_count": lambda: random.randint(1, 3),
        "endpoint": "/api/v1/data",
        "method": "GET"
    },
    {
        "level": "WARN", 
        "message": "High memory usage detected", 
        "memory_usage": lambda: random.randint(70, 95), 
        "threshold": 80,
        "service": "webapp"
    },
    {
        "level": "INFO", 
        "message": "API request processed", 
        "endpoint": lambda: f"/api/v1/users/{random.randint(1, 100)}", 
        "method": lambda: random.choice(["GET", "POST", "PUT"]),
        "response_time": lambda: random.randint(50, 300)
    },
    {
        "level": "ERROR", 
        "message": "Payment processing failed", 
        "transaction_id": lambda: f"txn_{random.randint(100000, 999999)}", 
        "amount": lambda: random.randint(10, 1000),
        "error_code": "PAYMENT_DECLINED"
    },
    {
        "level": "INFO", 
        "message": "Cache hit", 
        "cache_key": lambda: f"user_profile_{random.randint(1, 1000)}", 
        "hit_rate": lambda: round(random.uniform(0.7, 0.95), 3),
        "response_time": lambda: random.randint(5, 50)
    },
    {
        "level": "DEBUG", 
        "message": "SQL query executed", 
        "query_time": lambda: random.randint(50, 2000), 
        "table": lambda: random.choice(["users", "orders", "products", "sessions"]),
        "rows_affected": lambda: random.randint(1, 100)
    },
    {
        "level": "WARN", 
        "message": "Rate limit approaching", 
        "current_rate": lambda: random.randint(80, 99), 
        "limit": 100,
        "user_id": lambda: f"user_{random.randint(1000, 9999)}"
    },
    {
        "level": "INFO", 
        "message": "File upload completed", 
        "file_size": lambda: random.randint(1024, 10485760), 
        "file_type": lambda: random.choice(["pdf", "jpg", "png", "doc", "csv"]),
        "response_time": lambda: random.randint(200, 2000)
    },
    {
        "level": "ERROR", 
        "message": "Service unavailable", 
        "service": lambda: random.choice(["payment-service", "notification-service", "user-service"]),
        "error_code": "SERVICE_UNAVAILABLE",
        "retry_after": lambda: random.randint(30, 300)
    }
]

def generate_log_entry() -> Dict[str, Any]:
    """
    Generate a single realistic log entry with random data.
    
    Returns:
        Dict[str, Any]: Log entry with timestamp, level, message, and metadata
    """
    pattern = random.choice(LOG_PATTERNS)
    log_entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "request_id": f"req_{random.randint(1000000, 9999999)}",
        "environment": os.environ.get("ENVIRONMENT", "dev")
    }
    
    # Copy static values and evaluate callable values
    for key, value in pattern.items():
        if callable(value):
            log_entry[key] = value()
        else:
            log_entry[key] = value
    
    # Add additional contextual information based on log level
    if log_entry["level"] == "ERROR":
        log_entry["stack_trace"] = f"Error occurred at line {random.randint(100, 500)}"
        log_entry["correlation_id"] = f"corr_{random.randint(100000, 999999)}"
    elif log_entry["level"] == "WARN":
        log_entry["threshold_percentage"] = round(random.uniform(0.8, 0.95), 2)
    
    return log_entry

def write_log_entry(log_entry: Dict[str, Any]) -> None:
    """
    Write log entry to CloudWatch Logs with appropriate log level.
    
    Args:
        log_entry (Dict[str, Any]): Log entry to write
    """
    log_json = json.dumps(log_entry, default=str)
    
    # Log with appropriate level
    level = log_entry.get("level", "INFO")
    if level == "ERROR":
        logger.error(log_json)
    elif level == "WARN":
        logger.warning(log_json)
    elif level == "DEBUG":
        logger.debug(log_json)
    else:
        logger.info(log_json)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler function for generating operational log data.
    
    This function generates 5-10 random log entries with realistic patterns
    including different log levels, performance metrics, and business events.
    The logs are written to CloudWatch Logs for analysis with Logs Insights.
    
    Args:
        event (Dict[str, Any]): Lambda event data
        context (Any): Lambda context object
        
    Returns:
        Dict[str, Any]: Response with status code and generation summary
    """
    try:
        # Generate random number of log entries (5-10)
        num_entries = random.randint(5, 10)
        generated_entries = []
        
        logger.info(json.dumps({
            "message": "Starting log generation",
            "num_entries": num_entries,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "request_id": context.aws_request_id if hasattr(context, 'aws_request_id') else "unknown"
        }))
        
        # Generate and write log entries
        for i in range(num_entries):
            log_entry = generate_log_entry()
            write_log_entry(log_entry)
            generated_entries.append({
                "level": log_entry["level"],
                "message_type": log_entry["message"],
                "timestamp": log_entry["timestamp"]
            })
            
            # Small delay to spread timestamps realistically
            time.sleep(0.1)
        
        # Log completion summary
        completion_summary = {
            "message": "Log generation completed successfully",
            "total_entries": num_entries,
            "entries_by_level": {
                level: len([e for e in generated_entries if e["level"] == level])
                for level in ["INFO", "WARN", "ERROR", "DEBUG"]
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "request_id": context.aws_request_id if hasattr(context, 'aws_request_id') else "unknown"
        }
        
        logger.info(json.dumps(completion_summary))
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log generation completed successfully',
                'entries_generated': num_entries,
                'summary': completion_summary
            })
        }
        
    except Exception as e:
        error_details = {
            "message": "Error during log generation",
            "error": str(e),
            "error_type": type(e).__name__,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "request_id": context.aws_request_id if hasattr(context, 'aws_request_id') else "unknown"
        }
        
        logger.error(json.dumps(error_details))
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error during log generation',
                'error': str(e)
            })
        }