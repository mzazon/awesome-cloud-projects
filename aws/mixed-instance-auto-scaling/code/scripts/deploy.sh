#!/bin/bash

# =============================================================================
# Deploy Script for Mixed Instance Auto Scaling Groups
# 
# This script deploys an Auto Scaling Group with mixed instance types and 
# Spot Instances for cost optimization while maintaining high availability.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for EC2, Auto Scaling, and CloudWatch
# - VPC with multiple subnets across different Availability Zones
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version (should be v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! $AWS_CLI_VERSION =~ ^2\. ]]; then
        warn "AWS CLI v1 detected. AWS CLI v2 is recommended."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions by testing basic API calls
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error "Insufficient EC2 permissions. Check your IAM credentials."
        exit 1
    fi
    
    if ! aws autoscaling describe-auto-scaling-groups --max-items 1 &> /dev/null; then
        error "Insufficient Auto Scaling permissions. Check your IAM credentials."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Set AWS_REGION environment variable or configure default region."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export ASG_NAME="mixed-instances-asg-${RANDOM_SUFFIX}"
    export LAUNCH_TEMPLATE_NAME="mixed-instances-template-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="mixed-instances-sg-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="EC2InstanceRole-${RANDOM_SUFFIX}"
    export ALB_NAME="mixed-instances-alb-${RANDOM_SUFFIX}"
    export TARGET_GROUP_NAME="mixed-instances-tg-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="autoscaling-notifications-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnets
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
    
    if [[ "$VPC_ID" == "None" || "$VPC_ID" == "null" ]]; then
        # Try to get any VPC if no default VPC exists
        export VPC_ID=$(aws ec2 describe-vpcs \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
        
        if [[ "$VPC_ID" == "None" || "$VPC_ID" == "null" ]]; then
            error "No VPC found. Please create a VPC first."
            exit 1
        fi
        warn "No default VPC found. Using VPC: $VPC_ID"
    fi
    
    # Get subnets in different AZs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',' 2>/dev/null || echo "")
    
    if [[ -z "$SUBNET_IDS" ]]; then
        error "No subnets found in VPC $VPC_ID"
        exit 1
    fi
    
    # Ensure we have at least 2 subnets for high availability
    SUBNET_COUNT=$(echo $SUBNET_IDS | tr ',' '\n' | wc -l)
    if [[ $SUBNET_COUNT -lt 2 ]]; then
        warn "Only $SUBNET_COUNT subnet(s) found. High availability requires multiple subnets across different AZs."
    fi
    
    log "Environment setup completed"
    info "VPC ID: $VPC_ID"
    info "Subnet IDs: $SUBNET_IDS"
    info "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create security group
create_security_group() {
    log "Creating security group..."
    
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name ${SECURITY_GROUP_NAME} \
        --description "Security group for mixed instances Auto Scaling group" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SECURITY_GROUP_NAME}},{Key=Environment,Value=Demo},{Key=Project,Value=MixedInstancesASG}]" \
        --query 'GroupId' --output text)
    
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        error "Failed to create security group"
        exit 1
    fi
    
    export SECURITY_GROUP_ID
    
    # Add security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HTTP-Access}]" || true
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp --port 443 --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HTTPS-Access}]" || true
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SSH-Access}]" || true
    
    log "Security group created: $SECURITY_GROUP_ID"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Create trust policy
    cat > /tmp/ec2-trust-policy.json << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
        --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG || {
        warn "IAM role might already exist or insufficient permissions"
    }
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || true
    
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore || true
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name ${IAM_ROLE_NAME} \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG || true
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name ${IAM_ROLE_NAME} \
        --role-name ${IAM_ROLE_NAME} || true
    
    # Wait for instance profile to be available
    sleep 10
    
    log "IAM role created and configured: $IAM_ROLE_NAME"
    
    # Clean up temporary files
    rm -f /tmp/ec2-trust-policy.json
}

