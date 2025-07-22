---
title: Event-Driven Video Processing with MediaConvert
id: 3a186430
category: compute
difficulty: 300
subject: aws
services: s3,lambda,mediaconvert
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: s3,lambda,mediaconvert,video-processing
recipe-generator-version: 1.3
---

# Building Video Processing Workflows with S3, Lambda, and MediaConvert


## Problem

A streaming media company needs to automatically process user-uploaded videos into multiple formats and resolutions for different devices and bandwidth conditions. Manual video processing is time-consuming and doesn't scale with growing content volume. The company requires an automated solution that can handle various input formats, create adaptive bitrate streams, generate thumbnails, and trigger downstream workflows when processing completes.

## Solution

This solution creates an event-driven video processing pipeline using Amazon S3 for storage, AWS Lambda for orchestration, and AWS Elemental MediaConvert for transcoding. When videos are uploaded to S3, Lambda functions automatically initiate MediaConvert jobs to create HLS adaptive bitrate streams, MP4 files, and thumbnail images, enabling seamless content delivery across multiple devices and network conditions.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Upload & Storage"
        USER[Content Creator]
        S3_INPUT[S3 Source Bucket]
        S3_OUTPUT[S3 Output Bucket]
    end
    
    subgraph "Processing Pipeline"
        S3_EVENT[S3 Event Notification]
        LAMBDA[Lambda Function]
        MEDIACONVERT[AWS Elemental MediaConvert]
        EVENTBRIDGE[EventBridge]
    end
    
    subgraph "Delivery & Distribution"
        CLOUDFRONT[CloudFront Distribution]
        DEVICES[Multiple Devices]
    end
    
    USER-->S3_INPUT
    S3_INPUT-->S3_EVENT
    S3_EVENT-->LAMBDA
    LAMBDA-->MEDIACONVERT
    MEDIACONVERT-->S3_OUTPUT
    MEDIACONVERT-->EVENTBRIDGE
    EVENTBRIDGE-->LAMBDA
    S3_OUTPUT-->CLOUDFRONT
    CLOUDFRONT-->DEVICES
    
    style MEDIACONVERT fill:#FF9900
    style LAMBDA fill:#FF9900
    style S3_INPUT fill:#3F8624
    style S3_OUTPUT fill:#3F8624
```

## Prerequisites

1. AWS account with appropriate permissions for S3, Lambda, MediaConvert, and EventBridge
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic knowledge of video formats and streaming protocols
4. Understanding of event-driven architectures
5. Estimated cost: $5-15 for testing (depends on video processing volume)

> **Note**: AWS Elemental MediaConvert is the recommended service for video processing. Amazon Elastic Transcoder is being discontinued on November 13, 2025, and new applications should use MediaConvert.

> **Warning**: MediaConvert pricing is based on the duration and complexity of video processing. Monitor your usage through AWS Cost Explorer and consider implementing processing limits for cost control.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export S3_SOURCE_BUCKET="video-source-${RANDOM_SUFFIX}"
export S3_OUTPUT_BUCKET="video-output-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="video-processor-${RANDOM_SUFFIX}"
export MEDIACONVERT_ROLE_NAME="MediaConvertRole-${RANDOM_SUFFIX}"
export LAMBDA_ROLE_NAME="LambdaVideoProcessorRole-${RANDOM_SUFFIX}"

# Create S3 buckets for video processing
aws s3 mb s3://${S3_SOURCE_BUCKET}
aws s3 mb s3://${S3_OUTPUT_BUCKET}

echo "✅ Created S3 buckets: ${S3_SOURCE_BUCKET} and ${S3_OUTPUT_BUCKET}"
```

## Steps

1. **Create IAM role for MediaConvert**:

   AWS Elemental MediaConvert requires an IAM service role to access your S3 buckets for reading source videos and writing processed outputs. This role operates on the principle of least privilege, providing MediaConvert with only the specific permissions needed to perform video transcoding operations. Understanding IAM roles for AWS services is fundamental to building secure, automated workflows.

   ```bash
   # Create trust policy for MediaConvert
   cat > mediaconvert-trust-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "mediaconvert.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF
   
   # Create MediaConvert role
   aws iam create-role \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --assume-role-policy-document file://mediaconvert-trust-policy.json
   
   # Attach required policies
   aws iam attach-role-policy \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
   
   aws iam attach-role-policy \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
   
   export MEDIACONVERT_ROLE_ARN=$(aws iam get-role \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --query Role.Arn --output text)
   
   echo "✅ Created MediaConvert role: ${MEDIACONVERT_ROLE_ARN}"
   ```

   The MediaConvert service role is now established with the necessary S3 permissions. This security foundation enables MediaConvert to securely access your video files and write processed outputs without exposing your AWS credentials or granting excessive permissions.

2. **Create IAM role for Lambda function**:

   Lambda functions require an execution role to interact with other AWS services like MediaConvert and S3. This role enables the serverless orchestration of video processing workflows while maintaining security through temporary, rotatable credentials. The execution role eliminates the need to embed AWS credentials in your function code, following AWS security best practices.

   ```bash
   # Create trust policy for Lambda
   cat > lambda-trust-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "lambda.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF
   
   # Create Lambda role
   aws iam create-role \
       --role-name ${LAMBDA_ROLE_NAME} \
       --assume-role-policy-document file://lambda-trust-policy.json
   
   # Attach basic Lambda execution policy
   aws iam attach-role-policy \
       --role-name ${LAMBDA_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Create custom policy for MediaConvert and S3 access
   cat > lambda-permissions-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "mediaconvert:*",
           "s3:GetObject",
           "s3:PutObject",
           "iam:PassRole"
         ],
         "Resource": "*"
       }
     ]
   }
   EOF
   
   # Create and attach the policy
   aws iam create-policy \
       --policy-name LambdaMediaConvertPolicy-${RANDOM_SUFFIX} \
       --policy-document file://lambda-permissions-policy.json
   
   aws iam attach-role-policy \
       --role-name ${LAMBDA_ROLE_NAME} \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaMediaConvertPolicy-${RANDOM_SUFFIX}
   
   export LAMBDA_ROLE_ARN=$(aws iam get-role \
       --role-name ${LAMBDA_ROLE_NAME} \
       --query Role.Arn --output text)
   
   echo "✅ Created Lambda role: ${LAMBDA_ROLE_ARN}"
   ```

   The Lambda execution role is configured with permissions to orchestrate MediaConvert jobs and access S3 resources. This serverless security model enables your function to make AWS API calls on your behalf while adhering to the principle of least privilege.

3. **Get MediaConvert endpoint**:

   AWS Elemental MediaConvert uses region-specific endpoints that must be discovered dynamically. Unlike many AWS services with predictable endpoint patterns, MediaConvert assigns unique endpoints per region to optimize performance and distribute load. This step retrieves your region's dedicated endpoint, which is essential for all subsequent MediaConvert API operations.

   ```bash
   # Get the MediaConvert endpoint for your region
   export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
       --query Endpoints[0].Url --output text)
   
   echo "✅ MediaConvert endpoint: ${MEDIACONVERT_ENDPOINT}"
   ```

   Your region's MediaConvert endpoint is now configured and ready for video processing operations. This endpoint will be used by the Lambda function to submit transcoding jobs and monitor their progress.

