# Main Terraform configuration for AWS Cloud9 developer environments
# This configuration creates a complete Cloud9 development environment with supporting resources

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Data source to get the default VPC if vpc_id is not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Data source to get default subnet if subnet_id is not provided
data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Local values for resource naming and configuration
locals {
  suffix = random_id.suffix.hex
  
  # Resource names with consistent naming convention
  cloud9_environment_name = var.cloud9_environment_name != "" ? var.cloud9_environment_name : "${var.project_name}-${var.environment}-${local.suffix}"
  codecommit_repo_name   = var.codecommit_repository_name != "" ? var.codecommit_repository_name : "team-development-repo-${local.suffix}"
  dashboard_name         = var.dashboard_name != "" ? var.dashboard_name : "Cloud9-${local.suffix}-Dashboard"
  development_policy_name = var.development_policy_name != "" ? var.development_policy_name : "Cloud9-Development-Policy-${local.suffix}"
  
  # Get subnet ID - either provided or first default subnet
  subnet_id = var.subnet_id != "" ? var.subnet_id : (
    length(data.aws_subnets.default) > 0 && length(data.aws_subnets.default[0].ids) > 0 ? 
    data.aws_subnets.default[0].ids[0] : null
  )
  
  # Common tags merged with additional tags
  common_tags = merge({
    Name        = local.cloud9_environment_name
    Environment = var.environment
    Project     = var.project_name
  }, var.additional_tags)
}

# IAM role for Cloud9 environment EC2 instance
resource "aws_iam_role" "cloud9_role" {
  name = "Cloud9-${local.suffix}-Role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach AWS managed policy for Cloud9 environment member access
resource "aws_iam_role_policy_attachment" "cloud9_member_policy" {
  role       = aws_iam_role.cloud9_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloud9EnvironmentMember"
}

# Instance profile for the Cloud9 EC2 instance
resource "aws_iam_instance_profile" "cloud9_profile" {
  name = "Cloud9-${local.suffix}-Profile"
  role = aws_iam_role.cloud9_role.name
  
  tags = local.common_tags
}

# Custom IAM policy for development permissions (optional)
resource "aws_iam_policy" "development_policy" {
  count = var.create_development_policy ? 1 : 0
  
  name        = local.development_policy_name
  description = "Custom IAM policy providing development permissions for Cloud9 environment"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GitPush",
          "codecommit:GetRepository",
          "codecommit:ListRepositories",
          "codecommit:CreateCommit",
          "codecommit:GetCommit",
          "codecommit:GetCommitHistory",
          "codecommit:GetDifferences",
          "codecommit:GetReferences",
          "codecommit:ListBranches",
          "codecommit:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach custom development policy to Cloud9 role
resource "aws_iam_role_policy_attachment" "development_policy_attachment" {
  count = var.create_development_policy ? 1 : 0
  
  role       = aws_iam_role.cloud9_role.name
  policy_arn = aws_iam_policy.development_policy[0].arn
}

# AWS Cloud9 environment
resource "aws_cloud9_environment_ec2" "main" {
  name          = local.cloud9_environment_name
  description   = var.cloud9_description
  instance_type = var.cloud9_instance_type
  image_id      = var.cloud9_image_id
  subnet_id     = local.subnet_id
  
  # Automatic hibernation configuration
  automatic_stop_time_minutes = var.cloud9_auto_stop_minutes
  
  tags = local.common_tags
}

# Cloud9 environment memberships for team members
resource "aws_cloud9_environment_membership" "team_members" {
  count = length(var.team_member_arns)
  
  environment_id = aws_cloud9_environment_ec2.main.id
  permissions    = var.team_member_permissions
  user_arn       = var.team_member_arns[count.index]
}

# CodeCommit repository for team collaboration (optional)
resource "aws_codecommit_repository" "team_repo" {
  count = var.enable_codecommit ? 1 : 0
  
  repository_name        = local.codecommit_repo_name
  repository_description = var.codecommit_repository_description
  
  tags = merge(local.common_tags, {
    Name = local.codecommit_repo_name
  })
}

# CloudWatch dashboard for environment monitoring (optional)
resource "aws_cloudwatch_dashboard" "cloud9_monitoring" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = local.dashboard_name
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", "AUTO"],
            ["AWS/EC2", "NetworkIn", "InstanceId", "AUTO"],
            ["AWS/EC2", "NetworkOut", "InstanceId", "AUTO"]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = var.aws_region
          title     = "Cloud9 Environment Metrics"
          period    = 300
          stat      = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", "AUTO"],
            ["AWS/EC2", "StatusCheckFailed_Instance", "InstanceId", "AUTO"],
            ["AWS/EC2", "StatusCheckFailed_System", "InstanceId", "AUTO"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Instance Health Checks"
          period  = 300
          stat    = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "EBSReadOps", "InstanceId", "AUTO"],
            ["AWS/EC2", "EBSWriteOps", "InstanceId", "AUTO"],
            ["AWS/EC2", "EBSReadBytes", "InstanceId", "AUTO"],
            ["AWS/EC2", "EBSWriteBytes", "InstanceId", "AUTO"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "EBS Volume Performance"
          period  = 300
          stat    = "Sum"
        }
      }
    ]
  })
}

# Output the setup script for Cloud9 environment configuration
resource "local_file" "cloud9_setup_script" {
  filename = "${path.module}/cloud9-setup.sh"
  
  content = <<-EOF
    #!/bin/bash
    # Cloud9 Environment Setup Script
    # This script should be executed within the Cloud9 environment to install development tools
    
    set -e
    
    echo "Starting Cloud9 development environment setup..."
    
    # Update system packages
    sudo yum update -y
    
    # Install additional development tools
    sudo yum install -y git htop tree jq docker
    
    # Install Node.js and npm (latest LTS)
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    nvm install --lts
    nvm use --lts
    nvm alias default node
    
    # Install Python development tools
    pip3 install --user virtualenv pytest flake8 black isort
    
    # Install AWS CLI v2 (if not already installed)
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi
    
    # Install Terraform
    if ! command -v terraform &> /dev/null; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
        sudo yum -y install terraform
    fi
    
    # Configure Git (users should set their own credentials later)
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    
    # Create common project structure
    mkdir -p ~/projects/{frontend,backend,scripts,infrastructure}
    mkdir -p ~/projects/infrastructure/{terraform,cloudformation,cdk}
    
    # Create development aliases and environment configuration
    cat >> ~/.bashrc << 'BASHRC_EOF'

# Cloud9 Development Environment Configuration
export NODE_ENV=development
export PYTHONPATH="$HOME/projects:$PYTHONPATH"
export PATH="$HOME/.local/bin:$PATH"

# Development aliases
alias ll='ls -la'
alias la='ls -la'
alias proj='cd ~/projects'
alias gs='git status'
alias gp='git pull'
alias gc='git commit'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias gl='git log --oneline -10'

# AWS CLI shortcuts
alias awsprofile='aws configure list'
alias awsregion='aws configure get region'
alias awswhoami='aws sts get-caller-identity'

# Development shortcuts
alias serve='python3 -m http.server 8080'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# Terraform shortcuts
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# Docker shortcuts (if Docker is installed)
alias dps='docker ps'
alias dimg='docker images'
alias dstop='docker stop $(docker ps -aq)'
alias drm='docker rm $(docker ps -aq)'

BASHRC_EOF
    
    # Create project templates
    mkdir -p ~/projects/templates/{web-app,api-service,terraform-module}
    
    # Web application template
    cat > ~/projects/templates/web-app/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloud9 Web App</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 40px; 
            background-color: #f5f5f5;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .badge { 
            background-color: #232F3E; 
            color: white; 
            padding: 4px 8px; 
            border-radius: 4px; 
            font-size: 0.8em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Cloud9 Development <span class="badge">AWS</span></h1>
        <p>This is a template for web applications developed in Cloud9.</p>
        <p>Environment: <strong id="env">Development</strong></p>
        <p>Last updated: <span id="timestamp"></span></p>
    </div>
    <script>
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
HTML_EOF
    
    # API service template
    cat > ~/projects/templates/api-service/app.py << 'PYTHON_EOF'
from flask import Flask, jsonify, request
import os
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({
        "message": "Hello from Cloud9 API!",
        "timestamp": datetime.now().isoformat(),
        "environment": os.environ.get("NODE_ENV", "development")
    })

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0"
    })

@app.route('/api/data')
def get_data():
    return jsonify({
        "data": [
            {"id": 1, "name": "Sample Item 1"},
            {"id": 2, "name": "Sample Item 2"},
            {"id": 3, "name": "Sample Item 3"}
        ],
        "count": 3
    })

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 8080))
    debug = os.environ.get("NODE_ENV") == "development"
    app.run(host='0.0.0.0', port=port, debug=debug)
PYTHON_EOF
    
    # Requirements file for Python projects
    cat > ~/projects/templates/api-service/requirements.txt << 'REQ_EOF'
Flask==3.0.0
requests==2.31.0
python-dotenv==1.0.0
pytest==7.4.3
black==23.12.0
flake8==6.1.0
REQ_EOF
    
    # Terraform module template
    cat > ~/projects/templates/terraform-module/main.tf << 'TF_EOF'
# Example Terraform module for AWS resources
# Replace with your actual infrastructure requirements

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

resource "aws_s3_bucket" "example" {
  bucket = "$${var.project_name}-$${var.environment}-bucket"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.example.bucket
}
TF_EOF
    
    # Create a simple README for the projects directory
    cat > ~/projects/README.md << 'README_EOF'
# Cloud9 Development Projects

This directory contains your development projects and templates.

## Structure

- `frontend/` - Frontend applications and components
- `backend/` - Backend services and APIs  
- `scripts/` - Utility scripts and automation
- `infrastructure/` - Infrastructure as Code
  - `terraform/` - Terraform configurations
  - `cloudformation/` - CloudFormation templates
  - `cdk/` - AWS CDK applications
- `templates/` - Project templates for quick starts

## Getting Started

1. Navigate to the appropriate directory for your project type
2. Copy from templates/ if starting a new project
3. Configure your Git credentials: 
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

## Useful Commands

- `proj` - Quick navigation to projects directory
- `gs` - Git status
- `awswhoami` - Check current AWS identity
- `serve` - Start Python HTTP server on port 8080

## CodeCommit Integration

${var.enable_codecommit ? "Your team's CodeCommit repository: ${local.codecommit_repo_name}" : "CodeCommit repository not configured"}

To clone your team repository:
```bash
git clone https://git-codecommit.${var.aws_region}.amazonaws.com/v1/repos/${local.codecommit_repo_name}
```
README_EOF
    
    echo "✅ Cloud9 development environment setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Restart your terminal or run: source ~/.bashrc"
    echo "2. Configure your Git credentials"
    echo "3. Start developing in ~/projects/"
    echo ""
    echo "Available commands:"
    echo "- proj          Navigate to projects directory"
    echo "- gs            Git status"
    echo "- awswhoami     Check AWS identity"
    echo "- serve         Start HTTP server"
    echo ""
  EOF
  
  file_permission = "0755"
}

# Output the environment configuration script
resource "local_file" "environment_config_script" {
  filename = "${path.module}/environment-config.sh"
  
  content = <<-EOF
    #!/bin/bash
    # Cloud9 Environment Configuration Script
    # This script sets up environment variables and aliases for development
    
    # Export important environment information
    export CLOUD9_ENVIRONMENT_ID="${aws_cloud9_environment_ec2.main.id}"
    export CLOUD9_ENVIRONMENT_NAME="${aws_cloud9_environment_ec2.main.name}"
    ${var.enable_codecommit ? "export CODECOMMIT_REPO_NAME=\"${aws_codecommit_repository.team_repo[0].repository_name}\"" : ""}
    ${var.enable_codecommit ? "export CODECOMMIT_CLONE_URL=\"${aws_codecommit_repository.team_repo[0].clone_url_http}\"" : ""}
    export AWS_DEFAULT_REGION="${var.aws_region}"
    
    echo "Cloud9 Environment Configuration:"
    echo "- Environment ID: ${aws_cloud9_environment_ec2.main.id}"
    echo "- Environment Name: ${aws_cloud9_environment_ec2.main.name}"
    echo "- Instance Type: ${var.cloud9_instance_type}"
    echo "- Auto Stop: ${var.cloud9_auto_stop_minutes} minutes"
    ${var.enable_codecommit ? "echo \"- CodeCommit Repository: ${aws_codecommit_repository.team_repo[0].repository_name}\"" : ""}
    ${var.enable_cloudwatch_dashboard ? "echo \"- CloudWatch Dashboard: ${aws_cloudwatch_dashboard.cloud9_monitoring[0].dashboard_name}\"" : ""}
    echo ""
    echo "To access your Cloud9 environment:"
    echo "1. Go to the AWS Console"
    echo "2. Navigate to Cloud9 service"
    echo "3. Open the '${aws_cloud9_environment_ec2.main.name}' environment"
    echo ""
  EOF
  
  file_permission = "0755"
}