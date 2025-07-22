#!/bin/bash

# Cost-Effective ECS Clusters with Spot Instances
# Deploy Script - Creates ECS cluster with Spot Instance capacity providers
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    warn "Deployment failed. Cleaning up resources..."
    ./destroy.sh --force 2>/dev/null || true
    error "Deployment failed and cleanup attempted"
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Default values
CLUSTER_NAME="cost-optimized-cluster"
SERVICE_NAME="spot-resilient-service"
CAPACITY_PROVIDER_NAME="spot-capacity-provider"
ASG_NAME="ecs-spot-asg"
REGION=""
DRY_RUN=false
SKIP_PREREQ=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-prereq)
            SKIP_PREREQ=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --cluster-name NAME      ECS cluster name (default: cost-optimized-cluster)"
            echo "  --service-name NAME      ECS service name (default: spot-resilient-service)"
            echo "  --region REGION          AWS region (default: from AWS CLI config)"
            echo "  --dry-run               Show what would be deployed without creating resources"
            echo "  --skip-prereq           Skip prerequisite checks"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

log "Starting deployment of Cost-Effective ECS Cluster with Spot Instances"

# Set region from CLI config if not provided
if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region)
    if [[ -z "$REGION" ]]; then
        error "AWS region not configured. Set region using 'aws configure' or --region parameter"
    fi
fi

log "Using AWS region: $REGION"

# Prerequisites check
if [[ "$SKIP_PREREQ" == "false" ]]; then
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
    fi
    
    # Check required permissions (basic test)
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity | grep -q "assumed-role"; then
        warn "Unable to verify IAM permissions. Proceeding with deployment..."
    fi
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        warn "jq not found. Some output formatting may be limited"
    fi
    
    log "Prerequisites check completed"
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be created"
    log "Would deploy:"
    log "  - ECS Cluster: $CLUSTER_NAME"
    log "  - ECS Service: $SERVICE_NAME"
    log "  - Capacity Provider: $CAPACITY_PROVIDER_NAME"
    log "  - Auto Scaling Group: $ASG_NAME"
    log "  - IAM Roles: ecsTaskExecutionRole, ecsInstanceRole"
    log "  - Security Group for ECS instances"
    log "  - Launch Template with mixed instance types"
    exit 0
fi

# Set environment variables
export AWS_REGION="$REGION"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME SERVICE_NAME CAPACITY_PROVIDER_NAME ASG_NAME

log "Using AWS Account ID: $AWS_ACCOUNT_ID"

# Check if resources already exist
log "Checking for existing resources..."

# Check if cluster exists
if aws ecs describe-clusters --clusters "$CLUSTER_NAME" &> /dev/null; then
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text)
    if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
        warn "ECS cluster '$CLUSTER_NAME' already exists and is active"
        read -p "Continue with existing cluster? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
fi

# Create IAM roles
log "Creating IAM roles..."

# Create ECS task execution role
if ! aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
    log "Creating ECS Task Execution Role..."
    cat > /tmp/ecs-task-execution-role-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role --role-name ecsTaskExecutionRole \
        --assume-role-policy-document file:///tmp/ecs-task-execution-role-policy.json \
        --tags Key=Environment,Value=production Key=CreatedBy,Value=cost-optimized-ecs-recipe

    aws iam attach-role-policy --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    log "✅ ECS Task Execution Role created"
else
    log "ECS Task Execution Role already exists"
fi

# Create ECS instance role
if ! aws iam get-role --role-name ecsInstanceRole &> /dev/null; then
    log "Creating ECS Instance Role..."
    cat > /tmp/ec2-role-policy.json << 'EOF'
{
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
}
EOF

    aws iam create-role --role-name ecsInstanceRole \
        --assume-role-policy-document file:///tmp/ec2-role-policy.json \
        --tags Key=Environment,Value=production Key=CreatedBy,Value=cost-optimized-ecs-recipe

    aws iam attach-role-policy --role-name ecsInstanceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

    log "✅ ECS Instance Role created"
else
    log "ECS Instance Role already exists"
fi

# Create instance profile
if ! aws iam get-instance-profile --instance-profile-name ecsInstanceProfile &> /dev/null; then
    log "Creating ECS Instance Profile..."
    aws iam create-instance-profile --instance-profile-name ecsInstanceProfile \
        --tags Key=Environment,Value=production Key=CreatedBy,Value=cost-optimized-ecs-recipe

    aws iam add-role-to-instance-profile \
        --instance-profile-name ecsInstanceProfile \
        --role-name ecsInstanceRole

    log "✅ ECS Instance Profile created"
else
    log "ECS Instance Profile already exists"
fi

# Get VPC and subnet information
log "Discovering VPC and subnet information..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
    error "No default VPC found. Please create a VPC or specify VPC ID"
fi

SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].SubnetId' --output text)

SUBNET_ARRAY=($SUBNET_IDS)
if [[ ${#SUBNET_ARRAY[@]} -lt 2 ]]; then
    error "At least 2 subnets required for high availability"
fi

SUBNET_1=${SUBNET_ARRAY[0]}
SUBNET_2=${SUBNET_ARRAY[1]}
SUBNET_3=${SUBNET_ARRAY[2]:-$SUBNET_1}

export VPC_ID SUBNET_1 SUBNET_2 SUBNET_3

log "Using VPC: $VPC_ID"
log "Using Subnets: $SUBNET_1, $SUBNET_2, $SUBNET_3"

# Create ECS cluster
log "Creating ECS cluster..."

if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" &> /dev/null; then
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" \
        --settings name=containerInsights,value=enabled \
        --tags key=Environment,value=production key=CostOptimized,value=true \
        key=CreatedBy,value=cost-optimized-ecs-recipe

    log "✅ ECS cluster created: $CLUSTER_NAME"
else
    log "ECS cluster already exists: $CLUSTER_NAME"
fi

# Get latest ECS-optimized AMI
log "Getting latest ECS-optimized AMI..."

ECS_AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended \
    --query 'Parameters[0].Value' --output text | \
    python3 -c "import sys, json; print(json.load(sys.stdin)['image_id'])" 2>/dev/null || \
    aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2/recommended \
    --query 'Parameter.Value' --output text | jq -r '.image_id' 2>/dev/null || \
    error "Unable to get ECS-optimized AMI ID")

export ECS_AMI_ID
log "Using ECS-optimized AMI: $ECS_AMI_ID"

# Create security group
log "Creating security group..."

SG_ID=$(aws ec2 create-security-group \
    --group-name ecs-spot-cluster-sg \
    --description "Security group for ECS spot cluster" \
    --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=ecs-spot-cluster-sg},{Key=Environment,Value=production}]' \
    --query 'GroupId' --output text 2>/dev/null || \
    aws ec2 describe-security-groups --group-names ecs-spot-cluster-sg \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || \
    error "Unable to create or find security group")

# Add ingress rules
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || \
    log "Port 80 ingress rule already exists"

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0 2>/dev/null || \
    log "Port 443 ingress rule already exists"

# Allow dynamic port range for ECS
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 32768-65535 --source-group "$SG_ID" 2>/dev/null || \
    log "Dynamic port range ingress rule already exists"

export SG_ID
log "✅ Security group created: $SG_ID"

# Create user data script
log "Creating launch template..."

cat > /tmp/user-data.sh << EOF
#!/bin/bash
echo ECS_CLUSTER=$CLUSTER_NAME >> /etc/ecs/ecs.config
echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config
echo ECS_CONTAINER_STOP_TIMEOUT=30s >> /etc/ecs/ecs.config
echo ECS_CONTAINER_START_TIMEOUT=10m >> /etc/ecs/ecs.config
EOF

USER_DATA=$(base64 -w 0 /tmp/user-data.sh)

# Create launch template
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
    --launch-template-name ecs-spot-template \
    --launch-template-data '{
        "ImageId": "'$ECS_AMI_ID'",
        "SecurityGroupIds": ["'$SG_ID'"],
        "IamInstanceProfile": {
            "Name": "ecsInstanceProfile"
        },
        "UserData": "'$USER_DATA'",
        "TagSpecifications": [{
            "ResourceType": "instance",
            "Tags": [
                {"Key": "Name", "Value": "ECS-Spot-Instance"},
                {"Key": "Environment", "Value": "production"},
                {"Key": "CreatedBy", "Value": "cost-optimized-ecs-recipe"}
            ]
        }]
    }' \
    --query 'LaunchTemplate.LaunchTemplateId' --output text 2>/dev/null || \
    aws ec2 describe-launch-templates --launch-template-names ecs-spot-template \
    --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null || \
    error "Unable to create or find launch template")

export LAUNCH_TEMPLATE_ID
log "✅ Launch template created: $LAUNCH_TEMPLATE_ID"

# Create mixed instance policy configuration
log "Creating Auto Scaling Group with mixed instance policy..."

cat > /tmp/mixed-instances-policy.json << EOF
{
  "LaunchTemplate": {
    "LaunchTemplateSpecification": {
      "LaunchTemplateId": "$LAUNCH_TEMPLATE_ID",
      "Version": "\$Latest"
    },
    "Overrides": [
      {
        "InstanceType": "m5.large",
        "SubnetId": "$SUBNET_1"
      },
      {
        "InstanceType": "m4.large",
        "SubnetId": "$SUBNET_1"
      },
      {
        "InstanceType": "c5.large",
        "SubnetId": "$SUBNET_2"
      },
      {
        "InstanceType": "c4.large",
        "SubnetId": "$SUBNET_2"
      },
      {
        "InstanceType": "m5.large",
        "SubnetId": "$SUBNET_3"
      },
      {
        "InstanceType": "r5.large",
        "SubnetId": "$SUBNET_3"
      }
    ]
  },
  "InstancesDistribution": {
    "OnDemandAllocationStrategy": "prioritized",
    "OnDemandBaseCapacity": 1,
    "OnDemandPercentageAboveBaseCapacity": 20,
    "SpotAllocationStrategy": "diversified",
    "SpotInstancePools": 4,
    "SpotMaxPrice": "0.10"
  }
}
EOF

# Create Auto Scaling Group
if ! aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" &> /dev/null; then
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --min-size 1 \
        --max-size 10 \
        --desired-capacity 3 \
        --vpc-zone-identifier "$SUBNET_1,$SUBNET_2,$SUBNET_3" \
        --mixed-instances-policy file:///tmp/mixed-instances-policy.json \
        --health-check-type ECS \
        --health-check-grace-period 300 \
        --tags "Key=Name,Value=ECS-Spot-ASG,PropagateAtLaunch=true,ResourceId=$ASG_NAME,ResourceType=auto-scaling-group" \
        "Key=Environment,Value=production,PropagateAtLaunch=true,ResourceId=$ASG_NAME,ResourceType=auto-scaling-group" \
        "Key=CreatedBy,Value=cost-optimized-ecs-recipe,PropagateAtLaunch=true,ResourceId=$ASG_NAME,ResourceType=auto-scaling-group"

    log "✅ Auto Scaling Group created: $ASG_NAME"
else
    log "Auto Scaling Group already exists: $ASG_NAME"
fi

# Wait for instances to be ready
log "Waiting for instances to join the cluster..."
sleep 30

# Create capacity provider
log "Creating ECS capacity provider..."

if ! aws ecs describe-capacity-providers --capacity-providers "$CAPACITY_PROVIDER_NAME" &> /dev/null; then
    aws ecs create-capacity-provider \
        --name "$CAPACITY_PROVIDER_NAME" \
        --auto-scaling-group-provider '{
            "autoScalingGroupArn": "arn:aws:autoscaling:'$AWS_REGION':'$AWS_ACCOUNT_ID':autoScalingGroup:*:autoScalingGroupName/'$ASG_NAME'",
            "managedScaling": {
                "status": "ENABLED",
                "targetCapacity": 80,
                "minimumScalingStepSize": 1,
                "maximumScalingStepSize": 3
            },
            "managedTerminationProtection": "ENABLED"
        }' \
        --tags key=Environment,value=production key=CreatedBy,value=cost-optimized-ecs-recipe

    log "✅ Capacity provider created: $CAPACITY_PROVIDER_NAME"
else
    log "Capacity provider already exists: $CAPACITY_PROVIDER_NAME"
fi

# Associate capacity provider with cluster
log "Associating capacity provider with cluster..."

aws ecs put-cluster-capacity-providers \
    --cluster "$CLUSTER_NAME" \
    --capacity-providers "$CAPACITY_PROVIDER_NAME" \
    --default-capacity-provider-strategy '[{
        "capacityProvider": "'$CAPACITY_PROVIDER_NAME'",
        "weight": 1,
        "base": 0
    }]'

log "✅ Capacity provider associated with cluster"

# Create task definition
log "Creating task definition..."

cat > /tmp/task-definition.json << EOF
{
  "family": "spot-resilient-app",
  "cpu": "256",
  "memory": "512",
  "networkMode": "bridge",
  "requiresCompatibilities": ["EC2"],
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "web-server",
      "image": "public.ecr.aws/docker/library/nginx:latest",
      "cpu": 256,
      "memory": 512,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 0,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/spot-resilient-app",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-definition.json \
    --query 'taskDefinition.taskDefinitionArn' --output text)

export TASK_DEFINITION_ARN
log "✅ Task definition registered: $TASK_DEFINITION_ARN"

# Create ECS service
log "Creating ECS service..."

if ! aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" &> /dev/null; then
    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition spot-resilient-app \
        --desired-count 6 \
        --capacity-provider-strategy '[{
            "capacityProvider": "'$CAPACITY_PROVIDER_NAME'",
            "weight": 1,
            "base": 2
        }]' \
        --deployment-configuration '{
            "maximumPercent": 200,
            "minimumHealthyPercent": 50,
            "deploymentCircuitBreaker": {
                "enable": true,
                "rollback": true
            }
        }' \
        --tags key=Environment,value=production key=CostOptimized,value=true \
        key=CreatedBy,value=cost-optimized-ecs-recipe

    log "✅ ECS service created: $SERVICE_NAME"
else
    log "ECS service already exists: $SERVICE_NAME"
fi

# Set up service auto scaling
log "Setting up service auto scaling..."

aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/$CLUSTER_NAME/$SERVICE_NAME \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 20 2>/dev/null || \
    log "Scalable target already registered"

aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id service/$CLUSTER_NAME/$SERVICE_NAME \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name cpu-target-tracking \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 60.0,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
        },
        "ScaleOutCooldown": 300,
        "ScaleInCooldown": 300
    }' 2>/dev/null || \
    log "Scaling policy already exists"

log "✅ Service auto scaling configured"

# Wait for service to stabilize
log "Waiting for service to stabilize..."
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" || \
    warn "Service did not stabilize within timeout, but deployment continues"

# Clean up temporary files
rm -f /tmp/ecs-task-execution-role-policy.json
rm -f /tmp/ec2-role-policy.json
rm -f /tmp/mixed-instances-policy.json
rm -f /tmp/task-definition.json
rm -f /tmp/user-data.sh

# Display deployment summary
log "Deployment completed successfully!"
echo
echo "=== DEPLOYMENT SUMMARY ==="
echo "Cluster Name: $CLUSTER_NAME"
echo "Service Name: $SERVICE_NAME"
echo "Capacity Provider: $CAPACITY_PROVIDER_NAME"
echo "Auto Scaling Group: $ASG_NAME"
echo "AWS Region: $AWS_REGION"
echo "VPC ID: $VPC_ID"
echo "Security Group: $SG_ID"
echo "Launch Template: $LAUNCH_TEMPLATE_ID"
echo

log "Verifying deployment..."

# Check cluster status
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" \
    --query 'clusters[0].status' --output text)
echo "Cluster Status: $CLUSTER_STATUS"

# Check service status
SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --query 'services[0].[status,runningCount,desiredCount]' --output text)
echo "Service Status: $SERVICE_STATUS"

# Check capacity provider status
CP_STATUS=$(aws ecs describe-capacity-providers \
    --capacity-providers "$CAPACITY_PROVIDER_NAME" \
    --query 'capacityProviders[0].status' --output text)
echo "Capacity Provider Status: $CP_STATUS"

# Show cost optimization info
echo
echo "=== COST OPTIMIZATION INFO ==="
echo "• Mixed instance policy: 20% On-Demand, 80% Spot Instances"
echo "• Expected cost savings: 50-70% compared to On-Demand only"
echo "• Spot instances across multiple AZs for high availability"
echo "• Managed instance draining for graceful Spot interruption handling"
echo
echo "Monitor your costs using AWS Cost Explorer and adjust the On-Demand percentage"
echo "based on your availability requirements."
echo
echo "To clean up resources, run: ./destroy.sh"
echo

log "Deployment completed successfully! 🎉"