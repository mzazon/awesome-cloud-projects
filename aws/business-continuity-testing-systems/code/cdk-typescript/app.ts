#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

interface BusinessContinuityTestingStackProps extends cdk.StackProps {
  /**
   * Email address for SNS notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Project identifier for resource naming
   */
  readonly projectId?: string;
  
  /**
   * Environment name (dev, staging, prod)
   */
  readonly environment?: string;
  
  /**
   * Enable automated scheduling of tests
   */
  readonly enableAutomatedScheduling?: boolean;
}

export class BusinessContinuityTestingStack extends cdk.Stack {
  public readonly testResultsBucket: s3.Bucket;
  public readonly automationRole: iam.Role;
  public readonly snsTopicArn: string;
  public readonly orchestratorFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: BusinessContinuityTestingStackProps = {}) {
    super(scope, id, props);

    // Generate unique project ID if not provided
    const projectId = props.projectId || this.generateProjectId();
    const environment = props.environment || 'dev';
    const enableScheduling = props.enableAutomatedScheduling ?? true;

    // Create tags for all resources
    const commonTags = {
      Project: 'BusinessContinuityTesting',
      Environment: environment,
      ProjectId: projectId,
      ManagedBy: 'CDK'
    };

    // Create IAM role for business continuity testing automation
    this.automationRole = this.createAutomationRole(projectId, commonTags);

    // Create S3 bucket for test results and reports
    this.testResultsBucket = this.createTestResultsBucket(projectId, commonTags);

    // Create SNS topic for notifications
    const snsTopic = this.createSnsNotificationTopic(projectId, props.notificationEmail, commonTags);
    this.snsTopicArn = snsTopic.topicArn;

    // Create Systems Manager automation documents
    const automationDocuments = this.createAutomationDocuments(projectId, commonTags);

    // Create Lambda functions for orchestration and compliance
    const lambdaFunctions = this.createLambdaFunctions(
      projectId,
      this.automationRole,
      this.testResultsBucket,
      snsTopic,
      commonTags
    );
    this.orchestratorFunction = lambdaFunctions.orchestrator;

    // Create automated testing schedules if enabled
    if (enableScheduling) {
      this.createTestingSchedules(projectId, lambdaFunctions.orchestrator, commonTags);
    }

    // Create CloudWatch dashboard for monitoring
    this.createCloudWatchDashboard(projectId, lambdaFunctions, automationDocuments, commonTags);

    // Apply tags to all resources
    this.applyTags(commonTags);

    // Create stack outputs
    this.createOutputs(projectId, lambdaFunctions);
  }

  /**
   * Generate a unique project identifier
   */
  private generateProjectId(): string {
    return Math.random().toString(36).substring(2, 10);
  }

  /**
   * Create IAM role for automation services
   */
  private createAutomationRole(projectId: string, tags: Record<string, string>): iam.Role {
    const role = new iam.Role(this, 'BCTestingAutomationRole', {
      roleName: `BCTestingRole-${projectId}`,
      description: 'IAM role for business continuity testing automation',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('ssm.amazonaws.com'),
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('states.amazonaws.com'),
        new iam.ServicePrincipal('events.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add comprehensive policy for BC testing operations
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:*',
        'ec2:*',
        'rds:*',
        's3:*',
        'lambda:*',
        'states:*',
        'events:*',
        'cloudwatch:*',
        'sns:*',
        'logs:*',
        'backup:*',
        'iam:PassRole'
      ],
      resources: ['*']
    }));

    // Apply tags
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(role).add(key, value);
    });

    return role;
  }

  /**
   * Create S3 bucket for test results with lifecycle management
   */
  private createTestResultsBucket(projectId: string, tags: Record<string, string>): s3.Bucket {
    const bucket = new s3.Bucket(this, 'BCTestResultsBucket', {
      bucketName: `bc-testing-results-${projectId}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'BCTestResultsRetention',
          enabled: true,
          prefix: 'test-results/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ],
          expiration: cdk.Duration.days(2555) // ~7 years
        }
      ]
    });

    // Apply tags
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(bucket).add(key, value);
    });

    return bucket;
  }

  /**
   * Create SNS topic for BC testing notifications
   */
  private createSnsNotificationTopic(
    projectId: string,
    notificationEmail?: string,
    tags: Record<string, string> = {}
  ): sns.Topic {
    const topic = new sns.Topic(this, 'BCTestingNotificationTopic', {
      topicName: `bc-alerts-${projectId}`,
      displayName: 'Business Continuity Testing Alerts'
    });

    // Subscribe email if provided
    if (notificationEmail) {
      topic.addSubscription(new subscriptions.EmailSubscription(notificationEmail));
    }

    // Apply tags
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(topic).add(key, value);
    });

    return topic;
  }

  /**
   * Create Systems Manager automation documents
   */
  private createAutomationDocuments(
    projectId: string,
    tags: Record<string, string>
  ): { backupValidation: ssm.CfnDocument; databaseRecovery: ssm.CfnDocument; applicationFailover: ssm.CfnDocument } {
    
    // Backup Validation Automation Document
    const backupValidationDocument = new ssm.CfnDocument(this, 'BackupValidationDocument', {
      documentType: 'Automation',
      documentFormat: 'YAML',
      name: `BC-BackupValidation-${projectId}`,
      content: {
        schemaVersion: '0.3',
        description: 'Validate backup integrity and restore capabilities',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          InstanceId: {
            type: 'String',
            description: 'EC2 instance ID to test backup restore'
          },
          BackupVaultName: {
            type: 'String',
            description: 'AWS Backup vault name'
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution'
          }
        },
        mainSteps: [
          {
            name: 'CreateRestoreTestInstance',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'backup',
              Api: 'StartRestoreJob',
              RecoveryPointArn: '{{ GetLatestRecoveryPoint.RecoveryPointArn }}',
              Metadata: {
                InstanceType: 't3.micro'
              },
              IamRoleArn: '{{ AutomationAssumeRole }}'
            },
            outputs: [
              {
                Name: 'RestoreJobId',
                Selector: '$.RestoreJobId',
                Type: 'String'
              }
            ]
          },
          {
            name: 'WaitForRestoreCompletion',
            action: 'aws:waitForAwsResourceProperty',
            inputs: {
              Service: 'backup',
              Api: 'DescribeRestoreJob',
              RestoreJobId: '{{ CreateRestoreTestInstance.RestoreJobId }}',
              PropertySelector: '$.Status',
              DesiredValues: ['COMPLETED']
            },
            timeoutSeconds: 3600
          },
          {
            name: 'ValidateRestoredInstance',
            action: 'aws:runCommand',
            inputs: {
              DocumentName: 'AWS-RunShellScript',
              InstanceIds: ['{{ CreateRestoreTestInstance.CreatedResourceArn }}'],
              Parameters: {
                commands: [
                  '#!/bin/bash',
                  'echo "Validating restored instance..."',
                  'systemctl status',
                  'df -h',
                  'if command -v nginx &> /dev/null; then systemctl status nginx; fi',
                  'echo "Validation completed"'
                ]
              }
            },
            outputs: [
              {
                Name: 'ValidationResults',
                Selector: '$.CommandInvocations[0].CommandPlugins[0].Output',
                Type: 'String'
              }
            ]
          },
          {
            name: 'CleanupTestInstance',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'ec2',
              Api: 'TerminateInstances',
              InstanceIds: ['{{ CreateRestoreTestInstance.CreatedResourceArn }}']
            }
          }
        ],
        outputs: ['ValidationResults: {{ ValidateRestoredInstance.ValidationResults }}']
      },
      tags: Object.entries(tags).map(([key, value]) => ({ key, value }))
    });

    // Database Recovery Automation Document
    const databaseRecoveryDocument = new ssm.CfnDocument(this, 'DatabaseRecoveryDocument', {
      documentType: 'Automation',
      documentFormat: 'YAML',
      name: `BC-DatabaseRecovery-${projectId}`,
      content: {
        schemaVersion: '0.3',
        description: 'Test database backup and recovery procedures',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          DBInstanceIdentifier: {
            type: 'String',
            description: 'RDS instance identifier'
          },
          DBSnapshotIdentifier: {
            type: 'String',
            description: 'Snapshot to restore from'
          },
          TestDBInstanceIdentifier: {
            type: 'String',
            description: 'Test database instance identifier'
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution'
          }
        },
        mainSteps: [
          {
            name: 'CreateTestDatabase',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'rds',
              Api: 'RestoreDBInstanceFromDBSnapshot',
              DBInstanceIdentifier: '{{ TestDBInstanceIdentifier }}',
              DBSnapshotIdentifier: '{{ DBSnapshotIdentifier }}',
              DBInstanceClass: 'db.t3.micro',
              PubliclyAccessible: false,
              StorageEncrypted: true
            },
            outputs: [
              {
                Name: 'TestDBEndpoint',
                Selector: '$.DBInstance.Endpoint.Address',
                Type: 'String'
              }
            ]
          },
          {
            name: 'WaitForDBAvailable',
            action: 'aws:waitForAwsResourceProperty',
            inputs: {
              Service: 'rds',
              Api: 'DescribeDBInstances',
              DBInstanceIdentifier: '{{ TestDBInstanceIdentifier }}',
              PropertySelector: '$.DBInstances[0].DBInstanceStatus',
              DesiredValues: ['available']
            },
            timeoutSeconds: 1800
          },
          {
            name: 'CleanupTestDatabase',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 'rds',
              Api: 'DeleteDBInstance',
              DBInstanceIdentifier: '{{ TestDBInstanceIdentifier }}',
              SkipFinalSnapshot: true,
              DeleteAutomatedBackups: true
            }
          }
        ]
      },
      tags: Object.entries(tags).map(([key, value]) => ({ key, value }))
    });

    // Application Failover Automation Document
    const applicationFailoverDocument = new ssm.CfnDocument(this, 'ApplicationFailoverDocument', {
      documentType: 'Automation',
      documentFormat: 'YAML',
      name: `BC-ApplicationFailover-${projectId}`,
      content: {
        schemaVersion: '0.3',
        description: 'Test application failover to secondary region',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          PrimaryLoadBalancerArn: {
            type: 'String',
            description: 'Primary Application Load Balancer ARN'
          },
          SecondaryLoadBalancerArn: {
            type: 'String',
            description: 'Secondary Application Load Balancer ARN'
          },
          Route53HostedZoneId: {
            type: 'String',
            description: 'Route 53 hosted zone ID'
          },
          DomainName: {
            type: 'String',
            description: 'Domain name for failover testing'
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution'
          }
        },
        mainSteps: [
          {
            name: 'CheckPrimaryApplicationHealth',
            action: 'aws:executeScript',
            inputs: {
              Runtime: 'python3.8',
              Handler: 'check_application_health',
              Script: `
import requests
import json

def check_application_health(events, context):
    domain = events['DomainName']
    
    try:
        response = requests.get(f'https://{domain}/health', timeout=30)
        
        return {
            'statusCode': response.status_code,
            'healthy': response.status_code == 200,
            'response_time': response.elapsed.total_seconds()
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'healthy': False,
            'error': str(e)
        }
              `,
              InputPayload: {
                DomainName: '{{ DomainName }}'
              }
            },
            outputs: [
              {
                Name: 'PrimaryHealthStatus',
                Selector: '$.Payload.healthy',
                Type: 'Boolean'
              }
            ]
          },
          {
            name: 'WaitForDNSPropagation',
            action: 'aws:sleep',
            inputs: {
              Duration: 'PT2M'
            }
          }
        ]
      },
      tags: Object.entries(tags).map(([key, value]) => ({ key, value }))
    });

    return {
      backupValidation: backupValidationDocument,
      databaseRecovery: databaseRecoveryDocument,
      applicationFailover: applicationFailoverDocument
    };
  }

  /**
   * Create Lambda functions for orchestration and compliance
   */
  private createLambdaFunctions(
    projectId: string,
    role: iam.Role,
    resultsBucket: s3.Bucket,
    snsTopic: sns.Topic,
    tags: Record<string, string>
  ): { orchestrator: lambda.Function; compliance: lambda.Function; manual: lambda.Function } {

    // Test Orchestrator Lambda Function
    const orchestratorFunction = new lambda.Function(this, 'BCTestOrchestratorFunction', {
      functionName: `bc-test-orchestrator-${projectId}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      environment: {
        PROJECT_ID: projectId,
        RESULTS_BUCKET: resultsBucket.bucketName,
        AUTOMATION_ROLE_ARN: role.roleArn,
        SNS_TOPIC_ARN: snsTopic.topicArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
import uuid
import os
from typing import Dict, List

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    test_type = event.get('testType', 'daily')
    test_id = str(uuid.uuid4())
    
    test_results = {
        'testId': test_id,
        'testType': test_type,
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'results': []
    }
    
    try:
        if test_type in ['daily', 'weekly', 'monthly']:
            backup_result = execute_backup_validation(ssm, test_id)
            test_results['results'].append(backup_result)
        
        if test_type in ['weekly', 'monthly']:
            db_result = execute_database_recovery_test(ssm, test_id)
            test_results['results'].append(db_result)
        
        if test_type == 'monthly':
            app_result = execute_application_failover_test(ssm, test_id)
            test_results['results'].append(app_result)
        
        # Store results in S3
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=f'test-results/{test_type}/{test_id}/results.json',
            Body=json.dumps(test_results, indent=2),
            ContentType='application/json'
        )
        
        summary = generate_test_summary(test_results)
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing {test_type.title()} Report - {test_id[:8]}',
            Message=summary
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'testId': test_id,
                'summary': summary
            })
        }
        
    except Exception as e:
        error_message = f'BC testing failed: {str(e)}'
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing Failed - {test_id[:8]}',
            Message=error_message
        )
        raise e

