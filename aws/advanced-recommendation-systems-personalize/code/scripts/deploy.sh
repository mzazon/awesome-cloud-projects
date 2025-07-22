#!/bin/bash

# Deploy script for Building Advanced Recommendation Systems with Amazon Personalize
# This script deploys the complete recommendation system infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check Python3
    if ! command -v python3 &> /dev/null; then
        error "Python3 is not installed. Please install Python 3.7 or later."
    fi
    
    # Check zip command
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install zip utility."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export BUCKET_NAME="personalize-comprehensive-${RANDOM_SUFFIX}"
    export DATASET_GROUP_NAME="ecommerce-recommendation-${RANDOM_SUFFIX}"
    export USER_PERSONALIZATION_SOLUTION="user-personalization-${RANDOM_SUFFIX}"
    export SIMILAR_ITEMS_SOLUTION="similar-items-${RANDOM_SUFFIX}"
    export TRENDING_NOW_SOLUTION="trending-now-${RANDOM_SUFFIX}"
    export POPULARITY_SOLUTION="popularity-count-${RANDOM_SUFFIX}"
    
    # Save environment variables for later use
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
BUCKET_NAME=${BUCKET_NAME}
DATASET_GROUP_NAME=${DATASET_GROUP_NAME}
USER_PERSONALIZATION_SOLUTION=${USER_PERSONALIZATION_SOLUTION}
SIMILAR_ITEMS_SOLUTION=${SIMILAR_ITEMS_SOLUTION}
TRENDING_NOW_SOLUTION=${TRENDING_NOW_SOLUTION}
POPULARITY_SOLUTION=${POPULARITY_SOLUTION}
EOF
    
    success "Environment variables configured"
    log "Resources will be created with suffix: ${RANDOM_SUFFIX}"
}

# Create S3 bucket and directory structure
create_s3_infrastructure() {
    log "Creating S3 infrastructure..."
    
    # Create S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        success "Created S3 bucket: ${BUCKET_NAME}"
    else
        warning "S3 bucket ${BUCKET_NAME} already exists"
    fi
    
    # Create directory structure in S3
    aws s3api put-object --bucket "${BUCKET_NAME}" --key training-data/ --body /dev/null
    aws s3api put-object --bucket "${BUCKET_NAME}" --key batch-output/ --body /dev/null
    aws s3api put-object --bucket "${BUCKET_NAME}" --key metadata/ --body /dev/null
    aws s3api put-object --bucket "${BUCKET_NAME}" --key batch-input/ --body /dev/null
    
    success "S3 directory structure created"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Personalize service role trust policy
    cat > personalize-service-role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "personalize.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for Personalize service
    if ! aws iam get-role --role-name "PersonalizeServiceRole-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-role \
            --role-name "PersonalizeServiceRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://personalize-service-role-policy.json
        success "Created Personalize service role"
    else
        warning "Personalize service role already exists"
    fi
    
    # Create custom policy for S3 access
    cat > personalize-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    
    # Create and attach custom policy
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PersonalizeS3Access-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-policy \
            --policy-name "PersonalizeS3Access-${RANDOM_SUFFIX}" \
            --policy-document file://personalize-s3-policy.json
        success "Created Personalize S3 access policy"
    else
        warning "Personalize S3 access policy already exists"
    fi
    
    aws iam attach-role-policy \
        --role-name "PersonalizeServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PersonalizeS3Access-${RANDOM_SUFFIX}" || true
    
    export PERSONALIZE_ROLE_ARN=$(aws iam get-role \
        --role-name "PersonalizeServiceRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    echo "PERSONALIZE_ROLE_ARN=${PERSONALIZE_ROLE_ARN}" >> .env
    
    success "IAM roles configured"
}

# Generate training datasets
generate_training_data() {
    log "Generating comprehensive training datasets..."
    
    # Generate realistic user interaction data
    cat > generate_sample_data.py << 'EOF'
import csv
import random
import time
from datetime import datetime, timedelta

# Generate user interactions
users = [f"user_{i:04d}" for i in range(1, 501)]  # 500 users
items = [f"item_{i:04d}" for i in range(1, 1001)]  # 1000 items
categories = ["electronics", "clothing", "books", "sports", "home", "beauty"]

# Generate interactions dataset
interactions = []
base_timestamp = int((datetime.now() - timedelta(days=90)).timestamp())

for _ in range(25000):  # 25,000 interactions
    user = random.choice(users)
    item = random.choice(items)
    event_type = random.choices(
        ["view", "purchase", "add_to_cart", "like"], 
        weights=[60, 10, 20, 10]
    )[0]
    timestamp = base_timestamp + random.randint(0, 90*24*3600)
    
    interactions.append({
        "USER_ID": user,
        "ITEM_ID": item,
        "TIMESTAMP": timestamp,
        "EVENT_TYPE": event_type,
        "EVENT_VALUE": 1 if event_type == "view" else 
                      5 if event_type == "purchase" else 
                      2 if event_type == "add_to_cart" else 3
    })

# Write interactions CSV
with open("interactions.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["USER_ID", "ITEM_ID", "TIMESTAMP", "EVENT_TYPE", "EVENT_VALUE"])
    writer.writeheader()
    writer.writerows(interactions)

# Generate items metadata
items_metadata = []
for item in items:
    items_metadata.append({
        "ITEM_ID": item,
        "CATEGORY": random.choice(categories),
        "PRICE": round(random.uniform(10, 500), 2),
        "BRAND": f"Brand_{random.randint(1, 50)}",
        "CREATION_TIMESTAMP": base_timestamp + random.randint(0, 30*24*3600)
    })

# Write items CSV
with open("items.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["ITEM_ID", "CATEGORY", "PRICE", "BRAND", "CREATION_TIMESTAMP"])
    writer.writeheader()
    writer.writerows(items_metadata)

# Generate users metadata
users_metadata = []
for user in users:
    users_metadata.append({
        "USER_ID": user,
        "AGE": random.randint(18, 65),
        "GENDER": random.choice(["M", "F"]),
        "MEMBERSHIP_TYPE": random.choice(["free", "premium", "enterprise"])
    })

# Write users CSV
with open("users.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["USER_ID", "AGE", "GENDER", "MEMBERSHIP_TYPE"])
    writer.writeheader()
    writer.writerows(users_metadata)

print("Generated sample datasets successfully!")
EOF
    
    # Run data generation script
    python3 generate_sample_data.py
    
    # Upload datasets to S3
    aws s3 cp interactions.csv "s3://${BUCKET_NAME}/training-data/"
    aws s3 cp items.csv "s3://${BUCKET_NAME}/metadata/"
    aws s3 cp users.csv "s3://${BUCKET_NAME}/metadata/"
    
    # Create batch input sample
    cat > batch-input.json << EOF
{"userId": "user_0001"}
{"userId": "user_0002"}
{"userId": "user_0003"}
{"userId": "user_0004"}
{"userId": "user_0005"}
EOF
    
    aws s3 cp batch-input.json "s3://${BUCKET_NAME}/batch-input/users-batch.json"
    
    success "Training datasets generated and uploaded"
}

# Create Personalize infrastructure
create_personalize_infrastructure() {
    log "Creating Amazon Personalize infrastructure..."
    
    # Create dataset group
    if ! aws personalize describe-dataset-group --dataset-group-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}" &> /dev/null; then
        aws personalize create-dataset-group \
            --name "${DATASET_GROUP_NAME}" \
            --region "${AWS_REGION}"
        
        log "Waiting for dataset group to be active..."
        aws personalize wait dataset-group-active \
            --dataset-group-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}"
        
        success "Dataset group created and active"
    else
        warning "Dataset group already exists"
    fi
    
    export DATASET_GROUP_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-group/${DATASET_GROUP_NAME}"
    echo "DATASET_GROUP_ARN=${DATASET_GROUP_ARN}" >> .env
}

# Create schemas
create_schemas() {
    log "Creating Personalize schemas..."
    
    # Create interactions schema
    cat > interactions-schema.json << EOF
{
    "type": "record",
    "name": "Interactions",
    "namespace": "com.amazonaws.personalize.schema",
    "fields": [
        {"name": "USER_ID", "type": "string"},
        {"name": "ITEM_ID", "type": "string"},
        {"name": "TIMESTAMP", "type": "long"},
        {"name": "EVENT_TYPE", "type": "string"},
        {"name": "EVENT_VALUE", "type": "float"}
    ],
    "version": "1.0"
}
EOF
    
    # Create items schema
    cat > items-schema.json << EOF
{
    "type": "record",
    "name": "Items",
    "namespace": "com.amazonaws.personalize.schema",
    "fields": [
        {"name": "ITEM_ID", "type": "string"},
        {"name": "CATEGORY", "type": "string", "categorical": true},
        {"name": "PRICE", "type": "float"},
        {"name": "BRAND", "type": "string", "categorical": true},
        {"name": "CREATION_TIMESTAMP", "type": "long"}
    ],
    "version": "1.0"
}
EOF
    
    # Create users schema
    cat > users-schema.json << EOF
{
    "type": "record",
    "name": "Users",
    "namespace": "com.amazonaws.personalize.schema",
    "fields": [
        {"name": "USER_ID", "type": "string"},
        {"name": "AGE", "type": "int"},
        {"name": "GENDER", "type": "string", "categorical": true},
        {"name": "MEMBERSHIP_TYPE", "type": "string", "categorical": true}
    ],
    "version": "1.0"
}
EOF
    
    # Create schemas
    for schema_type in interactions items users; do
        schema_name="${schema_type}-schema-${RANDOM_SUFFIX}"
        if ! aws personalize describe-schema --schema-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/${schema_name}" &> /dev/null; then
            aws personalize create-schema \
                --name "${schema_name}" \
                --schema file://${schema_type}-schema.json
            success "Created ${schema_type} schema"
        else
            warning "${schema_type} schema already exists"
        fi
    done
    
    export INTERACTIONS_SCHEMA_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/interactions-schema-${RANDOM_SUFFIX}"
    export ITEMS_SCHEMA_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/items-schema-${RANDOM_SUFFIX}"
    export USERS_SCHEMA_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:schema/users-schema-${RANDOM_SUFFIX}"
    
    echo "INTERACTIONS_SCHEMA_ARN=${INTERACTIONS_SCHEMA_ARN}" >> .env
    echo "ITEMS_SCHEMA_ARN=${ITEMS_SCHEMA_ARN}" >> .env
    echo "USERS_SCHEMA_ARN=${USERS_SCHEMA_ARN}" >> .env
}

# Create datasets and import data
create_datasets_and_import() {
    log "Creating datasets and importing data..."
    
    # Create datasets
    for dataset_type in Interactions Items Users; do
        dataset_name="${dataset_type,,}-dataset-${RANDOM_SUFFIX}"
        if [ "$dataset_type" = "Interactions" ]; then
            schema_arn="$INTERACTIONS_SCHEMA_ARN"
        elif [ "$dataset_type" = "Items" ]; then
            schema_arn="$ITEMS_SCHEMA_ARN"
        else
            schema_arn="$USERS_SCHEMA_ARN"
        fi
        
        if ! aws personalize describe-dataset --dataset-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/${dataset_type^^}" &> /dev/null; then
            aws personalize create-dataset \
                --name "${dataset_name}" \
                --dataset-group-arn "${DATASET_GROUP_ARN}" \
                --dataset-type "${dataset_type}" \
                --schema-arn "${schema_arn}"
            success "Created ${dataset_type} dataset"
        else
            warning "${dataset_type} dataset already exists"
        fi
    done
    
    # Set dataset ARNs
    export INTERACTIONS_DATASET_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/INTERACTIONS"
    export ITEMS_DATASET_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/ITEMS"
    export USERS_DATASET_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_GROUP_NAME}/USERS"
    
    echo "INTERACTIONS_DATASET_ARN=${INTERACTIONS_DATASET_ARN}" >> .env
    echo "ITEMS_DATASET_ARN=${ITEMS_DATASET_ARN}" >> .env
    echo "USERS_DATASET_ARN=${USERS_DATASET_ARN}" >> .env
    
    # Import data
    log "Starting data import jobs..."
    
    # Import interactions data
    aws personalize create-dataset-import-job \
        --job-name "import-interactions-${RANDOM_SUFFIX}" \
        --dataset-arn "${INTERACTIONS_DATASET_ARN}" \
        --data-source "dataLocation=s3://${BUCKET_NAME}/training-data/interactions.csv" \
        --role-arn "${PERSONALIZE_ROLE_ARN}" || warning "Interactions import job might already exist"
    
    # Import items data
    aws personalize create-dataset-import-job \
        --job-name "import-items-${RANDOM_SUFFIX}" \
        --dataset-arn "${ITEMS_DATASET_ARN}" \
        --data-source "dataLocation=s3://${BUCKET_NAME}/metadata/items.csv" \
        --role-arn "${PERSONALIZE_ROLE_ARN}" || warning "Items import job might already exist"
    
    # Import users data
    aws personalize create-dataset-import-job \
        --job-name "import-users-${RANDOM_SUFFIX}" \
        --dataset-arn "${USERS_DATASET_ARN}" \
        --data-source "dataLocation=s3://${BUCKET_NAME}/metadata/users.csv" \
        --role-arn "${PERSONALIZE_ROLE_ARN}" || warning "Users import job might already exist"
    
    success "Dataset import jobs created - this will take 15-20 minutes"
}

# Create solutions (ML models)
create_solutions() {
    log "Creating ML solutions..."
    
    # Wait for dataset imports to complete
    log "Waiting for dataset imports to complete..."
    
    # Function to wait for import job completion
    wait_for_import_job() {
        local job_name=$1
        local dataset_arn=$2
        log "Waiting for import job: ${job_name}"
        
        while true; do
            status=$(aws personalize describe-dataset-import-job \
                --dataset-import-job-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset-import-job/${job_name}" \
                --query DatasetImportJob.Status --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$status" = "ACTIVE" ]; then
                success "Import job ${job_name} completed"
                break
            elif [ "$status" = "CREATE_FAILED" ]; then
                error "Import job ${job_name} failed"
            elif [ "$status" = "NOT_FOUND" ]; then
                warning "Import job ${job_name} not found, assuming completed"
                break
            fi
            
            log "Import job status: $status - waiting 2 minutes..."
            sleep 120
        done
    }
    
    # Wait for all import jobs
    wait_for_import_job "import-interactions-${RANDOM_SUFFIX}" "${INTERACTIONS_DATASET_ARN}"
    wait_for_import_job "import-items-${RANDOM_SUFFIX}" "${ITEMS_DATASET_ARN}"
    wait_for_import_job "import-users-${RANDOM_SUFFIX}" "${USERS_DATASET_ARN}"
    
    # Create solutions
    log "Creating recommendation solutions..."
    
    # User-Personalization solution
    if ! aws personalize describe-solution --solution-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${USER_PERSONALIZATION_SOLUTION}" &> /dev/null; then
        aws personalize create-solution \
            --name "${USER_PERSONALIZATION_SOLUTION}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --recipe-arn "arn:aws:personalize:::recipe/aws-user-personalization" \
            --solution-config '{
                "algorithmHyperParameters": {
                    "hidden_dimension": "100",
                    "bptt": "32",
                    "recency_mask": "true"
                },
                "featureTransformationParameters": {
                    "max_hist_len": "100"
                }
            }'
        success "Created User-Personalization solution"
    else
        warning "User-Personalization solution already exists"
    fi
    
    # Similar-Items solution
    if ! aws personalize describe-solution --solution-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${SIMILAR_ITEMS_SOLUTION}" &> /dev/null; then
        aws personalize create-solution \
            --name "${SIMILAR_ITEMS_SOLUTION}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --recipe-arn "arn:aws:personalize:::recipe/aws-similar-items"
        success "Created Similar-Items solution"
    else
        warning "Similar-Items solution already exists"
    fi
    
    # Trending-Now solution
    if ! aws personalize describe-solution --solution-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${TRENDING_NOW_SOLUTION}" &> /dev/null; then
        aws personalize create-solution \
            --name "${TRENDING_NOW_SOLUTION}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --recipe-arn "arn:aws:personalize:::recipe/aws-trending-now"
        success "Created Trending-Now solution"
    else
        warning "Trending-Now solution already exists"
    fi
    
    # Popularity-Count solution
    if ! aws personalize describe-solution --solution-arn "arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${POPULARITY_SOLUTION}" &> /dev/null; then
        aws personalize create-solution \
            --name "${POPULARITY_SOLUTION}" \
            --dataset-group-arn "${DATASET_GROUP_ARN}" \
            --recipe-arn "arn:aws:personalize:::recipe/aws-popularity-count"
        success "Created Popularity-Count solution"
    else
        warning "Popularity-Count solution already exists"
    fi
    
    # Store solution ARNs
    export USER_PERSONALIZATION_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${USER_PERSONALIZATION_SOLUTION}"
    export SIMILAR_ITEMS_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${SIMILAR_ITEMS_SOLUTION}"
    export TRENDING_NOW_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${TRENDING_NOW_SOLUTION}"
    export POPULARITY_ARN="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${POPULARITY_SOLUTION}"
    
    echo "USER_PERSONALIZATION_ARN=${USER_PERSONALIZATION_ARN}" >> .env
    echo "SIMILAR_ITEMS_ARN=${SIMILAR_ITEMS_ARN}" >> .env
    echo "TRENDING_NOW_ARN=${TRENDING_NOW_ARN}" >> .env
    echo "POPULARITY_ARN=${POPULARITY_ARN}" >> .env
}

