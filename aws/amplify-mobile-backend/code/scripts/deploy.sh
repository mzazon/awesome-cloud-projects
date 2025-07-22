#!/bin/bash

# Mobile Backend Services with Amplify - Deployment Script
# This script deploys a complete mobile backend using AWS Amplify CLI
# Recipe: Amplify Mobile Backend with Authentication and APIs

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

log "Starting Mobile Backend Services with Amplify deployment..."

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2"
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 16.x or later"
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm"
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        error "Amplify CLI is not installed. Run: npm install -g @aws-amplify/cli"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run: aws configure"
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | sed 's/v//')
    REQUIRED_VERSION="16.0.0"
    if ! node -p "process.exit(require('semver').gte('$NODE_VERSION', '$REQUIRED_VERSION'))" 2>/dev/null; then
        if ! command -v semver &> /dev/null; then
            # Fallback version check
            MAJOR_VERSION=$(echo $NODE_VERSION | cut -d. -f1)
            if [ "$MAJOR_VERSION" -lt 16 ]; then
                error "Node.js version $NODE_VERSION is too old. Please install Node.js 16.x or later"
            fi
        else
            error "Node.js version $NODE_VERSION is too old. Please install Node.js 16.x or later"
        fi
    fi
    
    success "All prerequisites satisfied"
}

# Initialize environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region if not already set
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not set, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique project identifier
    export PROJECT_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="mobile-backend-${PROJECT_SUFFIX}"
    export STORAGE_BUCKET_NAME="${PROJECT_NAME}-user-files-${PROJECT_SUFFIX}"
    
    # Create project directory
    export PROJECT_DIR="$HOME/amplify-projects/${PROJECT_NAME}"
    
    success "Environment variables configured"
    log "Project Name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
}

# Create project directory and initialize
initialize_project() {
    log "Initializing Amplify project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create directory $PROJECT_DIR"
        return
    fi
    
    # Create and navigate to project directory
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Create package.json for the project
    cat > package.json << EOF
{
  "name": "mobile-backend-app",
  "version": "1.0.0",
  "description": "Mobile backend services with AWS Amplify",
  "main": "index.js",
  "scripts": {
    "start": "react-native start",
    "android": "react-native run-android",
    "ios": "react-native run-ios",
    "build": "react-native bundle --platform android --dev false --entry-file index.js --bundle-output android/app/src/main/assets/index.android.bundle"
  },
  "dependencies": {
    "aws-amplify": "^5.0.0",
    "aws-amplify-react-native": "^6.0.0",
    "amazon-cognito-identity-js": "^6.0.0",
    "@react-native-async-storage/async-storage": "^1.0.0",
    "@react-native-community/netinfo": "^9.0.0",
    "react-native-get-random-values": "^1.0.0"
  },
  "devDependencies": {
    "@react-native/babel-preset": "^0.72.0",
    "@react-native/metro-config": "^0.72.0"
  }
}
EOF
    
    # Initialize Amplify project with predefined answers
    cat > amplify_init_answers.json << EOF
{
  "projectName": "mobile-backend-app",
  "envName": "dev",
  "defaultEditor": "code",
  "appType": "javascript",
  "framework": "react-native",
  "srcDir": "src",
  "distDir": "build",
  "buildCmd": "npm run build",
  "startCmd": "npm start",
  "useProfile": true,
  "profileName": "default"
}
EOF
    
    # Initialize Amplify
    amplify init --yes --amplify amplify_init_answers.json
    
    success "Amplify project initialized"
}

# Add authentication service
add_authentication() {
    log "Adding Amazon Cognito authentication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would add Cognito authentication"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create auth configuration
    cat > auth_config.json << EOF
{
  "resourceName": "mobilebackend",
  "serviceType": "cognito",
  "requiredAttributes": ["email"],
  "allowUnauthenticatedIdentities": false,
  "thirdPartyAuth": false,
  "authProviders": [],
  "smsAuthenticationMessage": "Your authentication code is {####}",
  "emailAuthenticationMessage": "Your authentication code is {####}",
  "emailAuthenticationSubject": "Your verification code",
  "passwordPolicyMinLength": 8,
  "passwordPolicyCharacters": [
    "Requires Lowercase",
    "Requires Uppercase",
    "Requires Numbers",
    "Requires Symbols"
  ],
  "mfaConfiguration": "OFF",
  "mfaTypes": ["SMS Text Message"],
  "roleName": "mobilebackend",
  "roleExternalId": "mobilebackend",
  "autoVerifiedAttributes": ["email"],
  "usernameAttributes": ["email"],
  "signupAttributes": ["email"],
  "socialProviders": [],
  "userpoolClientRefreshTokenValidity": 30,
  "userpoolClientReadAttributes": ["email"],
  "userpoolClientWriteAttributes": ["email"],
  "userpoolClientGenerateSecret": false,
  "authRoleArn": {
    "Fn::GetAtt": [
      "AuthRole",
      "Arn"
    ]
  },
  "unauthRoleArn": {
    "Fn::GetAtt": [
      "UnauthRole",
      "Arn"
    ]
  },
  "functionArn": {
    "Fn::GetAtt": [
      "UserPoolClientRole",
      "Arn"
    ]
  }
}
EOF
    
    amplify add auth --headless auth_config.json
    
    success "Authentication service configured"
}

# Add GraphQL API
add_graphql_api() {
    log "Adding AWS AppSync GraphQL API..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would add AppSync GraphQL API"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create API configuration
    cat > api_config.json << EOF
{
  "serviceName": "AppSync",
  "serviceConfiguration": {
    "apiName": "MobileBackendAPI",
    "serviceName": "AppSync",
    "gqlSchemaPath": "./schema.graphql",
    "defaultAuthType": {
      "mode": "AMAZON_COGNITO_USER_POOLS",
      "cognitoUserPoolId": "authMobileBackend"
    },
    "additionalAuthTypes": [],
    "conflictResolution": {
      "defaultResolutionStrategy": {
        "type": "AUTOMERGE"
      }
    }
  }
}
EOF
    
    # Create a sample GraphQL schema
    cat > schema.graphql << EOF
type Post @model @auth(rules: [{allow: owner}]) {
  id: ID!
  title: String!
  content: String!
  owner: String
  createdAt: AWSDateTime
  updatedAt: AWSDateTime
}

type Comment @model @auth(rules: [{allow: owner}]) {
  id: ID!
  postID: ID! @index(name: "byPost")
  content: String!
  owner: String
  createdAt: AWSDateTime
  updatedAt: AWSDateTime
}

type User @model @auth(rules: [{allow: owner}]) {
  id: ID!
  username: String!
  email: AWSEmail!
  profilePicture: String
  bio: String
  createdAt: AWSDateTime
  updatedAt: AWSDateTime
}
EOF
    
    amplify add api --headless api_config.json
    
    success "GraphQL API configured"
}

# Add file storage
add_storage() {
    log "Adding Amazon S3 file storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would add S3 storage"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create storage configuration
    cat > storage_config.json << EOF
{
  "resourceName": "${PROJECT_NAME}Storage",
  "bucketName": "${STORAGE_BUCKET_NAME}",
  "storageAccess": "authAndGuest",
  "guestAccess": ["READ"],
  "authAccess": ["CREATE_AND_UPDATE", "READ", "DELETE"],
  "triggerFunction": "NONE",
  "groupAccess": {}
}
EOF
    
    amplify add storage --headless storage_config.json
    
    success "File storage configured"
}

# Add analytics and notifications
add_analytics() {
    log "Adding Amazon Pinpoint analytics and notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would add Pinpoint analytics"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create analytics configuration
    cat > analytics_config.json << EOF
{
  "appName": "${PROJECT_NAME}Analytics",
  "includeCloudWatchLogs": false,
  "config": {
    "IdentityPoolId": "authMobileBackend"
  }
}
EOF
    
    amplify add analytics --headless analytics_config.json
    
    # Add notifications
    cat > notifications_config.json << EOF
{
  "resourceName": "Notifications",
  "channels": ["FCM", "APNS"]
}
EOF
    
    amplify add notifications --headless notifications_config.json
    
    success "Analytics and notifications configured"
}

# Add Lambda function
add_function() {
    log "Adding AWS Lambda function for custom business logic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would add Lambda function"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create function configuration
    cat > function_config.json << EOF
{
  "resourceName": "${PROJECT_NAME}PostProcessor",
  "functionTemplate": "Hello World",
  "runtime": "nodejs18.x",
  "dependsOn": [],
  "environmentVariables": {},
  "secretEnvironmentVariables": []
}
EOF
    
    amplify add function --headless function_config.json
    
    # Create the function code
    mkdir -p "amplify/backend/function/${PROJECT_NAME}PostProcessor/src"
    cat > "amplify/backend/function/${PROJECT_NAME}PostProcessor/src/index.js" << 'EOF'
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));
    
    try {
        // Example: Process post creation and send notifications
        if (event.typeName === 'Mutation' && event.fieldName === 'createPost') {
            const post = event.arguments.input;
            
            // Add processing logic here
            // Example: content moderation, image processing, etc.
            
            return {
                statusCode: 200,
                body: JSON.stringify({
                    message: 'Post processed successfully',
                    postId: post.id
                })
            };
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Function executed successfully' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};
EOF
    
    success "Lambda function configured"
}

# Deploy all services
deploy_services() {
    log "Deploying all backend services to AWS..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy all services to AWS"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Deploy with automatic confirmation
    amplify push --yes
    
    success "All backend services deployed successfully"
}

# Configure client integration
setup_client() {
    log "Setting up client-side integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would setup client integration"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Install required packages
    npm install aws-amplify aws-amplify-react-native \
        amazon-cognito-identity-js @react-native-async-storage/async-storage \
        @react-native-community/netinfo react-native-get-random-values
    
    # Create src directory and configuration
    mkdir -p src
    
    cat > src/amplify-config.js << 'EOF'
import { Amplify } from 'aws-amplify';
import config from './aws-exports';

Amplify.configure(config);

export default Amplify;
EOF
    
    success "Client-side integration configured"
}

# Set up monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would setup monitoring dashboard"
        return
    fi
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-Mobile-Backend" \
        --dashboard-body "{
            \"widgets\": [
                {
                    \"type\": \"metric\",
                    \"x\": 0,
                    \"y\": 0,
                    \"width\": 12,
                    \"height\": 6,
                    \"properties\": {
                        \"metrics\": [
                            [\"AWS/AppSync\", \"4XXError\"],
                            [\"AWS/AppSync\", \"5XXError\"],
                            [\"AWS/AppSync\", \"RequestCount\"]
                        ],
                        \"period\": 300,
                        \"stat\": \"Sum\",
                        \"region\": \"${AWS_REGION}\",
                        \"title\": \"AppSync API Metrics\"
                    }
                },
                {
                    \"type\": \"metric\",
                    \"x\": 0,
                    \"y\": 6,
                    \"width\": 12,
                    \"height\": 6,
                    \"properties\": {
                        \"metrics\": [
                            [\"AWS/Cognito\", \"SignUpSuccesses\"],
                            [\"AWS/Cognito\", \"SignInSuccesses\"]
                        ],
                        \"period\": 300,
                        \"stat\": \"Sum\",
                        \"region\": \"${AWS_REGION}\",
                        \"title\": \"Cognito Authentication Metrics\"
                    }
                }
            ]
        }" || warning "Failed to create CloudWatch dashboard - continuing deployment"
    
    success "Monitoring dashboard configured"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would save deployment information"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Create deployment info file
    cat > deployment-info.json << EOF
{
  "projectName": "$PROJECT_NAME",
  "awsRegion": "$AWS_REGION",
  "awsAccountId": "$AWS_ACCOUNT_ID",
  "projectDirectory": "$PROJECT_DIR",
  "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "services": {
    "authentication": "Amazon Cognito",
    "api": "AWS AppSync (GraphQL)",
    "storage": "Amazon S3",
    "analytics": "Amazon Pinpoint",
    "functions": "AWS Lambda",
    "monitoring": "Amazon CloudWatch"
  }
}
EOF
    
    # Display deployment information
    echo ""
    success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log "Project Name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "Project Directory: $PROJECT_DIR"
    echo ""
    log "Services Deployed:"
    log "  • Amazon Cognito (Authentication)"
    log "  • AWS AppSync (GraphQL API)"
    log "  • Amazon S3 (File Storage)"
    log "  • Amazon Pinpoint (Analytics & Notifications)"
    log "  • AWS Lambda (Custom Functions)"
    log "  • Amazon CloudWatch (Monitoring)"
    echo ""
    log "Next Steps:"
    log "  1. Check amplify status: cd $PROJECT_DIR && amplify status"
    log "  2. View GraphQL schema: cd $PROJECT_DIR && amplify console api"
    log "  3. Test authentication: cd $PROJECT_DIR && amplify console auth"
    log "  4. View monitoring: aws cloudwatch get-dashboard --dashboard-name ${PROJECT_NAME}-Mobile-Backend"
    echo ""
    warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges"
    echo ""
}

# Main deployment function
main() {
    log "Mobile Backend Services with Amplify Deployment Script"
    log "=================================================="
    
    check_prerequisites
    setup_environment
    initialize_project
    add_authentication
    add_graphql_api
    add_storage
    add_analytics
    add_function
    deploy_services
    setup_client
    setup_monitoring
    save_deployment_info
    
    success "Mobile backend deployment completed successfully!"
}

# Handle script termination
cleanup_on_error() {
    error "Deployment failed. Check the logs above for details."
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        log "Project directory: $PROJECT_DIR"
        log "You may need to manually clean up resources using: amplify delete"
    fi
}

trap cleanup_on_error ERR

# Run main function
main "$@"