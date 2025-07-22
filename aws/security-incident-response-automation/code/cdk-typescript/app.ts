#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as securityhub from 'aws-cdk-lib/aws-securityhub';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

/**
 * AWS CDK Stack for Automated Security Incident Response with Security Hub
 * 
 * This stack deploys a comprehensive security incident response automation system that:
 * - Enables AWS Security Hub with default security standards
 * - Creates Lambda functions for classification, remediation, and notification
 * - Configures EventBridge rules to trigger automated responses
 * - Sets up SNS topics for security team notifications
 * - Creates Security Hub insights for incident tracking
 * - Implements IAM roles with least-privilege permissions
 */
export class SecurityIncidentResponseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create SNS topic for security incident notifications
    const securityIncidentsTopic = new sns.Topic(this, 'SecurityIncidentsTopic', {
      topicName: `security-incidents-${uniqueSuffix}`,
      displayName: 'Security Incidents Notification Topic',
      fifo: false,
    });

    // Add email subscription to SNS topic (replace with actual security team email)
    securityIncidentsTopic.addSubscription(
      new subscriptions.EmailSubscription('security-team@company.com')
    );

    // Create IAM role for Lambda functions with incident response permissions
    const incidentResponseRole = new iam.Role(this, 'IncidentResponseRole', {
      roleName: `IncidentResponseRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for automated incident response Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        IncidentResponsePolicy: new iam.PolicyDocument({
          statements: [
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['arn:aws:logs:*:*:*'],
            }),
            // Security Hub permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'securityhub:GetFindings',
                'securityhub:BatchUpdateFindings',
                'securityhub:BatchImportFindings',
              ],
              resources: ['*'],
            }),
            // SNS publishing permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [securityIncidentsTopic.topicArn],
            }),
            // Remediation permissions for EC2, IAM, and S3
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeSecurityGroups',
                'ec2:AuthorizeSecurityGroupIngress',
                'ec2:RevokeSecurityGroupIngress',
                'ec2:CreateTags',
                'iam:AttachRolePolicy',
                'iam:DetachRolePolicy',
                'iam:PutRolePolicy',
                'iam:DeleteRolePolicy',
                's3:PutBucketPolicy',
                's3:GetBucketPolicy',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Classification Lambda Function
    const classificationFunction = new lambda.Function(this, 'ClassificationFunction', {
      functionName: `security-classification-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: incidentResponseRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Classifies security findings for automated response',
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

securityhub = boto3.client('securityhub')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Extract finding details from EventBridge event
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        
        # Classify finding based on severity and type
        classification = classify_finding(finding)
        
        # Update finding with classification
        response = securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-classified as {classification["category"]} - {classification["action"]}',
                'UpdatedBy': 'SecurityIncidentResponse'
            },
            UserDefinedFields={
                'AutoClassification': classification['category'],
                'RecommendedAction': classification['action'],
                'ProcessedAt': datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Successfully classified finding {finding_id} as {classification['category']}")
        
        # Return classification for downstream processing
        return {
            'statusCode': 200,
            'body': json.dumps({
                'findingId': finding_id,
                'classification': classification,
                'updated': True
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing finding: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def classify_finding(finding):
    """Classify finding based on severity, type, and content"""
    severity = finding['Severity']['Label']
    finding_type = finding.get('Types', ['Unknown'])[0]
    title = finding['Title'].lower()
    
    # High-priority security incidents
    if severity == 'CRITICAL':
        if 'root' in title or 'admin' in title:
            return {
                'category': 'CRITICAL_ADMIN_ISSUE',
                'action': 'IMMEDIATE_REVIEW_REQUIRED',
                'escalate': True
            }
        elif 'malware' in title or 'backdoor' in title:
            return {
                'category': 'MALWARE_DETECTED',
                'action': 'QUARANTINE_RESOURCE',
                'escalate': True
            }
        else:
            return {
                'category': 'CRITICAL_SECURITY_ISSUE',
                'action': 'INVESTIGATE_IMMEDIATELY',
                'escalate': True
            }
    
    # Medium-priority issues
    elif severity == 'HIGH':
        if 'mfa' in title:
            return {
                'category': 'MFA_COMPLIANCE_ISSUE',
                'action': 'ENFORCE_MFA_POLICY',
                'escalate': False
            }
        elif 'encryption' in title:
            return {
                'category': 'ENCRYPTION_COMPLIANCE',
                'action': 'ENABLE_ENCRYPTION',
                'escalate': False
            }
        else:
            return {
                'category': 'HIGH_SECURITY_ISSUE',
                'action': 'SCHEDULE_REMEDIATION',
                'escalate': False
            }
    
    # Lower priority issues
    else:
        return {
            'category': 'STANDARD_COMPLIANCE_ISSUE',
            'action': 'TRACK_FOR_REMEDIATION',
            'escalate': False
        }
      `),
    });

    // Remediation Lambda Function
    const remediationFunction = new lambda.Function(this, 'RemediationFunction', {
      functionName: `security-remediation-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: incidentResponseRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'Performs automated remediation of security findings',
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
iam = boto3.client('iam')
s3 = boto3.client('s3')
securityhub = boto3.client('securityhub')

def lambda_handler(event, context):
    try:
        # Extract finding details
        finding = event['detail']['findings'][0]
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        title = finding['Title']
        resources = finding.get('Resources', [])
        
        # Determine remediation action based on finding type
        remediation_result = perform_remediation(finding, resources)
        
        # Update finding with remediation status
        securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-remediation attempted: {remediation_result["action"]} - {remediation_result["status"]}',
                'UpdatedBy': 'SecurityIncidentResponse'
            },
            UserDefinedFields={
                'RemediationAction': remediation_result['action'],
                'RemediationStatus': remediation_result['status'],
                'RemediationTimestamp': datetime.utcnow().isoformat()
            },
            Workflow={
                'Status': 'RESOLVED' if remediation_result['status'] == 'SUCCESS' else 'NEW'
            }
        )
        
        logger.info(f"Remediation completed for finding {finding_id}: {remediation_result['status']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(remediation_result)
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def perform_remediation(finding, resources):
    """Perform automated remediation based on finding type"""
    title = finding['Title'].lower()
    
    try:
        # Security Group remediation
        if 'security group' in title and 'open' in title:
            return remediate_security_group(finding, resources)
        
        # S3 bucket policy remediation
        elif 's3' in title and 'public' in title:
            return remediate_s3_bucket(finding, resources)
        
        # IAM policy remediation
        elif 'iam' in title and 'policy' in title:
            return remediate_iam_policy(finding, resources)
        
        # Default action for other findings
        else:
            return {
                'action': 'MANUAL_REVIEW_REQUIRED',
                'status': 'PENDING',
                'message': 'Finding requires manual investigation'
            }
            
    except Exception as e:
        return {
            'action': 'REMEDIATION_FAILED',
            'status': 'ERROR',
            'message': str(e)
        }

def remediate_security_group(finding, resources):
    """Remediate overly permissive security group rules"""
    for resource in resources:
        if resource['Type'] == 'AwsEc2SecurityGroup':
            sg_id = resource['Id'].split('/')[-1]
            
            try:
                # Get security group details
                response = ec2.describe_security_groups(GroupIds=[sg_id])
                sg = response['SecurityGroups'][0]
                
                # Remove overly permissive rules (0.0.0.0/0)
                for rule in sg.get('IpPermissions', []):
                    for ip_range in rule.get('IpRanges', []):
                        if ip_range.get('CidrIp') == '0.0.0.0/0':
                            ec2.revoke_security_group_ingress(
                                GroupId=sg_id,
                                IpPermissions=[rule]
                            )
                            
                            # Add more restrictive rule (example: company IP range)
                            restricted_rule = rule.copy()
                            restricted_rule['IpRanges'] = [{'CidrIp': '10.0.0.0/8', 'Description': 'Internal network only'}]
                            
                            ec2.authorize_security_group_ingress(
                                GroupId=sg_id,
                                IpPermissions=[restricted_rule]
                            )
                
                return {
                    'action': 'SECURITY_GROUP_RESTRICTED',
                    'status': 'SUCCESS',
                    'message': f'Restricted security group {sg_id} access'
                }
                
            except Exception as e:
                return {
                    'action': 'SECURITY_GROUP_REMEDIATION_FAILED',
                    'status': 'ERROR',
                    'message': str(e)
                }
    
    return {
        'action': 'NO_SECURITY_GROUP_FOUND',
        'status': 'SKIPPED',
        'message': 'No security group resource found in finding'
    }

def remediate_s3_bucket(finding, resources):
    """Remediate public S3 bucket access"""
    for resource in resources:
        if resource['Type'] == 'AwsS3Bucket':
            bucket_name = resource['Id'].split('/')[-1]
            
            try:
                # Apply restrictive bucket policy
                restrictive_policy = {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "DenyPublicRead",
                            "Effect": "Deny",
                            "Principal": "*",
                            "Action": "s3:GetObject",
                            "Resource": f"arn:aws:s3:::{bucket_name}/*",
                            "Condition": {
                                "Bool": {
                                    "aws:SecureTransport": "false"
                                }
                            }
                        }
                    ]
                }
                
                s3.put_bucket_policy(
                    Bucket=bucket_name,
                    Policy=json.dumps(restrictive_policy)
                )
                
                return {
                    'action': 'S3_BUCKET_SECURED',
                    'status': 'SUCCESS',
                    'message': f'Applied restrictive policy to bucket {bucket_name}'
                }
                
            except Exception as e:
                return {
                    'action': 'S3_BUCKET_REMEDIATION_FAILED',
                    'status': 'ERROR',
                    'message': str(e)
                }
    
    return {
        'action': 'NO_S3_BUCKET_FOUND',
        'status': 'SKIPPED',
        'message': 'No S3 bucket resource found in finding'
    }

def remediate_iam_policy(finding, resources):
    """Remediate overly permissive IAM policies"""
    return {
        'action': 'IAM_POLICY_REVIEW_REQUIRED',
        'status': 'PENDING',
        'message': 'IAM policy changes require manual review for security'
    }
      `),
    });

    // Notification Lambda Function
    const notificationFunction = new lambda.Function(this, 'NotificationFunction', {
      functionName: `security-notification-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: incidentResponseRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Sends notifications for security incidents',
      logRetention: logs.RetentionDays.ONE_MONTH,
      environment: {
        SNS_TOPIC_ARN: securityIncidentsTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    try:
        # Extract finding details
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        account_id = finding['AwsAccountId']
        region = finding['Resources'][0]['Region'] if finding['Resources'] else 'Unknown'
        
        # Create notification message
        message = create_notification_message(finding, severity, title, description, account_id, region)
        
        # Send notification
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=f'Security Alert: {severity} - {title[:50]}...'
        )
        
        logger.info(f"Notification sent for finding {finding_id}: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'messageId': response['MessageId'],
                'finding': finding_id,
                'severity': severity
            })
        }
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_notification_message(finding, severity, title, description, account_id, region):
    """Create formatted notification message"""
    
    # Determine escalation based on severity
    escalation_level = "🔴 CRITICAL" if severity == "CRITICAL" else "🟠 HIGH" if severity == "HIGH" else "🟡 MEDIUM"
    
    # Extract resource information
    resources = []
    for resource in finding.get('Resources', []):
        resources.append(f"- {resource['Type']}: {resource['Id']}")
    
    resource_list = "\\n".join(resources) if resources else "No specific resources identified"
    
    # Create comprehensive message
    message = f"""
{escalation_level} SECURITY INCIDENT ALERT

======================================
INCIDENT DETAILS
======================================

Finding ID: {finding['Id']}
Severity: {severity}
Title: {title}

Account: {account_id}
Region: {region}
Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC

======================================
DESCRIPTION
======================================

{description}

======================================
AFFECTED RESOURCES
======================================

{resource_list}

======================================
RECOMMENDED ACTIONS
======================================

1. Review the finding details in AWS Security Hub
2. Investigate the affected resources
3. Apply necessary remediation steps
4. Update the finding status when resolved

======================================
SECURITY HUB LINK
======================================

https://console.aws.amazon.com/securityhub/home?region={region}#/findings?search=Id%3D{finding['Id'].replace(':', '%3A').replace('/', '%2F')}

This is an automated alert from AWS Security Hub Incident Response System.
"""
    
    return message
      `),
    });

    // Enable Security Hub with default standards
    const securityHub = new securityhub.CfnHub(this, 'SecurityHub', {
      tags: [
        { key: 'Project', value: 'IncidentResponse' },
        { key: 'Environment', value: 'Production' },
      ],
    });

    // Create EventBridge rule for high/critical findings
    const criticalFindingsRule = new events.Rule(this, 'CriticalFindingsRule', {
      ruleName: `security-hub-findings-critical-${uniqueSuffix}`,
      description: 'Triggers incident response for high/critical security findings',
      enabled: true,
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            Severity: {
              Label: ['HIGH', 'CRITICAL'],
            },
            RecordState: ['ACTIVE'],
            WorkflowState: ['NEW'],
          },
        },
      },
    });

    // Add Lambda targets to critical findings rule
    criticalFindingsRule.addTarget(new targets.LambdaFunction(classificationFunction));
    criticalFindingsRule.addTarget(new targets.LambdaFunction(remediationFunction));
    criticalFindingsRule.addTarget(new targets.LambdaFunction(notificationFunction));

    // Create EventBridge rule for medium severity findings (notification only)
    const mediumFindingsRule = new events.Rule(this, 'MediumFindingsRule', {
      ruleName: `security-hub-findings-medium-${uniqueSuffix}`,
      description: 'Triggers notifications for medium severity security findings',
      enabled: true,
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            Severity: {
              Label: ['MEDIUM'],
            },
            RecordState: ['ACTIVE'],
            WorkflowState: ['NEW'],
          },
        },
      },
    });

    // Add Lambda targets to medium findings rule
    mediumFindingsRule.addTarget(new targets.LambdaFunction(classificationFunction));
    mediumFindingsRule.addTarget(new targets.LambdaFunction(notificationFunction));

    // Create Security Hub custom action for manual escalation
    const customAction = new securityhub.CfnActionTarget(this, 'EscalateAction', {
      name: 'Escalate to Security Team',
      description: 'Manually escalate security finding to security team',
      id: 'escalate-to-security-team',
    });

    // Create EventBridge rule for custom action
    const manualEscalationRule = new events.Rule(this, 'ManualEscalationRule', {
      ruleName: `security-hub-manual-escalation-${uniqueSuffix}`,
      description: 'Handles manual escalation of security findings',
      enabled: true,
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Custom Action'],
        detail: {
          actionName: ['Escalate to Security Team'],
        },
      },
    });

    // Add notification target for manual escalation
    manualEscalationRule.addTarget(new targets.LambdaFunction(notificationFunction));

    // Create Security Hub insights for incident tracking
    const criticalInsight = new securityhub.CfnInsight(this, 'CriticalInsight', {
      name: 'Critical Security Incidents',
      filters: {
        SeverityLabel: [
          {
            Value: 'CRITICAL',
            Comparison: 'EQUALS',
          },
        ],
        RecordState: [
          {
            Value: 'ACTIVE',
            Comparison: 'EQUALS',
          },
        ],
      },
      groupByAttribute: 'ProductName',
    });

    const unresolvedInsight = new securityhub.CfnInsight(this, 'UnresolvedInsight', {
      name: 'Unresolved Security Findings',
      filters: {
        WorkflowStatus: [
          {
            Value: 'NEW',
            Comparison: 'EQUALS',
          },
        ],
        RecordState: [
          {
            Value: 'ACTIVE',
            Comparison: 'EQUALS',
          },
        ],
      },
      groupByAttribute: 'SeverityLabel',
    });

    // Stack outputs for reference
    new cdk.CfnOutput(this, 'SecurityHubArn', {
      value: securityHub.attrArn,
      description: 'ARN of the Security Hub instance',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: securityIncidentsTopic.topicArn,
      description: 'ARN of the security incidents SNS topic',
    });

    new cdk.CfnOutput(this, 'ClassificationFunctionArn', {
      value: classificationFunction.functionArn,
      description: 'ARN of the security finding classification Lambda function',
    });

    new cdk.CfnOutput(this, 'RemediationFunctionArn', {
      value: remediationFunction.functionArn,
      description: 'ARN of the security finding remediation Lambda function',
    });

    new cdk.CfnOutput(this, 'NotificationFunctionArn', {
      value: notificationFunction.functionArn,
      description: 'ARN of the security incident notification Lambda function',
    });

    new cdk.CfnOutput(this, 'CriticalInsightArn', {
      value: criticalInsight.attrInsightArn,
      description: 'ARN of the critical security incidents insight',
    });

    new cdk.CfnOutput(this, 'UnresolvedInsightArn', {
      value: unresolvedInsight.attrInsightArn,
      description: 'ARN of the unresolved security findings insight',
    });

    new cdk.CfnOutput(this, 'CustomActionArn', {
      value: customAction.attrActionTargetArn,
      description: 'ARN of the Security Hub custom action for manual escalation',
    });
  }
}

const app = new cdk.App();
new SecurityIncidentResponseStack(app, 'SecurityIncidentResponseStack', {
  description: 'Automated Security Incident Response with AWS Security Hub, EventBridge, and Lambda',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();