#!/bin/bash

# Deploy script for Scheduled Email Reports with App Runner and SES
# Recipe: Delivering Scheduled Reports with App Runner and SES
# Version: 1.0

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' is not installed"
        return 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        echo "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required commands
    check_command aws || exit 1
    check_command git || exit 1
    check_command jq || exit 1
    check_command curl || exit 1
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS_REGION not configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export APP_RUNNER_SERVICE_NAME="email-reports-service-${RANDOM_SUFFIX}"
    export SCHEDULE_NAME="daily-report-schedule-${RANDOM_SUFFIX}"
    export ROLE_NAME="AppRunnerEmailReportsRole-${RANDOM_SUFFIX}"
    export SCHEDULER_ROLE_NAME="EventBridgeSchedulerRole-${RANDOM_SUFFIX}"
    
    # Prompt for SES verified email if not set
    if [ -z "${SES_VERIFIED_EMAIL:-}" ]; then
        echo -n "Enter your verified SES email address: "
        read SES_VERIFIED_EMAIL
        export SES_VERIFIED_EMAIL
    fi
    
    # Prompt for GitHub repository URL if not set
    if [ -z "${GITHUB_REPO_URL:-}" ]; then
        echo -n "Enter your GitHub repository URL (e.g., https://github.com/username/email-reports-app): "
        read GITHUB_REPO_URL
        export GITHUB_REPO_URL
    fi
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    log "  Service Name: $APP_RUNNER_SERVICE_NAME"
    log "  SES Email: $SES_VERIFIED_EMAIL"
    log "  GitHub Repo: $GITHUB_REPO_URL"
}

