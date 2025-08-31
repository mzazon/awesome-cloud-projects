"""
Lambda function for transforming VPC Lattice access logs for OpenSearch analytics.

This function processes log records from Kinesis Data Firehose, enriches them with
analytical fields, and formats them for optimal indexing in OpenSearch Service.
The transformation includes parsing JSON logs, adding derived fields for analytics,
and categorizing response times and error codes.
"""

import json
import base64
import gzip
import datetime
from typing import List, Dict, Any


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, List[Dict[str, Any]]]:
    """
    Main Lambda handler function for processing Firehose records.
    
    Args:
        event: Event data from Kinesis Data Firehose containing records to transform
        context: Lambda runtime context information
        
    Returns:
        Dictionary containing transformed records for Firehose delivery
    """
    output = []
    
    for record in event.get('records', []):
        try:
            # Process each record from Firehose
            transformed_record = process_record(record)
            output.append(transformed_record)
            
        except Exception as e:
            # Mark record as processing failed if transformation fails
            print(f"Error processing record {record.get('recordId', 'unknown')}: {str(e)}")
            output.append({
                'recordId': record.get('recordId'),
                'result': 'ProcessingFailed'
            })
    
    return {'records': output}


def process_record(record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a single Firehose record.
    
    Args:
        record: Individual record from Firehose delivery stream
        
    Returns:
        Transformed record ready for OpenSearch indexing
    """
    try:
        # Decode and decompress the data
        compressed_payload = base64.b64decode(record['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        # Transform and enrich each log entry
        transformed_logs = []
        
        for log_entry in log_data.get('logEvents', []):
            try:
                # Parse the log message
                parsed_log = parse_log_message(log_entry, log_data)
                transformed_logs.append(json.dumps(parsed_log))
                
            except Exception as e:
                print(f"Error parsing log entry: {str(e)}")
                # Create a basic log entry for unparseable messages
                fallback_log = create_fallback_log(log_entry, log_data)
                transformed_logs.append(json.dumps(fallback_log))
        
        # Combine all log entries with newline separation
        combined_output = '\n'.join(transformed_logs) + '\n'
        
        # Encode for Firehose delivery
        encoded_data = base64.b64encode(combined_output.encode('utf-8')).decode('utf-8')
        
        return {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': encoded_data
        }
        
    except Exception as e:
        print(f"Error processing record: {str(e)}")
        return {
            'recordId': record['recordId'],
            'result': 'ProcessingFailed'
        }


def parse_log_message(log_entry: Dict[str, Any], log_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse and enrich a log message.
    
    Args:
        log_entry: Individual log entry from CloudWatch Logs
        log_data: Parent log data containing metadata
        
    Returns:
        Enriched log entry with analytical fields
    """
    # Check if the message is JSON format (VPC Lattice access logs)
    message = log_entry.get('message', '')
    
    if message.startswith('{') and message.endswith('}'):
        # Parse JSON log message
        parsed_log = json.loads(message)
        
        # Add timestamp and metadata
        parsed_log['@timestamp'] = convert_timestamp(log_entry.get('timestamp'))
        parsed_log['log_group'] = log_data.get('logGroup', '')
        parsed_log['log_stream'] = log_data.get('logStream', '')
        
        # Add derived analytical fields
        add_response_analysis(parsed_log)
        add_timing_analysis(parsed_log)
        add_traffic_classification(parsed_log)
        add_security_indicators(parsed_log)
        
        return parsed_log
    else:
        # Handle non-JSON messages
        return create_basic_log_entry(log_entry, log_data)


def create_fallback_log(log_entry: Dict[str, Any], log_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a fallback log entry for unparseable messages.
    
    Args:
        log_entry: Original log entry
        log_data: Parent log data
        
    Returns:
        Basic log entry with minimal processing
    """
    return create_basic_log_entry(log_entry, log_data)


def create_basic_log_entry(log_entry: Dict[str, Any], log_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a basic log entry for non-JSON messages.
    
    Args:
        log_entry: Original log entry
        log_data: Parent log data
        
    Returns:
        Basic structured log entry
    """
    return {
        'message': log_entry.get('message', ''),
        '@timestamp': convert_timestamp(log_entry.get('timestamp')),
        'log_group': log_data.get('logGroup', ''),
        'log_stream': log_data.get('logStream', ''),
        'log_type': 'unstructured',
        'processing_version': '1.0'
    }


def convert_timestamp(timestamp_ms: int) -> str:
    """
    Convert CloudWatch Logs timestamp to ISO format.
    
    Args:
        timestamp_ms: Timestamp in milliseconds
        
    Returns:
        ISO formatted timestamp string
    """
    if timestamp_ms:
        return datetime.datetime.fromtimestamp(
            timestamp_ms / 1000, tz=datetime.timezone.utc
        ).isoformat()
    else:
        return datetime.datetime.utcnow().isoformat()


def add_response_analysis(log_entry: Dict[str, Any]) -> None:
    """
    Add response code analysis fields.
    
    Args:
        log_entry: Log entry to enrich (modified in place)
    """
    response_code = log_entry.get('responseCode')
    if response_code is not None:
        try:
            response_code = int(response_code)
            log_entry['response_code_int'] = response_code
            log_entry['response_class'] = f"{str(response_code)[0]}xx"
            log_entry['is_error'] = response_code >= 400
            log_entry['is_server_error'] = response_code >= 500
            log_entry['is_client_error'] = 400 <= response_code < 500
            log_entry['is_success'] = 200 <= response_code < 300
            log_entry['is_redirect'] = 300 <= response_code < 400
        except (ValueError, TypeError):
            log_entry['response_code_parse_error'] = True


def add_timing_analysis(log_entry: Dict[str, Any]) -> None:
    """
    Add response timing analysis fields.
    
    Args:
        log_entry: Log entry to enrich (modified in place)
    """
    response_time_ms = log_entry.get('responseTimeMs')
    if response_time_ms is not None:
        try:
            response_time_ms = float(response_time_ms)
            log_entry['response_time_ms_float'] = response_time_ms
            log_entry['response_time_bucket'] = categorize_response_time(response_time_ms)
            log_entry['response_time_seconds'] = response_time_ms / 1000
            
            # Add performance indicators
            log_entry['is_fast_response'] = response_time_ms < 100
            log_entry['is_slow_response'] = response_time_ms > 2000
            log_entry['is_timeout_risk'] = response_time_ms > 10000
            
        except (ValueError, TypeError):
            log_entry['response_time_parse_error'] = True


def add_traffic_classification(log_entry: Dict[str, Any]) -> None:
    """
    Add traffic classification fields.
    
    Args:
        log_entry: Log entry to enrich (modified in place)
    """
    # Classify by request method
    method = log_entry.get('requestMethod', '').upper()
    log_entry['is_read_operation'] = method in ['GET', 'HEAD', 'OPTIONS']
    log_entry['is_write_operation'] = method in ['POST', 'PUT', 'PATCH', 'DELETE']
    
    # Classify by path patterns
    path = log_entry.get('requestPath', '')
    log_entry['is_api_request'] = '/api/' in path.lower()
    log_entry['is_health_check'] = any(keyword in path.lower() for keyword in ['/health', '/ping', '/status'])
    log_entry['is_static_content'] = any(path.lower().endswith(ext) for ext in ['.css', '.js', '.png', '.jpg', '.gif', '.ico'])
    
    # Extract API version if present
    if '/v' in path and '/api/' in path.lower():
        try:
            version_start = path.lower().find('/v') + 2
            version_end = path.find('/', version_start)
            if version_end == -1:
                version_end = len(path)
            version = path[version_start:version_end]
            if version.isdigit():
                log_entry['api_version'] = f"v{version}"
        except Exception:
            pass


def add_security_indicators(log_entry: Dict[str, Any]) -> None:
    """
    Add security-related analysis fields.
    
    Args:
        log_entry: Log entry to enrich (modified in place)
    """
    # Analyze User-Agent for potential security concerns
    user_agent = log_entry.get('userAgent', '').lower()
    if user_agent:
        log_entry['is_bot_request'] = any(bot in user_agent for bot in ['bot', 'crawler', 'spider', 'scraper'])
        log_entry['is_automation'] = any(tool in user_agent for tool in ['curl', 'wget', 'python', 'postman'])
    
    # Check for suspicious request patterns
    path = log_entry.get('requestPath', '').lower()
    log_entry['potential_security_scan'] = any(pattern in path for pattern in [
        '../', '..\\', 'etc/passwd', 'cmd.exe', '<script', 'union select', 'drop table'
    ])
    
    # Analyze source IP patterns (basic classification)
    source_ip = log_entry.get('sourceIpPort', '').split(':')[0] if log_entry.get('sourceIpPort') else ''
    if source_ip:
        log_entry['is_private_ip'] = is_private_ip(source_ip)
        log_entry['source_ip'] = source_ip


def categorize_response_time(response_time_ms: float) -> str:
    """
    Categorize response times for analytics dashboards.
    
    Args:
        response_time_ms: Response time in milliseconds
        
    Returns:
        Response time category string
    """
    if response_time_ms < 50:
        return 'very_fast'
    elif response_time_ms < 200:
        return 'fast'
    elif response_time_ms < 1000:
        return 'medium'
    elif response_time_ms < 5000:
        return 'slow'
    else:
        return 'very_slow'


def is_private_ip(ip: str) -> bool:
    """
    Check if an IP address is in private IP ranges.
    
    Args:
        ip: IP address string
        
    Returns:
        True if IP is in private ranges, False otherwise
    """
    try:
        parts = [int(part) for part in ip.split('.')]
        if len(parts) != 4:
            return False
        
        # Check private IP ranges
        # 10.0.0.0/8
        if parts[0] == 10:
            return True
        # 172.16.0.0/12
        elif parts[0] == 172 and 16 <= parts[1] <= 31:
            return True
        # 192.168.0.0/16
        elif parts[0] == 192 and parts[1] == 168:
            return True
        # 127.0.0.0/8 (loopback)
        elif parts[0] == 127:
            return True
        
        return False
        
    except (ValueError, IndexError):
        return False