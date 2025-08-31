#!/bin/bash

# Visual Infrastructure Composer CloudFormation Deployment Script
# This script deploys a static website using S3 and CloudFormation
# Generated for AWS recipe: visual-infrastructure-composer-cloudformation

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
STACK_NAME_PREFIX="visual-website-stack"
TEMPLATE_FILE="$PROJECT_ROOT/code/cloudformation.yaml"
DRY_RUN=false
FORCE_DEPLOY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --stack-name)
            CUSTOM_STACK_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run        Validate template without deploying"
            echo "  --force          Force deployment even if stack exists"
            echo "  --stack-name     Custom stack name (default: auto-generated)"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        log "Install instructions: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log "Run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    # Check if CloudFormation template exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "CloudFormation template not found at: $TEMPLATE_FILE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region from CLI config or default
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    log "AWS Region: $AWS_REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique suffix for resource naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set stack name
    if [[ -n "${CUSTOM_STACK_NAME:-}" ]]; then
        export STACK_NAME="$CUSTOM_STACK_NAME"
    else
        export STACK_NAME="${STACK_NAME_PREFIX}-${RANDOM_SUFFIX}"
    fi
    
    # Set bucket name
    export BUCKET_NAME="my-visual-website-${RANDOM_SUFFIX}"
    
    log_success "Environment configured"
    log "Stack name: $STACK_NAME"
    log "Bucket name: $BUCKET_NAME"
}

# Function to validate CloudFormation template
validate_template() {
    log "Validating CloudFormation template..."
    
    if aws cloudformation validate-template --template-body file://"$TEMPLATE_FILE" &> /dev/null; then
        log_success "CloudFormation template is valid"
    else
        log_error "CloudFormation template validation failed"
        aws cloudformation validate-template --template-body file://"$TEMPLATE_FILE"
        exit 1
    fi
}

# Function to check if stack already exists
check_stack_exists() {
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
        return 0  # Stack exists
    else
        return 1  # Stack doesn't exist
    fi
}

# Function to deploy CloudFormation stack
deploy_stack() {
    log "Deploying CloudFormation stack: $STACK_NAME"
    
    # Check if stack already exists
    if check_stack_exists; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log_warning "Stack already exists. Updating due to --force flag..."
            OPERATION="update-stack"
        else
            log_error "Stack '$STACK_NAME' already exists. Use --force to update or choose a different name."
            exit 1
        fi
    else
        OPERATION="create-stack"
    fi
    
    # Deploy or update stack
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would deploy stack with the following parameters:"
        log "Stack Name: $STACK_NAME"
        log "Bucket Name: $BUCKET_NAME"
        log "Region: $AWS_REGION"
        return 0
    fi
    
    aws cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        --template-body file://"$TEMPLATE_FILE" \
        --parameters ParameterKey=BucketName,ParameterValue="$BUCKET_NAME" \
        --capabilities CAPABILITY_IAM \
        --tags Key=Project,Value=VisualInfrastructureComposer \
               Key=Environment,Value=Demo \
               Key=ManagedBy,Value=CloudFormation
    
    log "Waiting for stack deployment to complete..."
    
    if [[ "$OPERATION" == "create-stack" ]]; then
        aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
    else
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
    fi
    
    log_success "CloudFormation stack deployed successfully"
}

# Function to create and upload website content
upload_website_content() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create and upload website content"
        return 0
    fi
    
    log "Creating website content..."
    
    # Create temporary directory for website files
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Create index.html
    cat > "$TEMP_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Visual Infrastructure Demo</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        .success { color: #4CAF50; font-weight: bold; }
        .highlight { color: #FFD700; }
        h1 { font-size: 2.5em; margin-bottom: 20px; }
        p { font-size: 1.2em; line-height: 1.6; }
        .footer { margin-top: 40px; text-align: center; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Success!</h1>
        <p class="success">This website was deployed using AWS Infrastructure Composer!</p>
        <p>Your visual infrastructure design is now live and serving content.</p>
        <p class="highlight">Deployed with CloudFormation automation scripts.</p>
        <div class="footer">
            <p>Powered by AWS S3 Static Website Hosting</p>
            <p>Created: <span id="timestamp"></span></p>
        </div>
    </div>
    <script>
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
    
    # Create error.html
    cat > "$TEMP_DIR/error.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Page Not Found - Visual Infrastructure Demo</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: linear-gradient(135deg, #ff6b6b 0%, #ffa726 100%);
            min-height: 100vh;
            color: white;
            text-align: center;
        }
        .container { 
            max-width: 600px; 
            margin: 100px auto; 
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        h1 { font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>
        <h2>Page Not Found</h2>
        <p>The page you're looking for doesn't exist.</p>
        <p><a href="/" style="color: #FFD700; text-decoration: none;">← Go back to home</a></p>
    </div>
</body>
</html>
EOF
    
    log "Uploading website content to S3..."
    
    # Upload files to S3
    aws s3 cp "$TEMP_DIR/index.html" "s3://$BUCKET_NAME/"
    aws s3 cp "$TEMP_DIR/error.html" "s3://$BUCKET_NAME/"
    
    log_success "Website content uploaded successfully"
}

# Function to get and display website URL
display_results() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Retrieving deployment information..."
    
    # Get website URL from CloudFormation outputs
    WEBSITE_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    # If no output exists, construct URL manually
    if [[ -z "$WEBSITE_URL" ]]; then
        WEBSITE_URL="http://${BUCKET_NAME}.s3-website-${AWS_REGION}.amazonaws.com"
    fi
    
    log_success "Deployment completed successfully!"
    echo ""
    echo "========================================="
    echo "🌐 WEBSITE INFORMATION"
    echo "========================================="
    echo "Website URL: $WEBSITE_URL"
    echo "Stack Name:  $STACK_NAME"
    echo "Bucket Name: $BUCKET_NAME"
    echo "AWS Region:  $AWS_REGION"
    echo "========================================="
    echo ""
    
    # Test website accessibility
    log "Testing website accessibility..."
    if curl -I "$WEBSITE_URL" &> /dev/null; then
        log_success "Website is accessible and responding"
    else
        log_warning "Website may still be propagating. Try again in a few minutes."
    fi
    
    echo ""
    echo "🎉 Your visual infrastructure design is now live!"
    echo "   Open the URL above in your browser to view your deployed website."
    echo ""
    echo "To clean up resources, run: ./destroy.sh --stack-name $STACK_NAME"
}

# Function to handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed or was interrupted"
        log "Check AWS CloudFormation console for stack status: $STACK_NAME"
        log "To clean up partial deployment, run: ./destroy.sh --stack-name $STACK_NAME"
    fi
}

# Main execution
main() {
    log "Starting Visual Infrastructure Composer CloudFormation deployment..."
    log "Script location: $SCRIPT_DIR"
    
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    validate_template
    deploy_stack
    upload_website_content
    display_results
    
    log_success "Deployment script completed successfully!"
}

# Execute main function
main "$@"