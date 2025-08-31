#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Interface for WeatherAlertStack constructor properties
 */
interface WeatherAlertStackProps extends cdk.StackProps {
  /**
   * City to monitor for weather alerts
   * @default "Seattle"
   */
  readonly city?: string;

  /**
   * Temperature threshold in Fahrenheit for cold weather alerts
   * @default 32
   */
  readonly temperatureThreshold?: number;

  /**
   * Wind speed threshold in mph for high wind alerts
   * @default 25
   */
  readonly windThreshold?: number;

  /**
   * Email address for weather alert notifications
   * If not provided, SNS topic will be created without email subscription
   */
  readonly notificationEmail?: string;

  /**
   * OpenWeatherMap API key for weather data
   * If not provided, function will use demo data
   */
  readonly weatherApiKey?: string;

  /**
   * Schedule expression for weather checks
   * @default "rate(1 hour)"
   */
  readonly scheduleExpression?: string;
}

/**
 * CDK Stack for Weather Alert Notifications
 * 
 * This stack creates a serverless weather monitoring system that:
 * - Checks weather conditions hourly using EventBridge scheduled rules
 * - Processes weather data using AWS Lambda
 * - Sends notifications via Amazon SNS when thresholds are exceeded
 * - Follows AWS Well-Architected Framework principles
 */
export class WeatherAlertStack extends cdk.Stack {
  /**
   * The Lambda function that checks weather conditions
   */
  public readonly weatherCheckFunction: lambda.Function;

  /**
   * The SNS topic for sending weather alerts
   */
  public readonly alertTopic: sns.Topic;

  /**
   * The EventBridge rule for scheduling weather checks
   */
  public readonly scheduleRule: events.Rule;

  constructor(scope: Construct, id: string, props: WeatherAlertStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const city = props.city ?? 'Seattle';
    const temperatureThreshold = props.temperatureThreshold ?? 32;
    const windThreshold = props.windThreshold ?? 25;
    const scheduleExpression = props.scheduleExpression ?? 'rate(1 hour)';

    // Create SNS topic for weather alerts
    this.alertTopic = new sns.Topic(this, 'WeatherAlertTopic', {
      displayName: 'Weather Alert Notifications',
      description: 'Topic for sending weather alert notifications when thresholds are exceeded',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.alertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'WeatherCheckLogGroup', {
      logGroupName: `/aws/lambda/weather-alerts-${cdk.Stack.of(this).region}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'WeatherCheckRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for weather monitoring Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SNSPublishPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.alertTopic.topicArn],
            }),
          ],
        }),
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for weather monitoring
    this.weatherCheckFunction = new lambda.Function(this, 'WeatherCheckFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      description: 'Monitors weather conditions and sends alerts when thresholds are exceeded',
      logGroup: logGroup,
      environment: {
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
        CITY: city,
        TEMP_THRESHOLD: temperatureThreshold.toString(),
        WIND_THRESHOLD: windThreshold.toString(),
        ...(props.weatherApiKey && { WEATHER_API_KEY: props.weatherApiKey }),
      },
      code: lambda.Code.fromInline(`
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
`),
    });

    // Create EventBridge rule for scheduled execution
    this.scheduleRule = new events.Rule(this, 'WeatherCheckSchedule', {
      schedule: events.Schedule.expression(scheduleExpression),
      description: 'Triggers weather monitoring Lambda function on schedule',
    });

    // Add Lambda function as target for EventBridge rule
    this.scheduleRule.addTarget(new targets.LambdaFunction(this.weatherCheckFunction, {
      retryAttempts: 2,
    }));

    // Add tags to all resources for better resource management
    cdk.Tags.of(this).add('Project', 'WeatherAlertNotifications');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Purpose', 'Weather Monitoring');

    // Output important resource information
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for weather alerts',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.weatherCheckFunction.functionName,
      description: 'Name of the weather monitoring Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: this.scheduleRule.ruleName,
      description: 'Name of the EventBridge rule for scheduling',
      exportName: `${this.stackName}-EventBridgeRuleName`,
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroup', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for Lambda function logs',
      exportName: `${this.stackName}-LogGroupName`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get context values from CDK context or environment variables
const city = app.node.tryGetContext('city') || process.env.CITY || 'Seattle';
const temperatureThreshold = parseInt(
  app.node.tryGetContext('temperatureThreshold') || 
  process.env.TEMP_THRESHOLD || 
  '32'
);
const windThreshold = parseInt(
  app.node.tryGetContext('windThreshold') || 
  process.env.WIND_THRESHOLD || 
  '25'
);
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const weatherApiKey = app.node.tryGetContext('weatherApiKey') || process.env.WEATHER_API_KEY;
const scheduleExpression = app.node.tryGetContext('scheduleExpression') || process.env.SCHEDULE_EXPRESSION || 'rate(1 hour)';

// Create the main stack
new WeatherAlertStack(app, 'WeatherAlertNotifications', {
  description: 'Serverless weather monitoring system with Lambda, SNS, and EventBridge',
  city,
  temperatureThreshold,
  windThreshold,
  notificationEmail,
  weatherApiKey,
  scheduleExpression,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add application-level metadata
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
app.node.setContext('aws:cdk:enable-path-metadata', true);
app.node.setContext('aws:cdk:enable-asset-metadata', true);