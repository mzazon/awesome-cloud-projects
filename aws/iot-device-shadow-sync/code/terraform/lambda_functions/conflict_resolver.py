import json
import boto3
import logging
import time
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
import hashlib
import copy

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
iot_data = boto3.client('iot-data')
events = boto3.client('events')
cloudwatch = boto3.client('cloudwatch')

# Configuration from environment variables
SHADOW_HISTORY_TABLE = '${shadow_history_table}'
DEVICE_CONFIG_TABLE = '${device_config_table}'
SYNC_METRICS_TABLE = '${sync_metrics_table}'
EVENT_BUS_NAME = '${event_bus_name}'

def lambda_handler(event, context):
    """
    Handle shadow synchronization conflicts and state management
    """
    try:
        logger.info(f"Shadow conflict resolution event: {json.dumps(event, default=str)}")
        
        # Parse shadow event
        if 'Records' in event:
            # DynamoDB stream event
            return handle_dynamodb_stream_event(event)
        elif 'operation' in event:
            # Direct operation invocation
            return handle_direct_operation(event)
        else:
            # IoT shadow delta event
            return handle_shadow_delta_event(event)
            
    except Exception as e:
        logger.error(f"Error in shadow conflict resolution: {str(e)}")
        return create_error_response(str(e))

def handle_shadow_delta_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle IoT shadow delta events for conflict resolution"""
    try:
        thing_name = event.get('thingName', '')
        shadow_name = event.get('shadowName', '$default')
        delta = event.get('state', {})
        version = event.get('version', 0)
        timestamp = event.get('timestamp', int(time.time()))
        
        logger.info(f"Processing delta for {thing_name}, shadow: {shadow_name}")
        
        # Get current shadow state
        current_shadow = get_current_shadow(thing_name, shadow_name)
        
        # Check for conflicts
        conflict_result = detect_conflicts(
            thing_name, shadow_name, delta, current_shadow, version
        )
        
        if conflict_result['has_conflict']:
            # Resolve conflicts using configured strategy
            resolution = resolve_shadow_conflict(
                thing_name, shadow_name, conflict_result, current_shadow
            )
            
            # Apply resolution
            apply_conflict_resolution(thing_name, shadow_name, resolution)
            
            # Log conflict resolution
            log_conflict_resolution(thing_name, shadow_name, conflict_result, resolution)
            
        else:
            # No conflict, proceed with normal update
            logger.info(f"No conflicts detected for {thing_name}")
        
        # Update shadow history
        record_shadow_history(thing_name, shadow_name, delta, version, timestamp)
        
        # Update sync metrics
        update_sync_metrics(thing_name, shadow_name, conflict_result['has_conflict'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'shadowName': shadow_name,
                'hasConflict': conflict_result['has_conflict'],
                'resolution': conflict_result.get('resolution', 'none')
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling shadow delta: {str(e)}")
        return create_error_response(str(e))

def detect_conflicts(thing_name: str, shadow_name: str, delta: Dict[str, Any], 
                    current_shadow: Dict[str, Any], version: int) -> Dict[str, Any]:
    """Detect conflicts in shadow updates"""
    try:
        conflicts = []
        
        # Check version conflicts
        current_version = current_shadow.get('version', 0)
        if version <= current_version:
            conflicts.append({
                'type': 'version_conflict',
                'current_version': current_version,
                'delta_version': version,
                'severity': 'high'
            })
        
        # Check for concurrent modifications
        recent_history = get_recent_shadow_history(thing_name, shadow_name, minutes=5)
        if len(recent_history) > 1:
            conflicts.append({
                'type': 'concurrent_modification',
                'recent_changes': len(recent_history),
                'severity': 'medium'
            })
        
        # Check for data type conflicts
        current_reported = current_shadow.get('state', {}).get('reported', {})
        for key, value in delta.items():
            if key in current_reported:
                current_type = type(current_reported[key]).__name__
                delta_type = type(value).__name__
                if current_type != delta_type:
                    conflicts.append({
                        'type': 'data_type_conflict',
                        'field': key,
                        'current_type': current_type,
                        'delta_type': delta_type,
                        'severity': 'low'
                    })
        
        # Check for business rule violations
        business_conflicts = check_business_rules(thing_name, delta, current_shadow)
        conflicts.extend(business_conflicts)
        
        return {
            'has_conflict': len(conflicts) > 0,
            'conflicts': conflicts,
            'severity': max([c.get('severity', 'low') for c in conflicts] + ['none'])
        }
        
    except Exception as e:
        logger.error(f"Error detecting conflicts: {str(e)}")
        return {'has_conflict': False, 'conflicts': [], 'error': str(e)}

def resolve_shadow_conflict(thing_name: str, shadow_name: str, 
                          conflict_result: Dict[str, Any], 
                          current_shadow: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve shadow conflicts using configurable strategies"""
    try:
        conflicts = conflict_result['conflicts']
        severity = conflict_result['severity']
        
        # Get device-specific conflict resolution strategy
        config = get_device_config(thing_name, 'conflict_resolution')
        strategy = config.get('strategy', 'last_writer_wins')
        
        logger.info(f"Resolving conflicts using strategy: {strategy}")
        
        if strategy == 'last_writer_wins':
            return resolve_last_writer_wins(conflicts, current_shadow)
        elif strategy == 'field_level_merge':
            return resolve_field_level_merge(conflicts, current_shadow)
        elif strategy == 'priority_based':
            return resolve_priority_based(conflicts, current_shadow, config)
        elif strategy == 'manual_review':
            return schedule_manual_review(thing_name, shadow_name, conflicts)
        else:
            # Default to last writer wins
            return resolve_last_writer_wins(conflicts, current_shadow)
            
    except Exception as e:
        logger.error(f"Error resolving conflicts: {str(e)}")
        return {'strategy': 'error', 'resolution': {}, 'error': str(e)}

def resolve_last_writer_wins(conflicts: List[Dict], current_shadow: Dict) -> Dict[str, Any]:
    """Resolve conflicts using last writer wins strategy"""
    return {
        'strategy': 'last_writer_wins',
        'resolution': 'accept_delta',
        'action': 'overwrite_current'
    }

def resolve_field_level_merge(conflicts: List[Dict], current_shadow: Dict) -> Dict[str, Any]:
    """Resolve conflicts by merging at field level"""
    merged_state = copy.deepcopy(current_shadow.get('state', {}).get('reported', {}))
    
    # Merge strategy: newer timestamps win for each field
    resolution_details = []
    
    for conflict in conflicts:
        if conflict['type'] == 'data_type_conflict':
            field = conflict['field']
            # Keep current value for type conflicts
            resolution_details.append({
                'field': field,
                'action': 'keep_current',
                'reason': 'type_conflict'
            })
    
    return {
        'strategy': 'field_level_merge',
        'resolution': merged_state,
        'details': resolution_details,
        'action': 'partial_merge'
    }

def resolve_priority_based(conflicts: List[Dict], current_shadow: Dict, config: Dict) -> Dict[str, Any]:
    """Resolve conflicts based on configured priorities"""
    priorities = config.get('field_priorities', {})
    
    resolution = {}
    for conflict in conflicts:
        if conflict['type'] == 'data_type_conflict':
            field = conflict['field']
            priority = priorities.get(field, 'low')
            
            if priority == 'high':
                # High priority fields always accept delta
                resolution[field] = 'accept_delta'
            else:
                # Low priority fields keep current
                resolution[field] = 'keep_current'
    
    return {
        'strategy': 'priority_based',
        'resolution': resolution,
        'action': 'selective_merge'
    }

def schedule_manual_review(thing_name: str, shadow_name: str, conflicts: List[Dict]) -> Dict[str, Any]:
    """Schedule manual review for complex conflicts"""
    review_id = f"review-{thing_name}-{int(time.time())}"
    
    # Send event for manual review
    events.put_events(
        Entries=[
            {
                'Source': 'iot.shadow.sync',
                'DetailType': 'Manual Review Required',
                'Detail': json.dumps({
                    'reviewId': review_id,
                    'thingName': thing_name,
                    'shadowName': shadow_name,
                    'conflicts': conflicts,
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }),
                'EventBusName': EVENT_BUS_NAME
            }
        ]
    )
    
    return {
        'strategy': 'manual_review',
        'reviewId': review_id,
        'action': 'defer_to_manual',
        'status': 'pending_review'
    }

def apply_conflict_resolution(thing_name: str, shadow_name: str, resolution: Dict[str, Any]):
    """Apply the conflict resolution to the device shadow"""
    try:
        action = resolution.get('action', 'none')
        
        if action == 'overwrite_current':
            # Full shadow update will be handled by IoT Core
            logger.info(f"Full shadow overwrite for {thing_name}")
            
        elif action == 'partial_merge':
            # Apply partial updates
            merged_state = resolution.get('resolution', {})
            update_payload = {
                'state': {
                    'reported': merged_state
                }
            }
            
            iot_data.update_thing_shadow(
                thingName=thing_name,
                shadowName=shadow_name,
                payload=json.dumps(update_payload)
            )
            
        elif action == 'selective_merge':
            # Apply selective field updates
            field_resolutions = resolution.get('resolution', {})
            # Implementation would depend on specific field handling
            logger.info(f"Selective merge for {thing_name}: {field_resolutions}")
            
        elif action == 'defer_to_manual':
            # No automatic action, waiting for manual intervention
            logger.info(f"Deferring to manual review for {thing_name}")
            
    except Exception as e:
        logger.error(f"Error applying conflict resolution: {str(e)}")

