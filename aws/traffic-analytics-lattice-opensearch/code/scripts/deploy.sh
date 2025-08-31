#!/bin/bash

# Traffic Analytics with VPC Lattice and OpenSearch - Deployment Script
# This script deploys the complete infrastructure for traffic analytics solution
# Recipe: traffic-analytics-lattice-opensearch

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required AWS permissions (basic check)
    log_info "Verifying AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query 'Arn' --output text | grep -q 'assumed-role'; then
        log_warning "Could not verify IAM permissions. Proceeding with deployment..."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set AWS region."
        exit 1
    fi
    log_info "Using AWS region: $AWS_REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export OPENSEARCH_DOMAIN_NAME="traffic-analytics-${RANDOM_SUFFIX}"
    export FIREHOSE_DELIVERY_STREAM="vpc-lattice-stream-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="traffic-transform-${RANDOM_SUFFIX}"
    export S3_BACKUP_BUCKET="vpc-lattice-backup-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="demo-network-${RANDOM_SUFFIX}"
    
    # Create deployment info file for cleanup reference
    cat > deployment_info.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "opensearch_domain_name": "$OPENSEARCH_DOMAIN_NAME",
    "firehose_delivery_stream": "$FIREHOSE_DELIVERY_STREAM",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "s3_backup_bucket": "$S3_BACKUP_BUCKET",
    "service_network_name": "$SERVICE_NETWORK_NAME"
}
EOF
    
    log_success "Environment variables configured"
}

# Function to create S3 backup bucket
create_s3_bucket() {
    log_info "Creating S3 backup bucket: $S3_BACKUP_BUCKET"
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BACKUP_BUCKET}" &> /dev/null; then
        log_warning "S3 bucket $S3_BACKUP_BUCKET already exists"
        return 0
    fi
    
    # Create bucket with appropriate region handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${S3_BACKUP_BUCKET}"
    else
        aws s3 mb "s3://${S3_BACKUP_BUCKET}" --region "$AWS_REGION"
    fi
    
    # Enable versioning for backup protection
    aws s3api put-bucket-versioning \
        --bucket "$S3_BACKUP_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$S3_BACKUP_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    log_success "S3 backup bucket created and configured"
}

# Function to create OpenSearch domain
create_opensearch_domain() {
    log_info "Creating OpenSearch Service domain: $OPENSEARCH_DOMAIN_NAME"
    
    # Check if domain already exists
    if aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN_NAME" &> /dev/null; then
        log_warning "OpenSearch domain $OPENSEARCH_DOMAIN_NAME already exists"
        return 0
    fi
    
    # Create OpenSearch domain
    aws opensearch create-domain \
        --domain-name "$OPENSEARCH_DOMAIN_NAME" \
        --engine-version "OpenSearch_2.11" \
        --cluster-config \
        InstanceType=t3.small.search,InstanceCount=1,DedicatedMasterEnabled=false \
        --ebs-options EBSEnabled=true,VolumeType=gp3,VolumeSize=20 \
        --access-policies "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"AWS\": \"*\"
                    },
                    \"Action\": \"es:*\",
                    \"Resource\": \"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN_NAME}/*\"
                }
            ]
        }" \
        --domain-endpoint-options EnforceHTTPS=true \
        --node-to-node-encryption-options Enabled=true \
        --encryption-at-rest-options Enabled=true
    
    log_info "OpenSearch domain creation initiated. This will take 10-15 minutes..."
    
    # Wait for domain to be available
    log_info "Waiting for OpenSearch domain to become available..."
    aws opensearch wait domain-available --domain-name "$OPENSEARCH_DOMAIN_NAME"
    
    # Get the domain endpoint
    export OPENSEARCH_ENDPOINT=$(aws opensearch describe-domain \
        --domain-name "$OPENSEARCH_DOMAIN_NAME" \
        --query 'DomainStatus.Endpoint' --output text)
    
    # Update deployment info with endpoint
    jq ".opensearch_endpoint = \"$OPENSEARCH_ENDPOINT\"" deployment_info.json > temp.json && mv temp.json deployment_info.json
    
    log_success "OpenSearch domain created at: https://$OPENSEARCH_ENDPOINT"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda transformation function: $LAMBDA_FUNCTION_NAME"
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists"
        return 0
    fi
    
    # Create Lambda execution role
    log_info "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if ! aws iam get-role --role-name "vpc-lattice-transform-role-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-role \
            --role-name "vpc-lattice-transform-role-${RANDOM_SUFFIX}" \
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
            }'
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "vpc-lattice-transform-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Wait for IAM role to propagate
        log_info "Waiting for IAM role to propagate..."
        sleep 15
    fi
    
    # Create Lambda function code
    log_info "Creating Lambda function code..."
    cat > transform_function.py << 'EOF'
import json
import base64
import gzip
import datetime

def lambda_handler(event, context):
    output = []
    
    for record in event['records']:
        try:
            # Decode and decompress the data
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Transform and enrich each log entry
            for log_entry in log_data.get('logEvents', []):
                try:
                    # Parse the log message if it's JSON
                    if log_entry['message'].startswith('{'):
                        parsed_log = json.loads(log_entry['message'])
                        
                        # Add timestamp and enrichment fields
                        parsed_log['@timestamp'] = datetime.datetime.fromtimestamp(
                            log_entry['timestamp'] / 1000
                        ).isoformat()
                        parsed_log['log_group'] = log_data.get('logGroup', '')
                        parsed_log['log_stream'] = log_data.get('logStream', '')
                        
                        # Add derived fields for analytics
                        if 'responseCode' in parsed_log:
                            parsed_log['response_class'] = str(parsed_log['responseCode'])[0] + 'xx'
                            parsed_log['is_error'] = parsed_log['responseCode'] >= 400
                        
                        if 'responseTimeMs' in parsed_log:
                            parsed_log['response_time_bucket'] = categorize_response_time(
                                parsed_log['responseTimeMs']
                            )
                        
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(parsed_log) + '\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    else:
                        # If not JSON, pass through with minimal processing
                        enhanced_log = {
                            'message': log_entry['message'],
                            '@timestamp': datetime.datetime.fromtimestamp(
                                log_entry['timestamp'] / 1000
                            ).isoformat(),
                            'log_group': log_data.get('logGroup', ''),
                            'log_stream': log_data.get('logStream', '')
                        }
                        
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(enhanced_log) + '\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    
                    output.append(output_record)
                    
                except Exception as e:
                    # If processing fails, mark as processing failure
                    output.append({
                        'recordId': record['recordId'],
                        'result': 'ProcessingFailed'
                    })
        except Exception as e:
            # If record processing fails completely
            output.append({
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            })
    
    return {'records': output}

def categorize_response_time(response_time_ms):
    """Categorize response times for analytics"""
    if response_time_ms < 100:
        return 'fast'
    elif response_time_ms < 500:
        return 'medium'
    elif response_time_ms < 2000:
        return 'slow'
    else:
        return 'very_slow'
EOF
    
    # Package the Lambda function
    zip transform_function.zip transform_function.py
    
    # Create the Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vpc-lattice-transform-role-${RANDOM_SUFFIX}" \
        --handler transform_function.lambda_handler \
        --zip-file fileb://transform_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --description "Transform VPC Lattice access logs for OpenSearch analytics"
    
    # Clean up local files
    rm -f transform_function.py transform_function.zip
    
    log_success "Lambda transformation function created"
}

# Function to create Kinesis Data Firehose
create_firehose_stream() {
    log_info "Creating Kinesis Data Firehose delivery stream: $FIREHOSE_DELIVERY_STREAM"
    
    # Check if delivery stream already exists
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" &> /dev/null; then
        log_warning "Firehose delivery stream $FIREHOSE_DELIVERY_STREAM already exists"
        return 0
    fi
    
    # Create IAM role for Firehose
    log_info "Creating IAM role for Firehose..."
    
    if ! aws iam get-role --role-name "firehose-opensearch-role-${RANDOM_SUFFIX}" &> /dev/null; then
        aws iam create-role \
            --role-name "firehose-opensearch-role-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "firehose.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
        
        # Create policy for Firehose to write to OpenSearch and S3
        aws iam put-role-policy \
            --role-name "firehose-opensearch-role-${RANDOM_SUFFIX}" \
            --policy-name FirehoseOpenSearchPolicy \
            --policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [
                    {
                        \"Effect\": \"Allow\",
                        \"Action\": [
                            \"es:DescribeDomain\",
                            \"es:DescribeDomains\",
                            \"es:DescribeDomainConfig\",
                            \"es:ESHttpPost\",
                            \"es:ESHttpPut\"
                        ],
                        \"Resource\": \"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN_NAME}/*\"
                    },
                    {
                        \"Effect\": \"Allow\",
                        \"Action\": [
                            \"s3:AbortMultipartUpload\",
                            \"s3:GetBucketLocation\",
                            \"s3:GetObject\",
                            \"s3:ListBucket\",
                            \"s3:ListBucketMultipartUploads\",
                            \"s3:PutObject\"
                        ],
                        \"Resource\": [
                            \"arn:aws:s3:::${S3_BACKUP_BUCKET}\",
                            \"arn:aws:s3:::${S3_BACKUP_BUCKET}/*\"
                        ]
                    },
                    {
                        \"Effect\": \"Allow\",
                        \"Action\": [
                            \"lambda:InvokeFunction\",
                            \"lambda:GetFunctionConfiguration\"
                        ],
                        \"Resource\": \"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\"
                    }
                ]
            }"
        
        # Wait for IAM role to propagate
        log_info "Waiting for IAM role to propagate..."
        sleep 15
    fi
    
    # Create the Firehose delivery stream
    aws firehose create-delivery-stream \
        --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" \
        --delivery-stream-type DirectPut \
        --amazon-opensearch-service-destination-configuration "{
            \"RoleARN\": \"arn:aws:iam:${AWS_ACCOUNT_ID}:role/firehose-opensearch-role-${RANDOM_SUFFIX}\",
            \"DomainARN\": \"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN_NAME}\",
            \"IndexName\": \"vpc-lattice-traffic\",
            \"S3Configuration\": {
                \"RoleARN\": \"arn:aws:iam:${AWS_ACCOUNT_ID}:role/firehose-opensearch-role-${RANDOM_SUFFIX}\",
                \"BucketARN\": \"arn:aws:s3:::${S3_BACKUP_BUCKET}\",
                \"Prefix\": \"firehose-backup/\",
                \"BufferingHints\": {
                    \"SizeInMBs\": 1,
                    \"IntervalInSeconds\": 60
                },
                \"CompressionFormat\": \"GZIP\"
            },
            \"ProcessingConfiguration\": {
                \"Enabled\": true,
                \"Processors\": [
                    {
                        \"Type\": \"Lambda\",
                        \"Parameters\": [
                            {
                                \"ParameterName\": \"LambdaArn\",
                                \"ParameterValue\": \"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\"
                            }
                        ]
                    }
                ]
            },
            \"CloudWatchLoggingOptions\": {
                \"Enabled\": true,
                \"LogGroupName\": \"/aws/kinesisfirehose/${FIREHOSE_DELIVERY_STREAM}\"
            }
        }"
    
    log_success "Kinesis Data Firehose delivery stream created"
}

# Function to create VPC Lattice resources
create_vpc_lattice_resources() {
    log_info "Creating VPC Lattice service network: $SERVICE_NETWORK_NAME"
    
    # Check if service network already exists
    if aws vpc-lattice list-service-networks --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text | grep -q .; then
        log_warning "VPC Lattice service network $SERVICE_NETWORK_NAME already exists"
        export SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" --output text)
        export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text)
    else
        # Create VPC Lattice service network
        aws vpc-lattice create-service-network \
            --name "$SERVICE_NETWORK_NAME" \
            --auth-type AWS_IAM
        
        # Get service network details
        export SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" --output text)
        export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text)
        
        # Create a demo service
        aws vpc-lattice create-service \
            --name "demo-service-${RANDOM_SUFFIX}" \
            --auth-type AWS_IAM
        
        export DEMO_SERVICE_ARN=$(aws vpc-lattice list-services \
            --query "items[?name=='demo-service-${RANDOM_SUFFIX}'].arn" --output text)
        
        # Associate the service with the service network
        aws vpc-lattice create-service-network-service-association \
            --service-network-identifier "$SERVICE_NETWORK_ID" \
            --service-identifier "$DEMO_SERVICE_ARN"
    fi
    
    # Update deployment info
    jq ".service_network_arn = \"$SERVICE_NETWORK_ARN\" | .service_network_id = \"$SERVICE_NETWORK_ID\"" deployment_info.json > temp.json && mv temp.json deployment_info.json
    
    log_success "VPC Lattice service network created: $SERVICE_NETWORK_ARN"
}

# Function to configure access log subscription
configure_access_logs() {
    log_info "Configuring VPC Lattice access log subscription..."
    
    # Check if access log subscription already exists
    if aws vpc-lattice list-access-log-subscriptions --resource-identifier "$SERVICE_NETWORK_ARN" --query 'items[0].arn' --output text | grep -q .; then
        log_warning "Access log subscription already exists for service network"
        return 0
    fi
    
    # Create access log subscription
    aws vpc-lattice create-access-log-subscription \
        --resource-identifier "$SERVICE_NETWORK_ARN" \
        --destination-arn "arn:aws:firehose:${AWS_REGION}:${AWS_ACCOUNT_ID}:deliverystream/${FIREHOSE_DELIVERY_STREAM}"
    
    # Get the access log subscription details
    export ACCESS_LOG_SUBSCRIPTION_ARN=$(aws vpc-lattice list-access-log-subscriptions \
        --resource-identifier "$SERVICE_NETWORK_ARN" \
        --query 'items[0].arn' --output text)
    
    # Update deployment info
    jq ".access_log_subscription_arn = \"$ACCESS_LOG_SUBSCRIPTION_ARN\"" deployment_info.json > temp.json && mv temp.json deployment_info.json
    
    log_success "Access log subscription configured: $ACCESS_LOG_SUBSCRIPTION_ARN"
}

# Function to configure OpenSearch index template
configure_opensearch_template() {
    log_info "Configuring OpenSearch index template..."
    
    # Wait for OpenSearch to be fully ready
    sleep 30
    
    # Create index template for VPC Lattice traffic logs
    curl -X PUT "https://${OPENSEARCH_ENDPOINT}/_index_template/vpc-lattice-template" \
        -H "Content-Type: application/json" \
        -d '{
            "index_patterns": ["vpc-lattice-traffic*"],
            "template": {
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 0,
                    "refresh_interval": "5s"
                },
                "mappings": {
                    "properties": {
                        "@timestamp": { "type": "date" },
                        "sourceIpPort": { "type": "keyword" },
                        "destinationIpPort": { "type": "keyword" },
                        "requestMethod": { "type": "keyword" },
                        "requestPath": { "type": "keyword" },
                        "responseCode": { "type": "integer" },
                        "responseTimeMs": { "type": "integer" },
                        "userAgent": { 
                            "type": "text", 
                            "fields": {"keyword": {"type": "keyword"}} 
                        },
                        "serviceNetworkArn": { "type": "keyword" },
                        "targetGroupArn": { "type": "keyword" },
                        "response_class": { "type": "keyword" },
                        "is_error": { "type": "boolean" },
                        "response_time_bucket": { "type": "keyword" }
                    }
                }
            }
        }' > /dev/null 2>&1
    
    # Create sample index pattern for immediate use
    curl -X PUT "https://${OPENSEARCH_ENDPOINT}/vpc-lattice-traffic-$(date +%Y.%m.%d)" \
        -H "Content-Type: application/json" \
        -d '{
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 0
            }
        }' > /dev/null 2>&1
    
    log_success "OpenSearch index template and initial index created"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check OpenSearch cluster health
    log_info "Checking OpenSearch cluster health..."
    CLUSTER_HEALTH=$(curl -s "https://${OPENSEARCH_ENDPOINT}/_cluster/health" | jq -r '.status')
    if [ "$CLUSTER_HEALTH" = "green" ] || [ "$CLUSTER_HEALTH" = "yellow" ]; then
        log_success "OpenSearch cluster is healthy (status: $CLUSTER_HEALTH)"
    else
        log_error "OpenSearch cluster health check failed (status: $CLUSTER_HEALTH)"
        return 1
    fi
    
    # Check Firehose delivery stream status
    log_info "Checking Firehose delivery stream status..."
    FIREHOSE_STATUS=$(aws firehose describe-delivery-stream \
        --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" \
        --query 'DeliveryStreamDescription.DeliveryStreamStatus' --output text)
    if [ "$FIREHOSE_STATUS" = "ACTIVE" ]; then
        log_success "Firehose delivery stream is active"
    else
        log_error "Firehose delivery stream is not active (status: $FIREHOSE_STATUS)"
        return 1
    fi
    
    # Check Lambda function status
    log_info "Checking Lambda function status..."
    LAMBDA_STATUS=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.State' --output text)
    if [ "$LAMBDA_STATUS" = "Active" ]; then
        log_success "Lambda function is active"
    else
        log_error "Lambda function is not active (status: $LAMBDA_STATUS)"
        return 1
    fi
    
    # Send test record to verify data flow
    log_info "Sending test record to verify data flow..."
    echo '{"test_message": "VPC Lattice traffic analytics test", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | \
    aws firehose put-record \
        --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" \
        --record Data=blob://dev/stdin > /dev/null
    
    log_success "Test record sent to Firehose"
    log_success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "==========================================================================================================="
    echo -e "${GREEN}✅ Traffic Analytics with VPC Lattice and OpenSearch - Deployment Complete${NC}"
    echo "==========================================================================================================="
    echo ""
    echo "📊 OpenSearch Dashboards URL: https://${OPENSEARCH_ENDPOINT}/_dashboards"
    echo "🔍 OpenSearch Domain: $OPENSEARCH_DOMAIN_NAME"
    echo "🚀 Firehose Delivery Stream: $FIREHOSE_DELIVERY_STREAM"
    echo "⚡ Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "🗂️  S3 Backup Bucket: $S3_BACKUP_BUCKET"
    echo "🌐 VPC Lattice Service Network: $SERVICE_NETWORK_NAME"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Access OpenSearch Dashboards to create visualizations"
    echo "   2. Generate traffic through your VPC Lattice services to see analytics data"
    echo "   3. Monitor the Kinesis Data Firehose delivery stream for incoming data"
    echo "   4. Check CloudWatch logs for any processing errors"
    echo ""
    echo "💡 Test the data flow:"
    echo "   curl -X GET 'https://${OPENSEARCH_ENDPOINT}/vpc-lattice-traffic-*/_search?pretty'"
    echo ""
    echo "🗑️  To clean up resources, run: ./destroy.sh"
    echo ""
    echo "📄 Deployment details saved to: deployment_info.json"
    echo "==========================================================================================================="
}

# Main deployment function
main() {
    echo "==========================================================================================================="
    echo "🚀 Traffic Analytics with VPC Lattice and OpenSearch - Deployment Script"
    echo "==========================================================================================================="
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_opensearch_domain
    create_lambda_function
    create_firehose_stream
    create_vpc_lattice_resources
    configure_access_logs
    configure_opensearch_template
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully! 🎉"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT TERM

# Run main function
main "$@"