# Function to create user data script
create_user_data() {
    log "Creating user data script..."
    
    cat > /tmp/user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
SPOT_TERMINATION=$(curl -s http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null || echo "On-Demand")

# Create web page
cat > /var/www/html/index.html << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Mixed Instance Auto Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .info { background: #e8f4fd; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .spot { color: #28a745; font-weight: bold; }
        .ondemand { color: #007bff; font-weight: bold; }
        .header { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        ul { background: #f8f9fa; padding: 20px; border-radius: 5px; }
        .refresh { margin-top: 20px; }
    </style>
    <script>
        function refreshPage() {
            location.reload();
        }
        // Auto-refresh every 30 seconds
        setTimeout(refreshPage, 30000);
    </script>
</head>
<body>
    <div class="container">
        <h1 class="header">Mixed Instance Auto Scaling Demo</h1>
        <div class="info">
            <h2>Instance Information</h2>
            <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
            <p><strong>Instance Type:</strong> $INSTANCE_TYPE</p>
            <p><strong>Availability Zone:</strong> $AZ</p>
            <p><strong>Purchase Type:</strong> 
                <span class="$([ "$SPOT_TERMINATION" = "On-Demand" ] && echo "ondemand" || echo "spot")">
                    $([ "$SPOT_TERMINATION" = "On-Demand" ] && echo "On-Demand Instance" || echo "Spot Instance")
                </span>
            </p>
            <p><strong>Last Updated:</strong> $(date)</p>
        </div>
        
        <h2>Auto Scaling Group Benefits</h2>
        <ul>
            <li><strong>Cost Optimization:</strong> Up to 90% savings with Spot Instances</li>
            <li><strong>High Availability:</strong> Distribution across multiple Availability Zones</li>
            <li><strong>Automatic Scaling:</strong> Responds to demand changes automatically</li>
            <li><strong>Instance Diversification:</strong> Multiple instance types for resilience</li>
            <li><strong>Capacity Rebalancing:</strong> Proactive Spot interruption handling</li>
        </ul>
        
        <div class="refresh">
            <button onclick="refreshPage()" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer;">
                Refresh Instance Info
            </button>
        </div>
    </div>
</body>
</html>
HTML

# Start web server
systemctl start httpd
systemctl enable httpd

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << JSON
{
    "metrics": {
        "namespace": "AutoScaling/MixedInstances",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
JSON

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
EOF
    
    # Encode user data as base64
    USER_DATA_B64=$(base64 -w 0 /tmp/user-data.sh)
    export USER_DATA_B64
    
    log "User data script created and encoded"
    
    # Clean up temporary files
    rm -f /tmp/user-data.sh
}

# Function to create launch template
create_launch_template() {
    log "Creating launch template..."
    
    # Get latest Amazon Linux 2 AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ -z "$AMI_ID" || "$AMI_ID" == "null" ]]; then
        error "Failed to find Amazon Linux 2 AMI"
        exit 1
    fi
    
    info "Using AMI: $AMI_ID"
    
    # Create launch template configuration
    cat > /tmp/launch-template.json << EOF
{
    "LaunchTemplateName": "${LAUNCH_TEMPLATE_NAME}",
    "LaunchTemplateData": {
        "ImageId": "${AMI_ID}",
        "InstanceType": "m5.large",
        "SecurityGroupIds": ["${SECURITY_GROUP_ID}"],
        "IamInstanceProfile": {
            "Name": "${IAM_ROLE_NAME}"
        },
        "UserData": "${USER_DATA_B64}",
        "TagSpecifications": [
            {
                "ResourceType": "instance",
                "Tags": [
                    {
                        "Key": "Name",
                        "Value": "MixedInstancesASG-Instance"
                    },
                    {
                        "Key": "Environment",
                        "Value": "Demo"
                    },
                    {
                        "Key": "AutoScalingGroup",
                        "Value": "${ASG_NAME}"
                    },
                    {
                        "Key": "Project",
                        "Value": "MixedInstancesDemo"
                    }
                ]
            }
        ],
        "MetadataOptions": {
            "HttpTokens": "required",
            "HttpPutResponseHopLimit": 2,
            "HttpEndpoint": "enabled"
        },
        "Monitoring": {
            "Enabled": true
        }
    }
}
EOF
    
    # Create launch template
    aws ec2 create-launch-template --cli-input-json file:///tmp/launch-template.json
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create launch template"
        exit 1
    fi
    
    log "Launch template created: $LAUNCH_TEMPLATE_NAME"
    
    # Clean up temporary files
    rm -f /tmp/launch-template.json
}

# Function to create Auto Scaling group
create_auto_scaling_group() {
    log "Creating Auto Scaling group with mixed instance policy..."
    
    # Create Auto Scaling group configuration
    cat > /tmp/asg-mixed-instances.json << EOF
{
    "AutoScalingGroupName": "${ASG_NAME}",
    "MinSize": 2,
    "MaxSize": 10,
    "DesiredCapacity": 4,
    "DefaultCooldown": 300,
    "HealthCheckType": "EC2",
    "HealthCheckGracePeriod": 300,
    "VPCZoneIdentifier": "${SUBNET_IDS}",
    "MixedInstancesPolicy": {
        "LaunchTemplate": {
            "LaunchTemplateSpecification": {
                "LaunchTemplateName": "${LAUNCH_TEMPLATE_NAME}",
                "Version": "\$Latest"
            },
            "Overrides": [
                {
                    "InstanceType": "m5.large",
                    "WeightedCapacity": "1"
                },
                {
                    "InstanceType": "m5.xlarge",
                    "WeightedCapacity": "2"
                },
                {
                    "InstanceType": "c5.large",
                    "WeightedCapacity": "1"
                },
                {
                    "InstanceType": "c5.xlarge",
                    "WeightedCapacity": "2"
                },
                {
                    "InstanceType": "r5.large",
                    "WeightedCapacity": "1"
                },
                {
                    "InstanceType": "r5.xlarge",
                    "WeightedCapacity": "2"
                }
            ]
        },
        "InstancesDistribution": {
            "OnDemandAllocationStrategy": "prioritized",
            "OnDemandBaseCapacity": 1,
            "OnDemandPercentageAboveBaseCapacity": 20,
            "SpotAllocationStrategy": "diversified",
            "SpotInstancePools": 4,
            "SpotMaxPrice": ""
        }
    },
    "Tags": [
        {
            "Key": "Name",
            "Value": "${ASG_NAME}",
            "PropagateAtLaunch": false,
            "ResourceId": "${ASG_NAME}",
            "ResourceType": "auto-scaling-group"
        },
        {
            "Key": "Environment",
            "Value": "Demo",
            "PropagateAtLaunch": true,
            "ResourceId": "${ASG_NAME}",
            "ResourceType": "auto-scaling-group"
        },
        {
            "Key": "Project",
            "Value": "MixedInstancesDemo",
            "PropagateAtLaunch": true,
            "ResourceId": "${ASG_NAME}",
            "ResourceType": "auto-scaling-group"
        }
    ]
}
EOF
    
    # Create Auto Scaling group
    aws autoscaling create-auto-scaling-group --cli-input-json file:///tmp/asg-mixed-instances.json
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create Auto Scaling group"
        exit 1
    fi
    
    # Enable capacity rebalancing
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name ${ASG_NAME} \
        --capacity-rebalance
    
    log "Auto Scaling group created with mixed instance policy: $ASG_NAME"
    info "Configuration: Min=2, Max=10, Desired=4"
    info "On-Demand base capacity: 1 instance"
    info "Spot allocation: diversified across 4 pools"
    
    # Clean up temporary files
    rm -f /tmp/asg-mixed-instances.json
}

# Function to create scaling policies
create_scaling_policies() {
    log "Creating CloudWatch scaling policies..."
    
    # Create CPU-based scaling policy
    SCALE_UP_POLICY_ARN=$(aws autoscaling put-scaling-policy \
        --auto-scaling-group-name ${ASG_NAME} \
        --policy-name "${ASG_NAME}-scale-up" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ASGAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --query 'PolicyARN' --output text)
    
    if [[ -z "$SCALE_UP_POLICY_ARN" ]]; then
        warn "Failed to create CPU scaling policy"
    else
        log "Created CPU-based scaling policy"
    fi
    
    # Create network-based scaling policy
    SCALE_NETWORK_POLICY_ARN=$(aws autoscaling put-scaling-policy \
        --auto-scaling-group-name ${ASG_NAME} \
        --policy-name "${ASG_NAME}-scale-network" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration '{
            "TargetValue": 1000000.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ASGAverageNetworkIn"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --query 'PolicyARN' --output text 2>/dev/null || echo "")
    
    if [[ -n "$SCALE_NETWORK_POLICY_ARN" ]]; then
        log "Created network-based scaling policy"
    fi
    
    log "Scaling policies configured for multi-metric optimization"
}

# Function to create SNS notifications
create_sns_notifications() {
    log "Setting up SNS notifications for scaling events..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG \
        --query 'TopicArn' --output text)
    
    export SNS_TOPIC_ARN
    
    # Configure Auto Scaling notifications
    aws autoscaling put-notification-configuration \
        --auto-scaling-group-name ${ASG_NAME} \
        --topic-arn ${SNS_TOPIC_ARN} \
        --notification-types \
            "autoscaling:EC2_INSTANCE_LAUNCH" \
            "autoscaling:EC2_INSTANCE_LAUNCH_ERROR" \
            "autoscaling:EC2_INSTANCE_TERMINATE" \
            "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
    
    log "SNS notifications configured"
    info "Topic ARN: $SNS_TOPIC_ARN"
    info "Subscribe to this topic to receive scaling notifications"
}

# Function to create Application Load Balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Create Application Load Balancer
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${ALB_NAME}" \
        --subnets $(echo ${SUBNET_IDS} | tr ',' ' ') \
        --security-groups ${SECURITY_GROUP_ID} \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    if [[ -z "$ALB_ARN" ]]; then
        error "Failed to create Application Load Balancer"
        exit 1
    fi
    
    export ALB_ARN
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    export ALB_DNS
    
    # Create target group
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${TARGET_GROUP_NAME}" \
        --protocol HTTP \
        --port 80 \
        --vpc-id ${VPC_ID} \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    if [[ -z "$TARGET_GROUP_ARN" ]]; then
        error "Failed to create target group"
        exit 1
    fi
    
    export TARGET_GROUP_ARN
    
    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} \
        --tags Key=Environment,Value=Demo Key=Project,Value=MixedInstancesASG
    
    # Attach Auto Scaling group to target group
    aws autoscaling attach-load-balancer-target-groups \
        --auto-scaling-group-name ${ASG_NAME} \
        --target-group-arns ${TARGET_GROUP_ARN}
    
    # Update health check type to use ELB
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name ${ASG_NAME} \
        --health-check-type ELB \
        --health-check-grace-period 300
    
    log "Application Load Balancer created and configured"
    info "ALB DNS: $ALB_DNS"
    info "Your application will be available at: http://$ALB_DNS"
}

# Function to save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/mixed-instances-deployment.json << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "auto_scaling_group": "${ASG_NAME}",
        "launch_template": "${LAUNCH_TEMPLATE_NAME}",
        "security_group": "${SECURITY_GROUP_ID}",
        "iam_role": "${IAM_ROLE_NAME}",
        "load_balancer": "${ALB_ARN}",
        "target_group": "${TARGET_GROUP_ARN}",
        "sns_topic": "${SNS_TOPIC_ARN}",
        "vpc_id": "${VPC_ID}",
        "subnets": "${SUBNET_IDS}"
    },
    "endpoints": {
        "application_url": "http://${ALB_DNS}"
    },
    "deployment_time": "$(date -Iseconds)"
}
EOF
    
    # Save to current directory as well for easy cleanup
    cp /tmp/mixed-instances-deployment.json ./mixed-instances-deployment-${RANDOM_SUFFIX}.json
    
    log "Deployment information saved to mixed-instances-deployment-${RANDOM_SUFFIX}.json"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for instances to launch
    info "Waiting for instances to launch (this may take a few minutes)..."
    sleep 60
    
    # Check Auto Scaling group status
    ASG_STATUS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${ASG_NAME} \
        --query 'AutoScalingGroups[0].[AutoScalingGroupName,DesiredCapacity,Instances[].InstanceId]' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [[ "$ASG_STATUS" == "ERROR" ]]; then
        warn "Could not verify Auto Scaling group status"
    else
        log "Auto Scaling group is active with instances"
    fi
    
    # Check load balancer targets
    info "Checking load balancer target health..."
    sleep 30
    
    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn ${TARGET_GROUP_ARN} \
        --query 'TargetHealthDescriptions[*].TargetHealth.State' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [[ "$TARGET_HEALTH" == "ERROR" ]]; then
        warn "Could not verify target health"
    else
        info "Target health status: $TARGET_HEALTH"
    fi
    
    log "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "================================================================================================"
    log "Mixed Instance Auto Scaling Group Deployment Completed Successfully!"
    echo "================================================================================================"
    echo ""
    info "Deployment Summary:"
    echo "  • Auto Scaling Group: $ASG_NAME"
    echo "  • Launch Template: $LAUNCH_TEMPLATE_NAME"
    echo "  • Security Group: $SECURITY_GROUP_ID"
    echo "  • IAM Role: $IAM_ROLE_NAME"
    echo "  • Load Balancer DNS: $ALB_DNS"
    echo "  • SNS Topic: $SNS_TOPIC_ARN"
    echo ""
    info "Configuration Highlights:"
    echo "  • Instance Types: m5.large, m5.xlarge, c5.large, c5.xlarge, r5.large, r5.xlarge"
    echo "  • Purchase Options: 20% On-Demand + 80% Spot Instances"
    echo "  • Capacity: Min=2, Max=10, Desired=4"
    echo "  • Auto Scaling: CPU and Network-based policies"
    echo "  • Health Checks: ELB health checks with 5-minute grace period"
    echo "  • Capacity Rebalancing: Enabled for Spot interruption handling"
    echo ""
    info "Access Your Application:"
    echo "  🌐 Web Application: http://$ALB_DNS"
    echo "  📊 CloudWatch Metrics: Custom namespace 'AutoScaling/MixedInstances'"
    echo "  🔔 Notifications: Subscribe to SNS topic for scaling events"
    echo ""
    info "Cost Optimization:"
    echo "  • Expected savings: 60-90% vs On-Demand only"
    echo "  • Diversified Spot allocation reduces interruption risk"
    echo "  • Automatic instance type selection based on availability"
    echo ""
    info "Management:"
    echo "  • Deployment info saved: mixed-instances-deployment-${RANDOM_SUFFIX}.json"
    echo "  • Use destroy.sh to clean up all resources"
    echo "  • Monitor Auto Scaling activities in AWS Console"
    echo ""
    warn "Important Notes:"
    echo "  • Spot Instance prices vary by region and time"
    echo "  • Monitor costs using AWS Cost Explorer"
    echo "  • Set up billing alerts for cost control"
    echo "  • Consider reserved instances for base On-Demand capacity"
    echo ""
    echo "================================================================================================"
    log "Deployment completed at $(date)"
    echo "================================================================================================"
}

# Main deployment function
main() {
    log "Starting Mixed Instance Auto Scaling Group deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_security_group
    create_iam_role
    create_user_data
    create_launch_template
    create_auto_scaling_group
    create_scaling_policies
    create_sns_notifications
    create_load_balancer
    save_deployment_info
    verify_deployment
    display_summary
    
    log "Deployment script completed successfully!"
}

# Cleanup function for script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may have been created."
    error "Check the AWS Console and run destroy.sh to clean up any resources."
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup_on_error INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi