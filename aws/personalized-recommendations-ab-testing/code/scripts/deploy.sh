#!/bin/bash

# Deploy script for Real-Time Recommendations with Personalize and A/B Testing
# This script deploys the complete infrastructure for the recommendation system

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ERROR_LOG"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check $ERROR_LOG for details."
    log_warning "Some resources may have been created. Run destroy.sh to clean up."
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        return 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or authentication failed"
        return 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed or not in PATH"
        return 1
    fi
    
    # Check required permissions
    local test_bucket="test-permissions-$(date +%s)"
    if aws s3 mb "s3://$test_bucket" 2>/dev/null; then
        aws s3 rb "s3://$test_bucket" 2>/dev/null
        log_success "AWS permissions verified"
    else
        log_warning "Cannot verify S3 permissions. Continuing with deployment..."
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export PROJECT_NAME="personalize-ab-${RANDOM_SUFFIX}"
    export BUCKET_NAME="personalize-data-${RANDOM_SUFFIX}"
    export ROLE_NAME="PersonalizeABTestRole-${RANDOM_SUFFIX}"
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    
    # Save configuration for cleanup
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
BUCKET_NAME=${BUCKET_NAME}
ROLE_NAME=${ROLE_NAME}
ROLE_ARN=${ROLE_ARN}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment initialized with project name: $PROJECT_NAME"
}

# Create foundational resources
create_foundational_resources() {
    log_info "Creating foundational resources..."
    
    # Create S3 bucket
    if aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
        log_success "Created S3 bucket: $BUCKET_NAME"
    else
        log_error "Failed to create S3 bucket: $BUCKET_NAME"
        return 1
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "personalize.amazonaws.com",
          "lambda.amazonaws.com",
          "states.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    if aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" \
        --output table &>> "$LOG_FILE"; then
        log_success "Created IAM role: $ROLE_NAME"
    else
        log_error "Failed to create IAM role: $ROLE_NAME"
        return 1
    fi
    
    # Attach policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        if aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "$policy" &>> "$LOG_FILE"; then
            log_success "Attached policy: $(basename $policy)"
        else
            log_warning "Failed to attach policy: $policy"
        fi
    done
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 30
    
    log_success "Foundational resources created"
}

# Generate and upload sample data
generate_sample_data() {
    log_info "Generating sample training data..."
    
    mkdir -p "${SCRIPT_DIR}/sample-data"
    
    cat > "${SCRIPT_DIR}/generate_sample_data.py" << 'EOF'
import csv
import random
import uuid
from datetime import datetime, timedelta
import sys
import os

# Generate sample users
users = []
for i in range(1000):
    users.append({
        'USER_ID': f'user_{i:05d}',
        'AGE': random.randint(18, 70),
        'GENDER': random.choice(['M', 'F']),
        'SUBSCRIPTION_TYPE': random.choice(['free', 'premium', 'enterprise'])
    })

# Generate sample items
items = []
categories = ['electronics', 'books', 'clothing', 'sports', 'home', 'automotive']
for i in range(2000):
    items.append({
        'ITEM_ID': f'item_{i:05d}',
        'CATEGORY': random.choice(categories),
        'PRICE': round(random.uniform(10.0, 500.0), 2),
        'BRAND': f'brand_{random.randint(1, 50)}',
        'CREATION_DATE': (datetime.now() - timedelta(days=random.randint(1, 365))).strftime('%Y-%m-%d')
    })

# Generate sample interactions
interactions = []
base_date = datetime.now() - timedelta(days=90)

for _ in range(50000):
    user = random.choice(users)
    item = random.choice(items)
    event_type = random.choices(
        ['view', 'purchase', 'add_to_cart', 'like', 'share'],
        weights=[0.6, 0.1, 0.15, 0.1, 0.05]
    )[0]
    
    event_date = base_date + timedelta(
        days=random.randint(0, 89),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59)
    )
    
    interactions.append({
        'USER_ID': user['USER_ID'],
        'ITEM_ID': item['ITEM_ID'],
        'EVENT_TYPE': event_type,
        'TIMESTAMP': int(event_date.timestamp()),
        'EVENT_VALUE': 1.0 if event_type == 'purchase' else 0.5 if event_type == 'add_to_cart' else 0.1
    })

# Sort interactions by timestamp
interactions.sort(key=lambda x: x['TIMESTAMP'])

# Write CSV files
output_dir = sys.argv[1] if len(sys.argv) > 1 else 'sample-data'
os.makedirs(output_dir, exist_ok=True)

