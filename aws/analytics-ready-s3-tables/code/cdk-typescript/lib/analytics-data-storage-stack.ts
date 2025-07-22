import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as s3tables from 'aws-cdk-lib/aws-s3tables';
import { Construct } from 'constructs';

export interface AnalyticsDataStorageStackProps extends cdk.StackProps {
  /**
   * Name for the S3 Table Bucket. If not provided, a unique name will be generated.
   */
  tableBucketName?: string;
  
  /**
   * Name for the namespace within the table bucket.
   * @default 'analytics_data'
   */
  namespaceName?: string;
  
  /**
   * Name for the sample table to create.
   * @default 'customer_events'
   */
  sampleTableName?: string;
  
  /**
   * Whether to enable sample data creation and configuration.
   * @default true
   */
  enableSampleData?: boolean;
}

export class AnalyticsDataStorageStack extends cdk.Stack {
  public readonly tableBucket: s3tables.CfnTableBucket;
  public readonly namespace: s3tables.CfnNamespace;
  public readonly sampleTable: s3tables.CfnTable;
  public readonly athenaResultsBucket: s3.Bucket;
  public readonly athenaWorkgroup: athena.CfnWorkGroup;
  public readonly glueDatabase: glue.CfnDatabase;

  constructor(scope: Construct, id: string, props: AnalyticsDataStorageStackProps = {}) {
    super(scope, id, props);

    const {
      tableBucketName,
      namespaceName = 'analytics_data',
      sampleTableName = 'customer_events',
      enableSampleData = true,
    } = props;

    // Generate unique suffix for resource names if not provided
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();
    const finalTableBucketName = tableBucketName || `analytics-data-${uniqueSuffix}`;

    // Create S3 bucket for Athena query results
    this.athenaResultsBucket = new s3.Bucket(this, 'AthenaResultsBucket', {
      bucketName: `athena-results-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteOldQueryResults',
          enabled: true,
          expiration: cdk.Duration.days(30),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 Table Bucket for analytics storage
    this.tableBucket = new s3tables.CfnTableBucket(this, 'AnalyticsTableBucket', {
      tableBucketName: finalTableBucketName,
    });

    // Create namespace for logical data organization
    this.namespace = new s3tables.CfnNamespace(this, 'AnalyticsNamespace', {
      tableBucketArn: this.tableBucket.attrArn,
      namespace: namespaceName,
    });

    // Create AWS Glue Database for catalog integration
    this.glueDatabase = new glue.CfnDatabase(this, 'AnalyticsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: namespaceName.replace(/_/g, '-'),
        description: 'Database for S3 Tables analytics data',
      },
    });

    // Create IAM role for S3 Tables integration with AWS analytics services
    const s3TablesIntegrationRole = new iam.Role(this, 'S3TablesIntegrationRole', {
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'Role for S3 Tables integration with AWS analytics services',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonGlueServiceRole'),
      ],
      inlinePolicies: {
        S3TablesAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3tables:GetTable',
                's3tables:GetTableMetadata',
                's3tables:ListTables',
                's3tables:ListNamespaces',
              ],
              resources: [
                this.tableBucket.attrArn,
                `${this.tableBucket.attrArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Add table bucket policy for AWS analytics services integration
    const tableBucketPolicy = new s3tables.CfnTableBucketPolicy(this, 'TableBucketPolicy', {
      tableBucketArn: this.tableBucket.attrArn,
      resourcePolicy: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'glue.amazonaws.com',
            },
            Action: [
              's3tables:GetTable',
              's3tables:GetTableMetadata',
              's3tables:ListTables',
              's3tables:ListNamespaces',
            ],
            Resource: '*',
          },
          {
            Effect: 'Allow',
            Principal: {
              Service: 'athena.amazonaws.com',
            },
            Action: [
              's3tables:GetTable',
              's3tables:GetTableMetadata',
              's3tables:ReadTable',
            ],
            Resource: '*',
          },
        ],
      },
    });

