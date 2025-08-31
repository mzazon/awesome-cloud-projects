#!/bin/bash

# AWS CDK Python Deployment Script for Lightsail WordPress
# This script automates the deployment of the WordPress hosting solution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VENV_NAME="venv"
STACK_NAME="LightsailWordPressStack"
DNS_STACK_NAME="LightsailDNSStack"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Python
    if ! command_exists python3; then
        print_error "Python 3 is required but not installed."
        exit 1
    fi
    
    # Check AWS CLI
    if ! command_exists aws; then
        print_error "AWS CLI is required but not installed."
        exit 1
    fi
    
    # Check CDK CLI
    if ! command_exists cdk; then
        print_error "AWS CDK CLI is required but not installed."
        print_error "Install with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured."
        print_error "Run: aws configure"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to setup Python virtual environment
setup_venv() {
    print_status "Setting up Python virtual environment..."
    
    if [ ! -d "$VENV_NAME" ]; then
        python3 -m venv "$VENV_NAME"
        print_success "Virtual environment created"
    else
        print_status "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    source "$VENV_NAME/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    print_status "Installing Python dependencies..."
    pip install -r requirements.txt
    
    print_success "Dependencies installed"
}

# Function to bootstrap CDK if needed
bootstrap_cdk() {
    print_status "Checking CDK bootstrap status..."
    
    # Check if CDK is already bootstrapped
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" >/dev/null 2>&1; then
        print_status "Bootstrapping CDK..."
        cdk bootstrap "aws://$ACCOUNT_ID/$REGION"
        print_success "CDK bootstrapped"
    else
        print_status "CDK already bootstrapped"
    fi
}

# Function to deploy the WordPress stack
deploy_wordpress() {
    print_status "Deploying WordPress Lightsail stack..."
    
    # Synthesize the stack first to check for errors
    print_status "Synthesizing CDK template..."
    cdk synth "$STACK_NAME"
    
    # Deploy the stack
    print_status "Deploying stack (this may take 3-5 minutes)..."
    cdk deploy "$STACK_NAME" --require-approval never
    
    print_success "WordPress stack deployed successfully"
}

# Function to deploy DNS stack (optional)
deploy_dns() {
    local domain_name="$1"
    
    if [ -n "$domain_name" ]; then
        print_status "Deploying DNS stack for domain: $domain_name"
        
        # Deploy with domain context
        cdk deploy "$DNS_STACK_NAME" \
            --context "domain_name=$domain_name" \
            --context "enable_dns=true" \
            --require-approval never
        
        print_success "DNS stack deployed successfully"
    fi
}

# Function to display deployment outputs
show_outputs() {
    print_status "Retrieving deployment information..."
    
    # Get stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "Deployment completed! Here are your WordPress details:"
        echo ""
        echo "$OUTPUTS"
        echo ""
        
        # Extract specific values for easy access
        STATIC_IP=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].Outputs[?OutputKey==`StaticIPAddress`].OutputValue' \
            --output text 2>/dev/null)
        
        if [ -n "$STATIC_IP" ]; then
            print_success "Quick Access URLs:"
            echo "  Website: http://$STATIC_IP"
            echo "  Admin:   http://$STATIC_IP/wp-admin"
            echo ""
            print_warning "To get your WordPress admin password:"
            echo "  1. SSH: ssh -i ~/.ssh/your-key-pair.pem bitnami@$STATIC_IP"
            echo "  2. Run: sudo cat /home/bitnami/bitnami_application_password"
            echo "  3. Username: user"
        fi
    else
        print_warning "Could not retrieve stack outputs. Check AWS Console."
    fi
}

# Function to show help
show_help() {
    echo "AWS CDK Python Deployment Script for Lightsail WordPress"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN    Deploy with custom domain"
    echo "  -h, --help            Show this help message"
    echo "  --skip-bootstrap      Skip CDK bootstrap check"
    echo "  --dry-run             Synthesize only, don't deploy"
    echo ""
    echo "Examples:"
    echo "  $0                           # Basic deployment"
    echo "  $0 -d example.com           # Deploy with custom domain"
    echo "  $0 --dry-run                # Test synthesis without deployment"
}

# Main deployment function
main() {
    local domain_name=""
    local skip_bootstrap=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                domain_name="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --skip-bootstrap)
                skip_bootstrap=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "AWS Lightsail WordPress CDK Deployment"
    echo "=========================================="
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_venv
    
    if [ "$skip_bootstrap" = false ]; then
        bootstrap_cdk
    fi
    
    if [ "$dry_run" = true ]; then
        print_status "Dry run mode - synthesizing only..."
        cdk synth
        print_success "Synthesis completed. Use without --dry-run to deploy."
        exit 0
    fi
    
    deploy_wordpress
    
    if [ -n "$domain_name" ]; then
        deploy_dns "$domain_name"
    fi
    
    show_outputs
    
    echo ""
    print_success "Deployment completed successfully!"
    print_status "Don't forget to:"
    echo "  1. Change default WordPress admin password"
    echo "  2. Update WordPress and plugins"
    echo "  3. Configure SSL certificate (Let's Encrypt)"
    echo "  4. Set up automated backups"
}

# Run main function with all arguments
main "$@"