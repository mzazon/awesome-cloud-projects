# Main Terraform configuration for Weather Alert Notifications
# This configuration creates a serverless weather monitoring system using
# AWS Lambda, SNS, EventBridge, and supporting services

# Data sources for AWS account information and caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = lower(random_id.suffix.hex)
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    },
    var.tags
  )
}

# ==============================================================================
# CloudWatch Log Group for Lambda Function
# ==============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-${local.name_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-logs-${local.name_suffix}"
    Description = "CloudWatch logs for weather monitoring Lambda function"
  })
}

# ==============================================================================
# SNS Topic for Weather Notifications
# ==============================================================================

resource "aws_sns_topic" "weather_notifications" {
  name = "${local.name_prefix}-notifications-${local.name_suffix}"

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-notifications-${local.name_suffix}"
    Description = "SNS topic for weather alert notifications"
  })
}

# SNS Topic Policy to allow Lambda to publish messages
resource "aws_sns_topic_policy" "weather_notifications_policy" {
  arn = aws_sns_topic.weather_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.weather_notifications.arn
      }
    ]
  })
}

# Optional email subscription if email is provided
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.weather_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# IAM Role and Policies for Lambda Function
# ==============================================================================

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-role-${local.name_suffix}"
    Description = "IAM role for weather monitoring Lambda function"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for SNS publishing permissions
resource "aws_iam_role_policy" "lambda_sns_policy" {
  name = "${local.name_prefix}-lambda-sns-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.weather_notifications.arn
      }
    ]
  })
}

# ==============================================================================
# Lambda Function
# ==============================================================================

# Create Lambda function code as a local file
resource "local_file" "lambda_code" {
  content = <<-EOF
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

  filename = "${path.module}/lambda_function.py"
}

# Create deployment package for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_code]
}

# Lambda function resource
resource "aws_lambda_function" "weather_checker" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables for Lambda function
  environment {
    variables = {
      SNS_TOPIC_ARN    = aws_sns_topic.weather_notifications.arn
      CITY             = var.city
      TEMP_THRESHOLD   = tostring(var.temperature_threshold)
      WIND_THRESHOLD   = tostring(var.wind_threshold)
      WEATHER_API_KEY  = var.weather_api_key
    }
  }

  # Ensure CloudWatch log group exists before function
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-weather-checker-${local.name_suffix}"
    Description = "Lambda function for weather monitoring and alerts"
  })
}

# ==============================================================================
# EventBridge Rule for Scheduled Execution
# ==============================================================================

resource "aws_cloudwatch_event_rule" "weather_schedule" {
  name                = "${local.name_prefix}-schedule-${local.name_suffix}"
  description         = "Scheduled trigger for weather monitoring"
  schedule_expression = var.schedule_expression
  state              = "ENABLED"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-schedule-${local.name_suffix}"
    Description = "EventBridge rule for scheduled weather checks"
  })
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.weather_schedule.name
  target_id = "WeatherCheckerLambdaTarget"
  arn       = aws_lambda_function.weather_checker.arn
}

# Permission for EventBridge to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_schedule.arn
}

# ==============================================================================
# CloudWatch Alarms for Monitoring (Optional)
# ==============================================================================

# Alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.weather_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.weather_checker.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
    Description = "CloudWatch alarm for Lambda function errors"
  })
}

# Alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.name_prefix}-lambda-duration-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "25000" # 25 seconds
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [aws_sns_topic.weather_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.weather_checker.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-duration-${local.name_suffix}"
    Description = "CloudWatch alarm for Lambda function duration"
  })
}