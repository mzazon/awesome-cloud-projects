#!/usr/bin/env python3
"""
Weather Alert Notifications CDK Application

This CDK application deploys a serverless weather monitoring system using:
- AWS Lambda for weather data processing
- Amazon SNS for alert notifications  
- Amazon EventBridge for scheduled execution
- IAM roles with least privilege permissions

The system periodically checks weather conditions and sends alerts when
thresholds are exceeded for temperature or wind speed.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class WeatherAlertStack(Stack):
    """
    CDK Stack for Weather Alert Notifications System
    
    Creates all necessary AWS resources for automated weather monitoring
    including Lambda function, SNS topic, EventBridge rule, and IAM permissions.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        city: str = "Seattle",
        temp_threshold: float = 32.0,
        wind_threshold: float = 25.0,
        schedule_expression: str = "rate(1 hour)",
        notification_email: Optional[str] = None,
        weather_api_key: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Weather Alert Stack
        
        Args:
            scope: CDK app scope
            construct_id: Unique identifier for this stack
            city: City to monitor for weather conditions
            temp_threshold: Temperature threshold in Fahrenheit for alerts
            wind_threshold: Wind speed threshold in mph for alerts  
            schedule_expression: EventBridge schedule expression
            notification_email: Email address for notifications
            weather_api_key: OpenWeatherMap API key
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for weather notifications
        self.sns_topic = sns.Topic(
            self,
            "WeatherNotificationsTopic",
            display_name="Weather Alert Notifications",
            topic_name=f"weather-notifications-{construct_id.lower()}",
        )

        # Add email subscription if provided
        if notification_email:
            sns.Subscription(
                self,
                "EmailSubscription", 
                topic=self.sns_topic,
                protocol=sns.SubscriptionProtocol.EMAIL,
                endpoint=notification_email,
            )

        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "WeatherLambdaRole",
            role_name=f"weather-lambda-role-{construct_id.lower()}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "SNSPublishPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.sns_topic.topic_arn],
                        )
                    ]
                )
            },
        )

        # Create CloudWatch Log Group for Lambda function
        log_group = logs.LogGroup(
            self,
            "WeatherLambdaLogGroup",
            log_group_name=f"/aws/lambda/weather-alerts-{construct_id.lower()}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda function for weather monitoring
        self.weather_function = _lambda.Function(
            self,
            "WeatherAlertFunction",
            function_name=f"weather-alerts-{construct_id.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            role=lambda_role,
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "CITY": city,
                "TEMP_THRESHOLD": str(temp_threshold),
                "WIND_THRESHOLD": str(wind_threshold),
                "WEATHER_API_KEY": weather_api_key or "demo_key",
            },
            log_group=log_group,
            description="Monitors weather conditions and sends alerts via SNS",
        )

        # Create EventBridge rule for scheduled execution
        self.schedule_rule = events.Rule(
            self,
            "WeatherCheckSchedule",
            rule_name=f"weather-check-schedule-{construct_id.lower()}",
            description="Triggers weather monitoring function on schedule",
            schedule=events.Schedule.expression(schedule_expression),
            enabled=True,
        )

        # Add Lambda function as target for EventBridge rule
        self.schedule_rule.add_target(
            targets.LambdaFunction(
                self.weather_function,
                retry_attempts=2,
            )
        )

        # Output important resource information
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for weather notifications",
            value=self.sns_topic.topic_arn,
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName", 
            description="Name of the weather monitoring Lambda function",
            value=self.weather_function.function_name,
        )

        cdk.CfnOutput(
            self,
            "EventBridgeRuleName",
            description="Name of the EventBridge rule for scheduling",
            value=self.schedule_rule.rule_name,
        )

        cdk.CfnOutput(
            self,
            "MonitoredCity",
            description="City being monitored for weather conditions",
            value=city,
        )

        cdk.CfnOutput(
            self,
            "AlertThresholds",
            description="Weather alert thresholds configured",
            value=f"Temperature: {temp_threshold}°F, Wind: {wind_threshold} mph",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string
        
        Returns:
            Complete Lambda function code for weather monitoring
        """
        return '''import json
import requests
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    AWS Lambda handler for weather alert monitoring
    
    Fetches weather data from OpenWeatherMap API and sends SNS alerts
    when temperature or wind speed thresholds are exceeded.
    """
    # Initialize SNS client
    sns = boto3.client('sns')
    
    # Configuration from environment variables
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
""" + '\\n'.join(f"• {alert}" for alert in alerts) + """

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
'''


class WeatherAlertApp(cdk.App):
    """
    CDK Application for Weather Alert Notifications
    
    Creates the main application with configurable parameters for
    weather monitoring thresholds and notification settings.
    """

    def __init__(self) -> None:
        """Initialize the CDK application"""
        super().__init__()

        # Get configuration from environment variables or use defaults
        city = os.environ.get("WEATHER_CITY", "Seattle")
        temp_threshold = float(os.environ.get("WEATHER_TEMP_THRESHOLD", "32"))
        wind_threshold = float(os.environ.get("WEATHER_WIND_THRESHOLD", "25"))
        schedule = os.environ.get("WEATHER_SCHEDULE", "rate(1 hour)")
        notification_email = os.environ.get("NOTIFICATION_EMAIL")
        weather_api_key = os.environ.get("WEATHER_API_KEY")

        # Create the weather alert stack
        WeatherAlertStack(
            self,
            "WeatherAlertStack",
            city=city,
            temp_threshold=temp_threshold,
            wind_threshold=wind_threshold,
            schedule_expression=schedule,
            notification_email=notification_email,
            weather_api_key=weather_api_key,
            description="Serverless weather monitoring system with SNS alerts",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create and run the CDK application
app = WeatherAlertApp()
app.synth()