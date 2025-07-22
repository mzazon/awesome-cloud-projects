"""
Task Processor Lambda Function for Real-Time Collaborative Task Management

This Lambda function handles task operations and event processing with Aurora DSQL integration.
It supports event-driven processing via EventBridge and direct API invocation patterns.

Features:
- Event-driven task processing (create, update, complete)
- Direct API operations via Lambda invocation
- Aurora DSQL database integration with connection pooling
- Comprehensive error handling and logging
- Event publishing for downstream notifications
- Multi-region aware configuration

Environment Variables Required:
- DSQL_CLUSTER_ENDPOINT: Aurora DSQL cluster endpoint
- DSQL_CLUSTER_PORT: Aurora DSQL cluster port
- DB_SECRET_ARN: AWS Secrets Manager ARN for database credentials
- EVENT_BUS_NAME: EventBridge custom event bus name
- AWS_REGION: Current AWS region
- ENVIRONMENT: Environment name (dev/test/staging/prod)
- LOG_LEVEL: Logging level (DEBUG/INFO/WARN/ERROR)
"""

import json
import boto3
import psycopg2
import os
import logging
from datetime import datetime
from typing import Dict, Any, Optional, List
from contextlib import contextmanager
import traceback

# Configure structured logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.environ.get('LOG_LEVEL', 'INFO')))

# Initialize AWS clients with retry configuration
events_client = boto3.client('events', 
    region_name=os.environ.get('AWS_REGION'),
    config=boto3.session.Config(
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )
)

secrets_client = boto3.client('secretsmanager',
    region_name=os.environ.get('AWS_REGION'),
    config=boto3.session.Config(
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )
)

# Global connection pool for database connections
connection_pool = None

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for task management operations.
    
    Supports two invocation patterns:
    1. EventBridge events (source: task.management)
    2. Direct API requests (httpMethod, path)
    
    Args:
        event: Lambda event payload
        context: Lambda context object
        
    Returns:
        Dict containing statusCode and response body
    """
    try:
        # Log incoming event for debugging (sanitized)
        logger.info("Processing event", extra={
            "event_source": event.get('source', 'direct'),
            "event_type": event.get('detail-type', 'unknown'),
            "request_id": context.aws_request_id if context else 'unknown'
        })
        
        # Initialize database connection pool if not exists
        initialize_connection_pool()
        
        # Route based on event source
        if 'source' in event and event['source'] == 'task.management':
            return process_task_event(event, context)
        else:
            return process_direct_request(event, context)
            
    except Exception as e:
        logger.error("Error processing event", extra={
            "error": str(e),
            "traceback": traceback.format_exc(),
            "event_source": event.get('source', 'unknown'),
            "request_id": context.aws_request_id if context else 'unknown'
        })
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e),
                'request_id': context.aws_request_id if context else 'unknown'
            }),
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': context.aws_request_id if context else 'unknown'
            }
        }

def initialize_connection_pool() -> None:
    """
    Initialize database connection pool with Aurora DSQL credentials.
    Uses connection pooling for better performance and resource utilization.
    """
    global connection_pool
    
    if connection_pool is None:
        try:
            # Get database credentials from Secrets Manager
            db_credentials = get_database_credentials()
            
            # Configure connection pool parameters
            connection_pool = {
                'host': os.environ['DSQL_CLUSTER_ENDPOINT'],
                'port': int(os.environ['DSQL_CLUSTER_PORT']),
                'database': 'postgres',
                'user': db_credentials['username'],
                'password': db_credentials['password'],
                'connect_timeout': 10,
                'application_name': f"task-management-{os.environ.get('ENVIRONMENT', 'dev')}"
            }
            
            logger.info("Connection pool initialized", extra={
                "host": connection_pool['host'],
                "database": connection_pool['database'],
                "user": connection_pool['user']
            })
            
        except Exception as e:
            logger.error("Failed to initialize connection pool", extra={
                "error": str(e),
                "traceback": traceback.format_exc()
            })
            raise

def get_database_credentials() -> Dict[str, str]:
    """
    Retrieve database credentials from AWS Secrets Manager.
    
    Returns:
        Dict containing username and password
    """
    try:
        response = secrets_client.get_secret_value(
            SecretId=os.environ['DB_SECRET_ARN']
        )
        credentials = json.loads(response['SecretString'])
        
        logger.debug("Retrieved database credentials from Secrets Manager")
        return credentials
        
    except Exception as e:
        logger.error("Failed to retrieve database credentials", extra={
            "error": str(e),
            "secret_arn": os.environ.get('DB_SECRET_ARN', 'not_set')
        })
        raise

@contextmanager
def get_db_connection():
    """
    Context manager for database connections with automatic cleanup.
    Provides connection pooling and error handling.
    
    Yields:
        psycopg2.connection: Database connection object
    """
    conn = None
    try:
        conn = psycopg2.connect(**connection_pool)
        conn.autocommit = False  # Enable transaction control
        
        logger.debug("Database connection established")
        yield conn
        
    except Exception as e:
        if conn:
            conn.rollback()
        logger.error("Database connection error", extra={
            "error": str(e),
            "traceback": traceback.format_exc()
        })
        raise
    finally:
        if conn:
            conn.close()
            logger.debug("Database connection closed")

def process_task_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process EventBridge task management events.
    
    Supported event types:
    - task.created: Handle new task creation
    - task.updated: Handle task updates
    - task.completed: Handle task completion
    
    Args:
        event: EventBridge event payload
        context: Lambda context object
        
    Returns:
        Dict containing processing result
    """
    try:
        detail = event['detail']
        event_type = detail['eventType']
        
        logger.info("Processing task event", extra={
            "event_type": event_type,
            "request_id": context.aws_request_id
        })
        
        if event_type == 'task.created':
            return handle_task_created(detail, context)
        elif event_type == 'task.updated':
            return handle_task_updated(detail, context)
        elif event_type == 'task.completed':
            return handle_task_completed(detail, context)
        else:
            logger.warning("Unknown event type", extra={
                "event_type": event_type,
                "request_id": context.aws_request_id
            })
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'event_type': event_type
            })
        }
        
    except Exception as e:
        logger.error("Error processing task event", extra={
            "error": str(e),
            "event_type": detail.get('eventType', 'unknown'),
            "request_id": context.aws_request_id
        })
        raise

def handle_task_created(detail: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle task creation events from EventBridge.
    
    Args:
        detail: Event detail containing task data
        context: Lambda context object
        
    Returns:
        Dict containing creation result
    """
    task_data = detail['taskData']
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        try:
            # Insert new task with validation
            cursor.execute("""
                INSERT INTO tasks (
                    title, description, status, priority, assigned_to, 
                    created_by, project_id, due_date, created_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                RETURNING id, created_at
            """, (
                task_data.get('title', '').strip(),
                task_data.get('description', '').strip(),
                task_data.get('status', 'pending'),
                task_data.get('priority', 'medium'),
                task_data.get('assigned_to', '').strip(),
                task_data.get('created_by', '').strip(),
                task_data.get('project_id'),
                task_data.get('due_date')
            ))
            
            result = cursor.fetchone()
            task_id, created_at = result[0], result[1]
            conn.commit()
            
            logger.info("Task created successfully", extra={
                "task_id": task_id,
                "title": task_data.get('title', ''),
                "created_by": task_data.get('created_by', ''),
                "request_id": context.aws_request_id
            })
            
            # Publish task creation notification
            publish_task_notification('task.created', task_id, {
                **task_data,
                'created_at': created_at.isoformat()
            })
            
            return {
                'statusCode': 201,
                'body': json.dumps({
                    'message': 'Task created successfully',
                    'task_id': task_id,
                    'created_at': created_at.isoformat()
                })
            }
            
        except psycopg2.IntegrityError as e:
            conn.rollback()
            logger.error("Database integrity error during task creation", extra={
                "error": str(e),
                "task_data": task_data,
                "request_id": context.aws_request_id
            })
            raise Exception("Task creation failed: Data validation error")
            
        except Exception as e:
            conn.rollback()
            logger.error("Error creating task", extra={
                "error": str(e),
                "task_data": task_data,
                "request_id": context.aws_request_id
            })
            raise

def handle_task_updated(detail: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle task update events from EventBridge.
    
    Args:
        detail: Event detail containing task updates
        context: Lambda context object
        
    Returns:
        Dict containing update result
    """
    task_id = detail['taskId']
    updates = detail['updates']
    updated_by = detail['updatedBy']
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        try:
            # Check if task exists
            cursor.execute("SELECT id, title FROM tasks WHERE id = %s", (task_id,))
            if not cursor.fetchone():
                return {
                    'statusCode': 404,
                    'body': json.dumps({
                        'error': 'Task not found',
                        'task_id': task_id
                    })
                }
            
            # Process each update with change tracking
            changes_logged = []
            
            for field, new_value in updates.items():
                if field in ['title', 'description', 'status', 'priority', 'assigned_to', 'due_date']:
                    # Get current value for change tracking
                    cursor.execute(f"SELECT {field} FROM tasks WHERE id = %s", (task_id,))
                    old_value = cursor.fetchone()[0]
                    
                    # Update the field
                    cursor.execute(f"""
                        UPDATE tasks 
                        SET {field} = %s, updated_at = CURRENT_TIMESTAMP
                        WHERE id = %s
                    """, (new_value, task_id))
                    
                    # Log the change in task_updates table
                    cursor.execute("""
                        INSERT INTO task_updates (
                            task_id, field_name, old_value, new_value, 
                            updated_by, updated_at
                        )
                        VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                    """, (task_id, field, str(old_value) if old_value else '', 
                         str(new_value) if new_value else '', updated_by))
                    
                    changes_logged.append({
                        'field': field,
                        'old_value': old_value,
                        'new_value': new_value
                    })
            
            conn.commit()
            
            logger.info("Task updated successfully", extra={
                "task_id": task_id,
                "updates": updates,
                "updated_by": updated_by,
                "changes_count": len(changes_logged),
                "request_id": context.aws_request_id
            })
            
            # Publish task update notification
            publish_task_notification('task.updated', task_id, {
                'updates': updates,
                'updated_by': updated_by,
                'changes': changes_logged
            })
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Task updated successfully',
                    'task_id': task_id,
                    'changes_applied': len(changes_logged)
                })
            }
            
        except Exception as e:
            conn.rollback()
            logger.error("Error updating task", extra={
                "error": str(e),
                "task_id": task_id,
                "updates": updates,
                "request_id": context.aws_request_id
            })
            raise

def handle_task_completed(detail: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle task completion events from EventBridge.
    
    Args:
        detail: Event detail containing completion data
        context: Lambda context object
        
    Returns:
        Dict containing completion result
    """
    task_id = detail['taskId']
    completed_by = detail['completedBy']
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        try:
            # Update task status and completion timestamp
            cursor.execute("""
                UPDATE tasks 
                SET status = 'completed', 
                    completed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING title, assigned_to
            """, (task_id,))
            
            result = cursor.fetchone()
            if not result:
                return {
                    'statusCode': 404,
                    'body': json.dumps({
                        'error': 'Task not found',
                        'task_id': task_id
                    })
                }
            
            title, assigned_to = result[0], result[1]
            
            # Log completion change
            cursor.execute("""
                INSERT INTO task_updates (
                    task_id, field_name, old_value, new_value, 
                    updated_by, updated_at
                )
                VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            """, (task_id, 'status', 'in-progress', 'completed', completed_by))
            
            conn.commit()
            
            logger.info("Task completed successfully", extra={
                "task_id": task_id,
                "title": title,
                "completed_by": completed_by,
                "assigned_to": assigned_to,
                "request_id": context.aws_request_id
            })
            
            # Publish task completion notification
            publish_task_notification('task.completed', task_id, {
                'completed_by': completed_by,
                'title': title,
                'assigned_to': assigned_to
            })
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Task completed successfully',
                    'task_id': task_id,
                    'title': title
                })
            }
            
        except Exception as e:
            conn.rollback()
            logger.error("Error completing task", extra={
                "error": str(e),
                "task_id": task_id,
                "completed_by": completed_by,
                "request_id": context.aws_request_id
            })
            raise

def publish_task_notification(event_type: str, task_id: int, data: Dict[str, Any]) -> None:
    """
    Publish task notification events to EventBridge for downstream processing.
    
    Args:
        event_type: Type of event (task.created, task.updated, task.completed)
        task_id: ID of the task
        data: Additional event data
    """
    try:
        event_payload = {
            'Source': 'task.management.notifications',
            'DetailType': 'Task Notification',
            'Detail': json.dumps({
                'eventType': event_type,
                'taskId': task_id,
                'data': data,
                'timestamp': datetime.utcnow().isoformat(),
                'environment': os.environ.get('ENVIRONMENT', 'dev')
            }),
            'EventBusName': os.environ['EVENT_BUS_NAME']
        }
        
        response = events_client.put_events(Entries=[event_payload])
        
        if response['FailedEntryCount'] > 0:
            logger.error("Failed to publish notification", extra={
                "event_type": event_type,
                "task_id": task_id,
                "failed_entries": response['Entries']
            })
        else:
            logger.info("Notification published successfully", extra={
                "event_type": event_type,
                "task_id": task_id,
                "event_id": response['Entries'][0]['EventId']
            })
            
    except Exception as e:
        logger.error("Error publishing notification", extra={
            "error": str(e),
            "event_type": event_type,
            "task_id": task_id
        })
        # Don't raise - notification failure shouldn't fail main operation

def process_direct_request(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process direct API requests to Lambda function.
    
    Supported operations:
    - GET /tasks: List all tasks
    - POST /tasks: Create new task
    - PUT /tasks/{id}: Update existing task
    - GET /tasks/{id}: Get specific task
    
    Args:
        event: Direct request event payload
        context: Lambda context object
        
    Returns:
        Dict containing API response
    """
    try:
        method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        logger.info("Processing direct API request", extra={
            "method": method,
            "path": path,
            "request_id": context.aws_request_id
        })
        
        if method == 'GET' and path == '/tasks':
            return get_all_tasks(context)
        elif method == 'POST' and path == '/tasks':
            body = json.loads(event.get('body', '{}'))
            return create_task_direct(body, context)
        elif method == 'PUT' and '/tasks/' in path:
            task_id = path.split('/')[-1]
            body = json.loads(event.get('body', '{}'))
            return update_task_direct(task_id, body, context)
        elif method == 'GET' and '/tasks/' in path:
            task_id = path.split('/')[-1]
            return get_task_by_id(task_id, context)
        else:
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'Endpoint not found',
                    'method': method,
                    'path': path
                }),
                'headers': {'Content-Type': 'application/json'}
            }
    
    except Exception as e:
        logger.error("Error processing direct request", extra={
            "error": str(e),
            "method": event.get('httpMethod', 'unknown'),
            "path": event.get('path', 'unknown'),
            "request_id": context.aws_request_id
        })
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            }),
            'headers': {'Content-Type': 'application/json'}
        }

def get_all_tasks(context: Any) -> Dict[str, Any]:
    """
    Retrieve all tasks from the database with pagination support.
    
    Args:
        context: Lambda context object
        
    Returns:
        Dict containing list of tasks
    """
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT 
                id, title, description, status, priority, assigned_to, 
                created_by, created_at, updated_at, project_id, due_date, 
                completed_at
            FROM tasks 
            ORDER BY created_at DESC
            LIMIT 100
        """)
        
        tasks = []
        for row in cursor.fetchall():
            tasks.append({
                'id': row[0],
                'title': row[1],
                'description': row[2],
                'status': row[3],
                'priority': row[4],
                'assigned_to': row[5],
                'created_by': row[6],
                'created_at': row[7].isoformat() if row[7] else None,
                'updated_at': row[8].isoformat() if row[8] else None,
                'project_id': row[9],
                'due_date': row[10].isoformat() if row[10] else None,
                'completed_at': row[11].isoformat() if row[11] else None
            })
        
        logger.info("Retrieved tasks successfully", extra={
            "task_count": len(tasks),
            "request_id": context.aws_request_id
        })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'tasks': tasks,
                'count': len(tasks)
            }),
            'headers': {'Content-Type': 'application/json'}
        }

def get_task_by_id(task_id: str, context: Any) -> Dict[str, Any]:
    """
    Retrieve a specific task by ID.
    
    Args:
        task_id: Task identifier
        context: Lambda context object
        
    Returns:
        Dict containing task details
    """
    try:
        task_id_int = int(task_id)
    except ValueError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid task ID'}),
            'headers': {'Content-Type': 'application/json'}
        }
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT 
                id, title, description, status, priority, assigned_to,
                created_by, created_at, updated_at, project_id, due_date,
                completed_at
            FROM tasks 
            WHERE id = %s
        """, (task_id_int,))
        
        row = cursor.fetchone()
        if not row:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Task not found'}),
                'headers': {'Content-Type': 'application/json'}
            }
        
        task = {
            'id': row[0],
            'title': row[1],
            'description': row[2],
            'status': row[3],
            'priority': row[4],
            'assigned_to': row[5],
            'created_by': row[6],
            'created_at': row[7].isoformat() if row[7] else None,
            'updated_at': row[8].isoformat() if row[8] else None,
            'project_id': row[9],
            'due_date': row[10].isoformat() if row[10] else None,
            'completed_at': row[11].isoformat() if row[11] else None
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({'task': task}),
            'headers': {'Content-Type': 'application/json'}
        }

def create_task_direct(task_data: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Create a new task via direct API call.
    
    Args:
        task_data: Task creation data
        context: Lambda context object
        
    Returns:
        Dict containing creation result
    """
    # Validate required fields
    if not task_data.get('title') or not task_data.get('created_by'):
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Missing required fields',
                'required': ['title', 'created_by']
            }),
            'headers': {'Content-Type': 'application/json'}
        }
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        try:
            cursor.execute("""
                INSERT INTO tasks (
                    title, description, status, priority, assigned_to,
                    created_by, project_id, due_date, created_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                RETURNING id, created_at
            """, (
                task_data['title'].strip(),
                task_data.get('description', '').strip(),
                task_data.get('status', 'pending'),
                task_data.get('priority', 'medium'),
                task_data.get('assigned_to', '').strip(),
                task_data['created_by'].strip(),
                task_data.get('project_id'),
                task_data.get('due_date')
            ))
            
            result = cursor.fetchone()
            task_id, created_at = result[0], result[1]
            conn.commit()
            
            # Publish creation event
            publish_task_notification('task.created', task_id, {
                **task_data,
                'created_at': created_at.isoformat()
            })
            
            return {
                'statusCode': 201,
                'body': json.dumps({
                    'message': 'Task created successfully',
                    'task_id': task_id,
                    'created_at': created_at.isoformat()
                }),
                'headers': {'Content-Type': 'application/json'}
            }
            
        except Exception as e:
            conn.rollback()
            logger.error("Error creating task via direct API", extra={
                "error": str(e),
                "task_data": task_data,
                "request_id": context.aws_request_id
            })
            raise

def update_task_direct(task_id: str, updates: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Update an existing task via direct API call.
    
    Args:
        task_id: Task identifier
        updates: Task update data
        context: Lambda context object
        
    Returns:
        Dict containing update result
    """
    try:
        task_id_int = int(task_id)
    except ValueError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid task ID'}),
            'headers': {'Content-Type': 'application/json'}
        }
    
    if not updates.get('updated_by'):
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Missing required field: updated_by'
            }),
            'headers': {'Content-Type': 'application/json'}
        }
    
    # Process via event-driven handler
    event_detail = {
        'eventType': 'task.updated',
        'taskId': task_id_int,
        'updates': {k: v for k, v in updates.items() if k != 'updated_by'},
        'updatedBy': updates['updated_by']
    }
    
    return handle_task_updated(event_detail, context)