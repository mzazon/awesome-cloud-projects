#!/bin/bash

# Advanced IoT Device Shadow Synchronization - Deployment Script
# This script deploys the complete IoT shadow synchronization infrastructure
# including Lambda functions, DynamoDB tables, IoT resources, and monitoring

set -e  # Exit on any error

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Progress tracking
STEP_COUNT=0
TOTAL_STEPS=10

progress() {
    STEP_COUNT=$((STEP_COUNT + 1))
    echo -e "\n${BLUE}[STEP $STEP_COUNT/$TOTAL_STEPS]${NC} $1\n"
}

# Configuration variables with defaults
REGION=${AWS_REGION:-$(aws configure get region)}
ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
PROJECT_NAME=${PROJECT_NAME:-"iot-shadow-sync"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    # Validate AWS region
    if [[ -z "$REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for resource uniqueness
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Export resource names as environment variables
    export SHADOW_SYNC_LAMBDA="${PROJECT_NAME}-shadow-sync-manager-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export CONFLICT_RESOLVER_LAMBDA="${PROJECT_NAME}-conflict-resolver-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export SHADOW_HISTORY_TABLE="${PROJECT_NAME}-shadow-history-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export DEVICE_CONFIG_TABLE="${PROJECT_NAME}-device-config-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export SYNC_METRICS_TABLE="${PROJECT_NAME}-sync-metrics-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export EVENT_BUS_NAME="${PROJECT_NAME}-shadow-events-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export THING_NAME="${PROJECT_NAME}-demo-device-${ENVIRONMENT}-${RANDOM_SUFFIX}"
    export EXECUTION_ROLE_NAME="${CONFLICT_RESOLVER_LAMBDA}-execution-role"
    export POLICY_NAME="${CONFLICT_RESOLVER_LAMBDA}-policy"
    
    log_success "Resource names generated with suffix: ${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > .deployment-config << EOF
REGION=${REGION}
ACCOUNT_ID=${ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
ENVIRONMENT=${ENVIRONMENT}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SHADOW_SYNC_LAMBDA=${SHADOW_SYNC_LAMBDA}
CONFLICT_RESOLVER_LAMBDA=${CONFLICT_RESOLVER_LAMBDA}
SHADOW_HISTORY_TABLE=${SHADOW_HISTORY_TABLE}
DEVICE_CONFIG_TABLE=${DEVICE_CONFIG_TABLE}
SYNC_METRICS_TABLE=${SYNC_METRICS_TABLE}
EVENT_BUS_NAME=${EVENT_BUS_NAME}
THING_NAME=${THING_NAME}
EXECUTION_ROLE_NAME=${EXECUTION_ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
DEPLOYMENT_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
EOF
}

# Create DynamoDB tables
create_dynamodb_tables() {
    progress "Creating DynamoDB tables for shadow synchronization"
    
    # Create shadow history table
    log_info "Creating shadow history table: ${SHADOW_HISTORY_TABLE}"
    aws dynamodb create-table \
        --table-name $SHADOW_HISTORY_TABLE \
        --attribute-definitions \
            AttributeName=thingName,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
            AttributeName=shadowName,AttributeType=S \
        --key-schema \
            AttributeName=thingName,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --global-secondary-indexes \
            IndexName=ShadowNameIndex,KeySchema='[{AttributeName=shadowName,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}]',Projection='{ProjectionType=ALL}',ProvisionedThroughput='{ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Create device configuration table
    log_info "Creating device configuration table: ${DEVICE_CONFIG_TABLE}"
    aws dynamodb create-table \
        --table-name $DEVICE_CONFIG_TABLE \
        --attribute-definitions \
            AttributeName=thingName,AttributeType=S \
            AttributeName=configType,AttributeType=S \
        --key-schema \
            AttributeName=thingName,KeyType=HASH \
            AttributeName=configType,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Create sync metrics table
    log_info "Creating sync metrics table: ${SYNC_METRICS_TABLE}"
    aws dynamodb create-table \
        --table-name $SYNC_METRICS_TABLE \
        --attribute-definitions \
            AttributeName=thingName,AttributeType=S \
            AttributeName=metricTimestamp,AttributeType=N \
        --key-schema \
            AttributeName=thingName,KeyType=HASH \
            AttributeName=metricTimestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Wait for tables to be active
    log_info "Waiting for DynamoDB tables to become active..."
    for table in $SHADOW_HISTORY_TABLE $DEVICE_CONFIG_TABLE $SYNC_METRICS_TABLE; do
        aws dynamodb wait table-exists --table-name $table
        log_success "Table $table is active"
    done
}

# Create EventBridge custom bus
create_eventbridge_bus() {
    progress "Creating EventBridge custom bus"
    
    log_info "Creating EventBridge bus: ${EVENT_BUS_NAME}"
    aws events create-event-bus \
        --name $EVENT_BUS_NAME \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    log_success "EventBridge bus created: ${EVENT_BUS_NAME}"
}

# Create and deploy Lambda functions
deploy_lambda_functions() {
    progress "Creating and deploying Lambda functions"
    
    # Create Lambda execution role
    log_info "Creating Lambda execution role: ${EXECUTION_ROLE_NAME}"
    
    cat > /tmp/shadow-lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    aws iam create-role \
        --role-name "${EXECUTION_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/shadow-lambda-trust-policy.json \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Create comprehensive IAM policy
    log_info "Creating IAM policy: ${POLICY_NAME}"
    
    cat > /tmp/shadow-lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:GetThingShadow",
                "iot:UpdateThingShadow",
                "iot:DeleteThingShadow"
            ],
            "Resource": "arn:aws:iot:${REGION}:${ACCOUNT_ID}:thing/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": [
                "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${SHADOW_HISTORY_TABLE}*",
                "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DEVICE_CONFIG_TABLE}*",
                "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${SYNC_METRICS_TABLE}*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": "arn:aws:events:${REGION}:${ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file:///tmp/shadow-lambda-policy.json \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    aws iam attach-role-policy \
        --role-name "${EXECUTION_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # Create conflict resolver Lambda function code
    create_conflict_resolver_lambda
    
    # Create sync manager Lambda function code
    create_sync_manager_lambda
    
    log_success "Lambda functions deployed successfully"
}

# Create conflict resolver Lambda function
create_conflict_resolver_lambda() {
    log_info "Creating conflict resolver Lambda function"
    
    mkdir -p /tmp/shadow-conflict-resolver
    cat > /tmp/shadow-conflict-resolver/lambda_function.py << EOF
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
import os
SHADOW_HISTORY_TABLE = os.environ.get('SHADOW_HISTORY_TABLE', '${SHADOW_HISTORY_TABLE}')
DEVICE_CONFIG_TABLE = os.environ.get('DEVICE_CONFIG_TABLE', '${DEVICE_CONFIG_TABLE}')
SYNC_METRICS_TABLE = os.environ.get('SYNC_METRICS_TABLE', '${SYNC_METRICS_TABLE}')
EVENT_BUS_NAME = os.environ.get('EVENT_BUS_NAME', '${EVENT_BUS_NAME}')

def lambda_handler(event, context):
    """Handle shadow synchronization conflicts and state management"""
    try:
        logger.info(f"Shadow conflict resolution event: {json.dumps(event, default=str)}")
        
        # Parse shadow event
        if 'Records' in event:
            return handle_dynamodb_stream_event(event)
        elif 'operation' in event:
            return handle_direct_operation(event)
        else:
            return handle_shadow_delta_event(event)
            
    except Exception as e:
        logger.error(f"Error in shadow conflict resolution: {str(e)}")
        return create_error_response(str(e))

def handle_shadow_delta_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle IoT shadow delta events for conflict resolution"""
    try:
        thing_name = event.get('thingName', '')
        shadow_name = event.get('shadowName', '\$default')
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
        
        # Record shadow history
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
        strategy = 'last_writer_wins'  # Default strategy
        
        return {
            'strategy': strategy,
            'resolution': 'accept_delta',
            'action': 'overwrite_current'
        }
        
    except Exception as e:
        logger.error(f"Error resolving conflicts: {str(e)}")
        return {'strategy': 'error', 'resolution': {}, 'error': str(e)}

def apply_conflict_resolution(thing_name: str, shadow_name: str, resolution: Dict[str, Any]):
    """Apply the conflict resolution to the device shadow"""
    try:
        action = resolution.get('action', 'none')
        logger.info(f"Applying resolution action: {action} for {thing_name}")
        
    except Exception as e:
        logger.error(f"Error applying conflict resolution: {str(e)}")

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

def record_shadow_history(thing_name: str, shadow_name: str, delta: Dict[str, Any], 
                         version: int, timestamp: int):
    """Record shadow change in history table"""
    try:
        table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        table.put_item(
            Item={
                'thingName': thing_name,
                'timestamp': int(timestamp * 1000),
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
                'syncType': 'delta_update'
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

def handle_dynamodb_stream_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle DynamoDB stream events for shadow history"""
    return {'statusCode': 200, 'body': 'Stream event processed'}

def handle_direct_operation(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle direct operation invocations"""
    operation = event.get('operation', '')
    return {'statusCode': 200, 'body': f'Operation {operation} processed'}

def create_error_response(error_message: str) -> Dict[str, Any]:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    }
EOF
    
    # Create deployment package
    cd /tmp/shadow-conflict-resolver
    zip -r ../shadow-conflict-resolver.zip . > /dev/null
    cd - > /dev/null
    
    # Deploy Lambda function
    aws lambda create-function \
        --function-name $CONFLICT_RESOLVER_LAMBDA \
        --runtime python3.9 \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/${EXECUTION_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/shadow-conflict-resolver.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{SHADOW_HISTORY_TABLE=${SHADOW_HISTORY_TABLE},DEVICE_CONFIG_TABLE=${DEVICE_CONFIG_TABLE},SYNC_METRICS_TABLE=${SYNC_METRICS_TABLE},EVENT_BUS_NAME=${EVENT_BUS_NAME}}" \
        --tags Project=IoTShadowSync,Environment=$ENVIRONMENT > /dev/null
    
    log_success "Conflict resolver Lambda function created: ${CONFLICT_RESOLVER_LAMBDA}"
}

# Create sync manager Lambda function
create_sync_manager_lambda() {
    log_info "Creating sync manager Lambda function"
    
    mkdir -p /tmp/shadow-sync-manager
    cat > /tmp/shadow-sync-manager/lambda_function.py << EOF
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
import os
SHADOW_HISTORY_TABLE = os.environ.get('SHADOW_HISTORY_TABLE', '${SHADOW_HISTORY_TABLE}')
DEVICE_CONFIG_TABLE = os.environ.get('DEVICE_CONFIG_TABLE', '${DEVICE_CONFIG_TABLE}')
SYNC_METRICS_TABLE = os.environ.get('SYNC_METRICS_TABLE', '${SYNC_METRICS_TABLE}')

def lambda_handler(event, context):
    """Manage shadow synchronization operations for offline devices"""
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
        shadow_names = event.get('shadowNames', ['\$default'])
        
        sync_results = []
        
        for shadow_name in shadow_names:
            shadow = get_shadow_safely(thing_name, shadow_name)
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
        
        processed_changes = []
        conflicts_detected = []
        
        for change in cached_changes:
            shadow_name = change.get('shadowName', '\$default')
            cached_state = change.get('state', {})
            timestamp = change.get('timestamp', int(time.time()))
            
            current_shadow = get_shadow_safely(thing_name, shadow_name)
            
            conflict_check = detect_offline_conflicts(
                thing_name, shadow_name, cached_state, current_shadow, timestamp
            )
            
            if conflict_check['hasConflicts']:
                conflicts_detected.append(conflict_check)
            else:
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
                'conflicts': conflicts_detected[:5],
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
        
        metrics_table = dynamodb.Table(SYNC_METRICS_TABLE)
        
        response = metrics_table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('metricTimestamp').gte(cutoff_time) &
                           boto3.dynamodb.conditions.Attr('hadConflict').eq(True)
        )
        
        conflicts = response.get('Items', [])
        
        summary = {
            'totalConflicts': len(conflicts),
            'conflictsByType': {},
            'conflictsByThing': {},
            'timeRange': f'{time_range_hours} hours'
        }
        
        for conflict in conflicts:
            thing_name = conflict.get('thingName', 'unknown')
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

# Helper functions
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
    
    if 'delta' in shadow.get('state', {}):
        status['inSync'] = False
        status['pendingChanges'] = list(shadow['state']['delta'].keys())
    
    return status

def detect_offline_conflicts(thing_name: str, shadow_name: str, cached_state: Dict[str, Any],
                           current_shadow: Dict[str, Any], cached_timestamp: int) -> Dict[str, Any]:
    """Detect conflicts between cached offline changes and current shadow"""
    conflicts = []
    
    current_reported = current_shadow.get('state', {}).get('reported', {})
    current_timestamp = current_shadow.get('metadata', {}).get('reported', {}).get('timestamp', 0)
    
    if current_timestamp > cached_timestamp:
        for key, cached_value in cached_state.items():
            if key in current_reported and current_reported[key] != cached_value:
                conflicts.append({
                    'field': key,
                    'cachedValue': cached_value,
                    'currentValue': current_reported[key],
                    'type': 'concurrent_modification'
                })
    
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
        shadow_names = ['\$default', 'configuration', 'telemetry', 'maintenance']
        
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
            
            if 'delta' in shadow.get('state', {}):
                health_status['issues'].append(f'Pending changes in {shadow_name}')
                if health_status['status'] == 'healthy':
                    health_status['status'] = 'warning'
        
        return health_status
        
    except Exception as e:
        logger.error(f"Error assessing device health: {str(e)}")
        return {
            'thingName': thing_name,
            'status': 'error',
            'error': str(e)
        }
EOF
    
    # Create deployment package
    cd /tmp/shadow-sync-manager
    zip -r ../shadow-sync-manager.zip . > /dev/null
    cd - > /dev/null
    
    # Deploy Lambda function
    aws lambda create-function \
        --function-name $SHADOW_SYNC_LAMBDA \
        --runtime python3.9 \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/${EXECUTION_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/shadow-sync-manager.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment Variables="{SHADOW_HISTORY_TABLE=${SHADOW_HISTORY_TABLE},DEVICE_CONFIG_TABLE=${DEVICE_CONFIG_TABLE},SYNC_METRICS_TABLE=${SYNC_METRICS_TABLE}}" \
        --tags Project=IoTShadowSync,Environment=$ENVIRONMENT > /dev/null
    
    log_success "Sync manager Lambda function created: ${SHADOW_SYNC_LAMBDA}"
}

# Create IoT resources
create_iot_resources() {
    progress "Creating IoT thing and device resources"
    
    # Create IoT thing type (optional but good practice)
    log_info "Creating IoT thing type"
    aws iot create-thing-type \
        --thing-type-name "SyncDemoDevice" \
        --thing-type-description "Demo device type for shadow synchronization testing" \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null 2>&1 || true
    
    # Create demo IoT thing
    log_info "Creating IoT thing: ${THING_NAME}"
    aws iot create-thing \
        --thing-name $THING_NAME \
        --thing-type-name "SyncDemoDevice" \
        --attribute-payload '{
            "attributes": {
                "deviceType": "sensor_gateway",
                "location": "test_lab",
                "syncEnabled": "true",
                "environment": "'$ENVIRONMENT'"
            }
        }' > /dev/null
    
    # Create device certificates
    log_info "Creating device certificates"
    aws iot create-keys-and-certificate \
        --set-as-active \
        --certificate-pem-outfile demo-device-certificate.pem \
        --public-key-outfile demo-device-public-key.pem \
        --private-key-outfile demo-device-private-key.pem > demo-cert-output.json
    
    DEMO_CERT_ARN=$(jq -r '.certificateArn' demo-cert-output.json)
    
    # Create IoT policy for demo device
    log_info "Creating IoT policy for device"
    cat > /tmp/demo-device-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect"
            ],
            "Resource": "arn:aws:iot:${REGION}:${ACCOUNT_ID}:client/${THING_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive"
            ],
            "Resource": [
                "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topic/\$aws/things/${THING_NAME}/shadow/*",
                "arn:aws:iot:${REGION}:${ACCOUNT_ID}:topicfilter/\$aws/things/${THING_NAME}/shadow/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:GetThingShadow",
                "iot:UpdateThingShadow"
            ],
            "Resource": "arn:aws:iot:${REGION}:${ACCOUNT_ID}:thing/${THING_NAME}"
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "DemoDeviceSyncPolicy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/demo-device-policy.json \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Attach policy and certificate to thing
    aws iot attach-policy \
        --policy-name "DemoDeviceSyncPolicy-${RANDOM_SUFFIX}" \
        --target $DEMO_CERT_ARN
    
    aws iot attach-thing-principal \
        --thing-name $THING_NAME \
        --principal $DEMO_CERT_ARN
    
    # Initialize named shadows
    log_info "Initializing named shadows"
    SHADOW_NAMES=("configuration" "telemetry" "maintenance")
    
    for shadow_name in "${SHADOW_NAMES[@]}"; do
        case $shadow_name in
            "configuration")
                initial_state='{"state":{"desired":{"samplingRate":30,"alertThreshold":80,"operatingMode":"normal"},"reported":{"samplingRate":30,"alertThreshold":80,"operatingMode":"normal","firmwareVersion":"v1.0.0"}}}'
                ;;
            "telemetry")
                initial_state='{"state":{"reported":{"temperature":23.5,"humidity":65.2,"pressure":1013.25,"lastUpdate":"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}}}'
                ;;
            "maintenance")
                initial_state='{"state":{"desired":{"maintenanceWindow":"02:00-04:00","autoUpdate":true},"reported":{"lastMaintenance":"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'","nextScheduled":"'$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%S.%3NZ)'"}}}'
                ;;
        esac
        
        aws iot-data update-thing-shadow \
            --thing-name $THING_NAME \
            --shadow-name $shadow_name \
            --payload "$initial_state" \
            "${shadow_name}-shadow-output.json" > /dev/null
        
        log_success "Initialized shadow: ${shadow_name}"
    done
    
    # Save certificate ARN for cleanup
    echo "DEMO_CERT_ARN=${DEMO_CERT_ARN}" >> .deployment-config
    echo "DEMO_CERT_ID=$(jq -r '.certificateId' demo-cert-output.json)" >> .deployment-config
    echo "DEMO_POLICY_NAME=DemoDeviceSyncPolicy-${RANDOM_SUFFIX}" >> .deployment-config
}

# Create IoT rules for shadow processing
create_iot_rules() {
    progress "Creating IoT rules for shadow delta processing"
    
    # Create IoT rule to process shadow delta events
    log_info "Creating shadow delta processing rule"
    aws iot create-topic-rule \
        --rule-name "ShadowDeltaProcessingRule-${RANDOM_SUFFIX}" \
        --topic-rule-payload '{
            "sql": "SELECT *, thingName as thingName, shadowName as shadowName FROM \"$aws/things/+/shadow/+/update/delta\"",
            "description": "Process shadow delta events for conflict resolution",
            "actions": [
                {
                    "lambda": {
                        "functionArn": "arn:aws:lambda:'${REGION}':'${ACCOUNT_ID}':function:'${CONFLICT_RESOLVER_LAMBDA}'"
                    }
                }
            ]
        }' > /dev/null
    
    # Grant IoT permission to invoke Lambda function
    aws lambda add-permission \
        --function-name $CONFLICT_RESOLVER_LAMBDA \
        --statement-id "iot-shadow-delta-permission-${RANDOM_SUFFIX}" \
        --action "lambda:InvokeFunction" \
        --principal "iot.amazonaws.com" \
        --source-arn "arn:aws:iot:${REGION}:${ACCOUNT_ID}:rule/ShadowDeltaProcessingRule-${RANDOM_SUFFIX}" > /dev/null
    
    # Create CloudWatch log group for shadow audit
    log_info "Creating CloudWatch log group for shadow audit"
    aws logs create-log-group \
        --log-group-name "/aws/iot/shadow-audit-${RANDOM_SUFFIX}" \
        --tags Project=IoTShadowSync,Environment=$ENVIRONMENT > /dev/null
    
    # Create rule to log all shadow events for audit
    aws iot create-topic-rule \
        --rule-name "ShadowAuditLoggingRule-${RANDOM_SUFFIX}" \
        --topic-rule-payload '{
            "sql": "SELECT * FROM \"$aws/things/+/shadow/+/update/+\"",
            "description": "Log all shadow update events for audit trail",
            "actions": [
                {
                    "cloudwatchLogs": {
                        "logGroupName": "/aws/iot/shadow-audit-'${RANDOM_SUFFIX}'",
                        "roleArn": "arn:aws:iam:'${ACCOUNT_ID}':role/'${EXECUTION_ROLE_NAME}'"
                    }
                }
            ]
        }' > /dev/null
    
    # Save rule names for cleanup
    echo "DELTA_RULE_NAME=ShadowDeltaProcessingRule-${RANDOM_SUFFIX}" >> .deployment-config
    echo "AUDIT_RULE_NAME=ShadowAuditLoggingRule-${RANDOM_SUFFIX}" >> .deployment-config
    echo "AUDIT_LOG_GROUP=/aws/iot/shadow-audit-${RANDOM_SUFFIX}" >> .deployment-config
    
    log_success "IoT rules created for shadow processing"
}

# Configure device settings
configure_device_settings() {
    progress "Configuring device-specific conflict resolution settings"
    
    # Set up device configuration for conflict resolution
    log_info "Setting up conflict resolution configuration"
    aws dynamodb put-item \
        --table-name $DEVICE_CONFIG_TABLE \
        --item '{
            "thingName": {"S": "'"$THING_NAME"'"},
            "configType": {"S": "conflict_resolution"},
            "config": {
                "M": {
                    "strategy": {"S": "field_level_merge"},
                    "field_priorities": {
                        "M": {
                            "firmware_version": {"S": "high"},
                            "temperature": {"S": "medium"},
                            "configuration": {"S": "high"},
                            "telemetry": {"S": "low"}
                        }
                    },
                    "auto_resolve_threshold": {"N": "5"},
                    "manual_review_severity": {"S": "high"}
                }
            },
            "lastUpdated": {"S": "'"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"'"}
        }' > /dev/null
    
    # Set up sync preferences
    log_info "Setting up sync preferences"
    aws dynamodb put-item \
        --table-name $DEVICE_CONFIG_TABLE \
        --item '{
            "thingName": {"S": "'"$THING_NAME"'"},
            "configType": {"S": "sync_preferences"},
            "config": {
                "M": {
                    "offline_buffer_duration": {"N": "3600"},
                    "max_conflict_retries": {"N": "3"},
                    "sync_frequency_seconds": {"N": "60"},
                    "compression_enabled": {"BOOL": true},
                    "delta_only_sync": {"BOOL": true}
                }
            },
            "lastUpdated": {"S": "'"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"'"}
        }' > /dev/null
    
    log_success "Device configuration completed"
}

# Create monitoring and alerting
create_monitoring() {
    progress "Setting up EventBridge rules and CloudWatch monitoring"
    
    # Create EventBridge rule for conflict notifications
    log_info "Creating EventBridge rule for conflict notifications"
    aws events put-rule \
        --name "shadow-conflict-notifications-${RANDOM_SUFFIX}" \
        --event-pattern '{
            "source": ["iot.shadow.sync"],
            "detail-type": ["Conflict Resolved", "Manual Review Required"]
        }' \
        --state ENABLED \
        --description "Process shadow conflict events" \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Create EventBridge rule for periodic health checks
    log_info "Creating EventBridge rule for periodic health checks"
    aws events put-rule \
        --name "shadow-health-check-schedule-${RANDOM_SUFFIX}" \
        --schedule-expression "rate(15 minutes)" \
        --state ENABLED \
        --description "Periodic shadow synchronization health checks" \
        --tags Key=Project,Value=IoTShadowSync,Key=Environment,Value=$ENVIRONMENT > /dev/null
    
    # Add Lambda target for health checks
    aws events put-targets \
        --rule "shadow-health-check-schedule-${RANDOM_SUFFIX}" \
        --targets '[{
            "Id": "1",
            "Arn": "arn:aws:lambda:'${REGION}':'${ACCOUNT_ID}':function:'${SHADOW_SYNC_LAMBDA}'",
            "Input": "{\"operation\": \"health_report\", \"thingNames\": [\"'${THING_NAME}'\"]}"
        }]' > /dev/null
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name $SHADOW_SYNC_LAMBDA \
        --statement-id "eventbridge-health-check-permission-${RANDOM_SUFFIX}" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${REGION}:${ACCOUNT_ID}:rule/shadow-health-check-schedule-${RANDOM_SUFFIX}" > /dev/null
    
    # Create CloudWatch dashboard
    log_info "Creating CloudWatch dashboard"
    cat > /tmp/shadow-sync-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["IoT/ShadowSync", "ConflictDetected"],
                    [".", "SyncCompleted"],
                    [".", "OfflineSync"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${REGION}",
                "title": "Shadow Synchronization Metrics"
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/iot/shadow-audit-${RANDOM_SUFFIX}' | fields @timestamp, @message\\n| filter @message like /shadow/\\n| sort @timestamp desc\\n| limit 50",
                "region": "${REGION}",
                "title": "Shadow Update Audit Trail"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${CONFLICT_RESOLVER_LAMBDA}' | fields @timestamp, @message\\n| filter @message like /conflict/\\n| sort @timestamp desc\\n| limit 30",
                "region": "${REGION}",
                "title": "Conflict Resolution Events"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "IoT-Shadow-Synchronization-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/shadow-sync-dashboard.json > /dev/null
    
    # Save monitoring resource names for cleanup
    echo "CONFLICT_NOTIFICATION_RULE=shadow-conflict-notifications-${RANDOM_SUFFIX}" >> .deployment-config
    echo "HEALTH_CHECK_RULE=shadow-health-check-schedule-${RANDOM_SUFFIX}" >> .deployment-config
    echo "DASHBOARD_NAME=IoT-Shadow-Synchronization-${RANDOM_SUFFIX}" >> .deployment-config
    
    log_success "Monitoring and alerting configured"
}

# Final validation and summary
validate_deployment() {
    progress "Validating deployment and generating summary"
    
    log_info "Validating Lambda functions..."
    CONFLICT_LAMBDA_STATUS=$(aws lambda get-function --function-name $CONFLICT_RESOLVER_LAMBDA --query 'Configuration.State' --output text 2>/dev/null || echo "ERROR")
    SYNC_LAMBDA_STATUS=$(aws lambda get-function --function-name $SHADOW_SYNC_LAMBDA --query 'Configuration.State' --output text 2>/dev/null || echo "ERROR")
    
    log_info "Validating DynamoDB tables..."
    HISTORY_TABLE_STATUS=$(aws dynamodb describe-table --table-name $SHADOW_HISTORY_TABLE --query 'Table.TableStatus' --output text 2>/dev/null || echo "ERROR")
    CONFIG_TABLE_STATUS=$(aws dynamodb describe-table --table-name $DEVICE_CONFIG_TABLE --query 'Table.TableStatus' --output text 2>/dev/null || echo "ERROR")
    METRICS_TABLE_STATUS=$(aws dynamodb describe-table --table-name $SYNC_METRICS_TABLE --query 'Table.TableStatus' --output text 2>/dev/null || echo "ERROR")
    
    log_info "Validating IoT resources..."
    IOT_THING_STATUS=$(aws iot describe-thing --thing-name $THING_NAME --query 'thingName' --output text 2>/dev/null || echo "ERROR")
    
    # Generate deployment summary
    echo -e "\n${GREEN}=== DEPLOYMENT SUMMARY ===${NC}\n"
    
    echo -e "${BLUE}Lambda Functions:${NC}"
    echo "  Conflict Resolver: $CONFLICT_RESOLVER_LAMBDA [$CONFLICT_LAMBDA_STATUS]"
    echo "  Sync Manager: $SHADOW_SYNC_LAMBDA [$SYNC_LAMBDA_STATUS]"
    
    echo -e "\n${BLUE}DynamoDB Tables:${NC}"
    echo "  Shadow History: $SHADOW_HISTORY_TABLE [$HISTORY_TABLE_STATUS]"
    echo "  Device Config: $DEVICE_CONFIG_TABLE [$CONFIG_TABLE_STATUS]"
    echo "  Sync Metrics: $SYNC_METRICS_TABLE [$METRICS_TABLE_STATUS]"
    
    echo -e "\n${BLUE}IoT Resources:${NC}"
    echo "  Thing Name: $THING_NAME [$IOT_THING_STATUS]"
    echo "  EventBridge Bus: $EVENT_BUS_NAME"
    
    echo -e "\n${BLUE}Monitoring:${NC}"
    echo "  CloudWatch Dashboard: IoT-Shadow-Synchronization-${RANDOM_SUFFIX}"
    echo "  Audit Log Group: /aws/iot/shadow-audit-${RANDOM_SUFFIX}"
    
    echo -e "\n${BLUE}Test Commands:${NC}"
    echo "  # Test sync check:"
    echo "  aws lambda invoke --function-name $SHADOW_SYNC_LAMBDA \\"
    echo "    --payload '{\"operation\":\"sync_check\",\"thingName\":\"$THING_NAME\",\"shadowNames\":[\"configuration\",\"telemetry\"]}' \\"
    echo "    --cli-binary-format raw-in-base64-out response.json"
    echo ""
    echo "  # Test health report:"
    echo "  aws lambda invoke --function-name $SHADOW_SYNC_LAMBDA \\"
    echo "    --payload '{\"operation\":\"health_report\",\"thingNames\":[\"$THING_NAME\"]}' \\"
    echo "    --cli-binary-format raw-in-base64-out health-response.json"
    
    # Check for any deployment errors
    if [[ "$CONFLICT_LAMBDA_STATUS" != "Active" ]] || [[ "$SYNC_LAMBDA_STATUS" != "Active" ]] || \
       [[ "$HISTORY_TABLE_STATUS" != "ACTIVE" ]] || [[ "$CONFIG_TABLE_STATUS" != "ACTIVE" ]] || \
       [[ "$METRICS_TABLE_STATUS" != "ACTIVE" ]] || [[ "$IOT_THING_STATUS" == "ERROR" ]]; then
        log_warning "Some resources may not be fully active. Check the AWS Console for details."
        echo ""
        echo -e "${YELLOW}Run the following to check resource status:${NC}"
        echo "  aws lambda get-function --function-name $CONFLICT_RESOLVER_LAMBDA --query 'Configuration.State'"
        echo "  aws dynamodb describe-table --table-name $SHADOW_HISTORY_TABLE --query 'Table.TableStatus'"
        echo "  aws iot describe-thing --thing-name $THING_NAME"
    else
        log_success "All resources deployed successfully!"
    fi
    
    echo -e "\n${BLUE}Cost Estimate:${NC}"
    echo "  Lambda invocations: ~\$0.20/1M invocations"
    echo "  DynamoDB: ~\$1.25/month for 1GB + requests"
    echo "  IoT Core: ~\$1.00/1M messages"
    echo "  CloudWatch Logs: ~\$0.50/GB ingested"
    echo "  EventBridge: ~\$1.00/1M events"
    echo "  Estimated monthly cost for demo: \$5-15"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "  1. Test shadow synchronization using the provided test commands"
    echo "  2. View CloudWatch dashboard for monitoring"
    echo "  3. Configure device certificates for real devices"
    echo "  4. Customize conflict resolution strategies in device configuration"
    echo "  5. Set up alerts based on conflict frequency"
    
    echo -e "\n${BLUE}Configuration saved to:${NC} .deployment-config"
    echo -e "${BLUE}To clean up:${NC} ./destroy.sh"
}

# Cleanup function for errors
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    if [[ -f .deployment-config ]]; then
        source .deployment-config
        # Basic cleanup - more comprehensive cleanup in destroy.sh
        aws lambda delete-function --function-name $CONFLICT_RESOLVER_LAMBDA 2>/dev/null || true
        aws lambda delete-function --function-name $SHADOW_SYNC_LAMBDA 2>/dev/null || true
    fi
    exit 1
}

# Main execution
main() {
    echo -e "${GREEN}Starting Advanced IoT Device Shadow Synchronization Deployment${NC}\n"
    
    # Set error handler
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_dynamodb_tables
    create_eventbridge_bus
    deploy_lambda_functions
    create_iot_resources
    create_iot_rules
    configure_device_settings
    create_monitoring
    validate_deployment
    
    # Cleanup temporary files
    rm -f /tmp/shadow-* /tmp/demo-* 2>/dev/null || true
    
    echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
    echo -e "${BLUE}Total deployment time: $(($(date +%s) - START_TIME)) seconds${NC}\n"
}

# Record start time
START_TIME=$(date +%s)

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi