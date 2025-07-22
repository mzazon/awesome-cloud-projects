import json
import boto3
import os
from datetime import datetime, timedelta
import uuid

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Replay messages from S3 archive back to processing queue
    """
    try:
        # Parse replay request
        replay_request = event.get('replay_request', {})
        
        # Default parameters
        start_time = replay_request.get('start_time')
        end_time = replay_request.get('end_time', datetime.utcnow().isoformat())
        message_group_filter = replay_request.get('message_group_id')
        dry_run = replay_request.get('dry_run', True)
        
        if not start_time:
            # Default to last hour
            start_time = (datetime.utcnow() - timedelta(hours=1)).isoformat()
        
        print(f"Replaying messages from {start_time} to {end_time}")
        print(f"Message group filter: {message_group_filter}")
        print(f"Dry run mode: {dry_run}")
        
        # List archived messages in time range
        archived_messages = list_archived_messages(start_time, end_time, message_group_filter)
        
        replay_results = {
            'total_found': len(archived_messages),
            'replayed': 0,
            'skipped': 0,
            'errors': 0,
            'dry_run': dry_run
        }
        
        for message_info in archived_messages:
            try:
                if should_replay_message(message_info):
                    if not dry_run:
                        replay_result = replay_single_message(message_info)
                        if replay_result['success']:
                            replay_results['replayed'] += 1
                        else:
                            replay_results['errors'] += 1
                    else:
                        replay_results['replayed'] += 1
                        print(f"DRY RUN: Would replay message {message_info['key']}")
                else:
                    replay_results['skipped'] += 1
                    
            except Exception as e:
                print(f"Error processing archived message {message_info['key']}: {str(e)}")
                replay_results['errors'] += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(replay_results)
        }
        
    except Exception as e:
        print(f"Error in message replay: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def list_archived_messages(start_time, end_time, message_group_filter=None):
    """
    List archived messages within time range
    """
    archived_messages = []
    
    try:
        # Convert times to datetime objects for filtering
        start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
        
        # List objects in S3 bucket with poison-messages prefix
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(
            Bucket='${archive_bucket_name}',
            Prefix='poison-messages/'
        )
        
        for page in pages:
            for obj in page.get('Contents', []):
                # Extract timestamp from object key
                try:
                    # Parse key format: poison-messages/YYYY/MM/DD/HHMMSS-uuid.json
                    key_parts = obj['Key'].split('/')
                    if len(key_parts) >= 5:
                        date_part = '/'.join(key_parts[1:4])  # YYYY/MM/DD
                        filename = key_parts[4]
                        time_part = filename.split('-')[0]    # HHMMSS
                        
                        # Reconstruct timestamp
                        timestamp_str = f"{date_part.replace('/', '')}T{time_part[:2]}:{time_part[2:4]}:{time_part[4:6]}"
                        msg_dt = datetime.strptime(timestamp_str, '%Y%m%dT%H:%M:%S')
                        
                        if start_dt <= msg_dt <= end_dt:
                            message_info = {
                                'key': obj['Key'],
                                'timestamp': msg_dt,
                                'size': obj['Size'],
                                'metadata': obj.get('Metadata', {})
                            }
                            
                            # Apply message group filter if specified
                            if not message_group_filter or obj.get('Metadata', {}).get('message-group-id') == message_group_filter:
                                archived_messages.append(message_info)
                
                except Exception as e:
                    print(f"Error parsing object key {obj['Key']}: {str(e)}")
                    continue
        
        print(f"Found {len(archived_messages)} archived messages in time range")
        return archived_messages
        
    except Exception as e:
        print(f"Error listing archived messages: {str(e)}")
        return []

def should_replay_message(message_info):
    """
    Determine if a message should be replayed based on analysis
    """
    try:
        # Get message content from S3
        response = s3.get_object(
            Bucket='${archive_bucket_name}',
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        analysis = message_data.get('analysis', {})
        
        # Only replay recoverable messages or those with medium/low severity
        if analysis.get('recoverable', False) or analysis.get('severity') in ['MEDIUM', 'LOW']:
            return True
        
        # Skip critical non-recoverable messages
        return False
        
    except Exception as e:
        print(f"Error analyzing message for replay: {str(e)}")
        return False

def replay_single_message(message_info):
    """
    Replay a single message back to the processing queue
    """
    try:
        # Get message content from S3
        response = s3.get_object(
            Bucket='${archive_bucket_name}',
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        original_message = message_data['originalMessage']
        
        # Add replay metadata
        replay_message = original_message.copy()
        replay_message['replayed'] = True
        replay_message['replay_timestamp'] = datetime.utcnow().isoformat()
        replay_message['original_archive_key'] = message_info['key']
        
        # Determine message group ID
        message_group_id = message_info.get('metadata', {}).get('message-group-id', 'replay-group')
        
        # Send message back to main queue
        response = sqs.send_message(
            QueueUrl='${main_queue_url}',
            MessageBody=json.dumps(replay_message),
            MessageGroupId=message_group_id,
            MessageDeduplicationId=f"replay-{uuid.uuid4()}"
        )
        
        print(f"Successfully replayed message {message_info['key']}: {response['MessageId']}")
        
        return {
            'success': True,
            'message_id': response['MessageId']
        }
        
    except Exception as e:
        print(f"Error replaying message {message_info['key']}: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }