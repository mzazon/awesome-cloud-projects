#!/bin/bash

# Deployment script for Implementing Enterprise Search with OpenSearch Service
# This script deploys a complete OpenSearch Service infrastructure with sample data

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${1:-false}
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in DRY-RUN mode - no resources will be created"
    shift
fi

# Prerequisites validation
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required tools
    for tool in jq curl zip; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS_REGION not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export DOMAIN_NAME="search-demo-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="opensearch-data-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="opensearch-indexer-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > deployment-config.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DOMAIN_NAME=$DOMAIN_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Domain Name: $DOMAIN_NAME"
    log "  S3 Bucket: $S3_BUCKET_NAME"
    log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
}

# Create S3 bucket for data storage
create_s3_bucket() {
    log "Creating S3 bucket for data storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create S3 bucket: $S3_BUCKET_NAME"
        return 0
    fi
    
    # Create S3 bucket with proper region configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://$S3_BUCKET_NAME
    else
        aws s3 mb s3://$S3_BUCKET_NAME --region $AWS_REGION
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $S3_BUCKET_NAME \
        --versioning-configuration Status=Enabled
    
    success "S3 bucket created: $S3_BUCKET_NAME"
}

# Create IAM role for OpenSearch Service
create_iam_role() {
    log "Creating IAM role for OpenSearch Service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create IAM role: OpenSearchServiceRole-${RANDOM_SUFFIX}"
        export OS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/OpenSearchServiceRole-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create trust policy
    cat > opensearch-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "opensearch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create the IAM role
    aws iam create-role \
        --role-name OpenSearchServiceRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://opensearch-trust-policy.json \
        --description "IAM role for OpenSearch Service domain"
    
    # Store role ARN
    export OS_ROLE_ARN=$(aws iam get-role \
        --role-name OpenSearchServiceRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    success "IAM role created: $OS_ROLE_ARN"
}

# Create CloudWatch log groups
create_log_groups() {
    log "Creating CloudWatch log groups for OpenSearch..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create CloudWatch log groups"
        return 0
    fi
    
    # Create log groups for OpenSearch logs
    aws logs create-log-group \
        --log-group-name /aws/opensearch/domains/${DOMAIN_NAME}/index-slow-logs \
        --region $AWS_REGION || warning "Index slow log group may already exist"
    
    aws logs create-log-group \
        --log-group-name /aws/opensearch/domains/${DOMAIN_NAME}/search-slow-logs \
        --region $AWS_REGION || warning "Search slow log group may already exist"
    
    success "CloudWatch log groups created"
}

# Create OpenSearch Service domain
create_opensearch_domain() {
    log "Creating OpenSearch Service domain (this may take 20-30 minutes)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create OpenSearch domain: $DOMAIN_NAME"
        export OS_ENDPOINT="search-${DOMAIN_NAME}-abcdef123456.${AWS_REGION}.es.amazonaws.com"
        return 0
    fi
    
    # Create domain configuration
    cat > domain-config.json << EOF
{
  "DomainName": "${DOMAIN_NAME}",
  "OpenSearchVersion": "OpenSearch_2.11",
  "ClusterConfig": {
    "InstanceType": "m6g.large.search",
    "InstanceCount": 3,
    "DedicatedMasterEnabled": true,
    "DedicatedMasterType": "m6g.medium.search",
    "DedicatedMasterCount": 3,
    "ZoneAwarenessEnabled": true,
    "ZoneAwarenessConfig": {
      "AvailabilityZoneCount": 3
    },
    "WarmEnabled": false
  },
  "EBSOptions": {
    "EBSEnabled": true,
    "VolumeType": "gp3",
    "VolumeSize": 100,
    "Iops": 3000,
    "Throughput": 125
  },
  "AccessPolicies": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"es:*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}/*\"}]}",
  "EncryptionAtRestOptions": {
    "Enabled": true
  },
  "NodeToNodeEncryptionOptions": {
    "Enabled": true
  },
  "DomainEndpointOptions": {
    "EnforceHTTPS": true,
    "TLSSecurityPolicy": "Policy-Min-TLS-1-2-2019-07"
  },
  "AdvancedSecurityOptions": {
    "Enabled": true,
    "InternalUserDatabaseEnabled": true,
    "MasterUserOptions": {
      "MasterUserName": "admin",
      "MasterUserPassword": "TempPassword123!"
    }
  },
  "LogPublishingOptions": {
    "INDEX_SLOW_LOGS": {
      "CloudWatchLogsLogGroupArn": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/opensearch/domains/${DOMAIN_NAME}/index-slow-logs",
      "Enabled": true
    },
    "SEARCH_SLOW_LOGS": {
      "CloudWatchLogsLogGroupArn": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/opensearch/domains/${DOMAIN_NAME}/search-slow-logs",
      "Enabled": true
    }
  }
}
EOF
    
    # Create the OpenSearch domain
    aws opensearch create-domain --cli-input-json file://domain-config.json
    
    log "Waiting for OpenSearch domain to be available (this may take 20-30 minutes)..."
    aws opensearch wait domain-available --domain-name $DOMAIN_NAME
    
    # Get domain endpoint
    export OS_ENDPOINT=$(aws opensearch describe-domain \
        --domain-name $DOMAIN_NAME \
        --query 'DomainStatus.Endpoint' --output text)
    
    success "OpenSearch domain created: https://$OS_ENDPOINT"
}

# Create sample data
create_sample_data() {
    log "Creating sample product data..."
    
    # Create sample product data
    cat > sample-products.json << 'EOF'
[
  {
    "id": "prod-001",
    "title": "Wireless Bluetooth Headphones",
    "description": "High-quality wireless headphones with noise cancellation and 30-hour battery life",
    "category": "Electronics",
    "brand": "TechSound",
    "price": 199.99,
    "rating": 4.5,
    "tags": ["wireless", "bluetooth", "noise-cancelling", "headphones"],
    "stock": 150,
    "created_date": "2024-01-15"
  },
  {
    "id": "prod-002", 
    "title": "Organic Cotton T-Shirt",
    "description": "Comfortable organic cotton t-shirt available in multiple colors and sizes",
    "category": "Clothing",
    "brand": "EcoWear",
    "price": 29.99,
    "rating": 4.2,
    "tags": ["organic", "cotton", "t-shirt", "eco-friendly"],
    "stock": 75,
    "created_date": "2024-01-10"
  },
  {
    "id": "prod-003",
    "title": "Smart Fitness Watch",
    "description": "Advanced fitness tracking watch with heart rate monitor and GPS",
    "category": "Electronics",
    "brand": "FitTech",
    "price": 299.99,
    "rating": 4.7,
    "tags": ["smartwatch", "fitness", "GPS", "heart-rate"],
    "stock": 89,
    "created_date": "2024-01-12"
  },
  {
    "id": "prod-004",
    "title": "Ergonomic Office Chair",
    "description": "Comfortable ergonomic office chair with lumbar support and adjustable height",
    "category": "Furniture",
    "brand": "OfficeComfort",
    "price": 449.99,
    "rating": 4.3,
    "tags": ["chair", "office", "ergonomic", "lumbar-support"],
    "stock": 32,
    "created_date": "2024-01-08"
  },
  {
    "id": "prod-005",
    "title": "Stainless Steel Water Bottle",
    "description": "Insulated stainless steel water bottle keeps drinks cold for 24 hours",
    "category": "Home & Kitchen",
    "brand": "HydroSteel",
    "price": 34.99,
    "rating": 4.6,
    "tags": ["water-bottle", "stainless-steel", "insulated", "eco-friendly"],
    "stock": 200,
    "created_date": "2024-01-05"
  }
]
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would upload sample data to S3"
        return 0
    fi
    
    # Upload sample data to S3
    aws s3 cp sample-products.json s3://$S3_BUCKET_NAME/
    
    success "Sample product data created and uploaded to S3"
}

# Create index mapping and index data
setup_opensearch_index() {
    log "Setting up OpenSearch index and mapping..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create index mapping and index data"
        return 0
    fi
    
    # Wait a bit for domain to be fully ready
    sleep 30
    
    # Create index mapping
    cat > product-mapping.json << 'EOF'
{
  "mappings": {
    "properties": {
      "id": {"type": "keyword"},
      "title": {
        "type": "text",
        "analyzer": "standard",
        "fields": {
          "keyword": {"type": "keyword"}
        }
      },
      "description": {
        "type": "text",
        "analyzer": "standard"
      },
      "category": {"type": "keyword"},
      "brand": {"type": "keyword"},
      "price": {"type": "float"},
      "rating": {"type": "float"},
      "tags": {"type": "keyword"},
      "stock": {"type": "integer"},
      "created_date": {"type": "date", "format": "yyyy-MM-dd"}
    }
  },
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "analysis": {
      "analyzer": {
        "custom_search_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop"]
        }
      }
    }
  }
}
EOF
    
    # Create the products index with mapping
    curl -X PUT "https://$OS_ENDPOINT/products" \
        -H "Content-Type: application/json" \
        -u admin:TempPassword123! \
        -d @product-mapping.json \
        --connect-timeout 30 \
        --max-time 60 \
        --silent \
        --show-error || error "Failed to create index mapping"
    
    # Index sample products
    for i in {1..5}; do
        product_data=$(jq ".[$((i-1))]" sample-products.json)
        product_id=$(echo "$product_data" | jq -r '.id')
        
        curl -X POST "https://$OS_ENDPOINT/products/_doc/$product_id" \
            -H "Content-Type: application/json" \
            -u admin:TempPassword123! \
            -d "$product_data" \
            --connect-timeout 30 \
            --max-time 60 \
            --silent \
            --show-error || warning "Failed to index product $product_id"
    done
    
    # Refresh index
    curl -X POST "https://$OS_ENDPOINT/products/_refresh" \
        -u admin:TempPassword123! \
        --silent \
        --show-error
    
    success "OpenSearch index configured and sample data indexed"
}

# Create Lambda function for automated indexing
create_lambda_function() {
    log "Creating Lambda function for automated indexing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > lambda-indexer.py << 'EOF'
import json
import boto3
import requests
from requests.auth import HTTPBasicAuth
import os

def lambda_handler(event, context):
    # OpenSearch endpoint from environment variable
    os_endpoint = os.environ['OPENSEARCH_ENDPOINT']
    
    # Process S3 event (if triggered by S3)
    if 'Records' in event:
        s3_client = boto3.client('s3')
        
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Download file from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')
            
            # Parse JSON data
            products = json.loads(content)
            
            # Index each product
            for product in products:
                doc_id = product['id']
                index_url = f"https://{os_endpoint}/products/_doc/{doc_id}"
                
                response = requests.put(
                    index_url,
                    headers={'Content-Type': 'application/json'},
                    data=json.dumps(product)
                )
                
                print(f"Indexed product {doc_id}: {response.status_code}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Data indexing completed successfully')
    }
EOF
    
    # Create deployment package
    zip lambda-indexer.zip lambda-indexer.py
    
    # Create Lambda execution role
    cat > lambda-trust-policy.json << 'EOF'
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
        --role-name LambdaOpenSearchRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "IAM role for Lambda function to index data in OpenSearch"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name LambdaOpenSearchRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name LambdaOpenSearchRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --runtime python3.9 \
        --role $LAMBDA_ROLE_ARN \
        --handler lambda-indexer.lambda_handler \
        --zip-file fileb://lambda-indexer.zip \
        --environment Variables="{OPENSEARCH_ENDPOINT=$OS_ENDPOINT}" \
        --timeout 60 \
        --description "Automated indexing function for OpenSearch"
    
    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Create monitoring dashboard
create_monitoring() {
    log "Creating CloudWatch monitoring dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create monitoring dashboard and alarms"
        return 0
    fi
    
    # Create CloudWatch dashboard
    cat > cloudwatch-dashboard.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ES", "SearchLatency", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "IndexingLatency", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "SearchRate", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "IndexingRate", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "OpenSearch Performance Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ES", "ClusterStatus.yellow", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "ClusterStatus.red", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "StorageUtilization", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"],
          ["AWS/ES", "CPUUtilization", "DomainName", "${DOMAIN_NAME}", "ClientId", "${AWS_ACCOUNT_ID}"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "OpenSearch Cluster Health"
      }
    }
  ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "OpenSearch-${DOMAIN_NAME}-Dashboard" \
        --dashboard-body file://cloudwatch-dashboard.json
    
    # Create CloudWatch alarm for high search latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "OpenSearch-High-Search-Latency-${DOMAIN_NAME}" \
        --alarm-description "Alert when search latency exceeds 1000ms" \
        --metric-name SearchLatency \
        --namespace AWS/ES \
        --statistic Average \
        --period 300 \
        --threshold 1000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DomainName,Value=${DOMAIN_NAME} Name=ClientId,Value=${AWS_ACCOUNT_ID}
    
    success "Monitoring dashboard and alarms created"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f opensearch-trust-policy.json lambda-trust-policy.json
    rm -f domain-config.json product-mapping.json
    rm -f sample-products.json lambda-indexer.py lambda-indexer.zip
    rm -f cloudwatch-dashboard.json
    success "Temporary files cleaned up"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary:"
    log "=================="
    log "OpenSearch Domain: $DOMAIN_NAME"
    log "OpenSearch Endpoint: https://$OS_ENDPOINT"
    log "S3 Bucket: $S3_BUCKET_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "Region: $AWS_REGION"
    log ""
    log "Access Information:"
    log "- OpenSearch Dashboards: https://$OS_ENDPOINT/_dashboards"
    log "- Username: admin"
    log "- Password: TempPassword123!"
    log ""
    warning "Remember to change the default password after deployment!"
    log ""
    log "Test search functionality:"
    log "curl -X GET \"https://$OS_ENDPOINT/products/_search\" -u admin:TempPassword123!"
    log ""
    log "Configuration saved to: deployment-config.env"
    log "Use ./destroy.sh to clean up all resources"
}

# Main deployment function
main() {
    log "Starting OpenSearch Service deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    create_log_groups
    create_opensearch_domain
    create_sample_data
    setup_opensearch_index
    create_lambda_function
    create_monitoring
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    print_summary
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."; exit 1' INT TERM

# Run main function
main "$@"