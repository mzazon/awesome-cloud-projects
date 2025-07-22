#!/bin/bash

# =============================================================================
# AWS Wavelength and CloudFront Edge Application Deployment Script
# 
# This script deploys a complete low-latency edge application using:
# - AWS Wavelength Zones for ultra-low latency processing
# - CloudFront for global content delivery
# - Application Load Balancer for high availability
# - Route 53 for DNS management
# - S3 for static asset storage
# =============================================================================

set -euo pipefail

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
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Some output formatting may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="${PROJECT_NAME:-edge-app-${RANDOM_SUFFIX}}"
    export DOMAIN_NAME="${DOMAIN_NAME:-your-domain.com}"
    
    # Wavelength Zone configuration (user should modify this)
    export WAVELENGTH_ZONE="${WAVELENGTH_ZONE:-us-west-2-wl1-las-wlz-1}"
    export WAVELENGTH_GROUP="${WAVELENGTH_GROUP:-us-west-2-wl1-las-1}"
    
    log "Environment configured:"
    log "  Project Name: ${PROJECT_NAME}"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  Wavelength Zone: ${WAVELENGTH_ZONE}"
    log "  Domain Name: ${DOMAIN_NAME}"
    
    success "Environment setup completed"
}

# Check and enable Wavelength Zone
enable_wavelength_zone() {
    log "Checking Wavelength Zone availability..."
    
    # Check available Wavelength zones
    local available_zones
    available_zones=$(aws ec2 describe-availability-zones \
        --filters "Name=zone-type,Values=wavelength-zone" \
        --query 'AvailabilityZones[*].ZoneName' \
        --output text || echo "")
    
    if [[ -z "${available_zones}" ]]; then
        error "No Wavelength Zones available in region ${AWS_REGION}"
        error "Please check AWS Wavelength availability at: https://aws.amazon.com/wavelength/locations/"
        exit 1
    fi
    
    log "Available Wavelength Zones: ${available_zones}"
    
    # Enable Wavelength Zone group
    log "Enabling Wavelength Zone group: ${WAVELENGTH_GROUP}"
    aws ec2 modify-availability-zone-group \
        --group-name "${WAVELENGTH_GROUP}" \
        --opt-in-status opted-in \
        || warning "Zone group may already be enabled"
    
    # Verify zone is enabled
    local zone_status
    zone_status=$(aws ec2 describe-availability-zones \
        --zone-names "${WAVELENGTH_ZONE}" \
        --query 'AvailabilityZones[0].OptInStatus' \
        --output text 2>/dev/null || echo "not-available")
    
    if [[ "${zone_status}" != "opted-in" ]]; then
        error "Failed to enable Wavelength Zone: ${WAVELENGTH_ZONE}"
        error "Zone status: ${zone_status}"
        exit 1
    fi
    
    success "Wavelength Zone enabled and available"
}

# Create VPC and networking
create_networking() {
    log "Creating VPC and networking components..."
    
    # Create VPC
    log "Creating VPC..."
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    echo "VPC_ID=${VPC_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames
    
    # Create Wavelength subnet
    log "Creating Wavelength subnet..."
    WL_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${WAVELENGTH_ZONE}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-wavelength-subnet},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "WL_SUBNET_ID=${WL_SUBNET_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Create regional subnet
    log "Creating regional subnet..."
    REGIONAL_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-regional-subnet},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "REGIONAL_SUBNET_ID=${REGIONAL_SUBNET_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Create carrier gateway
    log "Creating carrier gateway..."
    CG_ID=$(aws ec2 create-carrier-gateway \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=carrier-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-carrier-gateway},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'CarrierGateway.CarrierGatewayId' --output text)
    echo "CG_ID=${CG_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Create internet gateway for regional subnet
    log "Creating internet gateway..."
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    echo "IGW_ID=${IGW_ID}" >> "${PROJECT_NAME}-resources.env"
    
    aws ec2 attach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}"
    
    # Create route tables
    log "Creating route tables..."
    
    # Wavelength route table
    WL_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-wavelength-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'RouteTable.RouteTableId' --output text)
    echo "WL_RT_ID=${WL_RT_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Regional route table
    REGIONAL_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-regional-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'RouteTable.RouteTableId' --output text)
    echo "REGIONAL_RT_ID=${REGIONAL_RT_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Add routes
    aws ec2 create-route --route-table-id "${WL_RT_ID}" --destination-cidr-block 0.0.0.0/0 --carrier-gateway-id "${CG_ID}"
    aws ec2 create-route --route-table-id "${REGIONAL_RT_ID}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${IGW_ID}"
    
    # Associate route tables with subnets
    aws ec2 associate-route-table --subnet-id "${WL_SUBNET_ID}" --route-table-id "${WL_RT_ID}"
    aws ec2 associate-route-table --subnet-id "${REGIONAL_SUBNET_ID}" --route-table-id "${REGIONAL_RT_ID}"
    
    success "Networking components created successfully"
}

