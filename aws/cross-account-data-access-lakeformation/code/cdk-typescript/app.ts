#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lakeformation from 'aws-cdk-lib/aws-lakeformation';
import * as ram from 'aws-cdk-lib/aws-ram';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * Properties for the Lake Formation Producer Stack
 */
interface LakeFormationProducerStackProps extends cdk.StackProps {
  /**
   * The AWS account ID of the consumer account to share data with
   */
  readonly consumerAccountId: string;
  
  /**
   * Optional prefix for resource names to avoid conflicts
   */
  readonly resourcePrefix?: string;
}

/**
 * Properties for the Lake Formation Consumer Stack
 */
interface LakeFormationConsumerStackProps extends cdk.StackProps {
  /**
   * The AWS account ID of the producer account that shares data
   */
  readonly producerAccountId: string;
  
  /**
   * The name of the shared database from the producer account
   */
  readonly sharedDatabaseName: string;
  
  /**
   * Optional prefix for resource names to avoid conflicts
   */
  readonly resourcePrefix?: string;
}

/**
 * Producer Stack - Creates data lake resources and shares them via Lake Formation
 * This stack should be deployed in the account that owns the data
 */
class LakeFormationProducerStack extends cdk.Stack {
  public readonly dataLakeBucket: s3.Bucket;
  public readonly financialDatabase: glue.CfnDatabase;
  public readonly customerDatabase: glue.CfnDatabase;
  public readonly resourceShareArn: string;

  constructor(scope: Construct, id: string, props: LakeFormationProducerStackProps) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'lf-producer';

    // Create S3 bucket for data lake storage
    this.dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `${resourcePrefix}-data-lake-${this.account}-${Date.now()}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Deploy sample data to S3 bucket
    new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [
        s3deploy.Source.data('financial-reports/2024-q1.csv', 
          'department,revenue,expenses,profit,quarter\n' +
          'finance,1000000,800000,200000,Q1\n' +
          'marketing,500000,450000,50000,Q1\n' +
          'engineering,750000,700000,50000,Q1'
        ),
        s3deploy.Source.data('customer-data/customers.csv',
          'customer_id,name,department,region\n' +
          '1001,Acme Corp,finance,us-east\n' +
          '1002,TechStart Inc,engineering,us-west\n' +
          '1003,Marketing Pro,marketing,eu-west'
        ),
      ],
      destinationBucket: this.dataLakeBucket,
    });

    // Create IAM role for AWS Glue service
    const glueServiceRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `${resourcePrefix}-glue-service-role`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        DataLakeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:ListBucketVersions',
              ],
              resources: [
                this.dataLakeBucket.bucketArn,
                `${this.dataLakeBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Configure Lake Formation data lake settings
    new lakeformation.CfnDataLakeSettings(this, 'DataLakeSettings', {
      dataLakeAdministrators: [
        {
          dataLakePrincipalIdentifier: `arn:aws:iam::${this.account}:root`,
        },
      ],
      createDatabaseDefaultPermissions: [],
      createTableDefaultPermissions: [],
    });

    // Register S3 location with Lake Formation
    new lakeformation.CfnResource(this, 'LakeFormationResource', {
      resourceArn: this.dataLakeBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    // Create LF-Tags for tag-based access control
    const departmentTag = new lakeformation.CfnTag(this, 'DepartmentTag', {
      tagKey: 'department',
      tagValues: ['finance', 'marketing', 'engineering', 'hr'],
    });

    const classificationTag = new lakeformation.CfnTag(this, 'ClassificationTag', {
      tagKey: 'classification',
      tagValues: ['public', 'internal', 'confidential', 'restricted'],
    });

    const dataCategoryTag = new lakeformation.CfnTag(this, 'DataCategoryTag', {
      tagKey: 'data-category',
      tagValues: ['financial', 'customer', 'operational', 'analytics'],
    });

    // Create Glue databases
    this.financialDatabase = new glue.CfnDatabase(this, 'FinancialDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'financial_db',
        description: 'Financial reporting database managed by Lake Formation',
      },
    });

    this.customerDatabase = new glue.CfnDatabase(this, 'CustomerDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'customer_db',
        description: 'Customer information database managed by Lake Formation',
      },
    });

    // Create Glue crawler for financial data
    const financialCrawler = new glue.CfnCrawler(this, 'FinancialCrawler', {
      name: `${resourcePrefix}-financial-crawler`,
      role: glueServiceRole.roleArn,
      databaseName: this.financialDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataLakeBucket.bucketName}/financial-reports/`,
          },
        ],
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // Create Glue crawler for customer data
    const customerCrawler = new glue.CfnCrawler(this, 'CustomerCrawler', {
      name: `${resourcePrefix}-customer-crawler`,
      role: glueServiceRole.roleArn,
      databaseName: this.customerDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataLakeBucket.bucketName}/customer-data/`,
          },
        ],
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
    });

    // Assign LF-Tags to databases
    new lakeformation.CfnTagAssociation(this, 'FinancialDatabaseTags', {
      resource: {
        database: {
          name: this.financialDatabase.ref,
        },
      },
      lfTags: [
        {
          tagKey: departmentTag.tagKey,
          tagValues: ['finance'],
        },
        {
          tagKey: classificationTag.tagKey,
          tagValues: ['confidential'],
        },
        {
          tagKey: dataCategoryTag.tagKey,
          tagValues: ['financial'],
        },
      ],
    });

    new lakeformation.CfnTagAssociation(this, 'CustomerDatabaseTags', {
      resource: {
        database: {
          name: this.customerDatabase.ref,
        },
      },
      lfTags: [
        {
          tagKey: departmentTag.tagKey,
          tagValues: ['marketing'],
        },
        {
          tagKey: classificationTag.tagKey,
          tagValues: ['internal'],
        },
        {
          tagKey: dataCategoryTag.tagKey,
          tagValues: ['customer'],
        },
      ],
    });

    // Create RAM resource share for cross-account sharing
    const resourceShare = new ram.CfnResourceShare(this, 'LakeFormationResourceShare', {
      name: `${resourcePrefix}-lake-formation-share`,
      resourceArns: [
        `arn:aws:glue:${this.region}:${this.account}:database/${this.financialDatabase.ref}`,
      ],
      principals: [props.consumerAccountId],
      allowExternalPrincipals: true,
    });

    this.resourceShareArn = resourceShare.attrArn;

    // Grant Lake Formation permissions to consumer account for specific LF-Tags
    new lakeformation.CfnPermissions(this, 'ConsumerAccountPermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: props.consumerAccountId,
      },
      resource: {
        lfTag: {
          tagKey: departmentTag.tagKey,
          tagValues: ['finance'],
        },
      },
      permissions: ['ASSOCIATE', 'DESCRIBE'],
      permissionsWithGrantOption: ['ASSOCIATE'],
    });

    // Outputs for reference in consumer account
    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: this.dataLakeBucket.bucketName,
      description: 'Name of the S3 bucket containing data lake data',
    });

    new cdk.CfnOutput(this, 'FinancialDatabaseName', {
      value: this.financialDatabase.ref,
      description: 'Name of the financial database in Glue Data Catalog',
    });

    new cdk.CfnOutput(this, 'ResourceShareArn', {
      value: this.resourceShareArn,
      description: 'ARN of the RAM resource share for cross-account access',
    });

    new cdk.CfnOutput(this, 'ProducerAccountId', {
      value: this.account,
      description: 'Account ID of the data producer',
    });
  }
}

/**
 * Consumer Stack - Accepts shared resources and creates access patterns
 * This stack should be deployed in the account that consumes the data
 */
class LakeFormationConsumerStack extends cdk.Stack {
  public readonly dataAnalystRole: iam.Role;
  public readonly sharedDatabase: glue.CfnDatabase;

  constructor(scope: Construct, id: string, props: LakeFormationConsumerStackProps) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'lf-consumer';

    // Configure Lake Formation data lake settings for consumer account
    new lakeformation.CfnDataLakeSettings(this, 'ConsumerDataLakeSettings', {
      dataLakeAdministrators: [
        {
          dataLakePrincipalIdentifier: `arn:aws:iam::${this.account}:root`,
        },
      ],
    });

    // Create resource link to shared database
    this.sharedDatabase = new glue.CfnDatabase(this, 'SharedFinancialDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'shared_financial_db',
        description: 'Resource link to shared financial database from producer account',
        targetDatabase: {
          catalogId: props.producerAccountId,
          databaseName: props.sharedDatabaseName,
        },
      },
    });

    // Create IAM role for data analysts with Lake Formation permissions
    this.dataAnalystRole = new iam.Role(this, 'DataAnalystRole', {
      roleName: `${resourcePrefix}-data-analyst-role`,
      assumedBy: new iam.CompositePrincipal(
        new iam.AccountRootPrincipal(), // Allow account root to assume
        new iam.ServicePrincipal('athena.amazonaws.com') // Allow Athena service
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonAthenaFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSGlueConsoleFullAccess'),
      ],
      inlinePolicies: {
        LakeFormationDataAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lakeformation:GetDataAccess',
                'lakeformation:GetResourceLFTags',
                'lakeformation:ListLFTags',
                'lakeformation:GetLFTag',
                'lakeformation:SearchTablesByLFTags',
                'lakeformation:SearchDatabasesByLFTags',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:GetDatabase',
                'glue:GetDatabases',
                'glue:GetTable',
                'glue:GetTables',
                'glue:GetPartitions',
              ],
              resources: [
                `arn:aws:glue:${this.region}:${this.account}:catalog`,
                `arn:aws:glue:${this.region}:${this.account}:database/*`,
                `arn:aws:glue:${this.region}:${this.account}:table/*/*`,
                `arn:aws:glue:${this.region}:${props.producerAccountId}:catalog`,
                `arn:aws:glue:${this.region}:${props.producerAccountId}:database/*`,
                `arn:aws:glue:${this.region}:${props.producerAccountId}:table/*/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Grant Lake Formation permissions to analyst role for finance data
    new lakeformation.CfnPermissions(this, 'AnalystFinanceDataPermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: this.dataAnalystRole.roleArn,
      },
      resource: {
        lfTag: {
          tagKey: 'department',
          tagValues: ['finance'],
        },
      },
      permissions: ['SELECT', 'DESCRIBE'],
    });

    // Grant permissions on the resource link database
    new lakeformation.CfnPermissions(this, 'AnalystDatabasePermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: this.dataAnalystRole.roleArn,
      },
      resource: {
        database: {
          name: this.sharedDatabase.ref,
        },
      },
      permissions: ['DESCRIBE'],
    });

    // Create S3 bucket for Athena query results
    const athenaResultsBucket = new s3.Bucket(this, 'AthenaResultsBucket', {
      bucketName: `${resourcePrefix}-athena-results-${this.account}-${Date.now()}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldQueryResults',
          enabled: true,
          expiration: cdk.Duration.days(30),
        },
      ],
    });

    // Grant Athena access to results bucket for the analyst role
    athenaResultsBucket.grantReadWrite(this.dataAnalystRole);

    // Outputs for verification and testing
    new cdk.CfnOutput(this, 'DataAnalystRoleArn', {
      value: this.dataAnalystRole.roleArn,
      description: 'ARN of the data analyst role for cross-account data access',
    });

    new cdk.CfnOutput(this, 'SharedDatabaseName', {
      value: this.sharedDatabase.ref,
      description: 'Name of the shared database resource link',
    });

    new cdk.CfnOutput(this, 'AthenaResultsBucketName', {
      value: athenaResultsBucket.bucketName,
      description: 'S3 bucket for storing Athena query results',
    });

    new cdk.CfnOutput(this, 'ConsumerAccountId', {
      value: this.account,
      description: 'Account ID of the data consumer',
    });
  }
}

/**
 * Main CDK Application
 */
class LakeFormationCrossAccountApp extends cdk.App {
  constructor() {
    super();

    // Get context values for account configuration
    const producerAccountId = this.node.tryGetContext('producerAccountId') || process.env.CDK_PRODUCER_ACCOUNT_ID;
    const consumerAccountId = this.node.tryGetContext('consumerAccountId') || process.env.CDK_CONSUMER_ACCOUNT_ID;
    const deploymentMode = this.node.tryGetContext('deploymentMode') || process.env.CDK_DEPLOYMENT_MODE || 'producer';

    if (!producerAccountId || !consumerAccountId) {
      throw new Error(
        'Producer and consumer account IDs must be provided via context or environment variables. ' +
        'Use: cdk deploy -c producerAccountId=123456789012 -c consumerAccountId=098765432109'
      );
    }

    // Environment configuration
    const env = {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
    };

    if (deploymentMode === 'producer' || deploymentMode === 'both') {
      // Deploy producer stack (data owner account)
      new LakeFormationProducerStack(this, 'LakeFormationProducerStack', {
        env: { ...env, account: producerAccountId },
        consumerAccountId: consumerAccountId,
        resourcePrefix: 'lf-cross-account',
        description: 'Lake Formation Producer Stack - Creates and shares data lake resources',
        tags: {
          Project: 'LakeFormationCrossAccount',
          Environment: 'Demo',
          Component: 'Producer',
        },
      });
    }

    if (deploymentMode === 'consumer' || deploymentMode === 'both') {
      // Deploy consumer stack (data consumer account)
      new LakeFormationConsumerStack(this, 'LakeFormationConsumerStack', {
        env: { ...env, account: consumerAccountId },
        producerAccountId: producerAccountId,
        sharedDatabaseName: 'financial_db',
        resourcePrefix: 'lf-cross-account',
        description: 'Lake Formation Consumer Stack - Consumes shared data lake resources',
        tags: {
          Project: 'LakeFormationCrossAccount',
          Environment: 'Demo',
          Component: 'Consumer',
        },
      });
    }
  }
}

// Instantiate and run the CDK application
new LakeFormationCrossAccountApp();