#!/bin/bash

# AWS CLI Setup and First Commands - Deployment Script
# This script sets up AWS CLI v2 and demonstrates basic S3 operations
# Recipe: aws-cli-setup-first-commands

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
WORKING_DIR="${HOME}/aws-cli-tutorial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message  
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Cleanup on exit
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" != "linux-gnu"* && "$OSTYPE" != "darwin"* ]]; then
        error_exit "This script supports Linux and macOS only. For Windows, please use WSL or follow manual installation."
    fi
    
    # Check for required tools
    local required_tools=("curl" "unzip")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error_exit "$tool is required but not installed."
        fi
    done
    
    # Check for sudo access if needed
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if ! sudo -n true 2>/dev/null; then
            warning "This script may require sudo access for AWS CLI installation."
        fi
    fi
    
    success "Prerequisites check completed"
}

# Detect OS and architecture
detect_system() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        SYSTEM_OS="linux"
        ARCH=$(uname -m)
        if [[ "$ARCH" == "x86_64" ]]; then
            CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
            CLI_FILENAME="awscliv2-linux-x86_64.zip"
        elif [[ "$ARCH" == "aarch64" ]]; then
            CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
            CLI_FILENAME="awscliv2-linux-aarch64.zip"
        else
            error_exit "Unsupported Linux architecture: $ARCH"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        SYSTEM_OS="macos"
        ARCH=$(uname -m)
        if [[ "$ARCH" == "x86_64" ]]; then
            CLI_URL="https://awscli.amazonaws.com/AWSCLIV2.pkg"
            CLI_FILENAME="AWSCLIV2.pkg"
        elif [[ "$ARCH" == "arm64" ]]; then
            CLI_URL="https://awscli.amazonaws.com/AWSCLIV2-arm64.pkg"
            CLI_FILENAME="AWSCLIV2-arm64.pkg"
        else
            error_exit "Unsupported macOS architecture: $ARCH"
        fi
    fi
    
    info "Detected system: $SYSTEM_OS ($ARCH)"
}

# Install AWS CLI v2
install_aws_cli() {
    info "Installing AWS CLI v2..."
    
    # Check if AWS CLI is already installed
    if command_exists aws; then
        local current_version
        current_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
        if [[ "$current_version" =~ ^2\. ]]; then
            success "AWS CLI v2 is already installed (version: $current_version)"
            return 0
        else
            warning "AWS CLI v1 detected (version: $current_version). Upgrading to v2..."
        fi
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download and install based on OS
    if [[ "$SYSTEM_OS" == "linux" ]]; then
        info "Downloading AWS CLI v2 for Linux..."
        curl -fsSL "$CLI_URL" -o "$CLI_FILENAME"
        unzip -q "$CLI_FILENAME"
        
        # Install with appropriate permissions
        if sudo -n true 2>/dev/null; then
            sudo ./aws/install --update 2>/dev/null || sudo ./aws/install
        else
            info "Installing AWS CLI to user directory (no sudo access)..."
            ./aws/install -i ~/.local/aws-cli -b ~/.local/bin --update 2>/dev/null || ./aws/install -i ~/.local/aws-cli -b ~/.local/bin
            
            # Add to PATH if not already there
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                export PATH="$HOME/.local/bin:$PATH"
                warning "Added ~/.local/bin to PATH. You may need to restart your shell or run: source ~/.bashrc"
            fi
        fi
        
    elif [[ "$SYSTEM_OS" == "macos" ]]; then
        info "Downloading AWS CLI v2 for macOS..."
        curl -fsSL "$CLI_URL" -o "$CLI_FILENAME"
        
        # Install package
        sudo installer -pkg "$CLI_FILENAME" -target /
    fi
    
    # Verify installation
    if command_exists aws; then
        local installed_version
        installed_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
        success "AWS CLI v2 installed successfully (version: $installed_version)"
    else
        error_exit "AWS CLI installation failed"
    fi
}

