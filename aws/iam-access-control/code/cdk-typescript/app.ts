#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_iam as iam,
  aws_s3 as s3,
  aws_logs as logs,
  CfnOutput,
  RemovalPolicy,
  Stack,
  StackProps,
  App,
  Duration
} from 'aws-cdk-lib';

/**
 * CDK Stack for Fine-Grained Access Control with IAM Policies and Conditions
 * 
 * This stack demonstrates advanced IAM policy patterns including:
 * - Time-based access controls
 * - IP-based restrictions
 * - Tag-based access control (ABAC)
 * - MFA requirements
 * - Session-based controls
 * - Resource-based policies
 */
export class FineGrainedAccessControlStack extends Stack {
  public readonly testBucket: s3.Bucket;
  public readonly logGroup: logs.LogGroup;
  public readonly testUser: iam.User;
  public readonly testRole: iam.Role;

  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 10);
    const projectName = `finegrained-access-${uniqueSuffix}`;

    // Create test S3 bucket for policy testing
    this.testBucket = new s3.Bucket(this, 'TestBucket', {
      bucketName: `${projectName}-test-bucket`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: false,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CloudWatch log group for testing
    this.logGroup = new logs.LogGroup(this, 'TestLogGroup', {
      logGroupName: `/aws/lambda/${projectName}`,
      retention: logs.RetentionDays.ONE_DAY,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // 1. Create Time-Based Access Policy
    const businessHoursPolicy = this.createBusinessHoursPolicy(projectName);

    // 2. Create IP-Based Access Control Policy
    const ipRestrictionPolicy = this.createIpRestrictionPolicy(projectName);

    // 3. Create Tag-Based Access Control Policy (ABAC)
    const tagBasedPolicy = this.createTagBasedPolicy(projectName);

    // 4. Create MFA Required Policy
    const mfaRequiredPolicy = this.createMfaRequiredPolicy(projectName);

    // 5. Create Session-Based Access Control Policy
    const sessionPolicy = this.createSessionPolicy(projectName);

    // 6. Create Test User with tags
    this.testUser = new iam.User(this, 'TestUser', {
      userName: `${projectName}-test-user`,
    });

    // Add tags to test user
    cdk.Tags.of(this.testUser).add('Department', 'Engineering');
    cdk.Tags.of(this.testUser).add('Project', projectName);

    // 7. Create Test Role with conditional trust policy
    this.testRole = new iam.Role(this, 'TestRole', {
      roleName: `${projectName}-test-role`,
      description: 'Test role with conditional access',
      assumedBy: new iam.PrincipalWithConditions(
        new iam.ArnPrincipal(this.testUser.userArn),
        {
          StringEquals: {
            'aws:RequestedRegion': Stack.of(this).region,
          },
          IpAddress: {
            'aws:SourceIp': [
              '203.0.113.0/24',
              '198.51.100.0/24',
            ],
          },
        }
      ),
    });

    // Add tags to test role
    cdk.Tags.of(this.testRole).add('Department', 'Engineering');
    cdk.Tags.of(this.testRole).add('Environment', 'Test');

    // 8. Attach policies to test principals
    this.testUser.attachInlinePolicy(tagBasedPolicy);
    this.testRole.attachInlinePolicy(businessHoursPolicy);

    // 9. Create resource-based policy for S3 bucket
    this.createBucketPolicy(projectName);

    // 10. Create sample S3 objects with tags for testing
    this.createSampleS3Objects(projectName);

    // Stack outputs
    new CfnOutput(this, 'TestBucketName', {
      value: this.testBucket.bucketName,
      description: 'Name of the test S3 bucket',
      exportName: `${projectName}-bucket-name`,
    });

    new CfnOutput(this, 'TestUserArn', {
      value: this.testUser.userArn,
      description: 'ARN of the test IAM user',
      exportName: `${projectName}-user-arn`,
    });

    new CfnOutput(this, 'TestRoleArn', {
      value: this.testRole.roleArn,
      description: 'ARN of the test IAM role',
      exportName: `${projectName}-role-arn`,
    });

    new CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'Name of the CloudWatch log group',
      exportName: `${projectName}-log-group`,
    });

    new CfnOutput(this, 'ProjectName', {
      value: projectName,
      description: 'Project name for resource identification',
      exportName: `${projectName}-project-name`,
    });
  }

  /**
   * Creates a policy that allows S3 access only during business hours (9 AM - 5 PM UTC)
   */
  private createBusinessHoursPolicy(projectName: string): iam.Policy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:ListBucket',
          ],
          resources: [
            this.testBucket.bucketArn,
            `${this.testBucket.bucketArn}/*`,
          ],
          conditions: {
            DateGreaterThan: {
              'aws:CurrentTime': '09:00Z',
            },
            DateLessThan: {
              'aws:CurrentTime': '17:00Z',
            },
          },
        }),
      ],
    });

    return new iam.Policy(this, 'BusinessHoursPolicy', {
      policyName: `${projectName}-business-hours-policy`,
      document: policyDocument,
    });
  }

  /**
   * Creates a policy that restricts CloudWatch Logs access to specific IP ranges
   */
  private createIpRestrictionPolicy(projectName: string): iam.Policy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        // Allow CloudWatch Logs operations from specific IP ranges
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogStream',
            'logs:PutLogEvents',
            'logs:DescribeLogGroups',
            'logs:DescribeLogStreams',
          ],
          resources: [
            `arn:aws:logs:*:${Stack.of(this).account}:log-group:/aws/lambda/${projectName}*`,
          ],
          conditions: {
            IpAddress: {
              'aws:SourceIp': [
                '203.0.113.0/24',
                '198.51.100.0/24',
              ],
            },
          },
        }),
        // Explicit deny for all actions from non-approved IP ranges
        new iam.PolicyStatement({
          effect: iam.Effect.DENY,
          actions: ['*'],
          resources: ['*'],
          conditions: {
            Bool: {
              'aws:ViaAWSService': 'false',
            },
            NotIpAddress: {
              'aws:SourceIp': [
                '203.0.113.0/24',
                '198.51.100.0/24',
              ],
            },
          },
        }),
      ],
    });

    return new iam.Policy(this, 'IpRestrictionPolicy', {
      policyName: `${projectName}-ip-restriction-policy`,
      document: policyDocument,
    });
  }

  /**
   * Creates a policy using tag-based access control (ABAC)
   * Users can only access S3 objects tagged with their department
   */
  private createTagBasedPolicy(projectName: string): iam.Policy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        // Allow access to objects where principal's department tag matches object's department tag
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
          ],
          resources: [`${this.testBucket.bucketArn}/*`],
          conditions: {
            StringEquals: {
              'aws:PrincipalTag/Department': '${s3:ExistingObjectTag/Department}',
            },
          },
        }),
        // Allow access to shared objects for all users
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
          ],
          resources: [`${this.testBucket.bucketArn}/shared/*`],
        }),
        // Allow listing bucket with prefix restrictions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['s3:ListBucket'],
          resources: [this.testBucket.bucketArn],
          conditions: {
            StringLike: {
              's3:prefix': [
                'shared/*',
                '${aws:PrincipalTag/Department}/*',
              ],
            },
          },
        }),
      ],
    });

    return new iam.Policy(this, 'TagBasedPolicy', {
      policyName: `${projectName}-tag-based-policy`,
      document: policyDocument,
    });
  }

  /**
   * Creates a policy that requires MFA for write operations
   */
  private createMfaRequiredPolicy(projectName: string): iam.Policy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        // Allow read operations without MFA
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:ListBucket',
          ],
          resources: [
            this.testBucket.bucketArn,
            `${this.testBucket.bucketArn}/*`,
          ],
        }),
        // Require MFA for write operations
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:PutObject',
            's3:DeleteObject',
            's3:PutObjectAcl',
          ],
          resources: [`${this.testBucket.bucketArn}/*`],
          conditions: {
            Bool: {
              'aws:MultiFactorAuthPresent': 'true',
            },
            NumericLessThan: {
              'aws:MultiFactorAuthAge': '3600', // MFA session must be less than 1 hour old
            },
          },
        }),
      ],
    });

    return new iam.Policy(this, 'MfaRequiredPolicy', {
      policyName: `${projectName}-mfa-required-policy`,
      document: policyDocument,
    });
  }

  /**
   * Creates a policy with session duration and naming constraints
   */
  private createSessionPolicy(projectName: string): iam.Policy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        // Allow CloudWatch Logs operations with session constraints
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogStream',
            'logs:PutLogEvents',
          ],
          resources: [
            `arn:aws:logs:*:${Stack.of(this).account}:log-group:/aws/lambda/${projectName}*`,
          ],
          conditions: {
            StringEquals: {
              'aws:userid': '${aws:userid}',
            },
            StringLike: {
              'aws:rolename': `${projectName}*`,
            },
            NumericLessThan: {
              'aws:TokenIssueTime': '${aws:CurrentTime}',
            },
          },
        }),
        // Allow session token creation with duration limits
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sts:GetSessionToken'],
          resources: ['*'],
          conditions: {
            NumericLessThan: {
              'aws:RequestedDuration': '3600', // Limit session duration to 1 hour
            },
          },
        }),
      ],
    });

    return new iam.Policy(this, 'SessionPolicy', {
      policyName: `${projectName}-session-policy`,
      document: policyDocument,
    });
  }

  /**
   * Creates a resource-based policy for the S3 bucket with encryption and metadata requirements
   */
  private createBucketPolicy(projectName: string): void {
    const bucketPolicyDocument = new iam.PolicyDocument({
      statements: [
        // Allow access from test role with encryption and metadata requirements
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [this.testRole],
          actions: [
            's3:GetObject',
            's3:PutObject',
          ],
          resources: [`${this.testBucket.bucketArn}/*`],
          conditions: {
            StringEquals: {
              's3:x-amz-server-side-encryption': 'AES256',
            },
            StringLike: {
              's3:x-amz-meta-project': `${projectName}*`,
            },
          },
        }),
        // Deny all requests that don't use HTTPS
        new iam.PolicyStatement({
          effect: iam.Effect.DENY,
          principals: [new iam.AnyPrincipal()],
          actions: ['s3:*'],
          resources: [
            this.testBucket.bucketArn,
            `${this.testBucket.bucketArn}/*`,
          ],
          conditions: {
            Bool: {
              'aws:SecureTransport': 'false',
            },
          },
        }),
      ],
    });

    this.testBucket.addToResourcePolicy(bucketPolicyDocument.statements[0]);
    this.testBucket.addToResourcePolicy(bucketPolicyDocument.statements[1]);
  }

  /**
   * Creates sample S3 objects with appropriate tags for testing ABAC policies
   */
  private createSampleS3Objects(projectName: string): void {
    // Create a custom resource to upload test objects with tags
    const customResource = new cdk.CustomResource(this, 'SampleS3Objects', {
      serviceToken: this.createCustomResourceProvider(projectName).serviceToken,
      properties: {
        BucketName: this.testBucket.bucketName,
        ProjectName: projectName,
      },
    });

    customResource.node.addDependency(this.testBucket);
  }

  /**
   * Creates a Lambda function to handle the custom resource for S3 object creation
   */
  private createCustomResourceProvider(projectName: string): cdk.Provider {
    const lambdaFunction = new cdk.aws_lambda.Function(this, 'S3ObjectCreatorFunction', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: Duration.minutes(5),
      code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import urllib3

def handler(event, context):
    s3 = boto3.client('s3')
    
    bucket_name = event['ResourceProperties']['BucketName']
    project_name = event['ResourceProperties']['ProjectName']
    
    if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
        try:
            # Create test object with engineering department tag
            s3.put_object(
                Bucket=bucket_name,
                Key='Engineering/test-file.txt',
                Body=b'Test content for engineering department',
                ServerSideEncryption='AES256',
                Metadata={'project': f'{project_name}-test'},
                Tagging='Department=Engineering&Project=' + project_name
            )
            
            # Create shared object
            s3.put_object(
                Bucket=bucket_name,
                Key='shared/common-file.txt',
                Body=b'Shared content for all departments',
                ServerSideEncryption='AES256',
                Metadata={'project': f'{project_name}-shared'}
            )
            
            send_response(event, context, 'SUCCESS', {'Message': 'Objects created successfully'})
        except Exception as e:
            print(f"Error: {str(e)}")
            send_response(event, context, 'FAILED', {'Message': str(e)})
    
    elif event['RequestType'] == 'Delete':
        try:
            # Objects will be deleted automatically when bucket is deleted
            send_response(event, context, 'SUCCESS', {'Message': 'Objects deleted successfully'})
        except Exception as e:
            print(f"Error during delete: {str(e)}")
            send_response(event, context, 'SUCCESS', {'Message': 'Delete completed with errors'})

def send_response(event, context, response_status, response_data):
    response_body = {
        'Status': response_status,
        'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': response_data
    }
    
    json_response_body = json.dumps(response_body)
    
    headers = {
        'content-type': '',
        'content-length': str(len(json_response_body))
    }
    
    try:
        http = urllib3.PoolManager()
        response = http.request('PUT', event['ResponseURL'], body=json_response_body, headers=headers)
        print(f"Status code: {response.status}")
    except Exception as e:
        print(f"send_response failed: {e}")
`),
    });

    // Grant S3 permissions to the Lambda function
    this.testBucket.grantWrite(lambdaFunction);
    this.testBucket.grantPutAcl(lambdaFunction);

    return new cdk.Provider(this, 'S3ObjectCreatorProvider', {
      onEventHandler: lambdaFunction,
    });
  }
}

// CDK App
const app = new App();

new FineGrainedAccessControlStack(app, 'FineGrainedAccessControlStack', {
  description: 'Fine-Grained Access Control with IAM Policies and Conditions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'FineGrainedAccessControl',
    Environment: 'Demo',
    Purpose: 'Security-Recipe',
  },
});

app.synth();