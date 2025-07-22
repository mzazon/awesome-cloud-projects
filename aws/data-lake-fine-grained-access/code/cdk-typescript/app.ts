#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lakeformation from 'aws-cdk-lib/aws-lakeformation';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * CDK Stack for implementing AWS Lake Formation fine-grained access control
 * This stack creates a complete data lake setup with column-level and row-level security
 */
export class DataLakeFormationFineGrainedAccessControlStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    
    // Create S3 bucket for data lake storage
    const dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `data-lake-fgac-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });

    // Create sample CSV data for the demo
    const sampleData = `customer_id,name,email,department,salary,ssn
1,John Doe,john@example.com,Engineering,75000,123-45-6789
2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098`;

    // Deploy sample data to S3
    new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [s3deploy.Source.data('customer_data/sample_data.csv', sampleData)],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'customer_data/',
    });

    // Create Glue database for the data catalog
    const glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'sample_database',
        description: 'Sample database for fine-grained access control demonstration',
      },
    });

    // Create Glue table for customer data
    const glueTable = new glue.CfnTable(this, 'GlueTable', {
      catalogId: this.account,
      databaseName: glueDatabase.ref,
      tableInput: {
        name: 'customer_data',
        description: 'Customer data table with sensitive information',
        storageDescriptor: {
          columns: [
            { name: 'customer_id', type: 'bigint' },
            { name: 'name', type: 'string' },
            { name: 'email', type: 'string' },
            { name: 'department', type: 'string' },
            { name: 'salary', type: 'bigint' },
            { name: 'ssn', type: 'string' },
          ],
          location: `s3://${dataLakeBucket.bucketName}/customer_data/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
            parameters: {
              'field.delim': ',',
              'skip.header.line.count': '1',
            },
          },
        },
        tableType: 'EXTERNAL_TABLE',
      },
    });

    // Create IAM roles for different user types with Lake Formation trust relationships
    const createRoleWithLakeFormationTrust = (roleName: string, description: string): iam.Role => {
      return new iam.Role(this, roleName, {
        roleName: roleName,
        description: description,
        assumedBy: new iam.CompositePrincipal(
          new iam.ServicePrincipal('glue.amazonaws.com'),
          new iam.AccountRootPrincipal() // Allow cross-account assume role for testing
        ),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonAthenaFullAccess'),
          iam.ManagedPolicy.fromAwsManagedPolicyName('AWSGlueConsoleFullAccess'),
        ],
        inlinePolicies: {
          LakeFormationPermissions: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'lakeformation:GetDataAccess',
                  'lakeformation:GrantPermissions',
                  'lakeformation:RevokePermissions',
                  'lakeformation:BatchGrantPermissions',
                  'lakeformation:BatchRevokePermissions',
                  'lakeformation:ListPermissions',
                  'glue:GetTable',
                  'glue:GetTables',
                  'glue:GetDatabase',
                  'glue:GetDatabases',
                  'glue:GetPartitions',
                  's3:GetObject',
                  's3:ListBucket',
                ],
                resources: ['*'],
              }),
            ],
          }),
        },
      });
    };

    // Create roles for different user personas
    const dataAnalystRole = createRoleWithLakeFormationTrust(
      'DataAnalystRole',
      'Role for data analysts with full table access'
    );

    const financeTeamRole = createRoleWithLakeFormationTrust(
      'FinanceTeamRole',
      'Role for finance team with limited column access (no SSN)'
    );

    const hrRole = createRoleWithLakeFormationTrust(
      'HRRole',
      'Role for HR with very limited access (name and department only)'
    );

    // Register S3 location with Lake Formation
    const lakeFormationResource = new lakeformation.CfnResource(this, 'LakeFormationResource', {
      resourceArn: dataLakeBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    // Configure Lake Formation data lake settings
    const dataLakeSettings = new lakeformation.CfnDataLakeSettings(this, 'DataLakeSettings', {
      admins: [
        {
          dataLakePrincipalIdentifier: this.formatArn({
            service: 'iam',
            resource: 'root',
            region: '',
          }),
        },
      ],
      createDatabaseDefaultPermissions: [],
      createTableDefaultPermissions: [],
      trustedResourceOwners: [this.account],
    });

    // Grant full table access to data analyst role
    const dataAnalystPermissions = new lakeformation.CfnPermissions(this, 'DataAnalystPermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: dataAnalystRole.roleArn,
      },
      resource: {
        tableResource: {
          catalogId: this.account,
          databaseName: glueDatabase.ref,
          name: glueTable.ref,
        },
      },
      permissions: ['SELECT'],
      permissionsWithGrantOption: [],
    });

    // Grant limited column access to finance team (no SSN column)
    const financeTeamPermissions = new lakeformation.CfnPermissions(this, 'FinanceTeamPermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: financeTeamRole.roleArn,
      },
      resource: {
        tableWithColumnsResource: {
          catalogId: this.account,
          databaseName: glueDatabase.ref,
          name: glueTable.ref,
          columnNames: ['customer_id', 'name', 'department', 'salary'],
        },
      },
      permissions: ['SELECT'],
      permissionsWithGrantOption: [],
    });

    // Grant very limited access to HR (only name and department)
    const hrPermissions = new lakeformation.CfnPermissions(this, 'HRPermissions', {
      dataLakePrincipal: {
        dataLakePrincipalIdentifier: hrRole.roleArn,
      },
      resource: {
        tableWithColumnsResource: {
          catalogId: this.account,
          databaseName: glueDatabase.ref,
          name: glueTable.ref,
          columnNames: ['customer_id', 'name', 'department'],
        },
      },
      permissions: ['SELECT'],
      permissionsWithGrantOption: [],
    });

    // Create data filter for row-level security (Engineering department only for finance team)
    const engineeringOnlyFilter = new lakeformation.CfnDataCellsFilter(this, 'EngineeringOnlyFilter', {
      tableCatalogId: this.account,
      databaseName: glueDatabase.ref,
      tableName: glueTable.ref,
      name: 'engineering-only-filter',
      rowFilter: {
        filterExpression: 'department = "Engineering"',
      },
      columnNames: ['customer_id', 'name', 'department', 'salary'],
    });

    // Create S3 bucket for Athena query results
    const athenaResultsBucket = new s3.Bucket(this, 'AthenaResultsBucket', {
      bucketName: `athena-results-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });

    // Add dependencies to ensure proper creation order
    glueTable.addDependency(glueDatabase);
    lakeFormationResource.addDependency(glueDatabase);
    dataAnalystPermissions.addDependency(lakeFormationResource);
    dataAnalystPermissions.addDependency(glueTable);
    financeTeamPermissions.addDependency(lakeFormationResource);
    financeTeamPermissions.addDependency(glueTable);
    hrPermissions.addDependency(lakeFormationResource);
    hrPermissions.addDependency(glueTable);
    engineeringOnlyFilter.addDependency(glueTable);

    // Stack outputs for reference and testing
    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: dataLakeBucket.bucketName,
      description: 'Name of the S3 bucket used for data lake storage',
      exportName: `${this.stackName}-DataLakeBucketName`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the Glue database',
      exportName: `${this.stackName}-GlueDatabaseName`,
    });

    new cdk.CfnOutput(this, 'GlueTableName', {
      value: glueTable.ref,
      description: 'Name of the Glue table',
      exportName: `${this.stackName}-GlueTableName`,
    });

    new cdk.CfnOutput(this, 'DataAnalystRoleArn', {
      value: dataAnalystRole.roleArn,
      description: 'ARN of the Data Analyst role (full table access)',
      exportName: `${this.stackName}-DataAnalystRoleArn`,
    });

    new cdk.CfnOutput(this, 'FinanceTeamRoleArn', {
      value: financeTeamRole.roleArn,
      description: 'ARN of the Finance Team role (limited column access)',
      exportName: `${this.stackName}-FinanceTeamRoleArn`,
    });

    new cdk.CfnOutput(this, 'HRRoleArn', {
      value: hrRole.roleArn,
      description: 'ARN of the HR role (very limited access)',
      exportName: `${this.stackName}-HRRoleArn`,
    });

    new cdk.CfnOutput(this, 'AthenaResultsBucketName', {
      value: athenaResultsBucket.bucketName,
      description: 'Name of the S3 bucket for Athena query results',
      exportName: `${this.stackName}-AthenaResultsBucketName`,
    });

    new cdk.CfnOutput(this, 'LakeFormationResourceArn', {
      value: lakeFormationResource.resourceArn || dataLakeBucket.bucketArn,
      description: 'ARN of the Lake Formation registered resource',
      exportName: `${this.stackName}-LakeFormationResourceArn`,
    });

    // Output sample Athena queries for testing
    new cdk.CfnOutput(this, 'SampleAthenaQuery', {
      value: `SELECT * FROM "${glueDatabase.ref}"."${glueTable.ref}" LIMIT 10;`,
      description: 'Sample Athena query to test table access',
    });

    new cdk.CfnOutput(this, 'TestingInstructions', {
      value: 'Use AWS STS assume-role with the different role ARNs to test fine-grained access controls',
      description: 'Instructions for testing the access controls',
    });
  }
}

// Create the CDK application
const app = new cdk.App();

// Create the stack with proper naming and tagging
new DataLakeFormationFineGrainedAccessControlStack(app, 'DataLakeFormationFineGrainedAccessControlStack', {
  description: 'AWS Lake Formation fine-grained access control implementation with CDK TypeScript',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataLakeFormationFGAC',
    Environment: 'Demo',
    Purpose: 'Fine-grained access control demonstration',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();