# Configure AWS CLI (interactive)
configure_aws_cli() {
    info "Configuring AWS CLI..."
    
    # Check if already configured
    if aws configure list | grep -q "access_key" && [[ "$(aws configure get aws_access_key_id)" != "None" ]]; then
        info "AWS CLI appears to be already configured"
        echo -n "Do you want to reconfigure? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            success "Using existing AWS CLI configuration"
            return 0
        fi
    fi
    
    info "AWS CLI configuration is required for this tutorial."
    info "You'll need your AWS Access Key ID and Secret Access Key."
    info "If you don't have these, create them in the AWS Console under IAM > Users > Your User > Security Credentials"
    echo
    
    # Interactive configuration
    aws configure
    
    # Verify configuration
    if aws sts get-caller-identity >/dev/null 2>&1; then
        success "AWS CLI configured and authenticated successfully"
        local account_id
        local user_arn
        account_id=$(aws sts get-caller-identity --query Account --output text)
        user_arn=$(aws sts get-caller-identity --query Arn --output text)
        info "Connected to AWS Account: $account_id"
        info "User/Role: $user_arn"
    else
        error_exit "AWS CLI configuration failed. Please check your credentials."
    fi
}

# Setup working directory
setup_working_directory() {
    info "Setting up working directory..."
    
    # Create working directory
    mkdir -p "$WORKING_DIR"
    cd "$WORKING_DIR"
    
    success "Working directory created: $WORKING_DIR"
}

# Set environment variables
set_environment_variables() {
    info "Setting up environment variables..."
    
    # Get AWS configuration
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique bucket name
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    export BUCKET_NAME="my-first-cli-bucket-${timestamp}"
    
    # Save variables to file for later use
    cat > "${WORKING_DIR}/.env" << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export BUCKET_NAME=${BUCKET_NAME}
EOF
    
    info "Environment variables configured:"
    info "  AWS Region: ${AWS_REGION}"
    info "  Account ID: ${AWS_ACCOUNT_ID}"
    info "  Bucket Name: ${BUCKET_NAME}"
    
    success "Environment variables configured"
}

# Create S3 bucket
create_s3_bucket() {
    info "Creating S3 bucket..."
    
    # Source environment variables
    source "${WORKING_DIR}/.env"
    
    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" >/dev/null 2>&1; then
        warning "Bucket ${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Wait for bucket to be available
    info "Waiting for bucket to be available..."
    aws s3api wait bucket-exists --bucket "${BUCKET_NAME}"
    
    # Enable server-side encryption
    info "Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Verify bucket creation
    if aws s3 ls | grep -q "${BUCKET_NAME}"; then
        success "S3 bucket created with encryption: ${BUCKET_NAME}"
    else
        error_exit "Failed to create S3 bucket"
    fi
}

# Demonstrate S3 operations
demonstrate_s3_operations() {
    info "Demonstrating S3 operations..."
    
    # Source environment variables
    source "${WORKING_DIR}/.env"
    
    # Create sample files
    info "Creating sample files..."
    cat > "${WORKING_DIR}/sample-file.txt" << EOF
Hello AWS CLI! This is my first S3 object.
AWS CLI makes cloud operations simple and scriptable.
Created on $(date)
Demo file for AWS CLI tutorial
EOF
    
    # Upload file to S3
    info "Uploading file to S3..."
    aws s3 cp "${WORKING_DIR}/sample-file.txt" "s3://${BUCKET_NAME}/" \
        --metadata purpose=tutorial,created-by=aws-cli-script
    
    # List objects in bucket
    info "Listing objects in bucket..."
    aws s3 ls "s3://${BUCKET_NAME}/" --human-readable
    
    # Download file with different name
    info "Downloading file from S3..."
    aws s3 cp "s3://${BUCKET_NAME}/sample-file.txt" "${WORKING_DIR}/downloaded-file.txt"
    
    # Verify download
    if diff "${WORKING_DIR}/sample-file.txt" "${WORKING_DIR}/downloaded-file.txt" >/dev/null; then
        success "File uploaded to and downloaded from S3 successfully"
    else
        error_exit "File upload/download verification failed"
    fi
}

# Demonstrate advanced CLI features
demonstrate_advanced_features() {
    info "Demonstrating advanced CLI features..."
    
    # Source environment variables
    source "${WORKING_DIR}/.env"
    
    info "Getting detailed bucket information..."
    aws s3api head-bucket --bucket "${BUCKET_NAME}" || true
    
    info "Listing objects with metadata..."
    aws s3api list-objects-v2 --bucket "${BUCKET_NAME}"
    
    info "Using JMESPath query to extract specific data..."
    aws s3api list-objects-v2 --bucket "${BUCKET_NAME}" \
        --query 'Contents[].{Name:Key,Size:Size,Modified:LastModified}' \
        --output table
    
    info "Checking bucket encryption configuration..."
    aws s3api get-bucket-encryption --bucket "${BUCKET_NAME}"
    
    success "Advanced CLI features demonstrated"
}

