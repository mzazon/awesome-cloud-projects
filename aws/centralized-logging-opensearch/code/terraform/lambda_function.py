import json
import base64
import gzip
import boto3
import datetime
import os
import re
from typing import Dict, List, Any

firehose = boto3.client('firehose')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process CloudWatch Logs data from Kinesis stream
    Enrich logs and forward to Kinesis Data Firehose
    """
    records_to_firehose = []
    error_count = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            compressed_payload = base64.b64decode(record['kinesis']['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Process each log event
            for log_event in log_data.get('logEvents', []):
                enriched_log = enrich_log_event(log_event, log_data)
                
                # Convert to JSON string for Firehose
                json_record = json.dumps(enriched_log) + '\n'
                
                records_to_firehose.append({
                    'Data': json_record
                })
                
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            error_count += 1
            continue
    
    # Send processed records to Firehose
    if records_to_firehose:
        try:
            response = firehose.put_record_batch(
                DeliveryStreamName=os.environ['FIREHOSE_STREAM_NAME'],
                Records=records_to_firehose
            )
            
            failed_records = response.get('FailedPutCount', 0)
            if failed_records > 0:
                print(f"Failed to process {failed_records} records")
                
        except Exception as e:
            print(f"Error sending to Firehose: {str(e)}")
            error_count += len(records_to_firehose)
    
    # Send metrics to CloudWatch
    if error_count > 0:
        cloudwatch.put_metric_data(
            Namespace='CentralLogging/Processing',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    
    return {
        'statusCode': 200,
        'processedRecords': len(records_to_firehose),
        'errorCount': error_count
    }

def enrich_log_event(log_event: Dict, log_data: Dict) -> Dict:
    """
    Enrich log events with additional metadata and parsing
    """
    enriched = {
        '@timestamp': datetime.datetime.fromtimestamp(
            log_event['timestamp'] / 1000
        ).isoformat() + 'Z',
        'message': log_event.get('message', ''),
        'log_group': log_data.get('logGroup', ''),
        'log_stream': log_data.get('logStream', ''),
        'aws_account_id': log_data.get('owner', ''),
        'aws_region': os.environ.get('AWS_REGION', ''),
        'source_type': determine_source_type(log_data.get('logGroup', ''))
    }
    
    # Parse structured logs (JSON)
    try:
        if log_event['message'].strip().startswith('{'):
            parsed_message = json.loads(log_event['message'])
            enriched['parsed_message'] = parsed_message
            
            # Extract common fields
            if 'level' in parsed_message:
                enriched['log_level'] = parsed_message['level'].upper()
            if 'timestamp' in parsed_message:
                enriched['original_timestamp'] = parsed_message['timestamp']
                
    except (json.JSONDecodeError, KeyError):
        pass
    
    # Extract log level from message
    if 'log_level' not in enriched:
        enriched['log_level'] = extract_log_level(log_event['message'])
    
    # Add security context for security-related logs
    if is_security_related(log_event['message'], log_data.get('logGroup', '')):
        enriched['security_event'] = True
        enriched['priority'] = 'high'
    
    return enriched

def determine_source_type(log_group: str) -> str:
    """Determine the type of service generating the logs"""
    if '/aws/lambda/' in log_group:
        return 'lambda'
    elif '/aws/apigateway/' in log_group:
        return 'api-gateway'
    elif '/aws/rds/' in log_group:
        return 'rds'
    elif '/aws/vpc/flowlogs' in log_group:
        return 'vpc-flow-logs'
    elif 'cloudtrail' in log_group.lower():
        return 'cloudtrail'
    else:
        return 'application'

def extract_log_level(message: str) -> str:
    """Extract log level from message content"""
    log_levels = ['ERROR', 'WARN', 'WARNING', 'INFO', 'DEBUG', 'TRACE']
    message_upper = message.upper()
    
    for level in log_levels:
        if level in message_upper:
            return level
    
    return 'INFO'

def is_security_related(message: str, log_group: str) -> bool:
    """Identify potentially security-related log events"""
    security_keywords = [
        'authentication failed', 'access denied', 'unauthorized',
        'security group', 'iam', 'login failed', 'brute force',
        'suspicious', 'blocked', 'firewall', 'intrusion'
    ]
    
    message_lower = message.lower()
    log_group_lower = log_group.lower()
    
    # Check for security keywords
    for keyword in security_keywords:
        if keyword in message_lower:
            return True
    
    # Security-related log groups
    if any(term in log_group_lower for term in ['cloudtrail', 'security', 'auth', 'iam']):
        return True
    
    return False