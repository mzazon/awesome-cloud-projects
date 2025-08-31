#!/bin/bash

# Weather Alert Notifications Deployment Script
# This script deploys AWS Lambda, SNS, EventBridge, and IAM resources for weather monitoring

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required tools
    for tool in jq python3 zip; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    export FUNCTION_NAME="weather-alerts-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="weather-notifications-${RANDOM_SUFFIX}"
    export ROLE_NAME="weather-lambda-role-${RANDOM_SUFFIX}"
    export RULE_NAME="weather-check-schedule-${RANDOM_SUFFIX}"
    
    # Store resource names for cleanup
    cat > weather-resources.env << EOF
export FUNCTION_NAME="${FUNCTION_NAME}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export ROLE_NAME="${ROLE_NAME}"
export RULE_NAME="${RULE_NAME}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF
    
    success "Environment variables configured"
    log "Resource names:"
    log "  Function: ${FUNCTION_NAME}"
    log "  SNS Topic: ${SNS_TOPIC_NAME}"
    log "  IAM Role: ${ROLE_NAME}"
    log "  EventBridge Rule: ${RULE_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
    cat > trust-policy.json << 'EOF'
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document file://trust-policy.json \
            --tags Key=Project,Value=WeatherAlerts Key=ManagedBy,Value=BashScript
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        success "IAM role created: ${ROLE_NAME}"
    fi
    
    # Clean up temporary file
    rm -f trust-policy.json
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --tags Key=Project,Value=WeatherAlerts Key=ManagedBy,Value=BashScript \
        --query TopicArn --output text)
    
    export SNS_TOPIC_ARN
    echo "export SNS_TOPIC_ARN=\"${SNS_TOPIC_ARN}\"" >> weather-resources.env
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Prompt for email subscription
    if [ -z "$EMAIL_ADDRESS" ]; then
        echo -n "Enter your email address for notifications (optional, press Enter to skip): "
        read EMAIL_ADDRESS
    fi
    
    if [ -n "$EMAIL_ADDRESS" ]; then
        log "Creating email subscription..."
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}"
        
        warning "Please check your email and confirm the subscription"
    else
        warning "No email address provided. You can subscribe later using the AWS console"
    fi
}

# Function to create SNS policy for Lambda
create_sns_policy() {
    log "Creating SNS publish policy for Lambda..."
    
    # Create SNS publish policy
    cat > sns-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "${SNS_TOPIC_ARN}"
    }
  ]
}
EOF
    
    # Create and attach the policy
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name SNSPublishPolicy \
        --policy-document file://sns-policy.json
    
    success "SNS publish permissions granted to Lambda role"
    
    # Clean up temporary file
    rm -f sns-policy.json
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create temporary directory for Lambda code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import requests
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    # Initialize SNS client
    sns = boto3.client('sns')
    
    # Configuration
    api_key = os.environ.get('WEATHER_API_KEY', 'demo_key')
    city = os.environ.get('CITY', 'Seattle')
    temp_threshold = float(os.environ.get('TEMP_THRESHOLD', '32'))  # Fahrenheit
    wind_threshold = float(os.environ.get('WIND_THRESHOLD', '25'))  # mph
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Fetch weather data
        if api_key == 'demo_key':
            # For demo purposes, use mock data if no API key provided
            weather_data = {
                'main': {'temp': 28.5, 'feels_like': 25.0},
                'wind': {'speed': 30.2},
                'weather': [{'main': 'Snow', 'description': 'heavy snow'}],
                'name': city
            }
            print("Using demo weather data for testing")
        else:
            # Make API request to OpenWeatherMap
            url = f'https://api.openweathermap.org/data/2.5/weather'
            params = {
                'q': city,
                'appid': api_key,
                'units': 'imperial'
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            weather_data = response.json()
        
        # Extract weather information
        temperature = weather_data['main']['temp']
        feels_like = weather_data['main']['feels_like']
        wind_speed = weather_data['wind']['speed']
        weather_desc = weather_data['weather'][0]['description']
        city_name = weather_data['name']
        
        print(f"Weather check for {city_name}: {temperature}°F, {weather_desc}, {wind_speed} mph wind")
        
        # Check alert conditions
        alerts = []
        
        if temperature <= temp_threshold:
            alerts.append(f"🥶 Temperature alert: {temperature}°F (feels like {feels_like}°F)")
        
        if wind_speed >= wind_threshold:
            alerts.append(f"💨 Wind alert: {wind_speed} mph")
        
        # Send alerts if conditions met
        if alerts:
            timestamp = datetime.now().strftime('%Y-%m-%d %I:%M %p')
            message = f"""
⚠️ WEATHER ALERT for {city_name} ⚠️
Time: {timestamp}

Current Conditions:
🌡️ Temperature: {temperature}°F (feels like {feels_like}°F)
💨 Wind Speed: {wind_speed} mph
🌤️ Conditions: {weather_desc.title()}

Active Alerts:
""" + '\n'.join(f"• {alert}" for alert in alerts) + """

Stay safe and take appropriate precautions!
"""
            
            # Send SNS notification
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=f"Weather Alert - {city_name}",
                Message=message
            )
            
            print(f"Alert sent: {len(alerts)} conditions triggered")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Weather alert sent',
                    'alerts': alerts,
                    'city': city_name,
                    'temperature': temperature,
                    'wind_speed': wind_speed
                })
            }
        else:
            print("No alerts triggered - weather conditions normal")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Weather normal - no alerts',
                    'city': city_name,
                    'temperature': temperature,
                    'wind_speed': wind_speed
                })
            }
            
    except requests.exceptions.RequestException as e:
        print(f"API request error: {str(e)}")
        error_message = f"""
❌ Weather API Error
Time: {datetime.now().strftime('%Y-%m-%d %I:%M %p')}

Error: Unable to fetch weather data - {str(e)}

Please check API configuration and connectivity.
"""
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject="Weather API Error",
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'API request failed: {str(e)}'})
        }
        
    except Exception as e:
        print(f"Error checking weather: {str(e)}")
        # Send error notification
        error_message = f"""
❌ Weather Monitoring System Error
Time: {datetime.now().strftime('%Y-%m-%d %I:%M %p')}

Error: {str(e)}

Please check the system configuration.
"""
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject="Weather System Error",
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package
    zip -q lambda-function.zip lambda_function.py
    
    # Get role ARN (wait a moment for role propagation)
    log "Waiting for IAM role propagation..."
    sleep 10
    ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Check if function already exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function ${FUNCTION_NAME} already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 30 \
            --memory-size 128 \
            --environment Variables="{
                SNS_TOPIC_ARN=${SNS_TOPIC_ARN},
                CITY=Seattle,
                TEMP_THRESHOLD=32,
                WIND_THRESHOLD=25
            }" \
            --tags Project=WeatherAlerts,ManagedBy=BashScript
    fi
    
    success "Lambda function deployed: ${FUNCTION_NAME}"
    
    # Clean up
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge scheduled rule..."
    
    # Check if rule already exists
    if aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        warning "EventBridge rule ${RULE_NAME} already exists, skipping creation"
    else
        # Create EventBridge rule for hourly execution
        aws events put-rule \
            --name "${RULE_NAME}" \
            --schedule-expression "rate(1 hour)" \
            --description "Hourly weather monitoring trigger" \
            --state ENABLED \
            --tags Key=Project,Value=WeatherAlerts Key=ManagedBy,Value=BashScript
    fi
    
    # Get rule ARN
    RULE_ARN=$(aws events describe-rule --name "${RULE_NAME}" \
        --query Arn --output text)
    
    export RULE_ARN
    echo "export RULE_ARN=\"${RULE_ARN}\"" >> weather-resources.env
    
    success "EventBridge rule created: ${RULE_NAME}"
}

# Function to configure Lambda permissions and targets
configure_lambda_permissions() {
    log "Configuring Lambda permissions and EventBridge targets..."
    
    # Add permission for EventBridge to invoke Lambda (idempotent)
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id weather-schedule-permission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "${RULE_ARN}" 2>/dev/null || \
    warning "Lambda permission already exists or failed to add"
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)
    
    # Add Lambda function as target for EventBridge rule
    aws events put-targets \
        --rule "${RULE_NAME}" \
        --targets "Id=1,Arn=${LAMBDA_ARN}"
    
    success "EventBridge configured to trigger Lambda function"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test Lambda function manually
    log "Invoking Lambda function for testing..."
    aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{}' \
        response.json > /dev/null
    
    if [ -f response.json ]; then
        log "Lambda function response:"
        cat response.json | python3 -m json.tool 2>/dev/null || cat response.json
        rm -f response.json
        success "Lambda function test completed"
    else
        error "Lambda function test failed"
    fi
    
    # Verify EventBridge rule
    log "Verifying EventBridge rule configuration..."
    aws events describe-rule --name "${RULE_NAME}" > /dev/null
    aws events list-targets-by-rule --rule "${RULE_NAME}" > /dev/null
    success "EventBridge rule verification completed"
}

# Function to display deployment summary
display_summary() {
    echo
    echo "=================================="
    success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo
    log "Deployed Resources:"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • EventBridge Rule: ${RULE_NAME}"
    echo "  • Region: ${AWS_REGION}"
    echo
    log "Configuration:"
    echo "  • Schedule: Every hour"
    echo "  • City: Seattle (configurable via environment variable)"
    echo "  • Temperature Threshold: 32°F (configurable)"
    echo "  • Wind Threshold: 25 mph (configurable)"
    echo
    log "Next Steps:"
    echo "  1. If you provided an email, confirm the SNS subscription"
    echo "  2. Optionally update Lambda environment variables with your OpenWeatherMap API key"
    echo "  3. Monitor CloudWatch logs for function execution"
    echo "  4. Customize city and thresholds as needed"
    echo
    log "Resource details saved to: weather-resources.env"
    warning "Keep the weather-resources.env file for cleanup!"
    echo
}

# Main deployment function
main() {
    log "Starting Weather Alert Notifications deployment..."
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_sns_topic
    create_sns_policy
    create_lambda_function
    create_eventbridge_rule
    configure_lambda_permissions
    test_deployment
    display_summary
    
    log "Deployment process completed!"
}

# Handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"