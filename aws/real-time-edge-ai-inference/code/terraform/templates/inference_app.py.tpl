#!/usr/bin/env python3
"""
Real-time Edge AI Inference Engine
This component performs ML inference on edge devices using ONNX Runtime
and publishes results to AWS EventBridge for centralized monitoring.
"""

import json
import time
import boto3
import onnxruntime as ort
import numpy as np
from datetime import datetime
import cv2
import os
import logging
import signal
import sys
from typing import Optional, Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class EdgeInferenceEngine:
    """
    Edge AI Inference Engine with EventBridge integration
    
    This class handles:
    - ONNX model loading and inference
    - Image preprocessing and postprocessing
    - EventBridge event publishing
    - Error handling and monitoring
    """
    
    def __init__(self):
        # Configuration from environment variables
        self.model_path = os.environ.get(
            'MODEL_PATH', 
            '/greengrass/v2/work/com.${replace(project_name, "-", ".")}.DefectDetectionModel/model.onnx'
        )
        self.device_id = os.environ.get('AWS_IOT_THING_NAME', 'unknown-device')
        self.event_bus_name = os.environ.get('EVENT_BUS_NAME', '${event_bus_name}')
        self.confidence_threshold = float(os.environ.get('CONFIDENCE_THRESHOLD', '${confidence_threshold}'))
        self.inference_interval = int(os.environ.get('INFERENCE_INTERVAL', '${inference_interval}'))
        
        # Initialize AWS clients
        try:
            self.eventbridge = boto3.client('events')
            logger.info("✅ EventBridge client initialized successfully")
        except Exception as e:
            logger.error(f"❌ Failed to initialize EventBridge client: {e}")
            self.eventbridge = None
        
        # Model session
        self.session = None
        self.model_loaded = False
        
        # Statistics
        self.inference_count = 0
        self.error_count = 0
        self.start_time = datetime.utcnow()
        
        # Graceful shutdown handling
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        self.shutdown_requested = False
        
        # Load model on initialization
        self.load_model()
    
    def _signal_handler(self, signum, frame):
        """Handle graceful shutdown signals"""
        logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.shutdown_requested = True
    
    def load_model(self) -> bool:
        """
        Load ONNX model for inference
        
        Returns:
            bool: True if model loaded successfully, False otherwise
        """
        try:
            if not os.path.exists(self.model_path):
                logger.error(f"❌ Model file not found: {self.model_path}")
                self.publish_event('ModelLoadError', {
                    'error': f'Model file not found: {self.model_path}',
                    'device_id': self.device_id
                })
                return False
            
            # Load ONNX model with optimizations
            session_options = ort.SessionOptions()
            session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            
            self.session = ort.InferenceSession(
                self.model_path,
                sess_options=session_options
            )
            
            # Log model information
            input_info = self.session.get_inputs()[0]
            output_info = self.session.get_outputs()[0]
            
            logger.info(f"✅ Model loaded successfully from {self.model_path}")
            logger.info(f"   Input shape: {input_info.shape}")
            logger.info(f"   Input type: {input_info.type}")
            logger.info(f"   Output shape: {output_info.shape}")
            logger.info(f"   Output type: {output_info.type}")
            
            self.model_loaded = True
            
            # Publish model load success event
            self.publish_event('ModelLoaded', {
                'model_path': self.model_path,
                'input_shape': input_info.shape,
                'output_shape': output_info.shape,
                'device_id': self.device_id
            })
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Model loading failed: {e}")
            self.publish_event('ModelLoadError', {
                'error': str(e),
                'model_path': self.model_path,
                'device_id': self.device_id
            })
            self.model_loaded = False
            return False
    
    def preprocess_image(self, image_path: str) -> Optional[np.ndarray]:
        """
        Preprocess image for model input
        
        Args:
            image_path: Path to the input image
            
        Returns:
            Preprocessed image array or None if preprocessing fails
        """
        try:
            # Read image
            image = cv2.imread(image_path)
            if image is None:
                logger.error(f"❌ Failed to read image: {image_path}")
                return None
            
            # Resize to model input size (224x224 for most vision models)
            image = cv2.resize(image, (224, 224))
            
            # Convert BGR to RGB
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            
            # Normalize pixel values to [0, 1]
            image = image.astype(np.float32) / 255.0
            
            # Transpose to CHW format (channels first)
            image = np.transpose(image, (2, 0, 1))
            
            # Add batch dimension
            image = np.expand_dims(image, axis=0)
            
            return image
            
        except Exception as e:
            logger.error(f"❌ Image preprocessing failed: {e}")
            return None
    
    def run_inference(self, image_path: str) -> Optional[Dict[str, Any]]:
        """
        Perform inference on image
        
        Args:
            image_path: Path to the input image
            
        Returns:
            Inference result dictionary or None if inference fails
        """
        if not self.model_loaded:
            logger.error("❌ Model not loaded, cannot run inference")
            return None
        
        start_time = time.time()
        
        try:
            # Preprocess image
            input_data = self.preprocess_image(image_path)
            if input_data is None:
                return None
            
            # Run inference
            input_name = self.session.get_inputs()[0].name
            outputs = self.session.run(None, {input_name: input_data})
            
            # Process results
            predictions = outputs[0][0]  # Remove batch dimension
            class_idx = np.argmax(predictions)
            confidence = float(predictions[class_idx])
            
            # Calculate inference time
            inference_time_ms = (time.time() - start_time) * 1000
            
            # Determine prediction label
            prediction_label = 'defect' if class_idx == 1 else 'normal'
            
            # Create result dictionary
            result = {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': self.device_id,
                'image_path': image_path,
                'prediction': prediction_label,
                'confidence': confidence,
                'inference_time_ms': round(inference_time_ms, 2),
                'model_name': '${model_name}',
                'class_probabilities': predictions.tolist()
            }
            
            # Update statistics
            self.inference_count += 1
            
            # Log result if confidence is above threshold
            if confidence >= self.confidence_threshold:
                logger.info(
                    f"🔍 Inference: {prediction_label} "
                    f"(confidence: {confidence:.3f}, "
                    f"time: {inference_time_ms:.1f}ms)"
                )
            else:
                logger.warning(
                    f"⚠️  Low confidence inference: {prediction_label} "
                    f"(confidence: {confidence:.3f} < {self.confidence_threshold})"
                )
            
            # Publish inference event
            event_type = 'InferenceCompleted' if confidence >= self.confidence_threshold else 'LowConfidenceInference'
            self.publish_event(event_type, result)
            
            return result
            
        except Exception as e:
            self.error_count += 1
            logger.error(f"❌ Inference failed: {e}")
            self.publish_event('InferenceError', {
                'error': str(e),
                'image_path': image_path,
                'device_id': self.device_id,
                'inference_time_ms': (time.time() - start_time) * 1000
            })
            return None
    
    def publish_event(self, event_type: str, detail: Dict[str, Any]) -> bool:
        """
        Publish inference events to EventBridge
        
        Args:
            event_type: Type of event (e.g., 'InferenceCompleted')
            detail: Event detail dictionary
            
        Returns:
            bool: True if event published successfully, False otherwise
        """
        if not self.eventbridge:
            logger.warning("⚠️  EventBridge client not available, skipping event publish")
            return False
        
        try:
            # Add common fields to detail
            detail.update({
                'event_timestamp': datetime.utcnow().isoformat(),
                'device_id': self.device_id,
                'inference_count': self.inference_count,
                'error_count': self.error_count,
                'uptime_seconds': (datetime.utcnow() - self.start_time).total_seconds()
            })
            
            # Publish event
            response = self.eventbridge.put_events(
                Entries=[{
                    'Source': 'edge.ai.inference',
                    'DetailType': event_type,
                    'Detail': json.dumps(detail, default=str),
                    'EventBusName': self.event_bus_name
                }]
            )
            
            # Check for failures
            if response.get('FailedEntryCount', 0) > 0:
                logger.error(f"❌ Failed to publish event: {response}")
                return False
            
            logger.debug(f"📤 Published event: {event_type}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to publish event: {e}")
            return False
    
    def create_sample_image(self, image_path: str) -> bool:
        """
        Create a sample image for testing if none exists
        
        Args:
            image_path: Path where to create the sample image
            
        Returns:
            bool: True if image created successfully
        """
        try:
            # Create a simple test image (colored rectangle)
            image = np.random.randint(0, 256, (224, 224, 3), dtype=np.uint8)
            
            # Add some patterns to make it more realistic
            cv2.rectangle(image, (50, 50), (174, 174), (255, 255, 255), 2)
            cv2.circle(image, (112, 112), 30, (0, 255, 0), -1)
            
            # Save image
            os.makedirs(os.path.dirname(image_path), exist_ok=True)
            cv2.imwrite(image_path, image)
            
            logger.info(f"✅ Created sample image: {image_path}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to create sample image: {e}")
            return False
    
    def publish_health_check(self):
        """Publish periodic health check event"""
        uptime_seconds = (datetime.utcnow() - self.start_time).total_seconds()
        
        self.publish_event('HealthCheck', {
            'device_id': self.device_id,
            'status': 'healthy',
            'model_loaded': self.model_loaded,
            'inference_count': self.inference_count,
            'error_count': self.error_count,
            'uptime_seconds': uptime_seconds,
            'error_rate': self.error_count / max(self.inference_count, 1)
        })
    
    def monitor_and_infer(self):
        """
        Main inference loop with monitoring
        """
        logger.info("🚀 Starting edge inference engine...")
        logger.info(f"   Device ID: {self.device_id}")
        logger.info(f"   Model path: {self.model_path}")
        logger.info(f"   Event bus: {self.event_bus_name}")
        logger.info(f"   Inference interval: {self.inference_interval} seconds")
        logger.info(f"   Confidence threshold: {self.confidence_threshold}")
        
        # Sample image path
        sample_image_path = '/tmp/sample_image.jpg'
        
        # Health check counter
        health_check_counter = 0
        health_check_interval = 300  # 5 minutes
        
        while not self.shutdown_requested:
            try:
                # Create sample image if it doesn't exist
                if not os.path.exists(sample_image_path):
                    self.create_sample_image(sample_image_path)
                
                # Run inference
                if os.path.exists(sample_image_path):
                    result = self.run_inference(sample_image_path)
                    if result:
                        logger.debug(f"✅ Inference completed: {result['prediction']}")
                else:
                    logger.warning("⚠️  No image available for inference")
                
                # Periodic health check
                health_check_counter += self.inference_interval
                if health_check_counter >= health_check_interval:
                    self.publish_health_check()
                    health_check_counter = 0
                
                # Wait for next inference cycle
                time.sleep(self.inference_interval)
                
            except KeyboardInterrupt:
                logger.info("🛑 Received keyboard interrupt, shutting down...")
                break
            except Exception as e:
                self.error_count += 1
                logger.error(f"❌ Error in inference loop: {e}")
                self.publish_event('SystemError', {
                    'error': str(e),
                    'device_id': self.device_id,
                    'error_type': 'inference_loop_error'
                })
                time.sleep(5)  # Brief pause before retrying
        
        # Shutdown event
        logger.info("🏁 Edge inference engine shutting down...")
        self.publish_event('SystemShutdown', {
            'device_id': self.device_id,
            'total_inferences': self.inference_count,
            'total_errors': self.error_count,
            'uptime_seconds': (datetime.utcnow() - self.start_time).total_seconds()
        })

def main():
    """Main entry point"""
    try:
        engine = EdgeInferenceEngine()
        engine.monitor_and_infer()
    except Exception as e:
        logger.error(f"❌ Fatal error in main: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()