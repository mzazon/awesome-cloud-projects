#!/bin/bash

# Global Load Balancing with Route53 and CloudFront - Deployment Script
# This script deploys a comprehensive global load balancing solution using
# Route53 for DNS routing, CloudFront for edge optimization, and ALBs across multiple regions

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check required tools
    for tool in jq curl; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Check if running in CloudShell
check_cloudshell() {
    if [[ -n "${AWS_EXECUTION_ENV:-}" && "${AWS_EXECUTION_ENV}" == "CloudShell" ]]; then
        log "Running in AWS CloudShell"
        return 0
    else
        log "Running in local environment"
        return 1
    fi
}

# Get user confirmation for deployment
get_confirmation() {
    info "This script will deploy global load balancing infrastructure across multiple AWS regions."
    info "Estimated monthly cost: \$100-200 for testing (varies by usage)"
    info "Resources will be created in: us-east-1, eu-west-1, ap-southeast-1"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Define multiple regions for global deployment
    export PRIMARY_REGION="us-east-1"
    export SECONDARY_REGION="eu-west-1"
    export TERTIARY_REGION="ap-southeast-1"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 8)")
    
    export PROJECT_NAME="global-lb-${RANDOM_SUFFIX}"
    export DOMAIN_NAME="example-${RANDOM_SUFFIX}.com"
    export S3_FALLBACK_BUCKET="global-lb-fallback-${RANDOM_SUFFIX}"
    
    # Create deployment state directory
    export DEPLOYMENT_STATE_DIR="/tmp/global-lb-deployment-${RANDOM_SUFFIX}"
    mkdir -p "${DEPLOYMENT_STATE_DIR}"
    
    # Save deployment configuration
    cat > "${DEPLOYMENT_STATE_DIR}/deployment-config.sh" << EOF
export PROJECT_NAME="${PROJECT_NAME}"
export DOMAIN_NAME="${DOMAIN_NAME}"
export S3_FALLBACK_BUCKET="${S3_FALLBACK_BUCKET}"
export PRIMARY_REGION="${PRIMARY_REGION}"
export SECONDARY_REGION="${SECONDARY_REGION}"
export TERTIARY_REGION="${TERTIARY_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DEPLOYMENT_STATE_DIR="${DEPLOYMENT_STATE_DIR}"
EOF
    
    log "Environment initialized with project name: ${PROJECT_NAME}"
    log "Deployment state directory: ${DEPLOYMENT_STATE_DIR}"
}

