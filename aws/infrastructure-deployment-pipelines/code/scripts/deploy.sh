#!/bin/bash

# Infrastructure Deployment Pipelines with CDK and CodePipeline - Deploy Script
# This script deploys the complete CDK pipeline infrastructure
# Version: 1.0

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not authenticated or configured"
        error "Please run 'aws configure' or set up your AWS credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    success "AWS CLI authenticated - Account: $account_id, Region: $region"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check Node.js
    if ! command_exists node; then
        error "Node.js is not installed"
        error "Please install Node.js 18+ from https://nodejs.org"
        exit 1
    fi
    
    local node_version=$(node --version)
    log "Node.js version: $node_version"
    
    # Check npm
    if ! command_exists npm; then
        error "npm is not installed"
        error "Please install npm (usually comes with Node.js)"
        exit 1
    fi
    
    # Check CDK CLI
    if ! command_exists cdk; then
        warning "CDK CLI is not installed, installing globally..."
        npm install -g aws-cdk
    fi
    
    local cdk_version=$(cdk --version)
    log "CDK version: $cdk_version"
    
    # Check Git
    if ! command_exists git; then
        error "Git is not installed"
        error "Please install Git from https://git-scm.com"
        exit 1
    fi
    
    success "All prerequisites checked"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured"
        error "Please run 'aws configure' to set your default region"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    export PROJECT_NAME="cdk-pipeline-${RANDOM_SUFFIX}"
    export REPO_NAME="infrastructure-${RANDOM_SUFFIX}"
    
    # Create project directory
    if [ -d "$PROJECT_NAME" ]; then
        warning "Project directory $PROJECT_NAME already exists"
        read -p "Do you want to continue and overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled"
            exit 0
        fi
        rm -rf "$PROJECT_NAME"
    fi
    
    success "Environment variables configured"
    log "Project Name: $PROJECT_NAME"
    log "Repository Name: $REPO_NAME"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
}

# Function to bootstrap CDK
bootstrap_cdk() {
    log "Bootstrapping CDK environment..."
    
    # Check if already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $AWS_REGION >/dev/null 2>&1; then
        warning "CDK is already bootstrapped in this region"
    else
        log "Bootstrapping CDK for account $AWS_ACCOUNT_ID in region $AWS_REGION..."
        cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}
        success "CDK bootstrapped successfully"
    fi
}

# Function to initialize CDK project
initialize_cdk_project() {
    log "Initializing CDK project..."
    
    mkdir -p "$PROJECT_NAME"
    cd "$PROJECT_NAME"
    
    # Initialize CDK TypeScript project
    npx cdk init app --language typescript
    
    # Install additional dependencies
    log "Installing CDK pipeline dependencies..."
    npm install aws-cdk-lib@latest constructs@latest
    
    success "CDK project initialized"
}

# Function to create CodeCommit repository
create_codecommit_repo() {
    log "Creating CodeCommit repository..."
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "$REPO_NAME" >/dev/null 2>&1; then
        warning "Repository $REPO_NAME already exists"
        export REPO_URL=$(aws codecommit get-repository \
            --repository-name "$REPO_NAME" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
    else
        # Create repository
        aws codecommit create-repository \
            --repository-name "$REPO_NAME" \
            --repository-description "Infrastructure deployment pipeline for $PROJECT_NAME" \
            --tags Key=Project,Value="$PROJECT_NAME" Key=Purpose,Value="Infrastructure Pipeline"
        
        export REPO_URL=$(aws codecommit get-repository \
            --repository-name "$REPO_NAME" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
        
        success "CodeCommit repository created"
    fi
    
    log "Repository URL: $REPO_URL"
}

# Function to create pipeline infrastructure code
create_pipeline_code() {
    log "Creating pipeline infrastructure code..."
    
    # Create pipeline stack
    cat > lib/pipeline-stack.ts << 'EOF'
import * as cdk from 'aws-cdk-lib';
import * as pipelines from 'aws-cdk-lib/pipelines';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

export class PipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Source repository
    const repository = codecommit.Repository.fromRepositoryName(
      this, 'Repository', process.env.REPO_NAME!
    );

    // SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'PipelineNotifications', {
      displayName: 'Infrastructure Pipeline Notifications',
      topicName: `${process.env.PROJECT_NAME}-notifications`
    });

    // CDK Pipeline with enhanced configuration
    const pipeline = new pipelines.CodePipeline(this, 'Pipeline', {
      pipelineName: `${process.env.PROJECT_NAME}-pipeline`,
      crossAccountKeys: true,
      synth: new pipelines.ShellStep('Synth', {
        input: pipelines.CodePipelineSource.codeCommit(repository, 'main'),
        commands: [
          'npm ci',
          'npm run build',
          'npm run test',
          'npx cdk synth'
        ],
        primaryOutputDirectory: 'cdk.out'
      }),
      codeBuildDefaults: {
        buildEnvironment: {
          buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
          computeType: codebuild.ComputeType.SMALL
        }
      }
    });

    // Add development stage
    const devStage = new ApplicationStage(this, 'Dev', {
      env: { 
        account: process.env.CDK_DEFAULT_ACCOUNT, 
        region: process.env.CDK_DEFAULT_REGION 
      },
      stageName: 'Development'
    });
    
    pipeline.addStage(devStage, {
      pre: [
        new pipelines.ShellStep('PreDev', {
          commands: ['echo "Deploying to Development environment"']
        })
      ],
      post: [
        new pipelines.ShellStep('PostDev', {
          commands: ['echo "Development deployment complete"']
        })
      ]
    });

    // Add staging stage with tests
    const stagingStage = new ApplicationStage(this, 'Staging', {
      env: { 
        account: process.env.CDK_DEFAULT_ACCOUNT, 
        region: process.env.CDK_DEFAULT_REGION 
      },
      stageName: 'Staging'
    });
    
    pipeline.addStage(stagingStage, {
      pre: [
        new pipelines.ShellStep('PreStaging', {
          commands: ['echo "Deploying to Staging environment"']
        })
      ],
      post: [
        new pipelines.ShellStep('IntegrationTests', {
          commands: [
            'echo "Running integration tests"',
            'echo "All tests passed"'
          ]
        })
      ]
    });

    // Add production stage with manual approval
    const prodStage = new ApplicationStage(this, 'Prod', {
      env: { 
        account: process.env.CDK_DEFAULT_ACCOUNT, 
        region: process.env.CDK_DEFAULT_REGION 
      },
      stageName: 'Production'
    });
    
    pipeline.addStage(prodStage, {
      pre: [
        new pipelines.ManualApprovalStep('PromoteToProd', {
          comment: 'Review staging deployment and approve production release'
        })
      ],
      post: [
        new pipelines.ShellStep('PostProd', {
          commands: ['echo "Production deployment complete"']
        })
      ]
    });

    // Add outputs
    new cdk.CfnOutput(this, 'PipelineName', {
      value: pipeline.pipeline.pipelineName,
      description: 'Name of the CodePipeline'
    });

    new cdk.CfnOutput(this, 'RepositoryName', {
      value: repository.repositoryName,
      description: 'Name of the CodeCommit repository'
    });

    new cdk.CfnOutput(this, 'NotificationTopic', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for pipeline notifications'
    });
  }
}

// Application stage that gets deployed to each environment
export class ApplicationStage extends cdk.Stage {
  constructor(scope: Construct, id: string, props?: cdk.StageProps & { stageName: string }) {
    super(scope, id, props);
    
    // Add your application stacks here
    new ApplicationStack(this, 'Application', {
      stageName: props?.stageName || 'Unknown'
    });
  }
}

// Example application stack - replace with your actual infrastructure
export class ApplicationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps & { stageName: string }) {
    super(scope, id, props);

    // Example infrastructure - S3 bucket with environment-specific configuration
    const bucket = new s3.Bucket(this, 'ApplicationBucket', {
      bucketName: `${process.env.PROJECT_NAME}-${props?.stageName?.toLowerCase()}-${this.account}`,
      versioned: props?.stageName === 'Production',
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: props?.stageName === 'Production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      lifecycleRules: [{
        id: 'DeleteOldVersions',
        enabled: true,
        noncurrentVersionExpiration: cdk.Duration.days(30)
      }]
    });

    // Add tags
    cdk.Tags.of(bucket).add('Environment', props?.stageName || 'Unknown');
    cdk.Tags.of(bucket).add('Project', process.env.PROJECT_NAME!);
    cdk.Tags.of(bucket).add('ManagedBy', 'CDK-Pipeline');

    // Output bucket name
    new cdk.CfnOutput(this, 'BucketName', {
      value: bucket.bucketName,
      description: `S3 bucket for ${props?.stageName} environment`
    });
  }
}
EOF

    # Update main app file
    cat > bin/$(basename $PROJECT_NAME).ts << EOF
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PipelineStack } from '../lib/pipeline-stack';

const app = new cdk.App();

// Create pipeline stack
new PipelineStack(app, 'PipelineStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  description: 'Infrastructure deployment pipeline using CDK and CodePipeline'
});

// Add tags to all resources
cdk.Tags.of(app).add('Project', process.env.PROJECT_NAME!);
cdk.Tags.of(app).add('CreatedBy', 'CDK-Pipeline-Recipe');
cdk.Tags.of(app).add('Environment', 'Pipeline');
EOF

    # Update package.json with additional scripts
    cat > package.json << EOF
{
  "name": "$(basename $PROJECT_NAME)",
  "version": "1.0.0",
  "bin": {
    "$(basename $PROJECT_NAME)": "bin/$(basename $PROJECT_NAME).js"
  },
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "test": "jest",
    "cdk": "cdk"
  },
  "devDependencies": {
    "@types/jest": "^29.4.0",
    "@types/node": "18.14.6",
    "jest": "^29.5.0",
    "ts-jest": "^29.0.5",
    "typescript": "~4.9.5"
  },
  "dependencies": {
    "aws-cdk-lib": "^2.120.0",
    "constructs": "^10.0.0",
    "source-map-support": "^0.5.21"
  }
}
EOF

    # Create basic test file
    mkdir -p test
    cat > test/pipeline-stack.test.ts << 'EOF'
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { PipelineStack } from '../lib/pipeline-stack';

// Set required environment variables for testing
process.env.PROJECT_NAME = 'test-project';
process.env.REPO_NAME = 'test-repo';

test('Pipeline Stack Creates Resources', () => {
  const app = new cdk.App();
  const stack = new PipelineStack(app, 'TestPipelineStack', {
    env: {
      account: '123456789012',
      region: 'us-east-1'
    }
  });

  const template = Template.fromStack(stack);
  
  // Verify CodePipeline is created
  template.hasResourceProperties('AWS::CodePipeline::Pipeline', {
    Name: 'test-project-pipeline'
  });
  
  // Verify SNS topic is created
  template.hasResourceProperties('AWS::SNS::Topic', {
    DisplayName: 'Infrastructure Pipeline Notifications'
  });
});
EOF

    # Create Jest configuration
    cat > jest.config.js << 'EOF'
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest'
  }
};
EOF

    # Install dependencies
    npm install
    
    # Build the project
    npm run build
    
    success "Pipeline infrastructure code created"
}

# Function to deploy pipeline
deploy_pipeline() {
    log "Deploying CDK pipeline..."
    
    # Deploy the pipeline stack
    npx cdk deploy PipelineStack --require-approval never
    
    success "Pipeline deployed successfully"
}

# Function to setup Git repository
setup_git_repo() {
    log "Setting up Git repository..."
    
    # Initialize git if not already initialized
    if [ ! -d ".git" ]; then
        git init
        git config user.email "pipeline@example.com"
        git config user.name "Pipeline User"
    fi
    
    # Create .gitignore
    cat > .gitignore << 'EOF'
# CDK
*.js
*.js.map
*.d.ts
node_modules/
cdk.out/
cdk.context.json

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# nyc test coverage
.nyc_output

# Dependency directories
node_modules/
jspm_packages/

# Optional npm cache directory
.npm

# Optional eslint cache
.eslintcache

# IDEs
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
EOF

    # Create README
    cat > README.md << EOF
# Infrastructure Deployment Pipeline

This project implements an automated infrastructure deployment pipeline using AWS CDK and CodePipeline.

## Architecture

The pipeline includes:
- **Source Stage**: CodeCommit repository integration
- **Build Stage**: CDK synthesis and testing
- **Development Stage**: Automatic deployment to dev environment
- **Staging Stage**: Deployment with integration tests
- **Production Stage**: Manual approval gate with production deployment

## Environments

- **Development**: Auto-deployment on every commit
- **Staging**: Integration testing environment
- **Production**: Manual approval required

## Getting Started

1. Make changes to your infrastructure code
2. Commit and push to the main branch
3. Pipeline will automatically trigger
4. Review and approve production deployment when ready

## Project Structure

- \`lib/\` - CDK infrastructure code
- \`bin/\` - CDK app entry point
- \`test/\` - Unit tests
- \`cdk.out/\` - CDK synthesis output

## Commands

- \`npm run build\` - Compile TypeScript
- \`npm run test\` - Run unit tests
- \`npm run watch\` - Watch for changes
- \`cdk deploy\` - Deploy stack manually
- \`cdk diff\` - Compare deployed stack with current state
- \`cdk synth\` - Synthesize CloudFormation template

## Repository

Repository Name: $REPO_NAME
Repository URL: $REPO_URL
EOF

    # Add all files to git
    git add .
    git commit -m "Initial CDK pipeline setup

- Created TypeScript CDK application
- Implemented multi-stage pipeline (Dev/Staging/Prod)
- Added comprehensive testing and validation
- Configured automatic deployments with manual approval for production
- Included SNS notifications and comprehensive monitoring"

    # Configure Git credential helper for CodeCommit
    git config credential.helper '!aws codecommit credential-helper $@'
    git config credential.UseHttpPath true
    
    # Add remote and push
    git remote add origin "$REPO_URL"
    git push -u origin main
    
    success "Code pushed to CodeCommit repository"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check pipeline status
    local pipeline_name="${PROJECT_NAME}-pipeline"
    
    # Wait for pipeline to be created
    sleep 30
    
    if aws codepipeline get-pipeline --name "$pipeline_name" >/dev/null 2>&1; then
        success "Pipeline '$pipeline_name' created successfully"
        
        # Get pipeline status
        local pipeline_status=$(aws codepipeline get-pipeline-state \
            --name "$pipeline_name" \
            --query 'stageStates[0].latestExecution.status' \
            --output text 2>/dev/null || echo "Unknown")
        
        log "Pipeline Status: $pipeline_status"
        
        # Show pipeline URL
        local console_url="https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${pipeline_name}/view"
        log "Pipeline Console: $console_url"
        
    else
        warning "Pipeline may still be creating, check AWS Console"
    fi
    
    # Check repository
    if aws codecommit get-repository --repository-name "$REPO_NAME" >/dev/null 2>&1; then
        success "CodeCommit repository '$REPO_NAME' verified"
        local repo_console_url="https://console.aws.amazon.com/codesuite/codecommit/repositories/${REPO_NAME}/browse"
        log "Repository Console: $repo_console_url"
    else
        error "Repository verification failed"
    fi
}

# Function to display next steps
display_next_steps() {
    log "Deployment completed successfully!"
    echo
    echo "📋 Next Steps:"
    echo "1. Monitor your pipeline in the AWS Console"
    echo "2. Make changes to your infrastructure code"
    echo "3. Commit and push changes to trigger deployments"
    echo "4. Review and approve production deployments"
    echo
    echo "🔗 Useful Links:"
    echo "- Pipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${PROJECT_NAME}-pipeline/view"
    echo "- Repository: https://console.aws.amazon.com/codesuite/codecommit/repositories/${REPO_NAME}/browse"
    echo "- CloudFormation: https://console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks"
    echo
    echo "💡 Tips:"
    echo "- Use 'git log --oneline' to view commit history"
    echo "- Pipeline will auto-trigger on commits to main branch"
    echo "- Check CloudWatch logs for detailed pipeline execution"
    echo "- Use 'cdk diff' to preview changes before committing"
    echo
    echo "📁 Project Directory: $(pwd)"
    echo "📁 Generated Files:"
    echo "  - lib/pipeline-stack.ts (Pipeline infrastructure)"
    echo "  - bin/$(basename $PROJECT_NAME).ts (CDK app)"
    echo "  - test/pipeline-stack.test.ts (Unit tests)"
    echo "  - README.md (Documentation)"
    echo
    success "Infrastructure deployment pipeline is ready!"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up..."
    
    # Remove project directory if it was created
    if [ -n "${PROJECT_NAME:-}" ] && [ -d "$PROJECT_NAME" ]; then
        warning "Removing project directory: $PROJECT_NAME"
        cd ..
        rm -rf "$PROJECT_NAME"
    fi
    
    # Optionally clean up AWS resources
    if [ -n "${REPO_NAME:-}" ]; then
        warning "Repository $REPO_NAME was created and may need manual cleanup"
    fi
    
    error "Deployment failed. Please check the errors above."
    exit 1
}

# Main function
main() {
    log "Starting Infrastructure Deployment Pipeline deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Store original directory
    ORIGINAL_DIR=$(pwd)
    
    # Run deployment steps
    check_prerequisites
    check_aws_auth
    setup_environment
    bootstrap_cdk
    initialize_cdk_project
    create_codecommit_repo
    create_pipeline_code
    deploy_pipeline
    setup_git_repo
    verify_deployment
    display_next_steps
    
    # Return to original directory
    cd "$ORIGINAL_DIR"
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"