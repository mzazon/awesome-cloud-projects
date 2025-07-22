#!/bin/bash

# IoT Security with Device Certificates and Policies - Deployment Script
# This script deploys the complete IoT security infrastructure with device certificates and policies
# Exit on any error, treat undefined variables as errors
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    ./destroy.sh --force 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Configuration
PROJECT_NAME=${PROJECT_NAME:-"iot-security-demo"}
THING_TYPE_NAME=${THING_TYPE_NAME:-"IndustrialSensor"}
DEVICE_PREFIX=${DEVICE_PREFIX:-"sensor"}
NUM_DEVICES=${NUM_DEVICES:-3}
SKIP_PREREQUISITES=${SKIP_PREREQUISITES:-false}

# Display header
echo "=============================================================="
echo "🔒 IoT Security with Device Certificates and Policies"
echo "=============================================================="
echo "Project Name: $PROJECT_NAME"
echo "Thing Type: $THING_TYPE_NAME"
echo "Device Prefix: $DEVICE_PREFIX"
echo "Number of Devices: $NUM_DEVICES"
echo "=============================================================="

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            error "Cannot install jq automatically. Please install it manually."
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME_UNIQUE="${PROJECT_NAME}-${RANDOM_SUFFIX}"
    
    success "Environment configured - Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
}

# Create local directories
create_directories() {
    log "Creating local directories..."
    
    mkdir -p ./certificates
    mkdir -p ./logs
    
    success "Local directories created"
}

# Create IoT logging role
create_iot_logging_role() {
    log "Creating IoT logging role..."
    
    # Check if role already exists
    if aws iam get-role --role-name IoTLoggingRole &>/dev/null; then
        warning "IoTLoggingRole already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/iot-logging-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the role
    aws iam create-role \
        --role-name IoTLoggingRole \
        --assume-role-policy-document file:///tmp/iot-logging-trust-policy.json \
        --description "Service role for IoT Core logging"
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name IoTLoggingRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/IoTLogsFullAccess
    
    # Wait for role to be available
    sleep 10
    
    success "IoT logging role created"
}

# Enable IoT logging
enable_iot_logging() {
    log "Enabling IoT logging..."
    
    aws iot set-v2-logging-options \
        --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/IoTLoggingRole" \
        --default-log-level ERROR || warning "IoT logging may already be configured"
    
    success "IoT logging enabled"
}

# Create Thing Type
create_thing_type() {
    log "Creating Thing Type: $THING_TYPE_NAME..."
    
    # Check if thing type already exists
    if aws iot describe-thing-type --thing-type-name "$THING_TYPE_NAME" &>/dev/null; then
        warning "Thing type $THING_TYPE_NAME already exists, skipping creation"
        return 0
    fi
    
    aws iot create-thing-type \
        --thing-type-name "$THING_TYPE_NAME" \
        --thing-type-description "Industrial IoT sensors with security controls"
    
    success "Thing type created: $THING_TYPE_NAME"
}

