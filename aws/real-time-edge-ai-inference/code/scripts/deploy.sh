#!/bin/bash

# Deploy script for Real-Time Edge AI Inference with IoT Greengrass
# This script automates the deployment of edge AI infrastructure on AWS

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 could not be found. Please install it before running this script."
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    check_command "aws"
    check_command "jq"
    check_command "base64"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check if AWS CLI version is v2
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ${AWS_CLI_VERSION:0:1} != "2" ]]; then
        log_warning "AWS CLI v2 is recommended. Current version: $AWS_CLI_VERSION"
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS_REGION not set. Please set it or configure AWS CLI with a default region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    export EDGE_PROJECT_NAME="edge-ai-inference-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="edge-models-${RANDOM_SUFFIX}"
    export GREENGRASS_THING_NAME="edge-device-${RANDOM_SUFFIX}"
    export EVENT_BUS_NAME="edge-monitoring-bus"
    export DEPLOYMENT_ID=""
    
    log_success "Environment variables configured"
    log_info "Project Name: $EDGE_PROJECT_NAME"
    log_info "S3 Bucket: $S3_BUCKET_NAME"
    log_info "IoT Thing: $GREENGRASS_THING_NAME"
    log_info "Region: $AWS_REGION"
}

# Create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for model storage..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $S3_BUCKET_NAME already exists"
    else
        # Create bucket with proper region handling
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}"
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        # Add bucket policy for secure access
        cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}/*",
                "arn:aws:s3:::${S3_BUCKET_NAME}"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
        
        aws s3api put-bucket-policy \
            --bucket "$S3_BUCKET_NAME" \
            --policy file://bucket-policy.json
        
        rm bucket-policy.json
        
        log_success "S3 bucket created and configured"
    fi
}

# Create IAM roles for IoT Greengrass
create_iam_roles() {
    log_info "Creating IAM roles for IoT Greengrass..."
    
    # Check if role already exists
    if aws iam get-role --role-name GreengrassV2TokenExchangeRole &>/dev/null; then
        log_warning "IAM role GreengrassV2TokenExchangeRole already exists"
    else
        # Create trust policy
        cat > greengrass-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "credentials.iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

        # Create role
        aws iam create-role \
            --role-name GreengrassV2TokenExchangeRole \
            --assume-role-policy-document file://greengrass-trust-policy.json \
            --description "Token exchange role for AWS IoT Greengrass v2"

        # Attach policy
        aws iam attach-role-policy \
            --role-name GreengrassV2TokenExchangeRole \
            --policy-arn arn:aws:iam::aws:policy/GreengrassV2TokenExchangeRoleAccess

        rm greengrass-trust-policy.json
        log_success "IAM role created"
    fi
    
    # Create IoT Role Alias
    if aws iot describe-role-alias --role-alias GreengrassV2TokenExchangeRoleAlias &>/dev/null; then
        log_warning "IoT role alias already exists"
    else
        aws iot create-role-alias \
            --role-alias GreengrassV2TokenExchangeRoleAlias \
            --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GreengrassV2TokenExchangeRole"
        
        log_success "IoT role alias created"
    fi
}

# Upload model artifacts
upload_model_artifacts() {
    log_info "Preparing and uploading model artifacts..."
    
    # Create model artifacts directory
    mkdir -p model-artifacts
    
    # Create placeholder model files (in production, use real trained models)
    echo "# ONNX Model Placeholder
# In production, replace with actual trained model
model_version: 1.0.0
framework: onnx
input_shape: [1, 3, 224, 224]
output_classes: [normal, defect]" > model-artifacts/model.onnx
    
    cat > model-artifacts/config.json << EOF
{
    "model_name": "defect_detection_v1",
    "model_version": "1.0.0",
    "input_shape": [1, 3, 224, 224],
    "output_classes": ["normal", "defect"],
    "framework": "onnx",
    "preprocessing": {
        "resize": [224, 224],
        "normalize": true,
        "mean": [0.485, 0.456, 0.406],
        "std": [0.229, 0.224, 0.225]
    },
    "postprocessing": {
        "confidence_threshold": 0.8,
        "output_format": "classification"
    }
}
EOF
    
    # Upload model artifacts to S3
    aws s3 cp model-artifacts/ "s3://${S3_BUCKET_NAME}/models/v1.0.0/" --recursive
    
    # Create metadata file
    cat > model-metadata.json << EOF
{
    "model_name": "defect_detection_v1",
    "model_version": "1.0.0",
    "input_shape": [1, 3, 224, 224],
    "output_classes": ["normal", "defect"],
    "framework": "onnx",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "model_size_mb": 25,
    "accuracy": 0.95,
    "inference_time_ms": 50
}
EOF
    
    aws s3 cp model-metadata.json "s3://${S3_BUCKET_NAME}/models/metadata.json"
    
    # Cleanup local files
    rm -rf model-artifacts model-metadata.json
    
    log_success "Model artifacts uploaded to S3"
}

# Create Greengrass components
create_greengrass_components() {
    log_info "Creating IoT Greengrass components..."
    
    # Create ONNX runtime component
    cat > onnx-runtime-recipe.json << EOF
{
    "RecipeFormatVersion": "2020-01-25",
    "ComponentName": "com.edge.OnnxRuntime",
    "ComponentVersion": "1.0.0",
    "ComponentDescription": "ONNX Runtime for edge inference",
    "ComponentPublisher": "EdgeAI",
    "ComponentConfiguration": {
        "DefaultConfiguration": {
            "RuntimeVersion": "1.16.0",
            "InstallPath": "/opt/onnxruntime"
        }
    },
    "Manifests": [
        {
            "Platform": {
                "os": "linux"
            },
            "Lifecycle": {
                "Install": {
                    "Script": "pip3 install onnxruntime==1.16.0 numpy==1.24.0 opencv-python-headless==4.8.0 boto3",
                    "Timeout": 300,
                    "RequiresPrivilege": true
                }
            }
        }
    ]
}
EOF

    # Create model component
    cat > model-component-recipe.json << EOF
{
    "RecipeFormatVersion": "2020-01-25",
    "ComponentName": "com.edge.DefectDetectionModel",
    "ComponentVersion": "1.0.0",
    "ComponentDescription": "Defect detection model for edge inference",
    "ComponentPublisher": "EdgeAI",
    "ComponentConfiguration": {
        "DefaultConfiguration": {
            "ModelPath": "/greengrass/v2/work/com.edge.DefectDetectionModel",
            "ModelS3Uri": "s3://${S3_BUCKET_NAME}/models/v1.0.0/",
            "ModelVersion": "1.0.0"
        }
    },
    "Manifests": [
        {
            "Platform": {
                "os": "linux"
            },
            "Artifacts": [
                {
                    "URI": "s3://${S3_BUCKET_NAME}/models/v1.0.0/model.onnx",
                    "Unarchive": "NONE"
                },
                {
                    "URI": "s3://${S3_BUCKET_NAME}/models/v1.0.0/config.json",
                    "Unarchive": "NONE"
                }
            ],
            "Lifecycle": {}
        }
    ]
}
EOF

    # Create inference application
    cat > inference_app.py << 'EOF'
import json
import time
import boto3
import os
import logging
from datetime import datetime
import threading
import signal
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class EdgeInferenceEngine:
    def __init__(self):
        self.model_path = os.environ.get('MODEL_PATH', 
            '/greengrass/v2/work/com.edge.DefectDetectionModel/model.onnx')
        self.config_path = os.environ.get('CONFIG_PATH',
            '/greengrass/v2/work/com.edge.DefectDetectionModel/config.json')
        self.device_id = os.environ.get('AWS_IOT_THING_NAME', 'unknown')
        self.event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        self.inference_interval = int(os.environ.get('INFERENCE_INTERVAL', '10'))
        
        self.eventbridge = None
        self.session = None
        self.config = None
        self.running = True
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        self.initialize()
    
    def signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False
    
    def initialize(self):
        """Initialize the inference engine"""
        try:
            # Initialize AWS clients
            self.eventbridge = boto3.client('events')
            
            # Load model configuration
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    self.config = json.load(f)
                logger.info("Model configuration loaded")
            else:
                logger.warning(f"Config file not found: {self.config_path}")
                self.config = {"confidence_threshold": 0.8}
            
            # Try to load ONNX model (simulated for demo)
            if os.path.exists(self.model_path):
                logger.info(f"Model file found: {self.model_path}")
                # In production: self.session = ort.InferenceSession(self.model_path)
            else:
                logger.warning(f"Model file not found: {self.model_path}")
            
            self.publish_event('ModelLoadSuccess', {
                'device_id': self.device_id,
                'model_path': self.model_path,
                'config': self.config
            })
            
        except Exception as e:
            logger.error(f"Initialization failed: {e}")
            self.publish_event('ModelLoadError', {'error': str(e)})
    
    def simulate_inference(self):
        """Simulate inference on sensor data"""
        try:
            # Simulate processing time
            processing_start = time.time()
            time.sleep(0.05)  # Simulate 50ms inference time
            processing_time = (time.time() - processing_start) * 1000
            
            # Simulate inference results
            import random
            confidence = random.uniform(0.6, 0.99)
            prediction = 'defect' if confidence > 0.85 and random.random() > 0.8 else 'normal'
            
            result = {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': self.device_id,
                'prediction': prediction,
                'confidence': round(confidence, 3),
                'inference_time_ms': round(processing_time, 2),
                'model_version': self.config.get('model_version', '1.0.0') if self.config else '1.0.0'
            }
            
            # Publish result
            event_type = 'InferenceCompleted'
            if prediction == 'defect':
                event_type = 'DefectDetected'
            
            self.publish_event(event_type, result)
            logger.info(f"Inference result: {prediction} ({confidence:.3f})")
            
            return result
            
        except Exception as e:
            logger.error(f"Inference failed: {e}")
            self.publish_event('InferenceError', {'error': str(e)})
            return None
    
    def publish_event(self, event_type, detail):
        """Publish inference events to EventBridge"""
        try:
            if self.eventbridge:
                self.eventbridge.put_events(
                    Entries=[{
                        'Source': 'edge.ai.inference',
                        'DetailType': event_type,
                        'Detail': json.dumps(detail),
                        'EventBusName': self.event_bus_name
                    }]
                )
                logger.debug(f"Published event: {event_type}")
        except Exception as e:
            logger.error(f"Failed to publish event: {e}")
    
    def health_check(self):
        """Perform health check and publish status"""
        try:
            health_status = {
                'device_id': self.device_id,
                'timestamp': datetime.utcnow().isoformat(),
                'status': 'healthy',
                'model_loaded': os.path.exists(self.model_path),
                'config_loaded': self.config is not None,
                'uptime_seconds': int(time.time() - self.start_time)
            }
            
            self.publish_event('HealthCheck', health_status)
            
        except Exception as e:
            logger.error(f"Health check failed: {e}")
    
    def run(self):
        """Main inference loop"""
        logger.info("Starting edge inference engine...")
        self.start_time = time.time()
        
        # Publish startup event
        self.publish_event('EngineStarted', {
            'device_id': self.device_id,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        health_check_counter = 0
        
        while self.running:
            try:
                # Run inference
                self.simulate_inference()
                
                # Periodic health check (every 10 inference cycles)
                health_check_counter += 1
                if health_check_counter >= 10:
                    self.health_check()
                    health_check_counter = 0
                
                # Wait for next inference cycle
                time.sleep(self.inference_interval)
                
            except KeyboardInterrupt:
                logger.info("Received keyboard interrupt")
                break
            except Exception as e:
                logger.error(f"Unexpected error in main loop: {e}")
                time.sleep(5)  # Wait before retrying
        
        # Publish shutdown event
        self.publish_event('EngineStopped', {
            'device_id': self.device_id,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        logger.info("Edge inference engine stopped")

if __name__ == "__main__":
    engine = EdgeInferenceEngine()
    engine.run()
EOF

    # Create inference component recipe
    INFERENCE_APP_B64=$(base64 -w 0 inference_app.py)
    cat > inference-component-recipe.json << EOF
{
    "RecipeFormatVersion": "2020-01-25",
    "ComponentName": "com.edge.InferenceEngine",
    "ComponentVersion": "1.0.0",
    "ComponentDescription": "Real-time inference engine with EventBridge integration",
    "ComponentPublisher": "EdgeAI",
    "ComponentDependencies": {
        "com.edge.OnnxRuntime": {
            "VersionRequirement": ">=1.0.0 <2.0.0"
        },
        "com.edge.DefectDetectionModel": {
            "VersionRequirement": ">=1.0.0 <2.0.0"
        }
    },
    "ComponentConfiguration": {
        "DefaultConfiguration": {
            "EventBusName": "${EVENT_BUS_NAME}",
            "InferenceInterval": "10",
            "ConfidenceThreshold": "0.8",
            "ModelPath": "/greengrass/v2/work/com.edge.DefectDetectionModel/model.onnx",
            "ConfigPath": "/greengrass/v2/work/com.edge.DefectDetectionModel/config.json"
        }
    },
    "Manifests": [
        {
            "Platform": {
                "os": "linux"
            },
            "Artifacts": [
                {
                    "URI": "data:text/plain;base64,${INFERENCE_APP_B64}",
                    "Unarchive": "NONE"
                }
            ],
            "Lifecycle": {
                "Run": {
                    "Script": "python3 {artifacts:path}/inference_app.py",
                    "RequiresPrivilege": false
                }
            }
        }
    ]
}
EOF

    # Create components
    aws greengrassv2 create-component-version \
        --inline-recipe file://onnx-runtime-recipe.json || \
        log_warning "ONNX runtime component may already exist"

    aws greengrassv2 create-component-version \
        --inline-recipe file://model-component-recipe.json || \
        log_warning "Model component may already exist"

    aws greengrassv2 create-component-version \
        --inline-recipe file://inference-component-recipe.json || \
        log_warning "Inference component may already exist"

    # Cleanup
    rm -f onnx-runtime-recipe.json model-component-recipe.json \
          inference-component-recipe.json inference_app.py

    log_success "IoT Greengrass components created"
}

# Set up EventBridge
setup_eventbridge() {
    log_info "Setting up EventBridge for centralized monitoring..."
    
    # Create custom EventBridge bus
    if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        log_warning "EventBridge bus $EVENT_BUS_NAME already exists"
    else
        aws events create-event-bus --name "$EVENT_BUS_NAME"
        log_success "EventBridge bus created"
    fi
    
    # Create CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/events/edge-inference" | grep -q "edge-inference"; then
        log_warning "CloudWatch log group already exists"
    else
        aws logs create-log-group --log-group-name "/aws/events/edge-inference"
        log_success "CloudWatch log group created"
    fi
    
    # Create EventBridge rule
    cat > event-pattern.json << EOF
{
    "source": ["edge.ai.inference"],
    "detail-type": ["InferenceCompleted", "InferenceError", "ModelLoadError", "DefectDetected", "HealthCheck", "EngineStarted", "EngineStopped"]
}
EOF

    if aws events describe-rule --name edge-inference-monitoring --event-bus-name "$EVENT_BUS_NAME" &>/dev/null; then
        log_warning "EventBridge rule already exists"
    else
        aws events put-rule \
            --name edge-inference-monitoring \
            --event-pattern file://event-pattern.json \
            --event-bus-name "$EVENT_BUS_NAME" \
            --state ENABLED \
            --description "Monitor edge AI inference events"
        
        # Add CloudWatch Logs target
        aws events put-targets \
            --rule edge-inference-monitoring \
            --event-bus-name "$EVENT_BUS_NAME" \
            --targets "Id"="1","Arn"="arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/events/edge-inference"
        
        log_success "EventBridge monitoring configured"
    fi
    
    rm -f event-pattern.json
}

# Configure IoT resources
configure_iot_resources() {
    log_info "Configuring IoT resources..."
    
    # Create IoT Thing
    if aws iot describe-thing --thing-name "$GREENGRASS_THING_NAME" &>/dev/null; then
        log_warning "IoT Thing $GREENGRASS_THING_NAME already exists"
    else
        aws iot create-thing --thing-name "$GREENGRASS_THING_NAME"
        log_success "IoT Thing created"
    fi
    
    # Create IoT policy
    cat > device-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect",
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "greengrass:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}"
        }
    ]
}
EOF

    if aws iot get-policy --policy-name GreengrassV2IoTThingPolicy &>/dev/null; then
        log_warning "IoT policy already exists"
    else
        aws iot create-policy \
            --policy-name GreengrassV2IoTThingPolicy \
            --policy-document file://device-policy.json
        log_success "IoT policy created"
    fi
    
    rm -f device-policy.json
}

# Create deployment
create_deployment() {
    log_info "Creating Greengrass deployment..."
    
    # Create deployment configuration
    cat > deployment.json << EOF
{
    "targetArn": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/${GREENGRASS_THING_NAME}",
    "deploymentName": "EdgeAIInferenceDeployment-${RANDOM_SUFFIX}",
    "components": {
        "com.edge.OnnxRuntime": {
            "componentVersion": "1.0.0"
        },
        "com.edge.DefectDetectionModel": {
            "componentVersion": "1.0.0"
        },
        "com.edge.InferenceEngine": {
            "componentVersion": "1.0.0",
            "configurationUpdate": {
                "merge": "{\"EventBusName\":\"${EVENT_BUS_NAME}\",\"InferenceInterval\":\"10\"}"
            }
        },
        "aws.greengrass.Cli": {
            "componentVersion": "2.12.0"
        }
    },
    "deploymentPolicies": {
        "failureHandlingPolicy": "ROLLBACK",
        "componentUpdatePolicy": {
            "timeoutInSeconds": 60,
            "action": "NOTIFY_COMPONENTS"
        },
        "configurationValidationPolicy": {
            "timeoutInSeconds": 30
        }
    },
    "tags": {
        "Project": "${EDGE_PROJECT_NAME}",
        "Environment": "demo",
        "CreatedBy": "deploy-script"
    }
}
EOF

    # Create the deployment
    DEPLOYMENT_ID=$(aws greengrassv2 create-deployment \
        --cli-input-json file://deployment.json \
        --query deploymentId --output text)
    
    if [[ "$DEPLOYMENT_ID" != "None" && -n "$DEPLOYMENT_ID" ]]; then
        export DEPLOYMENT_ID
        echo "$DEPLOYMENT_ID" > .deployment_id
        log_success "Deployment created: $DEPLOYMENT_ID"
    else
        error_exit "Failed to create deployment"
    fi
    
    rm -f deployment.json
}

# Generate configuration files
generate_config_files() {
    log_info "Generating configuration files..."
    
    # Create Greengrass configuration for edge device
    cat > greengrass-config.yaml << EOF
# AWS IoT Greengrass Core Configuration
system:
  certificateFilePath: "/greengrass/v2/certificates/cert.pem"
  privateKeyPath: "/greengrass/v2/certificates/private.key"
  rootCaPath: "/greengrass/v2/certificates/AmazonRootCA1.pem"
  thingName: "${GREENGRASS_THING_NAME}"
services:
  aws.greengrass.Nucleus:
    configuration:
      awsRegion: "${AWS_REGION}"
      iotRoleAlias: "GreengrassV2TokenExchangeRoleAlias"
      mqtt:
        port: 8883
      logging:
        level: INFO
        format: TEXT
        outputDirectory: "/greengrass/v2/logs"
        fileSizeKB: 1024
        totalLogsSizeKB: 10240
EOF

    # Create device installation script
    cat > install-greengrass.sh << 'EOF'
#!/bin/bash

# Edge device installation script for AWS IoT Greengrass
# Run this script on your edge device (Raspberry Pi, Jetson, etc.)

set -euo pipefail

echo "Installing AWS IoT Greengrass Core on edge device..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root for security reasons"
   exit 1
fi

# Install Java 11 (required for Greengrass)
sudo apt-get update
sudo apt-get install -y openjdk-11-jdk python3-pip

# Install Python dependencies
pip3 install boto3 awsiotsdk

# Create Greengrass user and directory
sudo useradd --system --create-home ggc_user
sudo groupadd --system ggc_group

# Create Greengrass directory structure
sudo mkdir -p /greengrass/v2/{certificates,logs,work}
sudo chown -R ggc_user:ggc_group /greengrass/

# Download and install Greengrass Core
cd /tmp
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassCore

# Set up certificates (you need to create and download these from AWS IoT Console)
echo "Next steps:"
echo "1. Create device certificates in AWS IoT Console"
echo "2. Download certificates to /greengrass/v2/certificates/"
echo "3. Run Greengrass installer with configuration"
echo ""
echo "Example installer command:"
echo "sudo -E java -Droot=\"/greengrass/v2\" -Dlog.store=FILE \\"
echo "  -jar ./GreengrassCore/lib/Greengrass.jar \\"
echo "  --init-config ./greengrass-config.yaml \\"
echo "  --component-default-user ggc_user:ggc_group \\"
echo "  --setup-system-service true"
EOF

    chmod +x install-greengrass.sh

    log_success "Configuration files generated"
    log_info "Edge device setup files:"
    log_info "  - greengrass-config.yaml (Greengrass configuration)"
    log_info "  - install-greengrass.sh (Edge device installation script)"
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Project Name: $EDGE_PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $S3_BUCKET_NAME"
    echo "IoT Thing: $GREENGRASS_THING_NAME"
    echo "EventBridge Bus: $EVENT_BUS_NAME"
    if [[ -n "${DEPLOYMENT_ID:-}" ]]; then
        echo "Deployment ID: $DEPLOYMENT_ID"
    fi
    echo ""
    echo "Next Steps:"
    echo "1. Set up your edge device using install-greengrass.sh"
    echo "2. Monitor deployment status:"
    if [[ -n "${DEPLOYMENT_ID:-}" ]]; then
        echo "   aws greengrassv2 get-deployment --deployment-id $DEPLOYMENT_ID"
    fi
    echo "3. Monitor inference events:"
    echo "   aws logs tail /aws/events/edge-inference --follow"
    echo "4. View S3 models:"
    echo "   aws s3 ls s3://$S3_BUCKET_NAME/models/ --recursive"
    echo ""
    echo "Configuration files created:"
    echo "  - greengrass-config.yaml"
    echo "  - install-greengrass.sh"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "=================================="
}

# Save deployment state
save_deployment_state() {
    cat > .deployment_state << EOF
EDGE_PROJECT_NAME="$EDGE_PROJECT_NAME"
S3_BUCKET_NAME="$S3_BUCKET_NAME"
GREENGRASS_THING_NAME="$GREENGRASS_THING_NAME"
EVENT_BUS_NAME="$EVENT_BUS_NAME"
AWS_REGION="$AWS_REGION"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-}"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    log_info "Deployment state saved to .deployment_state"
}

# Main deployment function
main() {
    echo "Starting deployment of Real-Time Edge AI Inference solution..."
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_roles
    upload_model_artifacts
    create_greengrass_components
    setup_eventbridge
    configure_iot_resources
    create_deployment
    generate_config_files
    save_deployment_state
    display_summary
    
    log_success "All deployment steps completed!"
    exit 0
}

# Run main function
main "$@"