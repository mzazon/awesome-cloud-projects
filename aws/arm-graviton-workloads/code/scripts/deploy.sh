#!/bin/bash

# Deploy script for ARM-based Workloads with AWS Graviton Processors
# This script deploys the complete infrastructure for comparing ARM and x86 performance

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Check if script is run with required permissions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 before running this script."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may not work properly."
    fi
    
    # Check if user has required permissions
    log "Checking AWS permissions..."
    
    # Test EC2 permissions
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error "Missing EC2 permissions. Please ensure you have EC2 read/write permissions."
    fi
    
    # Test ELB permissions
    if ! aws elbv2 describe-load-balancers --max-items 1 &> /dev/null; then
        error "Missing ELB permissions. Please ensure you have ELB read/write permissions."
    fi
    
    # Test Auto Scaling permissions
    if ! aws autoscaling describe-auto-scaling-groups --max-items 1 &> /dev/null; then
        error "Missing Auto Scaling permissions. Please ensure you have Auto Scaling read/write permissions."
    fi
    
    # Test CloudWatch permissions
    if ! aws cloudwatch list-dashboards --max-items 1 &> /dev/null; then
        error "Missing CloudWatch permissions. Please ensure you have CloudWatch read/write permissions."
    fi
    
    success "Prerequisites check completed successfully"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_DEFAULT_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_DEFAULT_REGION environment variable or configure AWS CLI."
    fi
    log "Using AWS region: $AWS_REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique identifiers
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    RANDOM_SUFFIX="${timestamp:(-6)}${random_suffix}"
    
    export STACK_NAME="graviton-workload-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="graviton-demo-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="graviton-sg-${RANDOM_SUFFIX}"
    
    log "Stack name: $STACK_NAME"
    log "Key pair name: $KEY_PAIR_NAME"
    log "Security group name: $SECURITY_GROUP_NAME"
    
    # Create deployment state file
    cat > deployment-state.json << EOF
{
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "stack_name": "$STACK_NAME",
    "key_pair_name": "$KEY_PAIR_NAME",
    "security_group_name": "$SECURITY_GROUP_NAME",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID"
}
EOF
    
    success "Environment setup completed"
}

# Create SSH key pair
create_key_pair() {
    log "Creating SSH key pair..."
    
    if [ -f "${KEY_PAIR_NAME}.pem" ]; then
        warn "Key pair file already exists. Skipping creation."
        return 0
    fi
    
    aws ec2 create-key-pair \
        --key-name "$KEY_PAIR_NAME" \
        --query 'KeyMaterial' \
        --output text > "${KEY_PAIR_NAME}.pem"
    
    chmod 400 "${KEY_PAIR_NAME}.pem"
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg key_pair_id "$KEY_PAIR_NAME" '.key_pair_id = $key_pair_id' deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    success "SSH key pair created: $KEY_PAIR_NAME"
}

# Get VPC information
get_vpc_info() {
    log "Getting VPC information..."
    
    # Get default VPC
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters Name=is-default,Values=true \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please create a default VPC or specify a VPC ID."
    fi
    
    # Get first available subnet
    export SUBNET_ID=$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
        error "No subnets found in VPC $VPC_ID"
    fi
    
    # Get additional subnets for ALB (needs at least 2 AZs)
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --query 'Subnets[0:2].SubnetId' \
        --output text | tr '\t' ' ')
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg vpc_id "$VPC_ID" --arg subnet_id "$SUBNET_ID" --arg subnet_ids "$SUBNET_IDS" \
            '.vpc_id = $vpc_id | .subnet_id = $subnet_id | .subnet_ids = $subnet_ids' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "Using VPC: $VPC_ID"
    log "Using Subnet: $SUBNET_ID"
    log "Using Subnets for ALB: $SUBNET_IDS"
    
    success "VPC information retrieved"
}

# Create security group
create_security_group() {
    log "Creating security group..."
    
    # Check if security group already exists
    if aws ec2 describe-security-groups --group-names "$SECURITY_GROUP_NAME" &> /dev/null; then
        warn "Security group $SECURITY_GROUP_NAME already exists. Skipping creation."
        export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --group-names "$SECURITY_GROUP_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)
    else
        export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --group-name "$SECURITY_GROUP_NAME" \
            --description "Security group for Graviton workload demo" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)
        
        # Allow HTTP access
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0
        
        # Allow SSH access
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0
        
        # Allow HTTPS access
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0
    fi
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg sg_id "$SECURITY_GROUP_ID" '.security_group_id = $sg_id' deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    success "Security group created: $SECURITY_GROUP_ID"
}

# Get latest AMI IDs
get_ami_ids() {
    log "Getting latest AMI IDs..."
    
    # Get latest Amazon Linux 2 AMI for x86
    export X86_AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Get latest Amazon Linux 2 AMI for ARM64
    export ARM_AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=amzn2-ami-hvm-*-arm64-gp2" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ "$X86_AMI_ID" = "None" ] || [ -z "$X86_AMI_ID" ]; then
        error "Could not find x86 AMI ID"
    fi
    
    if [ "$ARM_AMI_ID" = "None" ] || [ -z "$ARM_AMI_ID" ]; then
        error "Could not find ARM AMI ID"
    fi
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg x86_ami "$X86_AMI_ID" --arg arm_ami "$ARM_AMI_ID" \
            '.x86_ami_id = $x86_ami | .arm_ami_id = $arm_ami' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "x86 AMI ID: $X86_AMI_ID"
    log "ARM AMI ID: $ARM_AMI_ID"
    
    success "AMI IDs retrieved"
}

# Create user data scripts
create_user_data_scripts() {
    log "Creating user data scripts..."
    
    # Create user data script for x86 instance
    cat > user-data-x86.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd stress-ng htop wget

# Start and enable httpd
systemctl start httpd
systemctl enable httpd

# Install CloudWatch agent
cd /tmp
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create simple web page showing architecture
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>x86 Architecture Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .info { margin: 20px 0; padding: 15px; background-color: #e6f3ff; border-radius: 5px; }
        .metrics { background-color: #f9f9f9; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>x86 Architecture Server</h1>
    </div>
    <div class="info">
        <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
        <p><strong>Architecture:</strong> x86_64</p>
        <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
        <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
    </div>
    <div class="metrics">
        <h3>System Information</h3>
        <p><strong>CPU Info:</strong> <span id="cpu-info">Loading...</span></p>
        <p><strong>Memory:</strong> <span id="memory">Loading...</span></p>
        <p><strong>Uptime:</strong> <span id="uptime">Loading...</span></p>
    </div>
    
    <script>
        // Load instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data);
        
        fetch('http://169.254.169.254/latest/meta-data/instance-type')
            .then(response => response.text())
            .then(data => document.getElementById('instance-type').textContent = data);
        
        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(response => response.text())
            .then(data => document.getElementById('az').textContent = data);
        
        // Add CPU info
        document.getElementById('cpu-info').textContent = 'Intel x86_64';
        
        // Add memory info
        document.getElementById('memory').textContent = '4GB';
        
        // Add uptime
        document.getElementById('uptime').textContent = 'System running';
    </script>
</body>
</html>
HTML

# Create benchmark script
cat > /home/ec2-user/benchmark.sh << 'SCRIPT'
#!/bin/bash
echo "Starting CPU benchmark on x86 architecture..."
echo "Date: $(date)"
echo "Architecture: $(uname -m)"
echo "CPU Info:"
cat /proc/cpuinfo | grep "model name" | head -1
echo "Memory Info:"
free -h
echo ""
echo "Running stress-ng benchmark..."
stress-ng --cpu 4 --timeout 60s --metrics-brief
echo ""
echo "Benchmark completed on $(date)"
SCRIPT

chmod +x /home/ec2-user/benchmark.sh

# Create system info script
cat > /home/ec2-user/system-info.sh << 'SCRIPT'
#!/bin/bash
echo "=== System Information ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo ""
echo "=== CPU Information ==="
cat /proc/cpuinfo | grep -E "(processor|model name|cpu cores|siblings)" | head -8
echo ""
echo "=== Memory Information ==="
free -h
echo ""
echo "=== Disk Information ==="
df -h
SCRIPT

chmod +x /home/ec2-user/system-info.sh

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack none --resource none --region none || true
EOF

    # Create user data script for ARM instance
    cat > user-data-arm.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd stress-ng htop wget

# Start and enable httpd
systemctl start httpd
systemctl enable httpd

# Install CloudWatch agent for ARM
cd /tmp
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create simple web page showing architecture
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>ARM64 Graviton Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .info { margin: 20px 0; padding: 15px; background-color: #e6ffe6; border-radius: 5px; }
        .metrics { background-color: #f9f9f9; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>ARM64 Graviton Server</h1>
    </div>
    <div class="info">
        <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
        <p><strong>Architecture:</strong> aarch64</p>
        <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
        <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
    </div>
    <div class="metrics">
        <h3>System Information</h3>
        <p><strong>CPU Info:</strong> <span id="cpu-info">Loading...</span></p>
        <p><strong>Memory:</strong> <span id="memory">Loading...</span></p>
        <p><strong>Uptime:</strong> <span id="uptime">Loading...</span></p>
    </div>
    
    <script>
        // Load instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data);
        
        fetch('http://169.254.169.254/latest/meta-data/instance-type')
            .then(response => response.text())
            .then(data => document.getElementById('instance-type').textContent = data);
        
        fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone')
            .then(response => response.text())
            .then(data => document.getElementById('az').textContent = data);
        
        // Add CPU info
        document.getElementById('cpu-info').textContent = 'AWS Graviton ARM64';
        
        // Add memory info
        document.getElementById('memory').textContent = '4GB';
        
        // Add uptime
        document.getElementById('uptime').textContent = 'System running';
    </script>
</body>
</html>
HTML

# Create benchmark script
cat > /home/ec2-user/benchmark.sh << 'SCRIPT'
#!/bin/bash
echo "Starting CPU benchmark on ARM64 architecture..."
echo "Date: $(date)"
echo "Architecture: $(uname -m)"
echo "CPU Info:"
cat /proc/cpuinfo | grep -E "(processor|model name|Features)" | head -3
echo "Memory Info:"
free -h
echo ""
echo "Running stress-ng benchmark..."
stress-ng --cpu 4 --timeout 60s --metrics-brief
echo ""
echo "Benchmark completed on $(date)"
SCRIPT

chmod +x /home/ec2-user/benchmark.sh

# Create system info script
cat > /home/ec2-user/system-info.sh << 'SCRIPT'
#!/bin/bash
echo "=== System Information ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
echo ""
echo "=== CPU Information ==="
cat /proc/cpuinfo | grep -E "(processor|model name|Features)" | head -6
echo ""
echo "=== Memory Information ==="
free -h
echo ""
echo "=== Disk Information ==="
df -h
SCRIPT

chmod +x /home/ec2-user/system-info.sh

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack none --resource none --region none || true
EOF

    success "User data scripts created"
}

# Launch instances
launch_instances() {
    log "Launching EC2 instances..."
    
    # Launch x86 instance
    log "Launching x86 baseline instance..."
    X86_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$X86_AMI_ID" \
        --instance-type c6i.large \
        --key-name "$KEY_PAIR_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --user-data file://user-data-x86.sh \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${STACK_NAME}-x86-baseline},{Key=Architecture,Value=x86},{Key=Project,Value=graviton-demo},{Key=StackName,Value=${STACK_NAME}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Launch ARM instance
    log "Launching ARM Graviton instance..."
    ARM_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$ARM_AMI_ID" \
        --instance-type c7g.large \
        --key-name "$KEY_PAIR_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --user-data file://user-data-arm.sh \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${STACK_NAME}-arm-graviton},{Key=Architecture,Value=arm64},{Key=Project,Value=graviton-demo},{Key=StackName,Value=${STACK_NAME}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg x86_id "$X86_INSTANCE_ID" --arg arm_id "$ARM_INSTANCE_ID" \
            '.x86_instance_id = $x86_id | .arm_instance_id = $arm_id' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "x86 Instance ID: $X86_INSTANCE_ID"
    log "ARM Instance ID: $ARM_INSTANCE_ID"
    
    success "EC2 instances launched"
}

# Wait for instances to be running
wait_for_instances() {
    log "Waiting for instances to be running..."
    
    # Wait for x86 instance
    log "Waiting for x86 instance to be running..."
    aws ec2 wait instance-running --instance-ids "$X86_INSTANCE_ID"
    
    # Wait for ARM instance
    log "Waiting for ARM instance to be running..."
    aws ec2 wait instance-running --instance-ids "$ARM_INSTANCE_ID"
    
    # Get public IP addresses
    X86_PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$X86_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    ARM_PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$ARM_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg x86_ip "$X86_PUBLIC_IP" --arg arm_ip "$ARM_PUBLIC_IP" \
            '.x86_public_ip = $x86_ip | .arm_public_ip = $arm_ip' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "x86 Instance IP: $X86_PUBLIC_IP"
    log "ARM Instance IP: $ARM_PUBLIC_IP"
    
    success "Instances are running"
}

# Create Application Load Balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Create ALB
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --subnets $SUBNET_IDS \
        --security-groups "$SECURITY_GROUP_ID" \
        --tags Key=Name,Value="${STACK_NAME}-alb" Key=Project,Value=graviton-demo Key=StackName,Value="$STACK_NAME" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Create target group
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-tg" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$VPC_ID" \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="${STACK_NAME}-tg" Key=Project,Value=graviton-demo Key=StackName,Value="$STACK_NAME" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instances to target group
    aws elbv2 register-targets \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --targets Id="$X86_INSTANCE_ID" Id="$ARM_INSTANCE_ID"
    
    # Create listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg alb_arn "$ALB_ARN" --arg tg_arn "$TARGET_GROUP_ARN" --arg listener_arn "$LISTENER_ARN" --arg alb_dns "$ALB_DNS" \
            '.alb_arn = $alb_arn | .target_group_arn = $tg_arn | .listener_arn = $listener_arn | .alb_dns = $alb_dns' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "ALB ARN: $ALB_ARN"
    log "Target Group ARN: $TARGET_GROUP_ARN"
    log "ALB DNS: $ALB_DNS"
    
    success "Application Load Balancer created"
}

# Create Auto Scaling Group
create_auto_scaling_group() {
    log "Creating Auto Scaling Group with ARM instances..."
    
    # Create launch template
    LAUNCH_TEMPLATE_DATA=$(cat << EOF
{
    "ImageId": "$ARM_AMI_ID",
    "InstanceType": "c7g.large",
    "KeyName": "$KEY_PAIR_NAME",
    "SecurityGroupIds": ["$SECURITY_GROUP_ID"],
    "UserData": "$(base64 -w 0 user-data-arm.sh 2>/dev/null || base64 -i user-data-arm.sh)",
    "TagSpecifications": [
        {
            "ResourceType": "instance",
            "Tags": [
                {"Key": "Name", "Value": "${STACK_NAME}-asg-arm"},
                {"Key": "Architecture", "Value": "arm64"},
                {"Key": "Project", "Value": "graviton-demo"},
                {"Key": "StackName", "Value": "$STACK_NAME"}
            ]
        }
    ]
}
EOF
)
    
    LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
        --launch-template-name "${STACK_NAME}-arm-template" \
        --launch-template-data "$LAUNCH_TEMPLATE_DATA" \
        --query 'LaunchTemplate.LaunchTemplateId' \
        --output text)
    
    # Create Auto Scaling Group
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "${STACK_NAME}-asg-arm" \
        --launch-template LaunchTemplateId="$LAUNCH_TEMPLATE_ID",Version=1 \
        --min-size 1 \
        --max-size 3 \
        --desired-capacity 2 \
        --vpc-zone-identifier "$SUBNET_ID" \
        --target-group-arns "$TARGET_GROUP_ARN" \
        --health-check-type ELB \
        --health-check-grace-period 300 \
        --tags Key=Name,Value="${STACK_NAME}-asg-arm",PropagateAtLaunch=true,ResourceId="${STACK_NAME}-asg-arm",ResourceType=auto-scaling-group \
               Key=Project,Value=graviton-demo,PropagateAtLaunch=true,ResourceId="${STACK_NAME}-asg-arm",ResourceType=auto-scaling-group \
               Key=StackName,Value="$STACK_NAME",PropagateAtLaunch=true,ResourceId="${STACK_NAME}-asg-arm",ResourceType=auto-scaling-group
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg lt_id "$LAUNCH_TEMPLATE_ID" --arg asg_name "${STACK_NAME}-asg-arm" \
            '.launch_template_id = $lt_id | .asg_name = $asg_name' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    log "Launch Template ID: $LAUNCH_TEMPLATE_ID"
    log "Auto Scaling Group: ${STACK_NAME}-asg-arm"
    
    success "Auto Scaling Group created"
}

# Create CloudWatch Dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Create dashboard configuration
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", "InstanceId", "$X86_INSTANCE_ID", { "label": "x86 Instance" }],
                    [".", ".", ".", "$ARM_INSTANCE_ID", { "label": "ARM Instance" }]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "CPU Utilization Comparison",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EC2", "NetworkIn", "InstanceId", "$X86_INSTANCE_ID", { "label": "x86 Instance" }],
                    [".", ".", ".", "$ARM_INSTANCE_ID", { "label": "ARM Instance" }]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Network In Comparison"
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
                    ["AWS/EC2", "NetworkOut", "InstanceId", "$X86_INSTANCE_ID", { "label": "x86 Instance" }],
                    [".", ".", ".", "$ARM_INSTANCE_ID", { "label": "ARM Instance" }]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Network Out Comparison"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "$(echo $ALB_ARN | cut -d'/' -f2-4)"],
                    [".", "TargetResponseTime", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Load Balancer Metrics"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "Graviton-Performance-Comparison-${STACK_NAME}" \
        --dashboard-body file://dashboard-config.json
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg dashboard_name "Graviton-Performance-Comparison-${STACK_NAME}" \
            '.dashboard_name = $dashboard_name' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    success "CloudWatch dashboard created"
}

# Create cost monitoring alarm
create_cost_alarm() {
    log "Creating cost monitoring alarm..."
    
    # Create cost alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STACK_NAME}-cost-alert" \
        --alarm-description "Alert when estimated charges exceed threshold for Graviton demo" \
        --metric-name EstimatedCharges \
        --namespace AWS/Billing \
        --statistic Maximum \
        --period 86400 \
        --threshold 50.0 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=Currency,Value=USD \
        --evaluation-periods 1 || warn "Cost alarm creation failed - billing metrics may not be enabled"
    
    # Enable detailed monitoring
    aws ec2 monitor-instances \
        --instance-ids "$X86_INSTANCE_ID" "$ARM_INSTANCE_ID"
    
    # Update state file
    if command -v jq &> /dev/null; then
        jq --arg alarm_name "${STACK_NAME}-cost-alert" \
            '.cost_alarm_name = $alarm_name' \
            deployment-state.json > tmp.json && mv tmp.json deployment-state.json
    fi
    
    success "Cost monitoring setup completed"
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "=================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================="
    echo ""
    echo "Stack Name: $STACK_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Instances:"
    echo "  x86 Instance ID: $X86_INSTANCE_ID"
    echo "  x86 Public IP: $X86_PUBLIC_IP"
    echo "  ARM Instance ID: $ARM_INSTANCE_ID"
    echo "  ARM Public IP: $ARM_PUBLIC_IP"
    echo ""
    echo "Load Balancer:"
    echo "  ALB DNS: $ALB_DNS"
    echo "  Target Group: $TARGET_GROUP_ARN"
    echo ""
    echo "Auto Scaling Group:"
    echo "  Name: ${STACK_NAME}-asg-arm"
    echo "  Launch Template: $LAUNCH_TEMPLATE_ID"
    echo ""
    echo "Monitoring:"
    echo "  Dashboard: Graviton-Performance-Comparison-${STACK_NAME}"
    echo "  Cost Alarm: ${STACK_NAME}-cost-alert"
    echo ""
    echo "Access URLs:"
    echo "  x86 Instance: http://$X86_PUBLIC_IP"
    echo "  ARM Instance: http://$ARM_PUBLIC_IP"
    echo "  Load Balancer: http://$ALB_DNS"
    echo ""
    echo "SSH Access:"
    echo "  x86: ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$X86_PUBLIC_IP"
    echo "  ARM: ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$ARM_PUBLIC_IP"
    echo ""
    echo "CloudWatch Dashboard:"
    echo "  https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=Graviton-Performance-Comparison-${STACK_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Wait 5-10 minutes for instances to fully initialize"
    echo "2. Test the web interfaces using the URLs above"
    echo "3. Run performance benchmarks using SSH"
    echo "4. Monitor metrics in CloudWatch dashboard"
    echo "5. Compare costs in AWS Cost Explorer"
    echo ""
    echo "To run benchmarks:"
    echo "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$X86_PUBLIC_IP 'sudo /home/ec2-user/benchmark.sh'"
    echo "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$ARM_PUBLIC_IP 'sudo /home/ec2-user/benchmark.sh'"
    echo ""
    echo "To clean up resources:"
    echo "  ./destroy.sh"
    echo ""
    echo "=================================="
    
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting deployment of ARM-based Workloads with AWS Graviton Processors"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_key_pair
    get_vpc_info
    create_security_group
    get_ami_ids
    create_user_data_scripts
    launch_instances
    wait_for_instances
    create_load_balancer
    create_auto_scaling_group
    create_cloudwatch_dashboard
    create_cost_alarm
    display_summary
    
    log "Deployment process completed"
}

# Execute main function
main "$@"