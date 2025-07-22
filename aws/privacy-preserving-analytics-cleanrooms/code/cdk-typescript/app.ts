#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as path from 'path';

/**
 * CDK Stack for Privacy-Preserving Data Analytics with AWS Clean Rooms and QuickSight
 * 
 * This stack creates infrastructure for secure multi-party data collaboration
 * using AWS Clean Rooms with differential privacy protections and QuickSight
 * visualization capabilities.
 */
export class PrivacyPreservingAnalyticsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // ==========================================================================
    // S3 BUCKETS FOR DATA STORAGE
    // ==========================================================================

    // S3 bucket for Organization A data
    const orgABucket = new s3.Bucket(this, 'OrganizationADataBucket', {
      bucketName: `clean-rooms-data-a-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 bucket for Organization B data
    const orgBBucket = new s3.Bucket(this, 'OrganizationBDataBucket', {
      bucketName: `clean-rooms-data-b-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 bucket for Clean Rooms query results
    const resultsBucket = new s3.Bucket(this, 'CleanRoomsResultsBucket', {
      bucketName: `clean-rooms-results-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ==========================================================================
    // IAM ROLES FOR CLEAN ROOMS AND GLUE
    // ==========================================================================

    // IAM role for AWS Glue service
    const glueRole = new iam.Role(this, 'GlueCleanRoomsRole', {
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue to access Clean Rooms data sources',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
    });

    // Add custom policy for S3 access to Glue role
    glueRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:ListBucket',
        's3:PutObject',
      ],
      resources: [
        orgABucket.bucketArn,
        `${orgABucket.bucketArn}/*`,
        orgBBucket.bucketArn,
        `${orgBBucket.bucketArn}/*`,
        resultsBucket.bucketArn,
        `${resultsBucket.bucketArn}/*`,
      ],
    }));

    // IAM role for AWS Clean Rooms service
    const cleanRoomsRole = new iam.Role(this, 'CleanRoomsAnalyticsRole', {
      assumedBy: new iam.ServicePrincipal('cleanrooms.amazonaws.com'),
      description: 'IAM role for AWS Clean Rooms to access configured data sources',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSCleanRoomsService'),
      ],
    });

    // Add custom policy for Clean Rooms to access S3 and Glue
    cleanRoomsRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:ListBucket',
        's3:PutObject',
      ],
      resources: [
        orgABucket.bucketArn,
        `${orgABucket.bucketArn}/*`,
        orgBBucket.bucketArn,
        `${orgBBucket.bucketArn}/*`,
        resultsBucket.bucketArn,
        `${resultsBucket.bucketArn}/*`,
      ],
    }));

    cleanRoomsRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'glue:GetTable',
        'glue:GetTables',
        'glue:GetDatabase',
      ],
      resources: ['*'],
    }));

    // ==========================================================================
    // SAMPLE DATA DEPLOYMENT
    // ==========================================================================

    // Create sample data for Organization A
    const orgAData = `customer_id,age_group,region,purchase_amount,product_category,registration_date
1001,25-34,east,250.00,electronics,2023-01-15
1002,35-44,west,180.50,clothing,2023-02-20
1003,45-54,central,320.75,home,2023-01-10
1004,25-34,east,95.25,books,2023-03-05
1005,55-64,west,450.00,electronics,2023-02-28
1006,25-34,central,180.00,electronics,2023-01-25
1007,35-44,east,275.50,clothing,2023-02-15
1008,45-54,west,395.25,home,2023-03-01
1009,25-34,central,125.75,books,2023-02-10
1010,55-64,east,520.00,electronics,2023-03-12`;

    // Create sample data for Organization B
    const orgBData = `customer_id,age_group,region,engagement_score,channel_preference,last_interaction
2001,25-34,east,85,email,2023-03-15
2002,35-44,west,72,social,2023-03-20
2003,45-54,central,91,email,2023-03-10
2004,25-34,east,68,mobile,2023-03-25
2005,55-64,west,88,email,2023-03-18
2006,25-34,central,76,mobile,2023-03-08
2007,35-44,east,82,email,2023-03-22
2008,45-54,west,94,social,2023-03-05
2009,25-34,central,69,mobile,2023-03-14
2010,55-64,east,87,email,2023-03-20`;

    // Deploy sample data to S3 buckets using inline content
    new s3deploy.BucketDeployment(this, 'OrgADataDeployment', {
      sources: [
        s3deploy.Source.data('data/customer_data_org_a.csv', orgAData)
      ],
      destinationBucket: orgABucket,
    });

    new s3deploy.BucketDeployment(this, 'OrgBDataDeployment', {
      sources: [
        s3deploy.Source.data('data/customer_data_org_b.csv', orgBData)
      ],
      destinationBucket: orgBBucket,
    });

    // ==========================================================================
    // AWS GLUE DATABASE AND CRAWLERS
    // ==========================================================================

    // Create Glue database for Clean Rooms analytics
    const glueDatabase = new glue.CfnDatabase(this, 'CleanRoomsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `clean_rooms_analytics_${uniqueSuffix.replace(/-/g, '_')}`,
        description: 'Clean Rooms analytics database for privacy-preserving collaboration',
      },
    });

    // Glue crawler for Organization A data
    const crawlerOrgA = new glue.CfnCrawler(this, 'CrawlerOrganizationA', {
      name: `crawler-org-a-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for Organization A customer data',
      targets: {
        s3Targets: [
          {
            path: `s3://${orgABucket.bucketName}/data/`,
          },
        ],
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // Glue crawler for Organization B data
    const crawlerOrgB = new glue.CfnCrawler(this, 'CrawlerOrganizationB', {
      name: `crawler-org-b-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for Organization B customer data',
      targets: {
        s3Targets: [
          {
            path: `s3://${orgBBucket.bucketName}/data/`,
          },
        ],
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // Ensure crawlers depend on the database and data deployment
    crawlerOrgA.addDependency(glueDatabase);
    crawlerOrgB.addDependency(glueDatabase);

    // ==========================================================================
    // QUICKSIGHT RESOURCES
    // ==========================================================================

    // QuickSight data source for Clean Rooms results
    const quickSightDataSource = new quicksight.CfnDataSource(this, 'QuickSightDataSource', {
      awsAccountId: this.account,
      dataSourceId: `clean-rooms-results-${uniqueSuffix}`,
      name: 'Clean Rooms Analytics Results',
      type: 'S3',
      dataSourceParameters: {
        s3Parameters: {
          manifestFileLocation: {
            bucket: resultsBucket.bucketName,
            key: 'query-results/',
          },
        },
      },
      permissions: [
        {
          principal: `arn:aws:iam::${this.account}:root`,
          actions: [
            'quicksight:DescribeDataSource',
            'quicksight:DescribeDataSourcePermissions',
            'quicksight:PassDataSource',
            'quicksight:UpdateDataSource',
            'quicksight:DeleteDataSource',
            'quicksight:UpdateDataSourcePermissions',
          ],
        },
      ],
    });

    // ==========================================================================
    // OUTPUTS
    // ==========================================================================

    new cdk.CfnOutput(this, 'OrganizationABucketName', {
      value: orgABucket.bucketName,
      description: 'S3 bucket name for Organization A data',
      exportName: `${this.stackName}-OrgABucket`,
    });

    new cdk.CfnOutput(this, 'OrganizationBBucketName', {
      value: orgBBucket.bucketName,
      description: 'S3 bucket name for Organization B data',
      exportName: `${this.stackName}-OrgBBucket`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket name for Clean Rooms query results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Glue database name for Clean Rooms analytics',
      exportName: `${this.stackName}-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'CleanRoomsRoleArn', {
      value: cleanRoomsRole.roleArn,
      description: 'IAM role ARN for Clean Rooms service',
      exportName: `${this.stackName}-CleanRoomsRole`,
    });

    new cdk.CfnOutput(this, 'GlueRoleArn', {
      value: glueRole.roleArn,
      description: 'IAM role ARN for Glue service',
      exportName: `${this.stackName}-GlueRole`,
    });

    new cdk.CfnOutput(this, 'CrawlerOrganizationAName', {
      value: crawlerOrgA.name!,
      description: 'Glue crawler name for Organization A data',
      exportName: `${this.stackName}-CrawlerOrgA`,
    });

    new cdk.CfnOutput(this, 'CrawlerOrganizationBName', {
      value: crawlerOrgB.name!,
      description: 'Glue crawler name for Organization B data',
      exportName: `${this.stackName}-CrawlerOrgB`,
    });

    new cdk.CfnOutput(this, 'QuickSightDataSourceId', {
      value: quickSightDataSource.dataSourceId!,
      description: 'QuickSight data source ID for Clean Rooms results',
      exportName: `${this.stackName}-QuickSightDataSource`,
    });

    // Manual setup instructions
    new cdk.CfnOutput(this, 'ManualSetupInstructions', {
      value: 'After deployment: 1) Run Glue crawlers, 2) Create Clean Rooms collaboration, 3) Configure tables and associations, 4) Execute privacy-preserving queries',
      description: 'Manual setup steps required after CDK deployment',
    });

    // Tags for resource governance
    cdk.Tags.of(this).add('Project', 'PrivacyPreservingAnalytics');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Owner', 'DataAnalyticsTeam');
    cdk.Tags.of(this).add('Purpose', 'CleanRoomsQuickSightIntegration');
  }
}

// ==========================================================================
// CDK APPLICATION
// ==========================================================================

const app = new cdk.App();

// Get deployment parameters from context or environment
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
  region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1',
};

// Create the main stack
new PrivacyPreservingAnalyticsStack(app, 'PrivacyPreservingAnalyticsStack', {
  env,
  description: 'Privacy-preserving data analytics with AWS Clean Rooms and QuickSight (uksb-1tupboc57)',
  stackName: app.node.tryGetContext('stackName') || 'privacy-preserving-analytics',
  tags: {
    Application: 'PrivacyPreservingAnalytics',
    CreatedBy: 'CDK',
    Purpose: 'CleanRoomsDemo',
  },
});

// Synthesize the CDK application
app.synth();