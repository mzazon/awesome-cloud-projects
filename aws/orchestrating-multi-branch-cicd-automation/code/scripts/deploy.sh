#!/bin/bash

# Deploy script for Multi-Branch CI/CD Pipelines with CodePipeline
# This script implements the complete infrastructure from the recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Function to execute command with dry-run support
execute_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install Git."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Please install zip."
        exit 1
    fi
    
    # Check permissions
    log "Checking AWS permissions..."
    aws iam get-user &> /dev/null || {
        error "Unable to access AWS IAM. Please ensure you have proper permissions."
        exit 1
    }
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export REPO_NAME="multi-branch-app-${RANDOM_SUFFIX}"
    export PIPELINE_MANAGER_FUNCTION="pipeline-manager-${RANDOM_SUFFIX}"
    export PIPELINE_ROLE_NAME="CodePipelineMultiBranchRole-${RANDOM_SUFFIX}"
    export CODEBUILD_ROLE_NAME="CodeBuildMultiBranchRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="LambdaPipelineManagerRole-${RANDOM_SUFFIX}"
    export ARTIFACT_BUCKET="multi-branch-artifacts-${RANDOM_SUFFIX}"
    export CODEBUILD_PROJECT_NAME="multi-branch-build-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="CodeCommitBranchEvents-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="MultibranchPipelines-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="PipelineAlerts-${RANDOM_SUFFIX}"
    
    # Save configuration to file for cleanup script
    cat > .deployment-config << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
REPO_NAME=${REPO_NAME}
PIPELINE_MANAGER_FUNCTION=${PIPELINE_MANAGER_FUNCTION}
PIPELINE_ROLE_NAME=${PIPELINE_ROLE_NAME}
CODEBUILD_ROLE_NAME=${CODEBUILD_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
ARTIFACT_BUCKET=${ARTIFACT_BUCKET}
CODEBUILD_PROJECT_NAME=${CODEBUILD_PROJECT_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
EOF
    
    success "Environment variables configured"
}

# Create S3 bucket for artifacts
create_artifact_bucket() {
    log "Creating S3 bucket for pipeline artifacts..."
    
    if execute_cmd aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" 2>/dev/null; then
        warning "Bucket ${ARTIFACT_BUCKET} already exists"
    else
        execute_cmd aws s3 mb "s3://${ARTIFACT_BUCKET}" --region "${AWS_REGION}"
        
        # Enable versioning
        execute_cmd aws s3api put-bucket-versioning \
            --bucket "${ARTIFACT_BUCKET}" \
            --versioning-configuration Status=Enabled
        
        # Enable server-side encryption
        execute_cmd aws s3api put-bucket-encryption \
            --bucket "${ARTIFACT_BUCKET}" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        success "Artifact bucket created: ${ARTIFACT_BUCKET}"
    fi
}

# Create CodeCommit repository
create_codecommit_repo() {
    log "Creating CodeCommit repository..."
    
    if execute_cmd aws codecommit get-repository --repository-name "${REPO_NAME}" 2>/dev/null; then
        warning "Repository ${REPO_NAME} already exists"
    else
        execute_cmd aws codecommit create-repository \
            --repository-name "${REPO_NAME}" \
            --repository-description "Multi-branch CI/CD demo application"
        
        success "Repository created: ${REPO_NAME}"
    fi
    
    # Get repository clone URL
    export REPO_URL=$(aws codecommit get-repository \
        --repository-name "${REPO_NAME}" \
        --query 'repositoryMetadata.cloneUrlHttp' \
        --output text)
    
    echo "REPO_URL=${REPO_URL}" >> .deployment-config
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create CodePipeline service role
    if execute_cmd aws iam get-role --role-name "${PIPELINE_ROLE_NAME}" 2>/dev/null; then
        warning "Role ${PIPELINE_ROLE_NAME} already exists"
    else
        execute_cmd aws iam create-role \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "codepipeline.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeCommitFullAccess
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess
        
        success "CodePipeline role created: ${PIPELINE_ROLE_NAME}"
    fi
    
    # Create CodeBuild service role
    if execute_cmd aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" 2>/dev/null; then
        warning "Role ${CODEBUILD_ROLE_NAME} already exists"
    else
        execute_cmd aws iam create-role \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "codebuild.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        success "CodeBuild role created: ${CODEBUILD_ROLE_NAME}"
    fi
    
    # Create Lambda execution role
    if execute_cmd aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null; then
        warning "Role ${LAMBDA_ROLE_NAME} already exists"
    else
        execute_cmd aws iam create-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --assume-role-policy-document '{
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
            }'
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
        
        execute_cmd aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess
        
        success "Lambda role created: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Wait for role propagation
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM role propagation..."
        sleep 15
    fi
}

# Create CodeBuild project
create_codebuild_project() {
    log "Creating CodeBuild project..."
    
    if execute_cmd aws codebuild batch-get-projects --names "${CODEBUILD_PROJECT_NAME}" 2>/dev/null | grep -q "${CODEBUILD_PROJECT_NAME}"; then
        warning "CodeBuild project ${CODEBUILD_PROJECT_NAME} already exists"
    else
        execute_cmd aws codebuild create-project \
            --name "${CODEBUILD_PROJECT_NAME}" \
            --description "Build project for multi-branch pipelines" \
            --service-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CODEBUILD_ROLE_NAME}" \
            --artifacts '{
                "type": "CODEPIPELINE"
            }' \
            --environment '{
                "type": "LINUX_CONTAINER",
                "image": "aws/codebuild/amazonlinux2-x86_64-standard:3.0",
                "computeType": "BUILD_GENERAL1_SMALL",
                "environmentVariables": [
                    {
                        "name": "AWS_DEFAULT_REGION",
                        "value": "'${AWS_REGION}'"
                    },
                    {
                        "name": "AWS_ACCOUNT_ID",
                        "value": "'${AWS_ACCOUNT_ID}'"
                    }
                ]
            }' \
            --source '{
                "type": "CODEPIPELINE",
                "buildspec": "version: 0.2\nphases:\n  pre_build:\n    commands:\n      - echo Logging in to Amazon ECR...\n      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com\n  build:\n    commands:\n      - echo Build started on `date`\n      - echo Building the Docker image...\n      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .\n      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG\n  post_build:\n    commands:\n      - echo Build completed on `date`\n      - echo Pushing the Docker image...\n      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG\nartifacts:\n  files:\n    - '**/*'"
            }'
        
        success "CodeBuild project created: ${CODEBUILD_PROJECT_NAME}"
    fi
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function for pipeline automation..."
    
    # Create Lambda function code
    cat > pipeline-manager.py << 'EOF'
import json
import boto3
import os
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codepipeline = boto3.client('codepipeline')
codecommit = boto3.client('codecommit')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to manage multi-branch CI/CD pipelines
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        repository_name = detail.get('requestParameters', {}).get('repositoryName', '')
        
        if event_name == 'CreateBranch':
            return handle_branch_creation(detail, repository_name)
        elif event_name == 'DeleteBranch':
            return handle_branch_deletion(detail, repository_name)
        elif event_name == 'GitPush':
            return handle_git_push(detail, repository_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed but no action taken')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_branch_creation(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch creation events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if not branch_name:
        return {'statusCode': 400, 'body': 'Branch name not found'}
    
    # Only create pipelines for feature branches
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            create_branch_pipeline(repository_name, branch_name, pipeline_name)
            logger.info(f"Created pipeline {pipeline_name} for branch {branch_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} created successfully')
            }
        except Exception as e:
            logger.error(f"Failed to create pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline creation failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline created for this branch type'}

def handle_branch_deletion(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch deletion events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            # Delete the pipeline
            codepipeline.delete_pipeline(name=pipeline_name)
            logger.info(f"Deleted pipeline {pipeline_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} deleted successfully')
            }
        except codepipeline.exceptions.PipelineNotFoundException:
            return {
                'statusCode': 404,
                'body': json.dumps(f'Pipeline {pipeline_name} not found')
            }
        except Exception as e:
            logger.error(f"Failed to delete pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline deletion failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline deleted for this branch type'}

def handle_git_push(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle git push events"""
    # For push events, we just log and let the pipeline trigger naturally
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    logger.info(f"Git push detected on branch {branch_name} in repository {repository_name}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Git push event processed')
    }

def create_branch_pipeline(repository_name: str, branch_name: str, pipeline_name: str) -> None:
    """Create a new pipeline for the specified branch"""
    
    pipeline_definition = {
        "pipeline": {
            "name": pipeline_name,
            "roleArn": f"arn:aws:iam::{os.environ['AWS_ACCOUNT_ID']}:role/{os.environ['PIPELINE_ROLE_NAME']}",
            "artifactStore": {
                "type": "S3",
                "location": os.environ['ARTIFACT_BUCKET']
            },
            "stages": [
                {
                    "name": "Source",
                    "actions": [
                        {
                            "name": "SourceAction",
                            "actionTypeId": {
                                "category": "Source",
                                "owner": "AWS",
                                "provider": "CodeCommit",
                                "version": "1"
                            },
                            "configuration": {
                                "RepositoryName": repository_name,
                                "BranchName": branch_name
                            },
                            "outputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ]
                        }
                    ]
                },
                {
                    "name": "Build",
                    "actions": [
                        {
                            "name": "BuildAction",
                            "actionTypeId": {
                                "category": "Build",
                                "owner": "AWS",
                                "provider": "CodeBuild",
                                "version": "1"
                            },
                            "configuration": {
                                "ProjectName": os.environ['CODEBUILD_PROJECT_NAME']
                            },
                            "inputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ],
                            "outputArtifacts": [
                                {
                                    "name": "BuildOutput"
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    }
    
    # Create the pipeline
    codepipeline.create_pipeline(**pipeline_definition)
EOF
    
    # Package Lambda function
    if [[ "$DRY_RUN" == "false" ]]; then
        zip pipeline-manager.zip pipeline-manager.py
    fi
    
    # Create Lambda function
    LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    if execute_cmd aws lambda get-function --function-name "${PIPELINE_MANAGER_FUNCTION}" 2>/dev/null; then
        warning "Lambda function ${PIPELINE_MANAGER_FUNCTION} already exists"
    else
        execute_cmd aws lambda create-function \
            --function-name "${PIPELINE_MANAGER_FUNCTION}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler pipeline-manager.lambda_handler \
            --zip-file fileb://pipeline-manager.zip \
            --description "Multi-branch pipeline manager" \
            --timeout 300 \
            --environment Variables="{
                AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID},
                PIPELINE_ROLE_NAME=${PIPELINE_ROLE_NAME},
                CODEBUILD_PROJECT_NAME=${CODEBUILD_PROJECT_NAME},
                ARTIFACT_BUCKET=${ARTIFACT_BUCKET}
            }"
        
        success "Lambda function created: ${PIPELINE_MANAGER_FUNCTION}"
    fi
}

# Create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules..."
    
    # Create EventBridge rule for CodeCommit events
    execute_cmd aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --description "Trigger pipeline management for branch events" \
        --event-pattern '{
            "source": ["aws.codecommit"],
            "detail-type": ["CodeCommit Repository State Change"],
            "detail": {
                "repositoryName": ["'${REPO_NAME}'"],
                "eventName": ["CreateBranch", "DeleteBranch", "GitPush"]
            }
        }'
    
    # Add Lambda function as target
    LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PIPELINE_MANAGER_FUNCTION}"
    
    execute_cmd aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="${LAMBDA_ARN}"
    
    # Grant EventBridge permission to invoke Lambda
    execute_cmd aws lambda add-permission \
        --function-name "${PIPELINE_MANAGER_FUNCTION}" \
        --statement-id "EventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    success "EventBridge rules configured"
}

# Create base pipelines
create_base_pipelines() {
    log "Creating base pipelines for main branches..."
    
    # Create main branch pipeline
    if execute_cmd aws codepipeline get-pipeline --name "${REPO_NAME}-main" 2>/dev/null; then
        warning "Pipeline ${REPO_NAME}-main already exists"
    else
        execute_cmd aws codepipeline create-pipeline \
            --cli-input-json '{
                "pipeline": {
                    "name": "'${REPO_NAME}'-main",
                    "roleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${PIPELINE_ROLE_NAME}'",
                    "artifactStore": {
                        "type": "S3",
                        "location": "'${ARTIFACT_BUCKET}'"
                    },
                    "stages": [
                        {
                            "name": "Source",
                            "actions": [
                                {
                                    "name": "SourceAction",
                                    "actionTypeId": {
                                        "category": "Source",
                                        "owner": "AWS",
                                        "provider": "CodeCommit",
                                        "version": "1"
                                    },
                                    "configuration": {
                                        "RepositoryName": "'${REPO_NAME}'",
                                        "BranchName": "main"
                                    },
                                    "outputArtifacts": [
                                        {
                                            "name": "SourceOutput"
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "name": "Build",
                            "actions": [
                                {
                                    "name": "BuildAction",
                                    "actionTypeId": {
                                        "category": "Build",
                                        "owner": "AWS",
                                        "provider": "CodeBuild",
                                        "version": "1"
                                    },
                                    "configuration": {
                                        "ProjectName": "'${CODEBUILD_PROJECT_NAME}'"
                                    },
                                    "inputArtifacts": [
                                        {
                                            "name": "SourceOutput"
                                        }
                                    ],
                                    "outputArtifacts": [
                                        {
                                            "name": "BuildOutput"
                                        }
                                    ]
                                }
                            ]
                        }
                    ]
                }
            }'
        
        success "Main pipeline created: ${REPO_NAME}-main"
    fi
    
    # Create develop branch pipeline
    if execute_cmd aws codepipeline get-pipeline --name "${REPO_NAME}-develop" 2>/dev/null; then
        warning "Pipeline ${REPO_NAME}-develop already exists"
    else
        execute_cmd aws codepipeline create-pipeline \
            --cli-input-json '{
                "pipeline": {
                    "name": "'${REPO_NAME}'-develop",
                    "roleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${PIPELINE_ROLE_NAME}'",
                    "artifactStore": {
                        "type": "S3",
                        "location": "'${ARTIFACT_BUCKET}'"
                    },
                    "stages": [
                        {
                            "name": "Source",
                            "actions": [
                                {
                                    "name": "SourceAction",
                                    "actionTypeId": {
                                        "category": "Source",
                                        "owner": "AWS",
                                        "provider": "CodeCommit",
                                        "version": "1"
                                    },
                                    "configuration": {
                                        "RepositoryName": "'${REPO_NAME}'",
                                        "BranchName": "develop"
                                    },
                                    "outputArtifacts": [
                                        {
                                            "name": "SourceOutput"
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "name": "Build",
                            "actions": [
                                {
                                    "name": "BuildAction",
                                    "actionTypeId": {
                                        "category": "Build",
                                        "owner": "AWS",
                                        "provider": "CodeBuild",
                                        "version": "1"
                                    },
                                    "configuration": {
                                        "ProjectName": "'${CODEBUILD_PROJECT_NAME}'"
                                    },
                                    "inputArtifacts": [
                                        {
                                            "name": "SourceOutput"
                                        }
                                    ],
                                    "outputArtifacts": [
                                        {
                                            "name": "BuildOutput"
                                        }
                                    ]
                                }
                            ]
                        }
                    ]
                }
            }'
        
        success "Develop pipeline created: ${REPO_NAME}-develop"
    fi
}

# Create monitoring and alerts
create_monitoring() {
    log "Creating CloudWatch monitoring and alerts..."
    
    # Create CloudWatch dashboard
    execute_cmd aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/CodePipeline", "PipelineExecutionSuccess", "PipelineName", "'${REPO_NAME}'-main"],
                            [".", "PipelineExecutionFailure", ".", "."],
                            [".", "PipelineExecutionSuccess", ".", "'${REPO_NAME}'-develop"],
                            [".", "PipelineExecutionFailure", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "Pipeline Execution Results"
                    }
                },
                {
                    "type": "metric",
                    "x": 0,
                    "y": 6,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/CodeBuild", "Duration", "ProjectName", "'${CODEBUILD_PROJECT_NAME}'"],
                            [".", "SucceededBuilds", ".", "."],
                            [".", "FailedBuilds", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'${AWS_REGION}'",
                        "title": "Build Performance"
                    }
                }
            ]
        }'
    
    # Create SNS topic for alerts
    export ALERT_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --output text --query TopicArn)
    
    echo "ALERT_TOPIC_ARN=${ALERT_TOPIC_ARN}" >> .deployment-config
    
    # Create CloudWatch alarm for pipeline failures
    execute_cmd aws cloudwatch put-metric-alarm \
        --alarm-name "PipelineFailure-${REPO_NAME}" \
        --alarm-description "Alert when pipeline fails" \
        --metric-name PipelineExecutionFailure \
        --namespace AWS/CodePipeline \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${ALERT_TOPIC_ARN}" \
        --dimensions Name=PipelineName,Value="${REPO_NAME}-main"
    
    success "CloudWatch monitoring and alerts configured"
}

# Initialize repository with sample code
initialize_repository() {
    log "Initializing repository with sample code..."
    
    # Check if repository has been initialized
    if aws codecommit get-branch --repository-name "${REPO_NAME}" --branch-name main 2>/dev/null; then
        warning "Repository ${REPO_NAME} already has main branch"
        return 0
    fi
    
    # Create temp directory for repo
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Clone the repository
    git clone "${REPO_URL}" .
    
    # Create sample application files
    cat > buildspec.yml << 'EOF'
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG

artifacts:
  files:
    - '**/*'
EOF

    cat > Dockerfile << 'EOF'
FROM node:16-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "index.js"]
EOF

    cat > package.json << 'EOF'
{
  "name": "multi-branch-app",
  "version": "1.0.0",
  "description": "Sample application for multi-branch CI/CD",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

    cat > index.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Multi-branch CI/CD pipeline demo',
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development'
  });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF

    # Create main branch
    if [[ "$DRY_RUN" == "false" ]]; then
        git add .
        git commit -m "Initial commit with sample application"
        git push origin main
        
        # Create develop branch
        git checkout -b develop
        git push origin develop
    fi
    
    # Clean up temp directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    success "Repository initialized with sample code"
}

# Main deployment function
main() {
    log "Starting multi-branch CI/CD pipeline deployment..."
    
    check_prerequisites
    setup_environment
    create_artifact_bucket
    create_codecommit_repo
    create_iam_roles
    create_codebuild_project
    create_lambda_function
    create_eventbridge_rules
    create_base_pipelines
    create_monitoring
    initialize_repository
    
    # Clean up temporary files
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f pipeline-manager.py pipeline-manager.zip
    fi
    
    success "Multi-branch CI/CD pipeline deployment completed successfully!"
    
    echo
    echo "=== Deployment Summary ==="
    echo "Repository: ${REPO_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Artifact Bucket: ${ARTIFACT_BUCKET}"
    echo "Lambda Function: ${PIPELINE_MANAGER_FUNCTION}"
    echo "CodeBuild Project: ${CODEBUILD_PROJECT_NAME}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo
    echo "To test the multi-branch functionality:"
    echo "1. Clone the repository: git clone ${REPO_URL}"
    echo "2. Create a feature branch: git checkout -b feature/test-feature"
    echo "3. Push the branch: git push origin feature/test-feature"
    echo "4. Check AWS Console for automatically created pipeline"
    echo
    echo "Configuration saved to .deployment-config for cleanup"
}

# Execute main function
main "$@"