    // Create Athena workgroup for S3 Tables queries
    this.athenaWorkgroup = new athena.CfnWorkGroup(this, 'S3TablesWorkgroup', {
      name: `s3-tables-workgroup-${uniqueSuffix}`,
      description: 'Workgroup for querying S3 Tables with optimized performance',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${this.athenaResultsBucket.bucketName}/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
        bytesScannedCutoffPerQuery: 1073741824, // 1 GB limit
        requesterPaysEnabled: false,
        engineVersion: {
          selectedEngineVersion: 'Athena engine version 3',
        },
      },
    });

    if (enableSampleData) {
      // Create sample Apache Iceberg table for customer events
      this.sampleTable = new s3tables.CfnTable(this, 'CustomerEventsTable', {
        tableBucketArn: this.tableBucket.attrArn,
        namespace: this.namespace.namespace,
        name: sampleTableName,
        format: 'ICEBERG',
      });

      // Add dependencies to ensure proper creation order
      this.sampleTable.addDependency(this.namespace);
      tableBucketPolicy.addDependency(this.tableBucket);
    }

    // Add outputs for verification and integration
    new cdk.CfnOutput(this, 'TableBucketArn', {
      value: this.tableBucket.attrArn,
      description: 'ARN of the S3 Table Bucket for analytics storage',
      exportName: `${this.stackName}-TableBucketArn`,
    });

    new cdk.CfnOutput(this, 'TableBucketName', {
      value: finalTableBucketName,
      description: 'Name of the S3 Table Bucket',
      exportName: `${this.stackName}-TableBucketName`,
    });

    new cdk.CfnOutput(this, 'NamespaceName', {
      value: namespaceName,
      description: 'Name of the namespace for logical data organization',
      exportName: `${this.stackName}-NamespaceName`,
    });

    new cdk.CfnOutput(this, 'AthenaResultsBucketName', {
      value: this.athenaResultsBucket.bucketName,
      description: 'S3 bucket for storing Athena query results',
      exportName: `${this.stackName}-AthenaResultsBucketName`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkgroupName', {
      value: this.athenaWorkgroup.name!,
      description: 'Athena workgroup for S3 Tables queries',
      exportName: `${this.stackName}-AthenaWorkgroupName`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'AWS Glue database for catalog integration',
      exportName: `${this.stackName}-GlueDatabaseName`,
    });

    if (enableSampleData && this.sampleTable) {
      new cdk.CfnOutput(this, 'SampleTableName', {
        value: sampleTableName,
        description: 'Name of the sample customer events table',
        exportName: `${this.stackName}-SampleTableName`,
      });

      new cdk.CfnOutput(this, 'SampleDDLCommand', {
        value: this.generateSampleDDL(namespaceName, sampleTableName),
        description: 'Athena DDL command to create the sample table schema',
      });

      new cdk.CfnOutput(this, 'SampleInsertCommand', {
        value: this.generateSampleInsert(namespaceName, sampleTableName),
        description: 'Athena INSERT command with sample data',
      });
    }

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: 'After deployment, use Athena to create table schemas and insert data. See outputs for sample commands.',
      description: 'Next steps for using the deployed infrastructure',
    });
  }

  /**
   * Generate sample DDL command for creating the customer events table schema
   */
  private generateSampleDDL(namespaceName: string, tableName: string): string {
    return `CREATE TABLE IF NOT EXISTS s3tablescatalog.${namespaceName}.${tableName} (
  event_id STRING,
  customer_id STRING,
  event_type STRING,
  event_timestamp TIMESTAMP,
  product_category STRING,
  amount DECIMAL(10,2),
  session_id STRING,
  user_agent STRING,
  event_date DATE
)
USING ICEBERG
PARTITIONED BY (event_date)
TBLPROPERTIES (
  'table_type'='ICEBERG',
  'format'='PARQUET',
  'write_compression'='SNAPPY'
);`;
  }

  /**
   * Generate sample INSERT command with demo data
   */
  private generateSampleInsert(namespaceName: string, tableName: string): string {
    return `INSERT INTO s3tablescatalog.${namespaceName}.${tableName} VALUES
('evt_001', 'cust_12345', 'page_view', TIMESTAMP '2025-01-15 10:30:00', 'electronics', 0.00, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
('evt_002', 'cust_12345', 'add_to_cart', TIMESTAMP '2025-01-15 10:35:00', 'electronics', 299.99, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
('evt_003', 'cust_67890', 'purchase', TIMESTAMP '2025-01-15 11:00:00', 'clothing', 89.99, 'sess_def456', 'Chrome/100.0', DATE '2025-01-15'),
('evt_004', 'cust_54321', 'page_view', TIMESTAMP '2025-01-15 11:15:00', 'books', 0.00, 'sess_ghi789', 'Safari/14.0', DATE '2025-01-15'),
('evt_005', 'cust_54321', 'purchase', TIMESTAMP '2025-01-15 11:30:00', 'books', 24.99, 'sess_ghi789', 'Safari/14.0', DATE '2025-01-15');`;
  }
}