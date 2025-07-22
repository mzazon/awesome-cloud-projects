#!/bin/bash

# Deploy script for Intelligent Content Moderation with Amazon Bedrock and EventBridge
# Recipe: building-intelligent-content-moderation-with-amazon-bedrock-and-eventbridge

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "AWS CLI is configured and authenticated"
}

# Function to check Bedrock model access
check_bedrock_access() {
    log "Checking Bedrock model access..."
    
    # Check if Claude 3 Sonnet model is available
    if ! aws bedrock list-foundation-models --region "${AWS_REGION}" --query 'modelSummaries[?contains(modelId, `anthropic.claude-3-sonnet`)]' --output text >/dev/null 2>&1; then
        warning "Cannot verify Bedrock model access. Please ensure Claude 3 Sonnet model access is enabled in the Bedrock console."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        success "Bedrock model access verified"
    fi
}

# Function to generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    export CONTENT_BUCKET="content-moderation-bucket-${RANDOM_SUFFIX}"
    export APPROVED_BUCKET="approved-content-${RANDOM_SUFFIX}"
    export REJECTED_BUCKET="rejected-content-${RANDOM_SUFFIX}"
    export CUSTOM_BUS_NAME="content-moderation-bus"
    export SNS_TOPIC_NAME="content-moderation-notifications"
    
    success "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    for bucket in "${CONTENT_BUCKET}" "${APPROVED_BUCKET}" "${REJECTED_BUCKET}"; do
        # Create bucket
        if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
            warning "Bucket ${bucket} already exists"
        else
            aws s3 mb "s3://${bucket}" --region "${AWS_REGION}"
            success "Created bucket: ${bucket}"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${bucket}" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "${bucket}" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Add public access block
        aws s3api put-public-access-block \
            --bucket "${bucket}" \
            --public-access-block-configuration \
            'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    done
    
    success "All S3 buckets created and configured"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    export SNS_TOPIC_ARN
    success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Subscribe email if provided
    if [ -n "${EMAIL_ADDRESS}" ]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}"
        success "Email subscription added: ${EMAIL_ADDRESS}"
    else
        warning "No email address provided. Skip email subscription or set EMAIL_ADDRESS environment variable."
    fi
}

