#!/bin/bash

#===============================================================================
# Simple Web Application Deployment with Elastic Beanstalk and CloudWatch
# Deploy Script
#
# This script deploys a simple Flask web application using AWS Elastic Beanstalk
# with CloudWatch monitoring integration.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions for Elastic Beanstalk, CloudWatch, IAM, and S3
# - jq installed for JSON parsing
#
# Usage: ./deploy.sh [--dry-run]
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            echo "🔍 Running in dry-run mode - no resources will be created"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run]"
            echo "  --dry-run  Validate prerequisites and show what would be deployed"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Clean up in reverse order of creation
    if [[ -n "${ENV_NAME:-}" ]]; then
        log_info "Attempting to terminate environment: $ENV_NAME"
        aws elasticbeanstalk terminate-environment --environment-name "$ENV_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "${APP_NAME:-}" ]]; then
        log_info "Attempting to delete application: $APP_NAME"
        aws elasticbeanstalk delete-application --application-name "$APP_NAME" --terminate-env-by-force 2>/dev/null || true
    fi
    
    if [[ -n "${S3_BUCKET:-}" ]]; then
        log_info "Attempting to clean up S3 bucket: $S3_BUCKET"
        aws s3 rm "s3://$S3_BUCKET" --recursive 2>/dev/null || true
        aws s3 rb "s3://$S3_BUCKET" 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites validation
validate_prerequisites() {
    log "🔍 Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install it first."
        exit 1
    fi
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid."
        log_error "Please run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    # Check required AWS permissions by testing basic operations
    log_info "Validating AWS permissions..."
    
    # Test Elastic Beanstalk permissions
    if ! aws elasticbeanstalk describe-applications --output text &> /dev/null; then
        log_error "Missing Elastic Beanstalk permissions. Please ensure you have elasticbeanstalk:* permissions."
        exit 1
    fi
    
    # Test CloudWatch permissions
    if ! aws cloudwatch describe-alarms --output text &> /dev/null; then
        log_error "Missing CloudWatch permissions. Please ensure you have cloudwatch:* permissions."
        exit 1
    fi
    
    # Test S3 permissions
    if ! aws s3 ls &> /dev/null; then
        log_error "Missing S3 permissions. Please ensure you have s3:* permissions."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Initialize environment variables
initialize_environment() {
    log "🔧 Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured. Please set it using 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export APP_NAME="simple-web-app-${RANDOM_SUFFIX}"
    export ENV_NAME="simple-web-env-${RANDOM_SUFFIX}"
    export S3_BUCKET="eb-source-${RANDOM_SUFFIX}"
    export VERSION_LABEL="v1-${RANDOM_SUFFIX}"
    
    # Create working directory
    export WORK_DIR="${HOME}/eb-sample-app-${RANDOM_SUFFIX}"
    
    log_success "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "  Application Name: $APP_NAME"
    log_info "  Environment Name: $ENV_NAME"
    log_info "  S3 Bucket: $S3_BUCKET"
    log_info "  Working Directory: $WORK_DIR"
}

# Create application files
create_application_files() {
    log "📁 Creating application files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create application files in $WORK_DIR"
        return 0
    fi
    
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Create main Flask application
    cat > application.py << 'EOF'
import flask
import logging
from datetime import datetime

# Create Flask application instance
application = flask.Flask(__name__)

# Configure logging for CloudWatch
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@application.route('/')
def hello():
    logger.info("Home page accessed")
    return flask.render_template('index.html')

@application.route('/health')
def health():
    logger.info("Health check accessed")
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}

@application.route('/api/info')
def info():
    logger.info("Info API accessed")
    return {
        'application': 'Simple Web App',
        'version': '1.0',
        'environment': 'production'
    }

if __name__ == '__main__':
    application.run(debug=True)
EOF
    
    # Create Python requirements
    cat > requirements.txt << 'EOF'
Flask==3.0.3
Werkzeug==3.0.3
EOF
    
    # Create templates directory and HTML template
    mkdir -p templates
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Simple Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; }
        .status { background: #e8f5e8; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Simple Web App</h1>
        <div class="status">
            <h3>Application Status: Running</h3>
            <p>This application is deployed on AWS Elastic Beanstalk with CloudWatch monitoring enabled.</p>
            <ul>
                <li><a href="/health">Health Check</a></li>
                <li><a href="/api/info">Application Info</a></li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create CloudWatch configuration
    mkdir -p .ebextensions
    cat > .ebextensions/cloudwatch-logs.config << 'EOF'
option_settings:
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: true
    DeleteOnTerminate: false
    RetentionInDays: 7
  aws:elasticbeanstalk:cloudwatch:logs:health:
    HealthStreamingEnabled: true
    DeleteOnTerminate: false
    RetentionInDays: 7
  aws:elasticbeanstalk:healthreporting:system:
    SystemType: enhanced
    EnhancedHealthAuthEnabled: true
EOF
    
    log_success "Application files created successfully"
}

# Create Elastic Beanstalk application
create_eb_application() {
    log "🚀 Creating Elastic Beanstalk application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create Elastic Beanstalk application: $APP_NAME"
        return 0
    fi
    
    aws elasticbeanstalk create-application \
        --application-name "$APP_NAME" \
        --description "Simple web application for learning deployment"
    
    # Verify application creation
    local app_status
    app_status=$(aws elasticbeanstalk describe-applications \
        --application-names "$APP_NAME" \
        --query 'Applications[0].ApplicationName' \
        --output text)
    
    if [[ "$app_status" != "$APP_NAME" ]]; then
        log_error "Failed to create Elastic Beanstalk application"
        exit 1
    fi
    
    log_success "Elastic Beanstalk application '$APP_NAME' created"
}

# Package and upload application
package_application() {
    log "📦 Packaging and uploading application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would package application and upload to S3 bucket: $S3_BUCKET"
        return 0
    fi
    
    cd "$WORK_DIR"
    
    # Create application source bundle
    zip -r "${APP_NAME}-source.zip" . -x "*.git*" "__pycache__/*" "*.pyc" "*.log"
    
    # Create S3 bucket for source bundle
    if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
        log_info "S3 bucket $S3_BUCKET already exists"
    else
        aws s3 mb "s3://$S3_BUCKET" --region "$AWS_REGION"
        log_success "S3 bucket $S3_BUCKET created"
    fi
    
    # Upload source bundle to S3
    aws s3 cp "${APP_NAME}-source.zip" "s3://$S3_BUCKET/${APP_NAME}-source.zip"
    
    # Create application version
    aws elasticbeanstalk create-application-version \
        --application-name "$APP_NAME" \
        --version-label "$VERSION_LABEL" \
        --source-bundle "S3Bucket=$S3_BUCKET,S3Key=${APP_NAME}-source.zip" \
        --description "Initial deployment version"
    
    log_success "Application packaged and uploaded as version $VERSION_LABEL"
}

# Deploy Elastic Beanstalk environment
deploy_eb_environment() {
    log "🌐 Deploying Elastic Beanstalk environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create Elastic Beanstalk environment: $ENV_NAME"
        return 0
    fi
    
    # Create Elastic Beanstalk environment with CloudWatch enabled
    aws elasticbeanstalk create-environment \
        --application-name "$APP_NAME" \
        --environment-name "$ENV_NAME" \
        --version-label "$VERSION_LABEL" \
        --solution-stack-name "64bit Amazon Linux 2023 v4.6.1 running Python 3.11" \
        --tier Name=WebServer,Type=Standard \
        --option-settings \
            Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro \
            Namespace=aws:elasticbeanstalk:cloudwatch:logs,OptionName=StreamLogs,Value=true \
            Namespace=aws:elasticbeanstalk:healthreporting:system,OptionName=SystemType,Value=enhanced
    
    log_info "Environment creation started - this may take 5-10 minutes..."
    
    # Wait for environment to be ready with timeout
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Environment creation timed out after 15 minutes"
            exit 1
        fi
        
        local env_status
        env_status=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-names "$ENV_NAME" \
            --query 'Environments[0].Status' \
            --output text 2>/dev/null || echo "NotFound")
        
        if [[ "$env_status" == "Ready" ]]; then
            break
        elif [[ "$env_status" == "Terminated" || "$env_status" == "Terminating" ]]; then
            log_error "Environment creation failed - environment is terminating"
            exit 1
        fi
        
        log_info "Environment status: $env_status (elapsed: ${elapsed}s)"
        sleep 30
    done
    
    log_success "Environment '$ENV_NAME' is ready and running"
}

# Configure monitoring and alarms
configure_monitoring() {
    log "📊 Configuring CloudWatch monitoring and alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create CloudWatch alarms for environment: $ENV_NAME"
        return 0
    fi
    
    # Create alarm for environment health
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ENV_NAME}-health-alarm" \
        --alarm-description "Monitor Elastic Beanstalk environment health" \
        --metric-name EnvironmentHealth \
        --namespace AWS/ElasticBeanstalk \
        --statistic Average \
        --period 300 \
        --threshold 15 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=EnvironmentName,Value="$ENV_NAME"
    
    # Create alarm for application errors (4xx responses)
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ENV_NAME}-4xx-errors" \
        --alarm-description "Monitor 4xx application errors" \
        --metric-name ApplicationRequests4xx \
        --namespace AWS/ElasticBeanstalk \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=EnvironmentName,Value="$ENV_NAME"
    
    log_success "CloudWatch alarms created for environment monitoring"
}

# Get deployment information
get_deployment_info() {
    log "📋 Retrieving deployment information..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Deployment information would be displayed here"
        return 0
    fi
    
    # Get environment URL
    local app_url
    app_url=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --query 'Environments[0].CNAME' \
        --output text)
    
    # Get environment ID
    local env_id
    env_id=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --query 'Environments[0].EnvironmentId' \
        --output text)
    
    # Save deployment info for cleanup script
    cat > "${SCRIPT_DIR}/deployment-info.env" << EOF
APP_NAME=$APP_NAME
ENV_NAME=$ENV_NAME
S3_BUCKET=$S3_BUCKET
VERSION_LABEL=$VERSION_LABEL
AWS_REGION=$AWS_REGION
WORK_DIR=$WORK_DIR
EOF
    
    log_success "Deployment completed successfully!"
    echo ""
    echo "=================================="
    echo "🎉 DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Application URL: http://$app_url"
    echo "Environment ID: $env_id"
    echo "Application Name: $APP_NAME"
    echo "Environment Name: $ENV_NAME"
    echo "S3 Bucket: $S3_BUCKET"
    echo "AWS Region: $AWS_REGION"
    echo ""
    echo "Test your application:"
    echo "  curl http://$app_url"
    echo "  curl http://$app_url/health"
    echo "  curl http://$app_url/api/info"
    echo ""
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
    echo "=================================="
}

# Main deployment function
main() {
    log "🚀 Starting Simple Web Application deployment with Elastic Beanstalk and CloudWatch"
    log "Deployment log: $LOG_FILE"
    
    validate_prerequisites
    initialize_environment
    create_application_files
    create_eb_application
    package_application
    deploy_eb_environment
    configure_monitoring
    get_deployment_info
    
    log_success "Deployment completed successfully! 🎉"
}

# Execute main function
main "$@"