#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  aws_s3 as s3,
  aws_events as events,
  aws_lambda as lambda,
  aws_lambda_nodejs as nodejs,
  aws_sns as sns,
  aws_sns_subscriptions as snsSubscriptions,
  aws_iam as iam,
  aws_logs as logs,
  aws_events_targets as targets,
  aws_s3_notifications as s3Notifications,
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
  Tags
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

/**
 * Props for the Centralized SaaS Security Monitoring Stack
 */
export interface SecurityMonitoringStackProps extends StackProps {
  /**
   * Email address for security alerts
   * @default - No email subscription created
   */
  readonly alertEmail?: string;
  
  /**
   * Environment name for resource naming
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge
 * 
 * This stack creates:
 * - S3 bucket for storing OCSF-formatted security logs from AppFabric
 * - Custom EventBridge event bus for security event routing
 * - Lambda function for intelligent security event processing
 * - SNS topic for multi-channel security alerts
 * - IAM roles and policies following least privilege principles
 */
export class SecurityMonitoringStack extends Stack {
  public readonly securityLogsBucket: s3.Bucket;
  public readonly securityEventBus: events.EventBus;
  public readonly securityProcessor: lambda.Function;
  public readonly securityAlertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: SecurityMonitoringStackProps) {
    super(scope, id, props);

    const environment = props?.environment ?? 'dev';
    
    // Generate unique suffix for resources
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for AppFabric security logs with encryption and versioning
    this.securityLogsBucket = this.createSecurityLogsBucket(uniqueSuffix);

    // Create custom EventBridge event bus for security events
    this.securityEventBus = this.createSecurityEventBus(uniqueSuffix);

    // Create SNS topic for security alerts
    this.securityAlertsTopic = this.createSecurityAlertsTopic(uniqueSuffix, props?.alertEmail);

    // Create Lambda function for security event processing
    this.securityProcessor = this.createSecurityProcessor(uniqueSuffix);

    // Create EventBridge rules for automated event routing
    this.createEventBridgeRules();

    // Create AppFabric IAM service role
    this.createAppFabricServiceRole(uniqueSuffix);

    // Add tags to all resources
    this.addResourceTags(environment);

    // Create CloudFormation outputs
    this.createOutputs();
  }

  /**
   * Creates S3 bucket for storing AppFabric security logs with proper security configurations
   */
  private createSecurityLogsBucket(uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'SecurityLogsBucket', {
      bucketName: `security-logs-${this.account}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      lifecycleRules: [{
        id: 'security-logs-lifecycle',
        enabled: true,
        transitions: [{
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: Duration.days(30)
        }, {
          storageClass: s3.StorageClass.GLACIER,
          transitionAfter: Duration.days(90)
        }]
      }],
      eventBridgeEnabled: true, // Enable EventBridge notifications
      serverAccessLogsPrefix: 'access-logs/'
    });

    // Add CORS configuration for potential web-based access
    bucket.addCorsRule({
      allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.POST],
      allowedOrigins: ['*'],
      allowedHeaders: ['*'],
      maxAge: 3000
    });

    return bucket;
  }

  /**
   * Creates custom EventBridge event bus for security events
   */
  private createSecurityEventBus(uniqueSuffix: string): events.EventBus {
    const eventBus = new events.EventBus(this, 'SecurityEventBus', {
      eventBusName: `security-monitoring-bus-${uniqueSuffix}`,
      description: 'Custom event bus for centralized SaaS security monitoring'
    });

    // Create CloudWatch log group for EventBridge events
    new logs.LogGroup(this, 'SecurityEventBusLogGroup', {
      logGroupName: `/aws/events/security-monitoring-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    return eventBus;
  }

  /**
   * Creates SNS topic for security alerts with optional email subscription
   */
  private createSecurityAlertsTopic(uniqueSuffix: string, alertEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `security-alerts-${uniqueSuffix}`,
      displayName: 'SaaS Security Monitoring Alerts',
      fifo: false
    });

    // Add email subscription if provided
    if (alertEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }

    return topic;
  }

  /**
   * Creates Lambda function for security event processing with proper IAM permissions
   */
  private createSecurityProcessor(uniqueSuffix: string): lambda.Function {
    // Create Lambda execution role with necessary permissions
    const lambdaRole = new iam.Role(this, 'SecurityProcessorRole', {
      roleName: `SecurityProcessorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add permissions to read from S3 bucket
    this.securityLogsBucket.grantRead(lambdaRole);

    // Add permissions to publish to SNS topic
    this.securityAlertsTopic.grantPublish(lambdaRole);

    // Create the Lambda function with inline code
    const securityProcessor = new lambda.Function(this, 'SecurityProcessor', {
      functionName: `security-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: this.securityAlertsTopic.topicArn,
        S3_BUCKET_NAME: this.securityLogsBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
import re
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Process security events from AppFabric and generate alerts"""
    
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Parse S3 event from EventBridge
        if 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    process_s3_security_log(record)
        
        # Process direct EventBridge events
        elif 'source' in event:
            process_eventbridge_event(event)
        
        # Process S3 events delivered via EventBridge
        elif 'detail' in event and 'bucket' in event['detail']:
            process_s3_eventbridge_event(event)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Security events processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}")
        # Send error alert
        send_error_alert(str(e))
        raise

def process_s3_security_log(s3_record):
    """Process security logs uploaded to S3 by AppFabric"""
    
    bucket = s3_record['s3']['bucket']['name']
    key = s3_record['s3']['object']['key']
    
    logger.info(f"Processing security log: s3://{bucket}/{key}")
    
    try:
        # Download and analyze the security log
        response = s3.get_object(Bucket=bucket, Key=key)
        log_content = response['Body'].read().decode('utf-8')
        
        # Parse OCSF formatted logs
        security_events = parse_ocsf_logs(log_content)
        
        # Apply threat detection logic
        for security_event in security_events:
            if is_suspicious_activity(security_event):
                alert_message = {
                    'alert_type': 'SUSPICIOUS_ACTIVITY_DETECTED',
                    'application': extract_app_name(key),
                    'timestamp': datetime.utcnow().isoformat(),
                    's3_location': f"s3://{bucket}/{key}",
                    'severity': determine_severity(security_event),
                    'event_details': security_event
                }
                send_security_alert(alert_message)
        
    except Exception as e:
        logger.error(f"Error processing S3 security log {key}: {str(e)}")

def process_s3_eventbridge_event(event):
    """Process S3 events delivered via EventBridge"""
    
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name', '')
    key = detail.get('object', {}).get('key', '')
    
    if bucket and key:
        logger.info(f"Processing EventBridge S3 event: s3://{bucket}/{key}")
        
        alert_message = {
            'alert_type': 'NEW_SECURITY_LOG',
            'application': extract_app_name(key),
            'timestamp': datetime.utcnow().isoformat(),
            's3_location': f"s3://{bucket}/{key}",
            'severity': 'INFO'
        }
        
        send_security_alert(alert_message)

def process_eventbridge_event(event):
    """Process custom security events from EventBridge"""
    
    event_type = event.get('detail-type', 'Unknown')
    source = event.get('source', 'Unknown')
    
    logger.info(f"Processing EventBridge event: {event_type} from {source}")
    
    # Apply threat detection logic based on event patterns
    if is_suspicious_activity(event):
        alert_message = {
            'alert_type': 'SUSPICIOUS_ACTIVITY',
            'event_type': event_type,
            'source': source,
            'timestamp': datetime.utcnow().isoformat(),
            'severity': 'HIGH',
            'details': event.get('detail', {})
        }
        
        send_security_alert(alert_message)

def parse_ocsf_logs(log_content):
    """Parse OCSF formatted security logs"""
    
    try:
        # Handle both single events and arrays
        if log_content.strip().startswith('['):
            return json.loads(log_content)
        else:
            return [json.loads(log_content)]
    except json.JSONDecodeError:
        # Handle NDJSON format (newline-delimited JSON)
        events = []
        for line in log_content.strip().split('\\n'):
            if line:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    logger.warning(f"Failed to parse log line: {line}")
        return events

def is_suspicious_activity(event):
    """Apply threat detection logic to identify suspicious activities"""
    
    # Convert event to string for pattern matching
    event_str = json.dumps(event).lower()
    
    # Define suspicious activity patterns
    suspicious_patterns = [
        'failed.*login',
        'authentication.*failed',
        'privilege.*escalation',
        'unusual.*access',
        'data.*exfiltration',
        'malware.*detected',
        'brute.*force',
        'unauthorized.*access',
        'security.*violation',
        'anomalous.*behavior'
    ]
    
    # Check for suspicious patterns
    for pattern in suspicious_patterns:
        if re.search(pattern, event_str):
            logger.info(f"Suspicious pattern detected: {pattern}")
            return True
    
    # Check OCSF severity levels
    if isinstance(event, dict):
        severity_id = event.get('severity_id', 0)
        if severity_id >= 4:  # High or Critical severity in OCSF
            return True
        
        # Check for specific OCSF class UIDs indicating security events
        class_uid = event.get('class_uid', 0)
        security_class_uids = [3001, 3002, 3003, 4001, 4002, 6001, 6002]
        if class_uid in security_class_uids:
            return True
    
    return False

def determine_severity(event):
    """Determine alert severity based on event characteristics"""
    
    if isinstance(event, dict):
        severity_id = event.get('severity_id', 1)
        severity_mapping = {
            1: 'INFO',
            2: 'LOW',
            3: 'MEDIUM',
            4: 'HIGH',
            5: 'CRITICAL'
        }
        return severity_mapping.get(severity_id, 'MEDIUM')
    
    return 'MEDIUM'

def extract_app_name(s3_key):
    """Extract application name from S3 key path"""
    
    # AppFabric S3 key format: app-bundle-id/app-name/yyyy/mm/dd/file
    path_parts = s3_key.split('/')
    if len(path_parts) > 1:
        return path_parts[1]
    return 'unknown'

def send_security_alert(alert_message):
    """Send security alert via SNS"""
    
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Format message for different delivery methods
    message = {
        'default': json.dumps(alert_message, indent=2),
        'email': format_email_alert(alert_message),
        'sms': format_sms_alert(alert_message)
    }
    
    try:
        response = sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message),
            MessageStructure='json',
            Subject=f"Security Alert: {alert_message['alert_type']}"
        )
        
        logger.info(f"Security alert sent: {alert_message['alert_type']} - MessageId: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")

def send_error_alert(error_message):
    """Send error alert for Lambda processing failures"""
    
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    alert_message = {
        'alert_type': 'PROCESSING_ERROR',
        'timestamp': datetime.utcnow().isoformat(),
        'severity': 'HIGH',
        'error': error_message
    }
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(alert_message, indent=2),
            Subject='Security Monitoring Processing Error'
        )
    except Exception as e:
        logger.error(f"Failed to send error alert: {str(e)}")

def format_email_alert(alert):
    """Format security alert for email delivery"""
    
    return f"""
Security Alert: {alert['alert_type']}

Severity: {alert['severity']}
Timestamp: {alert['timestamp']}
Application: {alert.get('application', 'N/A')}
Source: {alert.get('source', 'N/A')}

Details:
{json.dumps(alert.get('details', alert.get('event_details', {})), indent=2)}

S3 Location: {alert.get('s3_location', 'N/A')}

This is an automated security alert from your centralized SaaS monitoring system.
Please investigate this alert promptly and take appropriate action.

---
AWS Account: {os.environ.get('AWS_ACCOUNT_ID', 'Unknown')}
Region: {os.environ.get('AWS_REGION', 'Unknown')}
"""

def format_sms_alert(alert):
    """Format security alert for SMS delivery"""
    
    return f"SECURITY ALERT: {alert['alert_type']} - {alert['severity']} severity detected at {alert['timestamp'][:19]}"
      `),
      description: 'Lambda function for processing security events from AppFabric and generating alerts'
    });

    // Create CloudWatch log group with retention
    new logs.LogGroup(this, 'SecurityProcessorLogGroup', {
      logGroupName: `/aws/lambda/${securityProcessor.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    return securityProcessor;
  }

  /**
   * Creates EventBridge rules for automated security event routing
   */
  private createEventBridgeRules(): void {
    // Rule for S3 security log events
    const s3SecurityLogRule = new events.Rule(this, 'S3SecurityLogRule', {
      eventBus: this.securityEventBus,
      ruleName: 'SecurityLogProcessingRule',
      description: 'Route S3 security logs to Lambda processor',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created'],
        detail: {
          bucket: {
            name: [this.securityLogsBucket.bucketName]
          }
        }
      }
    });

    // Add Lambda function as target
    s3SecurityLogRule.addTarget(new targets.LambdaFunction(this.securityProcessor, {
      retryAttempts: 2
    }));

    // Rule for custom security events
    const customSecurityRule = new events.Rule(this, 'CustomSecurityRule', {
      eventBus: this.securityEventBus,
      ruleName: 'CustomSecurityEventRule',
      description: 'Route custom security events to Lambda processor',
      eventPattern: {
        source: ['custom.security'],
        detailType: ['Security Event', 'Threat Detection', 'Anomaly Alert']
      }
    });

    // Add Lambda function as target for custom events
    customSecurityRule.addTarget(new targets.LambdaFunction(this.securityProcessor, {
      retryAttempts: 2
    }));

    // Enable S3 Event Notifications to EventBridge
    this.securityLogsBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3Notifications.EventBridgeDestination(this.securityEventBus)
    );
  }

  /**
   * Creates IAM service role for AppFabric with S3 access permissions
   */
  private createAppFabricServiceRole(uniqueSuffix: string): iam.Role {
    const appFabricRole = new iam.Role(this, 'AppFabricServiceRole', {
      roleName: `AppFabricServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('appfabric.amazonaws.com'),
      description: 'Service role for AWS AppFabric to write security logs to S3'
    });

    // Add S3 permissions policy
    const s3AccessPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutObject',
        's3:PutObjectAcl',
        's3:GetBucketLocation',
        's3:GetBucketVersioning'
      ],
      resources: [
        this.securityLogsBucket.bucketArn,
        `${this.securityLogsBucket.bucketArn}/*`
      ]
    });

    appFabricRole.addToPolicy(s3AccessPolicy);

    return appFabricRole;
  }

  /**
   * Adds common tags to all resources
   */
  private addResourceTags(environment: string): void {
    const commonTags = {
      Purpose: 'SecurityMonitoring',
      Environment: environment,
      Project: 'CentralizedSaaSSecurityMonitoring',
      ManagedBy: 'CDK'
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      Tags.of(this).add(key, value);
    });
  }

  /**
   * Creates CloudFormation outputs for important resource ARNs and configurations
   */
  private createOutputs(): void {
    new CfnOutput(this, 'SecurityLogsBucketName', {
      value: this.securityLogsBucket.bucketName,
      description: 'Name of the S3 bucket for AppFabric security logs',
      exportName: `${this.stackName}-SecurityLogsBucket`
    });

    new CfnOutput(this, 'SecurityLogsBucketArn', {
      value: this.securityLogsBucket.bucketArn,
      description: 'ARN of the S3 bucket for AppFabric security logs'
    });

    new CfnOutput(this, 'SecurityEventBusName', {
      value: this.securityEventBus.eventBusName,
      description: 'Name of the custom EventBridge event bus for security events',
      exportName: `${this.stackName}-SecurityEventBus`
    });

    new CfnOutput(this, 'SecurityEventBusArn', {
      value: this.securityEventBus.eventBusArn,
      description: 'ARN of the custom EventBridge event bus for security events'
    });

    new CfnOutput(this, 'SecurityProcessorFunctionName', {
      value: this.securityProcessor.functionName,
      description: 'Name of the Lambda function for security event processing',
      exportName: `${this.stackName}-SecurityProcessor`
    });

    new CfnOutput(this, 'SecurityProcessorFunctionArn', {
      value: this.securityProcessor.functionArn,
      description: 'ARN of the Lambda function for security event processing'
    });

    new CfnOutput(this, 'SecurityAlertsTopicName', {
      value: this.securityAlertsTopic.topicName,
      description: 'Name of the SNS topic for security alerts',
      exportName: `${this.stackName}-SecurityAlertsTopic`
    });

    new CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: this.securityAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for security alerts'
    });
  }
}

// Create the CDK application
const app = new cdk.App();

// Get configuration from CDK context
const alertEmail = app.node.tryGetContext('alertEmail');
const environment = app.node.tryGetContext('environment') || 'dev';

// Create the main stack
new SecurityMonitoringStack(app, 'CentralizedSaaSSecurityMonitoringStack', {
  alertEmail,
  environment,
  description: 'Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the CloudFormation templates
app.synth();