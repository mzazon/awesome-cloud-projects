#!/bin/bash

# Real-time Anomaly Detection CDK Deployment Script
# This script deploys the complete anomaly detection infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d 'v' -f 2 | cut -d '.' -f 1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_error "Node.js version 18+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK is not installed. Please install it with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "All prerequisites met!"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing Node.js dependencies..."
    npm install
    print_success "Dependencies installed!"
}

# Function to build the project
build_project() {
    print_status "Building TypeScript project..."
    npm run build
    print_success "Project built successfully!"
}

# Function to bootstrap CDK
bootstrap_cdk() {
    print_status "Checking CDK bootstrap status..."
    
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo "us-east-1")
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" &> /dev/null; then
        print_success "CDK already bootstrapped for account $ACCOUNT in region $REGION"
    else
        print_status "Bootstrapping CDK for account $ACCOUNT in region $REGION..."
        cdk bootstrap "aws://$ACCOUNT/$REGION"
        print_success "CDK bootstrapped successfully!"
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_status "Deploying anomaly detection stack..."
    
    # Get deployment parameters
    if [ -n "$NOTIFICATION_EMAIL" ]; then
        print_status "Using notification email: $NOTIFICATION_EMAIL"
        DEPLOY_COMMAND="cdk deploy --require-approval never -c notificationEmail=$NOTIFICATION_EMAIL"
    else
        print_warning "No notification email specified. You can set it with: export NOTIFICATION_EMAIL=your-email@example.com"
        DEPLOY_COMMAND="cdk deploy --require-approval never"
    fi
    
    # Add additional context if provided
    if [ -n "$STREAM_SHARD_COUNT" ]; then
        DEPLOY_COMMAND="$DEPLOY_COMMAND -c streamShardCount=$STREAM_SHARD_COUNT"
    fi
    
    if [ -n "$FLINK_PARALLELISM" ]; then
        DEPLOY_COMMAND="$DEPLOY_COMMAND -c flinkParallelism=$FLINK_PARALLELISM"
    fi
    
    if [ -n "$ENVIRONMENT" ]; then
        DEPLOY_COMMAND="$DEPLOY_COMMAND -c environment=$ENVIRONMENT"
    fi
    
    # Execute deployment
    eval $DEPLOY_COMMAND
    
    if [ $? -eq 0 ]; then
        print_success "Stack deployed successfully!"
    else
        print_error "Stack deployment failed!"
        exit 1
    fi
}

# Function to show post-deployment instructions
show_post_deployment() {
    print_success "Deployment completed successfully!"
    echo ""
    print_status "Next steps:"
    echo "1. If you provided an email, check your inbox and confirm the SNS subscription"
    echo "2. Start the Flink application:"
    echo "   aws kinesisanalyticsv2 start-application --application-name \$(aws cloudformation describe-stacks --stack-name AnomalyDetectionStack --query 'Stacks[0].Outputs[?OutputKey==\`FlinkApplicationName\`].OutputValue' --output text) --run-configuration '{\"FlinkRunConfiguration\": {\"AllowNonRestoredState\": true}}'"
    echo ""
    echo "3. Generate test data:"
    echo "   aws lambda invoke --function-name \$(aws cloudformation describe-stacks --stack-name AnomalyDetectionStack --query 'Stacks[0].Outputs[?OutputKey==\`DataGeneratorName\`].OutputValue' --output text) --payload '{\"records_count\": 100}' response.json"
    echo ""
    echo "4. Monitor anomalies in CloudWatch metrics: AnomalyDetection/AnomalyCount"
    echo ""
    print_warning "Remember to stop the Flink application when not in use to avoid charges!"
}

# Main execution
main() {
    echo "=================================================="
    echo "Real-time Anomaly Detection CDK Deployment"
    echo "=================================================="
    echo ""
    
    # Load environment variables if .env file exists
    if [ -f .env ]; then
        print_status "Loading environment variables from .env file..."
        export $(grep -v '^#' .env | xargs)
    fi
    
    check_prerequisites
    install_dependencies
    build_project
    bootstrap_cdk
    deploy_stack
    show_post_deployment
    
    echo ""
    print_success "All done! Your anomaly detection system is ready to use."
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --check-only   Only check prerequisites"
        echo "  --build-only   Only build the project"
        echo ""
        echo "Environment variables:"
        echo "  NOTIFICATION_EMAIL   Email address for anomaly alerts"
        echo "  STREAM_SHARD_COUNT   Number of Kinesis shards (default: 2)"
        echo "  FLINK_PARALLELISM    Flink application parallelism (default: 2)"
        echo "  ENVIRONMENT          Environment name (dev/staging/prod)"
        echo ""
        echo "Example:"
        echo "  NOTIFICATION_EMAIL=me@example.com ./deploy.sh"
        exit 0
        ;;
    --check-only)
        check_prerequisites
        exit 0
        ;;
    --build-only)
        check_prerequisites
        install_dependencies
        build_project
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac