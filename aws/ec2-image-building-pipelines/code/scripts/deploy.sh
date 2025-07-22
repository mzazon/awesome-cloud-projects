#!/bin/bash

# EC2 Image Building Pipelines Deployment Script
# This script deploys EC2 Image Builder pipeline infrastructure for automated AMI creation

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${ERROR_LOG} for details."
    warn "Run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy EC2 Image Builder pipeline for automated AMI creation.

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: current AWS CLI region)
    -p, --prefix PREFIX     Resource name prefix (default: auto-generated)
    -t, --instance-type TYPE EC2 instance type for builds (default: t3.medium)
    -n, --no-wait           Don't wait for first build to complete
    -d, --dry-run           Show what would be deployed without creating resources
    
EXAMPLES:
    $0                      # Deploy with default settings
    $0 -r us-west-2         # Deploy to specific region
    $0 -p myapp             # Use custom prefix for resources
    $0 --dry-run            # Preview deployment

REQUIREMENTS:
    - AWS CLI v2 configured with appropriate permissions
    - IAM permissions for EC2 Image Builder, EC2, IAM, S3, SNS
    - Minimum estimated cost: \$5-15 for compute and storage during builds

EOF
}

# Parse command line arguments
REGION=""
PREFIX=""
INSTANCE_TYPE="t3.medium"
WAIT_FOR_BUILD=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -n|--no-wait)
            WAIT_FOR_BUILD=false
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
log "Starting EC2 Image Builder pipeline deployment"
log "Script version: 1.0"
log "Log file: $LOG_FILE"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS User/Role: $AWS_USER_ARN"
    
    # Set region
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            error "No AWS region configured. Use -r option or run 'aws configure'"
            exit 1
        fi
    fi
    log "AWS Region: $REGION"
    
    # Check required IAM permissions
    log "Checking IAM permissions..."
    local permissions_ok=true
    
    # Test Image Builder permissions
    if ! aws imagebuilder list-image-pipelines --region "$REGION" &> /dev/null; then
        error "Missing EC2 Image Builder permissions"
        permissions_ok=false
    fi
    
    # Test EC2 permissions
    if ! aws ec2 describe-vpcs --region "$REGION" &> /dev/null; then
        error "Missing EC2 VPC permissions"
        permissions_ok=false
    fi
    
    # Test IAM permissions
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        error "Missing IAM permissions"
        permissions_ok=false
    fi
    
    if [[ "$permissions_ok" != "true" ]]; then
        error "Insufficient AWS permissions. Please ensure you have EC2 Image Builder, EC2, IAM, S3, and SNS permissions."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION="$REGION"
    export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
    
    # Generate unique identifiers for resources
    if [[ -z "$PREFIX" ]]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --region "$REGION" \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        PREFIX="webserver"
    else
        RANDOM_SUFFIX="${PREFIX}-$(date +%s | tail -c 4)"
    fi
    
    export PIPELINE_NAME="${PREFIX}-pipeline-${RANDOM_SUFFIX}"
    export RECIPE_NAME="${PREFIX}-recipe-${RANDOM_SUFFIX}"
    export COMPONENT_NAME="${PREFIX}-component-${RANDOM_SUFFIX}"
    export INFRASTRUCTURE_NAME="${PREFIX}-infra-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="${PREFIX}-dist-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PREFIX}-logs-${RANDOM_SUFFIX}"
    export ROLE_SUFFIX="$RANDOM_SUFFIX"
    
    log "Resource prefix: $PREFIX"
    log "Random suffix: $RANDOM_SUFFIX"
    log "S3 bucket: $BUCKET_NAME"
    log "Pipeline name: $PIPELINE_NAME"
    
    # Save environment to file for destroy script
    cat > "${SCRIPT_DIR}/.deploy_env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
PIPELINE_NAME=$PIPELINE_NAME
RECIPE_NAME=$RECIPE_NAME
COMPONENT_NAME=$COMPONENT_NAME
INFRASTRUCTURE_NAME=$INFRASTRUCTURE_NAME
DISTRIBUTION_NAME=$DISTRIBUTION_NAME
BUCKET_NAME=$BUCKET_NAME
ROLE_SUFFIX=$ROLE_SUFFIX
INSTANCE_TYPE=$INSTANCE_TYPE
EOF
    
    success "Environment variables configured"
}

# Create S3 bucket and IAM roles
create_prerequisites() {
    log "Creating prerequisite resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create S3 bucket: $BUCKET_NAME"
        log "DRY RUN: Would create IAM role: ImageBuilderInstanceRole-${ROLE_SUFFIX}"
        return 0
    fi
    
    # Create S3 bucket for component storage and logs
    log "Creating S3 bucket: $BUCKET_NAME"
    if aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null; then
        success "Created S3 bucket: $BUCKET_NAME"
    else
        warn "S3 bucket creation failed or bucket already exists"
    fi
    
    # Create IAM role for Image Builder
    log "Creating IAM role: ImageBuilderInstanceRole-${ROLE_SUFFIX}"
    if aws iam create-role \
        --role-name "ImageBuilderInstanceRole-${ROLE_SUFFIX}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags "Key=Purpose,Value=ImageBuilder" "Key=Environment,Value=Production" \
        &> /dev/null; then
        success "Created IAM role"
    else
        warn "IAM role creation failed or role already exists"
    fi
    
    # Attach required policies to the role
    log "Attaching IAM policies..."
    aws iam attach-role-policy \
        --role-name "ImageBuilderInstanceRole-${ROLE_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder &> /dev/null || true
    
    aws iam attach-role-policy \
        --role-name "ImageBuilderInstanceRole-${ROLE_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore &> /dev/null || true
    
    # Create instance profile
    log "Creating instance profile..."
    if aws iam create-instance-profile \
        --instance-profile-name "ImageBuilderInstanceProfile-${ROLE_SUFFIX}" \
        --tags "Key=Purpose,Value=ImageBuilder" \
        &> /dev/null; then
        success "Created instance profile"
    else
        warn "Instance profile creation failed or profile already exists"
    fi
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "ImageBuilderInstanceProfile-${ROLE_SUFFIX}" \
        --role-name "ImageBuilderInstanceRole-${ROLE_SUFFIX}" &> /dev/null || true
    
    # Wait for IAM propagation
    log "Waiting for IAM resources to propagate..."
    sleep 10
    
    success "Prerequisite resources created"
}

# Create Image Builder components
create_components() {
    log "Creating Image Builder components..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create build component: $COMPONENT_NAME"
        log "DRY RUN: Would create test component: ${COMPONENT_NAME}-test"
        return 0
    fi
    
    # Create component definition YAML
    log "Creating build component definition..."
    cat > "${SCRIPT_DIR}/web-server-component.yaml" << 'EOF'
name: WebServerSetup
description: Install and configure Apache web server with security hardening
schemaVersion: 1.0

phases:
  - name: build
    steps:
      - name: UpdateSystem
        action: UpdateOS
      - name: InstallApache
        action: ExecuteBash
        inputs:
          commands:
            - yum update -y
            - yum install -y httpd
            - systemctl enable httpd
      - name: ConfigureApache
        action: ExecuteBash
        inputs:
          commands:
            - echo '<html><body><h1>Custom Web Server</h1><p>Built with EC2 Image Builder</p></body></html>' > /var/www/html/index.html
            - chown apache:apache /var/www/html/index.html
            - chmod 644 /var/www/html/index.html
      - name: SecurityHardening
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^#ServerTokens OS/ServerTokens Prod/' /etc/httpd/conf/httpd.conf
            - sed -i 's/^#ServerSignature On/ServerSignature Off/' /etc/httpd/conf/httpd.conf
            - systemctl start httpd
  - name: validate
    steps:
      - name: ValidateApache
        action: ExecuteBash
        inputs:
          commands:
            - systemctl is-active httpd
            - curl -f http://localhost/ || exit 1
  - name: test
    steps:
      - name: TestWebServer
        action: ExecuteBash
        inputs:
          commands:
            - systemctl status httpd
            - curl -s http://localhost/ | grep -q "Custom Web Server" || exit 1
            - netstat -tlnp | grep :80 || exit 1
EOF
    
    # Upload component to S3
    log "Uploading component to S3..."
    aws s3 cp "${SCRIPT_DIR}/web-server-component.yaml" "s3://${BUCKET_NAME}/components/" \
        --region "$AWS_REGION"
    
    # Create the build component
    log "Creating build component in Image Builder..."
    aws imagebuilder create-component \
        --name "$COMPONENT_NAME" \
        --semantic-version "1.0.0" \
        --description "Web server setup with security hardening" \
        --platform Linux \
        --uri "s3://${BUCKET_NAME}/components/web-server-component.yaml" \
        --tags "Environment=Production,Purpose=WebServer" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created build component: $COMPONENT_NAME"
    
    # Create test component definition
    log "Creating test component definition..."
    cat > "${SCRIPT_DIR}/web-server-test.yaml" << 'EOF'
name: WebServerTest
description: Comprehensive testing of web server setup
schemaVersion: 1.0

phases:
  - name: test
    steps:
      - name: ServiceTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing Apache service status..."
            - systemctl is-enabled httpd
            - systemctl is-active httpd
      - name: ConfigurationTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing Apache configuration..."
            - httpd -t
            - grep -q "ServerTokens Prod" /etc/httpd/conf/httpd.conf || exit 1
            - grep -q "ServerSignature Off" /etc/httpd/conf/httpd.conf || exit 1
      - name: SecurityTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing security configurations..."
            - curl -I http://localhost/ | grep -q "Apache" && exit 1 || echo "Server signature hidden"
            - ss -tlnp | grep :80 | grep -q httpd || exit 1
      - name: ContentTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing web content..."
            - curl -s http://localhost/ | grep -q "Custom Web Server" || exit 1
            - test -f /var/www/html/index.html || exit 1
EOF
    
    # Upload test component to S3
    aws s3 cp "${SCRIPT_DIR}/web-server-test.yaml" "s3://${BUCKET_NAME}/components/" \
        --region "$AWS_REGION"
    
    # Create the test component
    log "Creating test component in Image Builder..."
    aws imagebuilder create-component \
        --name "${COMPONENT_NAME}-test" \
        --semantic-version "1.0.0" \
        --description "Comprehensive web server testing" \
        --platform Linux \
        --uri "s3://${BUCKET_NAME}/components/web-server-test.yaml" \
        --tags "Environment=Production,Purpose=Testing" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created test component: ${COMPONENT_NAME}-test"
}

