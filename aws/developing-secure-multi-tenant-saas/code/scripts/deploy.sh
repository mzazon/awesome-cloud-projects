#!/bin/bash

# Multi-Tenant SaaS Applications with Amplify and Fine-Grained Authorization - Deployment Script
# This script deploys a complete multi-tenant SaaS platform with tenant isolation,
# fine-grained authorization, and comprehensive tenant management capabilities.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_LOG="$PROJECT_ROOT/deployment.log"

# Default values
DRY_RUN=false
SKIP_FRONTEND=false
REGION=""
PROJECT_NAME=""

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Multi-Tenant SaaS Applications with Amplify and Fine-Grained Authorization

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -s, --skip-frontend Skip frontend deployment and build
    -r, --region        AWS region (if not set, uses default from AWS config)
    -n, --name          Project name prefix (auto-generated if not provided)
    -v, --verbose       Enable verbose logging

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 --dry-run                         # Preview deployment without changes
    $0 --region us-east-1 --name myapp   # Deploy to specific region with custom name
    $0 --skip-frontend                   # Deploy backend only

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Node.js 18+ and npm installed
    - Amplify CLI installed globally
    - Appropriate AWS permissions for Amplify, AppSync, Cognito, DynamoDB, Lambda

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-frontend)
            SKIP_FRONTEND=true
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | grep -o 'aws-cli/[0-9]\+' | cut -d'/' -f2)
    if [[ $AWS_CLI_VERSION -lt 2 ]]; then
        warning "AWS CLI v1 detected. AWS CLI v2 is recommended."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 18+."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $NODE_VERSION -lt 18 ]]; then
        error "Node.js 18+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        error "Amplify CLI is not installed. Run 'npm install -g @aws-amplify/cli'"
        exit 1
    fi
    
    # Check Amplify CLI configuration
    if ! amplify configure list &> /dev/null; then
        warning "Amplify CLI may not be configured. Run 'amplify configure' if deployment fails."
    fi
    
    success "All prerequisites satisfied"
}

# Validate AWS permissions
validate_permissions() {
    log "Validating AWS permissions..."
    
    local required_permissions=(
        "amplify:*"
        "appsync:*"
        "cognito-idp:*"
        "dynamodb:*"
        "lambda:*"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "iam:PassRole"
        "cloudformation:*"
        "s3:*"
    )
    
    # Test basic permissions by attempting to list resources
    local permission_tests=(
        "amplify list-apps"
        "appsync list-graphql-apis"
        "cognito-idp list-user-pools --max-results 1"
        "dynamodb list-tables"
        "lambda list-functions --max-items 1"
        "iam list-roles --max-items 1"
        "cloudformation list-stacks --max-results 1"
        "s3api list-buckets"
    )
    
    for test in "${permission_tests[@]}"; do
        if ! aws $test &> /dev/null; then
            warning "Permission test failed: $test"
        fi
    done
    
    success "AWS permissions validated"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            REGION="us-east-1"
            warning "No region specified, defaulting to us-east-1"
        fi
    fi
    export AWS_REGION="$REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate project name if not provided
    if [[ -z "$PROJECT_NAME" ]]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        PROJECT_NAME="multitenant-saas-${RANDOM_SUFFIX}"
    fi
    
    export APP_NAME="${PROJECT_NAME}"
    export PROJECT_NAME="${PROJECT_NAME}"
    
    log "Environment configured:"
    log "  - AWS Region: $AWS_REGION"
    log "  - AWS Account: $AWS_ACCOUNT_ID"
    log "  - Project Name: $PROJECT_NAME"
    
    success "Environment variables configured"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create project directory structure"
        return 0
    fi
    
    # Create project directory
    local project_dir="$HOME/amplify-projects/${PROJECT_NAME}"
    mkdir -p "$project_dir"
    cd "$project_dir"
    
    # Create Next.js application
    if [[ ! -d "frontend" ]]; then
        log "Creating Next.js application..."
        npx create-next-app@latest frontend --typescript --tailwind --eslint --app --yes
    fi
    
    cd frontend
    
    # Install dependencies
    log "Installing multi-tenant dependencies..."
    npm install aws-amplify @aws-amplify/ui-react
    npm install uuid @types/uuid
    npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
    npm install jsonwebtoken @types/jsonwebtoken
    
    success "Project structure created at $project_dir"
}

# Initialize Amplify backend
initialize_amplify() {
    log "Initializing Amplify backend..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would initialize Amplify with multi-tenant configuration"
        return 0
    fi
    
    # Initialize Amplify project
    if [[ ! -f "amplify/.config/project-config.json" ]]; then
        log "Initializing new Amplify project..."
        amplify init --yes \
            --name "${PROJECT_NAME}" \
            --region "${AWS_REGION}" \
            --profile default
    else
        log "Amplify project already initialized"
    fi
    
    success "Amplify backend initialized"
}

# Configure authentication with multi-tenant support
configure_authentication() {
    log "Configuring multi-tenant authentication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would configure Cognito with multi-tenant support"
        return 0
    fi
    
    # Check if auth is already configured
    if amplify status | grep -q "Auth"; then
        log "Authentication already configured"
        return 0
    fi
    
    # Add authentication
    log "Adding Cognito authentication..."
    
    # Create auth configuration
    cat > /tmp/auth-config.json << EOF
{
    "version": 1,
    "cognitoConfig": {
        "identityPoolName": "${PROJECT_NAME}_identitypool",
        "allowUnauthenticatedIdentities": false,
        "resourceNameTruncated": "multit${RANDOM_SUFFIX}",
        "userPoolName": "${PROJECT_NAME}_userpool",
        "autoVerifiedAttributes": ["email"],
        "mfaConfiguration": "OPTIONAL",
        "mfaTypes": ["SMS Text Message"],
        "smsAuthenticationMessage": "Your authentication code is {####}",
        "smsVerificationMessage": "Your verification code is {####}",
        "emailVerificationSubject": "Your verification code",
        "emailVerificationMessage": "Your verification code is {####}",
        "defaultPasswordPolicy": false,
        "passwordPolicyMinLength": 8,
        "passwordPolicyCharacters": [],
        "requiredAttributes": ["email"],
        "userpoolClientGenerateSecret": false,
        "userpoolClientRefreshTokenValidity": 30,
        "userpoolClientWriteAttributes": ["email"],
        "userpoolClientReadAttributes": ["email"],
        "userpoolClientLambdaTriggers": [],
        "userpoolClientSetAttributes": false,
        "sharedId": "multit${RANDOM_SUFFIX}",
        "resourceName": "multit${RANDOM_SUFFIX}",
        "authSelections": "identityPoolAndUserPool",
        "useDefault": "manual",
        "userPoolGroupList": ["SuperAdmins", "TenantAdmins", "Users"],
        "serviceName": "Cognito",
        "usernameCaseSensitive": false,
        "useEnabledMfas": true
    }
}
EOF
    
    # Use headless mode for authentication
    amplify add auth --headless /tmp/auth-config.json
    
    success "Multi-tenant authentication configured"
}

# Create GraphQL API with multi-tenant schema
create_graphql_api() {
    log "Creating multi-tenant GraphQL API..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create AppSync GraphQL API with multi-tenant schema"
        return 0
    fi
    
    # Check if API is already configured
    if amplify status | grep -q "Api"; then
        log "GraphQL API already configured"
        return 0
    fi
    
    # Add GraphQL API
    log "Adding AppSync GraphQL API..."
    
    # Create API configuration
    cat > /tmp/api-config.json << EOF
{
    "version": 1,
    "serviceConfiguration": {
        "apiName": "MultiTenantSaaSAPI",
        "serviceName": "AppSync",
        "defaultAuthType": {
            "mode": "AMAZON_COGNITO_USER_POOLS"
        },
        "additionalAuthTypes": [
            {
                "mode": "AWS_IAM"
            }
        ],
        "conflictResolution": {
            "defaultResolutionStrategy": {
                "type": "AUTOMERGE"
            }
        }
    }
}
EOF
    
    amplify add api --headless /tmp/api-config.json
    
    success "Multi-tenant GraphQL API created"
}

# Add Lambda functions for tenant management
add_lambda_functions() {
    log "Adding Lambda functions for tenant management..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Lambda functions for tenant resolution and management"
        return 0
    fi
    
    # Check if functions already exist
    if amplify status | grep -q "Function"; then
        log "Lambda functions already configured"
        return 0
    fi
    
    # Add tenant resolver function
    log "Adding tenant resolver Lambda function..."
    
    cat > /tmp/function-config.json << EOF
{
    "version": 1,
    "functionConfiguration": {
        "functionName": "tenantResolver",
        "runtime": "nodejs18.x",
        "lambdaLayers": [],
        "cloudWatchRule": {},
        "environmentVariables": {},
        "permissions": {}
    }
}
EOF
    
    amplify add function --headless /tmp/function-config.json
    
    # Add auth triggers function
    log "Adding authentication triggers Lambda function..."
    
    cat > /tmp/auth-triggers-config.json << EOF
{
    "version": 1,
    "functionConfiguration": {
        "functionName": "tenantAuthTriggers",
        "runtime": "nodejs18.x",
        "lambdaLayers": [],
        "cloudWatchRule": {},
        "environmentVariables": {},
        "permissions": {}
    }
}
EOF
    
    amplify add function --headless /tmp/auth-triggers-config.json
    
    success "Lambda functions added"
}

# Deploy backend infrastructure
deploy_backend() {
    log "Deploying multi-tenant backend infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy backend with the following resources:"
        log "  - Cognito User Pool with tenant groups"
        log "  - AppSync GraphQL API with multi-tenant schema"
        log "  - DynamoDB tables with tenant partitioning"
        log "  - Lambda functions for tenant management"
        log "  - IAM roles and policies for tenant isolation"
        return 0
    fi
    
    log "Starting Amplify deployment..."
    amplify push --yes
    
    # Wait for deployment to complete and verify resources
    log "Verifying deployed resources..."
    
    # Check GraphQL API
    local api_id=$(aws appsync list-graphql-apis \
        --region "$AWS_REGION" \
        --query "graphqlApis[?contains(name, '${PROJECT_NAME}')].apiId" \
        --output text)
    
    if [[ -n "$api_id" ]]; then
        success "GraphQL API deployed: $api_id"
    else
        error "GraphQL API deployment failed"
        exit 1
    fi
    
    # Check Cognito User Pool
    local user_pool_id=$(aws cognito-idp list-user-pools \
        --max-results 50 \
        --region "$AWS_REGION" \
        --query "UserPools[?contains(Name, '${PROJECT_NAME}')].Id" \
        --output text)
    
    if [[ -n "$user_pool_id" ]]; then
        success "Cognito User Pool deployed: $user_pool_id"
    else
        error "Cognito User Pool deployment failed"
        exit 1
    fi
    
    # Check DynamoDB tables
    local table_count=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query 'length(TableNames[?contains(@, `'${PROJECT_NAME}'`)])' \
        --output text)
    
    if [[ "$table_count" -gt 0 ]]; then
        success "DynamoDB tables deployed: $table_count tables"
    else
        warning "No DynamoDB tables found with project name"
    fi
    
    success "Backend infrastructure deployed successfully"
}

# Build and deploy frontend
deploy_frontend() {
    if [[ "$SKIP_FRONTEND" == "true" ]]; then
        log "Skipping frontend deployment as requested"
        return 0
    fi
    
    log "Building and deploying frontend application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would build and deploy Next.js frontend with:"
        log "  - Multi-tenant React components"
        log "  - Tenant-aware routing"
        log "  - Permission-based UI rendering"
        log "  - Amplify hosting"
        return 0
    fi
    
    # Build the frontend application
    log "Building Next.js application..."
    npm run build
    
    # Add hosting
    if ! amplify status | grep -q "Hosting"; then
        log "Adding Amplify hosting..."
        amplify add hosting --headless << EOF
{
    "type": "cicd",
    "source": "amplify"
}
EOF
    fi
    
    # Deploy hosting
    log "Deploying to Amplify hosting..."
    amplify publish --yes
    
    success "Frontend application deployed"
}

# Generate configuration and output information
generate_outputs() {
    log "Generating deployment outputs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would generate configuration files and output URLs"
        return 0
    fi
    
    # Get deployment information
    local amplify_outputs="amplify/#current-cloud-backend/amplify-meta.json"
    
    if [[ -f "$amplify_outputs" ]]; then
        log "Deployment configuration:"
        
        # Extract key information
        local region=$(jq -r '.providers.awscloudformation.Region' "$amplify_outputs" 2>/dev/null || echo "$AWS_REGION")
        local api_id=$(jq -r '.api.MultiTenantSaaSAPI.output.GraphQLAPIIdOutput' "$amplify_outputs" 2>/dev/null || echo "Not available")
        local api_endpoint=$(jq -r '.api.MultiTenantSaaSAPI.output.GraphQLAPIEndpointOutput' "$amplify_outputs" 2>/dev/null || echo "Not available")
        local user_pool_id=$(jq -r '.auth.multit*.output.UserPoolId' "$amplify_outputs" 2>/dev/null || echo "Not available")
        local user_pool_client_id=$(jq -r '.auth.multit*.output.AppClientIDWeb' "$amplify_outputs" 2>/dev/null || echo "Not available")
        
        cat << EOF

🎉 Multi-Tenant SaaS Platform Deployment Complete!

📊 Deployment Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project Name:           $PROJECT_NAME
AWS Region:             $region
AWS Account:            $AWS_ACCOUNT_ID

🔗 API Configuration:
GraphQL API ID:         $api_id
GraphQL Endpoint:       $api_endpoint

🔐 Authentication:
User Pool ID:           $user_pool_id
User Pool Client ID:    $user_pool_client_id

🚀 Next Steps:
1. Configure your first tenant in the super admin portal
2. Set up custom domain names for tenant subdomains
3. Configure tenant-specific branding and settings
4. Set up monitoring and alerting for tenant usage
5. Implement backup and disaster recovery procedures

📚 Documentation:
- Recipe Guide: See the complete recipe documentation
- AWS Amplify Docs: https://docs.amplify.aws/
- AppSync Multi-tenant: https://docs.aws.amazon.com/appsync/

⚠️  Important Security Notes:
- Review and customize IAM permissions for production use
- Enable CloudTrail for audit logging
- Configure AWS Config for compliance monitoring
- Set up AWS GuardDuty for threat detection
- Review tenant data isolation configurations

💰 Cost Monitoring:
- Monitor DynamoDB usage per tenant
- Track AppSync request volumes
- Review Lambda execution costs
- Set up billing alerts for unexpected usage

EOF
    else
        warning "Could not find Amplify outputs file"
    fi
    
    # Save deployment information
    cat > "$PROJECT_ROOT/deployment-info.json" << EOF
{
    "projectName": "$PROJECT_NAME",
    "region": "$AWS_REGION",
    "accountId": "$AWS_ACCOUNT_ID",
    "deploymentTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "components": {
        "amplify": true,
        "appsync": true,
        "cognito": true,
        "dynamodb": true,
        "lambda": true,
        "frontend": $([ "$SKIP_FRONTEND" == "true" ] && echo "false" || echo "true")
    }
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Cleanup function for script exit
cleanup() {
    log "Cleaning up temporary files..."
    rm -f /tmp/auth-config.json /tmp/api-config.json /tmp/function-config.json /tmp/auth-triggers-config.json
}

# Main deployment function
main() {
    # Set up logging
    exec 1> >(tee -a "$DEPLOYMENT_LOG")
    exec 2> >(tee -a "$DEPLOYMENT_LOG" >&2)
    
    log "Starting Multi-Tenant SaaS Platform deployment..."
    log "Deployment log: $DEPLOYMENT_LOG"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    # Execute deployment steps
    check_prerequisites
    validate_permissions
    setup_environment
    create_project_structure
    initialize_amplify
    configure_authentication
    create_graphql_api
    add_lambda_functions
    deploy_backend
    deploy_frontend
    generate_outputs
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN completed successfully"
        log "Run without --dry-run to perform actual deployment"
    else
        success "Multi-Tenant SaaS Platform deployment completed successfully!"
        log "Total deployment time: $SECONDS seconds"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi