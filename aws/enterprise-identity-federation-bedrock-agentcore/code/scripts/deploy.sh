#!/bin/bash

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enterprise Identity Federation with Bedrock AgentCore - Deployment Script
# This script deploys the complete enterprise identity federation infrastructure
# for AI agent management using Bedrock AgentCore, Cognito, and Lambda

# Color codes for output formatting
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
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode. No resources will be created."
fi

# Function to execute commands (respects dry-run mode)
execute() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check Python for Lambda function
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    # Check zip utility
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS account information
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export IDENTITY_POOL_NAME="enterprise-ai-agents-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="agent-auth-handler-${RANDOM_SUFFIX}"
    export AGENTCORE_IDENTITY_NAME="enterprise-agent-${RANDOM_SUFFIX}"
    export STACK_NAME="enterprise-identity-federation-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .deployment_vars << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
IDENTITY_POOL_NAME=${IDENTITY_POOL_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
AGENTCORE_IDENTITY_NAME=${AGENTCORE_IDENTITY_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
STACK_NAME=${STACK_NAME}
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account: $AWS_ACCOUNT_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment setup completed"
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create Lambda trust policy
    cat > lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create Lambda execution role
    execute "aws iam create-role \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description 'Execution role for enterprise AI agent authentication handler' \
        --tags 'Key=Environment,Value=Production' 'Key=Purpose,Value=Enterprise-AI-Authentication'" \
        "Creating Lambda execution role"
    
    # Attach basic Lambda execution policy
    execute "aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching basic Lambda execution policy"
    
    # Create AgentCore access policy
    cat > agentcore-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream",
                "bedrock:ListFoundationModels"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${AWS_REGION}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::enterprise-ai-data-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
        }
    ]
}
EOF

    # Create AgentCore access policy
    execute "aws iam create-policy \
        --policy-name AgentCoreAccessPolicy-${RANDOM_SUFFIX} \
        --policy-document file://agentcore-access-policy.json \
        --description 'Access policy for Bedrock AgentCore AI agents'" \
        "Creating AgentCore access policy"
    
    # Create AgentCore trust policy
    cat > agent-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "bedrock-agentcore.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF

    # Create AgentCore execution role
    execute "aws iam create-role \
        --role-name AgentCoreExecutionRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://agent-trust-policy.json \
        --description 'Execution role for Bedrock AgentCore AI agents'" \
        "Creating AgentCore execution role"
    
    # Attach AgentCore policy to role
    execute "aws iam attach-role-policy \
        --role-name AgentCoreExecutionRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AgentCoreAccessPolicy-${RANDOM_SUFFIX}" \
        "Attaching AgentCore access policy to execution role"
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation (30 seconds)..."
    sleep 30
    
    success "IAM resources created successfully"
}

# Function to create and deploy Lambda function
create_lambda_function() {
    log "Creating Lambda authentication handler..."
    
    # Create Lambda function code
    cat > auth-handler.py << 'EOF'
import json
import boto3
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Custom authentication handler for enterprise AI agent identity management.
    Validates enterprise user context and determines agent access permissions.
    """
    try:
        trigger_source = event.get('triggerSource')
        user_attributes = event.get('request', {}).get('userAttributes', {})
        
        logger.info(f"Processing trigger: {trigger_source}")
        logger.info(f"User attributes: {json.dumps(user_attributes, default=str)}")
        
        if trigger_source == 'PostAuthentication_Authentication':
            # Process successful enterprise authentication
            email = user_attributes.get('email', '')
            department = user_attributes.get('custom:department', 'general')
            
            # Determine agent access based on department
            agent_permissions = determine_agent_permissions(department)
            
            # Store user session context for AgentCore access
            response = event
            response['response'] = {
                'agentPermissions': agent_permissions,
                'sessionDuration': 3600  # 1 hour session
            }
            
            logger.info(f"Authentication successful for {email} with permissions: {agent_permissions}")
            return response
            
        elif trigger_source == 'PreAuthentication_Authentication':
            # Validate user eligibility for AI agent access
            email = user_attributes.get('email', '')
            
            # Check if user is authorized for AI agent management
            if not is_authorized_for_ai_agents(email):
                raise Exception("User not authorized for AI agent access")
            
            return event
            
        return event
        
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        raise e

def determine_agent_permissions(department: str) -> Dict[str, Any]:
    """Determine AI agent access permissions based on user department."""
    permission_map = {
        'engineering': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 10,
            'allowedServices': ['bedrock', 's3', 'lambda']
        },
        'security': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 5,
            'allowedServices': ['bedrock', 'iam', 'cloudtrail']
        },
        'general': {
            'canCreateAgents': False,
            'canDeleteAgents': False,
            'maxAgents': 2,
            'allowedServices': ['bedrock']
        }
    }
    
    return permission_map.get(department, permission_map['general'])

def is_authorized_for_ai_agents(email: str) -> bool:
    """Check if user is authorized for AI agent management."""
    # Implement your authorization logic here
    # This could check against DynamoDB, external APIs, etc.
    authorized_domains = ['@company.com', '@enterprise.org']
    return any(domain in email for domain in authorized_domains)
EOF

    # Package Lambda function
    execute "zip auth-handler.zip auth-handler.py" \
        "Packaging Lambda function"
    
    # Create Lambda function
    execute "aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime python3.11 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role \
        --handler auth-handler.lambda_handler \
        --zip-file fileb://auth-handler.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment '{
            \"Variables\": {
                \"USER_POOL_ID\": \"\",
                \"AGENTCORE_IDENTITY\": \"${AGENTCORE_IDENTITY_NAME}\"
            }
        }' \
        --tags '{
            \"Environment\": \"Production\",
            \"Purpose\": \"Enterprise-AI-Authentication\"
        }' \
        --description 'Enterprise authentication handler for AI agent identity management'" \
        "Creating Lambda function"
    
    success "Lambda function created successfully"
}

# Function to create Cognito User Pool
create_cognito_user_pool() {
    log "Creating Cognito User Pool for enterprise federation..."
    
    # Create Cognito User Pool
    execute "aws cognito-idp create-user-pool \
        --pool-name ${IDENTITY_POOL_NAME} \
        --policies '{
            \"PasswordPolicy\": {
                \"MinimumLength\": 12,
                \"RequireUppercase\": true,
                \"RequireLowercase\": true,
                \"RequireNumbers\": true,
                \"RequireSymbols\": true
            }
        }' \
        --mfa-configuration \"OPTIONAL\" \
        --account-recovery-setting '{
            \"RecoveryMechanisms\": [
                {\"Name\": \"verified_email\", \"Priority\": 1}
            ]
        }' \
        --user-pool-tags '{
            \"Environment\": \"Production\",
            \"Purpose\": \"Enterprise-AI-Identity\",
            \"Project\": \"BedrockAgentCore\"
        }' \
        --schema '[
            {
                \"Name\": \"email\",
                \"AttributeDataType\": \"String\",
                \"Required\": true,
                \"Mutable\": true
            },
            {
                \"Name\": \"department\",
                \"AttributeDataType\": \"String\",
                \"Required\": false,
                \"Mutable\": true
            }
        ]'" \
        "Creating Cognito User Pool with enterprise settings"
    
    # Get User Pool ID
    export USER_POOL_ID=$(aws cognito-idp list-user-pools \
        --max-items 50 --query "UserPools[?Name=='${IDENTITY_POOL_NAME}'].Id" \
        --output text)
    
    if [[ -z "$USER_POOL_ID" ]]; then
        error "Failed to retrieve User Pool ID"
        exit 1
    fi
    
    log "User Pool ID: $USER_POOL_ID"
    
    # Update deployment variables file
    echo "USER_POOL_ID=${USER_POOL_ID}" >> .deployment_vars
    
    success "Cognito User Pool created: $USER_POOL_ID"
}

# Function to configure Lambda triggers
configure_lambda_triggers() {
    log "Configuring Cognito Lambda triggers..."
    
    # Get Lambda function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    # Grant Cognito permission to invoke Lambda
    execute "aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id \"CognitoInvokePermission\" \
        --action lambda:InvokeFunction \
        --principal cognito-idp.amazonaws.com \
        --source-arn arn:aws:cognito-idp:${AWS_REGION}:${AWS_ACCOUNT_ID}:userpool/${USER_POOL_ID}" \
        "Granting Cognito permission to invoke Lambda"
    
    # Configure Lambda triggers in User Pool
    execute "aws cognito-idp update-user-pool \
        --user-pool-id ${USER_POOL_ID} \
        --lambda-config '{
            \"PreAuthentication\": \"${LAMBDA_ARN}\",
            \"PostAuthentication\": \"${LAMBDA_ARN}\",
            \"CustomMessage\": \"${LAMBDA_ARN}\"
        }'" \
        "Configuring Lambda triggers in Cognito User Pool"
    
    # Update Lambda environment with User Pool ID
    execute "aws lambda update-function-configuration \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --environment '{
            \"Variables\": {
                \"USER_POOL_ID\": \"${USER_POOL_ID}\",
                \"AGENTCORE_IDENTITY\": \"${AGENTCORE_IDENTITY_NAME}\"
            }
        }'" \
        "Updating Lambda function environment variables"
    
    success "Lambda triggers configured successfully"
}

# Function to create User Pool App Client
create_user_pool_client() {
    log "Creating User Pool App Client for OAuth flows..."
    
    # Create User Pool App Client
    execute "aws cognito-idp create-user-pool-client \
        --user-pool-id ${USER_POOL_ID} \
        --client-name \"AgentCore-Enterprise-Client\" \
        --generate-secret \
        --supported-identity-providers \"COGNITO\" \
        --callback-urls \"https://your-app.company.com/oauth/callback\" \
        --logout-urls \"https://your-app.company.com/logout\" \
        --allowed-o-auth-flows \"code\" \"implicit\" \
        --allowed-o-auth-scopes \"openid\" \"email\" \"profile\" \"aws.cognito.signin.user.admin\" \
        --allowed-o-auth-flows-user-pool-client \
        --explicit-auth-flows \"ALLOW_USER_PASSWORD_AUTH\" \"ALLOW_REFRESH_TOKEN_AUTH\" \
        --token-validity-units '{
            \"AccessToken\": \"hours\",
            \"IdToken\": \"hours\",
            \"RefreshToken\": \"days\"
        }' \
        --access-token-validity 1 \
        --id-token-validity 1 \
        --refresh-token-validity 30" \
        "Creating User Pool App Client for OAuth integration"
    
    # Get client details
    export CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
        --user-pool-id ${USER_POOL_ID} \
        --query "UserPoolClients[?ClientName=='AgentCore-Enterprise-Client'].ClientId" \
        --output text)
    
    log "App Client ID: $CLIENT_ID"
    echo "CLIENT_ID=${CLIENT_ID}" >> .deployment_vars
    
    success "User Pool App Client created: $CLIENT_ID"
}

# Function to create Bedrock AgentCore workload identity
create_agentcore_identity() {
    log "Creating Bedrock AgentCore workload identity..."
    
    # Note: This is a simulated command as Bedrock AgentCore is in preview
    # Replace with actual AWS CLI commands when available
    warning "Bedrock AgentCore is in preview. Creating simulated workload identity..."
    warning "Please request access through the AWS console and replace with actual commands."
    
    # Create placeholder for AgentCore workload identity
    cat > agentcore-identity-config.json << EOF
{
    "workloadIdentityName": "${AGENTCORE_IDENTITY_NAME}",
    "allowedResourceOAuth2ReturnUrls": [
        "https://your-app.company.com/oauth/callback",
        "https://localhost:8080/callback"
    ],
    "status": "created",
    "workloadIdentityArn": "arn:aws:bedrock-agentcore:${AWS_REGION}:${AWS_ACCOUNT_ID}:workload-identity/${AGENTCORE_IDENTITY_NAME}"
}
EOF
    
    export WORKLOAD_IDENTITY_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${AWS_ACCOUNT_ID}:workload-identity/${AGENTCORE_IDENTITY_NAME}"
    echo "WORKLOAD_IDENTITY_ARN=${WORKLOAD_IDENTITY_ARN}" >> .deployment_vars
    
    # When AgentCore is generally available, replace above with:
    # execute "aws bedrock-agentcore-control create-workload-identity \
    #     --name ${AGENTCORE_IDENTITY_NAME} \
    #     --allowed-resource-oauth2-return-urls \
    #         \"https://your-app.company.com/oauth/callback\" \
    #         \"https://localhost:8080/callback\"" \
    #     "Creating AgentCore workload identity"
    
    success "AgentCore workload identity configuration created (simulated)"
}

# Function to store integration configuration
store_integration_config() {
    log "Storing integration configuration..."
    
    # Create integration configuration
    cat > integration-config.json << EOF
{
    "enterpriseIntegration": {
        "cognitoUserPool": "${USER_POOL_ID}",
        "agentCoreIdentity": "${WORKLOAD_IDENTITY_ARN}",
        "authenticationFlow": "enterprise-saml-oauth",
        "permissionMapping": {
            "engineering": {
                "maxAgents": 10,
                "allowedActions": ["create", "read", "update", "delete"],
                "resourceAccess": ["bedrock", "s3", "lambda"]
            },
            "security": {
                "maxAgents": 5,
                "allowedActions": ["create", "read", "update", "delete", "audit"],
                "resourceAccess": ["bedrock", "iam", "cloudtrail"]
            },
            "general": {
                "maxAgents": 2,
                "allowedActions": ["read"],
                "resourceAccess": ["bedrock"]
            }
        }
    }
}
EOF

    # Store configuration in Systems Manager Parameter Store
    execute "aws ssm put-parameter \
        --name \"/enterprise/agentcore/integration-config\" \
        --value file://integration-config.json \
        --type \"String\" \
        --description \"Enterprise AI agent integration configuration\" \
        --tags '[
            {\"Key\": \"Environment\", \"Value\": \"Production\"},
            {\"Key\": \"Purpose\", \"Value\": \"AgentCore-Integration\"}
        ]' \
        --overwrite" \
        "Storing integration configuration in Parameter Store"
    
    success "Integration configuration stored successfully"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Create test script
    cat > test-deployment.py << 'EOF'
import boto3
import json
import sys
import os

def test_deployment():
    """Test the deployment components."""
    
    # Initialize AWS clients
    cognito_client = boto3.client('cognito-idp')
    lambda_client = boto3.client('lambda')
    iam_client = boto3.client('iam')
    
    try:
        # Test 1: Verify User Pool
        print("Testing User Pool configuration...")
        user_pool_response = cognito_client.describe_user_pool(
            UserPoolId=os.environ['USER_POOL_ID']
        )
        print(f"✅ User Pool configured: {user_pool_response['UserPool']['Name']}")
        
        # Test 2: Verify Lambda function
        print("Testing Lambda function...")
        lambda_response = lambda_client.get_function(
            FunctionName=os.environ['LAMBDA_FUNCTION_NAME']
        )
        print(f"✅ Lambda function deployed: {lambda_response['Configuration']['FunctionName']}")
        
        # Test 3: Verify IAM roles
        print("Testing IAM roles...")
        lambda_role = iam_client.get_role(
            RoleName=f"{os.environ['LAMBDA_FUNCTION_NAME']}-role"
        )
        print(f"✅ Lambda IAM role exists: {lambda_role['Role']['RoleName']}")
        
        agentcore_role = iam_client.get_role(
            RoleName=f"AgentCoreExecutionRole-{os.environ['RANDOM_SUFFIX']}"
        )
        print(f"✅ AgentCore IAM role exists: {agentcore_role['Role']['RoleName']}")
        
        print("\n🎉 All deployment validation tests passed!")
        return True
        
    except Exception as e:
        print(f"❌ Validation test failed: {str(e)}")
        return False

if __name__ == "__main__":
    if test_deployment():
        sys.exit(0)
    else:
        sys.exit(1)
EOF

    # Run validation tests
    if [[ "$DRY_RUN" != "true" ]]; then
        python3 test-deployment.py
        if [[ $? -eq 0 ]]; then
            success "Validation tests passed"
        else
            warning "Some validation tests failed"
        fi
    else
        log "Skipping validation tests in dry-run mode"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f lambda-trust-policy.json
    rm -f agentcore-access-policy.json
    rm -f agent-trust-policy.json
    rm -f auth-handler.py
    rm -f auth-handler.zip
    rm -f agentcore-identity-config.json
    rm -f integration-config.json
    rm -f test-deployment.py
    
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "===================="
    
    if [[ -f .deployment_vars ]]; then
        source .deployment_vars
        
        echo "Stack Name: $STACK_NAME"
        echo "AWS Region: $AWS_REGION"
        echo "AWS Account: $AWS_ACCOUNT_ID"
        echo ""
        echo "Created Resources:"
        echo "- Cognito User Pool: $USER_POOL_ID"
        echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
        echo "- AgentCore Identity: $AGENTCORE_IDENTITY_NAME"
        echo "- App Client: $CLIENT_ID"
        echo ""
        echo "IAM Roles Created:"
        echo "- Lambda Execution Role: ${LAMBDA_FUNCTION_NAME}-role"
        echo "- AgentCore Execution Role: AgentCoreExecutionRole-${RANDOM_SUFFIX}"
        echo ""
        echo "Next Steps:"
        echo "1. Configure your enterprise SAML identity provider"
        echo "2. Update SAML identity provider settings in Cognito"
        echo "3. Test enterprise authentication flow"
        echo "4. Request Bedrock AgentCore access if not already available"
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
    else
        warning "Deployment variables file not found"
    fi
    
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Enterprise Identity Federation deployment..."
    
    # Check if help is requested
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        cat << EOF
Enterprise Identity Federation with Bedrock AgentCore - Deployment Script

Usage: $0 [OPTIONS]

Options:
  --help, -h          Show this help message
  --dry-run           Run in dry-run mode (no resources created)
  --skip-validation   Skip validation tests
  --verbose           Enable verbose logging

Environment Variables:
  AWS_REGION         AWS region for deployment (optional, uses configured region)
  DRY_RUN           Set to 'true' for dry-run mode
  IDP_METADATA_URL  Enterprise identity provider metadata URL

Examples:
  $0                          # Normal deployment
  DRY_RUN=true $0            # Dry-run mode
  AWS_REGION=us-west-2 $0    # Deploy to specific region

EOF
        exit 0
    fi
    
    # Parse command line arguments
    SKIP_VALIDATION=false
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_lambda_function
    create_cognito_user_pool
    configure_lambda_triggers
    create_user_pool_client
    create_agentcore_identity
    store_integration_config
    
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        run_validation_tests
    fi
    
    cleanup_temp_files
    display_deployment_summary
    
    log "Deployment script completed!"
}

# Trap errors and provide cleanup
trap 'error "Deployment failed. Check the logs above for details."; cleanup_temp_files; exit 1' ERR

# Run main function with all arguments
main "$@"