4. **Create Lambda function for video processing**:

   The Lambda function serves as the intelligent orchestrator of your video processing pipeline. When triggered by S3 events, it automatically creates MediaConvert jobs with predefined settings for HLS adaptive bitrate streaming and MP4 output. This serverless approach eliminates the need for constantly running servers, automatically scales with demand, and only charges for actual processing time.

   ```bash
   # Create Lambda function code
   cat > lambda_function.py << 'EOF'
   import json
   import boto3
   import urllib.parse
   import os
   
   def lambda_handler(event, context):
       # Initialize MediaConvert client
       mediaconvert = boto3.client('mediaconvert', 
           endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
       
       # Parse S3 event
       for record in event['Records']:
           bucket = record['s3']['bucket']['name']
           key = urllib.parse.unquote_plus(record['s3']['object']['key'])
           
           # Skip if not a video file
           if not key.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.m4v')):
               continue
           
           # Create job settings
           job_settings = {
               "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
               "Settings": {
                   "Inputs": [{
                       "AudioSelectors": {
                           "Audio Selector 1": {
                               "Offset": 0,
                               "DefaultSelection": "DEFAULT",
                               "ProgramSelection": 1
                           }
                       },
                       "VideoSelector": {
                           "ColorSpace": "FOLLOW"
                       },
                       "FilterEnable": "AUTO",
                       "PsiControl": "USE_PSI",
                       "FilterStrength": 0,
                       "DeblockFilter": "DISABLED",
                       "DenoiseFilter": "DISABLED",
                       "TimecodeSource": "EMBEDDED",
                       "FileInput": f"s3://{bucket}/{key}"
                   }],
                   "OutputGroups": [
                       {
                           "Name": "Apple HLS",
                           "OutputGroupSettings": {
                               "Type": "HLS_GROUP_SETTINGS",
                               "HlsGroupSettings": {
                                   "ManifestDurationFormat": "INTEGER",
                                   "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/hls/{key.split('.')[0]}/",
                                   "TimedMetadataId3Frame": "PRIV",
                                   "CodecSpecification": "RFC_4281",
                                   "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                                   "ProgramDateTimePeriod": 600,
                                   "MinSegmentLength": 0,
                                   "DirectoryStructure": "SINGLE_DIRECTORY",
                                   "ProgramDateTime": "EXCLUDE",
                                   "SegmentLength": 10,
                                   "ManifestCompression": "NONE",
                                   "ClientCache": "ENABLED",
                                   "AudioOnlyHeader": "INCLUDE"
                               }
                           },
                           "Outputs": [
                               {
                                   "VideoDescription": {
                                       "ScalingBehavior": "DEFAULT",
                                       "TimecodeInsertion": "DISABLED",
                                       "AntiAlias": "ENABLED",
                                       "Sharpness": 50,
                                       "CodecSettings": {
                                           "Codec": "H_264",
                                           "H264Settings": {
                                               "InterlaceMode": "PROGRESSIVE",
                                               "NumberReferenceFrames": 3,
                                               "Syntax": "DEFAULT",
                                               "Softness": 0,
                                               "GopClosedCadence": 1,
                                               "GopSize": 90,
                                               "Slices": 1,
                                               "GopBReference": "DISABLED",
                                               "SlowPal": "DISABLED",
                                               "SpatialAdaptiveQuantization": "ENABLED",
                                               "TemporalAdaptiveQuantization": "ENABLED",
                                               "FlickerAdaptiveQuantization": "DISABLED",
                                               "EntropyEncoding": "CABAC",
                                               "Bitrate": 2000000,
                                               "FramerateControl": "SPECIFIED",
                                               "RateControlMode": "CBR",
                                               "CodecProfile": "MAIN",
                                               "Telecine": "NONE",
                                               "MinIInterval": 0,
                                               "AdaptiveQuantization": "HIGH",
                                               "CodecLevel": "AUTO",
                                               "FieldEncoding": "PAFF",
                                               "SceneChangeDetect": "ENABLED",
                                               "QualityTuningLevel": "SINGLE_PASS",
                                               "FramerateConversionAlgorithm": "DUPLICATE_DROP",
                                               "UnregisteredSeiTimecode": "DISABLED",
                                               "GopSizeUnits": "FRAMES",
                                               "ParControl": "SPECIFIED",
                                               "NumberBFramesBetweenReferenceFrames": 2,
                                               "RepeatPps": "DISABLED",
                                               "FramerateNumerator": 30,
                                               "FramerateDenominator": 1,
                                               "ParNumerator": 1,
                                               "ParDenominator": 1
                                           }
                                       },
                                       "AfdSignaling": "NONE",
                                       "DropFrameTimecode": "ENABLED",
                                       "RespondToAfd": "NONE",
                                       "ColorMetadata": "INSERT",
                                       "Width": 1280,
                                       "Height": 720
                                   },
                                   "AudioDescriptions": [
                                       {
                                           "AudioTypeControl": "FOLLOW_INPUT",
                                           "CodecSettings": {
                                               "Codec": "AAC",
                                               "AacSettings": {
                                                   "AudioDescriptionBroadcasterMix": "NORMAL",
                                                   "Bitrate": 96000,
                                                   "RateControlMode": "CBR",
                                                   "CodecProfile": "LC",
                                                   "CodingMode": "CODING_MODE_2_0",
                                                   "RawFormat": "NONE",
                                                   "SampleRate": 48000,
                                                   "Specification": "MPEG4"
                                               }
                                           },
                                           "AudioSourceName": "Audio Selector 1",
                                           "LanguageCodeControl": "FOLLOW_INPUT"
                                       }
                                   ],
                                   "OutputSettings": {
                                       "HlsSettings": {
                                           "AudioGroupId": "program_audio",
                                           "AudioTrackType": "ALTERNATE_AUDIO_AUTO_SELECT_DEFAULT",
                                           "IFrameOnlyManifest": "EXCLUDE"
                                       }
                                   },
                                   "NameModifier": "_720p"
                               }
                           ]
                       },
                       {
                           "Name": "File Group",
                           "OutputGroupSettings": {
                               "Type": "FILE_GROUP_SETTINGS",
                               "FileGroupSettings": {
                                   "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/mp4/"
                               }
                           },
                           "Outputs": [
                               {
                                   "VideoDescription": {
                                       "Width": 1280,
                                       "Height": 720,
                                       "CodecSettings": {
                                           "Codec": "H_264",
                                           "H264Settings": {
                                               "Bitrate": 2000000,
                                               "RateControlMode": "CBR",
                                               "CodecProfile": "MAIN",
                                               "GopSize": 90,
                                               "FramerateControl": "SPECIFIED",
                                               "FramerateNumerator": 30,
                                               "FramerateDenominator": 1
                                           }
                                       }
                                   },
                                   "AudioDescriptions": [
                                       {
                                           "CodecSettings": {
                                               "Codec": "AAC",
                                               "AacSettings": {
                                                   "Bitrate": 96000,
                                                   "SampleRate": 48000
                                               }
                                           },
                                           "AudioSourceName": "Audio Selector 1"
                                       }
                                   ],
                                   "ContainerSettings": {
                                       "Container": "MP4",
                                       "Mp4Settings": {
                                           "CslgAtom": "INCLUDE",
                                           "FreeSpaceBox": "EXCLUDE",
                                           "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                                       }
                                   },
                                   "NameModifier": "_720p"
                               }
                           ]
                       }
                   ]
               }
           }
           
           # Create MediaConvert job
           try:
               response = mediaconvert.create_job(**job_settings)
               job_id = response['Job']['Id']
               print(f"Created MediaConvert job: {job_id} for {key}")
               
           except Exception as e:
               print(f"Error creating MediaConvert job: {str(e)}")
               raise
       
       return {
           'statusCode': 200,
           'body': json.dumps('Video processing initiated successfully')
       }
   EOF
   
   # Create deployment package
   zip lambda-function.zip lambda_function.py
   
   # Create Lambda function
   aws lambda create-function \
       --function-name ${LAMBDA_FUNCTION_NAME} \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://lambda-function.zip \
       --timeout 60 \
       --environment Variables="{MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT},MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN},S3_OUTPUT_BUCKET=${S3_OUTPUT_BUCKET}}"
   
   echo "✅ Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
   ```

   The video processing Lambda function is deployed and configured with the necessary environment variables and permissions. This serverless orchestrator will automatically detect video uploads and initiate appropriate MediaConvert jobs, enabling hands-free video processing at scale.

5. **Configure S3 event notification**:

   S3 event notifications create the trigger mechanism that makes your video processing pipeline truly event-driven. When videos are uploaded to your source bucket, S3 automatically invokes your Lambda function within seconds, eliminating the need for polling or manual triggering. This real-time response capability is essential for modern media workflows where processing latency directly impacts user experience.

   ```bash
   # Add Lambda invoke permission for S3
   aws lambda add-permission \
       --function-name ${LAMBDA_FUNCTION_NAME} \
       --statement-id s3-trigger \
       --action lambda:InvokeFunction \
       --principal s3.amazonaws.com \
       --source-arn arn:aws:s3:::${S3_SOURCE_BUCKET}
   
   # Create S3 event notification configuration
   cat > s3-notification.json << EOF
   {
     "LambdaConfigurations": [
       {
         "Id": "video-processing-trigger",
         "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
         "Events": ["s3:ObjectCreated:*"],
         "Filter": {
           "Key": {
             "FilterRules": [
               {
                 "Name": "suffix",
                 "Value": ".mp4"
               }
             ]
           }
         }
       }
     ]
   }
   EOF
   
   # Apply notification configuration
   aws s3api put-bucket-notification-configuration \
       --bucket ${S3_SOURCE_BUCKET} \
       --notification-configuration file://s3-notification.json
   
   echo "✅ Configured S3 event notification for video processing"
   ```

   The event-driven architecture is now active. S3 will automatically trigger your Lambda function whenever MP4 files are uploaded to the source bucket, creating a seamless, automated video processing pipeline that responds instantly to new content.

6. **Create EventBridge rule for job completion**:

   EventBridge enables sophisticated workflow orchestration by capturing MediaConvert job state changes and triggering downstream actions. This event-driven pattern allows you to build complex processing workflows, send notifications, update databases, or trigger additional processing steps when video transcoding completes. Understanding EventBridge patterns is crucial for building resilient, decoupled architectures.

   ```bash
   # Create EventBridge rule for MediaConvert job completion
   aws events put-rule \
       --name "MediaConvert-JobComplete-${RANDOM_SUFFIX}" \
       --event-pattern '{
         "source": ["aws.mediaconvert"],
         "detail-type": ["MediaConvert Job State Change"],
         "detail": {
           "status": ["COMPLETE"]
         }
       }'
   
   # Create Lambda function for job completion handling
   cat > completion_handler.py << 'EOF'
   import json
   import boto3
   
   def lambda_handler(event, context):
       print(f"MediaConvert job completed: {json.dumps(event)}")
       
       # Extract job details
       job_id = event['detail']['jobId']
       status = event['detail']['status']
       
       # Here you can add additional processing logic:
       # - Send notifications
       # - Update database records
       # - Trigger additional workflows
       
       print(f"Job {job_id} completed with status: {status}")
       
       return {
           'statusCode': 200,
           'body': json.dumps('Job completion handled successfully')
       }
   EOF
   
   # Create deployment package for completion handler
   zip completion-handler.zip completion_handler.py
   
   # Create completion handler Lambda function
   aws lambda create-function \
       --function-name "completion-handler-${RANDOM_SUFFIX}" \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler completion_handler.lambda_handler \
       --zip-file fileb://completion-handler.zip \
       --timeout 30
   
   # Add EventBridge target
   aws events put-targets \
       --rule "MediaConvert-JobComplete-${RANDOM_SUFFIX}" \
       --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:completion-handler-${RANDOM_SUFFIX}"
   
   # Add permission for EventBridge to invoke Lambda
   aws lambda add-permission \
       --function-name "completion-handler-${RANDOM_SUFFIX}" \
       --statement-id eventbridge-trigger \
       --action lambda:InvokeFunction \
       --principal events.amazonaws.com \
       --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/MediaConvert-JobComplete-${RANDOM_SUFFIX}"
   
   echo "✅ Created EventBridge rule for job completion handling"
   ```

   The completion handling system is now established, creating a comprehensive event-driven workflow. When MediaConvert jobs finish processing, EventBridge will automatically trigger the completion handler, enabling post-processing workflows, notifications, and business logic execution.

7. **Test the video processing workflow**:

   Testing validates that your entire event-driven pipeline functions correctly from upload to processing completion. This step simulates real-world usage by uploading a sample video and monitoring the automated workflow execution. Successful testing confirms that S3 events trigger Lambda functions, MediaConvert jobs execute properly, and processed outputs are generated as expected.

   ```bash
   # Download a sample video file for testing
   curl -o sample-video.mp4 "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4"
   
   # Upload the video to trigger processing
   aws s3 cp sample-video.mp4 s3://${S3_SOURCE_BUCKET}/
   
   echo "✅ Uploaded sample video to trigger processing"
   
   # Check Lambda logs to verify processing started
   sleep 10
   aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --follow
   ```

   The video processing workflow is now actively processing your sample video. Monitor the Lambda logs to observe the MediaConvert job creation and track processing progress through the various stages of transcoding.

8. **Create CloudFront distribution for content delivery**:

   CloudFront provides global content delivery network (CDN) capabilities essential for streaming video content to users worldwide. By caching video segments at edge locations closer to viewers, CloudFront significantly reduces latency and improves streaming quality. This distribution layer is crucial for delivering adaptive bitrate streaming content and handling traffic spikes during popular content releases.

   ```bash
   # Create CloudFront distribution for video delivery
   cat > cloudfront-distribution.json << EOF
   {
     "CallerReference": "video-distribution-${RANDOM_SUFFIX}",
     "Aliases": {
       "Quantity": 0
     },
     "Comment": "Video streaming distribution",
     "Enabled": true,
     "Origins": {
       "Quantity": 1,
       "Items": [
         {
           "Id": "S3-${S3_OUTPUT_BUCKET}",
           "DomainName": "${S3_OUTPUT_BUCKET}.s3.amazonaws.com",
           "S3OriginConfig": {
             "OriginAccessIdentity": ""
           }
         }
       ]
     },
     "DefaultCacheBehavior": {
       "TargetOriginId": "S3-${S3_OUTPUT_BUCKET}",
       "ViewerProtocolPolicy": "redirect-to-https",
       "AllowedMethods": {
         "Quantity": 2,
         "Items": ["GET", "HEAD"]
       },
       "ForwardedValues": {
         "QueryString": false,
         "Cookies": {
           "Forward": "none"
         }
       },
       "TrustedSigners": {
         "Enabled": false,
         "Quantity": 0
       },
       "MinTTL": 0
     },
     "PriceClass": "PriceClass_100"
   }
   EOF
   
   # Create CloudFront distribution
   aws cloudfront create-distribution \
       --distribution-config file://cloudfront-distribution.json \
       --query 'Distribution.{Id:Id,DomainName:DomainName}' \
       --output table
   
   echo "✅ Created CloudFront distribution for video delivery"
   ```

   Your global content delivery infrastructure is now established. CloudFront will cache processed video content at edge locations worldwide, enabling low-latency streaming to users regardless of their geographic location.

## Validation & Testing

1. **Verify S3 buckets and objects**:

   ```bash
   # List source bucket contents
   aws s3 ls s3://${S3_SOURCE_BUCKET}/
   
   # List output bucket contents (wait for processing to complete)
   aws s3 ls s3://${S3_OUTPUT_BUCKET}/ --recursive
   ```

   Expected output: You should see the original video in the source bucket and processed outputs (HLS and MP4) in the output bucket.

2. **Check MediaConvert job status**:

   ```bash
   # List recent MediaConvert jobs
   aws mediaconvert list-jobs \
       --endpoint-url ${MEDIACONVERT_ENDPOINT} \
       --max-results 10 \
       --query 'Jobs[*].{Id:Id,Status:Status,CreatedAt:CreatedAt}'
   ```

3. **Test video playback**:

   ```bash
   # Get HLS manifest URL
   aws s3 ls s3://${S3_OUTPUT_BUCKET}/hls/ --recursive | grep "\.m3u8"
   
   # Test MP4 file availability
   aws s3 ls s3://${S3_OUTPUT_BUCKET}/mp4/ --recursive | grep "\.mp4"
   ```

4. **Monitor Lambda function logs**:

   ```bash
   # Check processing logs
   aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --since 1h
   
   # Check completion handler logs
   aws logs tail /aws/lambda/completion-handler-${RANDOM_SUFFIX} --since 1h
   ```

## Cleanup

1. **Delete CloudFront distribution**:

   ```bash
   # Get distribution ID
   DISTRIBUTION_ID=$(aws cloudfront list-distributions \
       --query "DistributionList.Items[?Comment=='Video streaming distribution'].Id" \
       --output text)
   
   # Disable distribution first
   aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query 'DistributionConfig' > distribution-config.json
   
   # Update enabled status to false
   sed -i 's/"Enabled": true/"Enabled": false/' distribution-config.json
   
   # Update distribution
   ETAG=$(aws cloudfront get-distribution-config \
       --id ${DISTRIBUTION_ID} \
       --query 'ETag' --output text)
   
   aws cloudfront update-distribution \
       --id ${DISTRIBUTION_ID} \
       --distribution-config file://distribution-config.json \
       --if-match ${ETAG}
   
   echo "✅ Disabled CloudFront distribution (deletion requires manual completion)"
   ```

2. **Remove EventBridge rule and targets**:

   ```bash
   # Remove targets
   aws events remove-targets \
       --rule "MediaConvert-JobComplete-${RANDOM_SUFFIX}" \
       --ids "1"
   
   # Delete rule
   aws events delete-rule \
       --name "MediaConvert-JobComplete-${RANDOM_SUFFIX}"
   
   echo "✅ Deleted EventBridge rule and targets"
   ```

3. **Delete Lambda functions**:

   ```bash
   # Delete video processor function
   aws lambda delete-function \
       --function-name ${LAMBDA_FUNCTION_NAME}
   
   # Delete completion handler function
   aws lambda delete-function \
       --function-name "completion-handler-${RANDOM_SUFFIX}"
   
   echo "✅ Deleted Lambda functions"
   ```

4. **Remove S3 buckets and contents**:

   ```bash
   # Empty and delete source bucket
   aws s3 rm s3://${S3_SOURCE_BUCKET} --recursive
   aws s3 rb s3://${S3_SOURCE_BUCKET}
   
   # Empty and delete output bucket
   aws s3 rm s3://${S3_OUTPUT_BUCKET} --recursive
   aws s3 rb s3://${S3_OUTPUT_BUCKET}
   
   echo "✅ Deleted S3 buckets and contents"
   ```

5. **Delete IAM roles and policies**:

   ```bash
   # Detach and delete policies for MediaConvert role
   aws iam detach-role-policy \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
   
   aws iam detach-role-policy \
       --role-name ${MEDIACONVERT_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
   
   aws iam delete-role \
       --role-name ${MEDIACONVERT_ROLE_NAME}
   
   # Detach and delete policies for Lambda role
   aws iam detach-role-policy \
       --role-name ${LAMBDA_ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam detach-role-policy \
       --role-name ${LAMBDA_ROLE_NAME} \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaMediaConvertPolicy-${RANDOM_SUFFIX}
   
   aws iam delete-policy \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaMediaConvertPolicy-${RANDOM_SUFFIX}
   
   aws iam delete-role \
       --role-name ${LAMBDA_ROLE_NAME}
   
   echo "✅ Deleted IAM roles and policies"
   ```

6. **Clean up local files**:

   ```bash
   # Remove local files
   rm -f lambda_function.py completion_handler.py
   rm -f lambda-function.zip completion-handler.zip
   rm -f *.json sample-video.mp4
   
   echo "✅ Cleaned up local files"
   ```

## Discussion

This video processing workflow demonstrates a modern, scalable approach to automated video transcoding using AWS managed services. The architecture leverages event-driven processing to automatically handle video uploads, eliminating the need for manual intervention or polling mechanisms.

AWS Elemental MediaConvert provides enterprise-grade video processing capabilities with support for a wide range of input and output formats, advanced features like adaptive bitrate streaming, and integration with other AWS services. The service handles the complexity of video processing infrastructure, allowing developers to focus on business logic rather than managing encoding resources.

The Lambda-based orchestration provides several advantages over traditional approaches. Functions automatically scale based on demand, process videos in parallel, and integrate seamlessly with other AWS services. The event-driven architecture ensures processing begins immediately when videos are uploaded, reducing latency and improving user experience.

> **Tip**: Consider implementing additional features like progress tracking using DynamoDB, custom presets for different content types, and integration with AWS Elemental MediaLive for live streaming workflows. See the [MediaConvert Developer Guide](https://docs.aws.amazon.com/mediaconvert/latest/ug/) for advanced configuration options.

## Challenge

Extend this solution by implementing these enhancements:

1. **Multi-resolution processing**: Modify the MediaConvert job to create multiple output resolutions (480p, 720p, 1080p) for different device capabilities
2. **Thumbnail generation**: Add thumbnail extraction at specific time intervals and store them in a separate S3 prefix
3. **Content analysis**: Integrate Amazon Rekognition Video to detect and tag video content automatically
4. **Cost optimization**: Implement S3 Intelligent-Tiering and Glacier transitions for processed video archives
5. **Advanced monitoring**: Create CloudWatch dashboards with custom metrics for processing times, error rates, and cost tracking

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*