with open(f'{output_dir}/users.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['USER_ID', 'AGE', 'GENDER', 'SUBSCRIPTION_TYPE'])
    writer.writeheader()
    writer.writerows(users)

with open(f'{output_dir}/items.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['ITEM_ID', 'CATEGORY', 'PRICE', 'BRAND', 'CREATION_DATE'])
    writer.writeheader()
    writer.writerows(items)

with open(f'{output_dir}/interactions.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['USER_ID', 'ITEM_ID', 'EVENT_TYPE', 'TIMESTAMP', 'EVENT_VALUE'])
    writer.writeheader()
    writer.writerows(interactions)

print(f"Sample data generated successfully!")
print(f"Users: {len(users)}")
print(f"Items: {len(items)}")
print(f"Interactions: {len(interactions)}")
EOF
    
    if python3 "${SCRIPT_DIR}/generate_sample_data.py" "${SCRIPT_DIR}/sample-data"; then
        log_success "Generated sample data"
    else
        log_error "Failed to generate sample data"
        return 1
    fi
    
    # Upload to S3
    if aws s3 cp "${SCRIPT_DIR}/sample-data/" "s3://${BUCKET_NAME}/training-data/" --recursive &>> "$LOG_FILE"; then
        log_success "Uploaded sample data to S3"
    else
        log_error "Failed to upload sample data to S3"
        return 1
    fi
}

# Create DynamoDB tables
create_dynamodb_tables() {
    log_info "Creating DynamoDB tables..."
    
    local tables=(
        "${PROJECT_NAME}-users:UserId:S"
        "${PROJECT_NAME}-items:ItemId:S:Category:S"
        "${PROJECT_NAME}-ab-assignments:UserId:S:TestName:S"
        "${PROJECT_NAME}-events:UserId:S:Timestamp:N"
    )
    
    for table_spec in "${tables[@]}"; do
        IFS=':' read -ra PARTS <<< "$table_spec"
        local table_name="${PARTS[0]}"
        local hash_key="${PARTS[1]}"
        local hash_type="${PARTS[2]}"
        local range_key="${PARTS[3]:-}"
        local range_type="${PARTS[4]:-}"
        
        local key_schema="AttributeName=${hash_key},KeyType=HASH"
        local attr_def="AttributeName=${hash_key},AttributeType=${hash_type}"
        
        if [ -n "$range_key" ]; then
            key_schema="${key_schema} AttributeName=${range_key},KeyType=RANGE"
            attr_def="${attr_def} AttributeName=${range_key},AttributeType=${range_type}"
        fi
        
        local gsi_args=""
        if [ "$table_name" = "${PROJECT_NAME}-items" ]; then
            gsi_args="--global-secondary-indexes IndexName=CategoryIndex,KeySchema=[{AttributeName=Category,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}"
        fi
        
        if aws dynamodb create-table \
            --table-name "$table_name" \
            --attribute-definitions $attr_def \
            --key-schema $key_schema \
            --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10 \
            $gsi_args \
            --output table &>> "$LOG_FILE"; then
            log_success "Created DynamoDB table: $table_name"
        else
            log_warning "Table $table_name may already exist or creation failed"
        fi
    done
    
    # Wait for tables to be active
    log_info "Waiting for DynamoDB tables to become active..."
    for table_spec in "${tables[@]}"; do
        IFS=':' read -ra PARTS <<< "$table_spec"
        local table_name="${PARTS[0]}"
        aws dynamodb wait table-exists --table-name "$table_name" 2>/dev/null || true
    done
    
    log_success "DynamoDB tables are ready"
}

# Create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    # Create A/B test router
    create_ab_test_router
    
    # Create recommendation engine
    create_recommendation_engine
    
    # Create event tracker
    create_event_tracker
    
    # Create Personalize manager
    create_personalize_manager
    
    log_success "All Lambda functions created"
}

create_ab_test_router() {
    log_info "Creating A/B test router Lambda..."
    
    cat > "${SCRIPT_DIR}/ab_test_router.py" << 'EOF'
import json
import boto3
import hashlib
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    user_id = event.get('user_id')
    test_name = event.get('test_name', 'default_recommendation_test')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'user_id is required'})
        }
    
    try:
        # Get or assign A/B test variant
        variant = get_or_assign_variant(user_id, test_name)
        
        # Get recommendation model configuration for variant
        model_config = get_model_config(variant)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'user_id': user_id,
                'test_name': test_name,
                'variant': variant,
                'model_config': model_config
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_or_assign_variant(user_id, test_name):
    table = dynamodb.Table(os.environ['AB_ASSIGNMENTS_TABLE'])
    
    try:
        # Check if user already has assignment
        response = table.get_item(
            Key={'UserId': user_id, 'TestName': test_name}
        )
        
        if 'Item' in response:
            return response['Item']['Variant']
        
    except Exception:
        pass
    
    # Assign new variant using consistent hashing
    variant = assign_variant(user_id, test_name)
    
    # Store assignment
    table.put_item(
        Item={
            'UserId': user_id,
            'TestName': test_name,
            'Variant': variant,
            'AssignmentTimestamp': int(datetime.now().timestamp())
        }
    )
    
    return variant

def assign_variant(user_id, test_name):
    # Use consistent hashing for stable assignment
    hash_input = f"{user_id}-{test_name}".encode('utf-8')
    hash_value = int(hashlib.md5(hash_input).hexdigest(), 16)
    
    # Define test configuration
    test_config = {
        'default_recommendation_test': {
            'variant_a': 0.33,  # User-Personalization
            'variant_b': 0.33,  # Similar-Items
            'variant_c': 0.34   # Popularity-Count
        }
    }
    
    config = test_config.get(test_name, test_config['default_recommendation_test'])
    
    # Determine variant based on hash
    normalized_hash = (hash_value % 10000) / 10000.0
    
    cumulative = 0
    for variant, probability in config.items():
        cumulative += probability
        if normalized_hash <= cumulative:
            return variant
    
    return 'variant_a'  # Fallback

def get_model_config(variant):
    # Configuration for each variant
    configs = {
        'variant_a': {
            'recipe': 'aws-user-personalization',
            'campaign_arn': os.environ.get('CAMPAIGN_A_ARN'),
            'description': 'User-Personalization Algorithm'
        },
        'variant_b': {
            'recipe': 'aws-sims',
            'campaign_arn': os.environ.get('CAMPAIGN_B_ARN'),
            'description': 'Item-to-Item Similarity Algorithm'
        },
        'variant_c': {
            'recipe': 'aws-popularity-count',
            'campaign_arn': os.environ.get('CAMPAIGN_C_ARN'),
            'description': 'Popularity-Based Algorithm'
        }
    }
    
    return configs.get(variant, configs['variant_a'])
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip -q ab_test_router.zip ab_test_router.py
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-ab-test-router" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler ab_test_router.lambda_handler \
        --zip-file fileb://ab_test_router.zip \
        --timeout 30 \
        --environment Variables="{AB_ASSIGNMENTS_TABLE=${PROJECT_NAME}-ab-assignments}" \
        --output table &>> "$LOG_FILE"; then
        log_success "Created A/B test router Lambda"
    else
        log_error "Failed to create A/B test router Lambda"
        return 1
    fi
}

create_recommendation_engine() {
    log_info "Creating recommendation engine Lambda..."
    
    cat > "${SCRIPT_DIR}/recommendation_engine.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

personalize_runtime = boto3.client('personalize-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    user_id = event.get('user_id')
    model_config = event.get('model_config', {})
    num_results = event.get('num_results', 10)
    context_data = event.get('context', {})
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'user_id is required'})
        }
    
    try:
        # Get recommendations from Personalize
        recommendations = get_personalize_recommendations(
            user_id, model_config, num_results, context_data
        )
        
        # Enrich recommendations with item metadata
        enriched_recommendations = enrich_recommendations(recommendations)
        
        # Track recommendation request
        track_recommendation_request(user_id, model_config, enriched_recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'user_id': user_id,
                'recommendations': enriched_recommendations,
                'algorithm': model_config.get('description', 'Unknown'),
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        # Fallback to popularity-based recommendations
        fallback_recommendations = get_fallback_recommendations(num_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'user_id': user_id,
                'recommendations': fallback_recommendations,
                'algorithm': 'Fallback - Popularity Based',
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def get_personalize_recommendations(user_id, model_config, num_results, context_data):
    campaign_arn = model_config.get('campaign_arn')
    
    if not campaign_arn:
        raise ValueError("No campaign ARN provided")
    
    # Build request parameters
    request_params = {
        'campaignArn': campaign_arn,
        'userId': user_id,
        'numResults': num_results
    }
    
    # Add context if provided
    if context_data:
        request_params['context'] = context_data
    
    # Get recommendations from Personalize
    response = personalize_runtime.get_recommendations(**request_params)
    
    return response['itemList']

def enrich_recommendations(recommendations):
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    enriched = []
    for item in recommendations:
        item_id = item['itemId']
        
        try:
            # Get item metadata from DynamoDB
            response = items_table.get_item(Key={'ItemId': item_id})
            
            if 'Item' in response:
                item_data = response['Item']
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': item_data.get('Category', 'Unknown'),
                    'price': float(item_data.get('Price', 0)),
                    'brand': item_data.get('Brand', 'Unknown')
                })
            else:
                # Item not found in catalog
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': 'Unknown',
                    'price': 0,
                    'brand': 'Unknown'
                })
                
        except Exception as e:
            print(f"Error enriching item {item_id}: {str(e)}")
            enriched.append({
                'item_id': item_id,
                'score': item.get('score', 0),
                'error': str(e)
            })
    
    return enriched

def get_fallback_recommendations(num_results):
    # Simple fallback - return popular items by category
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    try:
        # Scan for items (in production, use a better method)
        response = items_table.scan(Limit=num_results)
        items = response.get('Items', [])
        
        fallback = []
        for item in items:
            fallback.append({
                'item_id': item['ItemId'],
                'score': 0.5,  # Default score for fallback
                'category': item.get('Category', 'Unknown'),
                'price': float(item.get('Price', 0)),
                'brand': item.get('Brand', 'Unknown')
            })
        
        return fallback
        
    except Exception:
        return []

def track_recommendation_request(user_id, model_config, recommendations):
    # Track recommendation serving for analytics
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    try:
        events_table.put_item(
            Item={
                'UserId': user_id,
                'Timestamp': int(datetime.now().timestamp() * 1000),
                'EventType': 'recommendation_served',
                'Algorithm': model_config.get('description', 'Unknown'),
                'ItemCount': len(recommendations),
                'Items': json.dumps([r['item_id'] for r in recommendations])
            }
        )
    except Exception as e:
        print(f"Failed to track recommendation request: {str(e)}")
EOF
    
    # Create deployment package
    zip -q recommendation_engine.zip recommendation_engine.py
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-recommendation-engine" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler recommendation_engine.lambda_handler \
        --zip-file fileb://recommendation_engine.zip \
        --timeout 30 \
        --environment Variables="{ITEMS_TABLE=${PROJECT_NAME}-items,EVENTS_TABLE=${PROJECT_NAME}-events}" \
        --output table &>> "$LOG_FILE"; then
        log_success "Created recommendation engine Lambda"
    else
        log_error "Failed to create recommendation engine Lambda"
        return 1
    fi
}

create_event_tracker() {
    log_info "Creating event tracker Lambda..."
    
    cat > "${SCRIPT_DIR}/event_tracker.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

personalize_events = boto3.client('personalize-events')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse event data
        user_id = event.get('user_id')
        session_id = event.get('session_id', user_id)
        event_type = event.get('event_type')
        item_id = event.get('item_id')
        recommendation_id = event.get('recommendation_id')
        properties = event.get('properties', {})
        
        if not all([user_id, event_type]):
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'user_id and event_type are required'})
            }
        
        # Store event in DynamoDB for analytics
        store_event_analytics(event)
        
        # Send event to Personalize (if real-time tracking is enabled)
        if os.environ.get('EVENT_TRACKER_ARN') and item_id:
            send_to_personalize(user_id, session_id, event_type, item_id, properties)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Event tracked successfully'})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def store_event_analytics(event):
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    # Store detailed event for analytics
    events_table.put_item(
        Item={
            'UserId': event['user_id'],
            'Timestamp': int(datetime.now().timestamp() * 1000),
            'EventType': event['event_type'],
            'ItemId': event.get('item_id', ''),
            'SessionId': event.get('session_id', ''),
            'RecommendationId': event.get('recommendation_id', ''),
            'Properties': json.dumps(event.get('properties', {}))
        }
    )

def send_to_personalize(user_id, session_id, event_type, item_id, properties):
    event_tracker_arn = os.environ['EVENT_TRACKER_ARN']
    
    # Prepare event for Personalize
    personalize_event = {
        'userId': user_id,
        'sessionId': session_id,
        'eventType': event_type,
        'sentAt': datetime.now().timestamp()
    }
    
    if item_id:
        personalize_event['itemId'] = item_id
    
    if properties:
        personalize_event['properties'] = json.dumps(properties)
    
    # Send to Personalize
    personalize_events.put_events(
        trackingId=event_tracker_arn.split('/')[-1],
        userId=user_id,
        sessionId=session_id,
        eventList=[personalize_event]
    )
EOF
    
    # Create deployment package
    zip -q event_tracker.zip event_tracker.py
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-event-tracker" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler event_tracker.lambda_handler \
        --zip-file fileb://event_tracker.zip \
        --timeout 30 \
        --environment Variables="{EVENTS_TABLE=${PROJECT_NAME}-events}" \
        --output table &>> "$LOG_FILE"; then
        log_success "Created event tracker Lambda"
    else
        log_error "Failed to create event tracker Lambda"
        return 1
    fi
}

create_personalize_manager() {
    log_info "Creating Personalize manager Lambda..."
    
    cat > "${SCRIPT_DIR}/personalize_manager.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

personalize = boto3.client('personalize')

def lambda_handler(event, context):
    action = event.get('action')
    
    try:
        if action == 'create_dataset_group':
            return create_dataset_group(event)
        elif action == 'import_data':
            return import_data(event)
        elif action == 'create_solution':
            return create_solution(event)
        elif action == 'create_campaign':
            return create_campaign(event)
        elif action == 'check_status':
            return check_status(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_dataset_group(event):
    dataset_group_name = event['dataset_group_name']
    
    response = personalize.create_dataset_group(
        name=dataset_group_name,
        domain='ECOMMERCE'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'dataset_group_arn': response['datasetGroupArn']
        })
    }

def import_data(event):
    dataset_arn = event['dataset_arn']
    job_name = event['job_name']
    s3_data_source = event['s3_data_source']
    role_arn = event['role_arn']
    
    response = personalize.create_dataset_import_job(
        jobName=job_name,
        datasetArn=dataset_arn,
        dataSource={
            's3DataSource': {
                'path': s3_data_source
            }
        },
        roleArn=role_arn
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'dataset_import_job_arn': response['datasetImportJobArn']
        })
    }

def create_solution(event):
    solution_name = event['solution_name']
    dataset_group_arn = event['dataset_group_arn']
    recipe_arn = event['recipe_arn']
    
    response = personalize.create_solution(
        name=solution_name,
        datasetGroupArn=dataset_group_arn,
        recipeArn=recipe_arn
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'solution_arn': response['solutionArn']
        })
    }

def create_campaign(event):
    campaign_name = event['campaign_name']
    solution_version_arn = event['solution_version_arn']
    min_provisioned_tps = event.get('min_provisioned_tps', 1)
    
    response = personalize.create_campaign(
        name=campaign_name,
        solutionVersionArn=solution_version_arn,
        minProvisionedTPS=min_provisioned_tps
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'campaign_arn': response['campaignArn']
        })
    }

def check_status(event):
    resource_arn = event['resource_arn']
    resource_type = event['resource_type']
    
    if resource_type == 'solution':
        response = personalize.describe_solution(solutionArn=resource_arn)
        status = response['solution']['status']
    elif resource_type == 'campaign':
        response = personalize.describe_campaign(campaignArn=resource_arn)
        status = response['campaign']['status']
    elif resource_type == 'dataset_import_job':
        response = personalize.describe_dataset_import_job(datasetImportJobArn=resource_arn)
        status = response['datasetImportJob']['status']
    else:
        raise ValueError(f"Unknown resource type: {resource_type}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'resource_arn': resource_arn,
            'status': status,
            'is_complete': status in ['ACTIVE', 'CREATE FAILED']
        })
    }
EOF
    
    # Create deployment package
    zip -q personalize_manager.zip personalize_manager.py
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-personalize-manager" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler personalize_manager.lambda_handler \
        --zip-file fileb://personalize_manager.zip \
        --timeout 60 \
        --output table &>> "$LOG_FILE"; then
        log_success "Created Personalize manager Lambda"
    else
        log_error "Failed to create Personalize manager Lambda"
        return 1
    fi
}

# Create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway..."
    
    # Create API Gateway
    local api_id=$(aws apigatewayv2 create-api \
        --name "${PROJECT_NAME}-recommendation-api" \
        --protocol-type HTTP \
        --description "Real-time recommendation API with A/B testing" \
        --query 'ApiId' --output text)
    
    if [ -z "$api_id" ]; then
        log_error "Failed to create API Gateway"
        return 1
    fi
    
    echo "API_ID=${api_id}" >> "${SCRIPT_DIR}/deployment_config.env"
    
    # Create integrations and routes
    create_api_routes "$api_id"
    
    # Create deployment
    if aws apigatewayv2 create-deployment \
        --api-id "$api_id" \
        --description "Initial deployment" \
        --output table &>> "$LOG_FILE"; then
        log_success "Created API Gateway deployment"
    else
        log_error "Failed to create API Gateway deployment"
        return 1
    fi
    
    # Get API endpoint
    local api_endpoint=$(aws apigatewayv2 get-api \
        --api-id "$api_id" \
        --query 'ApiEndpoint' --output text)
    
    echo "API_ENDPOINT=${api_endpoint}" >> "${SCRIPT_DIR}/deployment_config.env"
    
    log_success "API Gateway created: $api_endpoint"
}

create_api_routes() {
    local api_id="$1"
    
    # Create integration for A/B test router
    local integration1=$(aws apigatewayv2 create-integration \
        --api-id "$api_id" \
        --integration-type AWS_PROXY \
        --integration-method POST \
        --integration-uri "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-ab-test-router" \
        --payload-format-version 2.0 \
        --query 'IntegrationId' --output text)
    
    # Create integration for event tracker
    local integration2=$(aws apigatewayv2 create-integration \
        --api-id "$api_id" \
        --integration-type AWS_PROXY \
        --integration-method POST \
        --integration-uri "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-event-tracker" \
        --payload-format-version 2.0 \
        --query 'IntegrationId' --output text)
    
    # Create routes
    aws apigatewayv2 create-route \
        --api-id "$api_id" \
        --route-key "POST /recommendations" \
        --target "integrations/$integration1" \
        --output table &>> "$LOG_FILE"
    
    aws apigatewayv2 create-route \
        --api-id "$api_id" \
        --route-key "POST /events" \
        --target "integrations/$integration2" \
        --output table &>> "$LOG_FILE"
    
    # Add Lambda permissions
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-ab-test-router" \
        --statement-id api-gateway-invoke-1 \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${api_id}/*/*" \
        --output table &>> "$LOG_FILE"
    
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-event-tracker" \
        --statement-id api-gateway-invoke-2 \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${api_id}/*/*" \
        --output table &>> "$LOG_FILE"
}

# Load sample data into DynamoDB
load_sample_data() {
    log_info "Loading sample data into DynamoDB..."
    
    cat > "${SCRIPT_DIR}/load_dynamodb_data.py" << 'EOF'
import boto3
import csv
import json
import os
import sys

dynamodb = boto3.resource('dynamodb')

def load_users(project_name):
    table = dynamodb.Table(f"{project_name}-users")
    
    with open('sample-data/users.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            table.put_item(
                Item={
                    'UserId': row['USER_ID'],
                    'Age': int(row['AGE']),
                    'Gender': row['GENDER'],
                    'SubscriptionType': row['SUBSCRIPTION_TYPE']
                }
            )
    print("Loaded users data")

def load_items(project_name):
    table = dynamodb.Table(f"{project_name}-items")
    
    with open('sample-data/items.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            table.put_item(
                Item={
                    'ItemId': row['ITEM_ID'],
                    'Category': row['CATEGORY'],
                    'Price': row['PRICE'],
                    'Brand': row['BRAND'],
                    'CreationDate': row['CREATION_DATE']
                }
            )
    print("Loaded items data")

if __name__ == "__main__":
    project_name = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('PROJECT_NAME')
    if not project_name:
        print("Error: PROJECT_NAME not provided")
        sys.exit(1)
    
    load_users(project_name)
    load_items(project_name)
    print("Data loading completed")
EOF
    
    if python3 "${SCRIPT_DIR}/load_dynamodb_data.py" "$PROJECT_NAME"; then
        log_success "Loaded sample data into DynamoDB"
    else
        log_error "Failed to load sample data into DynamoDB"
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of Real-Time Recommendations with Personalize and A/B Testing"
    log_info "Deployment started at $(date)"
    
    # Initialize logging
    : > "$LOG_FILE"
    : > "$ERROR_LOG"
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_foundational_resources
    generate_sample_data
    create_dynamodb_tables
    create_lambda_functions
    create_api_gateway
    load_sample_data
    
    # Save final configuration
    log_info "Deployment completed successfully!"
    log_info "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    log_info "Next steps:"
    log_info "1. Set up Amazon Personalize datasets and models using the sample data"
    log_info "2. Update Lambda environment variables with campaign ARNs"
    log_info "3. Test the API endpoints"
    
    log_success "Deployment completed at $(date)"
}

# Run main function
main "$@"