# Function to create the Flask application files
create_application_files() {
    log "Creating Flask application files..."
    
    # Create project directory
    mkdir -p email-reports-app
    cd email-reports-app
    
    # Create main application file
    cat > app.py << 'EOF'
from flask import Flask, request, jsonify
import boto3
import json
import logging
from datetime import datetime
import os

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize AWS clients
ses_client = boto3.client('ses')
cloudwatch = boto3.client('cloudwatch')

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/generate-report', methods=['POST'])
def generate_report():
    try:
        # Generate sample business report
        report_data = {
            'date': datetime.now().strftime('%Y-%m-%d'),
            'total_users': 1250,
            'active_sessions': 892,
            'revenue': 45780.50,
            'conversion_rate': 3.2
        }
        
        # Create HTML email content
        html_body = f"""
        <html>
        <body>
            <h2>Daily Business Report - {report_data['date']}</h2>
            <table border="1" style="border-collapse: collapse;">
                <tr><td><strong>Total Users</strong></td><td>{report_data['total_users']}</td></tr>
                <tr><td><strong>Active Sessions</strong></td><td>{report_data['active_sessions']}</td></tr>
                <tr><td><strong>Revenue</strong></td><td>${report_data['revenue']:,.2f}</td></tr>
                <tr><td><strong>Conversion Rate</strong></td><td>{report_data['conversion_rate']}%</td></tr>
            </table>
        </body>
        </html>
        """
        
        # Send email via SES
        response = ses_client.send_email(
            Source=os.environ.get('SES_VERIFIED_EMAIL'),
            Destination={'ToAddresses': [os.environ.get('SES_VERIFIED_EMAIL')]},
            Message={
                'Subject': {'Data': f'Daily Business Report - {report_data["date"]}'},
                'Body': {'Html': {'Data': html_body}}
            }
        )
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='EmailReports',
            MetricData=[
                {
                    'MetricName': 'ReportsGenerated',
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        logging.info(f"Report sent successfully. MessageId: {response['MessageId']}")
        return jsonify({'status': 'success', 'message_id': response['MessageId']})
        
    except Exception as e:
        logging.error(f"Error generating report: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["python", "app.py"]
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==2.3.3
boto3==1.34.0
EOF
    
    # Create App Runner configuration
    cat > apprunner.yaml << 'EOF'
version: 1.0
runtime: python3
build:
  commands:
    build:
      - pip install -r requirements.txt
run:
  runtime-version: 3.9
  command: python app.py
  network:
    port: 8000
EOF
    
    success "Flask application files created"
}

# Function to set up Git repository (if not already exists)
setup_git_repository() {
    log "Setting up Git repository..."
    
    if [ ! -d ".git" ]; then
        git init
        git add .
        git commit -m "Initial commit: Email reports application"
        success "Git repository initialized"
    else
        log "Git repository already exists, skipping initialization"
    fi
    
    cd ..
}

# Function to create IAM role for App Runner
create_app_runner_role() {
    log "Creating IAM role for App Runner..."
    
    # Create trust policy
    cat > trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "tasks.apprunner.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create permissions policy
    cat > permissions-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail"
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
    
    # Create IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "IAM role $ROLE_NAME already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file://trust-policy.json
        
        # Attach permissions policy
        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name EmailReportsPolicy \
            --policy-document file://permissions-policy.json
        
        # Wait for role to be available
        sleep 10
        success "IAM role created: $ROLE_NAME"
    fi
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    log "Role ARN: $ROLE_ARN"
    
    # Cleanup temporary files
    rm -f trust-policy.json permissions-policy.json
}

# Function to verify SES email
verify_ses_email() {
    log "Setting up SES email verification..."
    
    # Check if email is already verified
    VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
        --identities "$SES_VERIFIED_EMAIL" \
        --query "VerificationAttributes.\"$SES_VERIFIED_EMAIL\".VerificationStatus" \
        --output text 2>/dev/null || echo "NotFound")
    
    if [ "$VERIFICATION_STATUS" = "Success" ]; then
        success "Email $SES_VERIFIED_EMAIL is already verified"
    else
        log "Sending verification email to $SES_VERIFIED_EMAIL"
        aws ses verify-email-identity --email-address "$SES_VERIFIED_EMAIL"
        
        warning "Please check your email ($SES_VERIFIED_EMAIL) and click the verification link"
        echo -n "Press Enter after verifying your email address..."
        read
        
        # Check verification status again
        VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
            --identities "$SES_VERIFIED_EMAIL" \
            --query "VerificationAttributes.\"$SES_VERIFIED_EMAIL\".VerificationStatus" \
            --output text)
        
        if [ "$VERIFICATION_STATUS" = "Success" ]; then
            success "Email verification completed"
        else
            error "Email verification failed or not completed. Status: $VERIFICATION_STATUS"
            exit 1
        fi
    fi
}

# Function to create App Runner service
create_app_runner_service() {
    log "Creating App Runner service..."
    
    # Check if service already exists
    if aws apprunner describe-service --service-name "$APP_RUNNER_SERVICE_NAME" &>/dev/null; then
        log "App Runner service $APP_RUNNER_SERVICE_NAME already exists, skipping creation"
        SERVICE_URL=$(aws apprunner describe-service \
            --service-name "$APP_RUNNER_SERVICE_NAME" \
            --query 'Service.ServiceUrl' --output text)
    else
        # Create service configuration
        cat > service-config.json << EOF
{
    "ServiceName": "$APP_RUNNER_SERVICE_NAME",
    "SourceConfiguration": {
        "CodeRepository": {
            "RepositoryUrl": "$GITHUB_REPO_URL",
            "SourceCodeVersion": {
                "Type": "BRANCH",
                "Value": "main"
            },
            "CodeConfiguration": {
                "ConfigurationSource": "REPOSITORY"
            }
        },
        "AutoDeploymentsEnabled": true
    },
    "InstanceConfiguration": {
        "Cpu": "0.25 vCPU",
        "Memory": "0.5 GB",
        "InstanceRoleArn": "$ROLE_ARN",
        "EnvironmentVariables": {
            "SES_VERIFIED_EMAIL": "$SES_VERIFIED_EMAIL"
        }
    },
    "HealthCheckConfiguration": {
        "Protocol": "HTTP",
        "Path": "/health",
        "Interval": 10,
        "Timeout": 5,
        "HealthyThreshold": 1,
        "UnhealthyThreshold": 5
    }
}
EOF
        
        # Create App Runner service
        aws apprunner create-service --cli-input-json file://service-config.json
        
        log "Waiting for App Runner service to be ready (this may take several minutes)..."
        aws apprunner wait service-running --service-name "$APP_RUNNER_SERVICE_NAME"
        
        # Get service URL
        SERVICE_URL=$(aws apprunner describe-service \
            --service-name "$APP_RUNNER_SERVICE_NAME" \
            --query 'Service.ServiceUrl' --output text)
        
        success "App Runner service created successfully"
        rm -f service-config.json
    fi
    
    export SERVICE_URL
    log "Service URL: https://$SERVICE_URL"
}

# Function to create EventBridge Scheduler role
create_scheduler_role() {
    log "Creating IAM role for EventBridge Scheduler..."
    
    # Create trust policy
    cat > scheduler-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "scheduler.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create permissions policy
    cat > scheduler-permissions-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "events:InvokeFunction"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create IAM role
    if aws iam get-role --role-name "$SCHEDULER_ROLE_NAME" &>/dev/null; then
        log "Scheduler IAM role $SCHEDULER_ROLE_NAME already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "$SCHEDULER_ROLE_NAME" \
            --assume-role-policy-document file://scheduler-trust-policy.json
        
        # Attach permissions policy
        aws iam put-role-policy \
            --role-name "$SCHEDULER_ROLE_NAME" \
            --policy-name SchedulerHttpPolicy \
            --policy-document file://scheduler-permissions-policy.json
        
        # Wait for role to be available
        sleep 10
        success "Scheduler IAM role created: $SCHEDULER_ROLE_NAME"
    fi
    
    # Get scheduler role ARN
    export SCHEDULER_ROLE_ARN=$(aws iam get-role --role-name "$SCHEDULER_ROLE_NAME" --query 'Role.Arn' --output text)
    log "Scheduler Role ARN: $SCHEDULER_ROLE_ARN"
    
    # Cleanup temporary files
    rm -f scheduler-trust-policy.json scheduler-permissions-policy.json
}

# Function to create EventBridge Schedule
create_eventbridge_schedule() {
    log "Creating EventBridge Schedule..."
    
    # Check if schedule already exists
    if aws scheduler get-schedule --name "$SCHEDULE_NAME" &>/dev/null; then
        log "EventBridge Schedule $SCHEDULE_NAME already exists, skipping creation"
    else
        # Create schedule configuration
        cat > schedule-config.json << EOF
{
    "Name": "$SCHEDULE_NAME",
    "ScheduleExpression": "cron(0 9 * * ? *)",
    "ScheduleExpressionTimezone": "UTC",
    "Description": "Daily email report generation",
    "State": "ENABLED",
    "FlexibleTimeWindow": {
        "Mode": "OFF"
    },
    "Target": {
        "Arn": "arn:aws:scheduler:::http-invoke",
        "RoleArn": "$SCHEDULER_ROLE_ARN",
        "HttpParameters": {
            "HttpMethod": "POST",
            "Url": "https://$SERVICE_URL/generate-report",
            "PathParameterValues": {},
            "QueryStringParameters": {},
            "HeaderParameters": {
                "Content-Type": "application/json"
            }
        }
    },
    "RetryPolicy": {
        "MaximumRetryAttempts": 3,
        "MaximumEventAge": 86400
    }
}
EOF
        
        # Create the schedule
        aws scheduler create-schedule --cli-input-json file://schedule-config.json
        success "EventBridge Schedule created: $SCHEDULE_NAME"
        rm -f schedule-config.json
    fi
}

# Function to configure CloudWatch monitoring
configure_cloudwatch_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch alarm
    ALARM_NAME="EmailReports-GenerationFailures-${RANDOM_SUFFIX}"
    if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" &>/dev/null | grep -q "MetricAlarms"; then
        log "CloudWatch alarm $ALARM_NAME already exists, skipping creation"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$ALARM_NAME" \
            --alarm-description "Alert when email report generation fails" \
            --metric-name ReportsGenerated \
            --namespace EmailReports \
            --statistic Sum \
            --period 3600 \
            --threshold 1 \
            --comparison-operator LessThanThreshold \
            --evaluation-periods 1 \
            --treat-missing-data notBreaching
        
        success "CloudWatch alarm created: $ALARM_NAME"
    fi
    
    # Create CloudWatch dashboard
    DASHBOARD_NAME="EmailReports-Dashboard-${RANDOM_SUFFIX}"
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["EmailReports", "ReportsGenerated"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Email Reports Generated"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/apprunner/$APP_RUNNER_SERVICE_NAME' | fields @timestamp, @message | filter @message like /Report sent successfully/ | sort @timestamp desc | limit 20",
                "region": "$AWS_REGION",
                "title": "Recent Report Generation Success"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file://dashboard-config.json
    
    success "CloudWatch dashboard created: $DASHBOARD_NAME"
    rm -f dashboard-config.json
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test health endpoint
    log "Testing health endpoint..."
    if curl -f -s "https://$SERVICE_URL/health" | jq -e '.status == "healthy"' > /dev/null; then
        success "Health endpoint is working"
    else
        error "Health endpoint test failed"
        return 1
    fi
    
    # Test report generation endpoint
    log "Testing report generation endpoint..."
    RESPONSE=$(curl -s -X POST "https://$SERVICE_URL/generate-report" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null; then
        success "Report generation endpoint is working"
        log "Check your email ($SES_VERIFIED_EMAIL) for the test report"
    else
        error "Report generation test failed: $RESPONSE"
        return 1
    fi
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "app_runner_service_name": "$APP_RUNNER_SERVICE_NAME",
    "service_url": "https://$SERVICE_URL",
    "ses_verified_email": "$SES_VERIFIED_EMAIL",
    "github_repo_url": "$GITHUB_REPO_URL",
    "schedule_name": "$SCHEDULE_NAME",
    "role_name": "$ROLE_NAME",
    "scheduler_role_name": "$SCHEDULER_ROLE_NAME",
    "cloudwatch_alarm": "EmailReports-GenerationFailures-${RANDOM_SUFFIX}",
    "cloudwatch_dashboard": "EmailReports-Dashboard-${RANDOM_SUFFIX}"
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Successfully deployed Scheduled Email Reports with App Runner and SES${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Service Details:${NC}"
    echo "  🌐 Service URL: https://$SERVICE_URL"
    echo "  📧 SES Email: $SES_VERIFIED_EMAIL"
    echo "  📅 Schedule: Daily at 9:00 AM UTC"
    echo "  🔧 Service Name: $APP_RUNNER_SERVICE_NAME"
    echo ""
    echo -e "${BLUE}Endpoints:${NC}"
    echo "  Health Check: https://$SERVICE_URL/health"
    echo "  Generate Report: https://$SERVICE_URL/generate-report (POST)"
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo "  CloudWatch Dashboard: EmailReports-Dashboard-${RANDOM_SUFFIX}"
    echo "  CloudWatch Alarm: EmailReports-GenerationFailures-${RANDOM_SUFFIX}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Check your email for the test report"
    echo "  2. Monitor the CloudWatch dashboard for metrics"
    echo "  3. The schedule will run daily at 9:00 AM UTC"
    echo "  4. View logs in CloudWatch Logs: /aws/apprunner/$APP_RUNNER_SERVICE_NAME"
    echo ""
    echo -e "${YELLOW}Note:${NC} Deployment information saved to deployment-info.json"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main deployment function
main() {
    log "Starting deployment of Scheduled Email Reports with App Runner and SES..."
    
    # Check if this is a dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_application_files
    setup_git_repository
    create_app_runner_role
    verify_ses_email
    create_app_runner_service
    create_scheduler_role
    create_eventbridge_schedule
    configure_cloudwatch_monitoring
    test_deployment
    save_deployment_info
    display_deployment_summary
    
    success "Deployment completed successfully!"
    
    # Cleanup temporary files
    rm -f *.json
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Deployment failed or was interrupted"
        log "Temporary files may need manual cleanup"
    fi
}
trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --ses-email)
            export SES_VERIFIED_EMAIL="$2"
            shift 2
            ;;
        --github-repo)
            export GITHUB_REPO_URL="$2"
            shift 2
            ;;
        --region)
            export AWS_REGION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy Scheduled Email Reports with App Runner and SES"
            echo ""
            echo "Options:"
            echo "  --dry-run              Run in dry-run mode (no resources created)"
            echo "  --ses-email EMAIL      SES verified email address"
            echo "  --github-repo URL      GitHub repository URL"
            echo "  --region REGION        AWS region (default: from AWS CLI config)"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"