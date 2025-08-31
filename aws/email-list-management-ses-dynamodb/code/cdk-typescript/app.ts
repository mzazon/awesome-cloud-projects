#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ses from 'aws-cdk-lib/aws-ses';
import { Construct } from 'constructs';
import { LambdaDynamoDBConstruct } from '@aws-solutions-constructs/aws-lambda-dynamodb';
import * as nag from 'cdk-nag';

/**
 * Props for the EmailListManagementStack
 */
interface EmailListManagementStackProps extends cdk.StackProps {
  /**
   * The verified SES email address for sending emails
   * @default 'your-email@example.com'
   */
  readonly senderEmail?: string;
  
  /**
   * The prefix for all resource names
   * @default 'EmailList'
   */
  readonly resourcePrefix?: string;
}

/**
 * Stack for email list management system using SES, DynamoDB, and Lambda
 */
export class EmailListManagementStack extends cdk.Stack {
  
  public readonly subscribersTable: dynamodb.Table;
  public readonly subscribeLambda: lambda.Function;
  public readonly newsletterLambda: lambda.Function;
  public readonly listSubscribersLambda: lambda.Function;

  constructor(scope: Construct, id: string, props: EmailListManagementStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'EmailList';
    const senderEmail = props.senderEmail || 'your-email@example.com';

    // Create DynamoDB table for subscribers using AWS Solutions Construct
    // This provides best practices for Lambda-DynamoDB integration
    const subscribeLambdaDynamoConstruct = new LambdaDynamoDBConstruct(this, 'SubscribeLambdaDynamoDB', {
      lambdaFunctionProps: {
        runtime: lambda.Runtime.PYTHON_3_12,
        handler: 'index.lambda_handler',
        code: lambda.Code.fromInline(`
import json
import boto3
import datetime
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE_NAME'])

def lambda_handler(event, context):
    """
    Subscribe Lambda function to handle new subscriber registrations
    """
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        email = body.get('email', '').lower().strip()
        name = body.get('name', 'Subscriber')
        
        # Validate email
        if not email or '@' not in email:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Valid email required'})
            }
        
        # Add subscriber to DynamoDB with conditional check for duplicates
        response = table.put_item(
            Item={
                'email': email,
                'name': name,
                'subscribed_date': datetime.datetime.now().isoformat(),
                'status': 'active'
            },
            ConditionExpression='attribute_not_exists(email)'
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': f'Successfully subscribed {email}',
                'email': email
            })
        }
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return {
                'statusCode': 409,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Email already subscribed'})
            }
        else:
            print(f"DynamoDB Error: {str(e)}")
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Database error occurred'})
            }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
        `),
        functionName: `${resourcePrefix}-Subscribe`,
        timeout: cdk.Duration.seconds(30),
        memorySize: 256,
        description: 'Lambda function to handle email subscription requests',
        architecture: lambda.Architecture.ARM_64,
        // Enable insights for better monitoring
        insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0
      },
      dynamoTableProps: {
        tableName: `${resourcePrefix}-Subscribers`,
        partitionKey: { name: 'email', type: dynamodb.AttributeType.STRING },
        billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
        pointInTimeRecovery: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY, // For development - change to RETAIN for production
        encryption: dynamodb.TableEncryption.AWS_MANAGED
      }
    });

    // Get references to the created resources
    this.subscribeLambda = subscribeLambdaDynamoConstruct.lambdaFunction;
    this.subscribersTable = subscribeLambdaDynamoConstruct.dynamoTable;

    // Create IAM role for other Lambda functions with SES and DynamoDB permissions
    const lambdaRole = new iam.Role(this, 'EmailLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        SESAndDynamoDBPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ses:SendEmail',
                'ses:SendRawEmail'
              ],
              resources: ['*'], // SES resources are account-level
              conditions: {
                StringEquals: {
                  'ses:FromAddress': senderEmail
                }
              }
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:Scan',
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem'
              ],
              resources: [this.subscribersTable.tableArn]
            })
          ]
        })
      }
    });

    // Create newsletter sending Lambda function
    this.newsletterLambda = new lambda.Function(this, 'NewsletterFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      functionName: `${resourcePrefix}-Newsletter`,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'Lambda function to send newsletters to all active subscribers',
      architecture: lambda.Architecture.ARM_64,
      insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0,
      environment: {
        TABLE_NAME: this.subscribersTable.tableName,
        SENDER_EMAIL: senderEmail
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from botocore.exceptions import ClientError
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    """
    Newsletter Lambda function to send emails to all active subscribers
    """
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        subject = body.get('subject', 'Newsletter Update')
        message = body.get('message', 'Thank you for subscribing!')
        sender_email = os.environ['SENDER_EMAIL']
        
        # Get all active subscribers with pagination support
        subscribers = []
        response = table.scan(
            FilterExpression='#status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'active'}
        )
        subscribers.extend(response['Items'])
        
        # Handle pagination for large subscriber lists
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': 'active'},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response['Items'])
        
        sent_count = 0
        failed_count = 0
        failed_emails = []
        
        # Send personalized emails to each subscriber
        for subscriber in subscribers:
            try:
                ses.send_email(
                    Source=sender_email,
                    Destination={'ToAddresses': [subscriber['email']]},
                    Message={
                        'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                        'Body': {
                            'Text': {
                                'Data': f"Hello {subscriber['name']},\\n\\n{message}\\n\\nBest regards,\\nYour Newsletter Team",
                                'Charset': 'UTF-8'
                            },
                            'Html': {
                                'Data': f"""
                                <html>
                                <head><title>{subject}</title></head>
                                <body>
                                <h2>Hello {subscriber['name']},</h2>
                                <p>{message}</p>
                                <p>Best regards,<br>Your Newsletter Team</p>
                                <hr>
                                <small>You received this email because you subscribed to our newsletter.</small>
                                </body>
                                </html>
                                """,
                                'Charset': 'UTF-8'
                            }
                        }
                    }
                )
                sent_count += 1
            except ClientError as e:
                print(f"Failed to send to {subscriber['email']}: {e}")
                failed_count += 1
                failed_emails.append(subscriber['email'])
            except Exception as e:
                print(f"Unexpected error sending to {subscriber['email']}: {e}")
                failed_count += 1
                failed_emails.append(subscriber['email'])
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': f'Newsletter sent to {sent_count} subscribers',
                'sent_count': sent_count,
                'failed_count': failed_count,
                'total_subscribers': len(subscribers),
                'failed_emails': failed_emails if failed_emails else None
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Failed to send newsletter'})
        }
      `)
    });

    // Create list subscribers Lambda function
    this.listSubscribersLambda = new lambda.Function(this, 'ListSubscribersFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      functionName: `${resourcePrefix}-ListSubscribers`,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Lambda function to list all subscribers',
      architecture: lambda.Architecture.ARM_64,
      insightsVersion: lambda.LambdaInsightsVersion.VERSION_1_0_229_0,
      environment: {
        TABLE_NAME: this.subscribersTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    """
    List subscribers Lambda function to retrieve all subscribers
    """
    try:
        # Parse query parameters for filtering (optional)
        query_params = event.get('queryStringParameters') or {}
        status_filter = query_params.get('status', None)
        
        # Scan table for all subscribers with pagination support
        subscribers = []
        scan_kwargs = {}
        
        if status_filter:
            scan_kwargs['FilterExpression'] = '#status = :status'
            scan_kwargs['ExpressionAttributeNames'] = {'#status': 'status'}
            scan_kwargs['ExpressionAttributeValues'] = {':status': status_filter}
        
        response = table.scan(**scan_kwargs)
        subscribers.extend(response['Items'])
        
        # Handle pagination for large subscriber lists
        while 'LastEvaluatedKey' in response:
            scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
            response = table.scan(**scan_kwargs)
            subscribers.extend(response['Items'])
        
        # Convert Decimal types for JSON serialization
        for subscriber in subscribers:
            for key, value in subscriber.items():
                if isinstance(value, Decimal):
                    subscriber[key] = float(value)
        
        # Calculate statistics
        total_count = len(subscribers)
        active_count = len([s for s in subscribers if s.get('status') == 'active'])
        inactive_count = total_count - active_count
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'subscribers': subscribers,
                'statistics': {
                    'total_count': total_count,
                    'active_count': active_count,
                    'inactive_count': inactive_count
                }
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Failed to retrieve subscribers'})
        }
      `)
    });

    // Create SES configuration set for better deliverability tracking (optional)
    const configSet = new ses.CfnConfigurationSet(this, 'EmailConfigSet', {
      name: `${resourcePrefix}-ConfigSet`,
      reputationTrackingEnabled: true,
      sendingEnabled: true
    });

    // Add tags to all resources for better organization
    const tags = {
      'Project': 'EmailListManagement',
      'Environment': 'Development',
      'ManagedBy': 'CDK'
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Outputs for easy reference
    new cdk.CfnOutput(this, 'SubscribersTableName', {
      value: this.subscribersTable.tableName,
      description: 'Name of the DynamoDB table storing subscribers',
      exportName: `${this.stackName}-SubscribersTableName`
    });

    new cdk.CfnOutput(this, 'SubscribeLambdaArn', {
      value: this.subscribeLambda.functionArn,
      description: 'ARN of the subscribe Lambda function',
      exportName: `${this.stackName}-SubscribeLambdaArn`
    });

    new cdk.CfnOutput(this, 'NewsletterLambdaArn', {
      value: this.newsletterLambda.functionArn,
      description: 'ARN of the newsletter Lambda function',
      exportName: `${this.stackName}-NewsletterLambdaArn`
    });

    new cdk.CfnOutput(this, 'ListSubscribersLambdaArn', {
      value: this.listSubscribersLambda.functionArn,
      description: 'ARN of the list subscribers Lambda function',
      exportName: `${this.stackName}-ListSubscribersLambdaArn`
    });

    new cdk.CfnOutput(this, 'SenderEmailInfo', {
      value: senderEmail,
      description: 'Configured sender email address - ensure this is verified in SES',
      exportName: `${this.stackName}-SenderEmail`
    });

    // Add CDK Nag suppressions where necessary
    nag.NagSuppressions.addResourceSuppressions(lambdaRole, [
      {
        id: 'AwsSolutions-IAM5',
        reason: 'SES requires wildcard permissions for sending emails from verified addresses'
      }
    ]);

    nag.NagSuppressions.addResourceSuppressions(this.subscribersTable, [
      {
        id: 'AwsSolutions-DDB3',
        reason: 'Point-in-time recovery is enabled for data protection'
      }
    ]);
  }
}

// CDK Application
const app = new cdk.App();

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new nag.AwsSolutionsChecks({ verbose: true }));

// Create the main stack
new EmailListManagementStack(app, 'EmailListManagementStack', {
  description: 'Email list management system with SES, DynamoDB, and Lambda',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Customize these properties as needed
  senderEmail: process.env.SENDER_EMAIL || 'your-email@example.com',
  resourcePrefix: process.env.RESOURCE_PREFIX || 'EmailList'
});

app.synth();