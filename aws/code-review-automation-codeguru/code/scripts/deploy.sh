#!/bin/bash

# AWS CodeGuru Code Review Automation - Deployment Script
# This script deploys the complete CodeGuru automation solution including:
# - CodeCommit repository
# - CodeGuru Reviewer association
# - CodeGuru Profiler group
# - IAM roles and policies
# - Sample code and automation scripts

set -e

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install Git."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON parsing."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || error "Unable to verify AWS identity"
    
    success "Prerequisites check completed"
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
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    export REPO_NAME="codeguru-demo-${RANDOM_SUFFIX}"
    export PROFILER_GROUP_NAME="demo-profiler-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="CodeGuruDemoRole-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
REPO_NAME=${REPO_NAME}
PROFILER_GROUP_NAME=${PROFILER_GROUP_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for CodeGuru services..."
    
    # Create trust policy
    cat > trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codeguru-reviewer.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    if aws iam get-role --role-name ${IAM_ROLE_NAME} &> /dev/null; then
        warning "IAM role ${IAM_ROLE_NAME} already exists, skipping creation"
    else
        aws iam create-role \
            --role-name ${IAM_ROLE_NAME} \
            --assume-role-policy-document file://trust-policy.json \
            --description "IAM role for CodeGuru demo services"
        
        # Wait for role to be available
        aws iam wait role-exists --role-name ${IAM_ROLE_NAME}
        
        # Attach managed policy for CodeGuru Reviewer
        aws iam attach-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonCodeGuruReviewerServiceRolePolicy
        
        success "IAM role created: ${IAM_ROLE_NAME}"
    fi
    
    # Clean up temporary file
    rm -f trust-policy.json
}

# Function to create CodeCommit repository
create_codecommit_repo() {
    log "Creating CodeCommit repository..."
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name ${REPO_NAME} &> /dev/null; then
        warning "Repository ${REPO_NAME} already exists, skipping creation"
    else
        aws codecommit create-repository \
            --repository-name ${REPO_NAME} \
            --repository-description "Demo repository for CodeGuru automation"
        
        success "Repository created: ${REPO_NAME}"
    fi
    
    # Get repository clone URL
    export CLONE_URL=$(aws codecommit get-repository \
        --repository-name ${REPO_NAME} \
        --query 'repositoryMetadata.cloneUrlHttp' --output text)
    
    echo "CLONE_URL=${CLONE_URL}" >> .env
    
    success "Repository URL: ${CLONE_URL}"
}

# Function to associate repository with CodeGuru Reviewer
associate_codeguru_reviewer() {
    log "Associating repository with CodeGuru Reviewer..."
    
    # Check if association already exists
    EXISTING_ASSOCIATIONS=$(aws codeguru-reviewer list-repository-associations \
        --query "RepositoryAssociationSummaries[?Repository.Name=='${REPO_NAME}'].AssociationArn" \
        --output text)
    
    if [ -n "$EXISTING_ASSOCIATIONS" ]; then
        export ASSOCIATION_ARN="$EXISTING_ASSOCIATIONS"
        warning "Repository association already exists: ${ASSOCIATION_ARN}"
    else
        # Associate the repository with CodeGuru Reviewer
        export ASSOCIATION_ARN=$(aws codeguru-reviewer associate-repository \
            --repository CodeCommit={Name=${REPO_NAME}} \
            --query 'RepositoryAssociation.AssociationArn' --output text)
        
        success "Repository associated with CodeGuru Reviewer: ${ASSOCIATION_ARN}"
    fi
    
    echo "ASSOCIATION_ARN=${ASSOCIATION_ARN}" >> .env
    
    # Wait for association to complete
    log "Waiting for association to complete..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws codeguru-reviewer describe-repository-association \
            --association-arn ${ASSOCIATION_ARN} \
            --query 'RepositoryAssociation.State' --output text)
        
        if [ "$status" = "Associated" ]; then
            success "Repository association completed"
            break
        elif [ "$status" = "Failed" ]; then
            error "Repository association failed"
        else
            log "Association status: $status (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Repository association timed out"
    fi
}

# Function to create CodeGuru Profiler group
create_profiler_group() {
    log "Creating CodeGuru Profiler group..."
    
    # Check if profiler group already exists
    if aws codeguru-profiler describe-profiling-group \
        --profiling-group-name ${PROFILER_GROUP_NAME} &> /dev/null; then
        warning "Profiler group ${PROFILER_GROUP_NAME} already exists, skipping creation"
    else
        aws codeguru-profiler create-profiling-group \
            --profiling-group-name ${PROFILER_GROUP_NAME} \
            --compute-platform Default \
            --agent-permissions '{
                "actionGroupPermissions": [
                    "agentPermissions:CreateProfilingGroup",
                    "agentPermissions:DescribeProfilingGroup"
                ]
            }'
        
        success "Profiler group created: ${PROFILER_GROUP_NAME}"
    fi
}

# Function to clone repository and add sample code
setup_sample_code() {
    log "Setting up sample code repository..."
    
    # Create temporary directory for repository
    local temp_dir="/tmp/codeguru-demo-${RANDOM_SUFFIX}"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Clone the repository
    git clone ${CLONE_URL}
    cd ${REPO_NAME}
    
    # Configure git if needed
    if ! git config user.email &> /dev/null; then
        git config user.email "demo@example.com"
        git config user.name "CodeGuru Demo"
    fi
    
    # Create directory structure
    mkdir -p src/main/java/com/example
    
    # Create sample Java application with potential issues
    cat > src/main/java/com/example/DatabaseManager.java << 'EOF'
package com.example;

import java.sql.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.List;
import java.util.ArrayList;

public class DatabaseManager {
    private static ConcurrentHashMap<String, Connection> connections = new ConcurrentHashMap<>();
    private static final String DB_URL = "jdbc:mysql://localhost:3306/mydb";
    private static final String USER = "admin";
    private static final String PASS = "password123"; // Hardcoded credential
    
    public Connection getConnection(String key) {
        if (connections.containsKey(key)) {
            return connections.get(key); // Potential race condition
        }
        return null;
    }
    
    public void addConnection(String key, Connection conn) {
        connections.put(key, conn);
    }
    
    public void removeConnection(String key) {
        Connection conn = connections.remove(key);
        if (conn != null) {
            // Connection not closed - resource leak
        }
    }
    
    public List<String> executeQuery(String sql) throws SQLException {
        Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(sql); // SQL injection potential
        
        List<String> results = new ArrayList<>();
        while (rs.next()) {
            results.add(rs.getString(1));
        }
        
        return results; // Resources not closed
    }
    
    public void slowOperation() {
        // Inefficient loop that could be optimized
        for (int i = 0; i < 1000000; i++) {
            String temp = "Processing item " + i;
            System.out.println(temp);
        }
    }
}
EOF
    
    # Create Python sample with issues
    cat > app.py << 'EOF'
import sqlite3
import os
import time

# Hardcoded database credentials
DB_PASSWORD = "secretpassword123"

def get_user_data(user_id):
    # SQL injection vulnerability
    query = f"SELECT * FROM users WHERE id = {user_id}"
    conn = sqlite3.connect("users.db")
    cursor = conn.cursor()
    cursor.execute(query)
    result = cursor.fetchall()
    # Connection not closed - resource leak
    return result

def process_large_dataset():
    # Inefficient processing
    data = []
    for i in range(100000):
        data.append(f"Item {i}")
        if i % 1000 == 0:
            time.sleep(0.01)  # Unnecessary delay
    return data

def file_handler(filename):
    # File handle not properly closed
    file = open(filename, 'r')
    content = file.read()
    return content

if __name__ == "__main__":
    user_data = get_user_data(123)
    large_data = process_large_dataset()
    content = file_handler("sample.txt")
EOF
    
    # Create CodeGuru configuration file
    cat > aws-codeguru-reviewer.yml << 'EOF'
version: 1.0

# Files and directories to exclude from analysis
exclude:
  - "*.log"
  - "*.tmp"
  - "target/**"
  - "__pycache__/**"
  - ".git/**"

# File patterns to include
include:
  - "**/*.java"
  - "**/*.py"
  - "**/*.js"
EOF
    
    # Create automation scripts
    mkdir -p scripts
    
    # Create code quality check script
    cat > scripts/check_code_quality.sh << 'EOF'
#!/bin/bash

CODE_REVIEW_ARN=$1

if [ -z "$CODE_REVIEW_ARN" ]; then
    echo "Usage: $0 <code-review-arn>"
    exit 1
fi

echo "Checking code review results..."

# Get recommendations
RECOMMENDATIONS=$(aws codeguru-reviewer list-recommendations \
    --code-review-arn $CODE_REVIEW_ARN \
    --query 'RecommendationSummaries[].{Description:Description,Severity:Severity,File:FilePath}' \
    --output json)

# Count recommendations by severity
HIGH_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "HIGH")] | length')
MEDIUM_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "MEDIUM")] | length')
LOW_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "LOW")] | length')

echo "Code Review Results:"
echo "High Severity Issues: $HIGH_SEVERITY"
echo "Medium Severity Issues: $MEDIUM_SEVERITY"
echo "Low Severity Issues: $LOW_SEVERITY"

# Quality gate: Fail if high severity issues found
if [ "$HIGH_SEVERITY" -gt 0 ]; then
    echo "❌ Quality gate failed: High severity issues found"
    exit 1
else
    echo "✅ Quality gate passed: No high severity issues"
    exit 0
fi
EOF
    
    chmod +x scripts/check_code_quality.sh
    
    # Create feedback script
    cat > scripts/feedback_recommendations.sh << 'EOF'
#!/bin/bash

CODE_REVIEW_ARN=$1

if [ -z "$CODE_REVIEW_ARN" ]; then
    echo "Usage: $0 <code-review-arn>"
    exit 1
fi

echo "Processing recommendations and providing feedback..."

# Get all recommendations
RECOMMENDATIONS=$(aws codeguru-reviewer list-recommendations \
    --code-review-arn $CODE_REVIEW_ARN \
    --query 'RecommendationSummaries[].RecommendationId' \
    --output text)

# Provide thumbs up feedback for each recommendation
for rec_id in $RECOMMENDATIONS; do
    aws codeguru-reviewer put-recommendation-feedback \
        --code-review-arn $CODE_REVIEW_ARN \
        --recommendation-id $rec_id \
        --reactions ThumbsUp
    
    echo "Provided feedback for recommendation: $rec_id"
done

echo "✅ Feedback provided for all recommendations"
EOF
    
    chmod +x scripts/feedback_recommendations.sh
    
    # Create performance monitoring script
    cat > scripts/monitor_performance.sh << 'EOF'
#!/bin/bash

PROFILING_GROUP=$1

if [ -z "$PROFILING_GROUP" ]; then
    echo "Usage: $0 <profiling-group-name>"
    exit 1
fi

echo "Monitoring performance for profiling group: $PROFILING_GROUP"

# List profiling groups
aws codeguru-profiler list-profiling-groups \
    --include-description

# Get profile times (if any profiles exist)
PROFILE_TIMES=$(aws codeguru-profiler list-profile-times \
    --profiling-group-name $PROFILING_GROUP \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --query 'profileTimes[].start' \
    --output text 2>/dev/null)

if [ -n "$PROFILE_TIMES" ]; then
    echo "Recent profile times found:"
    echo "$PROFILE_TIMES"
else
    echo "No recent profiles found. Start your application with profiling enabled."
fi

echo "✅ Performance monitoring check completed"
EOF
    
    chmod +x scripts/monitor_performance.sh
    
    # Create CI/CD integration script
    cat > scripts/integrate_codeguru_ci.sh << 'EOF'
#!/bin/bash

# This script demonstrates how to integrate CodeGuru into CI/CD pipelines

REPO_ASSOCIATION_ARN=$1
BRANCH_NAME=${2:-main}

if [ -z "$REPO_ASSOCIATION_ARN" ]; then
    echo "Usage: $0 <repository-association-arn> [branch-name]"
    exit 1
fi

echo "Integrating CodeGuru into CI/CD pipeline..."

# Create code review for the current branch
CODE_REVIEW_ARN=$(aws codeguru-reviewer create-code-review \
    --name "ci-analysis-$(date +%Y%m%d-%H%M%S)" \
    --repository-association-arn $REPO_ASSOCIATION_ARN \
    --type "{\"RepositoryAnalysis\": {\"RepositoryHead\": {\"BranchName\": \"$BRANCH_NAME\"}}}" \
    --query 'CodeReview.CodeReviewArn' --output text)

echo "Code review started: $CODE_REVIEW_ARN"

# Wait for completion
echo "Waiting for code review to complete..."
while true; do
    STATUS=$(aws codeguru-reviewer describe-code-review \
        --code-review-arn $CODE_REVIEW_ARN \
        --query 'CodeReview.State' --output text)
    
    if [[ "$STATUS" == "Completed" ]]; then
        echo "✅ Code review completed successfully"
        break
    elif [[ "$STATUS" == "Failed" ]]; then
        echo "❌ Code review failed"
        exit 1
    else
        echo "Status: $STATUS"
        sleep 30
    fi
done

# Run quality gate check
./check_code_quality.sh $CODE_REVIEW_ARN

echo "✅ CI/CD integration completed"
EOF
    
    chmod +x scripts/integrate_codeguru_ci.sh
    
    # Commit the initial code
    git add .
    git commit -m "Initial commit with sample code for CodeGuru analysis"
    
    # Check if main branch exists, if not create it
    if ! git show-ref --verify --quiet refs/heads/main; then
        git branch -M main
    fi
    
    git push origin main
    
    success "Sample code committed to repository"
    
    # Return to original directory
    cd - > /dev/null
}

# Function to trigger initial code review
trigger_code_review() {
    log "Triggering full repository analysis..."
    
    # Create a full repository analysis
    export CODE_REVIEW_ARN=$(aws codeguru-reviewer create-code-review \
        --name "initial-analysis-${RANDOM_SUFFIX}" \
        --repository-association-arn ${ASSOCIATION_ARN} \
        --type '{"RepositoryAnalysis": {"RepositoryHead": {"BranchName": "main"}}}' \
        --query 'CodeReview.CodeReviewArn' --output text)
    
    echo "CODE_REVIEW_ARN=${CODE_REVIEW_ARN}" >> .env
    
    success "Code review triggered: ${CODE_REVIEW_ARN}"
    
    # Wait for analysis to complete
    log "Waiting for code review analysis to complete (this may take several minutes)..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws codeguru-reviewer describe-code-review \
            --code-review-arn ${CODE_REVIEW_ARN} \
            --query 'CodeReview.State' --output text)
        
        if [ "$status" = "Completed" ]; then
            success "Code review analysis completed"
            break
        elif [ "$status" = "Failed" ]; then
            error "Code review analysis failed"
        else
            log "Current status: $status (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warning "Code review analysis is taking longer than expected. Check AWS console for status."
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "AWS Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo "Repository Name: ${REPO_NAME}"
    echo "Repository URL: ${CLONE_URL}"
    echo "Profiler Group: ${PROFILER_GROUP_NAME}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo "Association ARN: ${ASSOCIATION_ARN}"
    if [ -n "$CODE_REVIEW_ARN" ]; then
        echo "Code Review ARN: ${CODE_REVIEW_ARN}"
    fi
    echo ""
    echo "Next Steps:"
    echo "1. View CodeGuru Reviewer results in AWS Console:"
    echo "   https://console.aws.amazon.com/codeguru/reviewer/home?region=${AWS_REGION}"
    echo ""
    echo "2. Monitor CodeGuru Profiler:"
    echo "   https://console.aws.amazon.com/codeguru/profiler/home?region=${AWS_REGION}"
    echo ""
    echo "3. Clone the repository locally:"
    echo "   git clone ${CLONE_URL}"
    echo ""
    echo "4. Run automation scripts from the repository:"
    echo "   ./scripts/check_code_quality.sh ${CODE_REVIEW_ARN}"
    echo "   ./scripts/monitor_performance.sh ${PROFILER_GROUP_NAME}"
    echo ""
    success "CodeGuru automation deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting AWS CodeGuru Code Review Automation deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_codecommit_repo
    associate_codeguru_reviewer
    create_profiler_group
    setup_sample_code
    trigger_code_review
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"