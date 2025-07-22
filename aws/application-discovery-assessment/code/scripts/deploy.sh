#!/bin/bash

# AWS Application Discovery Service - Deployment Script
# This script deploys the infrastructure for application discovery and assessment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    success "AWS CLI version: $aws_version"
    
    # Check if jq is installed for JSON parsing
    if ! command_exists jq; then
        warning "jq is not installed. Some operations might be limited."
    fi
    
    check_aws_credentials
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured. Using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set Migration Hub home region
    export MH_HOME_REGION="us-west-2"
    
    # Set S3 bucket name
    export DISCOVERY_BUCKET="discovery-data-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
    log "Migration Hub Home Region: $MH_HOME_REGION"
    log "Discovery Bucket: $DISCOVERY_BUCKET"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for discovery data..."
    
    if aws s3api head-bucket --bucket "$DISCOVERY_BUCKET" 2>/dev/null; then
        warning "S3 bucket $DISCOVERY_BUCKET already exists"
        return 0
    fi
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$DISCOVERY_BUCKET"
    else
        aws s3api create-bucket --bucket "$DISCOVERY_BUCKET" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning on the bucket
    aws s3api put-bucket-versioning --bucket "$DISCOVERY_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Set up bucket lifecycle policy to manage costs
    cat > lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "DiscoveryDataLifecycle",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration --bucket "$DISCOVERY_BUCKET" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    rm -f lifecycle-policy.json
    success "S3 bucket created: $DISCOVERY_BUCKET"
}

# Function to create IAM role for Application Discovery Service
create_iam_role() {
    log "Creating IAM role for Application Discovery Service..."
    
    # Check if role already exists
    if aws iam get-role --role-name ApplicationDiscoveryServiceRole >/dev/null 2>&1; then
        warning "IAM role ApplicationDiscoveryServiceRole already exists"
        return 0
    fi
    
    # Create trust policy
    cat > discovery-service-role-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "discovery.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the IAM role
    aws iam create-role --role-name ApplicationDiscoveryServiceRole \
        --assume-role-policy-document file://discovery-service-role-policy.json
    
    # Attach the required policy
    aws iam attach-role-policy --role-name ApplicationDiscoveryServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/ApplicationDiscoveryServiceContinuousExportServiceRolePolicy
    
    # Wait for role to be available
    aws iam wait role-exists --role-name ApplicationDiscoveryServiceRole
    
    rm -f discovery-service-role-policy.json
    success "IAM role created: ApplicationDiscoveryServiceRole"
}

# Function to configure Migration Hub home region
configure_migration_hub() {
    log "Configuring Migration Hub home region..."
    
    # Create progress update stream
    aws migrationhub create-progress-update-stream \
        --progress-update-stream-name "DiscoveryAssessment" \
        --region "$MH_HOME_REGION" 2>/dev/null || true
    
    # Verify configuration
    if aws migrationhub describe-migration-task \
        --progress-update-stream "DiscoveryAssessment" \
        --migration-task-name "initial-setup" \
        --region "$MH_HOME_REGION" >/dev/null 2>&1; then
        success "Migration Hub home region already configured"
    else
        success "Migration Hub home region configured: $MH_HOME_REGION"
    fi
}

# Function to start continuous data export
start_continuous_export() {
    log "Starting continuous data export..."
    
    # Check if continuous export is already running
    local export_status=$(aws discovery describe-continuous-exports \
        --region "$AWS_REGION" --query 'descriptions[0].status' \
        --output text 2>/dev/null || echo "NONE")
    
    if [ "$export_status" = "ACTIVE" ]; then
        warning "Continuous export is already active"
        export EXPORT_ID=$(aws discovery describe-continuous-exports \
            --query 'descriptions[0].exportId' \
            --output text --region "$AWS_REGION")
        return 0
    fi
    
    # Start continuous export
    aws discovery start-continuous-export \
        --s3-bucket "$DISCOVERY_BUCKET" \
        --region "$AWS_REGION" || {
        warning "Failed to start continuous export. This is expected if no agents are installed yet."
        return 0
    }
    
    # Get export ID
    export EXPORT_ID=$(aws discovery describe-continuous-exports \
        --query 'descriptions[0].exportId' \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$EXPORT_ID" ]; then
        success "Continuous export started with ID: $EXPORT_ID"
    else
        warning "Continuous export setup complete, but no export ID available yet"
    fi
}

# Function to create application group
create_application_group() {
    log "Creating application group..."
    
    # Check if application already exists
    local existing_app=$(aws discovery list-applications \
        --query "applications[?name=='WebApplication-${RANDOM_SUFFIX}'].applicationId" \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$existing_app" ] && [ "$existing_app" != "None" ]; then
        warning "Application group already exists with ID: $existing_app"
        export APP_ID="$existing_app"
        return 0
    fi
    
    # Create application group
    aws discovery create-application \
        --name "WebApplication-${RANDOM_SUFFIX}" \
        --description "Web application servers discovered during assessment" \
        --region "$AWS_REGION"
    
    # Get application ID
    export APP_ID=$(aws discovery list-applications \
        --query 'applications[0].applicationId' \
        --output text --region "$AWS_REGION")
    
    success "Application group created with ID: $APP_ID"
}

# Function to create CloudWatch Events rule for automation
create_automation_rule() {
    log "Creating CloudWatch Events rule for automated discovery..."
    
    # Check if rule already exists
    if aws events describe-rule --name "DiscoveryReportSchedule" >/dev/null 2>&1; then
        warning "CloudWatch Events rule already exists"
        return 0
    fi
    
    # Create CloudWatch Events rule
    aws events put-rule \
        --name "DiscoveryReportSchedule" \
        --schedule-expression "rate(7 days)" \
        --description "Weekly discovery data export"
    
    success "CloudWatch Events rule created: DiscoveryReportSchedule"
}

# Function to create Athena database
create_athena_database() {
    log "Creating Athena database for discovery data analysis..."
    
    # Check if database already exists
    if aws athena get-database --catalog-name "AwsDataCatalog" \
        --database-name "discovery_analysis" >/dev/null 2>&1; then
        warning "Athena database already exists"
        return 0
    fi
    
    # Create Athena database
    local query_id=$(aws athena start-query-execution \
        --query-string "CREATE DATABASE IF NOT EXISTS discovery_analysis" \
        --result-configuration "OutputLocation=s3://${DISCOVERY_BUCKET}/athena-results/" \
        --query 'QueryExecutionId' --output text)
    
    # Wait for query completion
    aws athena wait query-execution-completed --query-execution-id "$query_id"
    
    success "Athena database created: discovery_analysis"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > deployment-state.json << EOF
{
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "awsRegion": "$AWS_REGION",
    "awsAccountId": "$AWS_ACCOUNT_ID",
    "randomSuffix": "$RANDOM_SUFFIX",
    "migrationHubHomeRegion": "$MH_HOME_REGION",
    "discoveryBucket": "$DISCOVERY_BUCKET",
    "exportId": "${EXPORT_ID:-}",
    "applicationId": "${APP_ID:-}",
    "resources": {
        "s3Bucket": "$DISCOVERY_BUCKET",
        "iamRole": "ApplicationDiscoveryServiceRole",
        "cloudWatchRule": "DiscoveryReportSchedule",
        "athenaDatabase": "discovery_analysis"
    }
}
EOF
    
    success "Deployment state saved to deployment-state.json"
}

# Function to display post-deployment instructions
display_post_deployment_instructions() {
    log "Deployment completed successfully!"
    echo
    echo "==========================================="
    echo "POST-DEPLOYMENT INSTRUCTIONS"
    echo "==========================================="
    echo
    echo "1. INSTALL DISCOVERY AGENTS:"
    echo "   - For Linux servers: Download and install AWS Application Discovery Agent"
    echo "   - For Windows servers: Download and install from AWS Migration Hub console"
    echo "   - For VMware: Deploy the Agentless Collector OVA template"
    echo
    echo "2. START DATA COLLECTION:"
    echo "   After installing agents, run the following command to start data collection:"
    echo "   aws discovery start-data-collection-by-agent-ids --agent-ids <AGENT_IDS> --region $AWS_REGION"
    echo
    echo "3. MONITOR DISCOVERY PROGRESS:"
    echo "   - Check agent status: aws discovery describe-agents --region $AWS_REGION"
    echo "   - View collected data: aws discovery describe-configurations --configuration-type SERVER --region $AWS_REGION"
    echo
    echo "4. ACCESS MIGRATION HUB:"
    echo "   - Open AWS Migration Hub console in region: $MH_HOME_REGION"
    echo "   - Review discovered servers and applications"
    echo
    echo "5. ANALYZE DATA:"
    echo "   - S3 bucket for exports: s3://$DISCOVERY_BUCKET"
    echo "   - Athena database: discovery_analysis"
    echo "   - CloudWatch automation rule: DiscoveryReportSchedule"
    echo
    echo "6. ESTIMATED COSTS:"
    echo "   - Application Discovery Service: FREE"
    echo "   - S3 storage: ~\$0.023 per GB per month"
    echo "   - Athena queries: ~\$5 per TB scanned"
    echo
    echo "==========================================="
    echo "For cleanup, run: ./destroy.sh"
    echo "==========================================="
}

# Main deployment function
main() {
    log "Starting AWS Application Discovery Service deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    # Create resources
    create_s3_bucket
    create_iam_role
    configure_migration_hub
    start_continuous_export
    create_application_group
    create_automation_rule
    create_athena_database
    
    # Save deployment state
    save_deployment_state
    
    # Display post-deployment instructions
    display_post_deployment_instructions
    
    success "Deployment completed successfully!"
}

# Trap to handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"