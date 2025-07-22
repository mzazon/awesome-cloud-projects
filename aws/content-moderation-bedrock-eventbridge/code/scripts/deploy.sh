#!/bin/bash

# AI Content Moderation with Bedrock
# Deployment Script
# 
# This script deploys the complete content moderation infrastructure including:
# - S3 buckets for content storage
# - Lambda functions for AI-powered analysis and workflow processing
# - EventBridge custom bus and rules for event routing
# - SNS topic for notifications
# - IAM roles and policies

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

# Cleanup function for rollback on failure
cleanup_on_failure() {
    warn "Deployment failed. Starting cleanup of partially created resources..."
    
    # Remove Lambda functions if they exist
    for function in ContentAnalysisFunction ApprovedHandlerFunction RejectedHandlerFunction ReviewHandlerFunction; do
        if aws lambda get-function --function-name $function >/dev/null 2>&1; then
            aws lambda delete-function --function-name $function
            log "Deleted Lambda function: $function"
        fi
    done
    
    # Remove EventBridge rules and custom bus
    for decision in approved rejected review; do
        if aws events list-targets-by-rule --rule ${decision}-content-rule --event-bus-name $CUSTOM_BUS_NAME >/dev/null 2>&1; then
            aws events remove-targets --rule ${decision}-content-rule --event-bus-name $CUSTOM_BUS_NAME --ids 1
            aws events delete-rule --name ${decision}-content-rule --event-bus-name $CUSTOM_BUS_NAME
        fi
    done
    
    if aws events describe-event-bus --name $CUSTOM_BUS_NAME >/dev/null 2>&1; then
        aws events delete-event-bus --name $CUSTOM_BUS_NAME
        log "Deleted custom EventBridge bus"
    fi
    
    # Remove S3 buckets
    for bucket in $CONTENT_BUCKET $APPROVED_BUCKET $REJECTED_BUCKET; do
        if aws s3 ls s3://$bucket >/dev/null 2>&1; then
            aws s3 rm s3://$bucket --recursive
            aws s3 rb s3://$bucket
            log "Deleted S3 bucket: $bucket"
        fi
    done
    
    # Remove IAM roles
    if aws iam get-role --role-name ContentAnalysisLambdaRole >/dev/null 2>&1; then
        aws iam detach-role-policy --role-name ContentAnalysisLambdaRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
        aws iam delete-role-policy --role-name ContentAnalysisLambdaRole --policy-name ContentAnalysisPolicy || true
        aws iam delete-role --role-name ContentAnalysisLambdaRole
        log "Deleted IAM role: ContentAnalysisLambdaRole"
    fi
    
    # Remove SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        aws sns delete-topic --topic-arn $SNS_TOPIC_ARN
        log "Deleted SNS topic"
    fi
    
    # Clean up local files
    rm -rf lambda-functions/ *.json *.txt
    
    error "Deployment failed and cleanup completed"
}

# Set trap for cleanup on failure
trap cleanup_on_failure ERR

# Check prerequisites
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed or not in PATH"
fi

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS credentials not configured or invalid"
fi

# Check Bedrock access
info "Checking Amazon Bedrock model access..."
if ! aws bedrock list-foundation-models --region us-east-1 >/dev/null 2>&1; then
    warn "Unable to access Bedrock. Ensure you have proper permissions and model access is enabled"
fi

log "Prerequisites check completed successfully"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warn "No default region found, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Set resource names
export CONTENT_BUCKET="content-moderation-bucket-${RANDOM_SUFFIX}"
export APPROVED_BUCKET="approved-content-${RANDOM_SUFFIX}"
export REJECTED_BUCKET="rejected-content-${RANDOM_SUFFIX}"
export CUSTOM_BUS_NAME="content-moderation-bus"
export SNS_TOPIC_NAME="content-moderation-notifications"

log "Environment variables configured"
info "Content bucket: $CONTENT_BUCKET"
info "Approved bucket: $APPROVED_BUCKET"
info "Rejected bucket: $REJECTED_BUCKET"
info "Custom bus: $CUSTOM_BUS_NAME"

# Create S3 buckets for content storage
log "Creating S3 buckets..."

aws s3 mb s3://${CONTENT_BUCKET} --region ${AWS_REGION}
aws s3 mb s3://${APPROVED_BUCKET} --region ${AWS_REGION}
aws s3 mb s3://${REJECTED_BUCKET} --region ${AWS_REGION}

# Enable versioning and encryption
for bucket in ${CONTENT_BUCKET} ${APPROVED_BUCKET} ${REJECTED_BUCKET}; do
    aws s3api put-bucket-versioning \
        --bucket ${bucket} \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-encryption \
        --bucket ${bucket} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
done

log "S3 buckets created with security features enabled"

# Create SNS Topic for Notifications
log "Creating SNS topic for notifications..."

SNS_TOPIC_ARN=$(aws sns create-topic \
    --name ${SNS_TOPIC_NAME} \
    --query TopicArn --output text)

log "SNS topic created: ${SNS_TOPIC_ARN}"

# Create Custom EventBridge Bus
log "Creating custom EventBridge bus..."

aws events create-event-bus --name ${CUSTOM_BUS_NAME}
CUSTOM_BUS_ARN="arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${CUSTOM_BUS_NAME}"

log "Custom EventBridge bus created: ${CUSTOM_BUS_NAME}"

# Create IAM Roles for Lambda Functions
log "Creating IAM roles for Lambda functions..."

# Trust policy for Lambda execution
cat > lambda-trust-policy.json << EOF
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

# Create role for content analysis Lambda
aws iam create-role \
    --role-name ContentAnalysisLambdaRole \
    --assume-role-policy-document file://lambda-trust-policy.json

# Create policy for Bedrock, S3, and EventBridge access
cat > content-analysis-policy.json << EOF
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
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:CopyObject"
            ],
            "Resource": [
                "arn:aws:s3:::${CONTENT_BUCKET}/*",
                "arn:aws:s3:::${APPROVED_BUCKET}/*",
                "arn:aws:s3:::${REJECTED_BUCKET}/*"
            ]
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
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name ContentAnalysisLambdaRole \
    --policy-name ContentAnalysisPolicy \
    --policy-document file://content-analysis-policy.json

# Attach basic Lambda execution role
aws iam attach-role-policy \
    --role-name ContentAnalysisLambdaRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

log "IAM roles created with appropriate permissions"

# Wait for IAM role propagation
info "Waiting for IAM role propagation (30 seconds)..."
sleep 30

# Create Content Analysis Lambda Function
log "Creating content analysis Lambda function..."

mkdir -p lambda-functions/content-analysis
cat > lambda-functions/content-analysis/index.py << 'EOF'
import json
import boto3
import urllib.parse
from datetime import datetime
import os

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        print(f"Processing file: s3://{bucket}/{key}")
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        print(f"Content length: {len(content)} characters")
        
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
        Assistant: I need to analyze this content for policy violations. Looking at the provided content:

        {content[:2000]}

        Let me evaluate this for harmful content across several categories:

        - Hate speech and harassment
        - Violence and threats
        - Sexual content
        - Misinformation
        - Spam and unwanted content

        Based on my analysis, here is my assessment:

        {"decision": "approved", "confidence": 0.95, "reason": "Content appears to be appropriate and does not violate content policies", "categories": []}
        """
        
        # Invoke Bedrock Claude model
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId="anthropic.claude-3-sonnet-20240229-v1:0",
            body=body,
            contentType="application/json"
        )
        
        response_body = json.loads(bedrock_response["body"].read())
        
        # Extract JSON from Claude response
        content_text = response_body["content"][0]["text"]
        print(f"Claude response: {content_text}")
        
        # Try to extract JSON from the response
        try:
            # Find JSON in the response
            start_idx = content_text.find("{")
            end_idx = content_text.rfind("}") + 1
            json_str = content_text[start_idx:end_idx]
            moderation_result = json.loads(json_str)
        except:
            # Fallback if JSON parsing fails
            print("Failed to parse JSON from Claude response, using default approved")
            moderation_result = {
                "decision": "approved",
                "confidence": 0.8,
                "reason": "Could not parse AI response",
                "categories": []
            }
        
        # Publish event to EventBridge
        event_detail = {
            "bucket": bucket,
            "key": key,
            "decision": moderation_result["decision"],
            "confidence": moderation_result["confidence"],
            "reason": moderation_result["reason"],
            "categories": moderation_result.get("categories", []),
            "timestamp": datetime.utcnow().isoformat()
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    "Source": "content.moderation",
                    "DetailType": f"Content {moderation_result[\"decision\"].title()}",
                    "Detail": json.dumps(event_detail),
                    "EventBusName": os.environ.get("CUSTOM_BUS_NAME", "content-moderation-bus")
                }
            ]
        )
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Content analyzed successfully",
                "decision": moderation_result["decision"]
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
EOF

# Package and deploy content analysis function
cd lambda-functions/content-analysis
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

cd ../..

log "Content analysis Lambda function deployed: ${CONTENT_ANALYSIS_FUNCTION_ARN}"

# Create workflow handler functions
log "Creating workflow handler Lambda functions..."

for workflow in approved rejected review; do
    mkdir -p lambda-functions/${workflow}-handler
    
    cat > lambda-functions/${workflow}-handler/index.py << HANDLER_EOF
import json
import boto3
from datetime import datetime
import os

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        # Determine target bucket based on workflow
        target_bucket_map = {
            'approved': os.environ.get('APPROVED_BUCKET', 'approved-content'),
            'rejected': os.environ.get('REJECTED_BUCKET', 'rejected-content'),
            'review': os.environ.get('REJECTED_BUCKET', 'rejected-content')
        }
        target_bucket = target_bucket_map['${workflow}']
        
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
        message = f"""