# Create S3 fallback bucket and content
create_fallback_infrastructure() {
    log "Creating S3 fallback infrastructure..."
    
    # Create S3 bucket for fallback content
    if aws s3 mb "s3://${S3_FALLBACK_BUCKET}" --region "${PRIMARY_REGION}" 2>/dev/null; then
        log "S3 fallback bucket created: ${S3_FALLBACK_BUCKET}"
    else
        warn "S3 bucket may already exist or there was an issue creating it"
    fi
    
    # Create fallback content directory
    local fallback_dir="${DEPLOYMENT_STATE_DIR}/fallback-content"
    mkdir -p "${fallback_dir}"
    
    # Create fallback maintenance page
    cat > "${fallback_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Service Temporarily Unavailable</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            padding: 50px; 
            background-color: #f8f9fa;
            color: #333;
        }
        .message { 
            background: #ffffff; 
            padding: 30px; 
            border-radius: 10px; 
            margin: 20px auto; 
            max-width: 600px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .status { 
            color: #dc3545; 
            font-size: 18px; 
            font-weight: bold; 
            margin: 20px 0;
        }
        .code {
            background: #f1f3f4;
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="message">
        <h1>🔧 Service Temporarily Unavailable</h1>
        <p class="status">We're working to restore service as quickly as possible.</p>
        <p>Our team has been notified and is working to resolve this issue.</p>
        <p>Please try again in a few minutes. If the problem persists, contact support.</p>
        <div class="code">
            <small>Error Code: GLB-FALLBACK | Timestamp: 2025-01-11</small>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create health check fallback
    cat > "${fallback_dir}/health" << 'EOF'
{
    "status": "maintenance",
    "message": "Service temporarily unavailable - all regions down",
    "timestamp": "2025-01-11T00:00:00Z",
    "fallback": true
}
EOF
    
    # Upload fallback content
    if aws s3 cp "${fallback_dir}" "s3://${S3_FALLBACK_BUCKET}/" --recursive; then
        log "Fallback content uploaded successfully"
    else
        error "Failed to upload fallback content to S3"
    fi
    
    # Set S3 bucket for static website hosting
    aws s3 website "s3://${S3_FALLBACK_BUCKET}" \
        --index-document index.html \
        --error-document index.html
    
    log "S3 fallback infrastructure created successfully"
}

# Create infrastructure in a specific region
create_regional_infrastructure() {
    local region=$1
    local region_code=$2
    
    log "Creating infrastructure in ${region}..."
    
    # Create VPC
    local vpc_id=$(aws ec2 create-vpc \
        --region "${region}" \
        --cidr-block "10.${region_code}.0.0/16" \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --region "${region}" \
        --resources "${vpc_id}" \
        --tags Key=Name,Value="${PROJECT_NAME}-vpc-${region}" Key=Project,Value="${PROJECT_NAME}"
    
    # Create Internet Gateway
    local igw_id=$(aws ec2 create-internet-gateway \
        --region "${region}" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --region "${region}" \
        --vpc-id "${vpc_id}" \
        --internet-gateway-id "${igw_id}"
    
    # Get availability zones
    local az1=$(aws ec2 describe-availability-zones \
        --region "${region}" --query 'AvailabilityZones[0].ZoneName' --output text)
    local az2=$(aws ec2 describe-availability-zones \
        --region "${region}" --query 'AvailabilityZones[1].ZoneName' --output text)
    
    # Create public subnets
    local subnet1_id=$(aws ec2 create-subnet \
        --region "${region}" \
        --vpc-id "${vpc_id}" \
        --cidr-block "10.${region_code}.1.0/24" \
        --availability-zone "${az1}" \
        --query 'Subnet.SubnetId' --output text)
    
    local subnet2_id=$(aws ec2 create-subnet \
        --region "${region}" \
        --vpc-id "${vpc_id}" \
        --cidr-block "10.${region_code}.2.0/24" \
        --availability-zone "${az2}" \
        --query 'Subnet.SubnetId' --output text)
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute \
        --region "${region}" \
        --subnet-id "${subnet1_id}" \
        --map-public-ip-on-launch
    
    aws ec2 modify-subnet-attribute \
        --region "${region}" \
        --subnet-id "${subnet2_id}" \
        --map-public-ip-on-launch
    
    # Create route table and associate subnets
    local rt_id=$(aws ec2 create-route-table \
        --region "${region}" \
        --vpc-id "${vpc_id}" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route \
        --region "${region}" \
        --route-table-id "${rt_id}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${igw_id}"
    
    aws ec2 associate-route-table \
        --region "${region}" \
        --subnet-id "${subnet1_id}" \
        --route-table-id "${rt_id}"
    
    aws ec2 associate-route-table \
        --region "${region}" \
        --subnet-id "${subnet2_id}" \
        --route-table-id "${rt_id}"
    
    # Create security group
    local sg_id=$(aws ec2 create-security-group \
        --region "${region}" \
        --group-name "${PROJECT_NAME}-sg-${region}" \
        --description "Security group for global load balancer demo" \
        --vpc-id "${vpc_id}" \
        --query 'GroupId' --output text)
    
    # Allow HTTP and HTTPS traffic
    aws ec2 authorize-security-group-ingress \
        --region "${region}" \
        --group-id "${sg_id}" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --region "${region}" \
        --group-id "${sg_id}" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Store values for later use
    cat >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh" << EOF
export VPC_ID_${region_code}="${vpc_id}"
export SUBNET1_ID_${region_code}="${subnet1_id}"
export SUBNET2_ID_${region_code}="${subnet2_id}"
export SG_ID_${region_code}="${sg_id}"
export IGW_ID_${region_code}="${igw_id}"
export RT_ID_${region_code}="${rt_id}"
EOF
    
    log "Infrastructure created successfully in ${region}"
}

# Create Application Load Balancer in a region
create_alb() {
    local region=$1
    local region_code=$2
    
    log "Creating Application Load Balancer in ${region}..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    local vpc_var="VPC_ID_${region_code}"
    local subnet1_var="SUBNET1_ID_${region_code}"
    local subnet2_var="SUBNET2_ID_${region_code}"
    local sg_var="SG_ID_${region_code}"
    
    # Create Application Load Balancer
    local alb_arn=$(aws elbv2 create-load-balancer \
        --region "${region}" \
        --name "${PROJECT_NAME}-alb-${region_code}" \
        --subnets "${!subnet1_var}" "${!subnet2_var}" \
        --security-groups "${!sg_var}" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="${PROJECT_NAME}-alb-${region}" Key=Project,Value="${PROJECT_NAME}" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get ALB DNS name
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --region "${region}" \
        --load-balancer-arns "${alb_arn}" \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    # Create target group
    local tg_arn=$(aws elbv2 create-target-group \
        --region "${region}" \
        --name "${PROJECT_NAME}-tg-${region_code}" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "${!vpc_var}" \
        --health-check-protocol HTTP \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="${PROJECT_NAME}-tg-${region}" Key=Project,Value="${PROJECT_NAME}" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener
    aws elbv2 create-listener \
        --region "${region}" \
        --load-balancer-arn "${alb_arn}" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="${tg_arn}" \
        --tags Key=Name,Value="${PROJECT_NAME}-listener-${region}" Key=Project,Value="${PROJECT_NAME}"
    
    # Store values
    cat >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh" << EOF
export ALB_ARN_${region_code}="${alb_arn}"
export ALB_DNS_${region_code}="${alb_dns}"
export TG_ARN_${region_code}="${tg_arn}"
EOF
    
    log "ALB created successfully in ${region}: ${alb_dns}"
}

# Create launch template and auto scaling group
create_compute_resources() {
    local region=$1
    local region_code=$2
    
    log "Creating compute resources in ${region}..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    local sg_var="SG_ID_${region_code}"
    local subnet1_var="SUBNET1_ID_${region_code}"
    local subnet2_var="SUBNET2_ID_${region_code}"
    local tg_var="TG_ARN_${region_code}"
    
    # Get latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --region "${region}" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        "Name=state,Values=available" \
        --query 'Images|sort_by(@, &CreationDate)[-1].ImageId' \
        --output text)
    
    # Create user data script
    local user_data_file="${DEPLOYMENT_STATE_DIR}/user-data-${region_code}.sh"
    cat > "${user_data_file}" << EOF
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create simple web application
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Global Load Balancer Demo - ${region}</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            padding: 50px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            margin: 0;
        }
        .region { 
            background: rgba(255, 255, 255, 0.1); 
            padding: 30px; 
            border-radius: 15px; 
            margin: 20px auto; 
            max-width: 600px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        .healthy { 
            color: #4caf50; 
            font-weight: bold; 
            font-size: 20px;
        }
        .info {
            background: rgba(255, 255, 255, 0.1);
            padding: 15px;
            border-radius: 10px;
            margin: 10px 0;
        }
        h1 { margin-bottom: 30px; }
    </style>
</head>
<body>
    <div class="region">
        <h1>🌍 Hello from ${region}!</h1>
        <p class="healthy">✅ Status: Healthy</p>
        <div class="info">
            <p><strong>Instance ID:</strong> \$(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
        </div>
        <div class="info">
            <p><strong>Availability Zone:</strong> \$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
        </div>
        <div class="info">
            <p><strong>Region:</strong> ${region}</p>
        </div>
        <div class="info">
            <p><strong>Timestamp:</strong> \$(date)</p>
        </div>
        <div class="info">
            <p><strong>Project:</strong> ${PROJECT_NAME}</p>
        </div>
    </div>
</body>
</html>
HTML

# Create health check endpoint
cat > /var/www/html/health << 'HEALTH'
{
    "status": "healthy",
    "region": "${region}",
    "timestamp": "\$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "instance_id": "\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
    "availability_zone": "\$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)",
    "project": "${PROJECT_NAME}"
}
HEALTH

# Configure Apache to serve health endpoint as JSON
echo "AddType application/json .json" >> /etc/httpd/conf/httpd.conf
systemctl restart httpd
EOF
    
    # Create launch template
    local lt_id=$(aws ec2 create-launch-template \
        --region "${region}" \
        --launch-template-name "${PROJECT_NAME}-lt-${region_code}" \
        --launch-template-data "{
            \"ImageId\": \"${ami_id}\",
            \"InstanceType\": \"t3.micro\",
            \"SecurityGroupIds\": [\"${!sg_var}\"],
            \"UserData\": \"$(base64 -i "${user_data_file}" | tr -d '\n')\",
            \"IamInstanceProfile\": {
                \"Name\": \"EC2InstanceConnect\"
            },
            \"TagSpecifications\": [{
                \"ResourceType\": \"instance\",
                \"Tags\": [
                    {\"Key\": \"Name\", \"Value\": \"${PROJECT_NAME}-instance-${region_code}\"},
                    {\"Key\": \"Project\", \"Value\": \"${PROJECT_NAME}\"},
                    {\"Key\": \"Region\", \"Value\": \"${region}\"}
                ]
            }]
        }" \
        --query 'LaunchTemplate.LaunchTemplateId' --output text)
    
    # Create Auto Scaling Group
    aws autoscaling create-auto-scaling-group \
        --region "${region}" \
        --auto-scaling-group-name "${PROJECT_NAME}-asg-${region_code}" \
        --launch-template LaunchTemplateId="${lt_id}",Version=1 \
        --min-size 1 \
        --max-size 3 \
        --desired-capacity 2 \
        --target-group-arns "${!tg_var}" \
        --health-check-type ELB \
        --health-check-grace-period 300 \
        --vpc-zone-identifier "${!subnet1_var},${!subnet2_var}" \
        --tags "Key=Name,Value=${PROJECT_NAME}-asg-${region_code},PropagateAtLaunch=true,ResourceId=${PROJECT_NAME}-asg-${region_code},ResourceType=auto-scaling-group" \
               "Key=Project,Value=${PROJECT_NAME},PropagateAtLaunch=true,ResourceId=${PROJECT_NAME}-asg-${region_code},ResourceType=auto-scaling-group"
    
    # Store launch template ID
    cat >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh" << EOF
export LT_ID_${region_code}="${lt_id}"
EOF
    
    log "Compute resources created successfully in ${region}"
}

# Create Route53 health checks
create_health_checks() {
    log "Creating Route53 health checks..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Function to create health check
    create_health_check() {
        local region=$1
        local region_code=$2
        local alb_dns_var="ALB_DNS_${region_code}"
        
        local hc_id=$(aws route53 create-health-check \
            --caller-reference "${PROJECT_NAME}-hc-${region_code}-$(date +%s)" \
            --health-check-config "{
                \"Type\": \"HTTP\",
                \"ResourcePath\": \"/health\",
                \"FullyQualifiedDomainName\": \"${!alb_dns_var}\",
                \"Port\": 80,
                \"RequestInterval\": 30,
                \"FailureThreshold\": 3
            }" \
            --query 'HealthCheck.Id' --output text)
        
        # Tag the health check
        aws route53 change-tags-for-resource \
            --resource-type healthcheck \
            --resource-id "${hc_id}" \
            --add-tags Key=Name,Value="${PROJECT_NAME}-hc-${region}" Key=Project,Value="${PROJECT_NAME}"
        
        echo "export HC_ID_${region_code}=\"${hc_id}\"" >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
        log "Health check created for ${region}: ${hc_id}"
    }
    
    # Create health checks for all regions
    create_health_check "${PRIMARY_REGION}" "10"
    create_health_check "${SECONDARY_REGION}" "20"
    create_health_check "${TERTIARY_REGION}" "30"
    
    log "Health checks created successfully"
}

# Create Route53 hosted zone and DNS records
create_dns_infrastructure() {
    log "Creating Route53 DNS infrastructure..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Create hosted zone
    local hz_id=$(aws route53 create-hosted-zone \
        --name "${DOMAIN_NAME}" \
        --caller-reference "${PROJECT_NAME}-$(date +%s)" \
        --hosted-zone-config Comment="Global load balancer demo zone for ${PROJECT_NAME}" \
        --query 'HostedZone.Id' --output text | cut -d'/' -f3)
    
    export HOSTED_ZONE_ID="${hz_id}"
    echo "export HOSTED_ZONE_ID=\"${hz_id}\"" >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Function to create weighted routing policy records
    create_weighted_record() {
        local region=$1
        local region_code=$2
        local weight=$3
        local alb_dns_var="ALB_DNS_${region_code}"
        local hc_var="HC_ID_${region_code}"
        
        cat > "${DEPLOYMENT_STATE_DIR}/change-batch-${region_code}.json" << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.${DOMAIN_NAME}",
                "Type": "CNAME",
                "SetIdentifier": "${region}",
                "Weight": ${weight},
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${!alb_dns_var}"
                    }
                ],
                "HealthCheckId": "${!hc_var}"
            }
        }
    ]
}
EOF
        
        aws route53 change-resource-record-sets \
            --hosted-zone-id "${HOSTED_ZONE_ID}" \
            --change-batch "file://${DEPLOYMENT_STATE_DIR}/change-batch-${region_code}.json"
        
        log "Weighted DNS record created for ${region}"
    }
    
    # Create weighted records (primary region gets higher weight)
    create_weighted_record "${PRIMARY_REGION}" "10" 100
    create_weighted_record "${SECONDARY_REGION}" "20" 50
    create_weighted_record "${TERTIARY_REGION}" "30" 25
    
    # Function to create geolocation-based routing
    create_geo_record() {
        local region=$1
        local region_code=$2
        local continent=$3
        local alb_dns_var="ALB_DNS_${region_code}"
        local hc_var="HC_ID_${region_code}"
        
        cat > "${DEPLOYMENT_STATE_DIR}/geo-batch-${region_code}.json" << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "geo.${DOMAIN_NAME}",
                "Type": "CNAME",
                "SetIdentifier": "${region}-geo",
                "GeoLocation": {
                    "ContinentCode": "${continent}"
                },
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${!alb_dns_var}"
                    }
                ],
                "HealthCheckId": "${!hc_var}"
            }
        }
    ]
}
EOF
        
        aws route53 change-resource-record-sets \
            --hosted-zone-id "${HOSTED_ZONE_ID}" \
            --change-batch "file://${DEPLOYMENT_STATE_DIR}/geo-batch-${region_code}.json"
        
        log "Geolocation DNS record created for ${region}"
    }
    
    # Create geolocation records
    create_geo_record "${PRIMARY_REGION}" "10" "NA"  # North America
    create_geo_record "${SECONDARY_REGION}" "20" "EU"  # Europe
    create_geo_record "${TERTIARY_REGION}" "30" "AS"  # Asia
    
    # Create default geolocation record
    cat > "${DEPLOYMENT_STATE_DIR}/geo-default.json" << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "geo.${DOMAIN_NAME}",
                "Type": "CNAME",
                "SetIdentifier": "default-geo",
                "GeoLocation": {
                    "CountryCode": "*"
                },
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${ALB_DNS_10}"
                    }
                ],
                "HealthCheckId": "${HC_ID_10}"
            }
        }
    ]
}
EOF
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch "file://${DEPLOYMENT_STATE_DIR}/geo-default.json"
    
    log "Route53 DNS infrastructure created successfully"
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Create Origin Access Control
    local oac_id=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config "{
            \"Name\": \"${PROJECT_NAME}-oac\",
            \"Description\": \"OAC for fallback S3 origin\",
            \"SigningProtocol\": \"sigv4\",
            \"SigningBehavior\": \"always\",
            \"OriginAccessControlOriginType\": \"s3\"
        }" \
        --query 'OriginAccessControl.Id' --output text)
    
    # Create CloudFront distribution configuration
    cat > "${DEPLOYMENT_STATE_DIR}/cloudfront-config.json" << EOF
{
    "CallerReference": "${PROJECT_NAME}-cf-$(date +%s)",
    "Comment": "Global load balancer with failover for ${PROJECT_NAME}",
    "Enabled": true,
    "Origins": {
        "Quantity": 4,
        "Items": [
            {
                "Id": "primary-origin",
                "DomainName": "${ALB_DNS_10}",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10
            },
            {
                "Id": "secondary-origin",
                "DomainName": "${ALB_DNS_20}",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10
            },
            {
                "Id": "tertiary-origin",
                "DomainName": "${ALB_DNS_30}",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10
            },
            {
                "Id": "fallback-s3-origin",
                "DomainName": "${S3_FALLBACK_BUCKET}.s3.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${oac_id}",
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10
            }
        ]
    },
    "OriginGroups": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "main-origin-group",
                "FailoverCriteria": {
                    "StatusCodes": {
                        "Quantity": 4,
                        "Items": [403, 404, 500, 502]
                    }
                },
                "Members": {
                    "Quantity": 4,
                    "Items": [
                        {"OriginId": "primary-origin"},
                        {"OriginId": "secondary-origin"},
                        {"OriginId": "tertiary-origin"},
                        {"OriginId": "fallback-s3-origin"}
                    ]
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "main-origin-group",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "TrustedKeyGroups": {
            "Enabled": false,
            "Quantity": 0
        },
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "SmoothStreaming": false,
        "Compress": true,
        "LambdaFunctionAssociations": {
            "Quantity": 0
        },
        "FunctionAssociations": {
            "Quantity": 0
        },
        "FieldLevelEncryptionId": "",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    },
    "CacheBehaviors": {
        "Quantity": 1,
        "Items": [
            {
                "PathPattern": "/health",
                "TargetOriginId": "main-origin-group",
                "ViewerProtocolPolicy": "https-only",
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "SmoothStreaming": false,
                "Compress": true,
                "LambdaFunctionAssociations": {
                    "Quantity": 0
                },
                "FunctionAssociations": {
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": "",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
            }
        ]
    },
    "CustomErrorResponses": {
        "Quantity": 2,
        "Items": [
            {
                "ErrorCode": 500,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 0
            },
            {
                "ErrorCode": 502,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 0
            }
        ]
    },
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "CertificateSource": "cloudfront"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true,
    "DefaultRootObject": "index.html"
}
EOF
    
    # Create CloudFront distribution
    local cf_output=$(aws cloudfront create-distribution \
        --distribution-config "file://${DEPLOYMENT_STATE_DIR}/cloudfront-config.json")
    
    export CF_DISTRIBUTION_ID=$(echo "${cf_output}" | jq -r '.Distribution.Id')
    export CF_DOMAIN_NAME=$(echo "${cf_output}" | jq -r '.Distribution.DomainName')
    
    # Store CloudFront values
    cat >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh" << EOF
export CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID}"
export CF_DOMAIN_NAME="${CF_DOMAIN_NAME}"
export OAC_ID="${oac_id}"
EOF
    
    log "CloudFront distribution created: ${CF_DISTRIBUTION_ID}"
    log "CloudFront domain: ${CF_DOMAIN_NAME}"
    
    # Configure S3 bucket policy for CloudFront access
    cat > "${DEPLOYMENT_STATE_DIR}/s3-cloudfront-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${S3_FALLBACK_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${CF_DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "${S3_FALLBACK_BUCKET}" \
        --policy "file://${DEPLOYMENT_STATE_DIR}/s3-cloudfront-policy.json"
    
    log "S3 bucket policy configured for CloudFront access"
}

# Create monitoring and alerting
create_monitoring() {
    log "Creating CloudWatch monitoring and alerting..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Create SNS topic for alerts
    local sns_topic_arn=$(aws sns create-topic \
        --name "${PROJECT_NAME}-alerts" \
        --tags Key=Project,Value="${PROJECT_NAME}" \
        --query 'TopicArn' --output text)
    
    echo "export SNS_TOPIC_ARN=\"${sns_topic_arn}\"" >> "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    # Function to create CloudWatch alarm for health check
    create_health_alarm() {
        local region=$1
        local region_code=$2
        local hc_var="HC_ID_${region_code}"
        
        aws cloudwatch put-metric-alarm \
            --alarm-name "${PROJECT_NAME}-health-${region}" \
            --alarm-description "Health check alarm for ${region}" \
            --metric-name HealthCheckStatus \
            --namespace AWS/Route53 \
            --statistic Minimum \
            --period 60 \
            --threshold 1 \
            --comparison-operator LessThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${sns_topic_arn}" \
            --ok-actions "${sns_topic_arn}" \
            --dimensions Name=HealthCheckId,Value="${!hc_var}" \
            --tags Key=Project,Value="${PROJECT_NAME}"
        
        log "CloudWatch alarm created for ${region}"
    }
    
    # Create alarms for all regions
    create_health_alarm "${PRIMARY_REGION}" "10"
    create_health_alarm "${SECONDARY_REGION}" "20"
    create_health_alarm "${TERTIARY_REGION}" "30"
    
    # Create CloudFront error rate alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-cloudfront-errors" \
        --alarm-description "CloudFront error rate alarm" \
        --metric-name 4xxErrorRate \
        --namespace AWS/CloudFront \
        --statistic Average \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${sns_topic_arn}" \
        --dimensions Name=DistributionId,Value="${CF_DISTRIBUTION_ID}" \
        --tags Key=Project,Value="${PROJECT_NAME}"
    
    # Create comprehensive monitoring dashboard
    cat > "${DEPLOYMENT_STATE_DIR}/dashboard.json" << EOF
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
                    ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", "${HC_ID_10}"],
                    [".", ".", ".", "${HC_ID_20}"],
                    [".", ".", ".", "${HC_ID_30}"]
                ],
                "period": 300,
                "stat": "Minimum",
                "region": "us-east-1",
                "title": "Route53 Health Check Status",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 1
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
                    ["AWS/CloudFront", "Requests", "DistributionId", "${CF_DISTRIBUTION_ID}"],
                    [".", "4xxErrorRate", ".", "."],
                    [".", "5xxErrorRate", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "CloudFront Performance"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${ALB_ARN_10##*/}"],
                    [".", ".", ".", "${ALB_ARN_20##*/}"],
                    [".", ".", ".", "${ALB_ARN_30##*/}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "ALB Response Times Across Regions"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "Global-LoadBalancer-${PROJECT_NAME}" \
        --dashboard-body "file://${DEPLOYMENT_STATE_DIR}/dashboard.json"
    
    log "CloudWatch monitoring and alerting created successfully"
    log "SNS Topic ARN: ${sns_topic_arn}"
    log "Dashboard: Global-LoadBalancer-${PROJECT_NAME}"
}

# Wait for instances to be healthy
wait_for_healthy_instances() {
    log "Waiting for instances to become healthy across all regions..."
    
    # Source regional variables
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    local max_wait=600  # 10 minutes
    local wait_time=0
    local check_interval=30
    
    while [ ${wait_time} -lt ${max_wait} ]; do
        local all_healthy=true
        
        for region_code in "10" "20" "30"; do
            local tg_var="TG_ARN_${region_code}"
            local region_var=""
            case $region_code in
                "10") region_var="${PRIMARY_REGION}" ;;
                "20") region_var="${SECONDARY_REGION}" ;;
                "30") region_var="${TERTIARY_REGION}" ;;
            esac
            
            local healthy_count=$(aws elbv2 describe-target-health \
                --region "${region_var}" \
                --target-group-arn "${!tg_var}" \
                --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
                --output text 2>/dev/null || echo "0")
            
            if [ "${healthy_count}" -lt 1 ]; then
                all_healthy=false
                info "Region ${region_var}: ${healthy_count} healthy instances"
                break
            else
                info "Region ${region_var}: ${healthy_count} healthy instances"
            fi
        done
        
        if [ "${all_healthy}" = true ]; then
            log "All regions have healthy instances!"
            break
        fi
        
        info "Waiting ${check_interval} seconds before next check..."
        sleep ${check_interval}
        wait_time=$((wait_time + check_interval))
    done
    
    if [ ${wait_time} -ge ${max_wait} ]; then
        warn "Timeout waiting for all instances to become healthy, but continuing..."
    fi
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    # Source regional variables for final summary
    source "${DEPLOYMENT_STATE_DIR}/regional-vars.sh"
    
    echo
    echo "========================================"
    echo "🌍 GLOBAL LOAD BALANCING DEPLOYMENT SUMMARY"
    echo "========================================"
    echo
    echo "📋 Project Details:"
    echo "   • Project Name: ${PROJECT_NAME}"
    echo "   • Domain Name: ${DOMAIN_NAME}"
    echo "   • Deployment ID: ${RANDOM_SUFFIX}"
    echo
    echo "🌐 CloudFront Distribution:"
    echo "   • Distribution ID: ${CF_DISTRIBUTION_ID}"
    echo "   • Domain Name: ${CF_DOMAIN_NAME}"
    echo "   • URL: https://${CF_DOMAIN_NAME}"
    echo
    echo "🔗 Route53 DNS Records:"
    echo "   • Weighted Routing: app.${DOMAIN_NAME}"
    echo "   • Geolocation Routing: geo.${DOMAIN_NAME}"
    echo "   • Hosted Zone ID: ${HOSTED_ZONE_ID}"
    echo
    echo "🏗️ Regional Infrastructure:"
    echo "   • Primary Region (${PRIMARY_REGION}): ${ALB_DNS_10}"
    echo "   • Secondary Region (${SECONDARY_REGION}): ${ALB_DNS_20}"
    echo "   • Tertiary Region (${TERTIARY_REGION}): ${ALB_DNS_30}"
    echo
    echo "📊 Monitoring:"
    echo "   • CloudWatch Dashboard: Global-LoadBalancer-${PROJECT_NAME}"
    echo "   • SNS Topic: ${SNS_TOPIC_ARN}"
    echo
    echo "💾 Deployment State:"
    echo "   • Configuration saved to: ${DEPLOYMENT_STATE_DIR}"
    echo "   • Use this path for cleanup operations"
    echo
    echo "🧪 Testing Commands:"
    echo "   curl -I https://${CF_DOMAIN_NAME}/"
    echo "   curl -s https://${CF_DOMAIN_NAME}/ | grep 'Hello from'"
    echo "   curl -s https://${CF_DOMAIN_NAME}/health | jq ."
    echo
    echo "⚠️  Important Notes:"
    echo "   • CloudFront distribution may take 15-20 minutes to fully deploy"
    echo "   • DNS propagation can take up to 48 hours"
    echo "   • Monitor costs in AWS Billing Console"
    echo "   • Use destroy.sh script for cleanup"
    echo
    echo "========================================"
    
    info "To clean up all resources, run: ./destroy.sh ${DEPLOYMENT_STATE_DIR}"
}

# Main deployment function
main() {
    log "Starting Global Load Balancing deployment..."
    
    # Run all deployment steps
    check_prerequisites
    get_confirmation
    initialize_environment
    
    # Create infrastructure
    create_fallback_infrastructure
    
    # Create regional infrastructure in parallel where possible
    log "Creating regional infrastructure..."
    create_regional_infrastructure "${PRIMARY_REGION}" "10"
    create_regional_infrastructure "${SECONDARY_REGION}" "20" 
    create_regional_infrastructure "${TERTIARY_REGION}" "30"
    
    # Create ALBs
    log "Creating Application Load Balancers..."
    create_alb "${PRIMARY_REGION}" "10"
    create_alb "${SECONDARY_REGION}" "20"
    create_alb "${TERTIARY_REGION}" "30"
    
    # Create compute resources
    log "Creating compute resources..."
    create_compute_resources "${PRIMARY_REGION}" "10"
    create_compute_resources "${SECONDARY_REGION}" "20"
    create_compute_resources "${TERTIARY_REGION}" "30"
    
    # Wait for instances to be healthy
    wait_for_healthy_instances
    
    # Create Route53 infrastructure
    create_health_checks
    create_dns_infrastructure
    
    # Create CloudFront distribution
    create_cloudfront_distribution
    
    # Create monitoring and alerting
    create_monitoring
    
    # Display summary
    display_summary
    
    log "Global Load Balancing deployment completed successfully!"
}

# Run main function
main "$@"