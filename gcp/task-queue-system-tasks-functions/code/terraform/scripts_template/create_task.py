#!/usr/bin/env python3
"""
Task creation script for Google Cloud Tasks queue.

This script demonstrates how to programmatically create tasks and submit them
to the Cloud Tasks queue for processing by the Cloud Function.

Usage:
    python create_task.py [task_type] [options]

Examples:
    python create_task.py process_file --filename="document.pdf" --content="Sample content"
    python create_task.py send_email --recipient="user@example.com" --subject="Hello"
    python create_task.py data_transform --transform_type="json_flatten"
"""

import argparse
import json
import sys
from datetime import datetime, timedelta
from google.cloud import tasks_v2
from google.auth import default

def create_task(project_id, location, queue_name, function_url, task_data, schedule_delay=0):
    """
    Create a task in Cloud Tasks queue.
    
    Args:
        project_id (str): GCP project ID
        location (str): GCP region where queue is located
        queue_name (str): Name of the Cloud Tasks queue
        function_url (str): URL of the Cloud Function to invoke
        task_data (dict): Task payload data
        schedule_delay (int): Delay in seconds before task execution
        
    Returns:
        Task: Created task response
    """
    try:
        # Initialize the Tasks client
        client = tasks_v2.CloudTasksClient()
        
        # Construct the fully qualified queue name
        parent = client.queue_path(project_id, location, queue_name)
        
        # Generate unique task ID
        task_id = f"task-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{hash(str(task_data)) % 10000:04d}"
        
        # Prepare task payload with metadata
        task_payload = {
            'task_id': task_id,
            'created_at': datetime.now().isoformat(),
            'project_id': project_id,
            'queue_name': queue_name,
            **task_data
        }
        
        # Create the HTTP request for the task
        http_request = {
            'http_method': tasks_v2.HttpMethod.POST,
            'url': function_url,
            'headers': {
                'Content-Type': 'application/json',
                'User-Agent': 'TaskCreationScript/1.0'
            },
            'body': json.dumps(task_payload).encode('utf-8')
        }
        
        # Create the task object
        task = {'http_request': http_request}
        
        # Add scheduling if delay is specified
        if schedule_delay > 0:
            schedule_time = datetime.now() + timedelta(seconds=schedule_delay)
            task['schedule_time'] = {
                'seconds': int(schedule_time.timestamp())
            }
            print(f"⏰ Task scheduled for: {schedule_time.isoformat()}")
        
        # Submit the task to the queue
        print(f"🚀 Creating task: {task_id}")
        print(f"📝 Task type: {task_data.get('task_type', 'unknown')}")
        print(f"📍 Queue: {queue_name} (location: {location})")
        
        response = client.create_task(request={
            'parent': parent, 
            'task': task
        })
        
        print(f"✅ Task created successfully!")
        print(f"   Task name: {response.name}")
        print(f"   Task ID: {task_id}")
        print(f"   Payload size: {len(json.dumps(task_payload))} bytes")
        
        return response
        
    except Exception as e:
        print(f"❌ Error creating task: {str(e)}")
        sys.exit(1)

def create_file_processing_task(args):
    """Create a file processing task."""
    return {
        'task_type': 'process_file',
        'filename': args.filename or f'sample-file-{datetime.now().strftime("%Y%m%d-%H%M%S")}.txt',
        'content': args.content or 'Default file content for processing',
        'content_type': args.content_type or 'text/plain',
        'processing_options': {
            'generate_metadata': True,
            'create_backup': args.backup,
            'compression': args.compression
        }
    }

def create_email_task(args):
    """Create an email sending task."""
    return {
        'task_type': 'send_email',
        'recipient': args.recipient or 'admin@example.com',
        'subject': args.subject or 'Background Task Notification',
        'body': args.body or 'Your background task has been completed successfully.',
        'email_type': args.email_type or 'notification',
        'priority': args.priority or 'normal',
        'processing_delay': args.processing_delay or 0
    }

def create_data_transform_task(args):
    """Create a data transformation task."""
    # Sample data for transformation
    sample_data = {
        'users': [
            {'id': 1, 'name': 'Alice', 'profile': {'age': 30, 'city': 'New York'}},
            {'id': 2, 'name': 'Bob', 'profile': {'age': 25, 'city': 'San Francisco'}}
        ],
        'metadata': {
            'version': '1.0',
            'created': datetime.now().isoformat()
        }
    }
    
    return {
        'task_type': 'data_transform',
        'transform_type': args.transform_type or 'json_flatten',
        'input_data': json.loads(args.input_data) if args.input_data else sample_data,
        'validation_rules': {
            'id': {'type': 'int', 'required': True},
            'name': {'type': 'str', 'required': True}
        } if args.validate else {},
        'target_format': args.target_format or 'json'
    }

def create_webhook_task(args):
    """Create a webhook notification task."""
    if not args.webhook_url:
        raise ValueError("webhook_url is required for webhook tasks")
    
    return {
        'task_type': 'webhook_notification',
        'webhook_url': args.webhook_url,
        'method': args.method or 'POST',
        'payload': json.loads(args.payload) if args.payload else {
            'event': 'task_completed',
            'timestamp': datetime.now().isoformat(),
            'message': 'Background task processing completed'
        },
        'headers': json.loads(args.headers) if args.headers else {
            'Content-Type': 'application/json',
            'User-Agent': 'TaskQueueSystem/1.0'
        }
    }

def main():
    """Main function to handle command line arguments and create tasks."""
    parser = argparse.ArgumentParser(
        description='Create tasks for Google Cloud Tasks queue',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s process_file --filename="report.pdf" --content="Monthly report data"
  %(prog)s send_email --recipient="user@company.com" --subject="Task Complete"
  %(prog)s data_transform --transform_type="json_flatten" --validate
  %(prog)s webhook_notification --webhook_url="https://api.example.com/notify"
        """
    )
    
    # Required positional argument
    parser.add_argument(
        'task_type',
        choices=['process_file', 'send_email', 'data_transform', 'webhook_notification'],
        help='Type of task to create'
    )
    
    # Global options
    parser.add_argument('--project-id', default='${project_id}', help='GCP project ID')
    parser.add_argument('--region', default='${region}', help='GCP region')
    parser.add_argument('--queue-name', default='${queue_name}', help='Cloud Tasks queue name')
    parser.add_argument('--function-url', default='${function_url}', help='Cloud Function URL')
    parser.add_argument('--schedule-delay', type=int, default=0, help='Delay in seconds before execution')
    parser.add_argument('--batch-size', type=int, default=1, help='Number of tasks to create')
    
    # File processing options
    parser.add_argument('--filename', help='Name of file to process')
    parser.add_argument('--content', help='File content to process')
    parser.add_argument('--content-type', help='MIME type of content')
    parser.add_argument('--backup', action='store_true', help='Create backup of original file')
    parser.add_argument('--compression', choices=['none', 'gzip', 'bzip2'], default='none', help='Compression type')
    
    # Email options
    parser.add_argument('--recipient', help='Email recipient address')
    parser.add_argument('--subject', help='Email subject')
    parser.add_argument('--body', help='Email body content')
    parser.add_argument('--email-type', choices=['notification', 'marketing', 'transactional'], help='Type of email')
    parser.add_argument('--priority', choices=['low', 'normal', 'high'], help='Email priority')
    parser.add_argument('--processing-delay', type=int, help='Simulated processing delay in seconds')
    
    # Data transformation options
    parser.add_argument('--transform-type', choices=['json_flatten', 'data_validation', 'format_conversion'], help='Type of transformation')
    parser.add_argument('--input-data', help='Input data as JSON string')
    parser.add_argument('--target-format', choices=['json', 'csv', 'xml'], help='Target format for conversion')
    parser.add_argument('--validate', action='store_true', help='Enable data validation')
    
    # Webhook options
    parser.add_argument('--webhook-url', help='Webhook URL to notify')
    parser.add_argument('--method', choices=['GET', 'POST', 'PUT', 'PATCH'], help='HTTP method for webhook')
    parser.add_argument('--payload', help='Webhook payload as JSON string')
    parser.add_argument('--headers', help='HTTP headers as JSON string')
    
    args = parser.parse_args()
    
    # Validate required environment or configuration
    if not all([args.project_id, args.region, args.queue_name, args.function_url]):
        print("❌ Error: Missing required configuration. Please ensure all parameters are provided.")
        sys.exit(1)
    
    # Create task data based on type
    try:
        if args.task_type == 'process_file':
            task_data = create_file_processing_task(args)
        elif args.task_type == 'send_email':
            task_data = create_email_task(args)
        elif args.task_type == 'data_transform':
            task_data = create_data_transform_task(args)
        elif args.task_type == 'webhook_notification':
            task_data = create_webhook_task(args)
        else:
            raise ValueError(f"Unsupported task type: {args.task_type}")
        
        # Create tasks (support batch creation)
        print(f"🎯 Creating {args.batch_size} task(s) of type '{args.task_type}'")
        print("-" * 60)
        
        created_tasks = []
        for i in range(args.batch_size):
            if args.batch_size > 1:
                # Modify task data for batch processing
                batch_task_data = task_data.copy()
                batch_task_data['batch_index'] = i + 1
                batch_task_data['batch_total'] = args.batch_size
                
                # Add variation for file processing
                if args.task_type == 'process_file' and 'filename' in batch_task_data:
                    base_name, ext = batch_task_data['filename'].rsplit('.', 1) if '.' in batch_task_data['filename'] else (batch_task_data['filename'], 'txt')
                    batch_task_data['filename'] = f"{base_name}_{i+1:03d}.{ext}"
            else:
                batch_task_data = task_data
            
            task_response = create_task(
                args.project_id,
                args.region,
                args.queue_name,
                args.function_url,
                batch_task_data,
                args.schedule_delay
            )
            created_tasks.append(task_response)
            
            if args.batch_size > 1 and i < args.batch_size - 1:
                print("-" * 40)
        
        print("\n" + "=" * 60)
        print(f"🎉 Successfully created {len(created_tasks)} task(s)!")
        print(f"📊 Monitor progress in Google Cloud Console:")
        print(f"   https://console.cloud.google.com/cloudtasks/queue/{args.region}/{args.queue_name}?project={args.project_id}")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()