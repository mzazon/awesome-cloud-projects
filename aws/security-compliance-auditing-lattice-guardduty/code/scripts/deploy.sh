#!/bin/bash

# Security Compliance Auditing with VPC Lattice and GuardDuty - Deployment Script
# This script deploys the complete security compliance auditing infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/security-compliance-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check log file: $LOG_FILE"
    log_warning "You may need to run destroy.sh to clean up partially created resources"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Security Compliance Auditing Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without creating resources
    -r, --region        AWS region (default: current configured region)
    -e, --email         Email address for security alerts (required)
    --skip-guardduty    Skip GuardDuty setup (if already enabled)
    --debug             Enable debug logging

EXAMPLES:
    $0 --email security@company.com
    $0 --email security@company.com --region us-west-2
    $0 --dry-run --email security@company.com

PREREQUISITES:
    - AWS CLI installed and configured
    - Appropriate IAM permissions
    - Email address for security notifications

EOF
}

# Parse command line arguments
EMAIL=""
SKIP_GUARDDUTY=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        --skip-guardduty)
            SKIP_GUARDDUTY=true
            shift
            ;;
        --debug)
            DEBUG=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$EMAIL" ]]; then
    log_error "Email address is required for security alerts"
    log_info "Use: $0 --email your-email@domain.com"
    exit 1
fi

# Email validation
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    log_error "Invalid email format: $EMAIL"
    exit 1
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("zip" "python3" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS region not configured. Set it with: aws configure set region us-east-1"
            exit 1
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="security-audit-logs-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/vpclattice/security-audit"
    export LAMBDA_FUNCTION_NAME="security-compliance-processor"
    export SNS_TOPIC_NAME="security-alerts-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="security-demo-network-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="SecurityComplianceProcessorRole"
    
    log_success "Environment variables configured"
    log_info "Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "Bucket Name: $BUCKET_NAME"
    log_info "SNS Topic: $SNS_TOPIC_NAME"
}

# Create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for compliance reports..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create S3 bucket: $BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log_warning "S3 bucket already exists: $BUCKET_NAME"
        return 0
    fi
    
    # Create bucket with region-specific configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    
    log_success "S3 bucket created and configured: $BUCKET_NAME"
}

# Create CloudWatch Log Group
create_log_group() {
    log_info "Creating CloudWatch log group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create log group: $LOG_GROUP_NAME"
        return 0
    fi
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`]' --output text | grep -q "$LOG_GROUP_NAME"; then
        log_warning "Log group already exists: $LOG_GROUP_NAME"
        return 0
    fi
    
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME"
    
    # Set retention policy (30 days)
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP_NAME" \
        --retention-in-days 30
    
    log_success "CloudWatch log group created: $LOG_GROUP_NAME"
}

# Enable GuardDuty
enable_guardduty() {
    log_info "Enabling Amazon GuardDuty..."
    
    if [[ "$SKIP_GUARDDUTY" == "true" ]]; then
        log_info "Skipping GuardDuty setup as requested"
        # Try to get existing detector ID
        export GUARDDUTY_DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")
        if [[ "$GUARDDUTY_DETECTOR_ID" == "None" || -z "$GUARDDUTY_DETECTOR_ID" ]]; then
            log_error "No existing GuardDuty detector found. Remove --skip-guardduty flag to create one."
            exit 1
        fi
        log_info "Using existing GuardDuty detector: $GUARDDUTY_DETECTOR_ID"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable GuardDuty"
        return 0
    fi
    
    # Check if GuardDuty is already enabled
    local existing_detectors=$(aws guardduty list-detectors --query 'DetectorIds' --output text)
    if [[ -n "$existing_detectors" && "$existing_detectors" != "None" ]]; then
        export GUARDDUTY_DETECTOR_ID=$(echo "$existing_detectors" | awk '{print $1}')
        log_warning "GuardDuty already enabled with detector: $GUARDDUTY_DETECTOR_ID"
        return 0
    fi
    
    # Enable GuardDuty
    export GUARDDUTY_DETECTOR_ID=$(aws guardduty create-detector \
        --enable \
        --finding-publishing-frequency FIFTEEN_MINUTES \
        --query DetectorId --output text)
    
    log_success "GuardDuty enabled with detector ID: $GUARDDUTY_DETECTOR_ID"
}

# Create SNS Topic
create_sns_topic() {
    log_info "Creating SNS topic for security alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        log_info "[DRY-RUN] Would subscribe email: $EMAIL"
        return 0
    fi
    
    # Create SNS topic
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    # Subscribe email
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$EMAIL"
    
    log_success "SNS topic created: $SNS_TOPIC_ARN"
    log_warning "Please check your email and confirm the subscription to receive alerts"
}

# Create IAM Role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create IAM role: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log_warning "IAM role already exists: $IAM_ROLE_NAME"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query Role.Arn --output text)
        return 0
    fi
    
    # Create trust policy
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Create custom policy
    cat > /tmp/lambda-security-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "guardduty:GetDetector",
                "guardduty:GetFindings",
                "guardduty:ListFindings"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
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
    
    # Attach policy
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name SecurityCompliancePolicy \
        --policy-document file:///tmp/lambda-security-policy.json
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query Role.Arn --output text)
    
    log_success "IAM role created: $LAMBDA_ROLE_ARN"
    
    # Clean up temp files
    rm -f /tmp/lambda-trust-policy.json /tmp/lambda-security-policy.json
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for security log processing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function already exists: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Copy Lambda code from repository
    local lambda_source="$SCRIPT_DIR/../terraform/lambda/security_processor.py"
    if [[ ! -f "$lambda_source" ]]; then
        # Fallback to inline code if source file not found
        cat > /tmp/security_processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta
import gzip
import base64

# Initialize AWS clients
guardduty = boto3.client('guardduty')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Process CloudWatch Logs events
        cw_data = event['awslogs']['data']
        compressed_payload = base64.b64decode(cw_data)
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        suspicious_activities = []
        metrics_data = []
        
        # Process each log event
        for log_event in log_data['logEvents']:
            try:
                log_entry = json.loads(log_event['message'])
                
                # Analyze access patterns
                analysis_result = analyze_access_log(log_entry)
                
                if analysis_result['is_suspicious']:
                    suspicious_activities.append(analysis_result)
                
                # Collect metrics
                metrics_data.append(extract_metrics(log_entry))
                
            except json.JSONDecodeError:
                print(f"Failed to parse log entry: {log_event['message']}")
                continue
        
        # Correlate with GuardDuty findings
        recent_findings = get_recent_guardduty_findings()
        
        # Generate compliance report
        compliance_report = generate_compliance_report(
            suspicious_activities, metrics_data, recent_findings
        )
        
        # Store report in S3
        store_compliance_report(compliance_report)
        
        # Send alerts if necessary
        if suspicious_activities:
            send_security_alert(suspicious_activities, recent_findings)
        
        # Publish metrics to CloudWatch
        publish_metrics(metrics_data)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {len(log_data["logEvents"])} log events')
        }
        
    except Exception as e:
        print(f"Error processing logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def analyze_access_log(log_entry):
    """Analyze VPC Lattice access log for suspicious patterns"""
    is_suspicious = False
    risk_score = 0
    reasons = []
    
    # Check for high error rates
    if log_entry.get('responseCode', 0) >= 400:
        risk_score += 20
        reasons.append('HTTP error response')
    
    # Check for unusual request patterns
    if log_entry.get('requestMethod') in ['PUT', 'DELETE', 'PATCH']:
        risk_score += 10
        reasons.append('Potentially sensitive operation')
    
    # Check for authentication failures
    if log_entry.get('authDeniedReason'):
        risk_score += 30
        reasons.append('Authentication failure')
    
    # Check for unusual response times
    duration = log_entry.get('duration', 0)
    if duration > 10000:  # More than 10 seconds
        risk_score += 15
        reasons.append('Unusually long response time')
    
    # Mark as suspicious if risk score exceeds threshold
    if risk_score >= 25:
        is_suspicious = True
    
    return {
        'is_suspicious': is_suspicious,
        'risk_score': risk_score,
        'reasons': reasons,
        'log_entry': log_entry,
        'timestamp': log_entry.get('startTime')
    }

def get_recent_guardduty_findings():
    """Retrieve recent GuardDuty findings"""
    detector_id = os.environ.get('GUARDDUTY_DETECTOR_ID')
    if not detector_id:
        return []
    
    try:
        # Get findings from the last hour
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        response = guardduty.list_findings(
            DetectorId=detector_id,
            FindingCriteria={
                'Criterion': {
                    'updatedAt': {
                        'Gte': int(start_time.timestamp() * 1000),
                        'Lte': int(end_time.timestamp() * 1000)
                    }
                }
            }
        )
        
        if response['FindingIds']:
            findings_response = guardduty.get_findings(
                DetectorId=detector_id,
                FindingIds=response['FindingIds']
            )
            return findings_response['Findings']
        
        return []
        
    except Exception as e:
        print(f"Error retrieving GuardDuty findings: {str(e)}")
        return []

def generate_compliance_report(suspicious_activities, metrics_data, guardduty_findings):
    """Generate comprehensive compliance report"""
    report = {
        'timestamp': datetime.utcnow().isoformat(),
        'summary': {
            'total_requests': len(metrics_data),
            'suspicious_activities': len(suspicious_activities),
            'guardduty_findings': len(guardduty_findings),
            'compliance_status': 'COMPLIANT' if len(suspicious_activities) == 0 else 'NON_COMPLIANT'
        },
        'suspicious_activities': suspicious_activities,
        'guardduty_findings': guardduty_findings,
        'metrics': calculate_summary_metrics(metrics_data)
    }
    
    return report

def store_compliance_report(report):
    """Store compliance report in S3"""
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return
    
    timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
    key = f"compliance-reports/{timestamp}/report-{int(datetime.utcnow().timestamp())}.json"
    
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(report, indent=2),
            ContentType='application/json'
        )
        print(f"Compliance report stored: s3://{bucket_name}/{key}")
    except Exception as e:
        print(f"Error storing compliance report: {str(e)}")

def send_security_alert(suspicious_activities, guardduty_findings):
    """Send security alert via SNS"""
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        return
    
    alert_message = {
        'timestamp': datetime.utcnow().isoformat(),
        'alert_type': 'SECURITY_VIOLATION',
        'suspicious_count': len(suspicious_activities),
        'guardduty_count': len(guardduty_findings),
        'details': {
            'suspicious_activities': suspicious_activities[:5],  # Limit to first 5
            'recent_guardduty_findings': [f['Title'] for f in guardduty_findings[:3]]
        }
    }
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject='Security Compliance Alert - Suspicious Activity Detected',
            Message=json.dumps(alert_message, indent=2)
        )
        print("Security alert sent successfully")
    except Exception as e:
        print(f"Error sending security alert: {str(e)}")

def extract_metrics(log_entry):
    """Extract metrics from log entry"""
    return {
        'response_code': log_entry.get('responseCode', 0),
        'duration': log_entry.get('duration', 0),
        'bytes_sent': log_entry.get('bytesSent', 0),
        'bytes_received': log_entry.get('bytesReceived', 0),
        'method': log_entry.get('requestMethod', 'UNKNOWN')
    }

def calculate_summary_metrics(metrics_data):
    """Calculate summary metrics"""
    if not metrics_data:
        return {}
    
    total_requests = len(metrics_data)
    error_count = sum(1 for m in metrics_data if m['response_code'] >= 400)
    avg_duration = sum(m['duration'] for m in metrics_data) / total_requests
    total_bytes = sum(m['bytes_sent'] + m['bytes_received'] for m in metrics_data)
    
    return {
        'total_requests': total_requests,
        'error_rate': (error_count / total_requests) * 100,
        'average_duration_ms': round(avg_duration, 2),
        'total_bytes_transferred': total_bytes
    }

def publish_metrics(metrics_data):
    """Publish custom metrics to CloudWatch"""
    if not metrics_data:
        return
    
    try:
        # Calculate and publish key metrics
        error_count = sum(1 for m in metrics_data if m['response_code'] >= 400)
        avg_duration = sum(m['duration'] for m in metrics_data) / len(metrics_data)
        
        cloudwatch.put_metric_data(
            Namespace='Security/VPCLattice',
            MetricData=[
                {
                    'MetricName': 'RequestCount',
                    'Value': len(metrics_data),
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ErrorCount',
                    'Value': error_count,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'AverageResponseTime',
                    'Value': avg_duration,
                    'Unit': 'Milliseconds'
                }
            ]
        )
        print("Metrics published to CloudWatch")
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")
EOF
        lambda_source="/tmp/security_processor.py"
    else
        cp "$lambda_source" /tmp/security_processor.py
    fi
    
    # Package Lambda function
    cd /tmp
    zip -q security-processor.zip security_processor.py
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 30
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler security_processor.lambda_handler \
        --zip-file fileb://security-processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{GUARDDUTY_DETECTOR_ID=${GUARDDUTY_DETECTOR_ID},BUCKET_NAME=${BUCKET_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
    
    log_success "Lambda function created: $LAMBDA_FUNCTION_NAME"
    
    # Clean up temp files
    rm -f /tmp/security_processor.py /tmp/security-processor.zip
}

# Create CloudWatch Log Subscription Filter
create_log_subscription() {
    log_info "Creating CloudWatch log subscription filter..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create log subscription filter"
        return 0
    fi
    
    # Create log subscription filter
    aws logs put-subscription-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "SecurityComplianceFilter" \
        --filter-pattern "" \
        --destination-arn "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_FUNCTION_NAME"
    
    # Grant CloudWatch Logs permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "AllowCWLogsInvocation" \
        --action lambda:InvokeFunction \
        --principal logs.amazonaws.com \
        --source-arn "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:$LOG_GROUP_NAME:*"
    
    log_success "CloudWatch log subscription filter configured"
}

# Create CloudWatch Dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create CloudWatch dashboard"
        return 0
    fi
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
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
                    [ "Security/VPCLattice", "RequestCount" ],
                    [ ".", "ErrorCount" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "VPC Lattice Traffic Overview"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "Security/VPCLattice", "AverageResponseTime" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Average Response Time"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}' | fields @timestamp, @message\\n| filter @message like /SECURITY_VIOLATION/\\n| sort @timestamp desc\\n| limit 20",
                "region": "${AWS_REGION}",
                "title": "Recent Security Alerts",
                "view": "table"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "SecurityComplianceDashboard" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    log_success "CloudWatch dashboard created: SecurityComplianceDashboard"
    
    # Clean up temp file
    rm -f /tmp/dashboard-config.json
}

# Create demo VPC Lattice service network
create_demo_service_network() {
    log_info "Creating demo VPC Lattice service network..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create VPC Lattice service network: $SERVICE_NETWORK_NAME"
        return 0
    fi
    
    # Create demo service network
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --query ServiceNetwork.Id --output text)
    
    # Configure access logging
    aws vpc-lattice create-access-log-subscription \
        --resource-identifier "$SERVICE_NETWORK_ID" \
        --destination-arn "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:$LOG_GROUP_NAME"
    
    log_success "VPC Lattice service network created: $SERVICE_NETWORK_ID"
    log_info "Access logging configured for security monitoring"
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would save deployment configuration"
        return 0
    fi
    
    # Create deployment config file
    cat > "$SCRIPT_DIR/.deployment-config" << EOF
# Security Compliance Auditing Deployment Configuration
# Generated: $(date)
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export LOG_GROUP_NAME="$LOG_GROUP_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export SNS_TOPIC_ARN="$SNS_TOPIC_ARN"
export SERVICE_NETWORK_NAME="$SERVICE_NETWORK_NAME"
export SERVICE_NETWORK_ID="$SERVICE_NETWORK_ID"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
export GUARDDUTY_DETECTOR_ID="$GUARDDUTY_DETECTOR_ID"
export EMAIL="$EMAIL"
EOF
    
    chmod 600 "$SCRIPT_DIR/.deployment-config"
    log_success "Deployment configuration saved to: $SCRIPT_DIR/.deployment-config"
}

# Print deployment summary
print_summary() {
    log_success "=== Deployment Complete ==="
    echo
    log_info "Deployed Resources:"
    echo "  ✅ S3 Bucket: $BUCKET_NAME"
    echo "  ✅ CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "  ✅ GuardDuty Detector: $GUARDDUTY_DETECTOR_ID"
    echo "  ✅ SNS Topic: $SNS_TOPIC_ARN"
    echo "  ✅ Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  ✅ IAM Role: $IAM_ROLE_NAME"
    echo "  ✅ CloudWatch Dashboard: SecurityComplianceDashboard"
    echo "  ✅ VPC Lattice Service Network: $SERVICE_NETWORK_ID"
    echo
    log_info "Next Steps:"
    echo "  1. Confirm email subscription for security alerts"
    echo "  2. View dashboard: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=SecurityComplianceDashboard"
    echo "  3. Monitor compliance reports in S3: s3://$BUCKET_NAME/compliance-reports/"
    echo "  4. Configure your VPC Lattice services to use the service network: $SERVICE_NETWORK_ID"
    echo
    log_info "To clean up resources, run: $SCRIPT_DIR/destroy.sh"
    log_info "Deployment log saved to: $LOG_FILE"
}

# Main deployment function
main() {
    log_info "Starting Security Compliance Auditing deployment..."
    log_info "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_log_group
    enable_guardduty
    create_sns_topic
    create_iam_role
    create_lambda_function
    create_log_subscription
    create_dashboard
    create_demo_service_network
    save_deployment_config
    
    if [[ "$DRY_RUN" == "false" ]]; then
        print_summary
    else
        log_info "DRY RUN COMPLETE - No resources were created"
    fi
}

# Run main function
main "$@"