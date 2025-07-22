#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Stack for AWS Application Discovery Service Enterprise Migration Assessment
 * 
 * This stack creates the infrastructure needed for comprehensive migration discovery
 * including S3 storage for discovery data, CloudWatch monitoring, and automation
 * for data export and migration wave planning.
 */
export class EnterpriseMigrationAssessmentStack extends cdk.Stack {
  public readonly discoveryDataBucket: s3.Bucket;
  public readonly migrationProjectName: string;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique project name for this deployment
    const projectSuffix = Math.random().toString(36).substring(2, 8);
    this.migrationProjectName = `enterprise-migration-${projectSuffix}`;

    // S3 bucket for storing discovery data exports
    this.discoveryDataBucket = new s3.Bucket(this, 'DiscoveryDataBucket', {
      bucketName: `migration-discovery-${projectSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'discovery-data-lifecycle',
          enabled: true,
          expiration: cdk.Duration.days(2555), // 7 years retention
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN, // Retain data for compliance
    });

    // CloudWatch log group for discovery service monitoring
    this.logGroup = new logs.LogGroup(this, 'DiscoveryLogGroup', {
      logGroupName: `/aws/discovery/${this.migrationProjectName}`,
      retention: logs.RetentionDays.ONE_YEAR,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM role for Application Discovery Service
    const discoveryServiceRole = new iam.Role(this, 'DiscoveryServiceRole', {
      assumedBy: new iam.ServicePrincipal('discovery.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSApplicationDiscoveryServiceFullAccess'),
      ],
      inlinePolicies: {
        S3DiscoveryPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                this.discoveryDataBucket.bucketArn,
                `${this.discoveryDataBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [this.logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for automating discovery data exports
    const exportAutomationFunction = new lambda.Function(this, 'ExportAutomationFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      environment: {
        BUCKET_NAME: this.discoveryDataBucket.bucketName,
        LOG_GROUP_NAME: this.logGroup.logGroupName,
        PROJECT_NAME: this.migrationProjectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Automate Application Discovery Service data export to S3
    """
    discovery = boto3.client('discovery')
    
    try:
        # Start export task for all discovery data
        response = discovery.start_export_task(
            exportDataFormat='CSV',
            filters=[
                {
                    'name': 'AgentId',
                    'values': ['*'],
                    'condition': 'EQUALS'
                }
            ],
            s3Bucket=os.environ['BUCKET_NAME'],
            s3Prefix=f"exports/{datetime.now().strftime('%Y/%m/%d')}/"
        )
        
        export_id = response['exportId']
        
        # Log the export initiation
        print(f"Started discovery data export with ID: {export_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Export task started successfully',
                'exportId': export_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error starting export task: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }
`),
    });

    // Grant permissions to the Lambda function
    this.discoveryDataBucket.grantReadWrite(exportAutomationFunction);
    this.logGroup.grantWrite(exportAutomationFunction);
    
    exportAutomationFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'discovery:StartExportTask',
          'discovery:DescribeExportTasks',
          'discovery:ListConfigurations',
          'discovery:DescribeAgents',
        ],
        resources: ['*'],
      })
    );

    // EventBridge rule for weekly automated exports
    const weeklyExportRule = new events.Rule(this, 'WeeklyExportRule', {
      ruleName: 'weekly-discovery-export',
      description: 'Trigger weekly export of Application Discovery Service data',
      schedule: events.Schedule.rate(cdk.Duration.days(7)),
      enabled: true,
    });

    weeklyExportRule.addTarget(new targets.LambdaFunction(exportAutomationFunction));

    // Lambda function for migration wave planning
    const waveplanningFunction = new lambda.Function(this, 'WavePlanningFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(10),
      environment: {
        BUCKET_NAME: this.discoveryDataBucket.bucketName,
        PROJECT_NAME: this.migrationProjectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Create migration wave planning framework based on discovery data
    """
    s3 = boto3.client('s3')
    
    try:
        # Define migration waves structure
        waves_config = {
            "migrationProject": os.environ['PROJECT_NAME'],
            "createdAt": datetime.now().isoformat(),
            "waves": [
                {
                    "waveNumber": 1,
                    "name": "Pilot Wave - Low Risk Applications",
                    "description": "Standalone applications with minimal dependencies",
                    "targetMigrationDate": "2024-Q2",
                    "criteria": {
                        "dependencies": "minimal",
                        "businessCriticality": "low-medium",
                        "complexity": "low"
                    },
                    "estimatedServers": "5-10",
                    "migrationStrategy": "rehost"
                },
                {
                    "waveNumber": 2,
                    "name": "Business Applications Wave", 
                    "description": "Core business applications with managed dependencies",
                    "targetMigrationDate": "2024-Q3",
                    "criteria": {
                        "dependencies": "moderate",
                        "businessCriticality": "medium-high",
                        "complexity": "medium"
                    },
                    "estimatedServers": "15-30",
                    "migrationStrategy": "rehost-replatform"
                },
                {
                    "waveNumber": 3,
                    "name": "Legacy Systems Wave",
                    "description": "Complex legacy systems requiring refactoring",
                    "targetMigrationDate": "2024-Q4",
                    "criteria": {
                        "dependencies": "high",
                        "businessCriticality": "high",
                        "complexity": "high"
                    },
                    "estimatedServers": "20-50",
                    "migrationStrategy": "refactor-modernize"
                }
            ],
            "assessmentCriteria": {
                "applicationDependencies": "Network connection analysis from discovery data",
                "performanceBaseline": "CPU, memory, disk utilization patterns",
                "securityRequirements": "Data classification and compliance needs",
                "businessImpact": "Downtime tolerance and user base size"
            }
        }
        
        # Upload wave planning configuration to S3
        s3.put_object(
            Bucket=os.environ['BUCKET_NAME'],
            Key='planning/migration-waves.json',
            Body=json.dumps(waves_config, indent=2),
            ContentType='application/json'
        )
        
        print(f"Migration wave planning framework uploaded successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Migration wave planning framework created',
                'waves': len(waves_config['waves']),
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error creating wave planning framework: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }
`),
    });

    // Grant permissions to the wave planning function
    this.discoveryDataBucket.grantReadWrite(waveplanningFunction);

    // Custom resource to enable Application Discovery Service
    const discoveryServiceCustomResource = new cr.AwsCustomResource(this, 'EnableDiscoveryService', {
      onCreate: {
        service: 'ApplicationDiscoveryService',
        action: 'startDataCollectionByAgentIds',
        parameters: {
          agentIds: [],
        },
        physicalResourceId: cr.PhysicalResourceId.of('discovery-service-enabled'),
      },
      policy: cr.AwsCustomResourcePolicy.fromStatements([
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'discovery:StartDataCollectionByAgentIds',
            'discovery:DescribeConfigurations',
          ],
          resources: ['*'],
        }),
      ]),
    });

    // Custom resource to create Migration Hub project
    const migrationHubProject = new cr.AwsCustomResource(this, 'MigrationHubProject', {
      onCreate: {
        service: 'MigrationHub',
        action: 'createProgressUpdateStream',
        parameters: {
          ProgressUpdateStreamName: this.migrationProjectName,
        },
        region: 'us-west-2', // Migration Hub home region
        physicalResourceId: cr.PhysicalResourceId.of(`migration-hub-${this.migrationProjectName}`),
      },
      onDelete: {
        service: 'MigrationHub',
        action: 'deleteProgressUpdateStream',
        parameters: {
          ProgressUpdateStreamName: this.migrationProjectName,
        },
        region: 'us-west-2',
      },
      policy: cr.AwsCustomResourcePolicy.fromStatements([
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'mgh:CreateProgressUpdateStream',
            'mgh:DeleteProgressUpdateStream',
            'mgh:DescribeApplicationState',
          ],
          resources: ['*'],
        }),
      ]),
    });

    // Outputs for easy reference
    new cdk.CfnOutput(this, 'DiscoveryDataBucketName', {
      value: this.discoveryDataBucket.bucketName,
      description: 'S3 bucket for storing Application Discovery Service data',
      exportName: `${this.stackName}-DiscoveryDataBucket`,
    });

    new cdk.CfnOutput(this, 'MigrationProjectName', {
      value: this.migrationProjectName,
      description: 'Migration Hub project name for tracking discovery progress',
      exportName: `${this.stackName}-MigrationProject`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch log group for discovery service monitoring',
      exportName: `${this.stackName}-LogGroup`,
    });

    new cdk.CfnOutput(this, 'AgentDownloadWindows', {
      value: 'https://aws-discovery-agent.s3.amazonaws.com/windows/latest/AWSApplicationDiscoveryAgentInstaller.exe',
      description: 'Download URL for Windows Discovery Agent',
    });

    new cdk.CfnOutput(this, 'AgentDownloadLinux', {
      value: 'https://aws-discovery-agent.s3.amazonaws.com/linux/latest/aws-discovery-agent.tar.gz',
      description: 'Download URL for Linux Discovery Agent',
    });

    new cdk.CfnOutput(this, 'ConnectorDownload', {
      value: 'https://aws-discovery-connector.s3.amazonaws.com/VMware/latest/AWS-Discovery-Connector.ova',
      description: 'Download URL for VMware Discovery Connector OVA',
    });

    new cdk.CfnOutput(this, 'ExportAutomationFunction', {
      value: exportAutomationFunction.functionArn,
      description: 'Lambda function ARN for automating discovery data exports',
    });

    new cdk.CfnOutput(this, 'WavePlanningFunction', {
      value: waveplanningFunction.functionArn,
      description: 'Lambda function ARN for migration wave planning',
    });
  }
}

// CDK App instantiation
const app = new cdk.App();

new EnterpriseMigrationAssessmentStack(app, 'EnterpriseMigrationAssessmentStack', {
  description: 'AWS Application Discovery Service infrastructure for enterprise migration assessment',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'EnterpriseMigrationAssessment',
    Environment: 'Production',
    Owner: 'MigrationTeam',
    CostCenter: 'Infrastructure',
  },
});

app.synth();