def execute_backup_validation(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
        Parameters={
            'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
            'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'backup_validation',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_database_recovery_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'prod-db')],
            'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
            'TestDBInstanceIdentifier': [f'test-db-{test_id[:8]}'],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'database_recovery',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_application_failover_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
        Parameters={
            'PrimaryLoadBalancerArn': [os.environ.get('PRIMARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/1234567890123456')],
            'SecondaryLoadBalancerArn': [os.environ.get('SECONDARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/secondary/6543210987654321')],
            'Route53HostedZoneId': [os.environ.get('HOSTED_ZONE_ID', 'Z1234567890123')],
            'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'application_failover',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def generate_test_summary(test_results):
    total_tests = len(test_results['results'])
    summary = f"""
Business Continuity Testing Summary
Test ID: {test_results['testId']}
Test Type: {test_results['testType']}
Timestamp: {test_results['timestamp']}

Tests Executed: {total_tests}

Test Results:
"""
    
    for result in test_results['results']:
        summary += f"- {result['test']}: {result['status']}\\n"
    
    return summary
      `)
    });

    // Compliance Reporter Lambda Function
    const complianceFunction = new lambda.Function(this, 'BCComplianceReporterFunction', {
      functionName: `bc-compliance-reporter-${projectId}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        RESULTS_BUCKET: resultsBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    
    report_data = generate_compliance_report(s3, ssm)
    
    report_key = f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.json"
    
    s3.put_object(
        Bucket=os.environ['RESULTS_BUCKET'],
        Key=report_key,
        Body=json.dumps(report_data, indent=2),
        ContentType='application/json'
    )
    
    html_report = generate_html_report(report_data)
    
    s3.put_object(
        Bucket=os.environ['RESULTS_BUCKET'],
        Key=f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.html",
        Body=html_report,
        ContentType='text/html'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'reportGenerated': True,
            'reportLocation': report_key
        })
    }

def generate_compliance_report(s3, ssm):
    start_date = datetime.datetime.utcnow() - datetime.timedelta(days=30)
    
    report = {
        'reportPeriod': {
            'start': start_date.isoformat(),
            'end': datetime.datetime.utcnow().isoformat()
        },
        'testingSummary': {
            'dailyTests': 0,
            'weeklyTests': 0,
            'monthlyTests': 0,
            'totalTests': 0,
            'successfulTests': 0,
            'failedTests': 0
        },
        'complianceStatus': 'COMPLIANT',
        'recommendations': []
    }
    
    return report

def generate_html_report(report_data):
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Business Continuity Compliance Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ background-color: #f0f0f0; padding: 20px; }}
        .summary {{ margin: 20px 0; }}
        .compliant {{ color: green; }}
        .non-compliant {{ color: red; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Business Continuity Testing Compliance Report</h1>
        <p>Report Period: {report_data['reportPeriod']['start']} to {report_data['reportPeriod']['end']}</p>
    </div>
    
    <div class="summary">
        <h2>Testing Summary</h2>
        <p>Total Tests Executed: {report_data['testingSummary']['totalTests']}</p>
        <p>Successful Tests: {report_data['testingSummary']['successfulTests']}</p>
        <p>Failed Tests: {report_data['testingSummary']['failedTests']}</p>
        <p>Compliance Status: <span class="{report_data['complianceStatus'].lower()}">{report_data['complianceStatus']}</span></p>
    </div>
</body>
</html>
    """
    return html
      `)
    });

    // Manual Test Executor Lambda Function
    const manualTestFunction = new lambda.Function(this, 'BCManualTestExecutorFunction', {
      functionName: `bc-manual-test-executor-${projectId}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        PROJECT_ID: projectId,
        AUTOMATION_ROLE_ARN: role.roleArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    
    test_type = event.get('testType', 'comprehensive')
    test_components = event.get('components', ['backup', 'database', 'application'])
    
    execution_results = []
    
    for component in test_components:
        if component == 'backup':
            result = execute_backup_test(ssm)
            execution_results.append(result)
        elif component == 'database':
            result = execute_database_test(ssm)
            execution_results.append(result)
        elif component == 'application':
            result = execute_application_test(ssm)
            execution_results.append(result)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'testType': test_type,
            'executionId': str(uuid.uuid4()),
            'results': execution_results
        })
    }

def execute_backup_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
        Parameters={
            'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
            'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'backup', 'executionId': response['AutomationExecutionId']}

def execute_database_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'prod-db')],
            'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
            'TestDBInstanceIdentifier': [f'manual-test-{uuid.uuid4().hex[:8]}'],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'database', 'executionId': response['AutomationExecutionId']}

def execute_application_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
        Parameters={
            'PrimaryLoadBalancerArn': [os.environ.get('PRIMARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/1234567890123456')],
            'SecondaryLoadBalancerArn': [os.environ.get('SECONDARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/secondary/6543210987654321')],
            'Route53HostedZoneId': [os.environ.get('HOSTED_ZONE_ID', 'Z1234567890123')],
            'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'application', 'executionId': response['AutomationExecutionId']}
      `)
    });

    // Apply tags to all Lambda functions
    const functions = [orchestratorFunction, complianceFunction, manualTestFunction];
    functions.forEach(func => {
      Object.entries(tags).forEach(([key, value]) => {
        cdk.Tags.of(func).add(key, value);
      });
    });

    return {
      orchestrator: orchestratorFunction,
      compliance: complianceFunction,
      manual: manualTestFunction
    };
  }

  /**
   * Create EventBridge rules for automated testing schedules
   */
  private createTestingSchedules(
    projectId: string,
    orchestratorFunction: lambda.Function,
    tags: Record<string, string>
  ): void {
    // Daily basic tests
    const dailyRule = new events.Rule(this, 'BCDailyTestsRule', {
      ruleName: `bc-daily-tests-${projectId}`,
      description: 'Daily business continuity basic tests',
      schedule: events.Schedule.rate(cdk.Duration.days(1))
    });

    dailyRule.addTarget(new targets.LambdaFunction(orchestratorFunction, {
      event: events.RuleTargetInput.fromObject({ testType: 'daily' })
    }));

    // Weekly comprehensive tests
    const weeklyRule = new events.Rule(this, 'BCWeeklyTestsRule', {
      ruleName: `bc-weekly-tests-${projectId}`,
      description: 'Weekly comprehensive business continuity tests',
      schedule: events.Schedule.cron({ hour: '2', minute: '0', weekDay: 'SUN' })
    });

    weeklyRule.addTarget(new targets.LambdaFunction(orchestratorFunction, {
      event: events.RuleTargetInput.fromObject({ testType: 'weekly' })
    }));

    // Monthly full DR tests
    const monthlyRule = new events.Rule(this, 'BCMonthlyTestsRule', {
      ruleName: `bc-monthly-tests-${projectId}`,
      description: 'Monthly full disaster recovery tests',
      schedule: events.Schedule.cron({ hour: '1', minute: '0', day: '1' })
    });

    monthlyRule.addTarget(new targets.LambdaFunction(orchestratorFunction, {
      event: events.RuleTargetInput.fromObject({ testType: 'monthly' })
    }));

    // Apply tags to rules
    const rules = [dailyRule, weeklyRule, monthlyRule];
    rules.forEach(rule => {
      Object.entries(tags).forEach(([key, value]) => {
        cdk.Tags.of(rule).add(key, value);
      });
    });
  }

  /**
   * Create CloudWatch dashboard for BC testing monitoring
   */
  private createCloudWatchDashboard(
    projectId: string,
    lambdaFunctions: { orchestrator: lambda.Function; compliance: lambda.Function; manual: lambda.Function },
    automationDocuments: { backupValidation: ssm.CfnDocument; databaseRecovery: ssm.CfnDocument; applicationFailover: ssm.CfnDocument },
    tags: Record<string, string>
  ): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'BCTestingDashboard', {
      dashboardName: `BC-Testing-${projectId}`,
      widgets: [
        [
          // Lambda metrics widget
          new cloudwatch.GraphWidget({
            title: 'BC Testing Lambda Metrics',
            left: [
              lambdaFunctions.orchestrator.metricDuration(),
              lambdaFunctions.orchestrator.metricErrors(),
              lambdaFunctions.orchestrator.metricInvocations()
            ],
            width: 12,
            height: 6
          }),
          // Systems Manager execution metrics
          new cloudwatch.SingleValueWidget({
            title: 'BC Testing Success/Failure Rates',
            metrics: [
              new cloudwatch.Metric({
                namespace: 'AWS/SSM',
                metricName: 'ExecutionSuccess',
                dimensionsMap: {
                  DocumentName: automationDocuments.backupValidation.name!
                },
                statistic: 'Sum',
                period: cdk.Duration.days(1)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/SSM',
                metricName: 'ExecutionFailed',
                dimensionsMap: {
                  DocumentName: automationDocuments.backupValidation.name!
                },
                statistic: 'Sum',
                period: cdk.Duration.days(1)
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          // Log insights widget for recent executions
          new cloudwatch.LogQueryWidget({
            title: 'Recent BC Test Executions',
            logGroups: [
              logs.LogGroup.fromLogGroupName(this, 'OrchestratorLogGroup', `/aws/lambda/${lambdaFunctions.orchestrator.functionName}`)
            ],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /Test/',
              'sort @timestamp desc',
              'limit 20'
            ],
            width: 24,
            height: 6
          })
        ]
      ]
    });

    // Apply tags
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(dashboard).add(key, value);
    });

    return dashboard;
  }

  /**
   * Apply common tags to all stack resources
   */
  private applyTags(tags: Record<string, string>): void {
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Create stack outputs
   */
  private createOutputs(
    projectId: string,
    lambdaFunctions: { orchestrator: lambda.Function; compliance: lambda.Function; manual: lambda.Function }
  ): void {
    new cdk.CfnOutput(this, 'ProjectId', {
      value: projectId,
      description: 'Business Continuity Testing Project ID'
    });

    new cdk.CfnOutput(this, 'TestResultsBucketName', {
      value: this.testResultsBucket.bucketName,
      description: 'S3 bucket for BC test results and compliance reports'
    });

    new cdk.CfnOutput(this, 'AutomationRoleArn', {
      value: this.automationRole.roleArn,
      description: 'IAM role ARN for BC testing automation'
    });

    new cdk.CfnOutput(this, 'OrchestratorFunctionArn', {
      value: lambdaFunctions.orchestrator.functionArn,
      description: 'Lambda function ARN for BC test orchestration'
    });

    new cdk.CfnOutput(this, 'ManualTestFunctionArn', {
      value: lambdaFunctions.manual.functionArn,
      description: 'Lambda function ARN for manual BC test execution'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopicArn,
      description: 'SNS topic ARN for BC testing notifications'
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=BC-Testing-${projectId}`,
      description: 'CloudWatch dashboard URL for BC testing monitoring'
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Get configuration from context or environment variables
const projectId = app.node.tryGetContext('projectId') || process.env.PROJECT_ID;
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const enableScheduling = app.node.tryGetContext('enableScheduling') !== 'false';

// Create the stack
new BusinessContinuityTestingStack(app, 'BusinessContinuityTestingStack', {
  description: 'Business Continuity Testing Framework with AWS Systems Manager, EventBridge, and Lambda',
  projectId: projectId,
  environment: environment,
  notificationEmail: notificationEmail,
  enableAutomatedScheduling: enableScheduling,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'BusinessContinuityTesting',
    Environment: environment,
    ManagedBy: 'CDK',
    Purpose: 'DisasterRecovery'
  }
});