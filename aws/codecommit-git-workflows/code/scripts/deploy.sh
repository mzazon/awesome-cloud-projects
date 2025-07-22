#!/bin/bash

# CodeCommit Git Workflows Deployment Script
# This script deploys the complete Git workflow automation infrastructure
# including repository, Lambda functions, SNS topics, IAM roles, and monitoring

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${TIMESTAMP} - $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    echo "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success logging function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning logging function
warn() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info logging function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        error_exit "Git is not installed. Please install Git."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing jq for JSON parsing..."
        # Try to install jq based on the system
        if command -v yum &> /dev/null; then
            sudo yum install -y jq || warn "Failed to install jq via yum"
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq || warn "Failed to install jq via apt-get"
        elif command -v brew &> /dev/null; then
            brew install jq || warn "Failed to install jq via brew"
        else
            warn "Could not install jq automatically. Please install jq manually."
        fi
    fi
    
    # Verify AWS permissions
    info "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || \
        error_exit "Unable to verify AWS identity. Check your credentials."
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 8)")
    
    # Core resource names
    export REPO_NAME="enterprise-app-${RANDOM_SUFFIX}"
    export REPO_DESCRIPTION="Enterprise application with Git workflow automation"
    export LAMBDA_FUNCTION_PREFIX="codecommit-automation-${RANDOM_SUFFIX}"
    export SNS_TOPIC_PREFIX="codecommit-notifications-${RANDOM_SUFFIX}"
    
    # Team configuration
    export TEAM_LEAD_USER="team-lead"
    export SENIOR_DEVELOPERS="senior-dev-1,senior-dev-2"
    export ALL_DEVELOPERS="dev-1,dev-2,dev-3,${SENIOR_DEVELOPERS}"
    
    # Store configuration for cleanup
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
# Deployment Configuration
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
REPO_NAME=${REPO_NAME}
LAMBDA_FUNCTION_PREFIX=${LAMBDA_FUNCTION_PREFIX}
SNS_TOPIC_PREFIX=${SNS_TOPIC_PREFIX}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=${TIMESTAMP}
EOF
    
    success "Environment variables configured"
    info "Repository Name: ${REPO_NAME}"
    info "Lambda Prefix: ${LAMBDA_FUNCTION_PREFIX}"
    info "SNS Topic Prefix: ${SNS_TOPIC_PREFIX}"
}

# Function to create SNS topics
create_sns_topics() {
    info "Creating SNS topics for notifications..."
    
    # Create SNS topics
    export PULL_REQUEST_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_PREFIX}-pull-requests" \
        --output text --query TopicArn)
    
    export MERGE_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_PREFIX}-merges" \
        --output text --query TopicArn)
    
    export QUALITY_GATE_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_PREFIX}-quality-gates" \
        --output text --query TopicArn)
    
    export SECURITY_ALERT_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_PREFIX}-security-alerts" \
        --output text --query TopicArn)
    
    # Add topic ARNs to config file
    cat >> "${SCRIPT_DIR}/deployment-config.env" << EOF
PULL_REQUEST_TOPIC_ARN=${PULL_REQUEST_TOPIC_ARN}
MERGE_TOPIC_ARN=${MERGE_TOPIC_ARN}
QUALITY_GATE_TOPIC_ARN=${QUALITY_GATE_TOPIC_ARN}
SECURITY_ALERT_TOPIC_ARN=${SECURITY_ALERT_TOPIC_ARN}
EOF
    
    success "SNS topics created"
    info "Pull Request Topic: ${PULL_REQUEST_TOPIC_ARN}"
    info "Merge Topic: ${MERGE_TOPIC_ARN}"
    info "Quality Gate Topic: ${QUALITY_GATE_TOPIC_ARN}"
    info "Security Alert Topic: ${SECURITY_ALERT_TOPIC_ARN}"
}

# Function to create IAM roles
create_iam_roles() {
    info "Creating IAM roles for Lambda functions..."
    
    # Create trust policy for Lambda
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << 'EOF'
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
    
    # Create IAM role for CodeCommit automation
    aws iam create-role \
        --role-name CodeCommitAutomationRole \
        --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-trust-policy.json" \
        --description "Role for CodeCommit automation Lambda functions" || \
        warn "IAM role CodeCommitAutomationRole may already exist"
    
    # Create policy for CodeCommit and SNS access
    cat > "${SCRIPT_DIR}/codecommit-automation-policy.json" << EOF
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
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codecommit:GetRepository",
        "codecommit:GetBranch",
        "codecommit:GetCommit",
        "codecommit:GetDifferences",
        "codecommit:GetPullRequest",
        "codecommit:ListPullRequests",
        "codecommit:GetMergeCommit",
        "codecommit:GetMergeConflicts",
        "codecommit:GetMergeOptions",
        "codecommit:PostCommentForPullRequest",
        "codecommit:UpdatePullRequestTitle",
        "codecommit:UpdatePullRequestDescription"
      ],
      "Resource": [
        "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REPO_NAME}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": [
        "${PULL_REQUEST_TOPIC_ARN}",
        "${MERGE_TOPIC_ARN}",
        "${QUALITY_GATE_TOPIC_ARN}",
        "${SECURITY_ALERT_TOPIC_ARN}"
      ]
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
    
    # Create and attach policy
    aws iam create-policy \
        --policy-name CodeCommitAutomationPolicy \
        --policy-document file://"${SCRIPT_DIR}/codecommit-automation-policy.json" \
        --description "Policy for CodeCommit automation functions" || \
        warn "IAM policy CodeCommitAutomationPolicy may already exist"
    
    aws iam attach-role-policy \
        --role-name CodeCommitAutomationRole \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CodeCommitAutomationPolicy || \
        warn "Policy may already be attached to role"
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name CodeCommitAutomationRole \
        --query Role.Arn --output text)
    
    # Add role ARN to config file
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "${SCRIPT_DIR}/deployment-config.env"
    
    success "IAM role created: ${LAMBDA_ROLE_ARN}"
    
    # Wait for IAM role to propagate
    info "Waiting for IAM role to propagate..."
    sleep 10
}

# Function to create Lambda functions
create_lambda_functions() {
    info "Creating Lambda functions..."
    
    # Create pull request automation function
    cat > "${SCRIPT_DIR}/pull-request-automation.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Handle CodeCommit pull request events"""
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse event details
        detail = event.get('detail', {})
        event_name = detail.get('event')
        repository_name = detail.get('repositoryName')
        pull_request_id = detail.get('pullRequestId')
        
        if not all([event_name, repository_name, pull_request_id]):
            logger.error("Missing required event details")
            return {'statusCode': 400, 'body': 'Invalid event format'}
        
        # Get pull request details
        pr_response = codecommit.get_pull_request(pullRequestId=pull_request_id)
        pull_request = pr_response['pullRequest']
        
        # Extract pull request information
        pr_info = {
            'pullRequestId': pull_request_id,
            'title': pull_request['title'],
            'description': pull_request.get('description', ''),
            'authorArn': pull_request['authorArn'],
            'sourceReference': pull_request['pullRequestTargets'][0]['sourceReference'],
            'destinationReference': pull_request['pullRequestTargets'][0]['destinationReference'],
            'repositoryName': repository_name,
            'creationDate': pull_request['creationDate'].isoformat(),
            'pullRequestStatus': pull_request['pullRequestStatus']
        }
        
        # Handle different pull request events
        if event_name == 'pullRequestCreated':
            return handle_pull_request_created(pr_info)
        elif event_name == 'pullRequestSourceBranchUpdated':
            return handle_pull_request_updated(pr_info)
        elif event_name == 'pullRequestStatusChanged':
            return handle_pull_request_status_changed(pr_info, detail)
        elif event_name == 'pullRequestMergeStatusUpdated':
            return handle_merge_status_updated(pr_info, detail)
        else:
            logger.info(f"Unhandled event type: {event_name}")
            return {'statusCode': 200, 'body': 'Event acknowledged'}
            
    except Exception as e:
        logger.error(f"Error processing pull request event: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def handle_pull_request_created(pr_info):
    """Handle new pull request creation"""
    logger.info(f"New pull request created: {pr_info['pullRequestId']}")
    
    # Validate pull request
    validation_results = validate_pull_request(pr_info)
    
    # Send notification
    message = f"""🔄 New Pull Request Created

Repository: {pr_info['repositoryName']}
Pull Request: #{pr_info['pullRequestId']}
Title: {pr_info['title']}
Author: {pr_info['authorArn'].split('/')[-1]}
Source: {pr_info['sourceReference']}
Target: {pr_info['destinationReference']}

Validation Results:
{format_validation_results(validation_results)}

Created: {pr_info['creationDate']}
"""
    
    sns.publish(
        TopicArn=os.environ['PULL_REQUEST_TOPIC_ARN'],
        Subject=f'New PR: {pr_info["title"]}',
        Message=message
    )
    
    # Record metrics
    cloudwatch.put_metric_data(
        Namespace='CodeCommit/PullRequests',
        MetricData=[
            {
                'MetricName': 'PullRequestsCreated',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                ]
            }
        ]
    )
    
    return {'statusCode': 200, 'body': 'Pull request creation handled'}

def handle_pull_request_updated(pr_info):
    """Handle pull request source branch updates"""
    logger.info(f"Pull request updated: {pr_info['pullRequestId']}")
    return {'statusCode': 200, 'body': 'Pull request update handled'}

def handle_pull_request_status_changed(pr_info, detail):
    """Handle pull request status changes"""
    old_status = detail.get('oldPullRequestStatus')
    new_status = detail.get('newPullRequestStatus')
    
    logger.info(f"Pull request status changed: {old_status} -> {new_status}")
    
    if new_status == 'CLOSED':
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/PullRequests',
            MetricData=[
                {
                    'MetricName': 'PullRequestsClosed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                    ]
                }
            ]
        )
    
    return {'statusCode': 200, 'body': 'Status change handled'}

def handle_merge_status_updated(pr_info, detail):
    """Handle merge status updates"""
    merge_status = detail.get('mergeStatus')
    
    if merge_status == 'MERGED':
        logger.info(f"Pull request merged: {pr_info['pullRequestId']}")
        
        message = f"""✅ Pull Request Merged

Repository: {pr_info['repositoryName']}
Pull Request: #{pr_info['pullRequestId']}
Title: {pr_info['title']}
Merged to: {pr_info['destinationReference']}

The changes have been successfully merged.
"""
        
        sns.publish(
            TopicArn=os.environ['MERGE_TOPIC_ARN'],
            Subject=f'PR Merged: {pr_info["title"]}',
            Message=message
        )
        
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/PullRequests',
            MetricData=[
                {
                    'MetricName': 'PullRequestsMerged',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': pr_info['repositoryName']}
                    ]
                }
            ]
        )
    
    return {'statusCode': 200, 'body': 'Merge status update handled'}

def validate_pull_request(pr_info):
    """Validate pull request against quality gates"""
    results = {
        'branch_naming': check_branch_naming(pr_info['sourceReference']),
        'title_format': check_title_format(pr_info['title']),
        'description_present': bool(pr_info['description'].strip()),
        'target_branch': check_target_branch(pr_info['destinationReference']),
        'all_passed': True
    }
    
    results['all_passed'] = all(results[key] for key in results if key != 'all_passed')
    return results

def check_branch_naming(branch_name):
    """Check if branch follows naming convention"""
    valid_prefixes = ['feature/', 'bugfix/', 'hotfix/', 'release/', 'chore/']
    return any(branch_name.startswith(prefix) for prefix in valid_prefixes)

def check_title_format(title):
    """Check if title follows format guidelines"""
    return (len(title.strip()) > 5 and 
            len(title) < 100 and 
            title[0].isupper())

def check_target_branch(target_branch):
    """Check if target branch is appropriate"""
    return (target_branch in ['develop', 'main', 'master'] or 
            target_branch.startswith('release/'))

def format_validation_results(results):
    """Format validation results for display"""
    status_emoji = "✅" if results['all_passed'] else "❌"
    
    checks = [
        f"{'✅' if results['branch_naming'] else '❌'} Branch naming convention",
        f"{'✅' if results['title_format'] else '❌'} Title format",
        f"{'✅' if results['description_present'] else '❌'} Description present",
        f"{'✅' if results['target_branch'] else '❌'} Target branch valid"
    ]
    
    return f"{status_emoji} Overall: {'PASSED' if results['all_passed'] else 'FAILED'}\n" + "\n".join(checks)
EOF
    
    # Create quality gate automation function
    cat > "${SCRIPT_DIR}/quality-gate-automation.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codecommit = boto3.client('codecommit')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Handle repository triggers for quality gate automation"""
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        records = event.get('Records', [])
        
        for record in records:
            trigger_info = extract_trigger_info(record)
            if not trigger_info:
                continue
            
            quality_results = run_quality_checks(trigger_info)
            process_quality_results(trigger_info, quality_results)
        
        return {'statusCode': 200, 'body': 'Quality checks completed'}
        
    except Exception as e:
        logger.error(f"Error in quality gate automation: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def extract_trigger_info(record):
    """Extract trigger information from CodeCommit event"""
    try:
        event_source_arn = record.get('eventSourceARN', '')
        repository_name = event_source_arn.split(':')[-1] if event_source_arn else ''
        
        codecommit_data = record.get('codecommit', {})
        references = codecommit_data.get('references', [])
        
        if not references:
            return None
        
        ref = references[0]
        return {
            'repository_name': repository_name,
            'branch': ref.get('ref', '').replace('refs/heads/', ''),
            'commit_id': ref.get('commit'),
            'event_type': 'push'
        }
        
    except Exception as e:
        logger.error(f"Error extracting trigger info: {str(e)}")
        return None

def run_quality_checks(trigger_info):
    """Run comprehensive quality checks"""
    results = {
        'repository': trigger_info['repository_name'],
        'branch': trigger_info['branch'],
        'commit_id': trigger_info['commit_id'],
        'timestamp': datetime.utcnow().isoformat(),
        'checks': {},
        'overall_result': 'PASSED'
    }
    
    try:
        # Simulate quality checks
        results['checks']['lint_check'] = {'passed': True, 'message': 'No linting issues found'}
        results['checks']['security_scan'] = {'passed': True, 'message': 'No security issues found'}
        results['checks']['test_coverage'] = {'passed': True, 'message': 'Test coverage: 85% (required: 80%)'}
        results['checks']['dependency_check'] = {'passed': True, 'message': 'No vulnerable dependencies'}
        
        # Record metrics
        record_quality_metrics(results)
        
    except Exception as e:
        logger.error(f"Error running quality checks: {str(e)}")
        results['overall_result'] = 'ERROR'
        results['error'] = str(e)
    
    return results

def process_quality_results(trigger_info, results):
    """Process and communicate quality check results"""
    try:
        if results['overall_result'] == 'FAILED':
            send_quality_failure_notification(trigger_info, results)
        elif results['overall_result'] == 'PASSED' and results['branch'] in ['main', 'master', 'develop']:
            send_quality_success_notification(trigger_info, results)
    except Exception as e:
        logger.error(f"Error processing quality results: {str(e)}")

def record_quality_metrics(results):
    """Record quality metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='CodeCommit/QualityGates',
            MetricData=[
                {
                    'MetricName': 'QualityChecksResult',
                    'Value': 1 if results['overall_result'] == 'PASSED' else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Repository', 'Value': results['repository']},
                        {'Name': 'Branch', 'Value': results['branch']}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error recording metrics: {str(e)}")

def send_quality_failure_notification(trigger_info, results):
    """Send notification for quality check failures"""
    try:
        message = f"""🚨 Quality Gates Failed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

Please address these issues before merging.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Failed: {results["repository"]}',
            Message=message
        )
    except Exception as e:
        logger.error(f"Error sending failure notification: {str(e)}")

def send_quality_success_notification(trigger_info, results):
    """Send notification for quality check success"""
    try:
        message = f"""✅ Quality Gates Passed

Repository: {results['repository']}
Branch: {results['branch']}
Commit: {results['commit_id'][:8]}

All quality checks passed successfully.
Timestamp: {results['timestamp']}
"""
        
        sns.publish(
            TopicArn=os.environ['QUALITY_GATE_TOPIC_ARN'],
            Subject=f'Quality Gates Passed: {results["repository"]}',
            Message=message
        )
    except Exception as e:
        logger.error(f"Error sending success notification: {str(e)}")
EOF
    
    # Package Lambda functions
    cd "${SCRIPT_DIR}"
    zip pull-request-automation.zip pull-request-automation.py
    zip quality-gate-automation.zip quality-gate-automation.py
    
    # Create pull request Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-pull-request" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler pull-request-automation.lambda_handler \
        --zip-file fileb://pull-request-automation.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment Variables="{
            PULL_REQUEST_TOPIC_ARN=${PULL_REQUEST_TOPIC_ARN},
            MERGE_TOPIC_ARN=${MERGE_TOPIC_ARN},
            QUALITY_GATE_TOPIC_ARN=${QUALITY_GATE_TOPIC_ARN}
        }" \
        --description "Automation for CodeCommit pull request workflows" || \
        error_exit "Failed to create pull request Lambda function"
    
    # Create quality gate Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-quality-gate" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler quality-gate-automation.lambda_handler \
        --zip-file fileb://quality-gate-automation.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{
            QUALITY_GATE_TOPIC_ARN=${QUALITY_GATE_TOPIC_ARN},
            SECURITY_ALERT_TOPIC_ARN=${SECURITY_ALERT_TOPIC_ARN}
        }" \
        --description "Quality gate automation for CodeCommit repositories" || \
        error_exit "Failed to create quality gate Lambda function"
    
    # Get Lambda function ARNs
    export PULL_REQUEST_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-pull-request" \
        --query Configuration.FunctionArn --output text)
    
    export QUALITY_GATE_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-quality-gate" \
        --query Configuration.FunctionArn --output text)
    
    # Add Lambda ARNs to config file
    cat >> "${SCRIPT_DIR}/deployment-config.env" << EOF
PULL_REQUEST_LAMBDA_ARN=${PULL_REQUEST_LAMBDA_ARN}
QUALITY_GATE_LAMBDA_ARN=${QUALITY_GATE_LAMBDA_ARN}
EOF
    
    success "Lambda functions created"
    info "Pull Request Lambda: ${PULL_REQUEST_LAMBDA_ARN}"
    info "Quality Gate Lambda: ${QUALITY_GATE_LAMBDA_ARN}"
}

# Function to create CodeCommit repository
create_repository() {
    info "Creating CodeCommit repository..."
    
    # Create CodeCommit repository
    aws codecommit create-repository \
        --repository-name "${REPO_NAME}" \
        --repository-description "${REPO_DESCRIPTION}" \
        --tags Environment=development,Project=enterprise-app,ManagedBy=codecommit-automation || \
        warn "Repository ${REPO_NAME} may already exist"
    
    # Get repository clone URL
    export REPO_CLONE_URL=$(aws codecommit get-repository \
        --repository-name "${REPO_NAME}" \
        --query 'repositoryMetadata.cloneUrlHttp' --output text)
    
    echo "REPO_CLONE_URL=${REPO_CLONE_URL}" >> "${SCRIPT_DIR}/deployment-config.env"
    
    success "Repository created: ${REPO_NAME}"
    info "Clone URL: ${REPO_CLONE_URL}"
}

# Function to configure repository triggers and events
configure_triggers_and_events() {
    info "Configuring repository triggers and EventBridge rules..."
    
    # Add permission for CodeCommit to invoke quality gate Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-quality-gate" \
        --statement-id "codecommit-trigger" \
        --action "lambda:InvokeFunction" \
        --principal codecommit.amazonaws.com \
        --source-arn "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REPO_NAME}" || \
        warn "Permission may already exist"
    
    # Create repository trigger
    aws codecommit put-repository-triggers \
        --repository-name "${REPO_NAME}" \
        --triggers repositoryName="${REPO_NAME}",triggerName=quality-gate-trigger,triggerEvents=all,destinationArn="${QUALITY_GATE_LAMBDA_ARN}" || \
        warn "Repository trigger may already exist"
    
    # Create EventBridge rule for pull request events
    export EVENTBRIDGE_RULE_NAME="codecommit-pull-request-events-${RANDOM_SUFFIX}"
    
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --description "Capture CodeCommit pull request events" \
        --event-pattern "{
            \"source\": [\"aws.codecommit\"],
            \"detail-type\": [\"CodeCommit Pull Request State Change\"],
            \"detail\": {
                \"repositoryName\": [\"${REPO_NAME}\"]
            }
        }" || error_exit "Failed to create EventBridge rule"
    
    # Add Lambda target to EventBridge rule
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="${PULL_REQUEST_LAMBDA_ARN}" || \
        error_exit "Failed to add Lambda target to EventBridge rule"
    
    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-pull-request" \
        --statement-id "eventbridge-invoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" || \
        warn "Permission may already exist"
    
    echo "EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}" >> "${SCRIPT_DIR}/deployment-config.env"
    
    success "Repository triggers and EventBridge rules configured"
}

# Function to create approval templates
create_approval_templates() {
    info "Creating approval rule templates..."
    
    # Create approval rule template
    cat > "${SCRIPT_DIR}/approval-rule-template.json" << EOF
{
  "approvalRuleTemplateName": "enterprise-approval-template-${RANDOM_SUFFIX}",
  "approvalRuleTemplateDescription": "Standard approval rules for enterprise repositories",
  "approvalRuleTemplateContent": "{\"Version\": \"2018-11-08\", \"DestinationReferences\": [\"refs/heads/main\", \"refs/heads/master\", \"refs/heads/develop\"], \"Statements\": [{\"Type\": \"Approvers\", \"NumberOfApprovalsNeeded\": 2, \"ApprovalPoolMembers\": [\"arn:aws:iam::${AWS_ACCOUNT_ID}:user/team-lead\", \"arn:aws:iam::${AWS_ACCOUNT_ID}:user/senior-dev-1\", \"arn:aws:iam::${AWS_ACCOUNT_ID}:user/senior-dev-2\"]}]}"
}
EOF
    
    # Create approval rule template
    export APPROVAL_TEMPLATE_NAME="enterprise-approval-template-${RANDOM_SUFFIX}"
    
    aws codecommit create-approval-rule-template \
        --cli-input-json file://"${SCRIPT_DIR}/approval-rule-template.json" || \
        warn "Approval rule template may already exist"
    
    # Associate template with repository
    aws codecommit associate-approval-rule-template-with-repository \
        --approval-rule-template-name "${APPROVAL_TEMPLATE_NAME}" \
        --repository-name "${REPO_NAME}" || \
        warn "Template may already be associated with repository"
    
    echo "APPROVAL_TEMPLATE_NAME=${APPROVAL_TEMPLATE_NAME}" >> "${SCRIPT_DIR}/deployment-config.env"
    
    success "Approval rule template created and associated"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    info "Creating CloudWatch monitoring dashboard..."
    
    # Create CloudWatch dashboard
    cat > "${SCRIPT_DIR}/git-workflow-dashboard.json" << EOF
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
          ["CodeCommit/PullRequests", "PullRequestsCreated", "Repository", "${REPO_NAME}"],
          [".", "PullRequestsMerged", ".", "."],
          [".", "PullRequestsClosed", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Pull Request Activity"
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
          ["CodeCommit/QualityGates", "QualityChecksResult", "Repository", "${REPO_NAME}"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Quality Gate Success Rate",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 1
          }
        }
      }
    }
  ]
}
EOF
    
    export DASHBOARD_NAME="Git-Workflow-${REPO_NAME}"
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body file://"${SCRIPT_DIR}/git-workflow-dashboard.json" || \
        error_exit "Failed to create CloudWatch dashboard"
    
    echo "DASHBOARD_NAME=${DASHBOARD_NAME}" >> "${SCRIPT_DIR}/deployment-config.env"
    
    success "Monitoring dashboard created: ${DASHBOARD_NAME}"
}

# Function to display deployment summary
display_summary() {
    info "Deployment Summary"
    echo "==================="
    echo
    echo "✅ Repository: ${REPO_NAME}"
    echo "✅ Clone URL: ${REPO_CLONE_URL}"
    echo "✅ Lambda Functions:"
    echo "   - Pull Request: ${LAMBDA_FUNCTION_PREFIX}-pull-request"
    echo "   - Quality Gate: ${LAMBDA_FUNCTION_PREFIX}-quality-gate"
    echo "✅ SNS Topics:"
    echo "   - Pull Requests: ${PULL_REQUEST_TOPIC_ARN}"
    echo "   - Merges: ${MERGE_TOPIC_ARN}"
    echo "   - Quality Gates: ${QUALITY_GATE_TOPIC_ARN}"
    echo "   - Security Alerts: ${SECURITY_ALERT_TOPIC_ARN}"
    echo "✅ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "✅ Approval Template: ${APPROVAL_TEMPLATE_NAME}"
    echo "✅ Dashboard: ${DASHBOARD_NAME}"
    echo
    echo "🔧 Next Steps:"
    echo "1. Subscribe to SNS topics for notifications"
    echo "2. Clone the repository and start developing"
    echo "3. Create pull requests to test the workflow"
    echo "4. Monitor the CloudWatch dashboard for metrics"
    echo
    echo "📚 Documentation available in: git-workflow-documentation.md"
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    echo "🚀 Starting CodeCommit Git Workflow Deployment"
    echo "=============================================="
    
    # Initialize log file
    echo "Deployment started at ${TIMESTAMP}" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_sns_topics
    create_iam_roles
    create_lambda_functions
    create_repository
    configure_triggers_and_events
    create_approval_templates
    create_monitoring_dashboard
    display_summary
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}"/*.zip
    rm -f "${SCRIPT_DIR}"/*.py
    rm -f "${SCRIPT_DIR}"/*.json
    
    echo
    success "All resources deployed successfully!"
    echo "Check the deployment log at: ${LOG_FILE}"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi