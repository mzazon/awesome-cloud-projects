#!/bin/bash

#######################################################################
# Deploy Script for Cloud-Based Development Workflows
# Recipe: Cloud Development Workflows with CloudShell
# 
# This script automates the deployment of:
# - AWS CodeCommit repository
# - Git configuration for CloudShell
# - Sample application with tests
# - Development workflow setup
#######################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/deploy-cloudshell-codecommit-$(date +%Y%m%d-%H%M%S).log"
REPO_PREFIX="dev-workflow-demo"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check if running in CloudShell
check_cloudshell_environment() {
    info "Checking CloudShell environment..."
    
    if [[ -z "${AWS_CLOUDSHELL_USER_ID:-}" ]]; then
        warning "This script is optimized for AWS CloudShell but can run in other environments"
        info "Ensure you have AWS CLI configured with appropriate permissions"
    else
        success "Running in AWS CloudShell environment"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        error_exit "Git is not installed. Please install Git first."
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error_exit "Python 3 is not installed. Please install Python 3 first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please configure AWS CLI first."
    fi
    
    success "All prerequisites validated"
}

# Setup environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c6)")
    
    # Set repository name
    export REPO_NAME="${REPO_PREFIX}-${RANDOM_SUFFIX}"
    
    success "Environment configured for region: ${AWS_REGION}"
    success "Repository name: ${REPO_NAME}"
    
    # Log environment details
    log "AWS_REGION: ${AWS_REGION}"
    log "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "REPO_NAME: ${REPO_NAME}"
}

# Create CodeCommit repository
create_codecommit_repository() {
    info "Creating CodeCommit repository..."
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        warning "Repository ${REPO_NAME} already exists, skipping creation"
        export REPO_URL=$(aws codecommit get-repository \
            --repository-name "${REPO_NAME}" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
    else
        # Create repository
        aws codecommit create-repository \
            --repository-name "${REPO_NAME}" \
            --repository-description "Demo repository for cloud-based development workflow" \
            || error_exit "Failed to create CodeCommit repository"
        
        # Get repository clone URL
        export REPO_URL=$(aws codecommit get-repository \
            --repository-name "${REPO_NAME}" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
        
        success "CodeCommit repository created: ${REPO_NAME}"
    fi
    
    info "Repository URL: ${REPO_URL}"
    log "REPO_URL: ${REPO_URL}"
}

# Configure Git for CodeCommit
configure_git() {
    info "Configuring Git for CodeCommit..."
    
    # Configure Git with IAM user information
    git config --global user.name "CloudShell Developer" || warning "Failed to set Git user name"
    git config --global user.email "developer@example.com" || warning "Failed to set Git email"
    
    # Configure Git to use AWS credential helper for CodeCommit
    git config --global credential.helper '!aws codecommit credential-helper $@' || \
        warning "Failed to set credential helper"
    git config --global credential.UseHttpPath true || \
        warning "Failed to set credential UseHttpPath"
    
    success "Git configured with AWS CodeCommit credential helper"
}

# Create project structure
create_project_structure() {
    info "Creating project structure..."
    
    # Create project directory
    PROJECT_DIR="${HOME}/projects/${REPO_NAME}"
    mkdir -p "${PROJECT_DIR}"
    cd "${PROJECT_DIR}"
    
    # Initialize Git repository
    git init || error_exit "Failed to initialize Git repository"
    
    # Create project directories
    mkdir -p src docs tests
    
    success "Project structure created at ${PROJECT_DIR}"
    log "PROJECT_DIR: ${PROJECT_DIR}"
}

# Create application files
create_application_files() {
    info "Creating sample application files..."
    
    # Create README file
    cat > README.md << 'EOF'
# Cloud-Based Development Workflow Demo

This project demonstrates cloud-based development workflows using AWS CloudShell and CodeCommit.

## Features
- Browser-based development environment
- Integrated Git version control
- Pre-configured development tools
- Secure IAM-based authentication

## Getting Started
1. Access AWS CloudShell from the console
2. Clone this repository
3. Start developing!

## Project Structure
- `src/` - Application source code
- `tests/` - Test files
- `docs/` - Documentation

## Development Workflow
1. Create feature branches for new development
2. Write tests for new functionality
3. Commit and push changes
4. Merge through pull requests

## Configuration
The application supports environment variables for configuration:
- `APP_NAME` - Application name
- `DEFAULT_NAME` - Default greeting name
- `DEBUG` - Enable debug mode
- `TIME_FORMAT` - Time format string
EOF

    # Create Python application
    cat > src/hello_world.py << 'EOF'
#!/usr/bin/env python3
"""
Configurable Hello World application for demonstrating cloud-based development workflows.
"""

import sys
import os
from datetime import datetime

# Configuration with environment variable support
APP_NAME = os.getenv("APP_NAME", "Hello World App")
APP_VERSION = "1.0.0"
DEBUG_MODE = os.getenv("DEBUG", "false").lower() == "true"
DEFAULT_NAME = os.getenv("DEFAULT_NAME", "World")
TIME_FORMAT = os.getenv("TIME_FORMAT", "%Y-%m-%d %H:%M:%S")

def get_config():
    """Return application configuration dictionary."""
    return {
        "app_name": APP_NAME,
        "app_version": APP_VERSION,
        "debug_mode": DEBUG_MODE,
        "default_name": DEFAULT_NAME,
        "time_format": TIME_FORMAT,
    }

def hello_world(name=None):
    """Return a greeting message with timestamp."""
    config = get_config()
    if name is None:
        name = config["default_name"]
    
    timestamp = datetime.now().strftime(config["time_format"])
    return f"Hello, {name}! Current time: {timestamp}"

def main():
    """Main function to run the application."""
    config = get_config()
    
    if config["debug_mode"]:
        print(f"Debug: Running {config['app_name']} v{config['app_version']}")
    
    if len(sys.argv) > 1:
        name = sys.argv[1]
    else:
        name = None
    
    message = hello_world(name)
    print(message)
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

    # Make the script executable
    chmod +x src/hello_world.py

    # Create test file
    cat > tests/test_hello_world.py << 'EOF'
#!/usr/bin/env python3
"""
Tests for the hello_world module.
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from hello_world import hello_world, get_config

def test_hello_world_default():
    """Test hello_world with default parameter."""
    result = hello_world()
    assert "Hello, World!" in result
    assert "Current time:" in result
    print("✅ Default greeting test passed")

def test_hello_world_custom_name():
    """Test hello_world with custom name."""
    result = hello_world("Developer")
    assert "Hello, Developer!" in result
    assert "Current time:" in result
    print("✅ Custom name test passed")

def test_configuration():
    """Test configuration loading."""
    config = get_config()
    assert "app_name" in config
    assert "app_version" in config
    assert "debug_mode" in config
    assert "default_name" in config
    assert "time_format" in config
    print("✅ Configuration test passed")

if __name__ == "__main__":
    test_hello_world_default()
    test_hello_world_custom_name()
    test_configuration()
    print("✅ All tests passed!")
EOF

    # Create documentation
    cat > docs/development-guide.md << 'EOF'
# Development Guide

## Environment Setup
This project is designed to work with AWS CloudShell, providing a consistent development environment across team members.

## Testing
Run tests using:
```bash
python3 tests/test_hello_world.py
```

## Configuration
The application supports several environment variables for customization:
- `DEBUG=true` - Enable debug output
- `DEFAULT_NAME="Your Name"` - Change default greeting name
- `TIME_FORMAT="%H:%M:%S"` - Customize time format

## Git Workflow
1. Create feature branches: `git checkout -b feature/feature-name`
2. Make changes and commit: `git commit -m "Description"`
3. Push to remote: `git push -u origin feature/feature-name`
4. Merge when ready: `git checkout main && git merge feature/feature-name`
EOF

    success "Sample application files created"
}

# Test the application
test_application() {
    info "Testing the application..."
    
    # Test basic functionality
    python3 src/hello_world.py "CloudShell Developer" || error_exit "Application test failed"
    
    # Run unit tests
    python3 tests/test_hello_world.py || error_exit "Unit tests failed"
    
    success "Application tests passed"
}

# Commit and push initial code
commit_and_push() {
    info "Committing and pushing initial code..."
    
    # Add files to Git
    git add . || error_exit "Failed to add files to Git"
    
    # Create initial commit
    git commit -m "Initial commit: Add hello world application with tests

- Add Python hello world application with configuration support
- Include comprehensive test suite
- Add project documentation and development guide
- Configure for cloud-based development workflow
- Support environment variables for customization" || error_exit "Failed to create initial commit"
    
    # Add remote origin
    git remote add origin "${REPO_URL}" || error_exit "Failed to add remote origin"
    
    # Push to CodeCommit
    git push -u origin main || error_exit "Failed to push to CodeCommit"
    
    success "Initial code committed and pushed to CodeCommit"
}

# Create feature branch demonstration
create_feature_branch_demo() {
    info "Creating feature branch demonstration..."
    
    # Create and switch to feature branch
    git checkout -b feature/add-logging || error_exit "Failed to create feature branch"
    
    # Add logging functionality
    cat > src/logger.py << 'EOF'
"""
Simple logging utility for the hello world application.
"""

import os
import sys
from datetime import datetime

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
LOG_FILE = os.getenv("LOG_FILE", None)

def log(level, message):
    """Log a message with timestamp and level."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {level}: {message}"
    
    # Always print to console
    print(log_entry)
    
    # Also write to file if specified
    if LOG_FILE:
        try:
            with open(LOG_FILE, 'a') as f:
                f.write(log_entry + '\n')
        except Exception as e:
            print(f"Failed to write to log file: {e}", file=sys.stderr)

def info(message):
    """Log an info message."""
    if LOG_LEVEL in ["DEBUG", "INFO", "WARN", "ERROR"]:
        log("INFO", message)

def debug(message):
    """Log a debug message."""
    if LOG_LEVEL in ["DEBUG"]:
        log("DEBUG", message)

def warning(message):
    """Log a warning message."""
    if LOG_LEVEL in ["DEBUG", "INFO", "WARN", "ERROR"]:
        log("WARN", message)

def error(message):
    """Log an error message."""
    if LOG_LEVEL in ["DEBUG", "INFO", "WARN", "ERROR"]:
        log("ERROR", message)
EOF

    # Update hello_world.py to use logging
    cat > src/hello_world.py << 'EOF'
#!/usr/bin/env python3
"""
Configurable Hello World application for demonstrating cloud-based development workflows.
"""

import sys
import os
from datetime import datetime
from logger import info, debug, error

# Configuration with environment variable support
APP_NAME = os.getenv("APP_NAME", "Hello World App")
APP_VERSION = "1.1.0"
DEBUG_MODE = os.getenv("DEBUG", "false").lower() == "true"
DEFAULT_NAME = os.getenv("DEFAULT_NAME", "World")
TIME_FORMAT = os.getenv("TIME_FORMAT", "%Y-%m-%d %H:%M:%S")

def get_config():
    """Return application configuration dictionary."""
    return {
        "app_name": APP_NAME,
        "app_version": APP_VERSION,
        "debug_mode": DEBUG_MODE,
        "default_name": DEFAULT_NAME,
        "time_format": TIME_FORMAT,
    }

def hello_world(name=None):
    """Return a greeting message with timestamp."""
    config = get_config()
    if name is None:
        name = config["default_name"]
    
    debug(f"Generating greeting for: {name}")
    
    timestamp = datetime.now().strftime(config["time_format"])
    message = f"Hello, {name}! Current time: {timestamp}"
    
    info(f"Generated greeting message")
    return message

def main():
    """Main function to run the application."""
    config = get_config()
    
    info(f"Starting {config['app_name']} v{config['app_version']}")
    
    if config["debug_mode"]:
        debug(f"Debug mode enabled")
        debug(f"Configuration: {config}")
    
    if len(sys.argv) > 1:
        name = sys.argv[1]
        debug(f"Using command line argument: {name}")
    else:
        name = None
        debug(f"Using default name from configuration")
    
    try:
        message = hello_world(name)
        print(message)
        info("Application completed successfully")
        return 0
    except Exception as e:
        error(f"Application failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
EOF

    # Commit feature changes
    git add . || error_exit "Failed to add feature files"
    git commit -m "Add logging functionality

- Add logger.py module for structured logging
- Update hello_world.py to use logging
- Support LOG_LEVEL and LOG_FILE environment variables
- Add debug, info, warning, and error logging levels
- Improve application observability and debugging" || error_exit "Failed to commit feature"
    
    # Push feature branch
    git push -u origin feature/add-logging || error_exit "Failed to push feature branch"
    
    success "Feature branch created and pushed"
}

# Merge feature branch
merge_feature_branch() {
    info "Merging feature branch..."
    
    # Switch back to main branch
    git checkout main || error_exit "Failed to checkout main branch"
    
    # Merge feature branch
    git merge feature/add-logging || error_exit "Failed to merge feature branch"
    
    # Push updated main branch
    git push origin main || error_exit "Failed to push merged changes"
    
    # Delete local feature branch
    git branch -d feature/add-logging || warning "Failed to delete local feature branch"
    
    # Delete remote feature branch
    git push origin --delete feature/add-logging || warning "Failed to delete remote feature branch"
    
    success "Feature branch merged and cleaned up"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check repository exists
    aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null || \
        error_exit "Repository validation failed"
    
    # Test Git connectivity
    git ls-remote origin &> /dev/null || error_exit "Git connectivity test failed"
    
    # Test application with logging
    export LOG_LEVEL=DEBUG
    python3 src/hello_world.py "Deployment Test" || error_exit "Application validation failed"
    
    # Verify Git history
    COMMIT_COUNT=$(git rev-list --count HEAD)
    if [[ $COMMIT_COUNT -lt 2 ]]; then
        error_exit "Expected at least 2 commits, found ${COMMIT_COUNT}"
    fi
    
    success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    echo -e "${BLUE}"
    echo "=============================================="
    echo "Cloud-Based Development Workflows Deployment"
    echo "=============================================="
    echo -e "${NC}"
    
    log "Starting deployment script"
    
    # Run deployment steps
    check_cloudshell_environment
    validate_prerequisites
    setup_environment
    create_codecommit_repository
    configure_git
    create_project_structure
    create_application_files
    test_application
    commit_and_push
    create_feature_branch_demo
    merge_feature_branch
    validate_deployment
    
    echo -e "${GREEN}"
    echo "=============================================="
    echo "         DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=============================================="
    echo -e "${NC}"
    
    info "Repository Name: ${REPO_NAME}"
    info "Repository URL: ${REPO_URL}"
    info "Project Directory: ${HOME}/projects/${REPO_NAME}"
    info "Log File: ${LOG_FILE}"
    
    echo ""
    echo "Next Steps:"
    echo "1. Navigate to your project: cd ~/projects/${REPO_NAME}"
    echo "2. Try the application: python3 src/hello_world.py 'Your Name'"
    echo "3. Enable debug logging: export LOG_LEVEL=DEBUG"
    echo "4. Create new features with: git checkout -b feature/your-feature"
    echo "5. Access your repository in the AWS Console > CodeCommit"
    
    log "Deployment completed successfully"
}

# Execute main function
main "$@"