Content Moderation Result: {detail['decision'].upper()}

File: {source_key}
Confidence: {detail['confidence']:.2f}
Reason: {detail['reason']}
Categories: {', '.join(detail.get('categories', []))}
Timestamp: {detail['timestamp']}

Target Location: s3://{target_bucket}/{target_key}
        """
        
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
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
HANDLER_EOF
    
    # Package and deploy workflow function
    cd lambda-functions/${workflow}-handler
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
    
    cd ../..
done

log "Workflow Lambda functions created for all decision types"

# Configure S3 Event Notifications
log "Configuring S3 event notifications..."

# Grant S3 permission to invoke Lambda function
aws lambda add-permission \
    --function-name ContentAnalysisFunction \
    --principal s3.amazonaws.com \
    --action lambda:InvokeFunction \
    --statement-id s3-trigger-permission \
    --source-arn arn:aws:s3:::${CONTENT_BUCKET}

# Configure S3 event notification
cat > s3-notification-config.json << EOF
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
    --notification-configuration file://s3-notification-config.json

log "S3 event notification configured for content analysis"

# Create EventBridge Rules for Workflow Routing
log "Creating EventBridge rules for workflow routing..."

for decision in approved rejected review; do
    # Create rule
    aws events put-rule \
        --name ${decision}-content-rule \
        --event-pattern "{\"source\":[\"content.moderation\"],\"detail-type\":[\"Content ${decision^}\"]}" \
        --state ENABLED \
        --event-bus-name ${CUSTOM_BUS_NAME}
    
    # Add Lambda target to rule
    aws events put-targets \
        --rule ${decision}-content-rule \
        --event-bus-name ${CUSTOM_BUS_NAME} \
        --targets Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${decision^}HandlerFunction
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${decision^}HandlerFunction \
        --principal events.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id eventbridge-${decision}-permission \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${decision}-content-rule
done

log "EventBridge rules configured for all content workflows"

# Clean up temporary files
rm -f lambda-trust-policy.json content-analysis-policy.json s3-notification-config.json

# Disable trap
trap - ERR

log "Content moderation infrastructure deployment complete\!"
info ""
info "To test the system:"
info "1. Upload a text file to s3://${CONTENT_BUCKET}/"
info "2. Check CloudWatch Logs for Lambda function execution"
info "3. Monitor EventBridge events and SNS notifications"
info "4. Check processed content in approved/rejected buckets"
info ""
info "Resource names saved to environment:"
info "  Content bucket: ${CONTENT_BUCKET}"
info "  Approved bucket: ${APPROVED_BUCKET}"
info "  Rejected bucket: ${REJECTED_BUCKET}"
info "  Custom bus: ${CUSTOM_BUS_NAME}"
info "  SNS topic: ${SNS_TOPIC_ARN}"
