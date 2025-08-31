"""
Business Process Approval Cloud Function

This function processes approval decisions for business processes with database integration.
Designed for deployment via Terraform with Cloud SQL connectivity.
"""

import functions_framework
import json
import os
import pg8000
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def approve_process(request):
    """
    Process approval function with business logic and database integration.
    
    Expected request format:
    {
        "request_id": "string",
        "decision": "approve|reject", 
        "approver_email": "string",
        "comments": "string (optional)"
    }
    """
    try:
        # Enable CORS for web requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }

        if request.method != 'POST':
            return ({'error': 'Method not allowed'}, 405, headers)
        
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'No JSON data provided'}, 400, headers)
        
        # Extract required parameters
        request_id = request_json.get('request_id')
        decision = request_json.get('decision')
        approver = request_json.get('approver_email')
        comments = request_json.get('comments', '')
        
        if not all([request_id, decision, approver]):
            return ({'error': 'Missing required fields: request_id, decision, approver_email'}, 400, headers)
        
        if decision not in ['approve', 'reject']:
            return ({'error': 'Decision must be "approve" or "reject"'}, 400, headers)
        
        logger.info(f"Processing approval request: {request_id}, decision: {decision}")
        
        # Connect to Cloud SQL using Unix socket (for private connections)
        # or TCP connection (for public connections)
        try:
            conn = get_database_connection()
            cursor = conn.cursor()
            
            # Start transaction
            cursor.execute("BEGIN")
            
            # Check if request exists
            cursor.execute("""
                SELECT id, status FROM process_requests 
                WHERE request_id = %s
            """, (request_id,))
            
            result = cursor.fetchone()
            if not result:
                cursor.execute("ROLLBACK")
                conn.close()
                return ({'error': f'Request {request_id} not found'}, 404, headers)
            
            request_db_id, current_status = result
            
            # Check if request is already processed
            if current_status in ['approved', 'rejected']:
                cursor.execute("ROLLBACK")
                conn.close()
                return ({'error': f'Request {request_id} already {current_status}'}, 409, headers)
            
            # Record approval decision
            cursor.execute("""
                INSERT INTO process_approvals 
                (request_id, approver_email, decision, comments)
                VALUES (%s, %s, %s, %s)
                RETURNING id
            """, (request_id, approver, decision, comments))
            
            approval_id = cursor.fetchone()[0]
            
            # Update process status
            new_status = 'approved' if decision == 'approve' else 'rejected'
            cursor.execute("""
                UPDATE process_requests 
                SET status = %s, updated_at = CURRENT_TIMESTAMP
                WHERE request_id = %s
            """, (new_status, request_id))
            
            # Add audit entry
            audit_details = {
                'approval_id': approval_id,
                'decision': decision,
                'comments': comments,
                'previous_status': current_status,
                'new_status': new_status
            }
            
            cursor.execute("""
                INSERT INTO process_audit 
                (request_id, action, actor, details)
                VALUES (%s, %s, %s, %s)
            """, (request_id, f'Process {decision}d', approver, json.dumps(audit_details)))
            
            # Commit transaction
            cursor.execute("COMMIT")
            conn.close()
            
            logger.info(f"Successfully processed approval: {request_id} -> {new_status}")
            
            response_data = {
                'status': 'success',
                'request_id': request_id,
                'new_status': new_status,
                'approval_id': approval_id,
                'processed_at': datetime.utcnow().isoformat() + 'Z'
            }
            
            return (response_data, 200, headers)
            
        except Exception as db_error:
            logger.error(f"Database error: {str(db_error)}")
            try:
                cursor.execute("ROLLBACK")
                conn.close()
            except:
                pass
            return ({'error': 'Database operation failed', 'details': str(db_error)}, 500, headers)
        
    except Exception as e:
        logger.error(f"Unexpected error in approve_process: {str(e)}")
        return ({'error': 'Internal server error', 'details': str(e)}, 500, headers)


def get_database_connection():
    """
    Establish connection to Cloud SQL database.
    Supports both Unix socket (private) and TCP (public) connections.
    """
    project_id = os.environ.get('PROJECT_ID', '${project_id}')
    region = os.environ.get('REGION', '${region}')
    db_instance = os.environ.get('DB_INSTANCE', '${db_instance}')
    db_password = os.environ.get('DB_PASSWORD')
    
    if not db_password:
        raise ValueError("DB_PASSWORD environment variable not set")
    
    # Try Unix socket connection first (for private IP)
    db_socket_path = "/cloudsql"
    instance_connection_name = f"{project_id}:{region}:{db_instance}"
    
    try:
        # Attempt Unix socket connection
        unix_socket = f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432"
        conn = pg8000.connect(
            user='postgres',
            password=db_password,
            unix_sock=unix_socket,
            database='business_processes'
        )
        logger.info("Connected to database via Unix socket")
        return conn
        
    except Exception as unix_error:
        logger.warning(f"Unix socket connection failed: {unix_error}")
        
        # Fallback to TCP connection (for public IP)
        try:
            # Note: In production, you would get the actual IP address
            # This is a simplified example
            conn = pg8000.connect(
                user='postgres',
                password=db_password,
                host='127.0.0.1',  # This would be the actual Cloud SQL IP
                port=5432,
                database='business_processes'
            )
            logger.info("Connected to database via TCP")
            return conn
            
        except Exception as tcp_error:
            logger.error(f"TCP connection failed: {tcp_error}")
            raise Exception(f"Failed to connect to database. Unix socket: {unix_error}, TCP: {tcp_error}")


def validate_approval_request(request_data):
    """
    Validate approval request data and business rules.
    """
    required_fields = ['request_id', 'decision', 'approver_email']
    missing_fields = [field for field in required_fields if not request_data.get(field)]
    
    if missing_fields:
        return False, f"Missing required fields: {', '.join(missing_fields)}"
    
    if request_data['decision'] not in ['approve', 'reject']:
        return False, "Decision must be 'approve' or 'reject'"
    
    # Basic email validation
    approver_email = request_data['approver_email']
    if '@' not in approver_email or '.' not in approver_email.split('@')[1]:
        return False, "Invalid approver email format"
    
    return True, "Valid"


if __name__ == "__main__":
    # For local testing
    import sys
    from unittest.mock import Mock
    
    # Mock request for testing
    mock_request = Mock()
    mock_request.method = 'POST'
    mock_request.get_json.return_value = {
        'request_id': 'test-001',
        'decision': 'approve',
        'approver_email': 'manager@company.com',
        'comments': 'Approved for business necessity'
    }
    
    print("Testing approval function...")
    try:
        result = approve_process(mock_request)
        print(f"Result: {result}")
    except Exception as e:
        print(f"Error: {e}")