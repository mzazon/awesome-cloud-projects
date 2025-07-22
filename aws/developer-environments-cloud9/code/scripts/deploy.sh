#!/bin/bash

# AWS Cloud9 Developer Environments Deployment Script
# This script creates a Cloud9 development environment with pre-configured tools and settings

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
handle_error() {
    error "An error occurred on line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check for required permissions (basic test)
    if ! aws cloud9 list-environments &> /dev/null; then
        error "Insufficient permissions for Cloud9 operations."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to generate unique suffix
generate_suffix() {
    # Try to use AWS Secrets Manager for random string, fallback to timestamp
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    log "Generated unique suffix: ${RANDOM_SUFFIX}"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    export CLOUD9_ENV_NAME="dev-environment-${RANDOM_SUFFIX}"
    export CLOUD9_DESCRIPTION="Shared development environment for team collaboration"
    export INSTANCE_TYPE="t3.medium"
    
    # Get default subnet ID
    export SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
        warning "No default subnet found, will use first available subnet"
        export SUBNET_ID=$(aws ec2 describe-subnets \
            --query 'Subnets[0].SubnetId' --output text)
    fi
    
    if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
        error "No subnets available in the region"
        exit 1
    fi
    
    success "Environment variables configured"
    log "  AWS Region: ${AWS_REGION}"
    log "  Account ID: ${AWS_ACCOUNT_ID}"
    log "  Environment Name: ${CLOUD9_ENV_NAME}"
    log "  Subnet ID: ${SUBNET_ID}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Cloud9 environment..."
    
    local role_name="Cloud9-${RANDOM_SUFFIX}-Role"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        warning "IAM role $role_name already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' > /dev/null
    
    # Attach basic policies for development
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/AWSCloud9EnvironmentMember
    
    export IAM_ROLE_NAME="$role_name"
    success "IAM role created: ${IAM_ROLE_NAME}"
}

# Function to create Cloud9 environment
create_cloud9_environment() {
    log "Creating Cloud9 development environment..."
    
    # Create the Cloud9 environment
    ENVIRONMENT_ID=$(aws cloud9 create-environment-ec2 \
        --name "${CLOUD9_ENV_NAME}" \
        --description "${CLOUD9_DESCRIPTION}" \
        --instance-type "${INSTANCE_TYPE}" \
        --image-id amazonlinux-2023-x86_64 \
        --subnet-id "${SUBNET_ID}" \
        --automatic-stop-time-minutes 60 \
        --query 'environmentId' --output text)
    
    export ENVIRONMENT_ID
    success "Cloud9 environment created with ID: ${ENVIRONMENT_ID}"
    
    # Save environment ID to file for cleanup
    echo "$ENVIRONMENT_ID" > .cloud9_environment_id
    echo "$RANDOM_SUFFIX" > .deployment_suffix
}

# Function to wait for environment to be ready
wait_for_environment() {
    log "Waiting for environment to be ready (this may take 2-3 minutes)..."
    
    local max_attempts=24  # 12 minutes total (24 * 30 seconds)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws cloud9 describe-environment-status \
            --environment-id "${ENVIRONMENT_ID}" \
            --query 'status' --output text)
        
        if [ "$STATUS" = "ready" ]; then
            success "Environment is ready"
            return 0
        elif [ "$STATUS" = "error" ]; then
            error "Environment creation failed"
            return 1
        fi
        
        log "Environment status: $STATUS - waiting... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    error "Timeout waiting for environment to be ready"
    return 1
}

# Function to configure environment settings
configure_environment() {
    log "Configuring environment settings..."
    
    # Update environment with custom settings
    aws cloud9 update-environment \
        --environment-id "${ENVIRONMENT_ID}" \
        --description "Development environment with pre-configured tools and settings"
    
    # Get environment details
    aws cloud9 describe-environments \
        --environment-ids "${ENVIRONMENT_ID}" \
        --query 'environments[0].{Name:name,Type:type,Status:lifecycle.status}' \
        --output table
    
    success "Environment settings configured"
}

# Function to create setup scripts
create_setup_scripts() {
    log "Creating environment setup scripts..."
    
    # Create setup script for Cloud9 environment
    cat > cloud9-setup.sh << 'EOF'
#!/bin/bash
# Cloud9 Environment Setup Script

echo "Starting Cloud9 environment setup..."

# Update system packages
sudo yum update -y

# Install additional development tools
sudo yum install -y git htop tree jq

# Install Node.js and npm (latest LTS)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install --lts
nvm use --lts

# Install Python tools
pip3 install --user virtualenv pytest flake8

# Configure Git (users should set their own credentials)
git config --global init.defaultBranch main
git config --global pull.rebase false

# Create common project structure
mkdir -p ~/projects/{frontend,backend,scripts}

echo "Development environment setup complete!"
EOF
    
    # Create environment configuration file
    cat > environment-config.sh << 'EOF'
#!/bin/bash
# Cloud9 Environment Configuration

# Common environment variables
export NODE_ENV=development
export PYTHONPATH="$HOME/projects:$PYTHONPATH"
export PATH="$HOME/.local/bin:$PATH"

# Helpful aliases
alias ll='ls -la'
alias la='ls -la'
alias proj='cd ~/projects'
alias gs='git status'
alias gp='git pull'
alias gc='git commit'
alias gco='git checkout'

# AWS CLI shortcuts
alias awsprofile='aws configure list'
alias awsregion='aws configure get region'

# Development shortcuts
alias serve='python3 -m http.server 8080'
alias venv='python3 -m venv'

echo "Environment configuration loaded"
EOF
    
    success "Setup scripts created"
}

# Function to create CodeCommit repository
create_codecommit_repo() {
    log "Creating CodeCommit repository..."
    
    local repo_name="team-development-repo-${RANDOM_SUFFIX}"
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "$repo_name" &> /dev/null; then
        warning "CodeCommit repository $repo_name already exists"
        export REPO_NAME="$repo_name"
        return 0
    fi
    
    # Create repository
    aws codecommit create-repository \
        --repository-name "$repo_name" \
        --repository-description "Team development repository for Cloud9 environment" > /dev/null
    
    # Get repository clone URL
    REPO_URL=$(aws codecommit get-repository \
        --repository-name "$repo_name" \
        --query 'repositoryMetadata.cloneUrlHttp' --output text)
    
    export REPO_NAME="$repo_name"
    export REPO_URL
    
    # Save repo name for cleanup
    echo "$repo_name" > .codecommit_repo_name
    
    success "CodeCommit repository created: ${REPO_URL}"
}

# Function to create project templates
create_project_templates() {
    log "Creating project templates..."
    
    mkdir -p project-templates/{web-app,api-service,data-pipeline}
    
    # Web application template
    cat > project-templates/web-app/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloud9 Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Cloud9 Development</h1>
        <p>This is a template for web applications in Cloud9.</p>
    </div>
</body>
</html>
EOF
    
    # API service template
    cat > project-templates/api-service/app.py << 'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"message": "Hello from Cloud9 API!"})

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
EOF
    
    # Requirements file for Python projects
    cat > project-templates/api-service/requirements.txt << 'EOF'
Flask==2.3.3
requests==2.31.0
python-dotenv==1.0.0
EOF
    
    success "Project templates created"
}

# Function to create IAM policies
create_iam_policies() {
    log "Creating custom IAM policy for development..."
    
    local policy_name="Cloud9-Development-Policy-${RANDOM_SUFFIX}"
    
    # Check if policy already exists
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        warning "IAM policy $policy_name already exists"
        export DEV_POLICY_ARN="$policy_arn"
        return 0
    fi
    
    # Create custom IAM policy for Cloud9 development
    cat > cloud9-dev-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "lambda:GetFunction",
                "lambda:CreateFunction",
                "lambda:UpdateFunctionCode"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create the policy
    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document file://cloud9-dev-policy.json > /dev/null
    
    export DEV_POLICY_NAME="$policy_name"
    export DEV_POLICY_ARN="$policy_arn"
    
    # Save policy name for cleanup
    echo "$policy_name" > .iam_policy_name
    
    success "Custom IAM policy created: ${DEV_POLICY_NAME}"
}

# Function to create CloudWatch dashboard
create_monitoring_dashboard() {
    log "Creating CloudWatch monitoring dashboard..."
    
    local dashboard_name="Cloud9-${RANDOM_SUFFIX}-Dashboard"
    
    # Create CloudWatch dashboard configuration
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", "InstanceId", "AUTO"],
                    ["AWS/EC2", "NetworkIn", "InstanceId", "AUTO"],
                    ["AWS/EC2", "NetworkOut", "InstanceId", "AUTO"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "Cloud9 Environment Metrics",
                "period": 300
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body file://dashboard-config.json > /dev/null
    
    export DASHBOARD_NAME="$dashboard_name"
    
    # Save dashboard name for cleanup
    echo "$dashboard_name" > .cloudwatch_dashboard_name
    
    success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Cloud9 Environment ID: ${ENVIRONMENT_ID}"
    echo "Environment Name: ${CLOUD9_ENV_NAME}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo "CodeCommit Repository: ${REPO_NAME}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Access your Cloud9 environment through the AWS Console:"
    echo "   https://${AWS_REGION}.console.aws.amazon.com/cloud9/ide/${ENVIRONMENT_ID}"
    echo
    echo "2. Run the setup script in your Cloud9 terminal:"
    echo "   bash ~/cloud9-setup.sh"
    echo
    echo "3. Source the environment configuration:"
    echo "   source ~/environment-config.sh"
    echo
    echo "4. Clone your CodeCommit repository:"
    echo "   git clone ${REPO_URL}"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    log "Starting AWS Cloud9 Developer Environment deployment..."
    
    check_prerequisites
    generate_suffix
    setup_environment
    create_iam_role
    create_cloud9_environment
    wait_for_environment
    configure_environment
    create_setup_scripts
    create_codecommit_repo
    create_project_templates
    create_iam_policies
    create_monitoring_dashboard
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"