# Create Image Builder recipe, infrastructure, and distribution configs
create_image_builder_config() {
    log "Creating Image Builder configurations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create image recipe: $RECIPE_NAME"
        log "DRY RUN: Would create infrastructure config: $INFRASTRUCTURE_NAME"
        log "DRY RUN: Would create distribution config: $DISTRIBUTION_NAME"
        return 0
    fi
    
    # Get component ARNs
    log "Retrieving component ARNs..."
    BUILD_COMPONENT_ARN=$(aws imagebuilder list-components \
        --filters "name=name,values=${COMPONENT_NAME}" \
        --region "$AWS_REGION" \
        --query 'componentVersionList[0].arn' --output text)
    
    TEST_COMPONENT_ARN=$(aws imagebuilder list-components \
        --filters "name=name,values=${COMPONENT_NAME}-test" \
        --region "$AWS_REGION" \
        --query 'componentVersionList[0].arn' --output text)
    
    # Get latest Amazon Linux 2 AMI ARN
    log "Finding base Amazon Linux 2 AMI..."
    BASE_IMAGE_ARN=$(aws imagebuilder list-images \
        --filters "name=name,values=Amazon Linux 2 x86" \
        --region "$AWS_REGION" \
        --query 'imageVersionList[0].arn' --output text)
    
    # Create image recipe
    log "Creating image recipe..."
    aws imagebuilder create-image-recipe \
        --name "$RECIPE_NAME" \
        --semantic-version "1.0.0" \
        --description "Web server recipe with security hardening" \
        --parent-image "$BASE_IMAGE_ARN" \
        --components "componentArn=${BUILD_COMPONENT_ARN}" \
                     "componentArn=${TEST_COMPONENT_ARN}" \
        --tags "Environment=Production,Purpose=WebServer" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created image recipe: $RECIPE_NAME"
    
    # Get default VPC and subnet
    log "Finding default VPC and subnet..."
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' --output text)
    
    DEFAULT_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
                  "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0].SubnetId' --output text)
    
    # Create security group for Image Builder
    log "Creating security group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "ImageBuilder-SG-${ROLE_SUFFIX}" \
        --description "Security group for Image Builder instances" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' --output text)
    
    # Add outbound rules for package downloads
    aws ec2 authorize-security-group-egress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" &> /dev/null || true
    
    aws ec2 authorize-security-group-egress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" &> /dev/null || true
    
    # Create SNS topic for notifications
    log "Creating SNS topic for notifications..."
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "ImageBuilder-Notifications-${ROLE_SUFFIX}" \
        --region "$AWS_REGION" \
        --query 'TopicArn' --output text)
    
    # Create infrastructure configuration
    log "Creating infrastructure configuration..."
    aws imagebuilder create-infrastructure-configuration \
        --name "$INFRASTRUCTURE_NAME" \
        --description "Infrastructure for web server image builds" \
        --instance-profile-name "ImageBuilderInstanceProfile-${ROLE_SUFFIX}" \
        --instance-types "$INSTANCE_TYPE" \
        --subnet-id "$DEFAULT_SUBNET_ID" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --terminate-instance-on-failure \
        --sns-topic-arn "$SNS_TOPIC_ARN" \
        --logging "s3Logs={s3BucketName=${BUCKET_NAME},s3KeyPrefix=build-logs/}" \
        --tags "Environment=Production,Purpose=WebServer" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created infrastructure configuration: $INFRASTRUCTURE_NAME"
    
    # Create distribution configuration
    log "Creating distribution configuration..."
    aws imagebuilder create-distribution-configuration \
        --name "$DISTRIBUTION_NAME" \
        --description "Multi-region distribution for web server AMIs" \
        --distributions "[
            {
                \"region\": \"${AWS_REGION}\",
                \"amiDistributionConfiguration\": {
                    \"name\": \"WebServer-{{imagebuilder:buildDate}}-{{imagebuilder:buildVersion}}\",
                    \"description\": \"Custom web server AMI built with Image Builder\",
                    \"amiTags\": {
                        \"Name\": \"WebServer-AMI\",
                        \"Environment\": \"Production\",
                        \"BuildDate\": \"{{imagebuilder:buildDate}}\",
                        \"BuildVersion\": \"{{imagebuilder:buildVersion}}\",
                        \"Recipe\": \"${RECIPE_NAME}\"
                    }
                }
            }
        ]" \
        --tags "Environment=Production,Purpose=WebServer" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created distribution configuration: $DISTRIBUTION_NAME"
    
    # Save additional environment variables
    cat >> "${SCRIPT_DIR}/.deploy_env" << EOF
SECURITY_GROUP_ID=$SECURITY_GROUP_ID
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
BUILD_COMPONENT_ARN=$BUILD_COMPONENT_ARN
TEST_COMPONENT_ARN=$TEST_COMPONENT_ARN
EOF
}

# Create Image Builder pipeline
create_pipeline() {
    log "Creating Image Builder pipeline..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create pipeline: $PIPELINE_NAME"
        return 0
    fi
    
    # Get ARNs for pipeline creation
    RECIPE_ARN=$(aws imagebuilder list-image-recipes \
        --filters "name=name,values=${RECIPE_NAME}" \
        --region "$AWS_REGION" \
        --query 'imageRecipeSummaryList[0].arn' --output text)
    
    INFRASTRUCTURE_ARN=$(aws imagebuilder list-infrastructure-configurations \
        --filters "name=name,values=${INFRASTRUCTURE_NAME}" \
        --region "$AWS_REGION" \
        --query 'infrastructureConfigurationSummaryList[0].arn' --output text)
    
    DISTRIBUTION_ARN=$(aws imagebuilder list-distribution-configurations \
        --filters "name=name,values=${DISTRIBUTION_NAME}" \
        --region "$AWS_REGION" \
        --query 'distributionConfigurationSummaryList[0].arn' --output text)
    
    # Create the pipeline
    log "Creating pipeline with weekly schedule..."
    aws imagebuilder create-image-pipeline \
        --name "$PIPELINE_NAME" \
        --description "Automated web server image building pipeline" \
        --image-recipe-arn "$RECIPE_ARN" \
        --infrastructure-configuration-arn "$INFRASTRUCTURE_ARN" \
        --distribution-configuration-arn "$DISTRIBUTION_ARN" \
        --image-tests-configuration "imageTestsEnabled=true,timeoutMinutes=90" \
        --schedule "scheduleExpression=cron(0 2 * * SUN),pipelineExecutionStartCondition=EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE" \
        --status ENABLED \
        --tags "Environment=Production,Purpose=WebServer" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created image pipeline: $PIPELINE_NAME"
    
    # Save pipeline ARN
    PIPELINE_ARN=$(aws imagebuilder list-image-pipelines \
        --filters "name=name,values=${PIPELINE_NAME}" \
        --region "$AWS_REGION" \
        --query 'imagePipelineList[0].arn' --output text)
    
    echo "PIPELINE_ARN=$PIPELINE_ARN" >> "${SCRIPT_DIR}/.deploy_env"
}

