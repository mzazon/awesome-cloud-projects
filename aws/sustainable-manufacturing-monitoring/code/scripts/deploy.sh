#!/bin/bash

# =============================================================================
# AWS IoT SiteWise Sustainable Manufacturing Monitoring - Deployment Script
# =============================================================================
# This script deploys the complete sustainable manufacturing monitoring solution
# using AWS IoT SiteWise, CloudWatch, Lambda, and QuickSight.
# 
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for IoT SiteWise, Lambda, CloudWatch, and QuickSight
# - jq installed for JSON parsing
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# =============================================================================
# CONFIGURATION AND GLOBALS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_info "Deployment state file exists. Run destroy.sh to clean up."
    fi
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required AWS services availability
    log_info "Checking AWS service availability..."
    
    # Test IoT SiteWise
    if ! aws iotsitewise list-asset-models --max-results 1 &> /dev/null; then
        log_error "IoT SiteWise not available in current region or insufficient permissions."
        exit 1
    fi
    
    # Test Lambda
    if ! aws lambda list-functions --max-items 1 &> /dev/null; then
        log_error "Lambda not available in current region or insufficient permissions."
        exit 1
    fi
    
    # Test CloudWatch
    if ! aws cloudwatch list-metrics --max-records 1 &> /dev/null; then
        log_error "CloudWatch not available in current region or insufficient permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warn "No region configured. Using default: ${AWS_REGION}"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_error "Failed to get AWS Account ID."
        exit 1
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export SITEWISE_MODEL_NAME="SustainableManufacturingModel"
    export LAMBDA_FUNCTION_NAME="manufacturing-carbon-calculator-${RANDOM_SUFFIX}"
    export QUICKSIGHT_DATASOURCE_NAME="manufacturing-sustainability-${RANDOM_SUFFIX}"
    export DEPLOYMENT_ID="${RANDOM_SUFFIX}"
    
    # Save environment variables to state file
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_ID=${DEPLOYMENT_ID}
SITEWISE_MODEL_NAME=${SITEWISE_MODEL_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
QUICKSIGHT_DATASOURCE_NAME=${QUICKSIGHT_DATASOURCE_NAME}
EOF
    
    log "Environment setup completed."
    log_info "Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Deployment ID: ${DEPLOYMENT_ID}"
}

# =============================================================================
# IOT SITEWISE DEPLOYMENT
# =============================================================================

