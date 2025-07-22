#!/usr/bin/env python3
"""
TPU v6e training script optimized for large-scale ML training pipelines.
This script leverages JAX/Flax for high-performance distributed training.
"""

import os
import sys
import time
import logging
from typing import Dict, Any, Tuple, Optional

import jax
import jax.numpy as jnp
from jax import random, grad, jit, vmap, pmap
import flax.linen as nn
import optax
import tensorflow as tf
import numpy as np
from google.cloud import storage
from google.cloud import monitoring_v3

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/training.log')
    ]
)
logger = logging.getLogger(__name__)

class TransformerModel(nn.Module):
    """
    Transformer model optimized for TPU v6e training.
    Implements efficient attention mechanisms and memory usage patterns.
    """
    vocab_size: int
    hidden_dim: int = 768
    num_heads: int = 12
    num_layers: int = 12
    max_seq_length: int = 2048
    dropout_rate: float = 0.1
    
    @nn.compact
    def __call__(self, x, training=True):
        # Token and position embeddings
        seq_len = x.shape[-1]
        
        # Token embeddings
        embed = nn.Embed(self.vocab_size, self.hidden_dim)
        x = embed(x)
        
        # Position embeddings
        pos_embed = nn.Embed(self.max_seq_length, self.hidden_dim)
        pos_ids = jnp.arange(seq_len)[None, :]
        x = x + pos_embed(pos_ids)
        
        # Dropout
        x = nn.Dropout(rate=self.dropout_rate, deterministic=not training)(x)
        
        # Transformer layers
        for layer_idx in range(self.num_layers):
            # Multi-head attention with residual connection
            attn_out = nn.MultiHeadDotProductAttention(
                num_heads=self.num_heads,
                dropout_rate=self.dropout_rate,
                deterministic=not training
            )(x, x)
            
            x = nn.LayerNorm()(x + attn_out)
            
            # Feed-forward network with residual connection
            ff_out = nn.Dense(self.hidden_dim * 4)(x)
            ff_out = nn.gelu(ff_out)
            ff_out = nn.Dense(self.hidden_dim)(ff_out)
            ff_out = nn.Dropout(rate=self.dropout_rate, deterministic=not training)(ff_out)
            
            x = nn.LayerNorm()(x + ff_out)
        
        # Output projection
        return nn.Dense(self.vocab_size)(x)

class TPUTrainingPipeline:
    """Training pipeline optimized for TPU v6e infrastructure."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.bucket_name = config.get('bucket_name', '${bucket_name}')
        self.project_id = config.get('project_id', '${project_id}')
        
        # Initialize model and optimizer
        self.model = TransformerModel(
            vocab_size=config.get('vocab_size', 50000),
            hidden_dim=config.get('hidden_dim', 768),
            num_heads=config.get('num_heads', 12),
            num_layers=config.get('num_layers', 12)
        )
        
        # Optimizer with learning rate scheduling
        self.learning_rate_schedule = optax.warmup_cosine_decay_schedule(
            init_value=0.0,
            peak_value=config.get('learning_rate', 1e-4),
            warmup_steps=config.get('warmup_steps', 1000),
            decay_steps=config.get('decay_steps', 100000),
            end_value=1e-6
        )
        
        self.optimizer = optax.adamw(
            learning_rate=self.learning_rate_schedule,
            weight_decay=config.get('weight_decay', 0.01)
        )
        
        # Initialize Cloud Monitoring client
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        logger.info(f"TPU Training Pipeline initialized")
        logger.info(f"JAX devices: {jax.devices()}")
        logger.info(f"JAX device count: {jax.device_count()}")
        logger.info(f"JAX local devices: {jax.local_devices()}")
    
    def create_train_step(self):
        """Create JIT-compiled training step function."""
        
        def train_step(params, opt_state, batch, step):
            """Single training step with gradient computation."""
            
            def loss_fn(params):
                # Forward pass
                logits = self.model.apply(params, batch['input_ids'], training=True)
                
                # Compute cross-entropy loss
                loss = optax.softmax_cross_entropy_with_integer_labels(
                    logits, batch['labels']
                ).mean()
                
                return loss, logits
            
            # Compute gradients
            (loss, logits), grads = jax.value_and_grad(loss_fn, has_aux=True)(params)
            
            # Apply optimizer updates
            updates, opt_state = self.optimizer.update(grads, opt_state, params)
            params = optax.apply_updates(params, updates)
            
            # Compute metrics
            accuracy = jnp.mean(jnp.argmax(logits, axis=-1) == batch['labels'])
            
            metrics = {
                'loss': loss,
                'accuracy': accuracy,
                'learning_rate': self.learning_rate_schedule(step),
                'grad_norm': optax.global_norm(grads)
            }
            
            return params, opt_state, metrics
        
        # Parallelize across TPU cores
        return jax.pmap(train_step, axis_name='devices')
    
    def load_data(self, data_path: str) -> tf.data.Dataset:
        """Load and prepare training data from Cloud Storage."""
        logger.info(f"Loading training data from {data_path}")
        
        try:
            # Read Parquet files from Cloud Storage
            dataset = tf.data.Dataset.list_files(f"{data_path}*.parquet")
            
            def parse_parquet(filename):
                # Parse parquet files using TensorFlow
                return tf.data.experimental.make_parquet_dataset(
                    filename,
                    batch_size=1,
                    num_parallel_reads=tf.data.AUTOTUNE
                )
            
            dataset = dataset.interleave(
                parse_parquet,
                cycle_length=tf.data.AUTOTUNE,
                num_parallel_calls=tf.data.AUTOTUNE
            )
            
            # Prepare data for model training
            def prepare_batch(example):
                text = example['text']
                
                # Simple tokenization (replace with proper tokenizer)
                tokens = tf.strings.to_hash_bucket_fast(text, 50000)
                
                # Create input_ids and labels for causal language modeling
                input_ids = tokens[:-1]
                labels = tokens[1:]
                
                return {
                    'input_ids': input_ids,
                    'labels': labels
                }
            
            dataset = dataset.map(
                prepare_batch,
                num_parallel_calls=tf.data.AUTOTUNE
            ).batch(
                self.config.get('batch_size', 32)
            ).prefetch(tf.data.AUTOTUNE)
            
            logger.info("Training data loaded successfully")
            return dataset
            
        except Exception as e:
            logger.error(f"Error loading training data: {str(e)}")
            raise
    
    def save_checkpoint(self, params, step: int):
        """Save training checkpoint to Cloud Storage."""
        try:
            checkpoint_path = f"gs://{self.bucket_name}/checkpoints/step_{step}"
            
            # Convert JAX parameters to numpy for saving
            np_params = jax.tree_map(lambda x: np.array(x), params)
            
            # Save using TensorFlow's checkpoint format
            tf.saved_model.save(np_params, checkpoint_path)
            
            logger.info(f"Checkpoint saved to {checkpoint_path}")
            
        except Exception as e:
            logger.error(f"Error saving checkpoint: {str(e)}")
    
    def log_metrics(self, metrics: Dict[str, float], step: int):
        """Log training metrics to Cloud Monitoring."""
        try:
            project_name = f"projects/{self.project_id}"
            
            # Create time series data
            now = time.time()
            seconds = int(now)
            nanos = int((now - seconds) * 10 ** 9)
            timestamp = {
                'seconds': seconds,
                'nanos': nanos
            }
            
            # Log metrics to Cloud Monitoring
            for metric_name, value in metrics.items():
                series = monitoring_v3.TimeSeries()
                series.metric.type = f"custom.googleapis.com/ml_training/{metric_name}"
                series.resource.type = "tpu_worker"
                series.resource.labels['project_id'] = self.project_id
                
                point = monitoring_v3.Point()
                point.value.double_value = float(value)
                point.interval.end_time = timestamp
                series.points = [point]
                
                self.monitoring_client.create_time_series(
                    name=project_name,
                    time_series=[series]
                )
            
        except Exception as e:
            logger.warning(f"Error logging metrics: {str(e)}")
    
    def train(self):
        """Execute the complete training pipeline."""
        logger.info("Starting TPU v6e training pipeline")
        
        try:
            # Initialize model parameters
            key = random.PRNGKey(42)
            dummy_input = jnp.ones((1, 512), dtype=jnp.int32)
            params = self.model.init(key, dummy_input, training=True)
            
            # Initialize optimizer state
            opt_state = self.optimizer.init(params)
            
            # Replicate parameters across TPU cores
            params = jax.tree_map(lambda x: jnp.array([x] * jax.device_count()), params)
            opt_state = jax.tree_map(lambda x: jnp.array([x] * jax.device_count()), opt_state)
            
            # Create training step function
            train_step = self.create_train_step()
            
            # Load training data
            data_path = f"gs://{self.bucket_name}/processed-data/"
            dataset = self.load_data(data_path)
            
            # Training loop
            step = 0
            total_steps = self.config.get('total_steps', 10000)
            log_interval = self.config.get('log_interval', 100)
            checkpoint_interval = self.config.get('checkpoint_interval', 1000)
            
            logger.info(f"Starting training for {total_steps} steps")
            
            for batch in dataset.take(total_steps):
                # Convert TensorFlow tensors to JAX arrays
                jax_batch = {
                    'input_ids': jnp.array(batch['input_ids'].numpy()),
                    'labels': jnp.array(batch['labels'].numpy())
                }
                
                # Shard batch across TPU cores
                sharded_batch = jax.tree_map(
                    lambda x: x.reshape((jax.device_count(), -1) + x.shape[1:]),
                    jax_batch
                )
                
                # Execute training step
                params, opt_state, metrics = train_step(
                    params, opt_state, sharded_batch, step
                )
                
                # Aggregate metrics from all devices
                metrics = jax.tree_map(lambda x: jnp.mean(x), metrics)
                
                # Logging
                if step % log_interval == 0:
                    logger.info(f"Step {step}: Loss={metrics['loss']:.4f}, "
                              f"Accuracy={metrics['accuracy']:.4f}, "
                              f"LR={metrics['learning_rate']:.2e}")
                    
                    # Log to Cloud Monitoring
                    self.log_metrics(metrics, step)
                
                # Checkpointing
                if step % checkpoint_interval == 0 and step > 0:
                    # Get parameters from first device for saving
                    save_params = jax.tree_map(lambda x: x[0], params)
                    self.save_checkpoint(save_params, step)
                
                step += 1
            
            # Save final model
            final_params = jax.tree_map(lambda x: x[0], params)
            model_path = f"gs://{self.bucket_name}/models/final_model"
            tf.saved_model.save(final_params, model_path)
            
            logger.info("Training completed successfully")
            logger.info(f"Final model saved to {model_path}")
            
        except Exception as e:
            logger.error(f"Training failed: {str(e)}")
            raise

def main():
    """Main training function."""
    logger.info("TPU v6e Training Script Starting")
    
    # Training configuration
    config = {
        'bucket_name': os.environ.get('BUCKET_NAME', '${bucket_name}'),
        'project_id': os.environ.get('PROJECT_ID', '${project_id}'),
        'vocab_size': 50000,
        'hidden_dim': 768,
        'num_heads': 12,
        'num_layers': 12,
        'learning_rate': 1e-4,
        'batch_size': 32,
        'total_steps': 10000,
        'warmup_steps': 1000,
        'decay_steps': 8000,
        'weight_decay': 0.01,
        'log_interval': 100,
        'checkpoint_interval': 1000
    }
    
    try:
        # Initialize and run training pipeline
        pipeline = TPUTrainingPipeline(config)
        pipeline.train()
        
        logger.info("Training pipeline completed successfully")
        
    except Exception as e:
        logger.error(f"Training pipeline failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()