import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as glue from 'aws-cdk-lib/aws-glue';
import { Construct } from 'constructs';

/**
 * Stack for AWS Application Discovery Service Assessment Infrastructure
 * 
 * This stack creates the necessary AWS infrastructure to support application discovery
 * and assessment activities including:
 * - S3 bucket for discovery data export
 * - IAM roles and policies for Application Discovery Service
 * - Lambda function for automated discovery reporting
 * - EventBridge rule for scheduled discovery exports
 * - Athena database and table for data analysis
 * - Glue catalog table for discovery data schema
 */
export class ApplicationDiscoveryAssessmentStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const accountId = cdk.Stack.of(this).account;
    const region = cdk.Stack.of(this).region;

    // Create S3 bucket for discovery data export with encryption and versioning
    const discoveryBucket = new s3.Bucket(this, 'DiscoveryDataBucket', {
      bucketName: `discovery-data-${accountId}-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'discovery-data-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(2555), // 7 years for compliance
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Application Discovery Service
    const discoveryServiceRole = new iam.Role(this, 'ApplicationDiscoveryServiceRole', {
      roleName: 'ApplicationDiscoveryServiceRole',
      assumedBy: new iam.ServicePrincipal('discovery.amazonaws.com'),
      description: 'Service role for AWS Application Discovery Service continuous export',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/ApplicationDiscoveryServiceContinuousExportServiceRolePolicy'
        ),
      ],
    });

    // Grant discovery service access to the S3 bucket
    discoveryBucket.grantReadWrite(discoveryServiceRole);

    // Create IAM role for Lambda function
    const lambdaExecutionRole = new iam.Role(this, 'DiscoveryAutomationLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Discovery Automation Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DiscoveryOperations: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'discovery:StartExportTask',
                'discovery:DescribeExportTasks',
                'discovery:StopExportTask',
                'discovery:StartContinuousExport',
                'discovery:StopContinuousExport',
                'discovery:DescribeContinuousExports',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Grant Lambda access to the S3 bucket
    discoveryBucket.grantReadWrite(lambdaExecutionRole);

    // Create Lambda function for automated discovery reporting
    const discoveryAutomationFunction = new lambda.Function(this, 'DiscoveryAutomationFunction', {
      functionName: `discovery-automation-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to automate discovery data export tasks
    
    This function can be triggered by EventBridge to:
    - Start export tasks for discovery data
    - Monitor export progress
    - Handle export failures
    """
    try:
        # Initialize AWS clients
        discovery_client = boto3.client('discovery')
        s3_bucket = os.environ['DISCOVERY_BUCKET']
        
        logger.info(f"Starting discovery export to bucket: {s3_bucket}")
        
        # Start export task for all discovery data
        export_response = discovery_client.start_export_task(
            exportDataFormat='CSV',
            s3Bucket=s3_bucket,
            s3Prefix=f'automated-export/{datetime.now().strftime("%Y/%m/%d/%H%M%S")}/'
        )
        
        export_id = export_response['exportId']
        logger.info(f"Started export task with ID: {export_id}")
        
        # Get export status
        status_response = discovery_client.describe_export_tasks(
            exportIds=[export_id]
        )
        
        export_status = status_response['exportsInfo'][0]['exportStatus']
        logger.info(f"Export status: {export_status}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Discovery export started successfully',
                'exportId': export_id,
                'status': export_status,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in discovery automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }
      `),
      environment: {
        DISCOVERY_BUCKET: discoveryBucket.bucketName,
      },
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      description: 'Automated discovery data export function',
    });

    // Create EventBridge rule for scheduled discovery exports
    const discoveryScheduleRule = new events.Rule(this, 'DiscoveryReportSchedule', {
      ruleName: 'DiscoveryReportSchedule',
      schedule: events.Schedule.rate(cdk.Duration.days(7)), // Weekly exports
      description: 'Weekly discovery data export schedule',
    });

    // Add Lambda function as target for the EventBridge rule
    discoveryScheduleRule.addTarget(new targets.LambdaFunction(discoveryAutomationFunction));

    // Create Athena database for discovery data analysis
    const discoveryDatabase = new athena.CfnDatabase(this, 'DiscoveryAnalysisDatabase', {
      catalogId: accountId,
      databaseInput: {
        name: 'discovery_analysis',
        description: 'Database for analyzing AWS Application Discovery Service data',
      },
    });

    // Create Glue catalog table for servers data
    const serversTable = new glue.CfnTable(this, 'ServersTable', {
      catalogId: accountId,
      databaseName: discoveryDatabase.ref,
      tableInput: {
        name: 'servers',
        description: 'Table containing server configuration data from Application Discovery Service',
        tableType: 'EXTERNAL_TABLE',
        parameters: {
          'classification': 'parquet',
          'compressionType': 'gzip',
          'typeOfData': 'file',
        },
        storageDescriptor: {
          columns: [
            {
              name: 'server_configuration_id',
              type: 'string',
              comment: 'Unique identifier for server configuration',
            },
            {
              name: 'server_hostname',
              type: 'string',
              comment: 'Server hostname',
            },
            {
              name: 'server_os_name',
              type: 'string',
              comment: 'Operating system name',
            },
            {
              name: 'server_cpu_type',
              type: 'string',
              comment: 'CPU type and architecture',
            },
            {
              name: 'server_total_ram_kb',
              type: 'bigint',
              comment: 'Total RAM in kilobytes',
            },
            {
              name: 'server_performance_avg_cpu_usage_pct',
              type: 'double',
              comment: 'Average CPU usage percentage',
            },
            {
              name: 'server_performance_max_cpu_usage_pct',
              type: 'double',
              comment: 'Maximum CPU usage percentage',
            },
            {
              name: 'server_performance_avg_free_ram_kb',
              type: 'double',
              comment: 'Average free RAM in kilobytes',
            },
            {
              name: 'server_type',
              type: 'string',
              comment: 'Server type (physical/virtual)',
            },
            {
              name: 'server_hypervisor',
              type: 'string',
              comment: 'Hypervisor type if virtual',
            },
          ],
          location: `s3://${discoveryBucket.bucketName}/continuous-export/servers/`,
          inputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe',
          },
        },
      },
    });

    // Create Athena workgroup for discovery analysis
    const discoveryWorkgroup = new athena.CfnWorkGroup(this, 'DiscoveryAnalysisWorkgroup', {
      name: 'discovery-analysis',
      description: 'Workgroup for analyzing Application Discovery Service data',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${discoveryBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
      },
    });

    // Create IAM role for Athena service
    const athenaServiceRole = new iam.Role(this, 'AthenaServiceRole', {
      assumedBy: new iam.ServicePrincipal('athena.amazonaws.com'),
      description: 'Service role for Athena to access discovery data',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonAthenaFullAccess'),
      ],
    });

    // Grant Athena access to the discovery data bucket
    discoveryBucket.grantReadWrite(athenaServiceRole);

    // Output important resource information
    new cdk.CfnOutput(this, 'DiscoveryBucketName', {
      value: discoveryBucket.bucketName,
      description: 'Name of the S3 bucket for discovery data export',
      exportName: 'DiscoveryBucketName',
    });

    new cdk.CfnOutput(this, 'DiscoveryServiceRoleArn', {
      value: discoveryServiceRole.roleArn,
      description: 'ARN of the IAM role for Application Discovery Service',
      exportName: 'DiscoveryServiceRoleArn',
    });

    new cdk.CfnOutput(this, 'DiscoveryAutomationFunctionArn', {
      value: discoveryAutomationFunction.functionArn,
      description: 'ARN of the Lambda function for discovery automation',
      exportName: 'DiscoveryAutomationFunctionArn',
    });

    new cdk.CfnOutput(this, 'AthenaDatabaseName', {
      value: discoveryDatabase.ref,
      description: 'Name of the Athena database for discovery analysis',
      exportName: 'AthenaDatabaseName',
    });

    new cdk.CfnOutput(this, 'AthenaWorkgroupName', {
      value: discoveryWorkgroup.name!,
      description: 'Name of the Athena workgroup for discovery analysis',
      exportName: 'AthenaWorkgroupName',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ApplicationDiscoveryAssessment');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'Migration Team');
    cdk.Tags.of(this).add('Purpose', 'Infrastructure Discovery and Assessment');
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new ApplicationDiscoveryAssessmentStack(app, 'ApplicationDiscoveryAssessmentStack', {
  description: 'AWS Application Discovery Service Assessment Infrastructure',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the CloudFormation template
app.synth();