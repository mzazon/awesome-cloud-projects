#!/bin/bash

# =============================================================================
# Container Security Scanning Pipeline Deployment Script
# =============================================================================
# This script deploys the complete container security scanning pipeline
# with ECR enhanced scanning, third-party tool integration, and automation.
# 
# Requirements:
# - AWS CLI v2 configured with appropriate permissions
# - Docker installed for container operations
# - Internet connection for third-party scanner integration
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/container-security-deploy-$$"
readonly LOG_FILE="${TEMP_DIR}/deployment.log"

# Deployment state file
readonly STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing jq..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            log_error "Cannot install jq. Please install jq manually."
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to initialize environment
initialize_environment() {
    log_info "Initializing deployment environment..."
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Initialize log file
    echo "Container Security Scanning Pipeline Deployment Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    echo "========================================" >> "${LOG_FILE}"
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="security-scanning-${random_suffix}"
    export ECR_REPO_NAME="secure-app-${random_suffix}"
    export CODEBUILD_PROJECT_NAME="security-scan-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="SecurityScanProcessor-${random_suffix}"
    export SNS_TOPIC_NAME="security-alerts-${random_suffix}"
    export EVENTBRIDGE_RULE_NAME="ECRScanCompleted-${random_suffix}"
    export CONFIG_RULE_NAME="ecr-repository-scan-enabled-${random_suffix}"
    export DASHBOARD_NAME="ContainerSecurityDashboard-${random_suffix}"
    export CODEBUILD_ROLE_NAME="ECRSecurityScanningRole-${random_suffix}"
    export LAMBDA_ROLE_NAME="SecurityScanLambdaRole-${random_suffix}"
    
    # Save state
    cat > "${STATE_FILE}" << EOF
PROJECT_NAME=${PROJECT_NAME}
ECR_REPO_NAME=${ECR_REPO_NAME}
CODEBUILD_PROJECT_NAME=${CODEBUILD_PROJECT_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
CONFIG_RULE_NAME=${CONFIG_RULE_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
CODEBUILD_ROLE_NAME=${CODEBUILD_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment initialized - Project: ${PROJECT_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # Create CodeBuild service role
    local codebuild_assume_policy
    codebuild_assume_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codebuild.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    aws iam create-role \
        --role-name "${CODEBUILD_ROLE_NAME}" \
        --assume-role-policy-document "${codebuild_assume_policy}" \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=CodeBuild \
        >> "${LOG_FILE}" 2>&1
    
    # Create Lambda execution role
    local lambda_assume_policy
    lambda_assume_policy=$(cat << 'EOF'
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
)
    
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document "${lambda_assume_policy}" \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=Lambda \
        >> "${LOG_FILE}" 2>&1
    
    # Wait for roles to be available
    log_info "Waiting for IAM roles to be available..."
    sleep 10
    
    log_success "IAM roles created"
}

# Function to create IAM policies
create_iam_policies() {
    log_info "Creating IAM policies..."
    
    # CodeBuild policy
    local codebuild_policy
    codebuild_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:GetAuthorizationToken",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "ecr:DescribeRepositories",
                "ecr:DescribeImages",
                "ecr:DescribeImageScanFindings"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
)
    
    aws iam put-role-policy \
        --role-name "${CODEBUILD_ROLE_NAME}" \
        --policy-name "ECRSecurityScanningPolicy" \
        --policy-document "${codebuild_policy}" \
        >> "${LOG_FILE}" 2>&1
    
    # Lambda policy
    local lambda_policy
    lambda_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "securityhub:BatchImportFindings",
                "securityhub:GetFindings",
                "sns:Publish",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name "SecurityHubIntegrationPolicy" \
        --policy-document "${lambda_policy}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "IAM policies created"
}

# Function to create ECR repository
create_ecr_repository() {
    log_info "Creating ECR repository with enhanced scanning..."
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name "${ECR_REPO_NAME}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=ECR \
        >> "${LOG_FILE}" 2>&1
    
    # Get repository URI
    local ecr_uri
    ecr_uri=$(aws ecr describe-repositories \
        --repository-names "${ECR_REPO_NAME}" \
        --query 'repositories[0].repositoryUri' \
        --output text)
    
    export ECR_URI="${ecr_uri}"
    echo "ECR_URI=${ECR_URI}" >> "${STATE_FILE}"
    
    log_success "ECR repository created: ${ECR_URI}"
}

# Function to configure enhanced scanning
configure_enhanced_scanning() {
    log_info "Configuring enhanced scanning..."
    
    # Enable enhanced scanning for the registry
    aws ecr put-registry-scanning-configuration \
        --scan-type ENHANCED \
        --rules '[
            {
                "scanFrequency": "CONTINUOUS_SCAN",
                "repositoryFilters": [
                    {
                        "filter": "*",
                        "filterType": "WILDCARD"
                    }
                ]
            }
        ]' >> "${LOG_FILE}" 2>&1
    
    log_success "Enhanced scanning configured"
}

# Function to create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for security alerts..."
    
    # Create SNS topic
    aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=SNS \
        >> "${LOG_FILE}" 2>&1
    
    # Get topic ARN
    local sns_topic_arn
    sns_topic_arn=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    export SNS_TOPIC_ARN="${sns_topic_arn}"
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${STATE_FILE}"
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for scan result processing..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/scan_processor.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    print("Processing security scan results...")
    
    # Parse ECR scan results from EventBridge
    detail = event.get('detail', {})
    repository_name = detail.get('repository-name', '')
    image_digest = detail.get('image-digest', '')
    finding_counts = detail.get('finding-severity-counts', {})
    
    # Create consolidated security report
    security_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'repository': repository_name,
        'image_digest': image_digest,
        'scan_results': {
            'ecr_enhanced': finding_counts,
            'total_vulnerabilities': finding_counts.get('TOTAL', 0),
            'critical_vulnerabilities': finding_counts.get('CRITICAL', 0),
            'high_vulnerabilities': finding_counts.get('HIGH', 0)
        }
    }
    
    # Determine risk level and actions
    critical_count = finding_counts.get('CRITICAL', 0)
    high_count = finding_counts.get('HIGH', 0)
    
    if critical_count > 0:
        risk_level = 'CRITICAL'
        action_required = 'IMMEDIATE_BLOCK'
    elif high_count > 5:
        risk_level = 'HIGH'
        action_required = 'REVIEW_REQUIRED'
    else:
        risk_level = 'LOW'
        action_required = 'MONITOR'
    
    security_report['risk_assessment'] = {
        'risk_level': risk_level,
        'action_required': action_required,
        'compliance_status': 'FAIL' if critical_count > 0 else 'PASS'
    }
    
    # Send to Security Hub
    securityhub = boto3.client('securityhub')
    try:
        securityhub.batch_import_findings(
            Findings=[{
                'SchemaVersion': '2018-10-08',
                'Id': f"{repository_name}-{image_digest}",
                'ProductArn': f"arn:aws:securityhub:{os.environ['AWS_REGION']}:{os.environ['AWS_ACCOUNT_ID']}:product/custom/container-security-scanner",
                'GeneratorId': 'container-security-pipeline',
                'AwsAccountId': os.environ['AWS_ACCOUNT_ID'],
                'Title': f"Container Security Scan - {repository_name}",
                'Description': f"Security scan completed for {repository_name}",
                'Severity': {
                    'Label': risk_level
                },
                'Resources': [{
                    'Type': 'AwsEcrContainerImage',
                    'Id': f"{repository_name}:{image_digest}",
                    'Region': os.environ['AWS_REGION']
                }]
            }]
        )
    except Exception as e:
        print(f"Error sending to Security Hub: {e}")
    
    # Trigger notifications based on risk level
    if risk_level in ['CRITICAL', 'HIGH']:
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(security_report, indent=2),
            Subject=f"Container Security Alert - {risk_level} Risk Detected"
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps(security_report)
    }
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip -q scan_processor.zip scan_processor.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler scan_processor.lambda_handler \
        --zip-file fileb://scan_processor.zip \
        --environment Variables='{"SNS_TOPIC_ARN":"'${SNS_TOPIC_ARN}'","AWS_REGION":"'${AWS_REGION}'","AWS_ACCOUNT_ID":"'${AWS_ACCOUNT_ID}'"}' \
        --tags Project="${PROJECT_NAME}",Component=Lambda \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log_info "Creating EventBridge rule for ECR scan events..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --event-pattern '{
            "source": ["aws.inspector2"],
            "detail-type": ["Inspector2 Scan"],
            "detail": {
                "scan-status": ["INITIAL_SCAN_COMPLETE"]
            }
        }' \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=EventBridge \
        >> "${LOG_FILE}" 2>&1
    
    # Add Lambda target
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        >> "${LOG_FILE}" 2>&1
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "AllowExecutionFromEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
}

# Function to create Config rule
create_config_rule() {
    log_info "Creating Config rule for ECR compliance..."
    
    # Create Config rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "'${CONFIG_RULE_NAME}'",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "ECR_PRIVATE_IMAGE_SCANNING_ENABLED"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::ECR::Repository"]
            }
        }' >> "${LOG_FILE}" 2>&1
    
    log_success "Config rule created: ${CONFIG_RULE_NAME}"
}

# Function to create CodeBuild project
create_codebuild_project() {
    log_info "Creating CodeBuild project for security scanning..."
    
    # Create buildspec.yml
    cat > "${TEMP_DIR}/buildspec.yml" << 'EOF'
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI
      - IMAGE_TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:-latest}
      - echo Build started on `date`
      - echo Building the Docker image...
      
  build:
    commands:
      # Build the container image
      - docker build -t $ECR_REPO_NAME:$IMAGE_TAG .
      - docker tag $ECR_REPO_NAME:$IMAGE_TAG $ECR_URI:$IMAGE_TAG
      
      # Run third-party security scans (if tools are configured)
      - echo "Running security scans..."
      - if [ -n "$SNYK_TOKEN" ]; then echo "Running Snyk scan..."; snyk container test $ECR_REPO_NAME:$IMAGE_TAG --severity-threshold=high --json > snyk-results.json || true; fi
      - if [ -n "$PRISMA_CONSOLE" ]; then echo "Running Prisma Cloud scan..."; ./twistcli images scan --details $ECR_REPO_NAME:$IMAGE_TAG --output-file prisma-results.json || true; fi
      
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker push $ECR_URI:$IMAGE_TAG
      
      # Wait for enhanced scanning to complete
      - echo "Waiting for ECR enhanced scanning..."
      - sleep 30
      
      # Get ECR scan results
      - aws ecr describe-image-scan-findings --repository-name $ECR_REPO_NAME --image-id imageTag=$IMAGE_TAG > ecr-scan-results.json || true
      
      # Log scan completion
      - echo "Security scanning pipeline completed"
      