# Create IoT Policies
create_iot_policies() {
    log "Creating IoT security policies..."
    
    # Create restrictive sensor policy
    cat > /tmp/sensor-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
            "Condition": {
                "Bool": {
                    "iot:Connection.Thing.IsAttached": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iot:Publish",
            "Resource": [
                "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry",
                "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/status"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Subscribe",
            "Resource": [
                "arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/commands",
                "arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/config"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Receive",
            "Resource": [
                "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/commands",
                "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/config"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:UpdateThingShadow",
                "iot:GetThingShadow"
            ],
            "Resource": "arn:aws:iot:*:*:thing/${iot:Connection.Thing.ThingName}"
        }
    ]
}
EOF
    
    # Create restrictive sensor policy
    if ! aws iot get-policy --policy-name "RestrictiveSensorPolicy" &>/dev/null; then
        aws iot create-policy \
            --policy-name "RestrictiveSensorPolicy" \
            --policy-document file:///tmp/sensor-policy.json
        success "RestrictiveSensorPolicy created"
    else
        warning "RestrictiveSensorPolicy already exists"
    fi
    
    # Create time-based policy
    cat > /tmp/time-based-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
            "Condition": {
                "Bool": {
                    "iot:Connection.Thing.IsAttached": "true"
                },
                "DateGreaterThan": {
                    "aws:CurrentTime": "08:00:00Z"
                },
                "DateLessThan": {
                    "aws:CurrentTime": "18:00:00Z"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iot:Publish",
            "Resource": "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry",
            "Condition": {
                "StringEquals": {
                    "iot:Connection.Thing.ThingTypeName": "IndustrialSensor"
                }
            }
        }
    ]
}
EOF
    
    if ! aws iot get-policy --policy-name "TimeBasedAccessPolicy" &>/dev/null; then
        aws iot create-policy \
            --policy-name "TimeBasedAccessPolicy" \
            --policy-document file:///tmp/time-based-policy.json
        success "TimeBasedAccessPolicy created"
    else
        warning "TimeBasedAccessPolicy already exists"
    fi
    
    # Create location-based policy
    cat > /tmp/location-based-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
            "Condition": {
                "Bool": {
                    "iot:Connection.Thing.IsAttached": "true"
                },
                "StringEquals": {
                    "iot:Connection.Thing.Attributes[location]": [
                        "factory-001",
                        "factory-002",
                        "factory-003"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iot:Publish",
            "Resource": "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/*",
            "Condition": {
                "StringLike": {
                    "iot:Connection.Thing.Attributes[location]": "factory-*"
                }
            }
        }
    ]
}
EOF
    
    if ! aws iot get-policy --policy-name "LocationBasedAccessPolicy" &>/dev/null; then
        aws iot create-policy \
            --policy-name "LocationBasedAccessPolicy" \
            --policy-document file:///tmp/location-based-policy.json
        success "LocationBasedAccessPolicy created"
    else
        warning "LocationBasedAccessPolicy already exists"
    fi
    
    # Create device quarantine policy
    cat > /tmp/quarantine-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Deny",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF
    
    if ! aws iot get-policy --policy-name "DeviceQuarantinePolicy" &>/dev/null; then
        aws iot create-policy \
            --policy-name "DeviceQuarantinePolicy" \
            --policy-document file:///tmp/quarantine-policy.json
        success "DeviceQuarantinePolicy created"
    else
        warning "DeviceQuarantinePolicy already exists"
    fi
}

# Create IoT devices with certificates
create_iot_devices() {
    log "Creating $NUM_DEVICES IoT devices with certificates..."
    
    for i in $(seq -f "%03g" 1 $NUM_DEVICES); do
        local thing_name="${DEVICE_PREFIX}-${i}"
        
        log "Creating device: $thing_name"
        
        # Check if thing already exists
        if aws iot describe-thing --thing-name "$thing_name" &>/dev/null; then
            warning "Thing $thing_name already exists, skipping creation"
            continue
        fi
        
        # Create IoT thing
        aws iot create-thing \
            --thing-name "$thing_name" \
            --thing-type-name "$THING_TYPE_NAME" \
            --attribute-payload "attributes={location=factory-${i},deviceType=temperature-sensor,firmwareVersion=1.0.0}"
        
        # Create keys and certificate
        local cert_output=$(aws iot create-keys-and-certificate \
            --set-as-active \
            --certificate-pem-outfile "./certificates/${thing_name}.cert.pem" \
            --public-key-outfile "./certificates/${thing_name}.public.key" \
            --private-key-outfile "./certificates/${thing_name}.private.key" \
            --output json)
        
        # Extract certificate ARN
        local cert_arn=$(echo "$cert_output" | jq -r '.certificateArn')
        
        # Attach policy to certificate
        aws iot attach-policy \
            --policy-name "RestrictiveSensorPolicy" \
            --target "$cert_arn"
        
        # Attach thing to certificate
        aws iot attach-thing-principal \
            --thing-name "$thing_name" \
            --principal "$cert_arn"
        
        success "Device $thing_name created with certificate"
    done
}

# Create thing group
create_thing_group() {
    log "Creating thing group: IndustrialSensors..."
    
    # Check if thing group already exists
    if aws iot describe-thing-group --thing-group-name "IndustrialSensors" &>/dev/null; then
        warning "Thing group IndustrialSensors already exists"
    else
        aws iot create-thing-group \
            --thing-group-name "IndustrialSensors" \
            --thing-group-properties "thingGroupDescription=Industrial sensor devices"
        success "Thing group created: IndustrialSensors"
    fi
    
    # Add devices to thing group
    log "Adding devices to thing group..."
    for i in $(seq -f "%03g" 1 $NUM_DEVICES); do
        local thing_name="${DEVICE_PREFIX}-${i}"
        
        # Check if thing is already in group
        if aws iot list-things-in-thing-group --thing-group-name "IndustrialSensors" --query "things[?@=='$thing_name']" --output text | grep -q "$thing_name"; then
            warning "Device $thing_name already in thing group"
        else
            aws iot add-thing-to-thing-group \
                --thing-group-name "IndustrialSensors" \
                --thing-name "$thing_name"
            success "Added $thing_name to thing group"
        fi
    done
}

# Create Device Defender security profile
create_security_profile() {
    log "Creating Device Defender security profile..."
    
    cat > /tmp/security-profile.json << 'EOF'
[
    {
        "name": "ExcessiveConnections",
        "metric": "aws:num-connections",
        "criteria": {
            "comparisonOperator": "greater-than",
            "value": {
                "count": 3
            },
            "consecutiveDatapointsToAlarm": 2,
            "consecutiveDatapointsToClear": 2
        }
    },
    {
        "name": "UnauthorizedOperations",
        "metric": "aws:num-authorization-failures",
        "criteria": {
            "comparisonOperator": "greater-than",
            "value": {
                "count": 5
            },
            "durationSeconds": 300,
            "consecutiveDatapointsToAlarm": 1,
            "consecutiveDatapointsToClear": 1
        }
    },
    {
        "name": "MessageSizeAnomaly",
        "metric": "aws:message-byte-size",
        "criteria": {
            "comparisonOperator": "greater-than",
            "value": {
                "count": 1024
            },
            "consecutiveDatapointsToAlarm": 3,
            "consecutiveDatapointsToClear": 3
        }
    }
]
EOF
    
    # Check if security profile already exists
    if aws iot describe-security-profile --security-profile-name "IndustrialSensorSecurity" &>/dev/null; then
        warning "Security profile IndustrialSensorSecurity already exists"
    else
        aws iot create-security-profile \
            --security-profile-name "IndustrialSensorSecurity" \
            --security-profile-description "Security monitoring for industrial IoT sensors" \
            --behaviors file:///tmp/security-profile.json
        success "Security profile created: IndustrialSensorSecurity"
    fi
    
    # Attach security profile to thing group
    log "Attaching security profile to thing group..."
    local target_arn="arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/IndustrialSensors"
    
    if aws iot list-targets-for-security-profile --security-profile-name "IndustrialSensorSecurity" --query "securityProfileTargets[?@=='$target_arn']" --output text | grep -q "$target_arn"; then
        warning "Security profile already attached to thing group"
    else
        aws iot attach-security-profile \
            --security-profile-name "IndustrialSensorSecurity" \
            --security-profile-target-arn "$target_arn"
        success "Security profile attached to thing group"
    fi
}

# Create DynamoDB table for security events
create_dynamodb_table() {
    log "Creating DynamoDB table for security events..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "IoTSecurityEvents" &>/dev/null; then
        warning "DynamoDB table IoTSecurityEvents already exists"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "IoTSecurityEvents" \
        --attribute-definitions \
            AttributeName=eventId,AttributeType=S \
            AttributeName=deviceId,AttributeType=S \
        --key-schema \
            AttributeName=eventId,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=DeviceIndex,KeySchema=[{AttributeName=deviceId,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
    
    # Wait for table to be created
    log "Waiting for DynamoDB table to be ready..."
    aws dynamodb wait table-exists --table-name "IoTSecurityEvents"
    
    success "DynamoDB table created: IoTSecurityEvents"
}

# Create CloudWatch resources
create_cloudwatch_resources() {
    log "Creating CloudWatch monitoring resources..."
    
    # Create log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/iot/security-events" --query "logGroups[?logGroupName=='/aws/iot/security-events']" --output text | grep -q "/aws/iot/security-events"; then
        warning "CloudWatch log group already exists"
    else
        aws logs create-log-group \
            --log-group-name "/aws/iot/security-events" \
            --retention-in-days 30
        success "CloudWatch log group created"
    fi
    
    # Create dashboard
    cat > /tmp/iot-security-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/IoT", "Connect.Success"],
                    ["AWS/IoT", "Connect.AuthError"],
                    ["AWS/IoT", "Connect.ClientError"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "IoT Connection Metrics"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/IoT", "PublishIn.Success"],
                    ["AWS/IoT", "PublishIn.AuthError"],
                    ["AWS/IoT", "Subscribe.Success"],
                    ["AWS/IoT", "Subscribe.AuthError"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "IoT Message Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "IoT-Security-Dashboard" \
        --dashboard-body file:///tmp/iot-security-dashboard.json
    
    success "CloudWatch dashboard created: IoT-Security-Dashboard"
}

# Create EventBridge rule for certificate rotation
create_eventbridge_rule() {
    log "Creating EventBridge rule for certificate rotation..."
    
    # Check if rule already exists
    if aws events describe-rule --name "IoT-Certificate-Rotation-Check" &>/dev/null; then
        warning "EventBridge rule already exists"
    else
        aws events put-rule \
            --name "IoT-Certificate-Rotation-Check" \
            --schedule-expression "rate(7 days)" \
            --description "Weekly check for certificate rotation needs" \
            --state ENABLED
        success "EventBridge rule created: IoT-Certificate-Rotation-Check"
    fi
}

# Download Amazon Root CA
download_root_ca() {
    log "Downloading Amazon Root CA certificate..."
    
    if [ ! -f "./certificates/AmazonRootCA1.pem" ]; then
        curl -s -o "./certificates/AmazonRootCA1.pem" \
            https://www.amazontrust.com/repository/AmazonRootCA1.pem
        success "Amazon Root CA downloaded"
    else
        warning "Amazon Root CA already exists"
    fi
}

# Get IoT endpoint
get_iot_endpoint() {
    log "Getting IoT endpoint..."
    
    local iot_endpoint=$(aws iot describe-endpoint \
        --endpoint-type iot:Data-ATS \
        --query 'endpointAddress' \
        --output text)
    
    echo "IoT_ENDPOINT=$iot_endpoint" > ./certificates/iot-endpoint.txt
    
    success "IoT endpoint saved: $iot_endpoint"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check things
    local thing_count=$(aws iot list-things --thing-type-name "$THING_TYPE_NAME" --query 'things | length(@)')
    if [ "$thing_count" -ge "$NUM_DEVICES" ]; then
        success "All $NUM_DEVICES IoT things created successfully"
    else
        error "Only $thing_count things found, expected $NUM_DEVICES"
        return 1
    fi
    
    # Check certificates
    local cert_count=$(find ./certificates -name "*.cert.pem" | wc -l)
    if [ "$cert_count" -ge "$NUM_DEVICES" ]; then
        success "All device certificates generated"
    else
        error "Only $cert_count certificates found, expected $NUM_DEVICES"
        return 1
    fi
    
    # Check security profile
    if aws iot describe-security-profile --security-profile-name "IndustrialSensorSecurity" &>/dev/null; then
        success "Security profile created and configured"
    else
        error "Security profile not found"
        return 1
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "IoTSecurityEvents" &>/dev/null; then
        success "DynamoDB table created successfully"
    else
        error "DynamoDB table not found"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/iot-*.json /tmp/*-policy.json
    success "Temporary files cleaned up"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    local iot_endpoint=$(cat ./certificates/iot-endpoint.txt | cut -d'=' -f2)
    
    cat > ./logs/deployment-summary.txt << EOF
===============================================
IoT Security Deployment Summary
===============================================
Deployment Date: $(date)
Project Name: $PROJECT_NAME_UNIQUE
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

Infrastructure Created:
- Thing Type: $THING_TYPE_NAME
- IoT Things: $NUM_DEVICES devices ($DEVICE_PREFIX-001 to $DEVICE_PREFIX-$(printf "%03d" $NUM_DEVICES))
- Thing Group: IndustrialSensors
- IoT Policies: 4 policies (Restrictive, Time-based, Location-based, Quarantine)
- Device Certificates: $NUM_DEVICES X.509 certificates
- Security Profile: IndustrialSensorSecurity
- DynamoDB Table: IoTSecurityEvents
- CloudWatch Dashboard: IoT-Security-Dashboard
- EventBridge Rule: IoT-Certificate-Rotation-Check

IoT Endpoint: $iot_endpoint

Certificate Files:
$(ls -la ./certificates/*.cert.pem | awk '{print "- " $9}')

Security Features:
- X.509 certificate-based authentication
- Fine-grained IoT policies with dynamic variables
- AWS IoT Device Defender monitoring
- Automated security event logging
- Certificate rotation monitoring
- Device quarantine capability

Next Steps:
1. Test device connections using the certificates in ./certificates/
2. Monitor security events in CloudWatch Dashboard
3. Review Device Defender alerts for anomalies
4. Implement certificate rotation procedures
5. Configure device quarantine automation

To clean up all resources, run:
./destroy.sh
===============================================
EOF
    
    success "Deployment summary saved to ./logs/deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting IoT Security deployment..."
    
    if [ "$SKIP_PREREQUISITES" != "true" ]; then
        check_prerequisites
    fi
    
    setup_environment
    create_directories
    create_iot_logging_role
    enable_iot_logging
    create_thing_type
    create_iot_policies
    create_iot_devices
    create_thing_group
    create_security_profile
    create_dynamodb_table
    create_cloudwatch_resources
    create_eventbridge_rule
    download_root_ca
    get_iot_endpoint
    validate_deployment
    cleanup_temp_files
    generate_summary
    
    echo ""
    echo "=============================================================="
    success "🎉 IoT Security deployment completed successfully!"
    echo "=============================================================="
    echo ""
    echo "📋 Summary:"
    echo "   • $NUM_DEVICES IoT devices created with X.509 certificates"
    echo "   • Security profiles and policies configured"
    echo "   • Monitoring and alerting enabled"
    echo "   • Device quarantine capability implemented"
    echo ""
    echo "📁 Files created:"
    echo "   • Device certificates: ./certificates/"
    echo "   • Deployment logs: ./logs/"
    echo "   • IoT endpoint: ./certificates/iot-endpoint.txt"
    echo ""
    echo "🔧 Next steps:"
    echo "   • Test device connections with certificates"
    echo "   • Monitor CloudWatch Dashboard: IoT-Security-Dashboard"
    echo "   • Review security events in /aws/iot/security-events logs"
    echo ""
    echo "🧹 To clean up resources:"
    echo "   ./destroy.sh"
    echo ""
    echo "=============================================================="
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --skip-prerequisites    Skip prerequisite checks"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_NAME           Project name prefix (default: iot-security-demo)"
        echo "  THING_TYPE_NAME        IoT Thing Type name (default: IndustrialSensor)"
        echo "  DEVICE_PREFIX          Device name prefix (default: sensor)"
        echo "  NUM_DEVICES            Number of devices to create (default: 3)"
        echo "  SKIP_PREREQUISITES     Skip prerequisite checks (default: false)"
        echo ""
        echo "Examples:"
        echo "  $0                                    # Deploy with defaults"
        echo "  NUM_DEVICES=5 $0                     # Deploy 5 devices"
        echo "  PROJECT_NAME=my-iot $0               # Custom project name"
        echo "  $0 --skip-prerequisites              # Skip prerequisite checks"
        exit 0
        ;;
    --skip-prerequisites)
        SKIP_PREREQUISITES=true
        ;;
    *)
        if [ -n "${1:-}" ]; then
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
        fi
        ;;
esac

# Run main deployment
main "$@"