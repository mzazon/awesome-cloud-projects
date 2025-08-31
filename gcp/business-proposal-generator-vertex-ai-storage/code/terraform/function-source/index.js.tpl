const { Storage } = require('@google-cloud/storage');
const { VertexAI } = require('@google-cloud/vertexai');
const functions = require('@google-cloud/functions-framework');

// Initialize Cloud Storage client
const storage = new Storage();

/**
 * Cloud Function to generate business proposals using Vertex AI
 * Triggered by Cloud Storage object creation events
 */
functions.cloudEvent('generateProposal', async (cloudEvent) => {
  try {
    console.log('Proposal generation triggered by file:', cloudEvent.data.name);
    console.log('Event details:', JSON.stringify(cloudEvent, null, 2));
    
    const bucketName = cloudEvent.data.bucket;
    const fileName = cloudEvent.data.name;
    
    // Skip if not a JSON client data file
    if (!fileName.endsWith('.json')) {
      console.log('Skipping non-JSON file:', fileName);
      return;
    }
    
    // Skip if file is in logs or system directories
    if (fileName.includes('/logs/') || fileName.startsWith('.') || fileName.includes('temp/')) {
      console.log('Skipping system or log file:', fileName);
      return;
    }
    
    console.log('Processing client data file:', fileName);
    
    // Download client data from the triggering bucket
    const clientDataFile = storage.bucket(bucketName).file(fileName);
    const [clientDataExists] = await clientDataFile.exists();
    
    if (!clientDataExists) {
      console.error('Client data file does not exist:', fileName);
      return;
    }
    
    const [clientDataContent] = await clientDataFile.download();
    let clientData;
    
    try {
      clientData = JSON.parse(clientDataContent.toString());
      console.log('Parsed client data:', JSON.stringify(clientData, null, 2));
    } catch (parseError) {
      console.error('Error parsing client data JSON:', parseError);
      throw new Error('Invalid JSON format in client data file');
    }
    
    // Validate required client data fields
    if (!clientData.client_name || !clientData.project_type) {
      console.error('Missing required fields: client_name and project_type are mandatory');
      throw new Error('Client data must include client_name and project_type');
    }
    
    // Download proposal template from templates bucket
    const templateBucket = '${templates_bucket}';
    console.log('Downloading template from bucket:', templateBucket);
    
    const templateFile = storage.bucket(templateBucket).file('proposal-template.txt');
    const [templateExists] = await templateFile.exists();
    
    if (!templateExists) {
      console.error('Proposal template not found in bucket:', templateBucket);
      throw new Error('Proposal template file not found');
    }
    
    const [templateContent] = await templateFile.download();
    const template = templateContent.toString();
    console.log('Template loaded successfully, length:', template.length);
    
    // Initialize Vertex AI with project configuration
    const projectId = process.env.GOOGLE_CLOUD_PROJECT;
    const location = '${region}';
    
    console.log('Initializing Vertex AI for project:', projectId, 'in region:', location);
    
    const vertexAI = new VertexAI({
      project: projectId,
      location: location
    });
    
    // Configure the generative model with optimized parameters
    const generativeModel = vertexAI.getGenerativeModel({
      model: '${vertex_ai_model}',
      generationConfig: {
        maxOutputTokens: ${max_output_tokens},
        temperature: ${temperature},
        topP: ${top_p},
        topK: ${top_k}
      }
    });
    
    // Create comprehensive prompt for proposal generation
    const prompt = `You are a professional business proposal writer with expertise in creating compelling, customized proposals. 

Based on the following client information and proposal template, generate a complete, professional business proposal. Replace ALL placeholder values (enclosed in double curly braces like {{PLACEHOLDER}}) with specific, relevant content based on the client data.

CLIENT INFORMATION:
${JSON.stringify(clientData, null, 2)}

PROPOSAL TEMPLATE:
${template}

INSTRUCTIONS:
1. Replace each {{PLACEHOLDER}} with specific, professional content relevant to the client
2. Use the client's industry context to make recommendations more relevant
3. Create specific timelines, approaches, and next steps based on the project requirements
4. Maintain a professional, persuasive tone throughout
5. Ensure all content is realistic and actionable
6. If any placeholder cannot be filled from the client data, create reasonable professional content based on the project type and industry

Return the complete proposal with all placeholders replaced by substantive content. Do not include any placeholder syntax in the final output.`;

    console.log('Sending request to Vertex AI model:', '${vertex_ai_model}');
    
    const request = {
      contents: [{
        role: 'user',
        parts: [{ text: prompt }]
      }]
    };
    
    // Generate proposal content using Vertex AI
    const startTime = Date.now();
    const result = await generativeModel.generateContent(request);
    const processingTime = Date.now() - startTime;
    
    console.log('Vertex AI processing completed in', processingTime, 'ms');
    
    if (!result.response || !result.response.candidates || result.response.candidates.length === 0) {
      console.error('No valid response from Vertex AI');
      throw new Error('Vertex AI did not return a valid response');
    }
    
    const response = result.response;
    const generatedContent = response.candidates[0].content.parts[0].text;
    
    if (!generatedContent || generatedContent.trim().length === 0) {
      console.error('Generated content is empty');
      throw new Error('Vertex AI returned empty content');
    }
    
    console.log('Generated proposal length:', generatedContent.length, 'characters');
    
    // Create output filename with timestamp and client name
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const clientNameSafe = clientData.client_name.replace(/[^a-zA-Z0-9]/g, '-').toLowerCase();
    const outputFileName = `proposal-$${clientNameSafe}-$${timestamp}.txt`;
    
    // Save generated proposal to output bucket
    const outputBucket = '${output_bucket}';
    console.log('Saving proposal to bucket:', outputBucket, 'as:', outputFileName);
    
    const outputFile = storage.bucket(outputBucket).file(outputFileName);
    
    // Add metadata header to the proposal
    const proposalWithMetadata = `Generated Business Proposal
Generated on: $${new Date().toISOString()}
Client: $${clientData.client_name}
Project Type: $${clientData.project_type}
Model Used: ${vertex_ai_model}
Processing Time: $${processingTime}ms

${'='.repeat(80)}

$${generatedContent}`;
    
    await outputFile.save(proposalWithMetadata, {
      metadata: {
        contentType: 'text/plain',
        metadata: {
          'client-name': clientData.client_name,
          'project-type': clientData.project_type,
          'generated-timestamp': new Date().toISOString(),
          'vertex-ai-model': '${vertex_ai_model}',
          'processing-time-ms': processingTime.toString()
        }
      }
    });
    
    console.log(`✅ Proposal generated successfully: $${outputFileName}`);
    console.log(`📊 Processing metrics: $${processingTime}ms generation time, $${generatedContent.length} characters`);
    
    // Log success metrics for monitoring
    console.log(JSON.stringify({
      event: 'proposal_generated',
      client_name: clientData.client_name,
      project_type: clientData.project_type,
      output_file: outputFileName,
      processing_time_ms: processingTime,
      content_length: generatedContent.length,
      model_used: '${vertex_ai_model}',
      timestamp: new Date().toISOString()
    }));
    
  } catch (error) {
    // Comprehensive error logging for debugging
    console.error('❌ Error generating proposal:', error);
    console.error('Error stack:', error.stack);
    
    // Log structured error for monitoring
    console.error(JSON.stringify({
      event: 'proposal_generation_failed',
      error_message: error.message,
      error_type: error.constructor.name,
      cloud_event_data: cloudEvent.data,
      timestamp: new Date().toISOString()
    }));
    
    // Re-throw to ensure function fails and can be retried
    throw error;
  }
});