def check_business_rules(thing_name: str, delta: Dict[str, Any], 
                        current_shadow: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Check business rules for shadow updates"""
    violations = []
    
    # Example business rules
    if 'temperature' in delta:
        temp = delta['temperature']
        if isinstance(temp, (int, float)) and (temp < -50 or temp > 100):
            violations.append({
                'type': 'business_rule_violation',
                'rule': 'temperature_range',
                'value': temp,
                'severity': 'high'
            })
    
    if 'firmware_version' in delta:
        current_version = current_shadow.get('state', {}).get('reported', {}).get('firmware_version', '')
        new_version = delta['firmware_version']
        
        # Check for firmware downgrade
        if version_compare(new_version, current_version) < 0:
            violations.append({
                'type': 'business_rule_violation',
                'rule': 'no_firmware_downgrade',
                'current': current_version,
                'proposed': new_version,
                'severity': 'medium'
            })
    
    return violations

def get_current_shadow(thing_name: str, shadow_name: str) -> Dict[str, Any]:
    """Retrieve current shadow state"""
    try:
        response = iot_data.get_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name
        )
        return json.loads(response['payload'].read())
    except Exception as e:
        logger.warning(f"Could not get shadow for {thing_name}: {str(e)}")
        return {}

def get_recent_shadow_history(thing_name: str, shadow_name: str, minutes: int = 5) -> List[Dict]:
    """Get recent shadow history for conflict detection"""
    try:
        table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        cutoff_time = int((datetime.now(timezone.utc).timestamp() - (minutes * 60)) * 1000)
        
        response = table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('thingName').eq(thing_name) & 
                                 boto3.dynamodb.conditions.Key('timestamp').gte(cutoff_time),
            FilterExpression=boto3.dynamodb.conditions.Attr('shadowName').eq(shadow_name),
            ScanIndexForward=False,
            Limit=10
        )
        
        return response.get('Items', [])
    except Exception as e:
        logger.error(f"Error getting shadow history: {str(e)}")
        return []

def get_device_config(thing_name: str, config_type: str) -> Dict[str, Any]:
    """Get device-specific configuration"""
    try:
        table = dynamodb.Table(DEVICE_CONFIG_TABLE)
        response = table.get_item(
            Key={
                'thingName': thing_name,
                'configType': config_type
            }
        )
        return response.get('Item', {}).get('config', {})
    except Exception as e:
        logger.error(f"Error getting device config: {str(e)}")
        return {}

def record_shadow_history(thing_name: str, shadow_name: str, delta: Dict[str, Any], 
                         version: int, timestamp: int):
    """Record shadow change in history table"""
    try:
        table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        table.put_item(
            Item={
                'thingName': thing_name,
                'timestamp': int(timestamp * 1000),  # Convert to milliseconds
                'shadowName': shadow_name,
                'delta': delta,
                'version': version,
                'changeType': 'delta_update',
                'checksum': hashlib.md5(json.dumps(delta, sort_keys=True).encode()).hexdigest()
            }
        )
    except Exception as e:
        logger.error(f"Error recording shadow history: {str(e)}")

def update_sync_metrics(thing_name: str, shadow_name: str, had_conflict: bool):
    """Update synchronization metrics"""
    try:
        table = dynamodb.Table(SYNC_METRICS_TABLE)
        timestamp = int(time.time() * 1000)
        
        table.put_item(
            Item={
                'thingName': thing_name,
                'metricTimestamp': timestamp,
                'shadowName': shadow_name,
                'hadConflict': had_conflict,
                'syncType': 'delta_update',
                'ttl': int(time.time()) + (30 * 24 * 60 * 60)  # 30 days TTL
            }
        )
        
        # Send CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='IoT/ShadowSync',
            MetricData=[
                {
                    'MetricName': 'ConflictDetected',
                    'Value': 1 if had_conflict else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ThingName', 'Value': thing_name},
                        {'Name': 'ShadowName', 'Value': shadow_name}
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Error updating sync metrics: {str(e)}")

def log_conflict_resolution(thing_name: str, shadow_name: str, 
                          conflict_result: Dict[str, Any], resolution: Dict[str, Any]):
    """Log conflict resolution details"""
    try:
        # Send detailed event to EventBridge
        events.put_events(
            Entries=[
                {
                    'Source': 'iot.shadow.sync',
                    'DetailType': 'Conflict Resolved',
                    'Detail': json.dumps({
                        'thingName': thing_name,
                        'shadowName': shadow_name,
                        'conflicts': conflict_result['conflicts'],
                        'resolution': resolution,
                        'timestamp': datetime.now(timezone.utc).isoformat()
                    }),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error logging conflict resolution: {str(e)}")

def version_compare(version1: str, version2: str) -> int:
    """Compare semantic versions"""
    try:
        v1_parts = [int(x) for x in str(version1).lstrip('v').split('.')]
        v2_parts = [int(x) for x in str(version2).lstrip('v').split('.')]
        
        for i in range(max(len(v1_parts), len(v2_parts))):
            v1_part = v1_parts[i] if i < len(v1_parts) else 0
            v2_part = v2_parts[i] if i < len(v2_parts) else 0
            
            if v1_part > v2_part:
                return 1
            elif v1_part < v2_part:
                return -1
        
        return 0
    except Exception:
        return 0

def handle_dynamodb_stream_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle DynamoDB stream events for shadow history"""
    # Implementation for processing shadow history changes
    return {'statusCode': 200, 'body': 'Stream event processed'}

def handle_direct_operation(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle direct operation invocations"""
    operation = event.get('operation', '')
    
    if operation == 'sync_device_shadows':
        return sync_device_shadows(event)
    elif operation == 'resolve_pending_conflicts':
        return resolve_pending_conflicts(event)
    else:
        return create_error_response(f'Unknown operation: {operation}')

def sync_device_shadows(event: Dict[str, Any]) -> Dict[str, Any]:
    """Synchronize device shadows for offline scenarios"""
    # Implementation for manual shadow synchronization
    return {'statusCode': 200, 'body': 'Shadow sync initiated'}

def resolve_pending_conflicts(event: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve pending conflicts from manual review"""
    # Implementation for resolving manually reviewed conflicts
    return {'statusCode': 200, 'body': 'Pending conflicts resolved'}

def create_error_response(error_message: str) -> Dict[str, Any]:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    }