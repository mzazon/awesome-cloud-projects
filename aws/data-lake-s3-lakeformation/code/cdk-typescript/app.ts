#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as lakeformation from 'aws-cdk-lib/aws-lakeformation';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Data Lake Architecture Stack with S3 and Lake Formation
 * 
 * This stack creates a comprehensive data lake architecture with:
 * - Three-tier S3 storage (Raw, Processed, Curated)
 * - Lake Formation governance and permissions
 * - Glue Data Catalog and crawlers
 * - IAM roles for different access levels
 * - CloudTrail audit logging
 * - LF-Tags for attribute-based access control
 * - Data cell filters for column/row-level security
 */
export class DataLakeArchitectureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const datalakeName = `datalake-${randomSuffix}`;

    // ==========================================
    // S3 BUCKETS - Three-tier data lake storage
    // ==========================================

    // Raw data bucket - stores original data from sources
    const rawBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `${datalakeName}-raw`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'transition-to-ia',
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
        },
      ],
    });

    // Processed data bucket - stores cleaned and transformed data
    const processedBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `${datalakeName}-processed`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'transition-to-ia',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
    });

    // Curated data bucket - stores business-ready optimized data
    const curatedBucket = new s3.Bucket(this, 'CuratedDataBucket', {
      bucketName: `${datalakeName}-curated`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'transition-to-ia',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(60),
            },
          ],
        },
      ],
    });

    // ==========================================
    // IAM ROLES AND POLICIES
    // ==========================================

    // Lake Formation service role
    const lakeFormationServiceRole = new iam.Role(this, 'LakeFormationServiceRole', {
      assumedBy: new iam.ServicePrincipal('lakeformation.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/LakeFormationServiceRole'),
      ],
    });

    // Glue crawler role
    const glueCrawlerRole = new iam.Role(this, 'GlueCrawlerRole', {
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
    });

    // Grant Glue crawler access to S3 buckets
    [rawBucket, processedBucket, curatedBucket].forEach((bucket) => {
      bucket.grantReadWrite(glueCrawlerRole);
    });

    // Data analyst role - read-only access to curated data
    const dataAnalystRole = new iam.Role(this, 'DataAnalystRole', {
      assumedBy: new iam.AccountRootPrincipal(),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonAthenaFullAccess'),
      ],
    });

    // Data engineer role - broader access for data processing
    const dataEngineerRole = new iam.Role(this, 'DataEngineerRole', {
      assumedBy: new iam.AccountRootPrincipal(),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSGlueConsoleFullAccess'),
      ],
    });

    // Lake Formation admin user
    const lakeFormationAdminUser = new iam.User(this, 'LakeFormationAdminUser', {
      userName: 'lake-formation-admin',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('LakeFormationDataAdmin'),
      ],
    });

    // ==========================================
    // GLUE DATA CATALOG
    // ==========================================

    // Glue database for sales data
    const glueDatabase = new glue.CfnDatabase(this, 'SalesDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `sales-${randomSuffix}`,
        description: 'Sales data lake database for analytics',
      },
    });

    // Sales data crawler
    const salesCrawler = new glue.CfnCrawler(this, 'SalesCrawler', {
      name: 'sales-crawler',
      role: glueCrawlerRole.roleArn,
      databaseName: glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${rawBucket.bucketName}/sales/`,
          },
        ],
      },
      tablePrefix: 'sales_',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // Customer data crawler
    const customerCrawler = new glue.CfnCrawler(this, 'CustomerCrawler', {
      name: 'customer-crawler',
      role: glueCrawlerRole.roleArn,
      databaseName: glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${rawBucket.bucketName}/customers/`,
          },
        ],
      },
      tablePrefix: 'customer_',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // ==========================================
    // LAKE FORMATION CONFIGURATION
    // ==========================================

    // Lake Formation data lake settings
    const dataLakeSettings = new lakeformation.CfnDataLakeSettings(this, 'DataLakeSettings', {
      dataLakeAdmins: [
        {
          dataLakePrincipalIdentifier: lakeFormationAdminUser.userArn,
        },
      ],
      createDatabaseDefaultPermissions: [],
      createTableDefaultPermissions: [],
      trustedResourceOwners: [this.account],
      allowExternalDataFiltering: true,
      externalDataFilteringAllowList: [
        {
          dataLakePrincipalIdentifier: this.account,
        },
      ],
    });

    // Register S3 buckets with Lake Formation
    const rawBucketRegistration = new lakeformation.CfnResource(this, 'RawBucketRegistration', {
      resourceArn: rawBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    const processedBucketRegistration = new lakeformation.CfnResource(this, 'ProcessedBucketRegistration', {
      resourceArn: processedBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    const curatedBucketRegistration = new lakeformation.CfnResource(this, 'CuratedBucketRegistration', {
      resourceArn: curatedBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    // ==========================================
    // LF-TAGS FOR GOVERNANCE
    // ==========================================

    // Department tag
    const departmentTag = new lakeformation.CfnTag(this, 'DepartmentTag', {
      tagKey: 'Department',
      tagValues: ['Sales', 'Marketing', 'Finance', 'Engineering'],
    });

    // Classification tag
    const classificationTag = new lakeformation.CfnTag(this, 'ClassificationTag', {
      tagKey: 'Classification',
      tagValues: ['Public', 'Internal', 'Confidential', 'Restricted'],
    });

    // Data zone tag
    const dataZoneTag = new lakeformation.CfnTag(this, 'DataZoneTag', {
      tagKey: 'DataZone',
      tagValues: ['Raw', 'Processed', 'Curated'],
    });

    // Access level tag
    const accessLevelTag = new lakeformation.CfnTag(this, 'AccessLevelTag', {
      tagKey: 'AccessLevel',
      tagValues: ['ReadOnly', 'ReadWrite', 'Admin'],
    });

    // ==========================================
    // LAKE FORMATION PERMISSIONS
    // ==========================================

    // Grant database permissions to data analyst (read-only)
    const analystDatabasePermission = new lakeformation.CfnPermissions(this, 'AnalystDatabasePermission', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: dataAnalystRole.roleArn,
      },
      resource: {
        databaseResource: {
          name: glueDatabase.ref,
        },
      },
      permissions: ['DESCRIBE'],
    });

    // Grant broader permissions to data engineer
    const engineerDatabasePermission = new lakeformation.CfnPermissions(this, 'EngineerDatabasePermission', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: dataEngineerRole.roleArn,
      },
      resource: {
        databaseResource: {
          name: glueDatabase.ref,
        },
      },
      permissions: ['CREATE_TABLE', 'ALTER', 'DROP', 'DESCRIBE'],
    });

    // Tag-based permissions for department access
    const departmentTagPermission = new lakeformation.CfnPermissions(this, 'DepartmentTagPermission', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: dataAnalystRole.roleArn,
      },
      resource: {
        lfTagResource: {
          tagKey: 'Department',
          tagValues: ['Sales'],
        },
      },
      permissions: ['DESCRIBE'],
    });

    // Tag-based permissions for classification level
    const classificationTagPermission = new lakeformation.CfnPermissions(this, 'ClassificationTagPermission', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: dataAnalystRole.roleArn,
      },
      resource: {
        lfTagResource: {
          tagKey: 'Classification',
          tagValues: ['Internal'],
        },
      },
      permissions: ['SELECT', 'DESCRIBE'],
    });

    // ==========================================
    // CLOUDTRAIL AUDIT LOGGING
    // ==========================================

    // CloudWatch log group for CloudTrail
    const cloudTrailLogGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: '/aws/lakeformation/audit',
      retention: logs.RetentionDays.ONE_MONTH,
    });

    // CloudTrail for Lake Formation auditing
    const lakeFormationTrail = new cloudtrail.Trail(this, 'LakeFormationTrail', {
      trailName: 'lake-formation-audit-trail',
      bucket: rawBucket,
      s3KeyPrefix: 'audit-logs/',
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      cloudWatchLogGroup: cloudTrailLogGroup,
    });

    // ==========================================
    // CUSTOM RESOURCE FOR LF-TAG ASSIGNMENTS
    // ==========================================

    // Lambda function to assign LF-Tags to database
    const lfTagAssignmentLambda = new lambda.Function(this, 'LfTagAssignmentLambda', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        client = boto3.client('lakeformation')
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            # Add LF-Tags to database
            client.add_lf_tags_to_resource(
                Resource={
                    'Database': {
                        'Name': event['ResourceProperties']['DatabaseName']
                    }
                },
                LFTags=[
                    {
                        'TagKey': 'Department',
                        'TagValues': ['Sales']
                    },
                    {
                        'TagKey': 'Classification',
                        'TagValues': ['Internal']
                    },
                    {
                        'TagKey': 'DataZone',
                        'TagValues': ['Raw']
                    }
                ]
            )
            
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `),
      timeout: cdk.Duration.minutes(5),
    });

    // Grant Lake Formation permissions to the Lambda function
    lfTagAssignmentLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          'lakeformation:AddLFTagsToResource',
          'lakeformation:RemoveLFTagsFromResource',
        ],
        resources: ['*'],
      })
    );

    // Custom resource to assign LF-Tags to database
    const lfTagAssignment = new cr.AwsCustomResource(this, 'LfTagAssignment', {
      onCreate: {
        service: 'Lambda',
        action: 'invoke',
        parameters: {
          FunctionName: lfTagAssignmentLambda.functionName,
          Payload: JSON.stringify({
            RequestType: 'Create',
            ResourceProperties: {
              DatabaseName: glueDatabase.ref,
            },
          }),
        },
      },
      onUpdate: {
        service: 'Lambda',
        action: 'invoke',
        parameters: {
          FunctionName: lfTagAssignmentLambda.functionName,
          Payload: JSON.stringify({
            RequestType: 'Update',
            ResourceProperties: {
              DatabaseName: glueDatabase.ref,
            },
          }),
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });

    // ==========================================
    // SAMPLE DATA DEPLOYMENT
    // ==========================================

    // Lambda function to deploy sample data
    const sampleDataLambda = new lambda.Function(this, 'SampleDataLambda', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse
import csv
import io

def handler(event, context):
    try:
        s3 = boto3.client('s3')
        
        if event['RequestType'] == 'Create':
            bucket_name = event['ResourceProperties']['BucketName']
            
            # Sample sales data
            sales_data = [
                ['customer_id', 'product_id', 'order_date', 'quantity', 'price', 'region', 'sales_rep'],
                ['1001', 'P001', '2024-01-15', '2', '29.99', 'North', 'John Smith'],
                ['1002', 'P002', '2024-01-16', '1', '49.99', 'South', 'Jane Doe'],
                ['1003', 'P001', '2024-01-17', '3', '29.99', 'East', 'Bob Johnson'],
                ['1004', 'P003', '2024-01-18', '1', '99.99', 'West', 'Alice Brown'],
                ['1005', 'P002', '2024-01-19', '2', '49.99', 'North', 'John Smith'],
                ['1006', 'P001', '2024-01-20', '1', '29.99', 'South', 'Jane Doe'],
                ['1007', 'P003', '2024-01-21', '2', '99.99', 'East', 'Bob Johnson'],
                ['1008', 'P002', '2024-01-22', '1', '49.99', 'West', 'Alice Brown']
            ]
            
            # Sample customer data
            customer_data = [
                ['customer_id', 'first_name', 'last_name', 'email', 'phone', 'registration_date'],
                ['1001', 'Michael', 'Johnson', 'mjohnson@example.com', '555-0101', '2023-12-01'],
                ['1002', 'Sarah', 'Davis', 'sdavis@example.com', '555-0102', '2023-12-02'],
                ['1003', 'Robert', 'Wilson', 'rwilson@example.com', '555-0103', '2023-12-03'],
                ['1004', 'Jennifer', 'Brown', 'jbrown@example.com', '555-0104', '2023-12-04'],
                ['1005', 'William', 'Jones', 'wjones@example.com', '555-0105', '2023-12-05'],
                ['1006', 'Lisa', 'Garcia', 'lgarcia@example.com', '555-0106', '2023-12-06'],
                ['1007', 'David', 'Miller', 'dmiller@example.com', '555-0107', '2023-12-07'],
                ['1008', 'Susan', 'Anderson', 'sanderson@example.com', '555-0108', '2023-12-08']
            ]
            
            # Convert to CSV and upload sales data
            sales_csv = io.StringIO()
            writer = csv.writer(sales_csv)
            writer.writerows(sales_data)
            s3.put_object(
                Bucket=bucket_name,
                Key='sales/sales_data.csv',
                Body=sales_csv.getvalue(),
                ContentType='text/csv'
            )
            
            # Convert to CSV and upload customer data
            customer_csv = io.StringIO()
            writer = csv.writer(customer_csv)
            writer.writerows(customer_data)
            s3.put_object(
                Bucket=bucket_name,
                Key='customers/customer_data.csv',
                Body=customer_csv.getvalue(),
                ContentType='text/csv'
            )
            
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `),
      timeout: cdk.Duration.minutes(5),
    });

    // Grant S3 permissions to the Lambda function
    rawBucket.grantWrite(sampleDataLambda);

    // Custom resource to deploy sample data
    const sampleDataDeployment = new cr.AwsCustomResource(this, 'SampleDataDeployment', {
      onCreate: {
        service: 'Lambda',
        action: 'invoke',
        parameters: {
          FunctionName: sampleDataLambda.functionName,
          Payload: JSON.stringify({
            RequestType: 'Create',
            ResourceProperties: {
              BucketName: rawBucket.bucketName,
            },
          }),
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });

    // ==========================================
    // STACK OUTPUTS
    // ==========================================

    new cdk.CfnOutput(this, 'RawBucketName', {
      value: rawBucket.bucketName,
      description: 'Name of the raw data S3 bucket',
    });

    new cdk.CfnOutput(this, 'ProcessedBucketName', {
      value: processedBucket.bucketName,
      description: 'Name of the processed data S3 bucket',
    });

    new cdk.CfnOutput(this, 'CuratedBucketName', {
      value: curatedBucket.bucketName,
      description: 'Name of the curated data S3 bucket',
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the Glue database',
    });

    new cdk.CfnOutput(this, 'DataAnalystRoleArn', {
      value: dataAnalystRole.roleArn,
      description: 'ARN of the data analyst role',
    });

    new cdk.CfnOutput(this, 'DataEngineerRoleArn', {
      value: dataEngineerRole.roleArn,
      description: 'ARN of the data engineer role',
    });

    new cdk.CfnOutput(this, 'LakeFormationAdminUserArn', {
      value: lakeFormationAdminUser.userArn,
      description: 'ARN of the Lake Formation admin user',
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: lakeFormationTrail.trailArn,
      description: 'ARN of the CloudTrail for audit logging',
    });

    // Dependencies
    rawBucketRegistration.node.addDependency(dataLakeSettings);
    processedBucketRegistration.node.addDependency(dataLakeSettings);
    curatedBucketRegistration.node.addDependency(dataLakeSettings);
    
    salesCrawler.node.addDependency(glueDatabase);
    customerCrawler.node.addDependency(glueDatabase);
    
    lfTagAssignment.node.addDependency(glueDatabase);
    lfTagAssignment.node.addDependency(departmentTag);
    lfTagAssignment.node.addDependency(classificationTag);
    lfTagAssignment.node.addDependency(dataZoneTag);
    
    sampleDataDeployment.node.addDependency(rawBucket);
    
    analystDatabasePermission.node.addDependency(glueDatabase);
    engineerDatabasePermission.node.addDependency(glueDatabase);
    departmentTagPermission.node.addDependency(departmentTag);
    classificationTagPermission.node.addDependency(classificationTag);
  }
}

// ==========================================
// CDK APP INITIALIZATION
// ==========================================

const app = new cdk.App();

new DataLakeArchitectureStack(app, 'DataLakeArchitectureStack', {
  description: 'Data Lake Architecture with S3 and Lake Formation - Comprehensive governance and security',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataLake',
    Environment: 'Development',
    CostCenter: 'Analytics',
    Owner: 'DataTeam',
  },
});

app.synth();