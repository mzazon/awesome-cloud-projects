"""
Multi-Region Aurora DSQL Application Lambda Function
Handles API requests and database operations for the globally distributed application
"""

import json
import os
import boto3
import logging
from typing import Dict, Any, Optional
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
DSQL_ENDPOINT = os.environ.get('DSQL_ENDPOINT')
DSQL_REGION = os.environ.get('AWS_REGION')
DATABASE_NAME = os.environ.get('DATABASE_NAME', '${database_name}')
REGION_TYPE = os.environ.get('REGION_TYPE', 'unknown')


class DatabaseError(Exception):
    """Custom exception for database-related errors"""
    pass


class AuroraDSQLClient:
    """Aurora DSQL client for database operations"""
    
    def __init__(self):
        """Initialize Aurora DSQL client with IAM authentication"""
        try:
            self.client = boto3.client('dsql', region_name=DSQL_REGION)
            logger.info(f"Aurora DSQL client initialized for region: {DSQL_REGION}")
        except Exception as e:
            logger.error(f"Failed to create DSQL client: {str(e)}")
            raise DatabaseError(f"Database client initialization failed: {str(e)}")
    
    def execute_statement(self, sql: str, parameters: Optional[list] = None) -> Dict[str, Any]:
        """
        Execute SQL statement against Aurora DSQL cluster
        
        Args:
            sql: SQL statement to execute
            parameters: Optional list of parameters for prepared statements
            
        Returns:
            Result from Aurora DSQL execution
            
        Raises:
            DatabaseError: If statement execution fails
        """
        try:
            request = {
                'Database': DATABASE_NAME,
                'Sql': sql
            }
            
            if parameters:
                request['Parameters'] = parameters
            
            logger.info(f"Executing SQL: {sql[:100]}{'...' if len(sql) > 100 else ''}")
            response = self.client.execute_statement(**request)
            
            logger.info(f"SQL execution successful, affected rows: {response.get('numberOfRecordsUpdated', 0)}")
            return response
            
        except Exception as e:
            error_msg = f"SQL execution failed: {str(e)}"
            logger.error(error_msg)
            raise DatabaseError(error_msg)
    
    def select_users(self, limit: int = 100) -> list:
        """
        Retrieve all users from the database
        
        Args:
            limit: Maximum number of users to return
            
        Returns:
            List of user dictionaries
        """
        try:
            sql = """
                SELECT id, name, email, created_at, updated_at 
                FROM users 
                ORDER BY created_at DESC 
                LIMIT ?
            """
            
            result = self.execute_statement(sql, [{'longValue': limit}])
            
            users = []
            if 'Records' in result and result['Records']:
                for record in result['Records']:
                    user = {
                        'id': record[0].get('longValue'),
                        'name': record[1].get('stringValue'),
                        'email': record[2].get('stringValue'),
                        'created_at': record[3].get('stringValue'),
                        'updated_at': record[4].get('stringValue') if len(record) > 4 else None
                    }
                    users.append(user)
            
            logger.info(f"Retrieved {len(users)} users from database")
            return users
            
        except Exception as e:
            logger.error(f"Failed to retrieve users: {str(e)}")
            raise DatabaseError(f"User retrieval failed: {str(e)}")
    
    def create_user(self, name: str, email: str) -> Dict[str, Any]:
        """
        Create a new user in the database
        
        Args:
            name: User's full name
            email: User's email address
            
        Returns:
            Dictionary containing the created user information
        """
        try:
            sql = """
                INSERT INTO users (name, email, created_at, updated_at) 
                VALUES (?, ?, NOW(), NOW()) 
                RETURNING id, name, email, created_at
            """
            
            parameters = [
                {'stringValue': name},
                {'stringValue': email}
            ]
            
            result = self.execute_statement(sql, parameters)
            
            if 'Records' in result and result['Records']:
                record = result['Records'][0]
                user = {
                    'id': record[0].get('longValue'),
                    'name': record[1].get('stringValue'),
                    'email': record[2].get('stringValue'),
                    'created_at': record[3].get('stringValue'),
                    'region': REGION_TYPE
                }
                
                logger.info(f"Created user: {user['id']} - {user['email']}")
                return user
            else:
                raise DatabaseError("User creation failed - no records returned")
                
        except Exception as e:
            logger.error(f"Failed to create user: {str(e)}")
            raise DatabaseError(f"User creation failed: {str(e)}")
    
    def health_check(self) -> Dict[str, Any]:
        """
        Perform a health check on the database connection
        
        Returns:
            Dictionary containing health check results
        """
        try:
            sql = "SELECT 1 as health_check"
            result = self.execute_statement(sql)
            
            health_info = {
                'database_status': 'healthy',
                'region': DSQL_REGION,
                'region_type': REGION_TYPE,
                'endpoint': DSQL_ENDPOINT,
                'database_name': DATABASE_NAME,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'query_successful': True
            }
            
            logger.info("Database health check successful")
            return health_info
            
        except Exception as e:
            logger.error(f"Database health check failed: {str(e)}")
            return {
                'database_status': 'unhealthy',
                'region': DSQL_REGION,
                'region_type': REGION_TYPE,
                'endpoint': DSQL_ENDPOINT,
                'database_name': DATABASE_NAME,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'query_successful': False,
                'error': str(e)
            }


def create_response(status_code: int, body: Dict[str, Any], headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """
    Create a standardized API Gateway response
    
    Args:
        status_code: HTTP status code
        body: Response body as dictionary
        headers: Optional additional headers
        
    Returns:
        API Gateway response format
    """
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body, default=str)
    }


def validate_user_input(data: Dict[str, Any]) -> tuple[Optional[str], Optional[str]]:
    """
    Validate user input for user creation
    
    Args:
        data: Request data dictionary
        
    Returns:
        Tuple of (error_message, None) or (None, validated_data)
    """
    if not isinstance(data, dict):
        return "Invalid request format", None
    
    name = data.get('name', '').strip()
    email = data.get('email', '').strip()
    
    if not name:
        return "Name is required and cannot be empty", None
    
    if not email:
        return "Email is required and cannot be empty", None
    
    if len(name) > 100:
        return "Name cannot exceed 100 characters", None
    
    if len(email) > 255:
        return "Email cannot exceed 255 characters", None
    
    # Basic email validation
    if '@' not in email or '.' not in email.split('@')[-1]:
        return "Invalid email format", None
    
    return None, None


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for multi-region Aurora DSQL application
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        API Gateway response
    """
    try:
        # Log incoming request
        logger.info(f"Processing request: {event.get('httpMethod', 'UNKNOWN')} {event.get('path', 'UNKNOWN')}")
        
        # Parse request details
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        body = event.get('body')
        
        # Initialize database client
        db_client = AuroraDSQLClient()
        
        # Handle CORS preflight requests
        if http_method == 'OPTIONS':
            return create_response(200, {'message': 'CORS preflight successful'})
        
        # Route requests based on path and method
        if path == '/health' and http_method == 'GET':
            # Health check endpoint
            health_info = db_client.health_check()
            health_info['lambda_region'] = DSQL_REGION
            health_info['request_id'] = context.aws_request_id
            
            status_code = 200 if health_info.get('query_successful', False) else 503
            return create_response(status_code, health_info)
        
        elif path == '/users' and http_method == 'GET':
            # Get all users
            try:
                users = db_client.select_users()
                
                response_body = {
                    'users': users,
                    'count': len(users),
                    'region': DSQL_REGION,
                    'region_type': REGION_TYPE,
                    'timestamp': datetime.utcnow().isoformat() + 'Z'
                }
                
                return create_response(200, response_body)
                
            except DatabaseError as e:
                logger.error(f"Database error retrieving users: {str(e)}")
                return create_response(500, {
                    'error': 'Failed to retrieve users',
                    'details': str(e),
                    'region': DSQL_REGION
                })
        
        elif path == '/users' and http_method == 'POST':
            # Create new user
            try:
                # Parse request body
                if not body:
                    return create_response(400, {'error': 'Request body is required'})
                
                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    return create_response(400, {'error': 'Invalid JSON in request body'})
                
                # Validate input
                error_msg, _ = validate_user_input(data)
                if error_msg:
                    return create_response(400, {'error': error_msg})
                
                # Create user
                user = db_client.create_user(data['name'], data['email'])
                
                return create_response(201, user)
                
            except DatabaseError as e:
                logger.error(f"Database error creating user: {str(e)}")
                
                # Check for duplicate email error
                if 'duplicate' in str(e).lower() or 'unique' in str(e).lower():
                    return create_response(409, {
                        'error': 'User with this email already exists',
                        'region': DSQL_REGION
                    })
                
                return create_response(500, {
                    'error': 'Failed to create user',
                    'details': str(e),
                    'region': DSQL_REGION
                })
        
        else:
            # Unknown endpoint
            return create_response(404, {
                'error': 'Not found',
                'path': path,
                'method': http_method,
                'available_endpoints': {
                    'GET /health': 'Health check endpoint',
                    'GET /users': 'List all users',
                    'POST /users': 'Create new user'
                }
            })
    
    except Exception as e:
        # Catch-all error handler
        logger.error(f"Unhandled error in Lambda function: {str(e)}")
        return create_response(500, {
            'error': 'Internal server error',
            'details': str(e),
            'region': DSQL_REGION,
            'request_id': context.aws_request_id
        })