deploy_iot_sitewise() {
    log "Deploying IoT SiteWise Asset Model..."
    
    # Create asset model definition
    cat > "${SCRIPT_DIR}/manufacturing-equipment-model.json" << 'EOF'
{
  "assetModelName": "SustainableManufacturingModel",
  "assetModelDescription": "Asset model for sustainable manufacturing monitoring",
  "assetModelProperties": [
    {
      "name": "Equipment_Serial_Number",
      "dataType": "STRING",
      "type": {
        "attribute": {
          "defaultValue": "UNKNOWN"
        }
      }
    },
    {
      "name": "Power_Consumption_kW",
      "dataType": "DOUBLE",
      "unit": "kW",
      "type": {
        "measurement": {}
      }
    },
    {
      "name": "Production_Rate_Units_Hour",
      "dataType": "DOUBLE",
      "unit": "units/hour",
      "type": {
        "measurement": {}
      }
    },
    {
      "name": "Energy_Efficiency_Ratio",
      "dataType": "DOUBLE",
      "unit": "units/kWh",
      "type": {
        "transform": {
          "expression": "production_rate / power_consumption",
          "variables": [
            {
              "name": "production_rate",
              "value": {
                "propertyId": "Production_Rate_Units_Hour"
              }
            },
            {
              "name": "power_consumption",
              "value": {
                "propertyId": "Power_Consumption_kW"
              }
            }
          ]
        }
      }
    },
    {
      "name": "Total_Energy_Consumption_kWh",
      "dataType": "DOUBLE",
      "unit": "kWh",
      "type": {
        "metric": {
          "expression": "sum(power)",
          "variables": [
            {
              "name": "power",
              "value": {
                "propertyId": "Power_Consumption_kW"
              }
            }
          ],
          "window": {
            "tumbling": {
              "interval": "1h"
            }
          }
        }
      }
    }
  ]
}
EOF
    
    # Create asset model
    ASSET_MODEL_RESPONSE=$(aws iotsitewise create-asset-model \
        --cli-input-json file://"${SCRIPT_DIR}/manufacturing-equipment-model.json")
    
    ASSET_MODEL_ID=$(echo "${ASSET_MODEL_RESPONSE}" | jq -r '.assetModelId')
    
    if [[ -z "${ASSET_MODEL_ID}" || "${ASSET_MODEL_ID}" == "null" ]]; then
        log_error "Failed to create IoT SiteWise asset model."
        exit 1
    fi
    
    # Save to state file
    echo "ASSET_MODEL_ID=${ASSET_MODEL_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log "Asset model created successfully: ${ASSET_MODEL_ID}"
    
    # Wait for asset model to be active
    log_info "Waiting for asset model to become active..."
    aws iotsitewise wait asset-model-active --asset-model-id "${ASSET_MODEL_ID}"
    
    # Create manufacturing equipment assets
    log "Creating manufacturing equipment assets..."
    
    # Create first asset
    EQUIPMENT_1_RESPONSE=$(aws iotsitewise create-asset \
        --asset-model-id "${ASSET_MODEL_ID}" \
        --asset-name "Production_Line_A_Extruder")
    
    EQUIPMENT_1_ID=$(echo "${EQUIPMENT_1_RESPONSE}" | jq -r '.assetId')
    
    # Create second asset
    EQUIPMENT_2_RESPONSE=$(aws iotsitewise create-asset \
        --asset-model-id "${ASSET_MODEL_ID}" \
        --asset-name "Production_Line_B_Injection_Molding")
    
    EQUIPMENT_2_ID=$(echo "${EQUIPMENT_2_RESPONSE}" | jq -r '.assetId')
    
    # Save to state file
    echo "EQUIPMENT_1_ID=${EQUIPMENT_1_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    echo "EQUIPMENT_2_ID=${EQUIPMENT_2_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log "Equipment assets created successfully."
    log_info "Equipment 1 ID: ${EQUIPMENT_1_ID}"
    log_info "Equipment 2 ID: ${EQUIPMENT_2_ID}"
    
    # Wait for assets to be active
    log_info "Waiting for assets to become active..."
    aws iotsitewise wait asset-active --asset-id "${EQUIPMENT_1_ID}"
    aws iotsitewise wait asset-active --asset-id "${EQUIPMENT_2_ID}"
    
    log "IoT SiteWise deployment completed successfully."
}

# =============================================================================
# LAMBDA DEPLOYMENT
# =============================================================================

deploy_lambda() {
    log "Deploying Lambda function for carbon calculations..."
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/carbon-calculator.py" << 'EOF'
import json
import boto3
import datetime
from decimal import Decimal

def lambda_handler(event, context):
    # Carbon intensity factors (kg CO2 per kWh) by region
    CARBON_INTENSITY_FACTORS = {
        'us-east-1': 0.393,    # Virginia
        'us-west-2': 0.295,    # Oregon  
        'eu-west-1': 0.316,    # Ireland
        'ap-northeast-1': 0.518 # Tokyo
    }
    
    sitewise = boto3.client('iotsitewise')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Get current energy consumption from IoT SiteWise
        asset_id = event.get('asset_id')
        if not asset_id:
            return {
                'statusCode': 400,
                'body': json.dumps('Asset ID required')
            }
        
        # Get asset properties first to find the correct property ID
        asset_properties = sitewise.describe_asset(
            assetId=asset_id
        )
        
        # Find Power_Consumption_kW property ID
        power_property_id = None
        for prop in asset_properties['assetProperties']:
            if prop['name'] == 'Power_Consumption_kW':
                power_property_id = prop['id']
                break
        
        if not power_property_id:
            return {
                'statusCode': 400,
                'body': json.dumps('Power consumption property not found')
            }
        
        # Get latest power consumption value
        response = sitewise.get_asset_property_value(
            assetId=asset_id,
            propertyId=power_property_id
        )
        
        power_consumption = response['propertyValue']['value']['doubleValue']
        
        # Calculate carbon emissions
        region = context.invoked_function_arn.split(':')[3]
        carbon_factor = CARBON_INTENSITY_FACTORS.get(region, 0.4)
        carbon_emissions = power_consumption * carbon_factor
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Manufacturing/Sustainability',
            MetricData=[
                {
                    'MetricName': 'CarbonEmissions',
                    'Dimensions': [
                        {
                            'Name': 'AssetId',
                            'Value': asset_id
                        }
                    ],
                    'Value': carbon_emissions,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.utcnow()
                },
                {
                    'MetricName': 'PowerConsumption',
                    'Dimensions': [
                        {
                            'Name': 'AssetId',
                            'Value': asset_id
                        }
                    ],
                    'Value': power_consumption,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'carbon_emissions_kg_co2_per_hour': carbon_emissions,
                'power_consumption_kw': power_consumption,
                'carbon_intensity_factor': carbon_factor
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    
    # Create deployment package
    pushd "${SCRIPT_DIR}" > /dev/null
    zip -q carbon-calculator.zip carbon-calculator.py
    popd > /dev/null
    
    # Create IAM role trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" \
        --tags Key=DeploymentId,Value="${DEPLOYMENT_ID}" \
        > /dev/null
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
    
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AWSIoTSiteWiseReadOnlyAccess
    
    # Save role name to state file
    echo "LAMBDA_ROLE_NAME=${ROLE_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --handler carbon-calculator.lambda_handler \
        --zip-file fileb://"${SCRIPT_DIR}/carbon-calculator.zip" \
        --timeout 60 \
        --memory-size 256 \
        --tags DeploymentId="${DEPLOYMENT_ID}" \
        > /dev/null
    
    log "Lambda function created successfully: ${LAMBDA_FUNCTION_NAME}"
}

# =============================================================================
# CLOUDWATCH ALARMS DEPLOYMENT
# =============================================================================

deploy_cloudwatch_alarms() {
    log "Deploying CloudWatch alarms for sustainability monitoring..."
    
    # Create alarm for high carbon emissions
    CARBON_ALARM_NAME="High-Carbon-Emissions-${DEPLOYMENT_ID}"
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CARBON_ALARM_NAME}" \
        --alarm-description "Alert when carbon emissions exceed threshold" \
        --metric-name CarbonEmissions \
        --namespace Manufacturing/Sustainability \
        --statistic Average \
        --period 300 \
        --threshold 50.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --tags Key=DeploymentId,Value="${DEPLOYMENT_ID}"
    
    # Create alarm for energy efficiency
    EFFICIENCY_ALARM_NAME="Low-Energy-Efficiency-${DEPLOYMENT_ID}"
    aws cloudwatch put-metric-alarm \
        --alarm-name "${EFFICIENCY_ALARM_NAME}" \
        --alarm-description "Alert when energy efficiency drops" \
        --metric-name PowerConsumption \
        --namespace Manufacturing/Sustainability \
        --statistic Average \
        --period 300 \
        --threshold 100.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --tags Key=DeploymentId,Value="${DEPLOYMENT_ID}"
    
    # Save alarm names to state file
    echo "CARBON_ALARM_NAME=${CARBON_ALARM_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    echo "EFFICIENCY_ALARM_NAME=${EFFICIENCY_ALARM_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log "CloudWatch alarms created successfully."
}

# =============================================================================
# EVENTBRIDGE SETUP
# =============================================================================

deploy_eventbridge() {
    log "Deploying EventBridge for automated sustainability reporting..."
    
    # Create EventBridge rule for daily reporting
    RULE_NAME="daily-sustainability-report-${DEPLOYMENT_ID}"
    aws events put-rule \
        --name "${RULE_NAME}" \
        --description "Trigger daily sustainability calculations" \
        --schedule-expression "cron(0 8 * * ? *)" \
        --tags Key=DeploymentId,Value="${DEPLOYMENT_ID}"
    
    # Create target for the rule
    aws events put-targets \
        --rule "${RULE_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "daily-sustainability-report" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}" \
        > /dev/null
    
    # Save rule name to state file
    echo "EVENTBRIDGE_RULE_NAME=${RULE_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log "EventBridge rule created successfully: ${RULE_NAME}"
}

# =============================================================================
# SIMULATION AND TESTING
# =============================================================================

simulate_manufacturing_data() {
    log "Simulating manufacturing data for testing..."
    
    # Load equipment IDs from state file
    source "${DEPLOYMENT_STATE_FILE}"
    
    # Create simulation data
    TIMESTAMP=$(date +%s)
    cat > "${SCRIPT_DIR}/simulate-data.json" << EOF
{
  "entries": [
    {
      "entryId": "power-${TIMESTAMP}-1",
      "assetId": "${EQUIPMENT_1_ID}",
      "propertyId": "Power_Consumption_kW",
      "propertyValues": [
        {
          "value": {
            "doubleValue": 75.5
          },
          "timestamp": {
            "timeInSeconds": ${TIMESTAMP}
          },
          "quality": "GOOD"
        }
      ]
    },
    {
      "entryId": "production-${TIMESTAMP}-1",
      "assetId": "${EQUIPMENT_1_ID}",
      "propertyId": "Production_Rate_Units_Hour",
      "propertyValues": [
        {
          "value": {
            "doubleValue": 1250.0
          },
          "timestamp": {
            "timeInSeconds": ${TIMESTAMP}
          },
          "quality": "GOOD"
        }
      ]
    }
  ]
}
EOF
    
    # Send simulated data to IoT SiteWise
    aws iotsitewise batch-put-asset-property-value \
        --cli-input-json file://"${SCRIPT_DIR}/simulate-data.json"
    
    log_info "Simulated data sent to IoT SiteWise."
    
    # Wait for data ingestion
    log_info "Waiting for data ingestion..."
    sleep 30
    
    # Test Lambda function
    log_info "Testing Lambda function..."
    aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload "{\"asset_id\":\"${EQUIPMENT_1_ID}\"}" \
        "${SCRIPT_DIR}/test-response.json" \
        > /dev/null
    
    if [[ -f "${SCRIPT_DIR}/test-response.json" ]]; then
        log_info "Lambda test response:"
        cat "${SCRIPT_DIR}/test-response.json"
    fi
    
    log "Manufacturing data simulation completed."
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    log "Starting AWS IoT SiteWise Sustainable Manufacturing Monitoring deployment..."
    
    # Check if deployment already exists
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warn "Deployment state file exists. This may be a re-deployment."
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
    fi
    
    # Initialize log file
    echo "=== AWS IoT SiteWise Sustainable Manufacturing Monitoring Deployment ===" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    deploy_iot_sitewise
    deploy_lambda
    deploy_cloudwatch_alarms
    deploy_eventbridge
    simulate_manufacturing_data
    
    # Display deployment summary
    log ""
    log "=========================================="
    log "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log "=========================================="
    log ""
    log "Deployment Summary:"
    log "- Region: ${AWS_REGION}"
    log "- Deployment ID: ${DEPLOYMENT_ID}"
    log "- Asset Model ID: ${ASSET_MODEL_ID}"
    log "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "- CloudWatch Alarms: ${CARBON_ALARM_NAME}, ${EFFICIENCY_ALARM_NAME}"
    log "- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log ""
    log "Next Steps:"
    log "1. Monitor CloudWatch metrics in the 'Manufacturing/Sustainability' namespace"
    log "2. Check CloudWatch alarms for sustainability threshold violations"
    log "3. Configure QuickSight dashboards for sustainability reporting"
    log "4. Set up additional equipment assets as needed"
    log ""
    log "For cleanup, run: ./destroy.sh"
    log ""
    
    # Save deployment completion time
    echo "DEPLOYMENT_COMPLETED_AT=$(date)" >> "${DEPLOYMENT_STATE_FILE}"
    
    log "Deployment completed successfully! Check ${LOG_FILE} for detailed logs."
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi