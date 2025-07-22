#!/bin/bash

# Deploy script for Continuous Deployment with CodeDeploy
# This script automates the deployment of a complete CI/CD pipeline using CodeDeploy

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if AWS CLI is installed and configured
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check git installation
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install it first."
        exit 1
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || warning "Cannot verify IAM permissions. Continuing..."
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please configure AWS CLI or set AWS_REGION environment variable."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    export APP_NAME="webapp-${RANDOM_SUFFIX}"
    export REPO_NAME="webapp-repo-${RANDOM_SUFFIX}"
    export BUILD_PROJECT_NAME="webapp-build-${RANDOM_SUFFIX}"
    export DEPLOYMENT_GROUP_NAME="webapp-depgroup-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="webapp-keypair-${RANDOM_SUFFIX}"
    export ARTIFACTS_BUCKET_NAME="codedeploy-artifacts-${RANDOM_SUFFIX}"
    
    # Get VPC information
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$DEFAULT_VPC_ID" = "None" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    export SUBNET_ID_1=$(echo $SUBNET_IDS | cut -d' ' -f1)
    export SUBNET_ID_2=$(echo $SUBNET_IDS | cut -d' ' -f2)
    
    if [ -z "$SUBNET_ID_1" ] || [ -z "$SUBNET_ID_2" ]; then
        error "Insufficient subnets in default VPC. At least 2 subnets required."
        exit 1
    fi
    
    # Save environment to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
REPO_NAME=${REPO_NAME}
BUILD_PROJECT_NAME=${BUILD_PROJECT_NAME}
DEPLOYMENT_GROUP_NAME=${DEPLOYMENT_GROUP_NAME}
KEY_PAIR_NAME=${KEY_PAIR_NAME}
ARTIFACTS_BUCKET_NAME=${ARTIFACTS_BUCKET_NAME}
DEFAULT_VPC_ID=${DEFAULT_VPC_ID}
SUBNET_ID_1=${SUBNET_ID_1}
SUBNET_ID_2=${SUBNET_ID_2}
EOF
    
    success "Environment variables configured"
    log "App Name: $APP_NAME"
    log "Repository: $REPO_NAME"
    log "VPC ID: $DEFAULT_VPC_ID"
}

# Create IAM roles and policies
create_iam_roles() {
    log "Creating IAM roles and policies..."
    
    # Check if roles already exist
    if aws iam get-role --role-name CodeDeployServiceRole &>/dev/null; then
        warning "CodeDeployServiceRole already exists, skipping creation"
    else
        # Create CodeDeploy service role
        aws iam create-role \
            --role-name CodeDeployServiceRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "codedeploy.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' > /dev/null
        
        aws iam attach-role-policy \
            --role-name CodeDeployServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
    fi
    
    # Create EC2 role for CodeDeploy agent
    if aws iam get-role --role-name CodeDeployEC2Role &>/dev/null; then
        warning "CodeDeployEC2Role already exists, skipping creation"
    else
        aws iam create-role \
            --role-name CodeDeployEC2Role \
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
        
        aws iam attach-role-policy \
            --role-name CodeDeployEC2Role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy
        
        aws iam attach-role-policy \
            --role-name CodeDeployEC2Role \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    fi
    
    # Create instance profile
    if aws iam get-instance-profile --instance-profile-name CodeDeployEC2InstanceProfile &>/dev/null; then
        warning "CodeDeployEC2InstanceProfile already exists, skipping creation"
    else
        aws iam create-instance-profile \
            --instance-profile-name CodeDeployEC2InstanceProfile > /dev/null
        
        aws iam add-role-to-instance-profile \
            --instance-profile-name CodeDeployEC2InstanceProfile \
            --role-name CodeDeployEC2Role
        
        log "Waiting for instance profile to be ready..."
        sleep 10
    fi
    
    success "IAM roles and policies created"
}

# Create EC2 resources
create_ec2_resources() {
    log "Creating EC2 resources..."
    
    # Create EC2 Key Pair
    if aws ec2 describe-key-pairs --key-names $KEY_PAIR_NAME &>/dev/null; then
        warning "Key pair $KEY_PAIR_NAME already exists, skipping creation"
    else
        aws ec2 create-key-pair \
            --key-name $KEY_PAIR_NAME \
            --query 'KeyMaterial' --output text > "${KEY_PAIR_NAME}.pem"
        chmod 400 "${KEY_PAIR_NAME}.pem"
        log "Key pair saved to ${KEY_PAIR_NAME}.pem"
    fi
    
    # Create security group for ALB
    export ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "${APP_NAME}-alb-sg" \
        --description "Security group for ALB" \
        --vpc-id $DEFAULT_VPC_ID \
        --query 'GroupId' --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${APP_NAME}-alb-sg" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Allow HTTP traffic to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id $ALB_SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 2>/dev/null || warning "ALB security group rule already exists"
    
    # Create security group for EC2 instances
    export EC2_SG_ID=$(aws ec2 create-security-group \
        --group-name "${APP_NAME}-ec2-sg" \
        --description "Security group for EC2 instances" \
        --vpc-id $DEFAULT_VPC_ID \
        --query 'GroupId' --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${APP_NAME}-ec2-sg" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Allow HTTP traffic from ALB and SSH
    aws ec2 authorize-security-group-ingress \
        --group-id $EC2_SG_ID \
        --protocol tcp \
        --port 80 \
        --source-group $ALB_SG_ID 2>/dev/null || warning "EC2 HTTP rule already exists"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $EC2_SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 2>/dev/null || warning "EC2 SSH rule already exists"
    
    # Update environment file with security group IDs
    echo "ALB_SG_ID=${ALB_SG_ID}" >> .env
    echo "EC2_SG_ID=${EC2_SG_ID}" >> .env
    
    success "EC2 resources created"
}

# Create Application Load Balancer and target groups
create_load_balancer() {
    log "Creating Application Load Balancer and target groups..."
    
    # Create Application Load Balancer
    export ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${APP_NAME}-alb" \
        --subnets $SUBNET_ID_1 $SUBNET_ID_2 \
        --security-groups $ALB_SG_ID \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || \
        aws elbv2 describe-load-balancers \
        --names "${APP_NAME}-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Create target groups for blue-green deployment
    export TG_BLUE_ARN=$(aws elbv2 create-target-group \
        --name "${APP_NAME}-tg-blue" \
        --protocol HTTP \
        --port 80 \
        --vpc-id $DEFAULT_VPC_ID \
        --health-check-path / \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || \
        aws elbv2 describe-target-groups \
        --names "${APP_NAME}-tg-blue" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    export TG_GREEN_ARN=$(aws elbv2 create-target-group \
        --name "${APP_NAME}-tg-green" \
        --protocol HTTP \
        --port 80 \
        --vpc-id $DEFAULT_VPC_ID \
        --health-check-path / \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || \
        aws elbv2 describe-target-groups \
        --names "${APP_NAME}-tg-green" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener for ALB
    export LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_BLUE_ARN \
        --query 'Listeners[0].ListenerArn' --output text 2>/dev/null || \
        aws elbv2 describe-listeners \
        --load-balancer-arn $ALB_ARN \
        --query 'Listeners[0].ListenerArn' --output text)
    
    # Update environment file
    echo "ALB_ARN=${ALB_ARN}" >> .env
    echo "TG_BLUE_ARN=${TG_BLUE_ARN}" >> .env
    echo "TG_GREEN_ARN=${TG_GREEN_ARN}" >> .env
    echo "LISTENER_ARN=${LISTENER_ARN}" >> .env
    
    success "Application Load Balancer and target groups created"
}

# Create Auto Scaling Group
create_auto_scaling_group() {
    log "Creating Auto Scaling Group and launch template..."
    
    # Get Amazon Linux 2 AMI ID
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Create launch template
    USER_DATA=$(base64 -w 0 <<EOF
#!/bin/bash
yum update -y
yum install -y ruby wget httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Blue Environment - Version 1.0</h1>" > /var/www/html/index.html
cd /home/ec2-user
wget https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl start codedeploy-agent
systemctl enable codedeploy-agent
EOF
)
    
    aws ec2 create-launch-template \
        --launch-template-name "${APP_NAME}-launch-template" \
        --launch-template-data "{
            \"ImageId\": \"$AMI_ID\",
            \"InstanceType\": \"t3.micro\",
            \"KeyName\": \"$KEY_PAIR_NAME\",
            \"SecurityGroupIds\": [\"$EC2_SG_ID\"],
            \"IamInstanceProfile\": {
                \"Name\": \"CodeDeployEC2InstanceProfile\"
            },
            \"UserData\": \"$USER_DATA\"
        }" > /dev/null 2>&1 || warning "Launch template might already exist"
    
    # Create Auto Scaling Group
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "${APP_NAME}-asg" \
        --launch-template LaunchTemplateName="${APP_NAME}-launch-template",Version='$Latest' \
        --min-size 2 \
        --max-size 4 \
        --desired-capacity 2 \
        --target-group-arns $TG_BLUE_ARN \
        --vpc-zone-identifier "${SUBNET_ID_1},${SUBNET_ID_2}" \
        --tags Key=Name,Value="${APP_NAME}-instance",PropagateAtLaunch=true \
               Key=Environment,Value=blue,PropagateAtLaunch=true 2>/dev/null || \
               warning "Auto Scaling Group might already exist"
    
    log "Waiting for instances to launch and become healthy..."
    sleep 60
    
    success "Auto Scaling Group and launch template created"
}

# Create CodeCommit repository
create_codecommit_repo() {
    log "Creating CodeCommit repository with sample application..."
    
    # Create CodeCommit repository
    aws codecommit create-repository \
        --repository-name $REPO_NAME \
        --repository-description "Repository for webapp deployment" > /dev/null 2>&1 || \
        warning "Repository might already exist"
    
    # Clone the repository
    if [ -d "$REPO_NAME" ]; then
        warning "Repository directory already exists, removing..."
        rm -rf $REPO_NAME
    fi
    
    git clone https://codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${REPO_NAME} 2>/dev/null || {
        error "Failed to clone repository. Check AWS credentials and permissions."
        exit 1
    }
    
    cd $REPO_NAME
    
    # Create sample application files
    mkdir -p scripts
    
    # Create application specification file
    cat > appspec.yml << 'EOF'
version: 0.0
os: linux
files:
  - source: /
    destination: /var/www/html
    overwrite: true
hooks:
  BeforeInstall:
    - location: scripts/install_dependencies.sh
      timeout: 300
      runas: root
  ApplicationStart:
    - location: scripts/start_server.sh
      timeout: 300
      runas: root
  ApplicationStop:
    - location: scripts/stop_server.sh
      timeout: 300
      runas: root
  ValidateService:
    - location: scripts/validate_service.sh
      timeout: 300
      runas: root
EOF
    
    # Create application HTML file
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>WebApp Deployment</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #4CAF50; color: white; padding: 20px; }
        .content { padding: 20px; }
        .version { background-color: #f0f0f0; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>WebApp Continuous Deployment</h1>
    </div>
    <div class="content">
        <div class="version">
            <h2>Version: 2.0</h2>
            <p>Environment: Green</p>
            <p>Deployment Status: Success</p>
        </div>
        <p>This application was deployed using AWS CodeDeploy with blue-green deployment strategy.</p>
        <p>Deployment timestamp: <span id="timestamp"></span></p>
    </div>
    <script>
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
    
    # Create deployment scripts
    cat > scripts/install_dependencies.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
EOF
    
    cat > scripts/start_server.sh << 'EOF'
#!/bin/bash
systemctl start httpd
systemctl enable httpd
EOF
    
    cat > scripts/stop_server.sh << 'EOF'
#!/bin/bash
systemctl stop httpd
EOF
    
    cat > scripts/validate_service.sh << 'EOF'
#!/bin/bash
systemctl is-active httpd
curl -f http://localhost/ || exit 1
EOF
    
    chmod +x scripts/*.sh
    
    # Create buildspec for CodeBuild
    cat > buildspec.yml << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: 14
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - echo Build started on `date`
  build:
    commands:
      - echo Build completed on `date`
artifacts:
  files:
    - '**/*'
EOF
    
    # Commit initial code
    git add .
    git commit -m "Initial commit with sample web application"
    git push origin main
    
    cd ..
    
    success "CodeCommit repository created with sample application"
}

# Create CodeBuild project
create_codebuild_project() {
    log "Creating CodeBuild project..."
    
    # Create CodeBuild service role
    if aws iam get-role --role-name CodeBuildServiceRole &>/dev/null; then
        warning "CodeBuildServiceRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name CodeBuildServiceRole \
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
            }' > /dev/null
        
        # Create and attach policy for CodeBuild
        cat > codebuild-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "codecommit:GitPull",
                "s3:GetObject",
                "s3:PutObject",
                "s3:GetBucketLocation",
                "s3:ListBucket"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name CodeBuildServiceRole \
            --policy-name CodeBuildServicePolicy \
            --policy-document file://codebuild-policy.json
        
        rm -f codebuild-policy.json
    fi
    
    # Create S3 bucket for artifacts
    aws s3 mb s3://$ARTIFACTS_BUCKET_NAME 2>/dev/null || warning "S3 bucket might already exist"
    
    # Create CodeBuild project
    aws codebuild create-project \
        --name $BUILD_PROJECT_NAME \
        --source type=CODECOMMIT,location=https://codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${REPO_NAME} \
        --artifacts type=S3,location=${ARTIFACTS_BUCKET_NAME}/artifacts \
        --environment type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:3.0,computeType=BUILD_GENERAL1_SMALL \
        --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/CodeBuildServiceRole > /dev/null 2>&1 || \
        warning "CodeBuild project might already exist"
    
    success "CodeBuild project created"
}

# Create CodeDeploy application
create_codedeploy_application() {
    log "Creating CodeDeploy application and deployment group..."
    
    # Create CodeDeploy application
    aws deploy create-application \
        --application-name $APP_NAME \
        --compute-platform EC2/On-Premises > /dev/null 2>&1 || \
        warning "CodeDeploy application might already exist"
    
    # Create deployment group with blue-green configuration
    aws deploy create-deployment-group \
        --application-name $APP_NAME \
        --deployment-group-name $DEPLOYMENT_GROUP_NAME \
        --service-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/CodeDeployServiceRole \
        --auto-scaling-groups "${APP_NAME}-asg" \
        --deployment-config-name CodeDeployDefault.AllAtOnceBlueGreen \
        --blue-green-deployment-configuration '{
            "deploymentReadyOption": {
                "actionOnTimeout": "CONTINUE_DEPLOYMENT"
            },
            "terminateBlueInstancesOnDeploymentSuccess": {
                "action": "TERMINATE",
                "terminationWaitTimeInMinutes": 5
            },
            "greenFleetProvisioningOption": {
                "action": "COPY_AUTO_SCALING_GROUP"
            }
        }' \
        --load-balancer-info "{
            \"targetGroupInfoList\": [
                {
                    \"name\": \"$(basename $TG_BLUE_ARN)\"
                }
            ]
        }" > /dev/null 2>&1 || warning "Deployment group might already exist"
    
    success "CodeDeploy application and deployment group created"
}

# Trigger initial deployment
trigger_deployment() {
    log "Triggering initial build and deployment..."
    
    # Start CodeBuild build
    export BUILD_ID=$(aws codebuild start-build \
        --project-name $BUILD_PROJECT_NAME \
        --query 'build.id' --output text)
    
    log "Build started: $BUILD_ID"
    
    # Wait for build to complete
    log "Waiting for build to complete..."
    aws codebuild wait build-succeeded --ids $BUILD_ID || {
        error "Build failed. Check CodeBuild logs for details."
        exit 1
    }
    
    # Create deployment
    export DEPLOYMENT_ID=$(aws deploy create-deployment \
        --application-name $APP_NAME \
        --deployment-group-name $DEPLOYMENT_GROUP_NAME \
        --s3-location bucket=$ARTIFACTS_BUCKET_NAME,key=artifacts,bundleType=zip \
        --deployment-config-name CodeDeployDefault.AllAtOnceBlueGreen \
        --description "Initial blue-green deployment" \
        --query 'deploymentId' --output text)
    
    log "Deployment started: $DEPLOYMENT_ID"
    echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> .env
    
    # Get ALB DNS name for testing
    export ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    echo "ALB_DNS=${ALB_DNS}" >> .env
    
    success "Initial deployment triggered"
    log "Application will be available at: http://$ALB_DNS"
    log "You can monitor the deployment progress in the AWS Console"
}

# Main deployment function
main() {
    log "Starting deployment of Continuous Deployment with CodeDeploy..."
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_ec2_resources
    create_load_balancer
    create_auto_scaling_group
    create_codecommit_repo
    create_codebuild_project
    create_codedeploy_application
    trigger_deployment
    
    success "Deployment completed successfully!"
    log "Environment details saved to .env file"
    log "To clean up resources, run: ./destroy.sh"
    
    # Display useful information
    echo ""
    echo "=== Deployment Summary ==="
    echo "Application Name: $APP_NAME"
    echo "Repository: $REPO_NAME"
    echo "Build Project: $BUILD_PROJECT_NAME"
    echo "Application URL: http://$ALB_DNS"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Next steps:"
    echo "1. Wait for deployment to complete (5-10 minutes)"
    echo "2. Access your application at: http://$ALB_DNS"
    echo "3. Make changes to the code in the $REPO_NAME repository to trigger new deployments"
    echo "4. Monitor deployments in the AWS Console"
}

# Run main function
main "$@"