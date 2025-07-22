#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, RemovalPolicy, Duration } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cfn from 'aws-cdk-lib/aws-cloudformation';
import { CfnApplication } from 'aws-cdk-lib/aws-serverlessrepo';

/**
 * Stack for deploying serverless analytics with Athena federated query
 * This stack creates the infrastructure needed for cross-source analytics
 * across RDS MySQL, DynamoDB, and other data sources using Athena
 */
export class ServerlessAnalyticsAthenaFederatedQueryStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC for database connectivity
    const vpc = new ec2.Vpc(this, 'AthenaFederatedVpc', {
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for private database access
      cidr: '10.0.0.0/16',
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'DatabaseSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Security group for database access
    const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for Athena federated query database access',
      allowAllOutbound: true,
    });

    // Allow MySQL traffic within the security group
    databaseSecurityGroup.addIngressRule(
      databaseSecurityGroup,
      ec2.Port.tcp(3306),
      'Allow MySQL access from Lambda connectors'
    );

    // Create S3 buckets for Athena spill data and query results
    const spillBucket = new s3.Bucket(this, 'AthenaSpillBucket', {
      bucketName: `athena-federated-spill-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteSpillDataAfter1Day',
          enabled: true,
          expiration: Duration.days(1),
        },
      ],
    });

    const resultsBucket = new s3.Bucket(this, 'AthenaResultsBucket', {
      bucketName: `athena-federated-results-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteResultsAfter30Days',
          enabled: true,
          expiration: Duration.days(30),
        },
      ],
    });

    // Create RDS MySQL instance for sample data
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      description: 'Subnet group for Athena federated query database',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    const mysqlDatabase = new rds.DatabaseInstance(this, 'MySQLDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        secretName: `athena-federated-mysql-secret-${uniqueSuffix}`,
      }),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [databaseSecurityGroup],
      subnetGroup: dbSubnetGroup,
      allocatedStorage: 20,
      storageType: rds.StorageType.GP2,
      databaseName: 'analytics_db',
      deletionProtection: false,
      removalPolicy: RemovalPolicy.DESTROY,
      backupRetention: Duration.days(0), // No backup for demo
      monitoringInterval: Duration.seconds(0), // No enhanced monitoring
      cloudwatchLogsExports: ['error', 'general', 'slow-query'],
    });

    // Create DynamoDB table for order tracking data
    const ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      tableName: `Orders-${uniqueSuffix}`,
      partitionKey: {
        name: 'order_id',
        type: dynamodb.AttributeType.STRING,
      },
      billing: dynamodb.Billing.provisioned({
        readCapacity: 5,
        writeCapacity: 5,
      }),
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: false,
    });

    // IAM role for Lambda connectors
    const connectorRole = new iam.Role(this, 'ConnectorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
      ],
      inlinePolicies: {
        AthenaConnectorPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for spill bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:GetObjectVersion',
                's3:PutObjectAcl',
              ],
              resources: [spillBucket.bucketArn, `${spillBucket.bucketArn}/*`],
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:GetItem',
                'dynamodb:BatchGetItem',
                'dynamodb:DescribeTable',
                'dynamodb:ListTables',
              ],
              resources: [ordersTable.tableArn],
            }),
            // RDS permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rds:DescribeDBInstances',
                'rds:DescribeDBClusters',
              ],
              resources: ['*'],
            }),
            // Secrets Manager permissions for database credentials
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'secretsmanager:GetSecretValue',
                'secretsmanager:DescribeSecret',
              ],
              resources: [mysqlDatabase.secret!.secretArn],
            }),
            // KMS permissions for encrypted resources
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey',
                'kms:GenerateDataKey',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Deploy MySQL connector using CloudFormation nested stack
    const mysqlConnectorStack = new cfn.CfnStack(this, 'MySQLConnectorStack', {
      templateUrl: 'https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC-2.0.32.1000/docs/Simba+Amazon+Athena+JDBC+Connector+Install+and+Configuration+Guide.pdf',
      parameters: {
        LambdaFunctionName: `athena-mysql-connector-${uniqueSuffix}`,
        DefaultConnectionString: `mysql://jdbc:mysql://${mysqlDatabase.instanceEndpoint.hostname}:3306/analytics_db`,
        SpillBucket: spillBucket.bucketName,
        LambdaMemory: '3008',
        LambdaTimeout: '900',
        SecurityGroupIds: databaseSecurityGroup.securityGroupId,
        SubnetIds: vpc.privateSubnets.map(subnet => subnet.subnetId).join(','),
        LambdaRole: connectorRole.roleArn,
      },
    });

    // Deploy DynamoDB connector using ServerlessRepo
    const dynamodbConnector = new CfnApplication(this, 'DynamoDBConnector', {
      location: {
        applicationId: 'arn:aws:serverlessrepo:us-east-1:292517598671:applications/AthenaDynamoDBConnector',
        semanticVersion: '2023.47.1',
      },
      parameters: {
        LambdaFunctionName: `athena-dynamodb-connector-${uniqueSuffix}`,
        SpillBucket: spillBucket.bucketName,
        LambdaMemory: '3008',
        LambdaTimeout: '900',
        LambdaRole: connectorRole.roleArn,
      },
    });

    // Create Athena workgroup for federated queries
    const workgroup = new athena.CfnWorkGroup(this, 'FederatedAnalyticsWorkgroup', {
      name: `federated-analytics-${uniqueSuffix}`,
      description: 'Workgroup for federated query analytics',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${resultsBucket.bucketName}/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
      },
    });

    // Create Lambda function for initializing sample data
    const initDataFunction = new lambda.Function(this, 'InitDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import pymysql
import os

def handler(event, context):
    # Initialize DynamoDB table with sample data
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('${ordersTable.tableName}')
    
    # Sample order tracking data
    sample_data = [
        {
            'order_id': '1001',
            'status': 'shipped',
            'tracking_number': 'TRK123456',
            'carrier': 'FedEx'
        },
        {
            'order_id': '1002',
            'status': 'processing',
            'tracking_number': 'TRK789012',
            'carrier': 'UPS'
        },
        {
            'order_id': '1003',
            'status': 'delivered',
            'tracking_number': 'TRK345678',
            'carrier': 'USPS'
        }
    ]
    
    for item in sample_data:
        table.put_item(Item=item)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Sample data initialized successfully')
    }
      `),
      timeout: Duration.minutes(5),
      environment: {
        DYNAMODB_TABLE: ordersTable.tableName,
      },
    });

    // Grant permissions to the init function
    ordersTable.grantWriteData(initDataFunction);

    // Custom resource to invoke the init function
    const initDataProvider = new lambda.Provider(this, 'InitDataProvider', {
      onEventHandler: initDataFunction,
    });

    new cdk.CustomResource(this, 'InitDataResource', {
      serviceToken: initDataProvider.serviceToken,
    });

    // Outputs
    new cdk.CfnOutput(this, 'SpillBucketName', {
      value: spillBucket.bucketName,
      description: 'S3 bucket for Athena spill data',
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket for Athena query results',
    });

    new cdk.CfnOutput(this, 'MySQLEndpoint', {
      value: mysqlDatabase.instanceEndpoint.hostname,
      description: 'RDS MySQL database endpoint',
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: ordersTable.tableName,
      description: 'DynamoDB table name for order tracking',
    });

    new cdk.CfnOutput(this, 'WorkgroupName', {
      value: workgroup.name!,
      description: 'Athena workgroup for federated analytics',
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: mysqlDatabase.secret!.secretArn,
      description: 'ARN of the RDS database secret',
    });

    // Sample queries for testing
    new cdk.CfnOutput(this, 'SampleFederatedQuery', {
      value: `
SELECT 
    mysql_orders.order_id,
    mysql_orders.customer_id,
    mysql_orders.product_name,
    mysql_orders.quantity,
    mysql_orders.price,
    mysql_orders.order_date,
    ddb_tracking.status as shipment_status,
    ddb_tracking.tracking_number,
    ddb_tracking.carrier
FROM mysql_catalog.analytics_db.sample_orders mysql_orders
LEFT JOIN dynamodb_catalog.default.${ordersTable.tableName} ddb_tracking
ON CAST(mysql_orders.order_id AS VARCHAR) = ddb_tracking.order_id
ORDER BY mysql_orders.order_date DESC
LIMIT 10;
      `,
      description: 'Sample federated query to join MySQL and DynamoDB data',
    });
  }
}

// CDK App
const app = new cdk.App();

new ServerlessAnalyticsAthenaFederatedQueryStack(app, 'ServerlessAnalyticsAthenaFederatedQueryStack', {
  description: 'Stack for deploying serverless analytics with Athena federated query (uksb-1tupboc57)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ServerlessAnalytics',
    Component: 'AthenaFederatedQuery',
    Environment: 'Demo',
    CostCenter: 'Analytics',
  },
});

app.synth();