import json
import boto3
import base64
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
rekognition = boto3.client('rekognition')

# Environment variables
DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing video analytics events from Kinesis Data Stream.
    Processes detection results from Amazon Rekognition stream processors.
    """
    logger.info(f"Processing {len(event['Records'])} records from Kinesis stream")
    
    processed_count = 0
    error_count = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            logger.info(f"Processing detection event: {json.dumps(data, default=str)}")
            process_detection_event(data)
            processed_count += 1
            
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            logger.error(f"Record data: {record}")
            error_count += 1
    
    logger.info(f"Processed {processed_count} records successfully, {error_count} errors")
    
    return {
        'statusCode': 200,
        'processedRecords': processed_count,
        'errorRecords': error_count
    }

def process_detection_event(data):
    """
    Process individual detection events and route to appropriate handlers.
    
    Args:
        data: Decoded detection event data from Rekognition stream processor
    """
    timestamp = datetime.now().timestamp()
    stream_name = data.get('StreamName', 'unknown')
    
    # Process different types of detection events
    if 'FaceSearchResponse' in data:
        process_face_detection(data['FaceSearchResponse'], stream_name, timestamp)
    
    if 'LabelDetectionResponse' in data:
        process_label_detection(data['LabelDetectionResponse'], stream_name, timestamp)
    
    if 'PersonTrackingResponse' in data:
        process_person_tracking(data['PersonTrackingResponse'], stream_name, timestamp)
    
    # Handle custom detection types
    if 'CustomLabelsResponse' in data:
        process_custom_labels(data['CustomLabelsResponse'], stream_name, timestamp)

def process_face_detection(face_data, stream_name, timestamp):
    """
    Process face detection and recognition results.
    
    Args:
        face_data: Face detection response from Rekognition
        stream_name: Name of the video stream
        timestamp: Event timestamp
    """
    table = dynamodb.Table(FACES_TABLE)
    
    try:
        # Process face matches from collection
        for face_match in face_data.get('FaceMatches', []):
            face_id = face_match['Face']['FaceId']
            confidence = face_match['Face']['Confidence']
            similarity = face_match['Similarity']
            
            logger.info(f"Face match detected: {face_id}, similarity: {similarity}%")
            
            # Store face detection event
            table.put_item(
                Item={
                    'FaceId': face_id,
                    'Timestamp': int(timestamp * 1000),
                    'StreamName': stream_name,
                    'Confidence': str(confidence),
                    'Similarity': str(similarity),
                    'BoundingBox': face_match['Face']['BoundingBox'],
                    'EventType': 'FaceMatch',
                    'ProcessedAt': datetime.now().isoformat()
                }
            )
            
            # Send alert for high-confidence matches
            if similarity > 90:
                send_alert(
                    f"High confidence face match detected: {face_id}",
                    f"Similarity: {similarity}%, Stream: {stream_name}, Confidence: {confidence}%"
                )
        
        # Process unmatched faces (faces detected but not in collection)
        for unmatched_face in face_data.get('UnmatchedFaces', []):
            face_id = f"unmatched_{int(timestamp * 1000)}"
            confidence = unmatched_face.get('Confidence', 0)
            
            table.put_item(
                Item={
                    'FaceId': face_id,
                    'Timestamp': int(timestamp * 1000),
                    'StreamName': stream_name,
                    'Confidence': str(confidence),
                    'Similarity': '0',
                    'BoundingBox': unmatched_face.get('BoundingBox', {}),
                    'EventType': 'UnmatchedFace',
                    'ProcessedAt': datetime.now().isoformat()
                }
            )
            
    except Exception as e:
        logger.error(f"Error processing face detection: {str(e)}")
        raise

def process_label_detection(label_data, stream_name, timestamp):
    """
    Process object and scene label detection results.
    
    Args:
        label_data: Label detection response from Rekognition
        stream_name: Name of the video stream
        timestamp: Event timestamp
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    try:
        for label in label_data.get('Labels', []):
            label_name = label['Label']['Name']
            confidence = label['Label']['Confidence']
            
            logger.info(f"Label detected: {label_name}, confidence: {confidence}%")
            
            # Store detection event
            table.put_item(
                Item={
                    'StreamName': stream_name,
                    'Timestamp': int(timestamp * 1000),
                    'DetectionType': 'Label',
                    'Label': label_name,
                    'Confidence': str(confidence),
                    'BoundingBox': json.dumps(label['Label'].get('BoundingBox', {})),
                    'Instances': json.dumps(label['Label'].get('Instances', [])),
                    'Parents': json.dumps(label['Label'].get('Parents', [])),
                    'ProcessedAt': datetime.now().isoformat()
                }
            )
            
            # Check for security-relevant objects and send alerts
            security_objects = [
                'Weapon', 'Gun', 'Knife', 'Handgun', 'Rifle',
                'Person', 'Car', 'Motorcycle', 'Truck', 'Vehicle',
                'Fire', 'Smoke', 'Crowd', 'Fighting'
            ]
            
            if label_name in security_objects and confidence > 80:
                send_alert(
                    f"Security object detected: {label_name}",
                    f"Object: {label_name}, Confidence: {confidence}%, Stream: {stream_name}, Time: {datetime.fromtimestamp(timestamp).isoformat()}"
                )
                
    except Exception as e:
        logger.error(f"Error processing label detection: {str(e)}")
        raise

