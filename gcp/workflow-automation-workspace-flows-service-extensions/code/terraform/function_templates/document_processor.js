/**
 * Document Processing Cloud Function
 * 
 * This function processes documents uploaded to the workflow system,
 * extracts metadata, and publishes events to trigger subsequent workflow steps.
 * 
 * Environment Variables:
 * - TOPIC_NAME: Pub/Sub topic for publishing document events
 * - BUCKET_NAME: Storage bucket name for documents
 * - PROJECT_ID: Google Cloud Project ID
 */

const {GoogleAuth} = require('google-auth-library');
const {PubSub} = require('@google-cloud/pubsub');
const {Storage} = require('@google-cloud/storage');
const {google} = require('googleapis');

// Initialize Google Cloud clients
const pubsub = new PubSub();
const storage = new Storage();

/**
 * HTTP Cloud Function that processes document upload events
 * 
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 */
exports.processDocument = async (req, res) => {
  try {
    // Validate request body
    const {fileName, bucketName, metadata} = req.body;
    
    if (!fileName || !bucketName) {
      return res.status(400).json({
        error: 'Missing required parameters: fileName and bucketName'
      });
    }

    console.log(`Processing document: $${fileName} from bucket: $${bucketName}`);

    // Extract document metadata from Cloud Storage
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(fileName);
    
    let fileMetadata;
    try {
      [fileMetadata] = await file.getMetadata();
    } catch (error) {
      console.error('Error fetching file metadata:', error);
      return res.status(404).json({
        error: 'File not found or inaccessible'
      });
    }

    // Generate unique workflow ID
    const workflowId = `workflow-$${Date.now()}-$${Math.random().toString(36).substr(2, 9)}`;

    // Prepare comprehensive processing event
    const processingEvent = {
      documentId: fileName,
      workflowId: workflowId,
      timestamp: new Date().toISOString(),
      metadata: {
        size: fileMetadata.size,
        contentType: fileMetadata.contentType,
        created: fileMetadata.timeCreated,
        updated: fileMetadata.updated,
        md5Hash: fileMetadata.md5Hash,
        crc32c: fileMetadata.crc32c,
        storageClass: fileMetadata.storageClass,
        bucket: bucketName,
        generation: fileMetadata.generation,
        ...metadata // Merge user-provided metadata
      },
      processingStage: 'analysis',
      source: 'document-processor',
      version: '1.0'
    };

    // Validate processing event data
    if (!processingEvent.metadata.contentType) {
      console.warn('Content type not detected, setting default');
      processingEvent.metadata.contentType = 'application/octet-stream';
    }

    // Publish event to Pub/Sub for downstream processing
    const topicName = '${topic_name}';
    const dataBuffer = Buffer.from(JSON.stringify(processingEvent));
    
    try {
      const messageId = await pubsub.topic(topicName).publish(dataBuffer, {
        source: 'document-processor',
        workflowId: workflowId,
        documentType: metadata?.document_type || 'unknown',
        priority: metadata?.priority || 'normal'
      });
      
      console.log(`Published message $${messageId} to topic $${topicName}`);
    } catch (error) {
      console.error('Error publishing to Pub/Sub:', error);
      return res.status(500).json({
        error: 'Failed to publish processing event',
        details: error.message
      });
    }

    // Log successful processing
    console.log(`Document processing initiated for workflow: $${workflowId}`);

    // Return success response with workflow details
    res.status(200).json({
      success: true,
      workflowId: workflowId,
      message: 'Document processing initiated successfully',
      details: {
        fileName: fileName,
        bucketName: bucketName,
        contentType: processingEvent.metadata.contentType,
        size: processingEvent.metadata.size,
        timestamp: processingEvent.timestamp
      }
    });

  } catch (error) {
    console.error('Unexpected error in document processing:', error);
    res.status(500).json({
      error: 'Internal server error during document processing',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
};