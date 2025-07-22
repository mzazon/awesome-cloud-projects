#!/bin/bash

#
# Deploy Script for Auto Scaling with Application Load Balancers and Target Groups
# This script implements the complete infrastructure for auto-scaling web application
# with load balancing, health checks, and CloudWatch monitoring
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${ASG_NAME:-}" ]]; then
        log_warn "Attempting cleanup of Auto Scaling Group: $ASG_NAME"
        aws autoscaling update-auto-scaling-group \
            --auto-scaling-group-name "$ASG_NAME" \
            --min-size 0 \
            --desired-capacity 0 || true
        
        sleep 30
        
        aws autoscaling delete-auto-scaling-group \
            --auto-scaling-group-name "$ASG_NAME" \
            --force-delete || true
    fi
    
    if [[ -n "${ALB_ARN:-}" ]]; then
        log_warn "Attempting cleanup of Application Load Balancer"
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" || true
    fi
    
    if [[ -n "${TG_ARN:-}" ]]; then
        log_warn "Attempting cleanup of Target Group"
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN" || true
    fi
    
    if [[ -n "${LT_NAME:-}" ]]; then
        log_warn "Attempting cleanup of Launch Template"
        aws ec2 delete-launch-template --launch-template-name "$LT_NAME" || true
    fi
    
    if [[ -n "${SG_ID:-}" ]]; then
        log_warn "Attempting cleanup of Security Group"
        aws ec2 delete-security-group --group-id "$SG_ID" || true
    fi
    
    # Clean up temporary files
    rm -f user-data.sh cpu-target-tracking.json alb-target-tracking.json || true
    
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required permissions
    log_info "Validating AWS permissions..."
    local test_operations=(
        "aws ec2 describe-vpcs --max-items 1"
        "aws autoscaling describe-auto-scaling-groups --max-items 1"
        "aws elbv2 describe-load-balancers --max-items 1"
        "aws cloudwatch list-metrics --max-items 1"
    )
    
    for operation in "${test_operations[@]}"; do
        if ! eval "$operation" &> /dev/null; then
            log_error "Missing permissions for: $operation"
            exit 1
        fi
    done
    
    log_info "✅ Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 3)
    
    export ASG_NAME="web-app-asg-${RANDOM_SUFFIX}"
    export ALB_NAME="web-app-alb-${RANDOM_SUFFIX}"
    export TG_NAME="web-app-targets-${RANDOM_SUFFIX}"
    export LT_NAME="web-app-template-${RANDOM_SUFFIX}"
    export SG_NAME="web-app-sg-${RANDOM_SUFFIX}"
    
    # Get VPC and subnet information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        log_error "No default VPC found. Please create a VPC with public subnets first."
        exit 1
    fi
    
    # Get subnets across multiple AZs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
                  "Name=default-for-az,Values=true" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    if [[ -z "$SUBNET_IDS" ]]; then
        log_error "No suitable subnets found in VPC $VPC_ID"
        exit 1
    fi
    
    log_info "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  VPC ID: $VPC_ID"
    log_info "  Subnet IDs: $SUBNET_IDS"
    log_info "  Resource Suffix: $RANDOM_SUFFIX"
}

# Create security group
create_security_group() {
    log_info "Creating security group for web application..."
    
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for auto-scaled web application" \
        --vpc-id "$VPC_ID" \
        --query GroupId --output text)
    
    # Allow HTTP traffic
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    # Allow HTTPS traffic
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Allow SSH access (for troubleshooting)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    export SG_ID
    log_info "✅ Created security group: $SG_ID"
}

# Create launch template
create_launch_template() {
    log_info "Creating launch template for Auto Scaling Group..."
    
    # Create user data script
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create a simple web page with instance metadata
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Auto Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .metric { background: #f0f0f0; padding: 20px; margin: 10px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Auto Scaling Demo Application</h1>
        <div class="metric">
            <h3>Instance Information</h3>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
            <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
            <p><strong>Local IP:</strong> <span id="local-ip">Loading...</span></p>
            <p><strong>Server Time:</strong> <span id="server-time"></span></p>
        </div>
        <div class="metric">
            <h3>Load Test</h3>
            <button onclick="generateLoad()">Generate CPU Load (30s)</button>
            <p><strong>Status:</strong> <span id="load-status">Ready</span></p>
        </div>
    </div>
    
    <script>
        // Fetch instance metadata
        async function fetchMetadata() {
            try {
                const token = await fetch('http://169.254.169.254/latest/api/token', {
                    method: 'PUT',
                    headers: {'X-aws-ec2-metadata-token-ttl-seconds': '21600'}
                }).then(r => r.text());
                
                const headers = {'X-aws-ec2-metadata-token': token};
                
                const instanceId = await fetch('http://169.254.169.254/latest/meta-data/instance-id', {headers}).then(r => r.text());
                const az = await fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone', {headers}).then(r => r.text());
                const instanceType = await fetch('http://169.254.169.254/latest/meta-data/instance-type', {headers}).then(r => r.text());
                const localIp = await fetch('http://169.254.169.254/latest/meta-data/local-ipv4', {headers}).then(r => r.text());
                
                document.getElementById('instance-id').textContent = instanceId;
                document.getElementById('az').textContent = az;
                document.getElementById('instance-type').textContent = instanceType;
                document.getElementById('local-ip').textContent = localIp;
            } catch (error) {
                console.error('Error fetching metadata:', error);
            }
        }
        
        // Generate CPU load for testing auto scaling
        function generateLoad() {
            document.getElementById('load-status').textContent = 'Generating high CPU load...';
            
            // Start multiple CPU-intensive tasks
            const workers = [];
            for (let i = 0; i < 4; i++) {
                workers.push(new Worker('data:application/javascript,let start=Date.now();while(Date.now()-start<30000){Math.random();}'));
            }
            
            setTimeout(() => {
                workers.forEach(worker => worker.terminate());
                document.getElementById('load-status').textContent = 'Load test completed';
            }, 30000);
        }
        
        // Update server time every second
        function updateTime() {
            document.getElementById('server-time').textContent = new Date().toLocaleString();
        }
        
        // Initialize
        fetchMetadata();
        updateTime();
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
HTML
EOF
    
    # Base64 encode user data
    USER_DATA=$(base64 -w 0 user-data.sh)
    
    # Get latest Amazon Linux 2 AMI
    LATEST_AMI=$(aws ec2 describe-images \
        --owners amazon \
        --filters 'Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2' \
                 'Name=state,Values=available' \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Create launch template
    aws ec2 create-launch-template \
        --launch-template-name "$LT_NAME" \
        --launch-template-data "{
            \"ImageId\": \"$LATEST_AMI\",
            \"InstanceType\": \"t3.micro\",
            \"SecurityGroupIds\": [\"$SG_ID\"],
            \"UserData\": \"$USER_DATA\",
            \"TagSpecifications\": [{
                \"ResourceType\": \"instance\",
                \"Tags\": [
                    {\"Key\": \"Name\", \"Value\": \"AutoScaling-WebServer\"},
                    {\"Key\": \"Environment\", \"Value\": \"demo\"},
                    {\"Key\": \"Project\", \"Value\": \"auto-scaling-recipe\"}
                ]
            }],
            \"MetadataOptions\": {
                \"HttpTokens\": \"required\",
                \"HttpPutResponseHopLimit\": 2
            }
        }" > /dev/null
    
    log_info "✅ Created launch template: $LT_NAME"
}

# Create Application Load Balancer
create_load_balancer() {
    log_info "Creating Application Load Balancer..."
    
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets $(echo "$SUBNET_IDS" | tr ',' ' ') \
        --security-groups "$SG_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="$ALB_NAME" \
               Key=Environment,Value=demo \
               Key=Project,Value=auto-scaling-recipe \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get the DNS name for testing
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    export ALB_ARN
    export ALB_DNS
    log_info "✅ Created Application Load Balancer: $ALB_DNS"
}

# Create target group
create_target_group() {
    log_info "Creating target group with health checks..."
    
    TG_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$VPC_ID" \
        --target-type instance \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --matcher HttpCode=200 \
        --tags Key=Name,Value="$TG_NAME" \
               Key=Environment,Value=demo \
               Key=Project,Value=auto-scaling-recipe \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Configure target group attributes
    aws elbv2 modify-target-group-attributes \
        --target-group-arn "$TG_ARN" \
        --attributes \
            Key=deregistration_delay.timeout_seconds,Value=30 \
            Key=stickiness.enabled,Value=false
    
    export TG_ARN
    log_info "✅ Created target group: $TG_ARN"
}

