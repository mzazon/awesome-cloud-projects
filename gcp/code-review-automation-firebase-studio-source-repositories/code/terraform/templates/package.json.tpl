{
  "name": "${function_name}",
  "version": "1.0.0",
  "description": "AI-powered code review automation function for Google Cloud",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1",
    "start": "node index.js"
  },
  "keywords": [
    "google-cloud",
    "cloud-functions",
    "vertex-ai",
    "code-review",
    "automation",
    "firebase-studio"
  ],
  "author": "Cloud Recipe Generator",
  "license": "Apache-2.0",
  "engines": {
    "node": ">=18.0.0"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/vertexai": "^1.4.0",
    "@google-cloud/storage": "^7.7.0",
    "@google-cloud/secret-manager": "^5.5.0",
    "@google-cloud/logging": "^11.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "eslint": "^8.0.0"
  },
  "repository": {
    "type": "git",
    "url": "https://source.developers.google.com/p/${project_id}/r/${repository_name}"
  },
  "bugs": {
    "url": "https://github.com/GoogleCloudPlatform/cloud-functions-samples/issues"
  },
  "homepage": "https://cloud.google.com/functions"
}