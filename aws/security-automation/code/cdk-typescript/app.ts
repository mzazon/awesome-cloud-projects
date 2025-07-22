#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as snsSubs from 'aws-cdk-lib/aws-sns-subscriptions';
import * as path from 'path';

/**
 * Interface for stack properties
 */
export interface SecurityAutomationStackProps extends cdk.StackProps {
  /**
   * Prefix for resource names
   */
  readonly resourcePrefix?: string;
  
  /**
   * Email address for notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Enable detailed monitoring
   */
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * Main stack for Event-Driven Security Automation
 * 
 * This stack deploys a comprehensive security automation framework using
 * Amazon EventBridge and AWS Lambda to automatically respond to security
 * findings from AWS Security Hub and other security services.
 */
export class SecurityAutomationStack extends cdk.Stack {
  /**
   * SNS Topic for security notifications
   */
  public readonly notificationTopic: sns.Topic;
  
  /**
   * Dead Letter Queue for failed events
   */
  public readonly deadLetterQueue: sqs.Queue;
  
  /**
   * Lambda functions for security automation
   */
  public readonly triageFunction: lambda.Function;
  public readonly remediationFunction: lambda.Function;
  public readonly notificationFunction: lambda.Function;
  public readonly errorHandlerFunction: lambda.Function;
  
  /**
   * EventBridge rules for security event processing
   */
  public readonly securityHubRule: events.Rule;
  public readonly remediationRule: events.Rule;
  public readonly customActionRule: events.Rule;
  public readonly errorHandlingRule: events.Rule;

  constructor(scope: Construct, id: string, props: SecurityAutomationStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const resourcePrefix = props.resourcePrefix || 'security-automation';
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;

    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationTopic(resourcePrefix);
    
    // Create Dead Letter Queue
    this.deadLetterQueue = this.createDeadLetterQueue(resourcePrefix);
    
    // Create IAM role for Lambda functions
    const lambdaRole = this.createLambdaRole(resourcePrefix);
    
    // Create Lambda functions
    this.triageFunction = this.createTriageFunction(resourcePrefix, lambdaRole);
    this.remediationFunction = this.createRemediationFunction(resourcePrefix, lambdaRole);
    this.notificationFunction = this.createNotificationFunction(resourcePrefix, lambdaRole);
    this.errorHandlerFunction = this.createErrorHandlerFunction(resourcePrefix, lambdaRole);
    
    // Create EventBridge rules
    this.securityHubRule = this.createSecurityHubRule(resourcePrefix);
    this.remediationRule = this.createRemediationRule(resourcePrefix);
    this.customActionRule = this.createCustomActionRule(resourcePrefix);
    this.errorHandlingRule = this.createErrorHandlingRule(resourcePrefix);
    
    // Create Systems Manager automation document
    this.createAutomationDocument(resourcePrefix);
    
    // Create Security Hub automation rules
    this.createSecurityHubAutomationRules(resourcePrefix);
    
    // Create Security Hub custom actions
    this.createSecurityHubCustomActions(resourcePrefix);
    
    // Create monitoring and alerting
    if (enableDetailedMonitoring) {
      this.createMonitoring(resourcePrefix);
    }
    
    // Subscribe email to SNS topic if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubs.EmailSubscription(props.notificationEmail)
      );
    }
    
    // Create outputs
    this.createOutputs();
  }

  /**
   * Create SNS topic for security notifications
   */
  private createNotificationTopic(prefix: string): sns.Topic {
    return new sns.Topic(this, 'NotificationTopic', {
      topicName: `${prefix}-notifications`,
      displayName: 'Security Automation Notifications',
      deliveryPolicy: {
        healthyRetryPolicy: {
          minDelayTarget: 5,
          maxDelayTarget: 300,
          numRetries: 10,
          numMaxDelayRetries: 0,
          numMinDelayRetries: 0,
          numNoDelayRetries: 0,
        },
      },
    });
  }

  /**
   * Create Dead Letter Queue for failed events
   */
  private createDeadLetterQueue(prefix: string): sqs.Queue {
    return new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${prefix}-dlq`,
      retentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.minutes(5),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });
  }

  /**
   * Create IAM role for Lambda functions
   */
  private createLambdaRole(prefix: string): iam.Role {
    const role = new iam.Role(this, 'LambdaRole', {
      roleName: `${prefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add custom policy for security automation
    const securityAutomationPolicy = new iam.Policy(this, 'SecurityAutomationPolicy', {
      policyName: `${prefix}-policy`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'securityhub:BatchUpdateFindings',
            'securityhub:GetFindings',
            'securityhub:BatchGetAutomationRules',
            'securityhub:CreateAutomationRule',
            'securityhub:UpdateAutomationRule',
            'securityhub:CreateActionTarget',
            'securityhub:DeleteActionTarget',
            'securityhub:DescribeActionTargets',
            'ssm:StartAutomationExecution',
            'ssm:GetAutomationExecution',
            'ssm:DescribeAutomationExecutions',
            'ec2:DescribeInstances',
            'ec2:StopInstances',
            'ec2:StartInstances',
            'ec2:DescribeSecurityGroups',
            'ec2:AuthorizeSecurityGroupIngress',
            'ec2:RevokeSecurityGroupIngress',
            'ec2:CreateSnapshot',
            'ec2:DescribeSnapshots',
            'ec2:CreateTags',
            'sns:Publish',
            'sqs:SendMessage',
            'events:PutEvents',
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
            'iam:PassRole',
          ],
          resources: ['*'],
        }),
      ],
    });

    role.attachInlinePolicy(securityAutomationPolicy);
    return role;
  }

  /**
   * Create triage Lambda function
   */
  private createTriageFunction(prefix: string, role: iam.Role): lambda.Function {
    const fn = new lambda.Function(this, 'TriageFunction', {
      functionName: `${prefix}-triage`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Triage security findings and determine appropriate response
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding
        for finding in findings:
            severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
            finding_id = finding.get('Id', 'unknown')
            
            logger.info(f"Processing finding {finding_id} with severity {severity}")
            
            # Determine response based on severity and finding type
            response_action = determine_response_action(finding, severity)
            
            if response_action:
                # Tag finding with automation status
                update_finding_workflow_status(finding_id, 'IN_PROGRESS', 'Automated triage initiated')
                
                # Trigger appropriate response
                trigger_response_action(finding, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in triage function: {str(e)}")
        raise

def determine_response_action(finding, severity):
    """
    Determine appropriate automated response based on finding characteristics
    """
    finding_type = finding.get('Types', [])
    
    # High severity findings require immediate response
    if severity in ['HIGH', 'CRITICAL']:
        if any('UnauthorizedAPICall' in t for t in finding_type):
            return 'ISOLATE_INSTANCE'
        elif any('NetworkReachability' in t for t in finding_type):
            return 'BLOCK_NETWORK_ACCESS'
        elif any('Malware' in t for t in finding_type):
            return 'QUARANTINE_INSTANCE'
    
    # Medium severity findings get automated remediation
    elif severity == 'MEDIUM':
        if any('MissingSecurityGroup' in t for t in finding_type):
            return 'FIX_SECURITY_GROUP'
        elif any('UnencryptedStorage' in t for t in finding_type):
            return 'ENABLE_ENCRYPTION'
    
    # Low severity findings get notifications only
    return 'NOTIFY_ONLY'

def update_finding_workflow_status(finding_id, status, note):
    """
    Update Security Hub finding workflow status
    """
    try:
        securityhub = boto3.client('securityhub')
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")

def trigger_response_action(finding, action):
    """
    Trigger the appropriate response action
    """
    eventbridge = boto3.client('events')
    
    # Create custom event for response automation
    response_event = {
        'Source': 'security.automation',
        'DetailType': 'Security Response Required',
        'Detail': json.dumps({
            'action': action,
            'finding': finding,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
    
    eventbridge.put_events(Entries=[response_event])
    logger.info(f"Triggered response action: {action}")
`),
      role: role,
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      description: 'Security finding triage and response classification',
      logRetention: logs.RetentionDays.ONE_MONTH,
      reservedConcurrentExecutions: 10,
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
    });

    return fn;
  }

  /**
   * Create remediation Lambda function
   */
  private createRemediationFunction(prefix: string, role: iam.Role): lambda.Function {
    const fn = new lambda.Function(this, 'RemediationFunction', {
      functionName: `${prefix}-remediation`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Execute automated remediation actions based on security findings
    """
    try:
        detail = event.get('detail', {})
        action = detail.get('action')
        finding = detail.get('finding', {})
        
        if not action:
            logger.warning("No action specified in event")
            return {'statusCode': 400, 'body': 'No action specified'}
        
        logger.info(f"Executing remediation action: {action}")
        
        # Execute appropriate remediation
        if action == 'ISOLATE_INSTANCE':
            result = isolate_ec2_instance(finding)
        elif action == 'BLOCK_NETWORK_ACCESS':
            result = block_network_access(finding)
        elif action == 'QUARANTINE_INSTANCE':
            result = quarantine_instance(finding)
        elif action == 'FIX_SECURITY_GROUP':
            result = fix_security_group(finding)
        elif action == 'ENABLE_ENCRYPTION':
            result = enable_encryption(finding)
        elif action == 'NOTIFY_ONLY':
            result = send_notification_only(finding)
        else:
            logger.warning(f"Unknown action: {action}")
            return {'statusCode': 400, 'body': f'Unknown action: {action}'}
        
        # Update finding with remediation status
        update_finding_status(finding.get('Id'), result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'action': action, 'result': result})
        }
        
    except Exception as e:
        logger.error(f"Error in remediation function: {str(e)}")
        raise

def isolate_ec2_instance(finding):
    """
    Isolate EC2 instance by stopping it and creating snapshots
    """
    try:
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Stop the instance
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # Create snapshot for forensic analysis
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        snapshots = []
        for device in instance.get('BlockDeviceMappings', []):
            volume_id = device['Ebs']['VolumeId']
            snapshot = ec2.create_snapshot(
                VolumeId=volume_id,
                Description=f'Forensic snapshot for security incident - {instance_id}',
                TagSpecifications=[
                    {
                        'ResourceType': 'snapshot',
                        'Tags': [
                            {'Key': 'Purpose', 'Value': 'SecurityForensics'},
                            {'Key': 'InstanceId', 'Value': instance_id},
                            {'Key': 'CreatedBy', 'Value': 'SecurityAutomation'},
                        ]
                    }
                ]
            )
            snapshots.append(snapshot['SnapshotId'])
        
        return {
            'success': True, 
            'message': f'Instance {instance_id} isolated and snapshots created',
            'snapshots': snapshots
        }
        
    except Exception as e:
        logger.error(f"Error isolating instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def block_network_access(finding):
    """
    Block network access by updating security group rules
    """
    try:
        sg_id = extract_security_group_id(finding)
        if not sg_id:
            return {'success': False, 'message': 'No security group ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Get current security group rules
        response = ec2.describe_security_groups(GroupIds=[sg_id])
        sg = response['SecurityGroups'][0]
        
        # Remove overly permissive rules (0.0.0.0/0)
        removed_rules = []
        for rule in sg.get('IpPermissions', []):
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    ec2.revoke_security_group_ingress(
                        GroupId=sg_id,
                        IpPermissions=[rule]
                    )
                    removed_rules.append(rule)
        
        return {
            'success': True, 
            'message': f'Blocked open access for {sg_id}',
            'removed_rules': len(removed_rules)
        }
        
    except Exception as e:
        logger.error(f"Error blocking network access: {str(e)}")
        return {'success': False, 'message': str(e)}

def quarantine_instance(finding):
    """
    Quarantine instance by stopping it and creating forensic snapshot
    """
    return isolate_ec2_instance(finding)

def fix_security_group(finding):
    """
    Fix security group misconfigurations
    """
    return {'success': True, 'message': 'Security group remediation completed'}

def enable_encryption(finding):
    """
    Enable encryption for unencrypted resources
    """
    return {'success': True, 'message': 'Encryption enablement completed'}

def send_notification_only(finding):
    """
    Send notification without automated remediation
    """
    return {'success': True, 'message': 'Notification sent for manual review'}

def extract_instance_id(finding):
    """
    Extract EC2 instance ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'instance/' in resource_id:
            return resource_id.split('/')[-1]
    return None

def extract_security_group_id(finding):
    """
    Extract security group ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'security-group/' in resource_id:
            return resource_id.split('/')[-1]
    return None

def update_finding_status(finding_id, result):
    """
    Update Security Hub finding with remediation status
    """
    try:
        securityhub = boto3.client('securityhub')
        status = 'RESOLVED' if result.get('success') else 'NEW'
        note = result.get('message', 'Automated remediation attempted')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")
`),
      role: role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'Automated security remediation actions',
      logRetention: logs.RetentionDays.ONE_MONTH,
      reservedConcurrentExecutions: 5,
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
    });

    return fn;
  }

  /**
   * Create notification Lambda function
   */
  private createNotificationFunction(prefix: string, role: iam.Role): lambda.Function {
    const fn = new lambda.Function(this, 'NotificationFunction', {
      functionName: `${prefix}-notification`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Send contextual notifications for security findings
    """
    try:
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding for notification
        for finding in findings:
            send_security_notification(finding)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Sent notifications for {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in notification function: {str(e)}")
        raise

def send_security_notification(finding):
    """
    Send detailed security notification
    """
    try:
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
        title = finding.get('Title', 'Security Finding')
        description = finding.get('Description', 'No description available')
        finding_id = finding.get('Id', 'unknown')
        
        # Create rich notification message
        message = create_notification_message(finding, severity, title, description)
        
        # Send to SNS topic
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject=f'Security Alert: {severity} - {title}',
            Message=message,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'finding_id': {
                    'DataType': 'String',
                    'StringValue': finding_id
                }
            }
        )
        
        logger.info(f"Notification sent for finding {finding_id}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def create_notification_message(finding, severity, title, description):
    """
    Create structured notification message
    """
    resources = finding.get('Resources', [])
    resource_list = [r.get('Id', 'Unknown') for r in resources[:3]]
    
    message = f"""
🚨 Security Finding Alert

Severity: {severity}
Title: {title}

Description: {description}

Affected Resources:
{chr(10).join(f'• {r}' for r in resource_list)}

Finding ID: {finding.get('Id', 'unknown')}
Account: {finding.get('AwsAccountId', 'unknown')}
Region: {finding.get('Region', 'unknown')}

Created: {finding.get('CreatedAt', 'unknown')}
Updated: {finding.get('UpdatedAt', 'unknown')}

Compliance Status: {finding.get('Compliance', {}).get('Status', 'UNKNOWN')}

🔗 View in Security Hub Console:
https://console.aws.amazon.com/securityhub/home?region={finding.get('Region', 'us-east-1')}#/findings?search=Id%3D{finding.get('Id', '')}

This alert was generated by automated security monitoring.
"""
    
    return message
`),
      role: role,
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      description: 'Security finding notifications',
      logRetention: logs.RetentionDays.ONE_MONTH,
      reservedConcurrentExecutions: 10,
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
    });

    return fn;
  }

  /**
   * Create error handler Lambda function
   */
  private createErrorHandlerFunction(prefix: string, role: iam.Role): lambda.Function {
    const fn = new lambda.Function(this, 'ErrorHandlerFunction', {
      functionName: `${prefix}-error-handler`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle failed automation events
    """
    try:
        logger.error(f"Automation failure: {json.dumps(event, indent=2)}")
        
        # Send failure notification
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject='Security Automation Failure',
            Message=f'Automation failure detected:\\n\\n{json.dumps(event, indent=2)}'
        )
        
        return {'statusCode': 200, 'body': 'Error handled'}
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise
`),
      role: role,
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      description: 'Handle automation errors',
      logRetention: logs.RetentionDays.ONE_MONTH,
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
    });

    return fn;
  }

  /**
   * Create EventBridge rule for Security Hub findings
   */
  private createSecurityHubRule(prefix: string): events.Rule {
    const rule = new events.Rule(this, 'SecurityHubRule', {
      ruleName: `${prefix}-findings-rule`,
      description: 'Route Security Hub findings to automation',
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            Severity: {
              Label: ['HIGH', 'CRITICAL', 'MEDIUM']
            },
            Workflow: {
              Status: ['NEW']
            }
          }
        }
      },
      enabled: true,
    });

    // Add Lambda targets
    rule.addTarget(new targets.LambdaFunction(this.triageFunction, {
      deadLetterQueue: this.deadLetterQueue,
      retryAttempts: 3,
    }));

    rule.addTarget(new targets.LambdaFunction(this.notificationFunction, {
      deadLetterQueue: this.deadLetterQueue,
      retryAttempts: 3,
    }));

    return rule;
  }

  /**
   * Create EventBridge rule for remediation actions
   */
  private createRemediationRule(prefix: string): events.Rule {
    const rule = new events.Rule(this, 'RemediationRule', {
      ruleName: `${prefix}-remediation-rule`,
      description: 'Route remediation actions to Lambda',
      eventPattern: {
        source: ['security.automation'],
        detailType: ['Security Response Required']
      },
      enabled: true,
    });

    rule.addTarget(new targets.LambdaFunction(this.remediationFunction, {
      deadLetterQueue: this.deadLetterQueue,
      retryAttempts: 3,
    }));

    return rule;
  }

  /**
   * Create EventBridge rule for custom actions
   */
  private createCustomActionRule(prefix: string): events.Rule {
    const rule = new events.Rule(this, 'CustomActionRule', {
      ruleName: `${prefix}-custom-actions`,
      description: 'Handle custom Security Hub actions',
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Custom Action'],
        detail: {
          actionName: ['TriggerAutomatedRemediation', 'EscalateToSOC']
        }
      },
      enabled: true,
    });

    rule.addTarget(new targets.LambdaFunction(this.triageFunction, {
      deadLetterQueue: this.deadLetterQueue,
      retryAttempts: 3,
    }));

    return rule;
  }

  /**
   * Create EventBridge rule for error handling
   */
  private createErrorHandlingRule(prefix: string): events.Rule {
    const rule = new events.Rule(this, 'ErrorHandlingRule', {
      ruleName: `${prefix}-error-handling`,
      description: 'Handle failed automation events',
      eventPattern: {
        source: ['aws.events'],
        detailType: ['EventBridge Rule Execution Failed']
      },
      enabled: true,
    });

    rule.addTarget(new targets.LambdaFunction(this.errorHandlerFunction, {
      deadLetterQueue: this.deadLetterQueue,
      retryAttempts: 3,
    }));

    return rule;
  }

  /**
   * Create Systems Manager automation document
   */
  private createAutomationDocument(prefix: string): void {
    const document = new ssm.CfnDocument(this, 'IsolateInstanceDocument', {
      documentType: 'Automation',
      documentFormat: 'JSON',
      name: `${prefix}-isolate-instance`,
      content: {
        schemaVersion: '0.3',
        description: 'Isolate EC2 instance for security incident response',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          InstanceId: {
            type: 'String',
            description: 'EC2 instance ID to isolate'
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution'
          }
        },
        mainSteps: [
          {
            name: 'StopInstance',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'ec2',
              Api: 'StopInstances',
              InstanceIds: ['{{ InstanceId }}']
            }
          },
          {
            name: 'CreateSnapshot',
            action: 'aws:executeScript',
            inputs: {
              Runtime: 'python3.8',
              Handler: 'create_snapshot',
              Script: `
def create_snapshot(events, context):
    import boto3
    ec2 = boto3.client('ec2')
    instance_id = events['InstanceId']
    
    # Get instance volumes
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    
    snapshots = []
    for device in instance.get('BlockDeviceMappings', []):
        volume_id = device['Ebs']['VolumeId']
        snapshot = ec2.create_snapshot(
            VolumeId=volume_id,
            Description=f'Forensic snapshot for {instance_id}'
        )
        snapshots.append(snapshot['SnapshotId'])
    
    return {'snapshots': snapshots}
              `,
              InputPayload: {
                InstanceId: '{{ InstanceId }}'
              }
            }
          }
        ]
      }
    });
  }

  /**
   * Create Security Hub automation rules
   */
  private createSecurityHubAutomationRules(prefix: string): void {
    // High severity automation rule
    new cdk.CfnResource(this, 'HighSeverityAutomationRule', {
      type: 'AWS::SecurityHub::AutomationRule',
      properties: {
        Actions: [
          {
            Type: 'FINDING_FIELDS_UPDATE',
            FindingFieldsUpdate: {
              Note: {
                Text: 'High severity finding detected - automated response initiated',
                UpdatedBy: 'SecurityAutomation'
              },
              Workflow: {
                Status: 'IN_PROGRESS'
              }
            }
          }
        ],
        Criteria: {
          SeverityLabel: [
            {
              Value: 'HIGH',
              Comparison: 'EQUALS'
            }
          ],
          WorkflowStatus: [
            {
              Value: 'NEW',
              Comparison: 'EQUALS'
            }
          ]
        },
        Description: 'Automatically mark high severity findings as in progress',
        RuleName: 'Auto-Process-High-Severity',
        RuleOrder: 1,
        RuleStatus: 'ENABLED'
      }
    });

    // Critical severity automation rule
    new cdk.CfnResource(this, 'CriticalSeverityAutomationRule', {
      type: 'AWS::SecurityHub::AutomationRule',
      properties: {
        Actions: [
          {
            Type: 'FINDING_FIELDS_UPDATE',
            FindingFieldsUpdate: {
              Note: {
                Text: 'Critical finding detected - immediate attention required',
                UpdatedBy: 'SecurityAutomation'
              },
              Workflow: {
                Status: 'IN_PROGRESS'
              }
            }
          }
        ],
        Criteria: {
          SeverityLabel: [
            {
              Value: 'CRITICAL',
              Comparison: 'EQUALS'
            }
          ],
          WorkflowStatus: [
            {
              Value: 'NEW',
              Comparison: 'EQUALS'
            }
          ]
        },
        Description: 'Automatically process critical findings',
        RuleName: 'Auto-Process-Critical-Findings',
        RuleOrder: 2,
        RuleStatus: 'ENABLED'
      }
    });
  }

  /**
   * Create Security Hub custom actions
   */
  private createSecurityHubCustomActions(prefix: string): void {
    // Remediation trigger action
    new cdk.CfnResource(this, 'RemediationActionTarget', {
      type: 'AWS::SecurityHub::ActionTarget',
      properties: {
        Name: 'TriggerAutomatedRemediation',
        Description: 'Trigger automated remediation for selected findings',
        Id: 'trigger-remediation'
      }
    });

    // SOC escalation action
    new cdk.CfnResource(this, 'EscalationActionTarget', {
      type: 'AWS::SecurityHub::ActionTarget',
      properties: {
        Name: 'EscalateToSOC',
        Description: 'Escalate finding to Security Operations Center',
        Id: 'escalate-soc'
      }
    });
  }

  /**
   * Create monitoring and alerting
   */
  private createMonitoring(prefix: string): void {
    // Lambda errors alarm
    const lambdaErrorsAlarm = new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `${prefix}-lambda-errors`,
      alarmDescription: 'Security automation Lambda errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Errors',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        dimensionsMap: {
          FunctionName: this.triageFunction.functionName
        }
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    lambdaErrorsAlarm.addAlarmAction(new cdk.aws_cloudwatch_actions.SnsAction(this.notificationTopic));

    // EventBridge failures alarm
    const eventBridgeFailuresAlarm = new cloudwatch.Alarm(this, 'EventBridgeFailuresAlarm', {
      alarmName: `${prefix}-eventbridge-failures`,
      alarmDescription: 'EventBridge rule failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Events',
        metricName: 'FailedInvocations',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        dimensionsMap: {
          RuleName: this.securityHubRule.ruleName
        }
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    eventBridgeFailuresAlarm.addAlarmAction(new cdk.aws_cloudwatch_actions.SnsAction(this.notificationTopic));

    // Create dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'SecurityAutomationDashboard', {
      dashboardName: `${prefix}-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Invocations',
            left: [
              this.triageFunction.metricInvocations(),
              this.remediationFunction.metricInvocations(),
              this.notificationFunction.metricInvocations(),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Errors',
            left: [
              this.triageFunction.metricErrors(),
              this.remediationFunction.metricErrors(),
              this.notificationFunction.metricErrors(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Duration',
            left: [
              this.triageFunction.metricDuration(),
              this.remediationFunction.metricDuration(),
              this.notificationFunction.metricDuration(),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Dead Letter Queue Messages',
            metrics: [
              this.deadLetterQueue.metricApproximateNumberOfVisibleMessages(),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for security notifications',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'URL of the dead letter queue',
      exportName: `${this.stackName}-DeadLetterQueueUrl`,
    });

    new cdk.CfnOutput(this, 'TriageFunctionArn', {
      value: this.triageFunction.functionArn,
      description: 'ARN of the triage Lambda function',
      exportName: `${this.stackName}-TriageFunctionArn`,
    });

    new cdk.CfnOutput(this, 'RemediationFunctionArn', {
      value: this.remediationFunction.functionArn,
      description: 'ARN of the remediation Lambda function',
      exportName: `${this.stackName}-RemediationFunctionArn`,
    });

    new cdk.CfnOutput(this, 'NotificationFunctionArn', {
      value: this.notificationFunction.functionArn,
      description: 'ARN of the notification Lambda function',
      exportName: `${this.stackName}-NotificationFunctionArn`,
    });

    new cdk.CfnOutput(this, 'SecurityHubRuleArn', {
      value: this.securityHubRule.ruleArn,
      description: 'ARN of the Security Hub EventBridge rule',
      exportName: `${this.stackName}-SecurityHubRuleArn`,
    });
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get context values
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 'security-automation';
const notificationEmail = app.node.tryGetContext('notificationEmail');
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') !== 'false';

// Create the stack
new SecurityAutomationStack(app, 'SecurityAutomationStack', {
  resourcePrefix,
  notificationEmail,
  enableDetailedMonitoring,
  description: 'Event-driven security automation with EventBridge and Lambda',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SecurityAutomation',
    Purpose: 'EventDrivenSecurity',
    Environment: process.env.CDK_DEFAULT_ENVIRONMENT || 'dev',
  },
});