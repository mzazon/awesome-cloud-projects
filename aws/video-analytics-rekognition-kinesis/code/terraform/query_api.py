import json
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime, timedelta
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
PROJECT_NAME = os.environ['PROJECT_NAME']

def lambda_handler(event, context):
    """
    Main Lambda handler for video analytics query API.
    Provides REST endpoints for querying detection data.
    """
    try:
        # Parse request
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        query_params = event.get('queryStringParameters') or {}
        headers = event.get('headers', {})
        
        logger.info(f"API request: {http_method} {path} with params: {query_params}")
        
        # Route requests to appropriate handlers
        if path == '/detections' and http_method == 'GET':
            return get_detections(query_params)
        elif path == '/faces' and http_method == 'GET':
            return get_face_detections(query_params)
        elif path == '/stats' and http_method == 'GET':
            return get_statistics(query_params)
        elif path == '/streams' and http_method == 'GET':
            return get_stream_list(query_params)
        elif path == '/health' and http_method == 'GET':
            return get_health_status()
        else:
            return create_response(404, {'error': 'Endpoint not found'})
            
    except Exception as e:
        logger.error(f"API error: {str(e)}")
        return create_response(500, {'error': 'Internal server error', 'details': str(e)})

def get_detections(params):
    """
    Get detection events with filtering and pagination.
    
    Query parameters:
    - stream: Stream name (required)
    - hours: Hours to look back (default: 24)
    - detection_type: Filter by detection type
    - min_confidence: Minimum confidence threshold
    - limit: Maximum number of results
    """
    try:
        table = dynamodb.Table(DETECTIONS_TABLE)
        
        # Validate required parameters
        stream_name = params.get('stream')
        if not stream_name:
            return create_response(400, {
                'error': 'Missing required parameter: stream',
                'example': '/detections?stream=my-video-stream'
            })
        
        # Parse optional parameters
        hours_back = int(params.get('hours', 24))
        detection_type = params.get('detection_type')
        min_confidence = float(params.get('min_confidence', 0))
        limit = int(params.get('limit', 100))
        
        # Validate parameters
        if hours_back < 1 or hours_back > 168:  # Max 1 week
            return create_response(400, {'error': 'Hours parameter must be between 1 and 168'})
        
        if limit < 1 or limit > 1000:
            return create_response(400, {'error': 'Limit parameter must be between 1 and 1000'})
        
        # Calculate time range
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        # Build query
        key_condition = Key('StreamName').eq(stream_name) & Key('Timestamp').between(start_time, end_time)
        
        # Add filters
        filter_expression = None
        if detection_type:
            filter_expression = Attr('DetectionType').eq(detection_type)
        
        if min_confidence > 0:
            confidence_filter = Attr('Confidence').gte(str(min_confidence))
            if filter_expression:
                filter_expression = filter_expression & confidence_filter
            else:
                filter_expression = confidence_filter
        
        # Execute query
        query_params = {
            'KeyConditionExpression': key_condition,
            'ScanIndexForward': False,  # Most recent first
            'Limit': limit
        }
        
        if filter_expression:
            query_params['FilterExpression'] = filter_expression
        
        response = table.query(**query_params)
        
        # Process results
        detections = []
        for item in response['Items']:
            detection = {
                'stream_name': item['StreamName'],
                'timestamp': int(item['Timestamp']),
                'detection_type': item.get('DetectionType'),
                'label': item.get('Label'),
                'confidence': float(item.get('Confidence', 0)),
                'processed_at': item.get('ProcessedAt'),
                'bounding_box': json.loads(item.get('BoundingBox', '{}'))
            }
            
            # Add type-specific fields
            if item.get('PersonId'):
                detection['person_id'] = item['PersonId']
            if item.get('Instances'):
                detection['instances'] = json.loads(item['Instances'])
            if item.get('Parents'):
                detection['parents'] = json.loads(item['Parents'])
                
            detections.append(detection)
        
        return create_response(200, {
            'detections': detections,
            'count': len(detections),
            'has_more': 'LastEvaluatedKey' in response,
            'query_params': {
                'stream': stream_name,
                'hours_back': hours_back,
                'detection_type': detection_type,
                'min_confidence': min_confidence,
                'limit': limit
            }
        })
        
    except ValueError as e:
        return create_response(400, {'error': f'Invalid parameter value: {str(e)}'})
    except Exception as e:
        logger.error(f"Error in get_detections: {str(e)}")
        return create_response(500, {'error': 'Failed to retrieve detections'})

def get_face_detections(params):
    """
    Get face detection and recognition events.
    
    Query parameters:
    - stream: Stream name
    - face_id: Specific face ID
    - hours: Hours to look back (default: 24)
    - min_similarity: Minimum similarity threshold
    - limit: Maximum number of results
    """
    try:
        table = dynamodb.Table(FACES_TABLE)
        
        # Parse parameters
        stream_name = params.get('stream')
        face_id = params.get('face_id')
        hours_back = int(params.get('hours', 24))
        min_similarity = float(params.get('min_similarity', 0))
        limit = int(params.get('limit', 100))
        
        # Validate parameters
        if hours_back < 1 or hours_back > 168:
            return create_response(400, {'error': 'Hours parameter must be between 1 and 168'})
        
        if limit < 1 or limit > 1000:
            return create_response(400, {'error': 'Limit parameter must be between 1 and 1000'})
        
        # Calculate time range
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        if face_id:
            # Query by specific face ID
            response = table.query(
                KeyConditionExpression=Key('FaceId').eq(face_id) & Key('Timestamp').between(start_time, end_time),
                ScanIndexForward=False,
                Limit=limit
            )
        elif stream_name:
            # Query by stream name using GSI
            response = table.query(
                IndexName='StreamNameIndex',
                KeyConditionExpression=Key('StreamName').eq(stream_name) & Key('Timestamp').between(start_time, end_time),
                ScanIndexForward=False,
                Limit=limit
            )
        else:
            # Scan recent faces (less efficient, use with caution)
            response = table.scan(
                FilterExpression=Attr('Timestamp').between(start_time, end_time),
                Limit=limit
            )
        
        # Process and filter results
        faces = []
        for item in response['Items']:
            similarity = float(item.get('Similarity', 0))
            
            # Apply similarity filter
            if similarity < min_similarity:
                continue
            
            face = {
                'face_id': item['FaceId'],
                'timestamp': int(item['Timestamp']),
                'stream_name': item['StreamName'],
                'confidence': float(item.get('Confidence', 0)),
                'similarity': similarity,
                'event_type': item.get('EventType', 'FaceMatch'),
                'processed_at': item.get('ProcessedAt'),
                'bounding_box': item.get('BoundingBox', {})
            }
            
            faces.append(face)
        
        return create_response(200, {
            'faces': faces,
            'count': len(faces),
            'has_more': 'LastEvaluatedKey' in response,
            'query_params': {
                'stream': stream_name,
                'face_id': face_id,
                'hours_back': hours_back,
                'min_similarity': min_similarity,
                'limit': limit
            }
        })
        
    except ValueError as e:
        return create_response(400, {'error': f'Invalid parameter value: {str(e)}'})
    except Exception as e:
        logger.error(f"Error in get_face_detections: {str(e)}")
        return create_response(500, {'error': 'Failed to retrieve face detections'})

def get_statistics(params):
    """
    Get aggregated statistics for video analytics.
    
    Query parameters:
    - stream: Stream name
    - hours: Hours to look back (default: 24)
    - groupby: Group statistics by (hour, detection_type, etc.)
    """
    try:
        stream_name = params.get('stream')
        hours_back = int(params.get('hours', 24))
        group_by = params.get('groupby', 'detection_type')
        
        if hours_back < 1 or hours_back > 168:
            return create_response(400, {'error': 'Hours parameter must be between 1 and 168'})
        
        # Get detection statistics
        detection_stats = get_detection_statistics(stream_name, hours_back)
        
        # Get face statistics
        face_stats = get_face_statistics(stream_name, hours_back)
        
        # Calculate time-based statistics
        time_stats = get_time_based_statistics(stream_name, hours_back)
        
        return create_response(200, {
            'statistics': {
                'detections': detection_stats,
                'faces': face_stats,
                'time_analysis': time_stats,
                'query_params': {
                    'stream': stream_name,
                    'hours_back': hours_back,
                    'group_by': group_by
                },
                'generated_at': datetime.now().isoformat()
            }
        })
        
    except ValueError as e:
        return create_response(400, {'error': f'Invalid parameter value: {str(e)}'})
    except Exception as e:
        logger.error(f"Error in get_statistics: {str(e)}")
        return create_response(500, {'error': 'Failed to retrieve statistics'})

def get_stream_list(params):
    """
    Get list of available video streams with recent activity.
    """
    try:
        hours_back = int(params.get('hours', 24))
        
        # Scan both tables to find active streams
        detections_table = dynamodb.Table(DETECTIONS_TABLE)
        faces_table = dynamodb.Table(FACES_TABLE)
        
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        streams = {}
        
        # Get streams from detection events
        detection_response = detections_table.scan(
            FilterExpression=Attr('Timestamp').between(start_time, end_time),
            ProjectionExpression='StreamName, Timestamp'
        )
        
        for item in detection_response['Items']:
            stream = item['StreamName']
            timestamp = item['Timestamp']
            
            if stream not in streams:
                streams[stream] = {
                    'stream_name': stream,
                    'last_detection': timestamp,
                    'detection_count': 0,
                    'face_count': 0
                }
            
            streams[stream]['detection_count'] += 1
            streams[stream]['last_detection'] = max(streams[stream]['last_detection'], timestamp)
        
        # Get streams from face events
        face_response = faces_table.scan(
            FilterExpression=Attr('Timestamp').between(start_time, end_time),
            ProjectionExpression='StreamName, Timestamp'
        )
        
        for item in face_response['Items']:
            stream = item['StreamName']
            timestamp = item['Timestamp']
            
            if stream not in streams:
                streams[stream] = {
                    'stream_name': stream,
                    'last_detection': timestamp,
                    'detection_count': 0,
                    'face_count': 0
                }
            
            streams[stream]['face_count'] += 1
            streams[stream]['last_detection'] = max(streams[stream]['last_detection'], timestamp)
        
        # Convert to list and sort by last activity
        stream_list = list(streams.values())
        stream_list.sort(key=lambda x: x['last_detection'], reverse=True)
        
        return create_response(200, {
            'streams': stream_list,
            'count': len(stream_list),
            'hours_back': hours_back,
            'generated_at': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error in get_stream_list: {str(e)}")
        return create_response(500, {'error': 'Failed to retrieve stream list'})

def get_health_status():
    """
    Get API health status and system information.
    """
    try:
        # Basic health check
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'version': '1.0',
            'project': PROJECT_NAME,
            'tables': {
                'detections': DETECTIONS_TABLE,
                'faces': FACES_TABLE
            }
        }
        
        # Test table connectivity
        try:
            detections_table = dynamodb.Table(DETECTIONS_TABLE)
            detections_table.load()
            health_status['tables']['detections_status'] = 'accessible'
        except Exception as e:
            health_status['tables']['detections_status'] = f'error: {str(e)}'
            health_status['status'] = 'degraded'
        
        try:
            faces_table = dynamodb.Table(FACES_TABLE)
            faces_table.load()
            health_status['tables']['faces_status'] = 'accessible'
        except Exception as e:
            health_status['tables']['faces_status'] = f'error: {str(e)}'
            health_status['status'] = 'degraded'
        
        status_code = 200 if health_status['status'] == 'healthy' else 503
        return create_response(status_code, health_status)
        
    except Exception as e:
        logger.error(f"Error in get_health_status: {str(e)}")
        return create_response(503, {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        })

def get_detection_statistics(stream_name, hours_back):
    """Get aggregated detection statistics."""
    try:
        table = dynamodb.Table(DETECTIONS_TABLE)
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        if stream_name:
            response = table.query(
                KeyConditionExpression=Key('StreamName').eq(stream_name) & Key('Timestamp').between(start_time, end_time)
            )
        else:
            response = table.scan(
                FilterExpression=Attr('Timestamp').between(start_time, end_time)
            )
        
        stats = {
            'total_detections': len(response['Items']),
            'by_type': {},
            'by_confidence': {'high': 0, 'medium': 0, 'low': 0},
            'labels': {}
        }
        
        for item in response['Items']:
            detection_type = item.get('DetectionType', 'Unknown')
            confidence = float(item.get('Confidence', 0))
            label = item.get('Label', 'Unknown')
            
            # Count by detection type
            stats['by_type'][detection_type] = stats['by_type'].get(detection_type, 0) + 1
            
            # Count by confidence level
            if confidence >= 90:
                stats['by_confidence']['high'] += 1
            elif confidence >= 70:
                stats['by_confidence']['medium'] += 1
            else:
                stats['by_confidence']['low'] += 1
            
            # Count by label
            stats['labels'][label] = stats['labels'].get(label, 0) + 1
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting detection statistics: {str(e)}")
        return {}

def get_face_statistics(stream_name, hours_back):
    """Get aggregated face detection statistics."""
    try:
        table = dynamodb.Table(FACES_TABLE)
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        if stream_name:
            response = table.query(
                IndexName='StreamNameIndex',
                KeyConditionExpression=Key('StreamName').eq(stream_name) & Key('Timestamp').between(start_time, end_time)
            )
        else:
            response = table.scan(
                FilterExpression=Attr('Timestamp').between(start_time, end_time)
            )
        
        stats = {
            'total_faces': len(response['Items']),
            'unique_faces': len(set(item['FaceId'] for item in response['Items'])),
            'by_event_type': {},
            'by_similarity': {'high': 0, 'medium': 0, 'low': 0}
        }
        
        for item in response['Items']:
            event_type = item.get('EventType', 'Unknown')
            similarity = float(item.get('Similarity', 0))
            
            # Count by event type
            stats['by_event_type'][event_type] = stats['by_event_type'].get(event_type, 0) + 1
            
            # Count by similarity level
            if similarity >= 90:
                stats['by_similarity']['high'] += 1
            elif similarity >= 70:
                stats['by_similarity']['medium'] += 1
            else:
                stats['by_similarity']['low'] += 1
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting face statistics: {str(e)}")
        return {}

def get_time_based_statistics(stream_name, hours_back):
    """Get time-based analysis of detection patterns."""
    try:
        # This is a simplified version - in production, you might use time-window aggregation
        current_time = datetime.now()
        stats = {
            'analysis_period': f'{hours_back} hours',
            'start_time': (current_time - timedelta(hours=hours_back)).isoformat(),
            'end_time': current_time.isoformat(),
            'note': 'Time-based analytics implementation placeholder'
        }
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting time-based statistics: {str(e)}")
        return {}

def create_response(status_code, body):
    """Create standardized API response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
        },
        'body': json.dumps(body, default=str)
    }