# Function to create custom EventBridge bus
create_eventbridge_bus() {
    log "Creating custom EventBridge bus..."
    
    if aws events describe-event-bus --name "${CUSTOM_BUS_NAME}" >/dev/null 2>&1; then
        warning "EventBridge bus ${CUSTOM_BUS_NAME} already exists"
    else
        aws events create-event-bus --name "${CUSTOM_BUS_NAME}"
        success "EventBridge bus created: ${CUSTOM_BUS_NAME}"
    fi
    
    CUSTOM_BUS_ARN="arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${CUSTOM_BUS_NAME}"
    export CUSTOM_BUS_ARN
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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
    
    # Create Lambda execution role
    if aws iam get-role --role-name ContentAnalysisLambdaRole >/dev/null 2>&1; then
        warning "IAM role ContentAnalysisLambdaRole already exists"
    else
        aws iam create-role \
            --role-name ContentAnalysisLambdaRole \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        success "IAM role created: ContentAnalysisLambdaRole"
    fi
    
    # Create comprehensive policy for Lambda functions
    cat > /tmp/content-analysis-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::${CONTENT_BUCKET}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": "${CUSTOM_BUS_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:CopyObject"
            ],
            "Resource": [
                "arn:aws:s3:::${APPROVED_BUCKET}/*",
                "arn:aws:s3:::${REJECTED_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    # Attach policies
    aws iam put-role-policy \
        --role-name ContentAnalysisLambdaRole \
        --policy-name ContentAnalysisPolicy \
        --policy-document file:///tmp/content-analysis-policy.json
    
    aws iam attach-role-policy \
        --role-name ContentAnalysisLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    success "IAM policies attached to ContentAnalysisLambdaRole"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Wait for IAM role to be available
    log "Waiting for IAM role propagation..."
    sleep 30
    
    # Create content analysis function
    create_content_analysis_function
    
    # Create workflow handler functions
    create_workflow_handlers
    
    success "All Lambda functions created successfully"
}

# Function to create content analysis function
create_content_analysis_function() {
    mkdir -p /tmp/lambda-functions/content-analysis
    
    # Create Python code for content analysis
    cat > /tmp/lambda-functions/content-analysis/index.py << 'EOF'
import json
import boto3
import urllib.parse
from datetime import datetime

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Prepare moderation prompt
        prompt = f"""
Human: Please analyze the following content for policy violations. 
Consider harmful content including hate speech, violence, harassment, 
inappropriate sexual content, misinformation, and spam.

Content to analyze:
{content[:2000]}

Respond with a JSON object containing:
- "decision": "approved", "rejected", or "review"
- "confidence": score from 0.0 to 1.0
- "reason": brief explanation
- "categories": array of policy categories if violations found

        Assistant: """
        
        # Invoke Bedrock Claude model
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=body,
            contentType='application/json'
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        
        # Parse AI response
        try:
            moderation_result = json.loads(response_body['content'][0]['text'])
        except:
            moderation_result = {
                "decision": "review",
                "confidence": 0.5,
                "reason": "Unable to parse AI response",
                "categories": ["parsing_error"]
            }
        
        # Publish event to EventBridge
        event_detail = {
            'bucket': bucket,
            'key': key,
            'decision': moderation_result['decision'],
            'confidence': moderation_result['confidence'],
            'reason': moderation_result['reason'],
            'categories': moderation_result.get('categories', []),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'content.moderation',
                    'DetailType': f"Content {moderation_result['decision'].title()}",
                    'Detail': json.dumps(event_detail),
                    'EventBusName': 'content-moderation-bus'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content analyzed successfully',
                'decision': moderation_result['decision']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

    # Deploy content analysis function
    cd /tmp/lambda-functions/content-analysis
    zip -r content-analysis.zip .
    
    CONTENT_ANALYSIS_FUNCTION_ARN=$(aws lambda create-function \
        --function-name ContentAnalysisFunction \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/ContentAnalysisLambdaRole \
        --handler index.lambda_handler \
        --zip-file fileb://content-analysis.zip \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables="{CUSTOM_BUS_NAME=${CUSTOM_BUS_NAME}}" \
        --query FunctionArn --output text)
    
    export CONTENT_ANALYSIS_FUNCTION_ARN
    success "Content analysis function deployed: ${CONTENT_ANALYSIS_FUNCTION_ARN}"
    
    cd /tmp
}

# Function to create workflow handlers
create_workflow_handlers() {
    for workflow in approved rejected review; do
        mkdir -p /tmp/lambda-functions/${workflow}-handler
        
        cat > /tmp/lambda-functions/${workflow}-handler/index.py << EOF
import json
import boto3
from datetime import datetime

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        # Determine target bucket based on workflow
        target_bucket = {
            'approved': '${APPROVED_BUCKET}',
            'rejected': '${REJECTED_BUCKET}',
            'review': '${REJECTED_BUCKET}'
        }['${workflow}']
        
        target_key = f"${workflow}/{datetime.utcnow().strftime('%Y/%m/%d')}/{source_key}"
        
        # Copy content to appropriate bucket
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=target_bucket,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={
                'moderation-decision': detail['decision'],
                'moderation-confidence': str(detail['confidence']),
                'moderation-reason': detail['reason'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }
        )
        
        # Send notification
        message = f"""Content Moderation Result: {detail['decision'].upper()}

File: {source_key}
Confidence: {detail['confidence']:.2f}
Reason: {detail['reason']}
Categories: {', '.join(detail.get('categories', []))}
Timestamp: {detail['timestamp']}

Target Location: s3://{target_bucket}/{target_key}"""
        
        sns.publish(
            TopicArn='${SNS_TOPIC_ARN}',
            Subject=f'Content {detail["decision"].title()}: {source_key}',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Content processed for ${workflow}',
                'target_location': f's3://{target_bucket}/{target_key}'
            })
        }
        
    except Exception as e:
        print(f"Error in ${workflow} handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
        
        # Deploy workflow handler
        cd /tmp/lambda-functions/${workflow}-handler
        zip -r ${workflow}-handler.zip .
        
        aws lambda create-function \
            --function-name ${workflow^}HandlerFunction \
            --runtime python3.9 \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/ContentAnalysisLambdaRole \
            --handler index.lambda_handler \
            --zip-file fileb://${workflow}-handler.zip \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables="{APPROVED_BUCKET=${APPROVED_BUCKET},REJECTED_BUCKET=${REJECTED_BUCKET},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
        
        success "Workflow handler deployed: ${workflow^}HandlerFunction"
    done
    
    cd /tmp
}

# Function to configure S3 event notifications
configure_s3_notifications() {
    log "Configuring S3 event notifications..."
    
    # Grant S3 permission to invoke Lambda function
    aws lambda add-permission \
        --function-name ContentAnalysisFunction \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn arn:aws:s3:::${CONTENT_BUCKET}
    
    # Configure S3 event notification for text files
    cat > /tmp/s3-notification-config.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "ContentAnalysisNotification",
            "LambdaFunctionArn": "${CONTENT_ANALYSIS_FUNCTION_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".txt"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-notification-configuration \
        --bucket ${CONTENT_BUCKET} \
        --notification-configuration file:///tmp/s3-notification-config.json
    
    success "S3 event notifications configured"
}

# Function to create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules..."
    
    # Create rules for each decision type
    for decision in approved rejected review; do
        # Create rule
        aws events put-rule \
            --name ${decision}-content-rule \
            --event-pattern "{\"source\":[\"content.moderation\"],\"detail-type\":[\"Content ${decision^}\"]}" \
            --state ENABLED \
            --event-bus-name ${CUSTOM_BUS_NAME}
        
        # Add Lambda target
        aws events put-targets \
            --rule ${decision}-content-rule \
            --event-bus-name ${CUSTOM_BUS_NAME} \
            --targets Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${decision^}HandlerFunction
        
        # Grant EventBridge permission
        aws lambda add-permission \
            --function-name ${decision^}HandlerFunction \
            --principal events.amazonaws.com \
            --action lambda:InvokeFunction \
            --statement-id eventbridge-${decision}-permission \
            --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${decision}-content-rule
        
        success "EventBridge rule created: ${decision}-content-rule"
    done
}

# Function to create test content
create_test_content() {
    log "Creating test content files..."
    
    # Create test files
    echo "This is a great product review. I love this item and recommend it to everyone!" > /tmp/positive-content.txt
    echo "I hate this stupid product and the people who made it are complete idiots!" > /tmp/negative-content.txt
    echo "This product is okay. Nothing special but it works fine for basic use." > /tmp/neutral-content.txt
    
    success "Test content files created"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Lambda functions
    local functions=("ContentAnalysisFunction" "ApprovedHandlerFunction" "RejectedHandlerFunction" "ReviewHandlerFunction")
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "${function}" >/dev/null 2>&1; then
            success "Lambda function validated: ${function}"
        else
            error "Lambda function validation failed: ${function}"
        fi
    done
    
    success "Deployment validation completed"
}

# Main execution function
main() {
    echo
    echo "=================================="
    echo "Content Moderation Deployment Script"
    echo "=================================="
    echo
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Check prerequisites
    check_aws_config
    check_bedrock_access
    
    # Generate resource names
    generate_resource_names
    
    # Deploy infrastructure
    create_s3_buckets
    create_sns_topic
    create_eventbridge_bus
    create_iam_roles
    create_lambda_functions
    configure_s3_notifications
    create_eventbridge_rules
    create_test_content
    
    # Validate deployment
    validate_deployment
    
    echo
    success "✅ Content moderation infrastructure deployed successfully!"
    echo
    echo "Resource Summary:"
    echo "  • Content bucket: ${CONTENT_BUCKET}"
    echo "  • Approved bucket: ${APPROVED_BUCKET}"
    echo "  • Rejected bucket: ${REJECTED_BUCKET}"
    echo "  • SNS topic: ${SNS_TOPIC_ARN}"
    echo "  • EventBridge bus: ${CUSTOM_BUS_NAME}"
    echo "  • Lambda functions: 4 deployed"
    echo
    echo "Testing:"
    echo "  • Upload test files: aws s3 cp /tmp/positive-content.txt s3://${CONTENT_BUCKET}/"
    echo "  • Monitor logs: aws logs tail /aws/lambda/ContentAnalysisFunction --follow"
    echo "  • Check processed content in approved/rejected buckets"
    echo
    if [ -n "${EMAIL_ADDRESS}" ]; then
        echo "  • Check your email (${EMAIL_ADDRESS}) for moderation notifications"
    else
        echo "  • Set EMAIL_ADDRESS environment variable and re-run to enable email notifications"
    fi
    echo
    warning "Remember to run destroy.sh when finished to avoid ongoing charges!"
    echo
}

# Run main function
main "$@"