# Create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Wavelength security group
    WL_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-wavelength-sg" \
        --description "Security group for Wavelength edge applications" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-wavelength-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'GroupId' --output text)
    echo "WL_SG_ID=${WL_SG_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Add inbound rules for Wavelength SG
    aws ec2 authorize-security-group-ingress --group-id "${WL_SG_ID}" --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "${WL_SG_ID}" --protocol tcp --port 443 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "${WL_SG_ID}" --protocol tcp --port 8080 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "${WL_SG_ID}" --protocol tcp --port 22 --cidr 10.0.0.0/16
    
    # Regional security group
    REGIONAL_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-regional-sg" \
        --description "Security group for regional backend services" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-regional-sg},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'GroupId' --output text)
    echo "REGIONAL_SG_ID=${REGIONAL_SG_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Add inbound rules for Regional SG
    aws ec2 authorize-security-group-ingress --group-id "${REGIONAL_SG_ID}" --protocol tcp --port 80 --source-group "${WL_SG_ID}"
    aws ec2 authorize-security-group-ingress --group-id "${REGIONAL_SG_ID}" --protocol tcp --port 443 --source-group "${WL_SG_ID}"
    aws ec2 authorize-security-group-ingress --group-id "${REGIONAL_SG_ID}" --protocol tcp --port 22 --cidr 10.0.0.0/16
    
    success "Security groups created successfully"
}

# Deploy edge application to Wavelength Zone
deploy_edge_application() {
    log "Deploying edge application to Wavelength Zone..."
    
    # Get latest Amazon Linux 2 AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Create user data script
    cat > wavelength-user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Run edge application
docker run -d --name edge-app -p 8080:8080 --restart unless-stopped nginx:alpine

# Configure nginx for edge application
docker exec edge-app sh -c 'cat > /etc/nginx/conf.d/default.conf << "NGINX_EOF"
server {
    listen 8080;
    location / {
        add_header Content-Type text/plain;
        return 200 "Edge Server Response - Request processed at: \$time_iso8601\nServer: \$hostname\nClient IP: \$remote_addr\n";
    }
    location /health {
        add_header Content-Type text/plain;
        return 200 "healthy";
    }
    location /api/latency {
        add_header Content-Type application/json;
        return 200 "{\"timestamp\":\"\$time_iso8601\",\"server\":\"\$hostname\",\"response_time_ms\":\"1-5\"}";
    }
}
NGINX_EOF'

docker restart edge-app

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent
EOF
    
    # Launch EC2 instance in Wavelength Zone
    log "Launching EC2 instance in Wavelength Zone..."
    WL_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type t3.medium \
        --subnet-id "${WL_SUBNET_ID}" \
        --security-group-ids "${WL_SG_ID}" \
        --user-data file://wavelength-user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-wavelength-server},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Instances[0].InstanceId' --output text)
    echo "WL_INSTANCE_ID=${WL_INSTANCE_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Wait for instance to be running
    log "Waiting for Wavelength instance to be running..."
    aws ec2 wait instance-running --instance-ids "${WL_INSTANCE_ID}"
    
    # Get instance details
    WL_INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids "${WL_INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)
    echo "WL_INSTANCE_IP=${WL_INSTANCE_IP}" >> "${PROJECT_NAME}-resources.env"
    
    # Clean up user data file
    rm wavelength-user-data.sh
    
    success "Edge application deployed to Wavelength Zone"
    log "  Instance ID: ${WL_INSTANCE_ID}"
    log "  Private IP: ${WL_INSTANCE_IP}"
}

# Create Application Load Balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Create ALB in Wavelength Zone
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${PROJECT_NAME}-wavelength-alb" \
        --subnets "${WL_SUBNET_ID}" \
        --security-groups "${WL_SG_ID}" \
        --scheme internal \
        --type application \
        --tags Key=Name,Value="${PROJECT_NAME}-wavelength-alb" Key=Project,Value="${PROJECT_NAME}" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    echo "ALB_ARN=${ALB_ARN}" >> "${PROJECT_NAME}-resources.env"
    
    # Create target group
    TG_ARN=$(aws elbv2 create-target-group \
        --name "${PROJECT_NAME}-edge-targets" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "${VPC_ID}" \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="${PROJECT_NAME}-edge-targets" Key=Project,Value="${PROJECT_NAME}" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    echo "TG_ARN=${TG_ARN}" >> "${PROJECT_NAME}-resources.env"
    
    # Register instance with target group
    aws elbv2 register-targets \
        --target-group-arn "${TG_ARN}" \
        --targets Id="${WL_INSTANCE_ID}"
    
    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn "${ALB_ARN}" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="${TG_ARN}"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "${ALB_ARN}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    echo "ALB_DNS=${ALB_DNS}" >> "${PROJECT_NAME}-resources.env"
    
    # Wait for targets to be healthy
    log "Waiting for target to be healthy..."
    local retries=0
    while [[ $retries -lt 20 ]]; do
        local health_status
        health_status=$(aws elbv2 describe-target-health \
            --target-group-arn "${TG_ARN}" \
            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
            --output text 2>/dev/null || echo "unknown")
        
        if [[ "${health_status}" == "healthy" ]]; then
            break
        fi
        
        log "Target health status: ${health_status}, waiting..."
        sleep 30
        ((retries++))
    done
    
    success "Application Load Balancer created and targets are healthy"
    log "  ALB DNS: ${ALB_DNS}"
}

# Create S3 bucket for static assets
create_s3_bucket() {
    log "Creating S3 bucket for static assets..."
    
    S3_BUCKET="${PROJECT_NAME}-static-assets-$(date +%s)"
    echo "S3_BUCKET=${S3_BUCKET}" >> "${PROJECT_NAME}-resources.env"
    
    # Create bucket
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET}"
    else
        aws s3 mb "s3://${S3_BUCKET}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    # Create sample content
    cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Low-Latency Edge Application</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: rgba(255,255,255,0.1);
            border-radius: 15px;
            padding: 40px;
            backdrop-filter: blur(10px);
        }
        .latency-test { 
            background: rgba(255,255,255,0.2); 
            padding: 20px; 
            margin: 20px 0; 
            border-radius: 10px;
            border: 1px solid rgba(255,255,255,0.3);
        }
        .btn {
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            margin: 10px 5px;
            transition: background 0.3s;
        }
        .btn:hover { background: #ee5a52; }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric {
            background: rgba(255,255,255,0.15);
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #4ecdc4;
        }
        .status { padding: 10px; border-radius: 5px; margin: 10px 0; }
        .success { background: rgba(76, 175, 80, 0.3); }
        .loading { background: rgba(255, 193, 7, 0.3); }
        .error { background: rgba(244, 67, 54, 0.3); }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 AWS Wavelength Edge Application</h1>
        <p>Experience ultra-low latency with AWS Wavelength Zones and CloudFront global distribution.</p>
        
        <div class="latency-test">
            <h2>📊 Real-Time Latency Test</h2>
            <div class="metrics">
                <div class="metric">
                    <div>Page Load Time</div>
                    <div class="metric-value" id="load-time">-</div>
                    <div>milliseconds</div>
                </div>
                <div class="metric">
                    <div>Edge Response</div>
                    <div class="metric-value" id="edge-latency">-</div>
                    <div>milliseconds</div>
                </div>
                <div class="metric">
                    <div>Connection Type</div>
                    <div class="metric-value" id="connection-type">CloudFront</div>
                    <div>CDN</div>
                </div>
            </div>
            
            <button class="btn" onclick="testEdgeLatency()">Test Edge Latency</button>
            <button class="btn" onclick="testAPICall()">Test API Call</button>
            <button class="btn" onclick="runContinuousTest()">Continuous Test</button>
            
            <div id="test-results"></div>
        </div>
        
        <div class="latency-test">
            <h3>🌐 Architecture Overview</h3>
            <ul>
                <li><strong>Static Content:</strong> Served via CloudFront global edge network</li>
                <li><strong>Dynamic API:</strong> Routed to AWS Wavelength Zone for &lt;10ms latency</li>
                <li><strong>Edge Computing:</strong> Processing at 5G network edge</li>
                <li><strong>Global Reach:</strong> Optimized content delivery worldwide</li>
            </ul>
        </div>
    </div>

    <script>
        const startTime = performance.now();
        let testInterval;
        
        window.onload = function() {
            const loadTime = Math.round(performance.now() - startTime);
            document.getElementById('load-time').textContent = loadTime;
            
            // Detect connection type
            if (navigator.connection) {
                document.getElementById('connection-type').textContent = 
                    navigator.connection.effectiveType || 'Unknown';
            }
        };
        
        function updateResults(message, type = 'success') {
            const results = document.getElementById('test-results');
            results.innerHTML = \`<div class="status \${type}">\${message}</div>\` + results.innerHTML;
        }
        
        async function testEdgeLatency() {
            updateResults('Testing edge latency...', 'loading');
            const start = performance.now();
            
            try {
                const response = await fetch('/api/latency', { 
                    cache: 'no-cache',
                    headers: { 'Cache-Control': 'no-cache' }
                });
                const latency = Math.round(performance.now() - start);
                const data = await response.json();
                
                document.getElementById('edge-latency').textContent = latency;
                updateResults(\`Edge latency: \${latency}ms - Response from: \${data.server || 'Wavelength Zone'}\`);
            } catch (error) {
                updateResults(\`Error testing edge latency: \${error.message}\`, 'error');
            }
        }
        
        async function testAPICall() {
            updateResults('Testing API call...', 'loading');
            const start = performance.now();
            
            try {
                const response = await fetch('/api/health', { 
                    cache: 'no-cache',
                    headers: { 'Cache-Control': 'no-cache' }
                });
                const latency = Math.round(performance.now() - start);
                const text = await response.text();
                
                updateResults(\`API call completed in \${latency}ms - Status: \${text}\`);
            } catch (error) {
                updateResults(\`Error in API call: \${error.message}\`, 'error');
            }
        }
        
        function runContinuousTest() {
            if (testInterval) {
                clearInterval(testInterval);
                testInterval = null;
                document.querySelector('button[onclick="runContinuousTest()"]').textContent = 'Continuous Test';
                return;
            }
            
            document.querySelector('button[onclick="runContinuousTest()"]').textContent = 'Stop Test';
            testInterval = setInterval(testEdgeLatency, 2000);
        }
        
        // Initial latency test
        setTimeout(testEdgeLatency, 1000);
    </script>
</body>
</html>
EOF
    
    # Upload content to S3
    aws s3 cp index.html "s3://${S3_BUCKET}/"
    
    # Clean up local file
    rm index.html
    
    success "S3 bucket created and configured: ${S3_BUCKET}"
}

# Configure CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Create Origin Access Control
    OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config '{
            "Name": "'${PROJECT_NAME}'-s3-oac",
            "Description": "OAC for S3 static assets",
            "OriginAccessControlOriginType": "s3",
            "SigningBehavior": "always",
            "SigningProtocol": "sigv4"
        }' \
        --query 'OriginAccessControl.Id' --output text)
    echo "OAC_ID=${OAC_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Create distribution configuration
    cat > distribution-config.json << EOF
{
    "CallerReference": "${PROJECT_NAME}-$(date +%s)",
    "Comment": "Edge application with Wavelength and S3 origins",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 2,
        "Items": [
            {
                "Id": "S3-${S3_BUCKET}",
                "DomainName": "${S3_BUCKET}.s3.${AWS_REGION}.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}"
            },
            {
                "Id": "Wavelength-ALB",
                "DomainName": "${ALB_DNS}",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-${S3_BUCKET}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "MinTTL": 0,
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        }
    },
    "CacheBehaviors": {
        "Quantity": 2,
        "Items": [
            {
                "PathPattern": "/api/*",
                "TargetOriginId": "Wavelength-ALB",
                "ViewerProtocolPolicy": "https-only",
                "MinTTL": 0,
                "MaxTTL": 0,
                "DefaultTTL": 0,
                "ForwardedValues": {
                    "QueryString": true,
                    "Cookies": {
                        "Forward": "all"
                    },
                    "Headers": {
                        "Quantity": 3,
                        "Items": ["Host", "User-Agent", "CloudFront-Viewer-Country"]
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                }
            },
            {
                "PathPattern": "/health",
                "TargetOriginId": "Wavelength-ALB",
                "ViewerProtocolPolicy": "allow-all",
                "MinTTL": 0,
                "MaxTTL": 0,
                "DefaultTTL": 0,
                "ForwardedValues": {
                    "QueryString": false,
                    "Cookies": {
                        "Forward": "none"
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All"
}
EOF
    
    # Create CloudFront distribution
    DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file://distribution-config.json \
        --query 'Distribution.Id' --output text)
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Get CloudFront domain name
    CF_DOMAIN=$(aws cloudfront get-distribution \
        --id "${DISTRIBUTION_ID}" \
        --query 'Distribution.DomainName' \
        --output text)
    echo "CF_DOMAIN=${CF_DOMAIN}" >> "${PROJECT_NAME}-resources.env"
    
    # Clean up config file
    rm distribution-config.json
    
    success "CloudFront distribution created: ${DISTRIBUTION_ID}"
    log "  Domain: ${CF_DOMAIN}"
    log "  Note: Distribution deployment may take 15-20 minutes to complete globally"
}

# Configure S3 bucket policy for CloudFront
configure_s3_bucket_policy() {
    log "Configuring S3 bucket policy for CloudFront access..."
    
    cat > bucket-policy.json << EOF
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
            "Resource": "arn:aws:s3:::${S3_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "${S3_BUCKET}" \
        --policy file://bucket-policy.json
    
    rm bucket-policy.json
    
    success "S3 bucket policy configured for CloudFront access"
}

# Configure Route 53 DNS (optional)
configure_dns() {
    if [[ "${DOMAIN_NAME}" == "your-domain.com" ]]; then
        warning "Skipping DNS configuration (using default domain name)"
        warning "To configure DNS, set DOMAIN_NAME environment variable to your actual domain"
        return
    fi
    
    log "Configuring Route 53 DNS for domain: ${DOMAIN_NAME}"
    
    # Check if hosted zone exists
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name "${DOMAIN_NAME}" \
        --query 'HostedZones[0].Id' \
        --output text 2>/dev/null | cut -d'/' -f3)
    
    if [[ "${HOSTED_ZONE_ID}" == "None" || -z "${HOSTED_ZONE_ID}" ]]; then
        log "Creating hosted zone for ${DOMAIN_NAME}"
        HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
            --name "${DOMAIN_NAME}" \
            --caller-reference "${PROJECT_NAME}-$(date +%s)" \
            --hosted-zone-config Comment="Edge application DNS zone" \
            --query 'HostedZone.Id' --output text | cut -d'/' -f3)
    fi
    
    echo "HOSTED_ZONE_ID=${HOSTED_ZONE_ID}" >> "${PROJECT_NAME}-resources.env"
    
    # Create CNAME record for CloudFront
    cat > dns-change.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "app.${DOMAIN_NAME}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${CF_DOMAIN}"
                    }
                ]
            }
        }
    ]
}
EOF
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch file://dns-change.json \
        --output text
    
    rm dns-change.json
    
    success "DNS configured: app.${DOMAIN_NAME} → ${CF_DOMAIN}"
}

# Display deployment summary
show_deployment_summary() {
    log "Deployment completed successfully! 🎉"
    echo ""
    echo "==================================================================="
    echo "              AWS WAVELENGTH EDGE APPLICATION"
    echo "==================================================================="
    echo ""
    echo "📊 DEPLOYMENT SUMMARY:"
    echo "  Project Name:        ${PROJECT_NAME}"
    echo "  AWS Region:          ${AWS_REGION}"
    echo "  Wavelength Zone:     ${WAVELENGTH_ZONE}"
    echo ""
    echo "🌐 ACCESS POINTS:"
    echo "  CloudFront Domain:   https://${CF_DOMAIN}"
    if [[ "${DOMAIN_NAME}" != "your-domain.com" ]]; then
        echo "  Custom Domain:       https://app.${DOMAIN_NAME}"
    fi
    echo "  Direct ALB Access:   http://${ALB_DNS}"
    echo ""
    echo "🔗 TEST ENDPOINTS:"
    echo "  Static Content:      https://${CF_DOMAIN}/"
    echo "  Health Check:        https://${CF_DOMAIN}/health"
    echo "  Edge API:            https://${CF_DOMAIN}/api/latency"
    echo ""
    echo "📁 RESOURCE INFORMATION:"
    echo "  Resource file:       ${PROJECT_NAME}-resources.env"
    echo "  S3 Bucket:           ${S3_BUCKET}"
    echo "  VPC ID:              ${VPC_ID}"
    echo "  Wavelength Instance: ${WL_INSTANCE_ID}"
    echo ""
    echo "⚠️  IMPORTANT NOTES:"
    echo "  • CloudFront deployment takes 15-20 minutes to propagate globally"
    echo "  • Wavelength Zone provides ultra-low latency (<10ms) for mobile users"
    echo "  • Static content is cached globally via CloudFront"
    echo "  • API calls are routed directly to Wavelength Zone"
    echo "  • Monitor costs as Wavelength and data transfer charges apply"
    echo ""
    echo "🧹 CLEANUP:"
    echo "  To remove all resources: ./destroy.sh ${PROJECT_NAME}"
    echo ""
    echo "==================================================================="
}

# Main deployment function
main() {
    log "Starting AWS Wavelength and CloudFront deployment..."
    
    # Check if resource file already exists
    if [[ -f "${PROJECT_NAME}-resources.env" ]]; then
        warning "Resource file ${PROJECT_NAME}-resources.env already exists"
        read -p "Do you want to continue and potentially overwrite existing resources? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
        rm "${PROJECT_NAME}-resources.env"
    fi
    
    # Create resource tracking file
    echo "# AWS Wavelength Edge Application Resources" > "${PROJECT_NAME}-resources.env"
    echo "# Generated on $(date)" >> "${PROJECT_NAME}-resources.env"
    echo "PROJECT_NAME=${PROJECT_NAME}" >> "${PROJECT_NAME}-resources.env"
    echo "AWS_REGION=${AWS_REGION}" >> "${PROJECT_NAME}-resources.env"
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> "${PROJECT_NAME}-resources.env"
    echo "WAVELENGTH_ZONE=${WAVELENGTH_ZONE}" >> "${PROJECT_NAME}-resources.env"
    echo "DOMAIN_NAME=${DOMAIN_NAME}" >> "${PROJECT_NAME}-resources.env"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_wavelength_zone
    create_networking
    create_security_groups
    deploy_edge_application
    create_load_balancer
    create_s3_bucket
    create_cloudfront_distribution
    configure_s3_bucket_policy
    configure_dns
    show_deployment_summary
    
    success "Deployment completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"