# Create load balancer listener
create_listener() {
    log_info "Creating load balancer listener..."
    
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
        --tags Key=Name,Value="${ALB_NAME}-listener" \
               Key=Environment,Value=demo \
               Key=Project,Value=auto-scaling-recipe > /dev/null
    
    log_info "✅ Created load balancer listener"
}

# Create Auto Scaling Group
create_auto_scaling_group() {
    log_info "Creating Auto Scaling Group with target group integration..."
    
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --launch-template "LaunchTemplateName=$LT_NAME,Version=\$Latest" \
        --min-size 2 \
        --max-size 8 \
        --desired-capacity 2 \
        --target-group-arns "$TG_ARN" \
        --health-check-type ELB \
        --health-check-grace-period 300 \
        --vpc-zone-identifier "$SUBNET_IDS" \
        --default-cooldown 300 \
        --tags \
            Key=Name,Value=AutoScaling-Demo,PropagateAtLaunch=true \
            Key=Environment,Value=demo,PropagateAtLaunch=true \
            Key=Project,Value=auto-scaling-recipe,PropagateAtLaunch=true
    
    log_info "✅ Created Auto Scaling Group: $ASG_NAME"
    
    # Wait for instances to launch
    log_info "Waiting for instances to launch and become healthy..."
    sleep 60
}

# Configure scaling policies
configure_scaling_policies() {
    log_info "Configuring target tracking scaling policies..."
    
    # Create CPU utilization target tracking policy
    cat > cpu-target-tracking.json << EOF
{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
        "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleOutCooldown": 300,
    "ScaleInCooldown": 300,
    "DisableScaleIn": false
}
EOF
    
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$ASG_NAME" \
        --policy-name "cpu-target-tracking-policy" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration file://cpu-target-tracking.json > /dev/null
    
    # Create ALB request count target tracking policy
    RESOURCE_LABEL=$(aws elbv2 describe-target-groups \
        --target-group-arns "$TG_ARN" \
        --query 'TargetGroups[0].TargetGroupArn' --output text | \
        sed 's/.*loadbalancer\///g' | sed 's/targetgroup/targetgroup/g')
    
    cat > alb-target-tracking.json << EOF
{
    "TargetValue": 1000.0,
    "PredefinedMetricSpecification": {
        "PredefinedMetricType": "ALBRequestCountPerTarget",
        "ResourceLabel": "$RESOURCE_LABEL"
    },
    "ScaleOutCooldown": 300,
    "ScaleInCooldown": 300,
    "DisableScaleIn": false
}
EOF
    
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "$ASG_NAME" \
        --policy-name "alb-request-count-policy" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration file://alb-target-tracking.json > /dev/null
    
    log_info "✅ Created target tracking scaling policies"
}

# Configure scheduled scaling
configure_scheduled_scaling() {
    log_info "Configuring scheduled scaling actions..."
    
    # Scale up during business hours (9 AM UTC)
    aws autoscaling put-scheduled-update-group-action \
        --auto-scaling-group-name "$ASG_NAME" \
        --scheduled-action-name "scale-up-business-hours" \
        --recurrence "0 9 * * MON-FRI" \
        --min-size 3 \
        --max-size 10 \
        --desired-capacity 4
    
    # Scale down after business hours (6 PM UTC)
    aws autoscaling put-scheduled-update-group-action \
        --auto-scaling-group-name "$ASG_NAME" \
        --scheduled-action-name "scale-down-after-hours" \
        --recurrence "0 18 * * MON-FRI" \
        --min-size 1 \
        --max-size 8 \
        --desired-capacity 2
    
    log_info "✅ Created scheduled scaling actions"
}

