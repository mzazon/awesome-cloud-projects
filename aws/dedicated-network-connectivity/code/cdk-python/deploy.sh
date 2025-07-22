#!/bin/bash
# AWS CDK deployment script for hybrid cloud connectivity
# This script automates the deployment process and provides helpful guidance

set -e

# Colors for output
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
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    print_status "Python 3: $(python3 --version)"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    print_status "AWS CLI: $(aws --version)"
    
    # Check CDK CLI
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK CLI is not installed"
        print_error "Install with: npm install -g aws-cdk"
        exit 1
    fi
    print_status "AWS CDK: $(cdk --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured"
        print_error "Configure with: aws configure"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    print_status "AWS Account: $ACCOUNT_ID"
    print_status "AWS Region: $REGION"
}

# Setup virtual environment
setup_environment() {
    print_header "Setting up Python Environment"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d ".venv" ]; then
        print_status "Creating Python virtual environment..."
        python3 -m venv .venv
    fi
    
    # Activate virtual environment
    print_status "Activating virtual environment..."
    source .venv/bin/activate
    
    # Install dependencies
    print_status "Installing dependencies..."
    pip install -r requirements.txt
    
    print_status "Environment setup complete"
}

# Bootstrap CDK
bootstrap_cdk() {
    print_header "Bootstrapping CDK"
    
    # Check if already bootstrapped
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION &> /dev/null; then
        print_status "CDK already bootstrapped in $REGION"
    else
        print_status "Bootstrapping CDK in $REGION..."
        cdk bootstrap aws://$ACCOUNT_ID/$REGION
    fi
}

# Deploy the stack
deploy_stack() {
    print_header "Deploying Hybrid Connectivity Stack"
    
    print_status "Synthesizing CDK application..."
    cdk synth
    
    print_status "Reviewing deployment plan..."
    cdk diff
    
    print_warning "This deployment will create AWS resources that may incur charges."
    print_warning "Direct Connect connections can be expensive. Make sure you understand the costs."
    
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deploying stack..."
        cdk deploy --require-approval never
        
        print_status "Deployment completed successfully!"
        
        # Run connectivity tests
        print_header "Running Connectivity Tests"
        if [ -f "test_connectivity.py" ]; then
            python3 test_connectivity.py --region $REGION
        else
            print_warning "Connectivity test script not found"
        fi
        
        print_post_deployment_instructions
    else
        print_status "Deployment cancelled"
        exit 0
    fi
}

# Print post-deployment instructions
print_post_deployment_instructions() {
    print_header "Post-Deployment Instructions"
    
    echo -e "${YELLOW}IMPORTANT: Manual configuration required!${NC}"
    echo
    echo "1. Create Virtual Interface (VIF):"
    echo "   - Go to AWS Direct Connect Console"
    echo "   - Select your Direct Connect connection"
    echo "   - Create a new Transit Virtual Interface"
    echo "   - Use the Direct Connect Gateway ID from the stack outputs"
    echo
    echo "2. Configure BGP on your on-premises router:"
    echo "   - Use the BGP configuration template generated during deployment"
    echo "   - Ensure BGP ASN matches your configuration"
    echo "   - Configure route advertisements for on-premises networks"
    echo
    echo "3. Configure DNS forwarding:"
    echo "   - Point on-premises DNS to the inbound resolver endpoint"
    echo "   - IP address: 10.3.1.100"
    echo
    echo "4. Test connectivity:"
    echo "   - Run: python3 test_connectivity.py"
    echo "   - Verify BGP session establishment"
    echo "   - Test DNS resolution"
    echo
    echo "5. Monitor your deployment:"
    echo "   - Check CloudWatch dashboard for metrics"
    echo "   - Review VPC Flow Logs for traffic patterns"
    echo "   - Set up SNS notifications for alerts"
    echo
    echo -e "${GREEN}For detailed instructions, see the README.md file.${NC}"
}

# Cleanup function
cleanup_stack() {
    print_header "Cleaning up Resources"
    
    print_warning "This will permanently delete all resources created by this stack."
    print_warning "Make sure you have backed up any important data."
    
    read -p "Are you sure you want to delete the stack? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destroying stack..."
        cdk destroy --force
        print_status "Stack destroyed successfully!"
    else
        print_status "Cleanup cancelled"
    fi
}

# Main script logic
main() {
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            setup_environment
            bootstrap_cdk
            deploy_stack
            ;;
        "destroy")
            setup_environment
            cleanup_stack
            ;;
        "test")
            setup_environment
            if [ -f "test_connectivity.py" ]; then
                python3 test_connectivity.py --region $(aws configure get region)
            else
                print_error "Test script not found"
                exit 1
            fi
            ;;
        "diff")
            setup_environment
            cdk diff
            ;;
        "synth")
            setup_environment
            cdk synth
            ;;
        *)
            echo "Usage: $0 {deploy|destroy|test|diff|synth}"
            echo
            echo "Commands:"
            echo "  deploy  - Deploy the hybrid connectivity stack (default)"
            echo "  destroy - Destroy the stack and all resources"
            echo "  test    - Run connectivity tests"
            echo "  diff    - Show differences between current and deployed stack"
            echo "  synth   - Synthesize the CloudFormation template"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"