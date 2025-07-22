#!/usr/bin/env python3
"""
Traffic Simulation Application for Smart City Digital Twin
Simulates traffic flow, congestion patterns, and optimization scenarios
using real-time IoT sensor data integration.
"""

import json
import time
import random
import math
import logging
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Tuple, Optional
import argparse
import sys
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class Vehicle:
    """Represents a vehicle in the simulation."""
    id: str
    position: Tuple[float, float]
    destination: Tuple[float, float]
    speed: float
    max_speed: float
    vehicle_type: str
    route: List[Tuple[float, float]]
    current_route_index: int = 0
    waiting_time: float = 0.0
    total_distance: float = 0.0

@dataclass
class TrafficLight:
    """Represents a traffic light in the simulation."""
    id: str
    position: Tuple[float, float]
    state: str  # 'green', 'yellow', 'red'
    cycle_time: float
    current_time: float
    intersection_id: str

@dataclass
class Sensor:
    """Represents a traffic sensor in the simulation."""
    id: str
    position: Tuple[float, float]
    sensor_type: str
    detection_radius: float
    last_reading: Dict
    reading_interval: float

@dataclass
class Road:
    """Represents a road segment in the simulation."""
    id: str
    start_pos: Tuple[float, float]
    end_pos: Tuple[float, float]
    lanes: int
    speed_limit: float
    capacity: int
    current_vehicles: int = 0

class TrafficSimulation:
    """Main traffic simulation class."""
    
    def __init__(self, config: Dict):
        """Initialize the traffic simulation."""
        self.config = config
        self.vehicles: Dict[str, Vehicle] = {}
        self.traffic_lights: Dict[str, TrafficLight] = {}
        self.sensors: Dict[str, Sensor] = {}
        self.roads: Dict[str, Road] = {}
        self.current_time = datetime.now()
        self.simulation_speed = float(config.get('SIMULATION_SPEED', 1.0))
        self.update_interval = int(config.get('UPDATE_INTERVAL', 30))
        self.max_vehicles = int(config.get('MAX_VEHICLES', 10000))
        self.grid_size = 5000  # 5km x 5km simulation area
        self.running = True
        
        # Performance metrics
        self.metrics = {
            'vehicles_spawned': 0,
            'vehicles_completed': 0,
            'total_waiting_time': 0.0,
            'average_speed': 0.0,
            'congestion_level': 0.0,
            'throughput': 0.0
        }
        
        logger.info(f"Traffic simulation initialized with config: {config}")
    
    def initialize(self):
        """Initialize simulation state and entities."""
        logger.info("Initializing traffic simulation...")
        
        # Create road network
        self.create_road_network()
        
        # Create traffic lights
        self.create_traffic_lights()
        
        # Create traffic sensors
        self.create_traffic_sensors()
        
        # Spawn initial vehicles
        self.spawn_initial_vehicles()
        
        logger.info(f"Simulation initialized with {len(self.roads)} roads, "
                   f"{len(self.traffic_lights)} traffic lights, "
                   f"{len(self.sensors)} sensors, and "
                   f"{len(self.vehicles)} initial vehicles")
    
    def create_road_network(self):
        """Create a realistic road network for the city."""
        # Create main arterials (north-south and east-west)
        arterials = [
            # North-South arterials
            ("ns_arterial_1", (1000, 0), (1000, 5000), 4, 60, 2000),
            ("ns_arterial_2", (2500, 0), (2500, 5000), 4, 60, 2000),
            ("ns_arterial_3", (4000, 0), (4000, 5000), 4, 60, 2000),
            
            # East-West arterials
            ("ew_arterial_1", (0, 1000), (5000, 1000), 4, 60, 2000),
            ("ew_arterial_2", (0, 2500), (5000, 2500), 4, 60, 2000),
            ("ew_arterial_3", (0, 4000), (5000, 4000), 4, 60, 2000),
        ]
        
        for road_id, start, end, lanes, speed_limit, capacity in arterials:
            self.roads[road_id] = Road(road_id, start, end, lanes, speed_limit, capacity)
        
        # Create secondary roads (grid pattern)
        for i in range(0, 5001, 500):  # Every 500m
            if i not in [1000, 2500, 4000]:  # Skip arterials
                # North-South roads
                road_id = f"ns_secondary_{i}"
                self.roads[road_id] = Road(road_id, (i, 0), (i, 5000), 2, 40, 800)
                
        for i in range(0, 5001, 500):  # Every 500m
            if i not in [1000, 2500, 4000]:  # Skip arterials
                # East-West roads
                road_id = f"ew_secondary_{i}"
                self.roads[road_id] = Road(road_id, (0, i), (5000, i), 2, 40, 800)
        
        logger.info(f"Created {len(self.roads)} road segments")
    
    def create_traffic_lights(self):
        """Create traffic lights at major intersections."""
        # Major intersections (arterials)
        arterial_intersections = [
            (1000, 1000), (1000, 2500), (1000, 4000),
            (2500, 1000), (2500, 2500), (2500, 4000),
            (4000, 1000), (4000, 2500), (4000, 4000)
        ]
        
        for i, (x, y) in enumerate(arterial_intersections):
            light_id = f"traffic_light_{i+1:03d}"
            self.traffic_lights[light_id] = TrafficLight(
                id=light_id,
                position=(x, y),
                state='green',
                cycle_time=120.0,  # 2-minute cycle
                current_time=random.uniform(0, 120),
                intersection_id=f"intersection_{i+1:03d}"
            )
        
        # Secondary intersections (shorter cycles)
        secondary_positions = [(x, y) for x in range(500, 5000, 1000) 
                             for y in range(500, 5000, 1000)
                             if (x, y) not in arterial_intersections]
        
        for i, (x, y) in enumerate(secondary_positions[:20]):  # Limit to 20 secondary lights
            light_id = f"traffic_light_{len(arterial_intersections)+i+1:03d}"
            self.traffic_lights[light_id] = TrafficLight(
                id=light_id,
                position=(x, y),
                state='green',
                cycle_time=60.0,  # 1-minute cycle
                current_time=random.uniform(0, 60),
                intersection_id=f"intersection_{len(arterial_intersections)+i+1:03d}"
            )
        
        logger.info(f"Created {len(self.traffic_lights)} traffic lights")
    
    def create_traffic_sensors(self):
        """Create traffic sensors throughout the city."""
        # Place sensors on major roads
        sensor_positions = []
        
        # Sensors on arterials
        for road_id, road in self.roads.items():
            if 'arterial' in road_id:
                # Place sensors every 1km along arterials
                start_x, start_y = road.start_pos
                end_x, end_y = road.end_pos
                
                if start_x == end_x:  # North-South road
                    for y in range(int(min(start_y, end_y)), int(max(start_y, end_y)), 1000):
                        sensor_positions.append((start_x, y))
                else:  # East-West road
                    for x in range(int(min(start_x, end_x)), int(max(start_x, end_x)), 1000):
                        sensor_positions.append((x, start_y))
        
        # Create sensor objects
        for i, (x, y) in enumerate(sensor_positions):
            sensor_id = f"traffic_sensor_{i+1:03d}"
            self.sensors[sensor_id] = Sensor(
                id=sensor_id,
                position=(x, y),
                sensor_type='traffic',
                detection_radius=100.0,  # 100m detection radius
                last_reading={},
                reading_interval=30.0  # 30-second intervals
            )
        
        logger.info(f"Created {len(self.sensors)} traffic sensors")
    
    def spawn_initial_vehicles(self):
        """Spawn initial vehicles in the simulation."""
        initial_count = min(self.max_vehicles // 4, 100)  # Start with 25% capacity or 100 vehicles
        
        for i in range(initial_count):
            vehicle = self.create_random_vehicle(f"vehicle_{i+1:06d}")
            if vehicle:
                self.vehicles[vehicle.id] = vehicle
                self.metrics['vehicles_spawned'] += 1
        
        logger.info(f"Spawned {len(self.vehicles)} initial vehicles")
    
    def create_random_vehicle(self, vehicle_id: str) -> Optional[Vehicle]:
        """Create a vehicle with random attributes."""
        # Random spawn position (edge of simulation area)
        spawn_edge = random.choice(['north', 'south', 'east', 'west'])
        
        if spawn_edge == 'north':
            start_pos = (random.uniform(0, self.grid_size), 0)
            dest_pos = (random.uniform(0, self.grid_size), random.uniform(self.grid_size/2, self.grid_size))
        elif spawn_edge == 'south':
            start_pos = (random.uniform(0, self.grid_size), self.grid_size)
            dest_pos = (random.uniform(0, self.grid_size), random.uniform(0, self.grid_size/2))
        elif spawn_edge == 'east':
            start_pos = (self.grid_size, random.uniform(0, self.grid_size))
            dest_pos = (random.uniform(0, self.grid_size/2), random.uniform(0, self.grid_size))
        else:  # west
            start_pos = (0, random.uniform(0, self.grid_size))
            dest_pos = (random.uniform(self.grid_size/2, self.grid_size), random.uniform(0, self.grid_size))
        
        # Vehicle types with different characteristics
        vehicle_types = [
            ('car', 50, 0.7),
            ('truck', 30, 0.15),
            ('bus', 40, 0.1),
            ('motorcycle', 70, 0.05)
        ]
        
        vehicle_type, max_speed, probability = random.choices(
            vehicle_types, 
            weights=[p for _, _, p in vehicle_types]
        )[0]
        
        # Generate simple route (direct path with some randomness)
        route = self.generate_route(start_pos, dest_pos)
        
        return Vehicle(
            id=vehicle_id,
            position=start_pos,
            destination=dest_pos,
            speed=0.0,
            max_speed=max_speed,
            vehicle_type=vehicle_type,
            route=route,
            current_route_index=0
        )
    
    def generate_route(self, start: Tuple[float, float], dest: Tuple[float, float]) -> List[Tuple[float, float]]:
        """Generate a simple route between two points."""
        # For simplicity, create a route with a few waypoints
        route = [start]
        
        # Add intermediate waypoints
        num_waypoints = random.randint(2, 5)
        for _ in range(num_waypoints):
            # Interpolate between start and destination with some randomness
            t = random.uniform(0.2, 0.8)
            x = start[0] + t * (dest[0] - start[0]) + random.uniform(-500, 500)
            y = start[1] + t * (dest[1] - start[1]) + random.uniform(-500, 500)
            
            # Clamp to simulation bounds
            x = max(0, min(self.grid_size, x))
            y = max(0, min(self.grid_size, y))
            
            route.append((x, y))
        
        route.append(dest)
        return route
    
    def update_vehicles(self, dt: float):
        """Update all vehicle positions and states."""
        vehicles_to_remove = []
        
        for vehicle in self.vehicles.values():
            # Move vehicle along route
            if vehicle.current_route_index < len(vehicle.route) - 1:
                current_pos = vehicle.route[vehicle.current_route_index]
                next_pos = vehicle.route[vehicle.current_route_index + 1]
                
                # Calculate direction and distance
                dx = next_pos[0] - current_pos[0]
                dy = next_pos[1] - current_pos[1]
                distance = math.sqrt(dx*dx + dy*dy)
                
                if distance > 0:
                    # Normalize direction
                    dx /= distance
                    dy /= distance
                    
                    # Calculate speed based on conditions
                    target_speed = self.calculate_vehicle_speed(vehicle)
                    
                    # Move vehicle
                    move_distance = target_speed * dt
                    vehicle.position = (
                        vehicle.position[0] + dx * move_distance,
                        vehicle.position[1] + dy * move_distance
                    )
                    vehicle.speed = target_speed
                    vehicle.total_distance += move_distance
                    
                    # Check if reached next waypoint
                    dist_to_next = math.sqrt(
                        (vehicle.position[0] - next_pos[0])**2 + 
                        (vehicle.position[1] - next_pos[1])**2
                    )
                    
                    if dist_to_next < 50:  # Within 50m of waypoint
                        vehicle.current_route_index += 1
            else:
                # Vehicle reached destination
                vehicles_to_remove.append(vehicle.id)
                self.metrics['vehicles_completed'] += 1
        
        # Remove completed vehicles
        for vehicle_id in vehicles_to_remove:
            del self.vehicles[vehicle_id]
        
        # Spawn new vehicles to maintain population
        self.spawn_new_vehicles()
    
    def calculate_vehicle_speed(self, vehicle: Vehicle) -> float:
        """Calculate vehicle speed based on traffic conditions."""
        base_speed = vehicle.max_speed
        
        # Check for nearby traffic lights
        for light in self.traffic_lights.values():
            dist_to_light = math.sqrt(
                (vehicle.position[0] - light.position[0])**2 + 
                (vehicle.position[1] - light.position[1])**2
            )
            
            if dist_to_light < 100 and light.state == 'red':
                base_speed *= 0.1  # Nearly stop for red lights
            elif dist_to_light < 150 and light.state == 'yellow':
                base_speed *= 0.7  # Slow down for yellow lights
        
        # Check for congestion (simplified)
        nearby_vehicles = sum(1 for v in self.vehicles.values() 
                            if v.id != vehicle.id and 
                            math.sqrt((v.position[0] - vehicle.position[0])**2 + 
                                    (v.position[1] - vehicle.position[1])**2) < 50)
        
        if nearby_vehicles > 3:
            base_speed *= 0.5  # Reduce speed in congestion
        elif nearby_vehicles > 1:
            base_speed *= 0.8  # Slight reduction for moderate traffic
        
        return max(5, base_speed)  # Minimum speed of 5 km/h
    
    def spawn_new_vehicles(self):
        """Spawn new vehicles to maintain simulation population."""
        if len(self.vehicles) < self.max_vehicles * 0.8:  # Maintain 80% capacity
            num_to_spawn = min(5, self.max_vehicles - len(self.vehicles))  # Spawn up to 5 at once
            
            for i in range(num_to_spawn):
                vehicle_id = f"vehicle_{self.metrics['vehicles_spawned'] + 1:06d}"
                vehicle = self.create_random_vehicle(vehicle_id)
                if vehicle:
                    self.vehicles[vehicle.id] = vehicle
                    self.metrics['vehicles_spawned'] += 1
    
    def update_traffic_lights(self, dt: float):
        """Update traffic light states."""
        for light in self.traffic_lights.values():
            light.current_time += dt
            
            # Simple traffic light cycle
            cycle_progress = (light.current_time % light.cycle_time) / light.cycle_time
            
            if cycle_progress < 0.6:
                light.state = 'green'
            elif cycle_progress < 0.7:
                light.state = 'yellow'
            else:
                light.state = 'red'
    
    def update_sensors(self, dt: float):
        """Update sensor readings and generate IoT data."""
        current_time = self.current_time.isoformat()
        
        for sensor in self.sensors.values():
            # Count vehicles within detection radius
            vehicles_detected = []
            speeds = []
            
            for vehicle in self.vehicles.values():
                dist = math.sqrt(
                    (vehicle.position[0] - sensor.position[0])**2 + 
                    (vehicle.position[1] - sensor.position[1])**2
                )
                
                if dist <= sensor.detection_radius:
                    vehicles_detected.append(vehicle)
                    speeds.append(vehicle.speed)
            
            # Generate sensor reading
            reading = {
                'sensor_id': sensor.id,
                'sensor_type': 'traffic',
                'timestamp': current_time,
                'location': {
                    'lat': sensor.position[1] / 111000,  # Rough conversion to lat/lon
                    'lon': sensor.position[0] / 111000,
                    'x': sensor.position[0],
                    'y': sensor.position[1]
                },
                'data': {
                    'vehicle_count': len(vehicles_detected),
                    'average_speed': sum(speeds) / len(speeds) if speeds else 0,
                    'max_speed': max(speeds) if speeds else 0,
                    'min_speed': min(speeds) if speeds else 0,
                    'congestion_level': min(100, len(vehicles_detected) * 10)  # Simple congestion metric
                }
            }
            
            sensor.last_reading = reading
            
            # In a real implementation, this would be sent to IoT Core
            logger.debug(f"Sensor {sensor.id}: {reading['data']}")
    
    def calculate_metrics(self):
        """Calculate simulation performance metrics."""
        if not self.vehicles:
            return
        
        # Calculate average speed
        total_speed = sum(v.speed for v in self.vehicles.values())
        self.metrics['average_speed'] = total_speed / len(self.vehicles)
        
        # Calculate overall congestion level
        total_congestion = 0
        for sensor in self.sensors.values():
            if sensor.last_reading:
                total_congestion += sensor.last_reading['data'].get('congestion_level', 0)
        
        self.metrics['congestion_level'] = total_congestion / len(self.sensors) if self.sensors else 0
        
        # Calculate throughput (vehicles per hour)
        simulation_hours = (datetime.now() - self.current_time).total_seconds() / 3600
        if simulation_hours > 0:
            self.metrics['throughput'] = self.metrics['vehicles_completed'] / simulation_hours
    
    def run_simulation_step(self, dt: float):
        """Run one simulation step."""
        self.current_time += timedelta(seconds=dt)
        
        # Update simulation entities
        self.update_vehicles(dt)
        self.update_traffic_lights(dt)
        self.update_sensors(dt)
        
        # Calculate performance metrics
        self.calculate_metrics()
    
    def get_simulation_state(self) -> Dict:
        """Get current simulation state for output."""
        return {
            'timestamp': self.current_time.isoformat(),
            'vehicles': {
                'count': len(self.vehicles),
                'positions': [(v.position[0], v.position[1]) for v in list(self.vehicles.values())[:100]]  # Limit output
            },
            'traffic_lights': [
                {
                    'id': light.id,
                    'position': light.position,
                    'state': light.state
                } for light in self.traffic_lights.values()
            ],
            'sensors': [
                {
                    'id': sensor.id,
                    'position': sensor.position,
                    'last_reading': sensor.last_reading
                } for sensor in self.sensors.values()
            ],
            'metrics': self.metrics
        }
    
    def run(self):
        """Main simulation loop."""
        self.initialize()
        
        last_update = time.time()
        last_output = time.time()
        
        logger.info("Starting traffic simulation main loop...")
        
        try:
            while self.running:
                current = time.time()
                dt = (current - last_update) * self.simulation_speed
                
                if dt >= 1.0:  # Update every second (simulation time)
                    self.run_simulation_step(dt)
                    last_update = current
                
                # Output simulation state every update interval
                if current - last_output >= self.update_interval:
                    state = self.get_simulation_state()
                    print(json.dumps(state, indent=2))
                    last_output = current
                
                # Small sleep to prevent excessive CPU usage
                time.sleep(0.1)
                
        except KeyboardInterrupt:
            logger.info("Simulation interrupted by user")
        except Exception as e:
            logger.error(f"Simulation error: {str(e)}")
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Shutdown the simulation gracefully."""
        logger.info("Shutting down traffic simulation...")
        self.running = False
        
        # Output final metrics
        final_metrics = {
            'simulation_summary': {
                'total_runtime': (datetime.now() - self.current_time).total_seconds(),
                'vehicles_spawned': self.metrics['vehicles_spawned'],
                'vehicles_completed': self.metrics['vehicles_completed'],
                'final_vehicle_count': len(self.vehicles),
                'average_speed': self.metrics['average_speed'],
                'final_congestion': self.metrics['congestion_level'],
                'throughput': self.metrics['throughput']
            }
        }
        
        print(json.dumps(final_metrics, indent=2))
        logger.info("Traffic simulation shutdown complete")

def main():
    """Main entry point for the simulation."""
    parser = argparse.ArgumentParser(description='Smart City Traffic Simulation')
    parser.add_argument('--config', type=str, help='Configuration file path')
    parser.add_argument('--simulation-speed', type=float, default=1.0, help='Simulation speed multiplier')
    parser.add_argument('--update-interval', type=int, default=30, help='Update interval in seconds')
    parser.add_argument('--max-vehicles', type=int, default=1000, help='Maximum number of vehicles')
    
    args = parser.parse_args()
    
    # Build configuration from environment and arguments
    config = {
        'SIMULATION_SPEED': str(args.simulation_speed),
        'UPDATE_INTERVAL': str(args.update_interval),
        'MAX_VEHICLES': str(args.max_vehicles)
    }
    
    # Override with environment variables
    for key in config.keys():
        if key in os.environ:
            config[key] = os.environ[key]
    
    # Create and run simulation
    simulation = TrafficSimulation(config)
    simulation.run()

if __name__ == "__main__":
    main()