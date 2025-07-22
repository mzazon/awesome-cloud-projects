#!/bin/bash

# Deploy script for Automated Development Environment Provisioning with WorkSpaces Personal
# This script provisions the complete automation infrastructure including Lambda, IAM, SSM, and EventBridge

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEPLOYMENT_LOG="$PROJECT_ROOT/deployment.log"

# Initialize deployment log
echo "=== Deployment started at $(date) ===" > "$DEPLOYMENT_LOG"

# Cleanup function for script interruption
cleanup() {
    log_warning "Deployment interrupted. Check $DEPLOYMENT_LOG for details."
    exit 1
}

trap cleanup SIGINT SIGTERM

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version
    major_version=$(echo "$aws_version" | cut -d. -f1)
    if [[ "$major_version" -lt 2 ]]; then
        log_error "AWS CLI version 2.0 or later is required. Current version: $aws_version"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local tools=("python3" "zip" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    log_success "All prerequisites met"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Get AWS account details
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured. Please set AWS_REGION or run 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    export PROJECT_NAME="devenv-automation"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-provisioner-${random_suffix}"
    export IAM_ROLE_NAME="${PROJECT_NAME}-lambda-role-${random_suffix}"
    export SECRET_NAME="${PROJECT_NAME}-ad-credentials-${random_suffix}"
    export SSM_DOCUMENT_NAME="${PROJECT_NAME}-dev-setup-${random_suffix}"
    export EVENTBRIDGE_RULE_NAME="${PROJECT_NAME}-daily-provisioning-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Save environment variables for cleanup script
    cat > "$PROJECT_ROOT/deployment-vars.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
PROJECT_NAME=$PROJECT_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
SECRET_NAME=$SECRET_NAME
SSM_DOCUMENT_NAME=$SSM_DOCUMENT_NAME
EVENTBRIDGE_RULE_NAME=$EVENTBRIDGE_RULE_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Environment variables configured (Random suffix: $random_suffix)"
}

# Function to create Secrets Manager secret
create_secrets_manager_secret() {
    log_info "Creating Secrets Manager secret for AD credentials..."
    
    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        log_warning "Secret $SECRET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Default credentials (should be updated after deployment)
    local secret_value='{"username":"workspaces-service","password":"ChangeMe123!"}'
    
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "AD service account credentials for WorkSpaces automation" \
        --secret-string "$secret_value" \
        --tags Key=Project,Value="$PROJECT_NAME" \
        --output table >> "$DEPLOYMENT_LOG" 2>&1
    
    export SECRET_ARN
    SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET_NAME" \
        --query ARN --output text)
    
    log_success "Secret created with ARN: $SECRET_ARN"
    log_warning "Remember to update the secret with actual AD credentials after deployment"
}

# Function to create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM role and policies..."
    
    # Create trust policy
    cat > "$PROJECT_ROOT/lambda-trust-policy.json" << 'EOF'
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
    
    # Check if role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log_warning "IAM role $IAM_ROLE_NAME already exists, skipping creation"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document "file://$PROJECT_ROOT/lambda-trust-policy.json" \
            --description "Service role for WorkSpaces automation Lambda function" \
            --tags Key=Project,Value="$PROJECT_NAME" \
            --output table >> "$DEPLOYMENT_LOG" 2>&1
        
        log_success "IAM role created: $IAM_ROLE_NAME"
    fi
    
    # Create permissions policy
    cat > "$PROJECT_ROOT/lambda-permissions-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "workspaces:CreateWorkspaces",
        "workspaces:TerminateWorkspaces",
        "workspaces:DescribeWorkspaces",
        "workspaces:DescribeWorkspaceDirectories",
        "workspaces:DescribeWorkspaceBundles",
        "workspaces:ModifyWorkspaceProperties"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:DescribeInstanceInformation",
        "ssm:GetDocument",
        "ssm:ListDocuments",
        "ssm:DescribeDocumentParameters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "$SECRET_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:/aws/lambda/$LAMBDA_FUNCTION_NAME:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:DetachNetworkInterface"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    local policy_name="${PROJECT_NAME}-lambda-policy-${RANDOM_SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log_warning "IAM policy $policy_name already exists, skipping creation"
    else
        # Create and attach policy
        aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "file://$PROJECT_ROOT/lambda-permissions-policy.json" \
            --description "Permissions for WorkSpaces automation Lambda function" \
            --tags Key=Project,Value="$PROJECT_NAME" \
            --output table >> "$DEPLOYMENT_LOG" 2>&1
        
        log_success "IAM policy created: $policy_name"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "$policy_arn" \
        --output table >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "IAM policy attached to role"
}

# Function to create Systems Manager document
create_ssm_document() {
    log_info "Creating Systems Manager document..."
    
    # Check if document already exists
    if aws ssm describe-document --name "$SSM_DOCUMENT_NAME" &>/dev/null; then
        log_warning "SSM document $SSM_DOCUMENT_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create SSM document content
    cat > "$PROJECT_ROOT/dev-environment-setup.json" << 'EOF'
{
  "schemaVersion": "2.2",
  "description": "Configure development environment on WorkSpaces",
  "parameters": {
    "developmentTools": {
      "type": "String",
      "description": "Comma-separated list of development tools to install",
      "default": "git,vscode,nodejs,python,docker"
    },
    "teamConfiguration": {
      "type": "String",
      "description": "Team-specific configuration settings",
      "default": "standard"
    }
  },
  "mainSteps": [
    {
      "action": "aws:runPowerShellScript",
      "name": "InstallChocolatey",
      "inputs": {
        "runCommand": [
          "Write-Output 'Installing Chocolatey package manager...'",
          "Set-ExecutionPolicy Bypass -Scope Process -Force",
          "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
          "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))",
          "Write-Output 'Chocolatey installation completed'"
        ]
      }
    },
    {
      "action": "aws:runPowerShellScript",
      "name": "InstallDevelopmentTools",
      "inputs": {
        "runCommand": [
          "Write-Output 'Installing development tools...'",
          "$tools = '{{ developmentTools }}'.Split(',')",
          "foreach ($tool in $tools) {",
          "  $trimmedTool = $tool.Trim()",
          "  Write-Output \"Installing $trimmedTool...\"",
          "  switch ($trimmedTool) {",
          "    'git' { choco install git -y --no-progress }",
          "    'vscode' { choco install vscode -y --no-progress }",
          "    'nodejs' { choco install nodejs -y --no-progress }",
          "    'python' { choco install python -y --no-progress }",
          "    'docker' { choco install docker-desktop -y --no-progress }",
          "    default { Write-Output \"Unknown tool: $trimmedTool\" }",
          "  }",
          "}",
          "Write-Output 'Development environment setup completed successfully'"
        ]
      }
    },
    {
      "action": "aws:runPowerShellScript",
      "name": "ConfigureEnvironment",
      "inputs": {
        "runCommand": [
          "Write-Output 'Configuring development environment...'",
          "# Set Git global configuration",
          "git config --global init.defaultBranch main",
          "git config --global pull.rebase false",
          "# Create development directories",
          "New-Item -ItemType Directory -Force -Path C:\\Dev\\Projects",
          "New-Item -ItemType Directory -Force -Path C:\\Dev\\Tools",
          "Write-Output 'Environment configuration completed'"
        ]
      }
    }
  ]
}
EOF
    
    # Create the SSM document
    aws ssm create-document \
        --name "$SSM_DOCUMENT_NAME" \
        --document-type "Command" \
        --document-format JSON \
        --content "file://$PROJECT_ROOT/dev-environment-setup.json" \
        --tags Key=Project,Value="$PROJECT_NAME" \
               Key=Purpose,Value=DevEnvironmentAutomation \
        --output table >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "Systems Manager document created: $SSM_DOCUMENT_NAME"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create Lambda package directory
    local lambda_dir="$PROJECT_ROOT/lambda-package"
    mkdir -p "$lambda_dir"
    
    # Create Lambda function code
    cat > "$lambda_dir/lambda_function.py" << 'EOF'
import json
import boto3
import logging
import time
from botocore.exceptions import ClientError
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for WorkSpaces automation
    
    Args:
        event: Event data containing configuration parameters
        context: Lambda runtime information
        
    Returns:
        Response with status and results
    """
    try:
        # Initialize AWS clients
        workspaces_client = boto3.client('workspaces')
        ssm_client = boto3.client('ssm')
        secrets_client = boto3.client('secretsmanager')
        
        logger.info("Starting WorkSpaces automation process")
        
        # Validate required event parameters
        required_params = ['secret_name', 'directory_id', 'bundle_id']
        for param in required_params:
            if param not in event:
                raise ValueError(f"Missing required parameter: {param}")
        
        # Get AD credentials from Secrets Manager
        credentials = get_ad_credentials(secrets_client, event['secret_name'])
        
        # Get current WorkSpaces
        current_workspaces = get_current_workspaces(workspaces_client, event['directory_id'])
        logger.info(f"Found {len(current_workspaces)} existing WorkSpaces")
        
        # Get users who should have WorkSpaces (simplified for demo)
        target_users = get_target_users(event)
        logger.info(f"Target users: {target_users}")
        
        # Provision WorkSpaces for new users
        provision_results = provision_workspaces(
            workspaces_client, ssm_client, 
            target_users, current_workspaces, event
        )
        
        # Configure new WorkSpaces
        configuration_results = configure_workspaces(
            ssm_client, provision_results, event
        )
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'WorkSpaces provisioning completed successfully',
                'provisioned': provision_results,
                'configured': configuration_results,
                'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
            })
        }
        
        logger.info("WorkSpaces automation completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Error in WorkSpaces automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'WorkSpaces automation failed'
            })
        }

def get_ad_credentials(secrets_client: Any, secret_name: str) -> Dict[str, str]:
    """Retrieve AD credentials from Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except ClientError as e:
        logger.error(f"Failed to retrieve credentials: {e}")
        raise

def get_current_workspaces(workspaces_client: Any, directory_id: str) -> Dict[str, str]:
    """Get list of current WorkSpaces for the directory"""
    try:
        response = workspaces_client.describe_workspaces(
            DirectoryId=directory_id
        )
        return {
            ws['UserName']: ws['WorkspaceId'] 
            for ws in response['Workspaces']
            if ws['State'] in ['AVAILABLE', 'PENDING', 'STARTING', 'REBUILDING']
        }
    except ClientError as e:
        logger.error(f"Failed to describe WorkSpaces: {e}")
        return {}

def get_target_users(event: Dict[str, Any]) -> List[str]:
    """Get list of users who should have WorkSpaces"""
    # In production, this would query Active Directory
    # For demo purposes, using a static list from event or default
    return event.get('target_users', ['developer1', 'developer2', 'developer3'])

def provision_workspaces(
    workspaces_client: Any, 
    ssm_client: Any,
    target_users: List[str], 
    current_workspaces: Dict[str, str], 
    event: Dict[str, Any]
) -> List[Dict[str, str]]:
    """Provision WorkSpaces for users who don't have them"""
    results = []
    
    for user in target_users:
        if user not in current_workspaces:
            try:
                logger.info(f"Creating WorkSpace for user: {user}")
                
                response = workspaces_client.create_workspaces(
                    Workspaces=[{
                        'DirectoryId': event['directory_id'],
                        'UserName': user,
                        'BundleId': event['bundle_id'],
                        'WorkspaceProperties': {
                            'RunningMode': 'AUTO_STOP',
                            'RunningModeAutoStopTimeoutInMinutes': 60,
                            'UserVolumeEncryptionEnabled': True,
                            'RootVolumeEncryptionEnabled': True
                        },
                        'Tags': [
                            {'Key': 'Project', 'Value': 'DevEnvironmentAutomation'},
                            {'Key': 'User', 'Value': user},
                            {'Key': 'Environment', 'Value': 'Development'}
                        ]
                    }]
                )
                
                if response['PendingRequests']:
                    workspace_id = response['PendingRequests'][0]['WorkspaceId']
                    results.append({
                        'user': user,
                        'workspace_id': workspace_id,
                        'status': 'created'
                    })
                    logger.info(f"Successfully created WorkSpace {workspace_id} for {user}")
                
            except ClientError as e:
                logger.error(f"Failed to create WorkSpace for {user}: {e}")
                results.append({
                    'user': user,
                    'status': 'failed',
                    'error': str(e)
                })
        else:
            logger.info(f"User {user} already has WorkSpace: {current_workspaces[user]}")
    
    return results

def configure_workspaces(
    ssm_client: Any, 
    provision_results: List[Dict[str, str]], 
    event: Dict[str, Any]
) -> List[Dict[str, str]]:
    """Configure newly provisioned WorkSpaces"""
    configuration_results = []
    
    # Note: In production, you would wait for WorkSpaces to be available
    # and then send SSM commands to configure them
    
    for result in provision_results:
        if result.get('status') == 'created':
            configuration_results.append({
                'workspace_id': result['workspace_id'],
                'user': result['user'],
                'configuration_status': 'scheduled'
            })
    
    return configuration_results
EOF
    
    # Create deployment package
    cd "$lambda_dir"
    zip -r "../lambda-deployment-package.zip" . >> "$DEPLOYMENT_LOG" 2>&1
    cd - > /dev/null
    
    # Get IAM role ARN
    local role_arn
    role_arn=$(aws iam get-role --role-name "$IAM_ROLE_NAME" \
        --query Role.Arn --output text)
    
    # Wait for role to be ready
    log_info "Waiting for IAM role to be ready..."
    sleep 10
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code"
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file "fileb://$PROJECT_ROOT/lambda-deployment-package.zip" \
            --output table >> "$DEPLOYMENT_LOG" 2>&1
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$role_arn" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://$PROJECT_ROOT/lambda-deployment-package.zip" \
            --timeout 300 \
            --memory-size 256 \
            --description "Automated WorkSpaces provisioning for development teams" \
            --tags Project="$PROJECT_NAME",Purpose=DevEnvironmentAutomation \
            --output table >> "$DEPLOYMENT_LOG" 2>&1
    fi
    
    log_success "Lambda function deployed: $LAMBDA_FUNCTION_NAME"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log_info "Creating EventBridge rule..."
    
    # Check if rule already exists
    if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" &>/dev/null; then
        log_warning "EventBridge rule $EVENTBRIDGE_RULE_NAME already exists, skipping creation"
    else
        # Create EventBridge rule
        aws events put-rule \
            --name "$EVENTBRIDGE_RULE_NAME" \
            --schedule-expression "rate(24 hours)" \
            --description "Daily WorkSpaces provisioning automation" \
            --state ENABLED \
            --tags Key=Project,Value="$PROJECT_NAME" \
            --output table >> "$DEPLOYMENT_LOG" 2>&1
        
        log_success "EventBridge rule created: $EVENTBRIDGE_RULE_NAME"
    fi
    
    # Get Lambda function ARN
    local lambda_arn
    lambda_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "allow-eventbridge-invocation" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENTBRIDGE_RULE_NAME" \
        --output table >> "$DEPLOYMENT_LOG" 2>&1 || log_warning "Permission might already exist"
    
    # Create target for the rule (using example values - update for production)
    local target_input
    target_input=$(cat << EOF
{
  "secret_name": "$SECRET_NAME",
  "directory_id": "d-906734e6b2",
  "bundle_id": "wsb-b0s22j3d7",
  "target_users": ["developer1", "developer2", "developer3"],
  "ssm_document": "$SSM_DOCUMENT_NAME"
}
EOF
)
    
    aws events put-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --targets "Id=1,Arn=$lambda_arn,Input=$target_input" \
        --output table >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "EventBridge rule configured with Lambda target"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Create test event
    cat > "$PROJECT_ROOT/test-event.json" << EOF
{
  "secret_name": "$SECRET_NAME",
  "directory_id": "d-906734e6b2",
  "bundle_id": "wsb-b0s22j3d7",
  "target_users": ["testuser1", "testuser2"],
  "ssm_document": "$SSM_DOCUMENT_NAME"
}
EOF
    
    # Test Lambda function
    log_info "Invoking Lambda function for testing..."
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "file://$PROJECT_ROOT/test-event.json" \
        --cli-binary-format raw-in-base64-out \
        "$PROJECT_ROOT/response.json" >> "$DEPLOYMENT_LOG" 2>&1
    
    # Check response
    if [[ -f "$PROJECT_ROOT/response.json" ]]; then
        log_info "Lambda function response:"
        cat "$PROJECT_ROOT/response.json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2))
except:
    print('Invalid JSON response')
"
        log_success "Lambda function test completed"
    else
        log_error "Failed to get Lambda function response"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "Project: $PROJECT_NAME"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- Secret: $SECRET_NAME"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo "- SSM Document: $SSM_DOCUMENT_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Update the secret $SECRET_NAME with actual AD credentials"
    echo "2. Update EventBridge rule target with your actual directory_id and bundle_id"
    echo "3. Test the automation with actual WorkSpaces configuration"
    echo "4. Monitor CloudWatch logs for the Lambda function"
    echo ""
    echo "Configuration saved to: $PROJECT_ROOT/deployment-vars.env"
    echo "Deployment log: $DEPLOYMENT_LOG"
}

# Main deployment function
main() {
    log_info "Starting deployment of WorkSpaces automation infrastructure..."
    
    check_prerequisites
    set_environment_variables
    create_secrets_manager_secret
    create_iam_resources
    create_ssm_document
    create_lambda_function
    create_eventbridge_rule
    test_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
    echo "=== Deployment completed at $(date) ===" >> "$DEPLOYMENT_LOG"
}

# Run main function
main "$@"