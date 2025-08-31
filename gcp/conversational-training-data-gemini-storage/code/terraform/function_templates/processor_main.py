import json
from google.cloud import storage
import pandas as pd
from typing import List, Dict
import logging
import functions_framework
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def process_conversations(request):
    """Process raw conversations into training-ready formats."""
    
    try:
        # Set CORS headers
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        if request.method == 'OPTIONS':
            return ('', 204, headers)
            
        storage_client = storage.Client()
        request_json = request.get_json(silent=True) or {}
        bucket_name = request_json.get('bucket_name')
        
        if not bucket_name:
            return (json.dumps({'status': 'error', 'message': 'bucket_name required'}), 400, headers)
            
        bucket = storage_client.bucket(bucket_name)
        
        # List all raw conversation files
        raw_blobs = list(bucket.list_blobs(prefix='raw-conversations/'))
        
        all_conversations = []
        training_pairs = []
        generation_metadata = []
        
        # Process each file
        for blob in raw_blobs:
            if blob.name.endswith('.json') and not blob.name.endswith('.keep'):
                try:
                    content = json.loads(blob.download_as_text())
                    conversations = content.get('conversations', [])
                    file_metadata = content.get('generation_metadata', {})
                    generation_metadata.append(file_metadata)
                    
                    for conv in conversations:
                        all_conversations.append(conv)
                        
                        # Create training pairs from conversation messages
                        messages = conv.get('messages', [])
                        conversation_history = []
                        
                        for i, message in enumerate(messages):
                            if message['role'] == 'user':
                                # Find corresponding assistant response
                                if i + 1 < len(messages) and messages[i + 1]['role'] == 'assistant':
                                    training_pairs.append({
                                        'conversation_id': conv.get('conversation_id', str(uuid.uuid4())),
                                        'scenario': conv.get('scenario', 'unknown'),
                                        'intent': conv.get('intent', 'unknown'),
                                        'conversation_history': conversation_history.copy(),
                                        'user_input': message['content'],
                                        'assistant_response': messages[i + 1]['content'],
                                        'turn_number': len(conversation_history) // 2 + 1,
                                        'generation_metadata': conv.get('generation_metadata', {})
                                    })
                            
                            conversation_history.append({
                                'role': message['role'],
                                'content': message['content']
                            })
                except Exception as e:
                    logger.warning(f"Failed to process {blob.name}: {e}")
                    continue
        
        if not training_pairs:
            return (json.dumps({'status': 'error', 'message': 'No training data found to process'}), 400, headers)
        
        # Create different output formats
        try:
            formats = {
                'jsonl': create_jsonl_format(training_pairs),
                'csv': create_csv_format(training_pairs),
                'chatml': create_chatml_format(training_pairs),
                'alpaca': create_alpaca_format(training_pairs)
            }
        except Exception as e:
            logger.error(f"Failed to create training formats: {e}")
            return (json.dumps({'status': 'error', 'message': f'Failed to format data: {e}'}), 500, headers)
        
        # Save processed data in multiple formats
        processing_id = str(uuid.uuid4())[:8]
        saved_files = []
        
        for format_name, format_data in formats.items():
            try:
                blob_name = f"formatted-training/training_data_{processing_id}.{format_name}"
                blob = bucket.blob(blob_name)
                blob.upload_from_string(format_data)
                saved_files.append(blob_name)
                logger.info(f"Saved {format_name} format to {blob_name}")
            except Exception as e:
                logger.warning(f"Failed to save {format_name} format: {e}")
        
        # Create summary statistics
        stats = {
            'processing_id': processing_id,
            'total_conversations': len(all_conversations),
            'total_training_pairs': len(training_pairs),
            'scenarios': list(set(conv.get('scenario', 'unknown') for conv in all_conversations)),
            'intents': list(set(conv.get('intent', 'unknown') for conv in all_conversations)),
            'files_processed': len([blob for blob in raw_blobs if blob.name.endswith('.json') and not blob.name.endswith('.keep')]),
            'average_conversation_length': sum(len(conv.get('messages', [])) for conv in all_conversations) / len(all_conversations) if all_conversations else 0,
            'turn_distribution': get_turn_distribution(training_pairs),
            'generation_metadata_summary': generation_metadata
        }
        
        # Save statistics
        try:
            stats_blob = bucket.blob(f'processed-conversations/processing_stats_{processing_id}.json')
            stats_blob.upload_from_string(json.dumps(stats, indent=2))
            saved_files.append(f'processed-conversations/processing_stats_{processing_id}.json')
        except Exception as e:
            logger.warning(f"Failed to save statistics: {e}")
        
        result = {
            'status': 'success',
            'processing_id': processing_id,
            'processed_conversations': len(all_conversations),
            'training_pairs_created': len(training_pairs),
            'output_formats': list(formats.keys()),
            'saved_files': saved_files,
            'statistics': stats
        }
        
        logger.info(f"Successfully processed {len(all_conversations)} conversations into {len(training_pairs)} training pairs")
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        logger.error(f"Processing error: {str(e)}")
        error_result = {'status': 'error', 'message': str(e)}
        return (json.dumps(error_result), 500, headers)

def create_jsonl_format(training_pairs: List[Dict]) -> str:
    """Create JSONL format for training."""
    lines = []
    for pair in training_pairs:
        jsonl_record = {
            'messages': pair['conversation_history'] + [
                {'role': 'user', 'content': pair['user_input']},
                {'role': 'assistant', 'content': pair['assistant_response']}
            ],
            'metadata': {
                'conversation_id': pair['conversation_id'],
                'scenario': pair['scenario'],
                'intent': pair['intent'],
                'turn_number': pair['turn_number'],
                'generation_metadata': pair.get('generation_metadata', {})
            }
        }
        lines.append(json.dumps(jsonl_record))
    return '\n'.join(lines)

def create_csv_format(training_pairs: List[Dict]) -> str:
    """Create CSV format for training."""
    df_data = []
    for pair in training_pairs:
        history_text = ' '.join([f"{msg['role']}: {msg['content']}" 
                               for msg in pair['conversation_history']])
        df_data.append({
            'conversation_id': pair['conversation_id'],
            'scenario': pair['scenario'],
            'intent': pair['intent'],
            'conversation_history': history_text,
            'user_input': pair['user_input'],
            'assistant_response': pair['assistant_response'],
            'turn_number': pair['turn_number']
        })
    
    df = pd.DataFrame(df_data)
    return df.to_csv(index=False)

def create_chatml_format(training_pairs: List[Dict]) -> str:
    """Create ChatML format for training."""
    chatml_conversations = []
    for pair in training_pairs:
        conversation = []
        for msg in pair['conversation_history']:
            conversation.append(f"<|im_start|>{msg['role']}\n{msg['content']}<|im_end|>")
        conversation.append(f"<|im_start|>user\n{pair['user_input']}<|im_end|>")
        conversation.append(f"<|im_start|>assistant\n{pair['assistant_response']}<|im_end|>")
        chatml_conversations.append('\n'.join(conversation))
    
    return '\n\n'.join(chatml_conversations)

def create_alpaca_format(training_pairs: List[Dict]) -> str:
    """Create Alpaca instruction format for training."""
    alpaca_data = []
    for pair in training_pairs:
        # Create context from conversation history
        context = ""
        if pair['conversation_history']:
            context = "Previous conversation:\n" + '\n'.join([
                f"{msg['role'].title()}: {msg['content']}" 
                for msg in pair['conversation_history']
            ]) + "\n\n"
        
        alpaca_record = {
            'instruction': f"You are an AI assistant helping with {pair['scenario']}. {context}Respond to the following user message:",
            'input': pair['user_input'],
            'output': pair['assistant_response'],
            'metadata': {
                'conversation_id': pair['conversation_id'],
                'scenario': pair['scenario'],
                'intent': pair['intent'],
                'turn_number': pair['turn_number']
            }
        }
        alpaca_data.append(alpaca_record)
    
    return json.dumps(alpaca_data, indent=2)

def get_turn_distribution(training_pairs: List[Dict]) -> Dict[int, int]:
    """Get distribution of conversation turns."""
    turn_counts = {}
    for pair in training_pairs:
        turn = pair['turn_number']
        turn_counts[turn] = turn_counts.get(turn, 0) + 1
    return turn_counts