# Start initial build
start_initial_build() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would start initial pipeline build"
        return 0
    fi
    
    log "Starting initial image build..."
    
    BUILD_ARN=$(aws imagebuilder start-image-pipeline-execution \
        --image-pipeline-arn "$PIPELINE_ARN" \
        --region "$AWS_REGION" \
        --query 'imageBuildVersionArn' --output text)
    
    success "Started image build: $BUILD_ARN"
    log "Build typically takes 20-30 minutes to complete"
    
    echo "BUILD_ARN=$BUILD_ARN" >> "${SCRIPT_DIR}/.deploy_env"
    
    if [[ "$WAIT_FOR_BUILD" == "true" ]]; then
        monitor_build "$BUILD_ARN"
    else
        log "Skipping build monitoring. Use 'aws imagebuilder get-image --image-build-version-arn $BUILD_ARN' to check status"
    fi
}

# Monitor build progress
monitor_build() {
    local build_arn=$1
    log "Monitoring build progress..."
    
    local timeout=3600  # 1 hour timeout
    local elapsed=0
    local check_interval=60
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(aws imagebuilder get-image \
            --image-build-version-arn "$build_arn" \
            --region "$AWS_REGION" \
            --query 'image.state.status' --output text 2>/dev/null || echo "UNKNOWN")
        
        log "Build status: $status (elapsed: ${elapsed}s)"
        
        case "$status" in
            "AVAILABLE")
                success "Build completed successfully!"
                
                # Get the created AMI ID
                local ami_id=$(aws imagebuilder get-image \
                    --image-build-version-arn "$build_arn" \
                    --region "$AWS_REGION" \
                    --query 'image.outputResources.amis[0].image' --output text 2>/dev/null || echo "Not available")
                
                if [[ "$ami_id" != "Not available" ]]; then
                    success "Created AMI: $ami_id"
                    echo "AMI_ID=$ami_id" >> "${SCRIPT_DIR}/.deploy_env"
                fi
                return 0
                ;;
            "FAILED")
                error "Build failed. Check CloudWatch logs for details."
                
                # Get failure reason
                local failure_reason=$(aws imagebuilder get-image \
                    --image-build-version-arn "$build_arn" \
                    --region "$AWS_REGION" \
                    --query 'image.state.reason' --output text 2>/dev/null || echo "Unknown")
                
                error "Failure reason: $failure_reason"
                return 1
                ;;
            "CANCELLED")
                warn "Build was cancelled"
                return 1
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    warn "Build monitoring timed out after ${timeout} seconds"
    log "Build may still be in progress. Check AWS console for current status."
}

# Display deployment summary
show_summary() {
    log "Deployment Summary"
    log "=================="
    log "Region: $AWS_REGION"
    log "Pipeline: $PIPELINE_NAME"
    log "Recipe: $RECIPE_NAME"
    log "S3 Bucket: $BUCKET_NAME"
    log "Instance Type: $INSTANCE_TYPE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN completed - no resources were created"
    else
        log "Deployment configuration saved to: ${SCRIPT_DIR}/.deploy_env"
        log ""
        log "Next Steps:"
        log "- Monitor builds in AWS Console: EC2 Image Builder > Image pipelines"
        log "- View build logs in S3: s3://${BUCKET_NAME}/build-logs/"
        log "- Test created AMIs by launching EC2 instances"
        log "- Run ./destroy.sh to clean up resources when done"
        log ""
        log "Estimated monthly costs:"
        log "- S3 storage: $1-5 (logs and components)"
        log "- Build costs: $5-15 per build (compute and storage)"
        log "- AMI storage: $0.50-2 per AMI per month"
    fi
}

# Main execution
main() {
    log "Starting EC2 Image Builder deployment"
    
    check_prerequisites
    set_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN mode - showing what would be deployed"
    fi
    
    create_prerequisites
    create_components
    create_image_builder_config
    create_pipeline
    
    if [[ "$WAIT_FOR_BUILD" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
        start_initial_build
    fi
    
    show_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "EC2 Image Builder deployment completed successfully!"
    fi
}

# Run main function
main "$@"