#!/bin/bash

#
# Deployment script for Simple File Sharing with Transfer Family Web Apps
# This script helps deploy the CDK application with proper configuration
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check CDK CLI
    if ! command -v cdk &> /dev/null; then
        log_error "CDK CLI is not installed. Install it with: npm install -g aws-cdk@latest"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

setup_environment() {
    log_info "Setting up Python environment..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d ".venv" ]; then
        python3 -m venv .venv
        log_success "Created Python virtual environment"
    fi
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Install dependencies
    pip install -r requirements.txt
    log_success "Installed Python dependencies"
}

get_identity_center_info() {
    log_info "Retrieving IAM Identity Center information..."
    
    # Get Identity Center instance ARN
    IDENTITY_CENTER_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "None")
    
    if [ "$IDENTITY_CENTER_ARN" = "None" ] || [ "$IDENTITY_CENTER_ARN" = "null" ]; then
        log_error "IAM Identity Center is not enabled in your account."
        log_info "Please enable it manually:"
        log_info "1. Go to https://console.aws.amazon.com/singlesignon/"
        log_info "2. Click 'Enable' and follow the setup wizard"
        log_info "3. Re-run this script after enabling IAM Identity Center"
        exit 1
    fi
    
    # Get Identity Store ID
    IDENTITY_STORE_ID=$(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text 2>/dev/null || echo "None")
    
    log_success "Found IAM Identity Center instance: ${IDENTITY_CENTER_ARN}"
    log_success "Identity Store ID: ${IDENTITY_STORE_ID}"
    
    # Export for CDK
    export IDENTITY_CENTER_INSTANCE_ARN="$IDENTITY_CENTER_ARN"
    export IDENTITY_STORE_ID="$IDENTITY_STORE_ID"
}

bootstrap_cdk() {
    log_info "Checking CDK bootstrap status..."
    
    # Get current account and region
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    
    # Check if already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" &> /dev/null; then
        log_success "CDK already bootstrapped in account $ACCOUNT_ID, region $REGION"
    else
        log_info "Bootstrapping CDK in account $ACCOUNT_ID, region $REGION..."
        cdk bootstrap
        log_success "CDK bootstrap completed"
    fi
}

deploy_application() {
    log_info "Deploying Simple File Sharing with Transfer Family Web Apps..."
    
    # Source virtual environment
    source .venv/bin/activate
    
    # Deploy with configuration
    cdk deploy \
        -c identity_center_instance_arn="$IDENTITY_CENTER_INSTANCE_ARN" \
        -c identity_store_id="$IDENTITY_STORE_ID" \
        -c create_demo_user=true \
        -c enable_cdk_nag=true \
        --require-approval never
    
    log_success "Deployment completed!"
}

show_outputs() {
    log_info "Retrieving deployment outputs..."
    
    # Get stack outputs
    STACK_NAME="SimpleFileSharingTransferWebAppStack"
    
    echo ""
    echo "=== Deployment Outputs ==="
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' --output table
    
    # Get web app access endpoint specifically
    ACCESS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`TransferWebAppAccessEndpoint`].OutputValue' --output text)
    
    if [ "$ACCESS_ENDPOINT" != "None" ] && [ -n "$ACCESS_ENDPOINT" ]; then
        echo ""
        log_success "🌐 Web App Access URL: $ACCESS_ENDPOINT"
        echo ""
        log_info "Next Steps:"
        log_info "1. Set a password for the demo user in IAM Identity Center console"
        log_info "2. Access the file sharing interface at: $ACCESS_ENDPOINT"
        log_info "3. Login with the demo user credentials"
        log_info "4. Start uploading and sharing files!"
    fi
}

main() {
    echo "🚀 Simple File Sharing with Transfer Family Web Apps - Deployment Script"
    echo "===================================================================="
    echo ""
    
    # Parse command line arguments
    SKIP_CHECKS=false
    SKIP_BOOTSTRAP=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-checks)
                SKIP_CHECKS=true
                shift
                ;;
            --skip-bootstrap)
                SKIP_BOOTSTRAP=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-checks      Skip prerequisite checks"
                echo "  --skip-bootstrap   Skip CDK bootstrap"
                echo "  --help, -h         Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    if [ "$SKIP_CHECKS" = false ]; then
        check_prerequisites
    fi
    
    setup_environment
    get_identity_center_info
    
    if [ "$SKIP_BOOTSTRAP" = false ]; then
        bootstrap_cdk
    fi
    
    deploy_application
    show_outputs
    
    echo ""
    log_success "🎉 Deployment completed successfully!"
    log_info "Check the outputs above for your web app access URL and next steps."
}

# Run main function
main "$@"