# Configure CloudWatch monitoring
configure_monitoring() {
    log_info "Configuring CloudWatch monitoring and alarms..."
    
    # Enable detailed monitoring for Auto Scaling Group
    aws autoscaling enable-metrics-collection \
        --auto-scaling-group-name "$ASG_NAME" \
        --granularity "1Minute" \
        --metrics "GroupMinSize" "GroupMaxSize" "GroupDesiredCapacity" \
                  "GroupInServiceInstances" "GroupPendingInstances" \
                  "GroupStandbyInstances" "GroupTerminatingInstances" \
                  "GroupTotalInstances"
    
    # Create CloudWatch alarm for high CPU utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ASG_NAME}-high-cpu" \
        --alarm-description "High CPU utilization across Auto Scaling Group" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=AutoScalingGroupName,Value="$ASG_NAME" \
        --tags Key=Name,Value="${ASG_NAME}-high-cpu" \
               Key=Environment,Value=demo \
               Key=Project,Value=auto-scaling-recipe
    
    # Create CloudWatch alarm for unhealthy target count
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ASG_NAME}-unhealthy-targets" \
        --alarm-description "Unhealthy targets in target group" \
        --metric-name UnHealthyHostCount \
        --namespace AWS/ApplicationELB \
        --statistic Average \
        --period 60 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 \
        --dimensions Name=TargetGroup,Value=$(echo "$TG_ARN" | sed 's/.*\///g') \
                     Name=LoadBalancer,Value=$(echo "$ALB_ARN" | sed 's/.*loadbalancer\///g') \
        --tags Key=Name,Value="${ASG_NAME}-unhealthy-targets" \
               Key=Environment,Value=demo \
               Key=Project,Value=auto-scaling-recipe
    
    log_info "✅ Configured CloudWatch monitoring and alarms"
}

# Test deployment
test_deployment() {
    log_info "Testing auto scaling deployment..."
    
    # Display current Auto Scaling Group status
    log_info "Current Auto Scaling Group status:"
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
        --output table
    
    # Display running instances
    log_info "Running instances:"
    aws autoscaling describe-auto-scaling-instances \
        --query "AutoScalingInstances[?AutoScalingGroupName==\`$ASG_NAME\`].[InstanceId,LifecycleState,HealthStatus,AvailabilityZone]" \
        --output table
    
    # Check target group health
    log_info "Target group health status:"
    aws elbv2 describe-target-health \
        --target-group-arn "$TG_ARN" \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Description]' \
        --output table
    
    # Wait for ALB to be ready
    log_info "Waiting for load balancer to become active..."
    aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"
    
    # Test connectivity
    log_info "Testing load balancer connectivity..."
    for i in {1..5}; do
        log_info "Test attempt $i/5:"
        if curl -s --connect-timeout 10 "http://$ALB_DNS" | grep -q "Auto Scaling Demo"; then
            log_info "✅ Successfully connected to load balancer"
            break
        else
            log_warn "Connection attempt $i failed, retrying in 30 seconds..."
            sleep 30
        fi
        
        if [ $i -eq 5 ]; then
            log_error "Failed to connect to load balancer after 5 attempts"
            log_error "This may be due to DNS propagation delay. Try accessing http://$ALB_DNS manually."
        fi
    done
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.txt << EOF
# Auto Scaling Deployment Information
# Generated on: $(date)

## Resources Created
ASG_NAME=$ASG_NAME
ALB_NAME=$ALB_NAME
ALB_ARN=$ALB_ARN
ALB_DNS=$ALB_DNS
TG_NAME=$TG_NAME
TG_ARN=$TG_ARN
LT_NAME=$LT_NAME
SG_NAME=$SG_NAME
SG_ID=$SG_ID

## Access Information
Load Balancer URL: http://$ALB_DNS

## AWS Region and Account
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
VPC_ID=$VPC_ID

## Cleanup Command
To clean up all resources, run: ./destroy.sh
EOF
    
    log_info "✅ Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log_info "🚀 Starting Auto Scaling with Application Load Balancer deployment..."
    log_info "Estimated deployment time: 8-10 minutes"
    
    check_prerequisites
    setup_environment
    create_security_group
    create_launch_template
    create_load_balancer
    create_target_group
    create_listener
    create_auto_scaling_group
    configure_scaling_policies
    configure_scheduled_scaling
    configure_monitoring
    test_deployment
    save_deployment_info
    
    # Clean up temporary files
    rm -f user-data.sh cpu-target-tracking.json alb-target-tracking.json
    
    log_info "🎉 Deployment completed successfully!"
    log_info ""
    log_info "Access your auto-scaling web application at: http://$ALB_DNS"
    log_info "Use the 'Generate CPU Load' button to test auto scaling behavior"
    log_info ""
    log_info "Deployment details saved to: deployment-info.txt"
    log_info "To clean up resources, run: ./destroy.sh"
    log_info ""
    log_info "Note: DNS propagation may take a few minutes. If the URL doesn't work immediately,"
    log_info "      wait 5-10 minutes and try again."
}

# Check if running in non-interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi