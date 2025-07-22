import json
import boto3
import logging
from datetime import datetime, timezone
import time
from typing import Dict, Any, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_data = boto3.client('iot-data')
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Configuration from environment variables
SHADOW_HISTORY_TABLE = '${shadow_history_table}'
DEVICE_CONFIG_TABLE = '${device_config_table}'
SYNC_METRICS_TABLE = '${sync_metrics_table}'

def lambda_handler(event, context):
    """
    Manage shadow synchronization operations for offline devices
    """
    try:
        operation = event.get('operation', 'sync_check')
        thing_name = event.get('thingName', '')
        
        logger.info(f"Shadow sync operation: {operation} for {thing_name}")
        
        if operation == 'sync_check':
            return perform_sync_check(event)
        elif operation == 'offline_sync':
            return handle_offline_sync(event)
        elif operation == 'conflict_summary':
            return generate_conflict_summary(event)
        elif operation == 'health_report':
            return generate_health_report(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps(f'Unknown operation: {operation}')
            }
            
    except Exception as e:
        logger.error(f"Error in shadow sync manager: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Sync manager error: {str(e)}')
        }

def perform_sync_check(event: Dict[str, Any]) -> Dict[str, Any]:
    """Perform comprehensive shadow synchronization check"""
    try:
        thing_name = event.get('thingName', '')
        shadow_names = event.get('shadowNames', ['$default'])
        
        sync_results = []
        
        for shadow_name in shadow_names:
            # Get current shadow
            shadow = get_shadow_safely(thing_name, shadow_name)
            
            # Check sync status
            sync_status = check_shadow_sync_status(thing_name, shadow_name, shadow)
            
            sync_results.append({
                'shadowName': shadow_name,
                'syncStatus': sync_status,
                'lastSync': get_last_sync_time(thing_name, shadow_name),
                'hasConflicts': sync_status.get('hasConflicts', False)
            })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'syncResults': sync_results,
                'overallHealth': calculate_overall_health(sync_results)
            })
        }
        
    except Exception as e:
        logger.error(f"Error performing sync check: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_offline_sync(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle synchronization for devices coming back online"""
    try:
        thing_name = event.get('thingName', '')
        offline_duration = event.get('offlineDurationSeconds', 0)
        cached_changes = event.get('cachedChanges', [])
        
        logger.info(f"Handling offline sync for {thing_name}, offline for {offline_duration}s")
        
        # Process cached changes
        processed_changes = []
        conflicts_detected = []
        
        for change in cached_changes:
            shadow_name = change.get('shadowName', '$default')
            cached_state = change.get('state', {})
            timestamp = change.get('timestamp', int(time.time()))
            
            # Get current shadow state
            current_shadow = get_shadow_safely(thing_name, shadow_name)
            
            # Detect conflicts
            conflict_check = detect_offline_conflicts(
                thing_name, shadow_name, cached_state, current_shadow, timestamp
            )
            
            if conflict_check['hasConflicts']:
                conflicts_detected.append(conflict_check)
                # Queue for manual resolution if needed
                if conflict_check['severity'] == 'high':
                    queue_for_manual_resolution(thing_name, shadow_name, conflict_check)
            else:
                # Apply cached changes
                apply_cached_changes(thing_name, shadow_name, cached_state)
                processed_changes.append({
                    'shadowName': shadow_name,
                    'status': 'applied',
                    'timestamp': timestamp
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'processedChanges': len(processed_changes),
                'conflictsDetected': len(conflicts_detected),
                'conflicts': conflicts_detected[:5],  # Return first 5 conflicts
                'syncCompleted': datetime.now(timezone.utc).isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling offline sync: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_conflict_summary(event: Dict[str, Any]) -> Dict[str, Any]:
    """Generate summary of shadow conflicts"""
    try:
        time_range_hours = event.get('timeRangeHours', 24)
        cutoff_time = int((datetime.now(timezone.utc).timestamp() - (time_range_hours * 3600)) * 1000)
        
        # Query conflict history
        metrics_table = dynamodb.Table(SYNC_METRICS_TABLE)
        
        response = metrics_table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('metricTimestamp').gte(cutoff_time) &
                           boto3.dynamodb.conditions.Attr('hadConflict').eq(True)
        )
        
        conflicts = response.get('Items', [])
        
        # Analyze conflicts
        summary = {
            'totalConflicts': len(conflicts),
            'conflictsByType': {},
            'conflictsByThing': {},
            'timeRange': f'{time_range_hours} hours'
        }
        
        for conflict in conflicts:
            thing_name = conflict.get('thingName', 'unknown')
            shadow_name = conflict.get('shadowName', '$default')
            
            summary['conflictsByThing'][thing_name] = summary['conflictsByThing'].get(thing_name, 0) + 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(summary)
        }
        
    except Exception as e:
        logger.error(f"Error generating conflict summary: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_health_report(event: Dict[str, Any]) -> Dict[str, Any]:
    """Generate comprehensive shadow health report"""
    try:
        thing_names = event.get('thingNames', [])
        
        health_report = {
            'reportTimestamp': datetime.now(timezone.utc).isoformat(),
            'deviceHealth': [],
            'overallMetrics': {
                'totalDevices': len(thing_names),
                'healthyDevices': 0,
                'devicesWithConflicts': 0,
                'offlineDevices': 0
            }
        }
        
        for thing_name in thing_names:
            device_health = assess_device_health(thing_name)
            health_report['deviceHealth'].append(device_health)
            
            if device_health['status'] == 'healthy':
                health_report['overallMetrics']['healthyDevices'] += 1
            elif device_health['status'] == 'conflict':
                health_report['overallMetrics']['devicesWithConflicts'] += 1
            elif device_health['status'] == 'offline':
                health_report['overallMetrics']['offlineDevices'] += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report)
        }
        
    except Exception as e:
        logger.error(f"Error generating health report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_shadow_safely(thing_name: str, shadow_name: str) -> Dict[str, Any]:
    """Safely retrieve shadow, returning empty dict if not found"""
    try:
        response = iot_data.get_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name
        )
        return json.loads(response['payload'].read())
    except Exception as e:
        logger.warning(f"Could not get shadow {shadow_name} for {thing_name}: {str(e)}")
        return {}

def check_shadow_sync_status(thing_name: str, shadow_name: str, shadow: Dict[str, Any]) -> Dict[str, Any]:
    """Check the synchronization status of a shadow"""
    status = {
        'inSync': True,
        'hasConflicts': False,
        'lastUpdate': shadow.get('metadata', {}).get('reported', {}).get('timestamp'),
        'version': shadow.get('version', 0)
    }
    
    # Check for delta (indicates desired != reported)
    if 'delta' in shadow.get('state', {}):
        status['inSync'] = False
        status['pendingChanges'] = list(shadow['state']['delta'].keys())
    
    # Check recent conflict history
    recent_conflicts = get_recent_conflicts(thing_name, shadow_name)
    if recent_conflicts:
        status['hasConflicts'] = True
        status['recentConflicts'] = len(recent_conflicts)
    
    return status

def detect_offline_conflicts(thing_name: str, shadow_name: str, cached_state: Dict[str, Any],
                           current_shadow: Dict[str, Any], cached_timestamp: int) -> Dict[str, Any]:
    """Detect conflicts between cached offline changes and current shadow"""
    conflicts = []
    
    current_reported = current_shadow.get('state', {}).get('reported', {})
    current_timestamp = current_shadow.get('metadata', {}).get('reported', {}).get('timestamp', 0)
    
    # Check if current shadow was updated while device was offline
    if current_timestamp > cached_timestamp:
        for key, cached_value in cached_state.items():
            if key in current_reported and current_reported[key] != cached_value:
                conflicts.append({
                    'field': key,
                    'cachedValue': cached_value,
                    'currentValue': current_reported[key],
                    'type': 'concurrent_modification'
                })
    
    # Determine severity
    severity = 'low'
    if len(conflicts) > 3:
        severity = 'high'
    elif len(conflicts) > 1:
        severity = 'medium'
    
    return {
        'hasConflicts': len(conflicts) > 0,
        'conflicts': conflicts,
        'severity': severity,
        'conflictCount': len(conflicts)
    }

def apply_cached_changes(thing_name: str, shadow_name: str, cached_state: Dict[str, Any]):
    """Apply cached changes to shadow"""
    try:
        update_payload = {
            'state': {
                'reported': cached_state
            }
        }
        
        iot_data.update_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name,
            payload=json.dumps(update_payload)
        )
        
        logger.info(f"Applied cached changes to {thing_name}/{shadow_name}")
        
    except Exception as e:
        logger.error(f"Error applying cached changes: {str(e)}")