# Train solution versions
train_models() {
    log "Training solution versions (models)..."
    
    # Train all solutions
    for solution_name in "${USER_PERSONALIZATION_SOLUTION}" "${SIMILAR_ITEMS_SOLUTION}" "${TRENDING_NOW_SOLUTION}" "${POPULARITY_SOLUTION}"; do
        solution_arn="arn:aws:personalize:${AWS_REGION}:${AWS_ACCOUNT_ID}:solution/${solution_name}"
        
        aws personalize create-solution-version \
            --solution-arn "${solution_arn}" \
            --training-mode FULL || warning "Solution version for ${solution_name} might already exist"
    done
    
    success "Model training initiated - this will take 60-90 minutes"
    log "You can monitor training progress in the AWS Personalize console"
    log "The script will continue with other deployments that don't require trained models"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create Lambda execution role
    cat > lambda-execution-role-policy.json << EOF
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
    
    if ! aws iam get-role --role-name "LambdaRecommendationRole-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-role \
            --role-name "LambdaRecommendationRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://lambda-execution-role-policy.json
        success "Created Lambda execution role"
    else
        warning "Lambda execution role already exists"
    fi
    
    # Create custom policy for Lambda permissions
    cat > lambda-personalize-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "personalize:GetRecommendations",
                "personalize:GetPersonalizedRanking",
                "personalize:DescribeCampaign",
                "personalize:DescribeFilter"
            ],
            "Resource": "*"
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
    
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaPersonalizePolicy-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-policy \
            --policy-name "LambdaPersonalizePolicy-${RANDOM_SUFFIX}" \
            --policy-document file://lambda-personalize-policy.json
        success "Created Lambda Personalize policy"
    else
        warning "Lambda Personalize policy already exists"
    fi
    
    # Attach policies to role
    aws iam attach-role-policy \
        --role-name "LambdaRecommendationRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || true
    
    aws iam attach-role-policy \
        --role-name "LambdaRecommendationRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaPersonalizePolicy-${RANDOM_SUFFIX}" || true
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "LambdaRecommendationRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .env
    
    success "Lambda IAM configuration completed"
    
    # Note: Lambda function creation will be completed after campaigns are created
    log "Lambda function will be created after campaigns are ready"
}

# Cleanup function
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f *.json *.py *.csv generate_sample_data.py
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Recommendation Systems with Amazon Personalize"
    log "Estimated deployment time: 60-90 minutes for complete setup"
    
    check_prerequisites
    setup_environment
    create_s3_infrastructure
    create_iam_roles
    generate_training_data
    create_personalize_infrastructure
    create_schemas
    create_datasets_and_import
    create_solutions
    train_models
    create_lambda_functions
    
    success "Deployment Phase 1 completed successfully!"
    
    cat << EOF

🎉 Phase 1 Deployment Complete!

The following resources have been created:
- S3 Bucket: ${BUCKET_NAME}
- Dataset Group: ${DATASET_GROUP_NAME}
- Schemas and Datasets for interactions, items, and users
- ML Solutions for User-Personalization, Similar-Items, Trending-Now, and Popularity
- IAM Roles for Personalize and Lambda
- Training data uploaded and import jobs started

⏳ Next Steps:
1. Model training is in progress (60-90 minutes)
2. After training completes, run the following commands to complete deployment:
   
   # Check training status
   aws personalize describe-solution-version --solution-version-arn <solution-version-arn>
   
   # Create campaigns (after training completes)
   # Create filters
   # Deploy Lambda functions
   # Set up EventBridge automation

📋 Environment file saved as .env with all resource identifiers
📊 Monitor training progress in AWS Personalize console: https://console.aws.amazon.com/personalize/

💰 Estimated ongoing costs:
- Campaigns: ~\$50-100/month per campaign
- Storage: ~\$5-10/month
- Lambda: Pay per request
- Training: One-time cost per training session

EOF
    
    cleanup_temp_files
}

# Handle script interruption
trap 'error "Deployment interrupted. Check AWS console for created resources."' INT TERM

# Run main function
main "$@"