artifacts:
  files:
    - '**/*'
EOF
    
    # Create CodeBuild project
    aws codebuild create-project \
        --name "${CODEBUILD_PROJECT_NAME}" \
        --source type=NO_SOURCE,buildspec="${TEMP_DIR}/buildspec.yml" \
        --artifacts type=NO_ARTIFACTS \
        --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_MEDIUM,privilegedMode=true \
        --service-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CODEBUILD_ROLE_NAME}" \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=CodeBuild \
        >> "${LOG_FILE}" 2>&1
    
    log_success "CodeBuild project created: ${CODEBUILD_PROJECT_NAME}"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard for security monitoring..."
    
    # Create dashboard configuration
    local dashboard_config
    dashboard_config=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ECR", "RepositoryCount"],
                    ["AWS/ECR", "ImageCount"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "ECR Repository Metrics"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}' | fields @timestamp, @message | filter @message like /CRITICAL/ | sort @timestamp desc | limit 20",
                "region": "${AWS_REGION}",
                "title": "Critical Security Findings"
            }
        }
    ]
}
EOF
)
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "${dashboard_config}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Function to deploy sample application
deploy_sample_application() {
    log_info "Deploying sample application for testing..."
    
    # Create sample Dockerfile
    cat > "${TEMP_DIR}/Dockerfile" << 'EOF'
FROM ubuntu:18.04

# Install packages with known vulnerabilities for testing
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    openssl \
    nodejs \
    npm

# Create application directory
WORKDIR /app

# Copy application files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Expose port
EXPOSE 3000

# Run application
CMD ["node", "app.js"]
EOF
    
    # Create sample package.json with vulnerable dependencies
    cat > "${TEMP_DIR}/package.json" << 'EOF'
{
    "name": "security-test-app",
    "version": "1.0.0",
    "description": "Test application for security scanning",
    "main": "app.js",
    "dependencies": {
        "express": "4.16.0",
        "lodash": "4.17.4",
        "request": "2.81.0"
    }
}
EOF
    
    # Create sample app.js
    cat > "${TEMP_DIR}/app.js" << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
    res.send('Hello from Security Test App!');
});

app.listen(port, () => {
    console.log(`App listening at http://localhost:${port}`);
});
EOF
    
    # Build and push test image
    cd "${TEMP_DIR}"
    docker build -t "${ECR_REPO_NAME}:test" .
    
    # Get ECR login token
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_URI}"
    
    # Tag and push image
    docker tag "${ECR_REPO_NAME}:test" "${ECR_URI}:test"
    docker push "${ECR_URI}:test"
    
    log_success "Sample application deployed for testing"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" &>/dev/null; then
        log_success "ECR repository validation passed"
    else
        log_error "ECR repository validation failed"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_success "Lambda function validation passed"
    else
        log_error "Lambda function validation failed"
        return 1
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        log_success "EventBridge rule validation passed"
    else
        log_error "EventBridge rule validation failed"
        return 1
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
        log_success "SNS topic validation passed"
    else
        log_error "SNS topic validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to print deployment summary
print_deployment_summary() {
    log_info "Deployment Summary"
    echo "========================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "ECR Repository: ${ECR_URI}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "========================================="
    echo ""
    echo "Next Steps:"
    echo "1. Configure third-party scanner credentials (Snyk, Prisma Cloud)"
    echo "2. Subscribe to SNS topic for security alerts"
    echo "3. Review CloudWatch dashboard for security metrics"
    echo "4. Test the pipeline by pushing container images"
    echo ""
    echo "State file saved to: ${STATE_FILE}"
    echo "Log file saved to: ${LOG_FILE}"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Deployment failed. Cleaning up resources..."
    if [ -f "${STATE_FILE}" ]; then
        source "${STATE_FILE}"
        "${SCRIPT_DIR}/destroy.sh"
    fi
}

# Main deployment function
main() {
    log_info "Starting Container Security Scanning Pipeline deployment..."
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_iam_roles
    create_iam_policies
    create_sns_topic
    create_lambda_function
    create_ecr_repository
    configure_enhanced_scanning
    create_eventbridge_rule
    create_config_rule
    create_codebuild_project
    create_cloudwatch_dashboard
    deploy_sample_application
    validate_deployment
    print_deployment_summary
    
    log_success "Container Security Scanning Pipeline deployed successfully!"
}

# Run main function
main "$@"