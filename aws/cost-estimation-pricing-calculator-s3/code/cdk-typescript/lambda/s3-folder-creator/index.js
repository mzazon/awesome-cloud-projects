/**
 * AWS Lambda function to create folder structure in S3 bucket
 * This custom resource handler creates empty objects with trailing slashes
 * to establish folder structure in S3 for cost estimate organization
 */

const AWS = require('aws-sdk');
const response = require('cfn-response');

const s3 = new AWS.S3();

/**
 * Lambda handler for S3 folder creation custom resource
 * 
 * @param {Object} event - CloudFormation custom resource event
 * @param {Object} context - Lambda context object
 */
exports.handler = async (event, context) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const { RequestType, ResourceProperties } = event;
  const { BucketName, ProjectName, Folders } = ResourceProperties;

  try {
    if (RequestType === 'Create' || RequestType === 'Update') {
      console.log(`Creating folder structure in bucket: ${BucketName}`);
      
      // Create each folder by putting an empty object with trailing slash
      const folderPromises = Folders.map(async (folder) => {
        const params = {
          Bucket: BucketName,
          Key: folder,
          Body: '',
          Metadata: {
            'created-by': 'cost-estimation-cdk',
            'project': ProjectName,
            'created-date': new Date().toISOString(),
          },
        };

        console.log(`Creating folder: ${folder}`);
        return s3.putObject(params).promise();
      });

      // Wait for all folders to be created
      await Promise.all(folderPromises);
      console.log('Successfully created all folder structures');

      // Send success response to CloudFormation
      await response.send(event, context, response.SUCCESS, {
        Message: `Successfully created ${Folders.length} folders in bucket ${BucketName}`,
        BucketName: BucketName,
        FoldersCreated: Folders.length,
      });

    } else if (RequestType === 'Delete') {
      console.log('Delete operation - no cleanup needed for folders');
      
      // Send success response for delete operation
      await response.send(event, context, response.SUCCESS, {
        Message: 'Folder structure cleanup not required',
      });
    }

  } catch (error) {
    console.error('Error in S3 folder creation:', error);
    
    // Send failure response to CloudFormation
    await response.send(event, context, response.FAILED, {
      Error: error.message,
      Message: `Failed to create folder structure in bucket ${BucketName}`,
    });
  }
};