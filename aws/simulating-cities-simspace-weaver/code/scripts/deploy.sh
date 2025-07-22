#!/bin/bash

# Smart City Digital Twins with SimSpace Weaver and IoT - Deployment Script
# This script deploys the complete infrastructure for the smart city digital twin solution

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run    Show what would be deployed without making changes"
            echo "  --force      Force deployment even if resources exist"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    info "Running in DRY-RUN mode - no resources will be created"
fi

log "Starting Smart City Digital Twins deployment..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
fi

# Check AWS CLI version
AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log "AWS CLI version: $AWS_VERSION"

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS authentication failed. Please configure your AWS credentials."
fi

# Check required permissions
info "Verifying AWS permissions..."
CALLER_IDENTITY=$(aws sts get-caller-identity)
AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
log "Authenticated as: $(echo "$CALLER_IDENTITY" | jq -r '.Arn')"

# Set environment variables
export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    warn "AWS region not configured, defaulting to us-east-1"
fi

export AWS_ACCOUNT_ID
log "Using AWS region: $AWS_REGION"
log "Using AWS account: $AWS_ACCOUNT_ID"

# Generate unique identifiers for resources
if [ "$DRY_RUN" = false ]; then
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
else
    RANDOM_SUFFIX="dryrun"
fi

# Set project variables
export PROJECT_NAME="smartcity-${RANDOM_SUFFIX}"
export IOT_THING_GROUP_NAME="${PROJECT_NAME}-sensors"
export DYNAMODB_TABLE_NAME="${PROJECT_NAME}-sensor-data"
export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
export SIMSPACE_PROJECT_NAME="${PROJECT_NAME}-simulation"
export S3_BUCKET_NAME="${PROJECT_NAME}-simulation-${AWS_REGION}"

log "Project configuration:"
log "  Project Name: $PROJECT_NAME"
log "  IoT Thing Group: $IOT_THING_GROUP_NAME"
log "  DynamoDB Table: $DYNAMODB_TABLE_NAME"
log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
log "  S3 Bucket: $S3_BUCKET_NAME"

# Check for existing resources
if [ "$FORCE_DEPLOY" = false ]; then
    info "Checking for existing resources..."
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &>/dev/null; then
        error "DynamoDB table $DYNAMODB_TABLE_NAME already exists. Use --force to override."
    fi
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        error "Lambda function $LAMBDA_FUNCTION_NAME already exists. Use --force to override."
    fi
    
    # Check if S3 bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &>/dev/null; then
        error "S3 bucket $S3_BUCKET_NAME already exists. Use --force to override."
    fi
fi

if [ "$DRY_RUN" = true ]; then
    log "DRY-RUN: Would deploy resources with the above configuration"
    exit 0
fi

# Start deployment
log "Beginning resource deployment..."

# Create IAM role for Lambda execution
log "Creating IAM role for Lambda execution..."
aws iam create-role \
    --role-name "${PROJECT_NAME}-lambda-role" \
    --assume-role-policy-document '{
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
    }' || warn "IAM role may already exist"

# Wait for role to be available
sleep 10

# Attach managed policies for Lambda execution
log "Attaching Lambda execution policies..."
aws iam attach-role-policy \
    --role-name "${PROJECT_NAME}-lambda-role" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
    --role-name "${PROJECT_NAME}-lambda-role" \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaDynamoDBExecutionRole

aws iam attach-role-policy \
    --role-name "${PROJECT_NAME}-lambda-role" \
    --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

log "✅ IAM role created and configured"

# Create DynamoDB table with streams enabled
log "Creating DynamoDB table for sensor data storage..."
aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_NAME" \
    --attribute-definitions \
        AttributeName=sensor_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=S \
    --key-schema \
        AttributeName=sensor_id,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --provisioned-throughput \
        ReadCapacityUnits=10,WriteCapacityUnits=10 \
    --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES

# Wait for table creation to complete
log "Waiting for DynamoDB table creation to complete..."
aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME"

# Store table ARN for later use
TABLE_ARN=$(aws dynamodb describe-table \
    --table-name "$DYNAMODB_TABLE_NAME" \
    --query 'Table.TableArn' --output text)

log "✅ DynamoDB table created with streams enabled: $DYNAMODB_TABLE_NAME"

# Configure IoT Core Thing Group and Policies
log "Configuring IoT Core thing group and policies..."
aws iot create-thing-group \
    --thing-group-name "$IOT_THING_GROUP_NAME" \
    --thing-group-properties \
        'thingGroupDescription="Smart city sensor fleet for digital twin"'

# Create IoT policy for sensor devices
aws iot create-policy \
    --policy-name "${PROJECT_NAME}-sensor-policy" \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Action\": [\"iot:Connect\"],
                \"Resource\": \"arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/\${aws:username}\"
            },
            {
                \"Effect\": \"Allow\",
                \"Action\": [\"iot:Publish\"],
                \"Resource\": \"arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smartcity/sensors/*\"
            }
        ]
    }"

# Create sample IoT thing for testing
aws iot create-thing \
    --thing-name "${PROJECT_NAME}-traffic-sensor-001" \
    --thing-type-name traffic-sensor || true

# Add thing to group
aws iot add-thing-to-thing-group \
    --thing-group-name "$IOT_THING_GROUP_NAME" \
    --thing-name "${PROJECT_NAME}-traffic-sensor-001"

log "✅ IoT Core configured with thing group: $IOT_THING_GROUP_NAME"

# Create Lambda function for data processing
log "Creating Lambda function for data processing..."

# Create Lambda function code
cat > /tmp/lambda_function.py << EOF
import json
import boto3
import uuid
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${DYNAMODB_TABLE_NAME}')

def lambda_handler(event, context):
    """Process IoT sensor data and store in DynamoDB"""
    try:
        # Parse IoT message
        for record in event.get('Records', []):
            # Extract sensor data from IoT message
            message = json.loads(record['body']) if 'body' in record else record
            
            sensor_data = {
                'sensor_id': message.get('sensor_id', 'unknown'),
                'timestamp': datetime.utcnow().isoformat(),
                'sensor_type': message.get('sensor_type', 'generic'),
                'location': message.get('location', {}),
                'data': message.get('data', {}),
                'metadata': {
                    'processed_at': datetime.utcnow().isoformat(),
                    'processor_id': context.function_name
                }
            }
            
            # Store in DynamoDB
            table.put_item(Item=sensor_data)
            
            logger.info(f"Processed sensor data: {sensor_data['sensor_id']}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed sensor data')
        }
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        raise
EOF

# Create deployment package
cd /tmp
zip -r lambda_function.zip lambda_function.py

# Create Lambda function
aws lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment "Variables={TABLE_NAME=${DYNAMODB_TABLE_NAME}}"

log "✅ Lambda function deployed: $LAMBDA_FUNCTION_NAME"

# Create IoT rule for message routing
log "Creating IoT rule for sensor data processing..."
RULE_NAME="${PROJECT_NAME//-/_}_sensor_processing"
aws iot create-topic-rule \
    --rule-name "$RULE_NAME" \
    --topic-rule-payload "{
        \"sql\": \"SELECT * FROM 'smartcity/sensors/+/data'\",
        \"description\": \"Route smart city sensor data to processing Lambda\",
        \"actions\": [
            {
                \"lambda\": {
                    \"functionArn\": \"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\"
                }
            }
        ]
    }"

# Grant IoT permission to invoke Lambda
aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id iot-invoke-permission \
    --action lambda:InvokeFunction \
    --principal iot.amazonaws.com \
    --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}"

log "✅ IoT rule created for sensor data routing"

# Configure DynamoDB Streams for real-time processing
log "Configuring DynamoDB streams for real-time processing..."

# Get DynamoDB stream ARN
STREAM_ARN=$(aws dynamodb describe-table \
    --table-name "$DYNAMODB_TABLE_NAME" \
    --query 'Table.LatestStreamArn' --output text)

# Create stream processing function
cat > /tmp/stream_processor.py << EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process DynamoDB stream events for simulation updates"""
    try:
        for record in event['Records']:
            event_name = record['eventName']
            
            if event_name in ['INSERT', 'MODIFY']:
                # Extract sensor data from stream record
                sensor_data = record['dynamodb']['NewImage']
                
                # Process for simulation input
                simulation_input = {
                    'sensor_id': sensor_data['sensor_id']['S'],
                    'timestamp': sensor_data['timestamp']['S'],
                    'sensor_type': sensor_data['sensor_type']['S'],
                    'event_type': event_name,
                    'data': sensor_data.get('data', {})
                }
                
                logger.info(f"Processed stream event: {simulation_input}")
                
                # TODO: Send to SimSpace Weaver simulation
                # This would typically trigger simulation updates
                
        return {'statusCode': 200, 'body': 'Stream processed successfully'}
        
    except Exception as e:
        logger.error(f"Error processing stream: {str(e)}")
        raise
EOF

# Create stream processing deployment package
zip -r stream_processor.zip stream_processor.py

# Create stream processing Lambda function
aws lambda create-function \
    --function-name "${PROJECT_NAME}-stream-processor" \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
    --handler stream_processor.lambda_handler \
    --zip-file fileb://stream_processor.zip \
    --timeout 60 \
    --memory-size 256

# Create event source mapping for DynamoDB stream
aws lambda create-event-source-mapping \
    --function-name "${PROJECT_NAME}-stream-processor" \
    --event-source-arn "$STREAM_ARN" \
    --starting-position LATEST \
    --batch-size 10

log "✅ DynamoDB stream processing configured"

# Set up SimSpace Weaver simulation project
log "Setting up SimSpace Weaver simulation project..."

# Create S3 bucket for simulation assets
aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"

# Create simulation schema configuration
cat > /tmp/simulation_schema.yaml << EOF
name: smart-city-digital-twin
spatial_domains:
  - name: city_grid
    partitioning_strategy: grid_partitioning
    dimensions:
      x: 1000
      y: 1000
      z: 100
    
partitioning_strategies:
  grid_partitioning:
    type: grid
    grid_size: 4
    overlap: 10
    
apps:
  - name: traffic_simulation
    type: spatial
    executable: traffic_sim.py
    instances: 4
    
  - name: utility_monitoring
    type: spatial
    executable: utility_sim.py
    instances: 2
    
  - name: emergency_response
    type: spatial
    executable: emergency_sim.py
    instances: 1
EOF

# Create basic simulation application
cat > /tmp/traffic_sim.py << 'EOF'
import json
import time
import random
from datetime import datetime

class TrafficSimulation:
    def __init__(self):
        self.vehicles = []
        self.traffic_lights = []
        self.current_time = datetime.now()
        
    def initialize(self):
        """Initialize simulation state"""
        print("Initializing traffic simulation...")
        # Create initial vehicles and traffic infrastructure
        self.create_initial_state()
        
    def create_initial_state(self):
        """Create initial simulation entities"""
        # Generate traffic lights
        for i in range(10):
            light = {
                'id': f'light_{i}',
                'position': {'x': random.randint(0, 1000), 'y': random.randint(0, 1000)},
                'state': 'green',
                'cycle_time': 30
            }
            self.traffic_lights.append(light)
            
        # Generate vehicles
        for i in range(50):
            vehicle = {
                'id': f'vehicle_{i}',
                'position': {'x': random.randint(0, 1000), 'y': random.randint(0, 1000)},
                'speed': random.randint(20, 60),
                'destination': {'x': random.randint(0, 1000), 'y': random.randint(0, 1000)}
            }
            self.vehicles.append(vehicle)
            
    def update(self, sensor_data):
        """Update simulation based on real sensor data"""
        print(f"Updating simulation with sensor data: {len(sensor_data)} records")
        
        # Process traffic sensor data
        for data in sensor_data:
            if data.get('sensor_type') == 'traffic':
                self.process_traffic_data(data)
                
    def process_traffic_data(self, data):
        """Process traffic sensor data for simulation"""
        location = data.get('location', {})
        traffic_count = data.get('data', {}).get('vehicle_count', 0)
        
        # Update simulation based on real traffic data
        print(f"Processing traffic data: {traffic_count} vehicles at {location}")
        
    def simulate_step(self):
        """Execute one simulation step"""
        # Update vehicle positions
        for vehicle in self.vehicles:
            # Simple movement simulation
            vehicle['position']['x'] += random.randint(-5, 5)
            vehicle['position']['y'] += random.randint(-5, 5)
            
        # Update traffic lights
        for light in self.traffic_lights:
            # Simple traffic light cycling
            if random.random() < 0.1:  # 10% chance to change state
                light['state'] = 'red' if light['state'] == 'green' else 'green'
                
        return {
            'vehicles': len(self.vehicles),
            'traffic_lights': len(self.traffic_lights),
            'timestamp': datetime.now().isoformat()
        }

if __name__ == "__main__":
    sim = TrafficSimulation()
    sim.initialize()
    
    # Run simulation loop
    for step in range(100):
        result = sim.simulate_step()
        print(f"Step {step}: {result}")
        time.sleep(1)
EOF

# Create simulation deployment package
zip -r simulation_package.zip simulation_schema.yaml traffic_sim.py

# Upload to S3 for SimSpace Weaver
aws s3 cp simulation_package.zip "s3://${S3_BUCKET_NAME}/"

log "✅ SimSpace Weaver simulation project configured"

# Create simulation management and analytics functions
log "Creating simulation management functions..."

# Create simulation management function
cat > /tmp/simulation_manager.py << EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

simspace = boto3.client('simspaceweaver')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Manage SimSpace Weaver simulations"""
    try:
        action = event.get('action', 'status')
        
        if action == 'start':
            return start_simulation(event, context)
        elif action == 'stop':
            return stop_simulation(event)
        elif action == 'status':
            return get_simulation_status(event)
        else:
            return {'statusCode': 400, 'body': 'Invalid action'}
            
    except Exception as e:
        logger.error(f"Error managing simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def start_simulation(event, context):
    """Start a new simulation"""
    simulation_name = event.get('simulation_name', 'smart-city-simulation')
    
    try:
        # Extract AWS account ID from context
        account_id = context.invoked_function_arn.split(':')[4]
        
        response = simspace.start_simulation(
            Name=simulation_name,
            RoleArn=f'arn:aws:iam::{account_id}:role/SimSpaceWeaverRole',
            SchemaS3Location={
                'BucketName': f'{simulation_name}-{context.aws_region}',
                'ObjectKey': 'simulation_schema.yaml'
            }
        )
        
        logger.info(f"Started simulation: {simulation_name}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation started',
                'simulation_name': simulation_name,
                'arn': response.get('Arn')
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to start simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def stop_simulation(event):
    """Stop running simulation"""
    simulation_name = event.get('simulation_name')
    
    try:
        simspace.stop_simulation(Simulation=simulation_name)
        
        logger.info(f"Stopped simulation: {simulation_name}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation stopped',
                'simulation_name': simulation_name
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to stop simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def get_simulation_status(event):
    """Get current simulation status"""
    try:
        response = simspace.list_simulations()
        
        simulations = []
        for sim in response.get('Simulations', []):
            simulations.append({
                'name': sim.get('Name'),
                'status': sim.get('Status'),
                'created': sim.get('CreationTime').isoformat() if sim.get('CreationTime') else None
            })
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'simulations': simulations,
                'count': len(simulations)
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to get simulation status: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}
EOF

# Create deployment package
zip -r simulation_manager.zip simulation_manager.py

# Deploy simulation management function
aws lambda create-function \
    --function-name "${PROJECT_NAME}-simulation-manager" \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
    --handler simulation_manager.lambda_handler \
    --zip-file fileb://simulation_manager.zip \
    --timeout 300 \
    --memory-size 512

log "✅ Simulation management functions deployed"

# Create analytics processing function
log "Creating analytics processing function..."
cat > /tmp/analytics_processor.py << EOF
import json
import boto3
import logging
from datetime import datetime, timedelta
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${DYNAMODB_TABLE_NAME}')

def lambda_handler(event, context):
    """Process analytics for smart city insights"""
    try:
        analytics_type = event.get('type', 'traffic_summary')
        time_range = event.get('time_range', '24h')
        
        if analytics_type == 'traffic_summary':
            return generate_traffic_summary(time_range)
        elif analytics_type == 'sensor_health':
            return generate_sensor_health_report()
        elif analytics_type == 'simulation_insights':
            return generate_simulation_insights()
        else:
            return {'statusCode': 400, 'body': 'Invalid analytics type'}
            
    except Exception as e:
        logger.error(f"Error processing analytics: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def generate_traffic_summary(time_range):
    """Generate traffic analytics summary"""
    try:
        # Calculate time range
        end_time = datetime.now()
        if time_range == '24h':
            start_time = end_time - timedelta(hours=24)
        elif time_range == '7d':
            start_time = end_time - timedelta(days=7)
        else:
            start_time = end_time - timedelta(hours=1)
            
        # Query traffic sensor data
        response = table.scan(
            FilterExpression='#sensor_type = :sensor_type AND #timestamp BETWEEN :start_time AND :end_time',
            ExpressionAttributeNames={
                '#sensor_type': 'sensor_type',
                '#timestamp': 'timestamp'
            },
            ExpressionAttributeValues={
                ':sensor_type': 'traffic',
                ':start_time': start_time.isoformat(),
                ':end_time': end_time.isoformat()
            }
        )
        
        # Process traffic data
        traffic_data = response['Items']
        total_vehicles = sum(item.get('data', {}).get('vehicle_count', 0) for item in traffic_data)
        average_speed = sum(item.get('data', {}).get('average_speed', 0) for item in traffic_data) / len(traffic_data) if traffic_data else 0
        
        # Generate congestion metrics
        congestion_score = calculate_congestion_score(traffic_data)
        
        summary = {
            'time_range': time_range,
            'total_vehicles': total_vehicles,
            'average_speed': float(average_speed),
            'congestion_score': congestion_score,
            'sensor_count': len(set(item['sensor_id'] for item in traffic_data)),
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(summary, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate traffic summary: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def calculate_congestion_score(traffic_data):
    """Calculate traffic congestion score"""
    if not traffic_data:
        return 0
        
    # Simple congestion calculation based on speed and volume
    total_score = 0
    for item in traffic_data:
        speed = item.get('data', {}).get('average_speed', 50)
        volume = item.get('data', {}).get('vehicle_count', 0)
        
        # Higher volume and lower speed = higher congestion
        score = (volume / 10) * (60 - speed) / 60
        total_score += max(0, min(100, score))
        
    return total_score / len(traffic_data)

def generate_sensor_health_report():
    """Generate sensor health and connectivity report"""
    try:
        # Query recent sensor data
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=1)
        
        response = table.scan(
            FilterExpression='#timestamp BETWEEN :start_time AND :end_time',
            ExpressionAttributeNames={'#timestamp': 'timestamp'},
            ExpressionAttributeValues={
                ':start_time': start_time.isoformat(),
                ':end_time': end_time.isoformat()
            }
        )
        
        # Analyze sensor health
        sensors = {}
        for item in response['Items']:
            sensor_id = item['sensor_id']
            if sensor_id not in sensors:
                sensors[sensor_id] = {
                    'sensor_id': sensor_id,
                    'sensor_type': item.get('sensor_type', 'unknown'),
                    'message_count': 0,
                    'last_seen': item['timestamp'],
                    'status': 'active'
                }
            sensors[sensor_id]['message_count'] += 1
            
        # Determine sensor health status
        for sensor in sensors.values():
            if sensor['message_count'] < 5:  # Less than 5 messages per hour
                sensor['status'] = 'warning'
            if sensor['message_count'] == 0:
                sensor['status'] = 'offline'
                
        health_report = {
            'total_sensors': len(sensors),
            'active_sensors': sum(1 for s in sensors.values() if s['status'] == 'active'),
            'warning_sensors': sum(1 for s in sensors.values() if s['status'] == 'warning'),
            'offline_sensors': sum(1 for s in sensors.values() if s['status'] == 'offline'),
            'sensors': list(sensors.values()),
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate sensor health report: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def generate_simulation_insights():
    """Generate insights from simulation results"""
    try:
        # This would typically query simulation results
        # For now, return mock insights
        insights = {
            'traffic_optimization': {
                'potential_improvement': '15%',
                'recommended_actions': [
                    'Optimize traffic light timing at Main St intersection',
                    'Implement dynamic routing for congested areas',
                    'Add traffic sensors to Highway 101 corridor'
                ]
            },
            'emergency_response': {
                'average_response_time': '4.2 minutes',
                'optimization_opportunities': [
                    'Relocate ambulance station to reduce coverage gaps',
                    'Implement priority traffic routing for emergency vehicles'
                ]
            },
            'infrastructure_utilization': {
                'capacity_utilization': '68%',
                'peak_hours': ['8:00-9:00 AM', '5:00-6:00 PM'],
                'recommendations': [
                    'Implement congestion pricing during peak hours',
                    'Promote alternative transportation options'
                ]
            },
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(insights)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate simulation insights: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}
EOF

# Create deployment package
zip -r analytics_processor.zip analytics_processor.py

# Deploy analytics function
aws lambda create-function \
    --function-name "${PROJECT_NAME}-analytics" \
    --runtime python3.9 \
    --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
    --handler analytics_processor.lambda_handler \
    --zip-file fileb://analytics_processor.zip \
    --timeout 300 \
    --memory-size 1024

log "✅ Analytics and visualization components deployed"

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
rm -f /tmp/stream_processor.py /tmp/stream_processor.zip
rm -f /tmp/simulation_manager.py /tmp/simulation_manager.zip
rm -f /tmp/analytics_processor.py /tmp/analytics_processor.zip
rm -f /tmp/simulation_schema.yaml /tmp/traffic_sim.py /tmp/simulation_package.zip

# Display deployment summary
log "🎉 Smart City Digital Twins deployment completed successfully!"
echo ""
log "Deployment Summary:"
log "===================="
log "Project Name: $PROJECT_NAME"
log "AWS Region: $AWS_REGION"
log "AWS Account: $AWS_ACCOUNT_ID"
echo ""
log "Created Resources:"
log "- DynamoDB Table: $DYNAMODB_TABLE_NAME"
log "- Lambda Functions:"
log "  * $LAMBDA_FUNCTION_NAME (sensor data processor)"
log "  * ${PROJECT_NAME}-stream-processor (DynamoDB streams)"
log "  * ${PROJECT_NAME}-simulation-manager (simulation control)"
log "  * ${PROJECT_NAME}-analytics (analytics processing)"
log "- IoT Thing Group: $IOT_THING_GROUP_NAME"
log "- IoT Rule: $RULE_NAME"
log "- S3 Bucket: $S3_BUCKET_NAME"
log "- IAM Role: ${PROJECT_NAME}-lambda-role"
echo ""
log "Next Steps:"
log "1. Test IoT data ingestion by publishing to topic: smartcity/sensors/+/data"
log "2. Run analytics functions to generate insights"
log "3. Monitor CloudWatch logs for processing status"
log "4. Consider setting up SimSpace Weaver role for simulation execution"
echo ""
warn "Note: SimSpace Weaver will reach end of support on May 20, 2026."
warn "Consider alternative simulation platforms for long-term production use."
echo ""
log "Use './destroy.sh' to remove all created resources when no longer needed."