def process_person_tracking(person_data, stream_name, timestamp):
    """
    Process person tracking results for movement analysis.
    
    Args:
        person_data: Person tracking response from Rekognition
        stream_name: Name of the video stream
        timestamp: Event timestamp
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    try:
        for person in person_data.get('Persons', []):
            person_id = person.get('Index', 'unknown')
            
            logger.info(f"Person tracked: {person_id}")
            
            # Store person tracking event
            table.put_item(
                Item={
                    'StreamName': stream_name,
                    'Timestamp': int(timestamp * 1000),
                    'DetectionType': 'Person',
                    'PersonId': str(person_id),
                    'BoundingBox': json.dumps(person.get('BoundingBox', {})),
                    'Face': json.dumps(person.get('Face', {})),
                    'ProcessedAt': datetime.now().isoformat()
                }
            )
            
    except Exception as e:
        logger.error(f"Error processing person tracking: {str(e)}")
        raise

def process_custom_labels(custom_data, stream_name, timestamp):
    """
    Process custom label detection results from trained models.
    
    Args:
        custom_data: Custom labels response from Rekognition
        stream_name: Name of the video stream
        timestamp: Event timestamp
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    try:
        for custom_label in custom_data.get('CustomLabels', []):
            label_name = custom_label.get('Name', 'unknown')
            confidence = custom_label.get('Confidence', 0)
            
            logger.info(f"Custom label detected: {label_name}, confidence: {confidence}%")
            
            # Store custom detection event
            table.put_item(
                Item={
                    'StreamName': stream_name,
                    'Timestamp': int(timestamp * 1000),
                    'DetectionType': 'CustomLabel',
                    'Label': label_name,
                    'Confidence': str(confidence),
                    'BoundingBox': json.dumps(custom_label.get('Geometry', {}).get('BoundingBox', {})),
                    'ProcessedAt': datetime.now().isoformat()
                }
            )
            
            # Send alerts for high-confidence custom detections
            if confidence > 85:
                send_alert(
                    f"Custom detection alert: {label_name}",
                    f"Custom Label: {label_name}, Confidence: {confidence}%, Stream: {stream_name}"
                )
                
    except Exception as e:
        logger.error(f"Error processing custom labels: {str(e)}")
        raise

def send_alert(subject, message):
    """
    Send security alert via SNS topic.
    
    Args:
        subject: Alert subject line
        message: Alert message body
    """
    if not SNS_TOPIC_ARN:
        logger.warning("SNS topic ARN not configured, skipping alert")
        return
    
    try:
        logger.info(f"Sending alert: {subject}")
        
        # Enhanced message with metadata
        enhanced_message = f"""
{message}

Alert Details:
- Timestamp: {datetime.now().isoformat()}
- System: Video Analytics Platform
- Alert Type: Security Detection

This is an automated alert from the video analytics system.
"""
        
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=enhanced_message
        )
        
        logger.info(f"Alert sent successfully, MessageId: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Failed to send alert: {str(e)}")
        # Don't raise exception as alert failure shouldn't stop processing

def get_detection_statistics(stream_name, hours_back=1):
    """
    Get detection statistics for monitoring and dashboards.
    
    Args:
        stream_name: Video stream name
        hours_back: Number of hours to look back
        
    Returns:
        Dictionary with detection statistics
    """
    try:
        table = dynamodb.Table(DETECTIONS_TABLE)
        
        # Calculate time range
        end_time = datetime.now().timestamp() * 1000
        start_time = end_time - (hours_back * 3600 * 1000)
        
        # Query recent detections
        response = table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('StreamName').eq(stream_name) &
                                  boto3.dynamodb.conditions.Key('Timestamp').between(start_time, end_time)
        )
        
        # Aggregate statistics
        stats = {
            'total_detections': len(response['Items']),
            'detection_types': {},
            'confidence_distribution': {'high': 0, 'medium': 0, 'low': 0}
        }
        
        for item in response['Items']:
            detection_type = item.get('DetectionType', 'Unknown')
            confidence = float(item.get('Confidence', 0))
            
            # Count by type
            stats['detection_types'][detection_type] = stats['detection_types'].get(detection_type, 0) + 1
            
            # Count by confidence level
            if confidence >= 90:
                stats['confidence_distribution']['high'] += 1
            elif confidence >= 70:
                stats['confidence_distribution']['medium'] += 1
            else:
                stats['confidence_distribution']['low'] += 1
        
        return stats
        
    except Exception as e:
        logger.error(f"Error getting detection statistics: {str(e)}")
        return {}