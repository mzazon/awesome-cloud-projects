#!/bin/bash

# Secure Database Access with VPC Lattice Resource Gateway - Deployment Script
# This script automates the deployment of the CDK Python application

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Python
    if ! command_exists python3; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    if [[ $(echo "$python_version 3.8" | awk '{print ($1 >= $2)}') -eq 0 ]]; then
        print_error "Python 3.8 or higher is required. Current version: $python_version"
        exit 1
    fi
    print_status "Python version: $python_version ✓"
    
    # Check Node.js
    if ! command_exists node; then
        print_error "Node.js is required but not installed"
        exit 1
    fi
    
    node_version=$(node --version | sed 's/v//')
    print_status "Node.js version: $node_version ✓"
    
    # Check AWS CLI
    if ! command_exists aws; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    print_status "AWS CLI version: $aws_version ✓"
    
    # Check CDK
    if ! command_exists cdk; then
        print_warning "AWS CDK not found. Installing globally..."
        npm install -g aws-cdk
    fi
    
    cdk_version=$(cdk --version | cut -d' ' -f1)
    print_status "AWS CDK version: $cdk_version ✓"
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        print_error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    account_id=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region)
    print_status "AWS Account: $account_id"
    print_status "AWS Region: $region ✓"
}

# Function to setup Python environment
setup_python_env() {
    print_header "Setting Up Python Environment"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        print_status "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    print_status "Activating virtual environment..."
    source venv/bin/activate
    
    # Upgrade pip
    print_status "Upgrading pip..."
    pip install --upgrade pip
    
    # Install dependencies
    print_status "Installing Python dependencies..."
    pip install -r requirements.txt
    
    print_status "Python environment setup complete ✓"
}

# Function to validate configuration
validate_configuration() {
    print_header "Validating Configuration"
    
    # Check if consumer account ID is set
    consumer_account=$(cat cdk.json | python3 -c "import sys, json; print(json.load(sys.stdin)['context']['consumer_account_id'])" 2>/dev/null || echo "")
    
    if [ "$consumer_account" = "123456789012" ] || [ -z "$consumer_account" ]; then
        print_warning "Consumer account ID is set to default value: $consumer_account"
        print_warning "Please update the 'consumer_account_id' in cdk.json with the actual consumer account ID"
        
        read -p "Do you want to continue with the default value? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled. Please update cdk.json with the correct consumer account ID"
            exit 1
        fi
    fi
    
    print_status "Consumer Account ID: $consumer_account ✓"
    
    # Validate CDK configuration
    print_status "Validating CDK configuration..."
    cdk synth --quiet >/dev/null
    print_status "CDK configuration is valid ✓"
}

# Function to bootstrap CDK (if needed)
bootstrap_cdk() {
    print_header "Checking CDK Bootstrap"
    
    account_id=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region)
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region "$region" >/dev/null 2>&1; then
        print_status "CDK already bootstrapped in $region ✓"
    else
        print_status "Bootstrapping CDK in $region..."
        cdk bootstrap "aws://$account_id/$region"
        print_status "CDK bootstrap complete ✓"
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_header "Deploying Secure Database Access Stack"
    
    print_status "Synthesizing CloudFormation template..."
    cdk synth
    
    print_status "Starting deployment..."
    print_warning "This deployment will create AWS resources that may incur charges"
    print_warning "Estimated monthly cost: $80-120 (including RDS, VPC Lattice, NAT Gateway)"
    
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled by user"
        exit 1
    fi
    
    # Deploy the stack
    cdk deploy --require-approval never
    
    print_status "Deployment complete ✓"
}

# Function to display post-deployment instructions
show_post_deployment_info() {
    print_header "Post-Deployment Configuration"
    
    print_status "Deployment completed successfully!"
    echo
    print_warning "IMPORTANT: Additional steps required in the consumer account:"
    echo
    echo "1. Accept the AWS RAM invitation:"
    echo "   aws ram get-resource-share-invitations"
    echo "   aws ram accept-resource-share-invitation --resource-share-invitation-arn <invitation-arn>"
    echo
    echo "2. Associate consumer VPC with the shared service network:"
    echo "   aws vpc-lattice create-service-network-vpc-association \\"
    echo "       --service-network-identifier <service-network-arn> \\"
    echo "       --vpc-identifier <consumer-vpc-id>"
    echo
    echo "3. Test database connectivity from consumer account:"
    echo "   mysql -h <lattice-dns-name> -P 3306 -u admin -p"
    echo
    
    # Get stack outputs
    print_status "Stack Outputs:"
    aws cloudformation describe-stacks \
        --stack-name SecureDatabaseAccessStack \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo
    print_status "For detailed instructions, see README.md"
    print_status "To clean up resources, run: ./destroy.sh"
}

# Function to handle errors
handle_error() {
    print_error "Deployment failed on line $1"
    print_error "Check the error messages above for details"
    exit 1
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  Secure Database Access with VPC Lattice"
    echo "  CDK Python Deployment Script"
    echo "=========================================="
    echo
    
    # Set error handler
    trap 'handle_error $LINENO' ERR
    
    # Run deployment steps
    check_prerequisites
    setup_python_env
    validate_configuration
    bootstrap_cdk
    deploy_stack
    show_post_deployment_info
    
    echo
    print_status "Deployment script completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo "  --dry-run      Perform validation without deploying"
            echo "  --force        Skip confirmation prompts"
            echo
            echo "This script deploys the Secure Database Access with VPC Lattice Resource Gateway solution"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Handle dry run
if [ "$DRY_RUN" = true ]; then
    print_header "Dry Run Mode - Validation Only"
    check_prerequisites
    setup_python_env
    validate_configuration
    print_status "Dry run completed successfully. No resources were deployed."
    exit 0
fi

# Run main deployment
main