# Validation and testing
run_validation() {
    info "Running validation tests..."
    
    # Source environment variables
    source "${WORKING_DIR}/.env"
    
    # Test 1: CLI version check
    info "Test 1: Verifying AWS CLI installation..."
    local cli_version
    cli_version=$(aws --version 2>&1)
    if [[ "$cli_version" =~ aws-cli/2 ]]; then
        success "AWS CLI v2 is properly installed"
    else
        error_exit "AWS CLI v2 not found or incorrect version"
    fi
    
    # Test 2: Configuration check
    info "Test 2: Verifying AWS CLI configuration..."
    if aws configure list | grep -q "access_key"; then
        success "AWS CLI is properly configured"
    else
        error_exit "AWS CLI configuration is incomplete"
    fi
    
    # Test 3: Authentication test
    info "Test 3: Testing authentication..."
    if aws sts get-caller-identity >/dev/null 2>&1; then
        success "AWS authentication is working"
    else
        error_exit "AWS authentication failed"
    fi
    
    # Test 4: S3 bucket verification
    info "Test 4: Verifying S3 bucket..."
    if aws s3 ls | grep -q "${BUCKET_NAME}"; then
        success "S3 bucket exists and is accessible"
    else
        error_exit "S3 bucket not found or not accessible"
    fi
    
    # Test 5: Object verification
    info "Test 5: Verifying S3 object operations..."
    if aws s3 ls "s3://${BUCKET_NAME}/sample-file.txt" >/dev/null 2>&1; then
        success "S3 object operations working correctly"
    else
        error_exit "S3 object not found"
    fi
    
    # Test 6: Encryption verification
    info "Test 6: Verifying bucket encryption..."
    if aws s3api get-bucket-encryption --bucket "${BUCKET_NAME}" | grep -q "AES256"; then
        success "Bucket encryption is properly configured"
    else
        warning "Bucket encryption verification failed or not using AES256"
    fi
    
    success "All validation tests passed!"
}

# Create deployment summary
create_summary() {
    info "Creating deployment summary..."
    
    # Source environment variables
    source "${WORKING_DIR}/.env"
    
    cat > "${WORKING_DIR}/deployment-summary.txt" << EOF
AWS CLI Setup and First Commands - Deployment Summary
====================================================

Deployment Date: $(date)
Working Directory: ${WORKING_DIR}

AWS Configuration:
- Region: ${AWS_REGION}
- Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
- S3 Bucket: ${BUCKET_NAME}
  - Encryption: AES256 (Server-side)
  - Location: ${AWS_REGION}
  - Sample Object: sample-file.txt

Files Created:
- ${WORKING_DIR}/sample-file.txt (original)
- ${WORKING_DIR}/downloaded-file.txt (from S3)
- ${WORKING_DIR}/.env (environment variables)
- ${WORKING_DIR}/deployment-summary.txt (this file)

Next Steps:
1. Explore additional AWS CLI commands
2. Practice with other AWS services
3. Learn about AWS CLI profiles for multiple accounts
4. When finished, run destroy.sh to clean up resources

Cleanup Command:
cd ${WORKING_DIR} && ../scripts/destroy.sh
EOF
    
    success "Deployment summary created: ${WORKING_DIR}/deployment-summary.txt"
}

# Main deployment function
main() {
    log "${BLUE}Starting AWS CLI Setup and First Commands deployment...${NC}"
    
    # Initialize log file
    echo "AWS CLI Setup Deployment Log - $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    detect_system
    install_aws_cli
    configure_aws_cli
    setup_working_directory
    set_environment_variables
    create_s3_bucket
    demonstrate_s3_operations
    demonstrate_advanced_features
    run_validation
    create_summary
    
    log "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo
    info "Summary:"
    info "- AWS CLI v2 installed and configured"
    info "- S3 bucket created: ${BUCKET_NAME:-N/A}"
    info "- Sample operations demonstrated"
    info "- Working directory: ${WORKING_DIR}"
    echo
    info "Check the deployment summary: ${WORKING_DIR}/deployment-summary.txt"
    info "To clean up resources, run: ${SCRIPT_DIR}/destroy.sh"
    echo
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi