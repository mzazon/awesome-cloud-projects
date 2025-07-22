#!/usr/bin/env node
import 'source-map-support/register';
import { App, Stack, StackProps, Duration, CfnOutput } from 'aws-cdk-lib';
import { Function, Runtime, Code } from 'aws-cdk-lib/aws-lambda';
import { RestApi, LambdaIntegration, Cors, MethodOptions } from 'aws-cdk-lib/aws-apigateway';
import { PolicyStatement, Effect } from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Props for the ContactFormStack
 */
export interface ContactFormStackProps extends StackProps {
  /**
   * The email address to use as sender and recipient for contact form submissions
   * This email must be verified in SES before deployment
   */
  readonly senderEmail: string;
  
  /**
   * Optional recipient email address (defaults to sender email if not provided)
   */
  readonly recipientEmail?: string;
}

/**
 * AWS CDK Stack for a serverless contact form backend
 * 
 * This stack creates:
 * - Lambda function to process contact form submissions
 * - API Gateway REST API with CORS support
 * - IAM role with minimal permissions for SES email sending
 * 
 * Architecture:
 * Static Website -> API Gateway -> Lambda -> SES -> Email Recipient
 */
export class ContactFormStack extends Stack {
  constructor(scope: Construct, id: string, props: ContactFormStackProps) {
    super(scope, id, props);

    // Validate required props
    if (!props.senderEmail) {
      throw new Error('senderEmail is required and must be verified in SES');
    }

    const recipientEmail = props.recipientEmail || props.senderEmail;

    // Lambda function code for processing contact form submissions
    const lambdaCode = `
const { SES } = require('@aws-sdk/client-ses');

/**
 * Lambda handler for processing contact form submissions
 * @param {Object} event - API Gateway event
 * @param {Object} context - Lambda context
 * @returns {Object} API Gateway response
 */
exports.handler = async (event, context) => {
    // Configure SES client
    const ses = new SES({ region: process.env.AWS_REGION });
    
    // CORS headers for all responses
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token',
        'Content-Type': 'application/json'
    };
    
    try {
        console.log('Processing contact form submission', { 
            requestId: context.awsRequestId,
            httpMethod: event.httpMethod 
        });
        
        // Handle preflight OPTIONS request
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: corsHeaders,
                body: JSON.stringify({ message: 'CORS preflight successful' })
            };
        }
        
        // Parse and validate request body
        if (!event.body) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Request body is required',
                    code: 'MISSING_BODY'
                })
            };
        }
        
        let requestData;
        try {
            requestData = JSON.parse(event.body);
        } catch (parseError) {
            console.error('JSON parse error:', parseError);
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Invalid JSON in request body',
                    code: 'INVALID_JSON'
                })
            };
        }
        
        // Extract and validate form fields
        const { name, email, subject, message } = requestData;
        
        // Validate required fields
        const missingFields = [];
        if (!name || name.trim() === '') missingFields.push('name');
        if (!email || email.trim() === '') missingFields.push('email');
        if (!message || message.trim() === '') missingFields.push('message');
        
        if (missingFields.length > 0) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: \`Missing required fields: \${missingFields.join(', ')}\`,
                    code: 'MISSING_FIELDS',
                    missingFields
                })
            };
        }
        
        // Basic email format validation
        const emailRegex = /^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/;
        if (!emailRegex.test(email)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Invalid email format',
                    code: 'INVALID_EMAIL'
                })
            };
        }
        
        // Sanitize inputs to prevent injection attacks
        const sanitizedData = {
            name: name.trim().substring(0, 100),
            email: email.trim().toLowerCase().substring(0, 100),
            subject: (subject || 'Contact Form Submission').trim().substring(0, 200),
            message: message.trim().substring(0, 5000)
        };
        
        // Prepare email content
        const timestamp = new Date().toISOString();
        const emailSubject = \`Contact Form: \${sanitizedData.subject}\`;
        
        const emailBody = \`
New Contact Form Submission

Submission Details:
-------------------
Timestamp: \${timestamp}
Name: \${sanitizedData.name}
Email: \${sanitizedData.email}
Subject: \${sanitizedData.subject}

Message:
--------
\${sanitizedData.message}

---
This message was sent from your website contact form.
Request ID: \${context.awsRequestId}
        \`.trim();
        
        // Send email using SES
        const emailParams = {
            Source: process.env.FROM_EMAIL,
            Destination: {
                ToAddresses: [process.env.TO_EMAIL]
            },
            Message: {
                Subject: {
                    Data: emailSubject,
                    Charset: 'UTF-8'
                },
                Body: {
                    Text: {
                        Data: emailBody,
                        Charset: 'UTF-8'
                    }
                }
            },
            ReplyToAddresses: [sanitizedData.email]
        };
        
        console.log('Sending email via SES', { 
            from: process.env.FROM_EMAIL,
            to: process.env.TO_EMAIL,
            subject: emailSubject
        });
        
        const sesResponse = await ses.sendEmail(emailParams);
        
        console.log('Email sent successfully', { 
            messageId: sesResponse.MessageId,
            requestId: context.awsRequestId
        });
        
        // Return success response
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                message: 'Contact form submitted successfully',
                messageId: sesResponse.MessageId,
                timestamp: timestamp
            })
        };
        
    } catch (error) {
        console.error('Error processing contact form:', error);
        
        // Handle specific SES errors
        if (error.name === 'MessageRejected') {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Email could not be sent. Please verify the sender email address.',
                    code: 'EMAIL_REJECTED'
                })
            };
        }
        
        if (error.name === 'SendingPausedException') {
            return {
                statusCode: 503,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Email service is temporarily unavailable',
                    code: 'SERVICE_UNAVAILABLE'
                })
            };
        }
        
        // Generic error response
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ 
                error: 'Internal server error. Please try again later.',
                code: 'INTERNAL_ERROR',
                requestId: context.awsRequestId
            })
        };
    }
};
    `.trim();

    // Create Lambda function for contact form processing
    const contactFormFunction = new Function(this, 'ContactFormHandler', {
      runtime: Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: Code.fromInline(lambdaCode),
      timeout: Duration.seconds(30),
      memorySize: 256,
      description: 'Processes contact form submissions and sends emails via SES',
      environment: {
        FROM_EMAIL: props.senderEmail,
        TO_EMAIL: recipientEmail,
        AWS_REGION: this.region
      },
      // Enable detailed monitoring and logging
      logRetention: 14, // days
    });

    // Add SES permissions to Lambda function
    contactFormFunction.addToRolePolicy(
      new PolicyStatement({
        effect: Effect.ALLOW,
        actions: [
          'ses:SendEmail',
          'ses:SendRawEmail'
        ],
        resources: [
          // Allow sending from the verified email address
          `arn:aws:ses:${this.region}:${this.account}:identity/${props.senderEmail}`,
          // Allow sending to the recipient email address (if different)
          ...(recipientEmail !== props.senderEmail ? 
            [`arn:aws:ses:${this.region}:${this.account}:identity/${recipientEmail}`] : [])
        ]
      })
    );

    // Create API Gateway REST API
    const api = new RestApi(this, 'ContactFormApi', {
      restApiName: 'Contact Form API',
      description: 'Serverless API for processing contact form submissions',
      deployOptions: {
        stageName: 'prod',
        description: 'Production stage for contact form API',
        // Enable request/response logging
        loggingLevel: 'INFO',
        dataTraceEnabled: false, // Disable for privacy
        metricsEnabled: true,
        // Configure throttling
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200
      },
      // Configure CORS at the API level
      defaultCorsPreflightOptions: {
        allowOrigins: Cors.ALL_ORIGINS, // Configure specific origins in production
        allowMethods: ['POST', 'OPTIONS'],
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token'
        ],
        maxAge: Duration.hours(1)
      },
      // Enable binary media types if needed for file uploads
      binaryMediaTypes: ['multipart/form-data']
    });

    // Create Lambda integration
    const contactFormIntegration = new LambdaIntegration(contactFormFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true,
      allowTestInvoke: false // Disable test invoke for security
    });

    // Add contact resource and POST method
    const contactResource = api.root.addResource('contact', {
      defaultCorsPreflightOptions: {
        allowOrigins: Cors.ALL_ORIGINS,
        allowMethods: ['POST', 'OPTIONS'],
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token'
        ]
      }
    });

    // Configure method options for additional security
    const methodOptions: MethodOptions = {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Methods': true,
            'Access-Control-Allow-Headers': true
          }
        },
        {
          statusCode: '400',
          responseHeaders: {
            'Access-Control-Allow-Origin': true
          }
        },
        {
          statusCode: '500',
          responseHeaders: {
            'Access-Control-Allow-Origin': true
          }
        }
      ]
    };

    // Add POST method to contact resource
    contactResource.addMethod('POST', contactFormIntegration, methodOptions);

    // Create CloudFormation outputs
    new CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL for the contact form',
      exportName: `${this.stackName}-ApiEndpoint`
    });

    new CfnOutput(this, 'ContactFormUrl', {
      value: `${api.url}contact`,
      description: 'Full URL for contact form submissions',
      exportName: `${this.stackName}-ContactFormUrl`
    });

    new CfnOutput(this, 'LambdaFunctionName', {
      value: contactFormFunction.functionName,
      description: 'Name of the Lambda function processing contact forms',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new CfnOutput(this, 'LambdaFunctionArn', {
      value: contactFormFunction.functionArn,
      description: 'ARN of the Lambda function processing contact forms',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new CfnOutput(this, 'SenderEmail', {
      value: props.senderEmail,
      description: 'Email address used for sending contact form notifications',
      exportName: `${this.stackName}-SenderEmail`
    });

    new CfnOutput(this, 'RecipientEmail', {
      value: recipientEmail,
      description: 'Email address receiving contact form notifications',
      exportName: `${this.stackName}-RecipientEmail`
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new App();

// Get configuration from CDK context or environment variables
const senderEmail = app.node.tryGetContext('senderEmail') || process.env.SENDER_EMAIL;
const recipientEmail = app.node.tryGetContext('recipientEmail') || process.env.RECIPIENT_EMAIL;

if (!senderEmail) {
  throw new Error(
    'Sender email is required. Provide via CDK context (-c senderEmail=your@email.com) ' +
    'or environment variable (SENDER_EMAIL=your@email.com)'
  );
}

// Create the stack
new ContactFormStack(app, 'ContactFormStack', {
  senderEmail,
  recipientEmail,
  description: 'Serverless contact form backend with Lambda, API Gateway, and SES',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Project: 'ContactForm',
    Environment: 'Production',
    ManagedBy: 'CDK'
  }
});

app.synth();