def get_recent_conflicts(thing_name: str, shadow_name: str, hours: int = 1) -> List[Dict]:
    """Get recent conflicts for a shadow"""
    try:
        metrics_table = dynamodb.Table(SYNC_METRICS_TABLE)
        cutoff_time = int((datetime.now(timezone.utc).timestamp() - (hours * 3600)) * 1000)
        
        response = metrics_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('thingName').eq(thing_name) &
                                 boto3.dynamodb.conditions.Key('metricTimestamp').gte(cutoff_time),
            FilterExpression=boto3.dynamodb.conditions.Attr('shadowName').eq(shadow_name) &
                           boto3.dynamodb.conditions.Attr('hadConflict').eq(True)
        )
        
        return response.get('Items', [])
    except Exception as e:
        logger.error(f"Error getting recent conflicts: {str(e)}")
        return []

def get_last_sync_time(thing_name: str, shadow_name: str) -> Optional[str]:
    """Get the last synchronization time for a shadow"""
    try:
        history_table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        
        response = history_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('thingName').eq(thing_name),
            FilterExpression=boto3.dynamodb.conditions.Attr('shadowName').eq(shadow_name),
            ScanIndexForward=False,
            Limit=1
        )
        
        items = response.get('Items', [])
        if items:
            return datetime.fromtimestamp(items[0]['timestamp'] / 1000, timezone.utc).isoformat()
        
        return None
    except Exception as e:
        logger.error(f"Error getting last sync time: {str(e)}")
        return None

def calculate_overall_health(sync_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate overall health metrics from sync results"""
    total_shadows = len(sync_results)
    healthy_shadows = sum(1 for r in sync_results if r['syncStatus']['inSync'])
    conflicted_shadows = sum(1 for r in sync_results if r['syncStatus']['hasConflicts'])
    
    health_percentage = (healthy_shadows / max(total_shadows, 1)) * 100
    
    return {
        'healthPercentage': health_percentage,
        'totalShadows': total_shadows,
        'healthyShadows': healthy_shadows,
        'conflictedShadows': conflicted_shadows,
        'status': 'healthy' if health_percentage > 80 else 'degraded' if health_percentage > 60 else 'critical'
    }

def assess_device_health(thing_name: str) -> Dict[str, Any]:
    """Assess the overall health of a device's shadows"""
    try:
        # This would typically check multiple named shadows
        shadow_names = ['$default', 'configuration', 'telemetry', 'maintenance']
        
        health_status = {
            'thingName': thing_name,
            'status': 'healthy',
            'shadowCount': len(shadow_names),
            'issues': []
        }
        
        for shadow_name in shadow_names:
            shadow = get_shadow_safely(thing_name, shadow_name)
            if not shadow:
                health_status['issues'].append(f'Shadow {shadow_name} not found')
                health_status['status'] = 'offline'
                continue
            
            # Check for deltas
            if 'delta' in shadow.get('state', {}):
                health_status['issues'].append(f'Pending changes in {shadow_name}')
                if health_status['status'] == 'healthy':
                    health_status['status'] = 'warning'
            
            # Check for recent conflicts
            recent_conflicts = get_recent_conflicts(thing_name, shadow_name)
            if recent_conflicts:
                health_status['issues'].append(f'Recent conflicts in {shadow_name}')
                health_status['status'] = 'conflict'
        
        return health_status
        
    except Exception as e:
        logger.error(f"Error assessing device health: {str(e)}")
        return {
            'thingName': thing_name,
            'status': 'error',
            'error': str(e)
        }

def queue_for_manual_resolution(thing_name: str, shadow_name: str, conflict_check: Dict[str, Any]):
    """Queue conflicts for manual resolution"""
    try:
        # This would typically send to a queue or notification system
        logger.warning(f"High-severity conflict queued for manual resolution: {thing_name}/{shadow_name}")
        
        # Could implement SQS queue, SNS notification, or EventBridge event
        # For now, just log the conflict
        
    except Exception as e:
        logger.error(f"Error queuing for manual resolution: {str(e)}")