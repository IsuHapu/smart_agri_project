"""
Enhanced Sri Lankan Agriculture AI Analysis Server
Designed for Google Colab deployment with detailed forecasting and predictions
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import json
import math
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import warnings
from pyngrok import ngrok, conf

warnings.filterwarnings('ignore')

app = Flask(__name__)
CORS(app)
# Set your Ngrok auth token
NGROK_AUTH_TOKEN = "2uuIt6mC2IA9jQvCtH93Su9yJzW_6Ljzw3HJHLWDiYPVNAgkU"
conf.get_default().auth_token = NGROK_AUTH_TOKEN

class NumpyEncoder(json.JSONEncoder):
    """Custom JSON encoder for numpy data types"""
    def default(self, obj):
        if isinstance(obj, np.integer):
            return int(obj)
        elif isinstance(obj, np.floating):
            return float(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        elif isinstance(obj, np.bool_):
            return bool(obj)
        elif isinstance(obj, (datetime, np.datetime64)):
            return obj.isoformat()
        return super(NumpyEncoder, self).default(obj)

class SriLankanAgricultureAI:
    def __init__(self):
        self.models = {}
        self.scalers = {}
        self.sri_lanka_data = self._load_sri_lanka_agriculture_data()
        self.monsoon_patterns = self._get_monsoon_patterns()
        self.crop_calendars = self._get_crop_calendars()
        self.setup_models()
    
    def _load_sri_lanka_agriculture_data(self):
        """Load Sri Lankan specific agriculture data and patterns"""
        return {
            'climate_zones': {
                'Wet Zone': {
                    'rainfall_mm': [200, 300, 400, 350, 180, 120, 100, 120, 200, 350, 400, 250],
                    'temperature_range': [24, 30],
                    'humidity_range': [75, 85],
                    'optimal_crops': ['Rice', 'Tea', 'Rubber', 'Coconut', 'Vegetables']
                },
                'Dry Zone': {
                    'rainfall_mm': [50, 80, 120, 150, 80, 40, 30, 50, 120, 200, 180, 100],
                    'temperature_range': [26, 35],
                    'humidity_range': [60, 75],
                    'optimal_crops': ['Rice', 'Maize', 'Sesame', 'Cotton', 'Chili']
                },
                'Intermediate Zone': {
                    'rainfall_mm': [120, 180, 250, 220, 140, 80, 60, 80, 160, 280, 300, 180],
                    'temperature_range': [22, 28],
                    'humidity_range': [70, 80],
                    'optimal_crops': ['Rice', 'Vegetables', 'Fruits', 'Spices', 'Tea']
                }
            },
            'crop_varieties': {
                'Rice': {
                    'BG 352': {'yield_per_acre': 4.5, 'growth_days': 105, 'water_requirement': 'High'},
                    'AT 362': {'yield_per_acre': 4.2, 'growth_days': 110, 'water_requirement': 'Medium'},
                    'BG 300': {'yield_per_acre': 4.0, 'growth_days': 95, 'water_requirement': 'High'},
                    'H-4': {'yield_per_acre': 3.8, 'growth_days': 120, 'water_requirement': 'Medium'}
                },
                'Tea': {
                    'TRI 2025': {'yield_per_acre': 1500, 'growth_years': 3, 'elevation': 'High'},
                    'TRI 2043': {'yield_per_acre': 1400, 'growth_years': 3, 'elevation': 'Medium'},
                    'TRI 3055': {'yield_per_acre': 1600, 'growth_years': 4, 'elevation': 'High'}
                },
                'Coconut': {
                    'Dwarf': {'nuts_per_tree': 180, 'growth_years': 5, 'lifespan': 80},
                    'Tall': {'nuts_per_tree': 120, 'growth_years': 8, 'lifespan': 100}
                }
            },
            'soil_types': {
                'Red Earth': {'pH_range': [5.5, 6.5], 'fertility': 'Medium', 'drainage': 'Good'},
                'Alluvial': {'pH_range': [6.0, 7.5], 'fertility': 'High', 'drainage': 'Medium'},
                'Laterite': {'pH_range': [5.0, 6.0], 'fertility': 'Low', 'drainage': 'Excellent'},
                'Peat': {'pH_range': [4.5, 5.5], 'fertility': 'High', 'drainage': 'Poor'},
                'Clay': {'pH_range': [6.5, 7.5], 'fertility': 'Medium', 'drainage': 'Poor'}
            }
        }
    
    def _get_monsoon_patterns(self):
        """Sri Lankan monsoon patterns and timing"""
        return {
            'Southwest Monsoon': {
                'months': [5, 6, 7, 8, 9],
                'peak_rainfall': [6, 7],
                'affected_zones': ['Wet Zone', 'Intermediate Zone']
            },
            'Northeast Monsoon': {
                'months': [10, 11, 12, 1, 2],
                'peak_rainfall': [11, 12],
                'affected_zones': ['Dry Zone', 'Eastern Province']
            },
            'Inter Monsoon': {
                'months': [3, 4, 9, 10],
                'characteristics': 'Variable rainfall, thunderstorms'
            }
        }
    
    def _get_crop_calendars(self):
        """Sri Lankan crop planting and harvesting calendars"""
        return {
            'Rice': {
                'Yala': {'planting': [4, 5, 6], 'harvesting': [8, 9, 10]},
                'Maha': {'planting': [10, 11, 12], 'harvesting': [2, 3, 4]}
            },
            'Tea': {
                'plucking_cycle': 7,  # days
                'peak_months': [3, 4, 5, 9, 10, 11]
            },
            'Vegetables': {
                'year_round': ['Tomato', 'Cabbage', 'Carrot', 'Beans'],
                'seasonal': {
                    'dry_season': ['Onion', 'Chili', 'Brinjal'],
                    'wet_season': ['Okra', 'Cucumber', 'Pumpkin']
                }
            }
        }
    
    def setup_models(self):
        """Initialize ML models for predictions"""
        self.models['yield_prediction'] = RandomForestRegressor(n_estimators=100, random_state=42)
        self.models['disease_risk'] = GradientBoostingRegressor(n_estimators=50, random_state=42)
        self.models['weather_forecast'] = RandomForestRegressor(n_estimators=80, random_state=42)
        
        # Setup scalers
        for model_name in self.models.keys():
            self.scalers[model_name] = StandardScaler()
    
    def analyze_farm_data(self, sensor_data, farm_config, nodes):
        """Comprehensive Sri Lankan farm analysis"""
        current_time = datetime.now()
        
        # Basic sensor analysis
        sensor_analysis = self._analyze_sensor_data(sensor_data)
        
        # Sri Lankan specific analysis
        climate_analysis = self._analyze_climate_zone(farm_config, sensor_analysis)
        monsoon_analysis = self._analyze_monsoon_impact(current_time, farm_config)
        crop_analysis = self._analyze_crop_specific(farm_config, sensor_analysis)
        
        # Predictions and forecasting
        yield_prediction = self._predict_yield(farm_config, sensor_analysis)
        harvest_forecast = self._forecast_harvest(farm_config, current_time)
        weather_forecast = self._forecast_weather(farm_config, sensor_analysis)
        disease_risk = self._assess_disease_risk(sensor_analysis, farm_config)
        
        # Recommendations
        recommendations = self._generate_sri_lankan_recommendations(
            farm_config, sensor_analysis, climate_analysis, monsoon_analysis
        )
        
        return {
            'analysis_timestamp': current_time.isoformat(),
            'farm_location': farm_config.get('location', 'Unknown'),
            'climate_zone': farm_config.get('climateZone', 'Unknown'),
            'current_conditions': sensor_analysis,
            'climate_analysis': climate_analysis,
            'monsoon_analysis': monsoon_analysis,
            'crop_analysis': crop_analysis,
            'yield_prediction': yield_prediction,
            'harvest_forecast': harvest_forecast,
            'weather_forecast': weather_forecast,
            'disease_risk': disease_risk,
            'recommendations': recommendations,
            'alerts': self._generate_alerts(sensor_analysis, disease_risk, monsoon_analysis),
            'country_context': 'Sri Lanka'
        }
    
    def _analyze_sensor_data(self, sensor_data):
        """Analyze current sensor readings"""
        if not sensor_data:
            return {'status': 'No sensor data available'}
        
        # Calculate averages and trends
        temperatures = [d['temperature'] for d in sensor_data if d.get('temperature') is not None]
        humidity = [d['humidity'] for d in sensor_data if d.get('humidity') is not None]
        soil_moisture = [d['soil_moisture'] for d in sensor_data if d.get('soil_moisture') is not None]
        
        return {
            'average_temperature': float(np.mean(temperatures)) if temperatures else 0.0,
            'average_humidity': float(np.mean(humidity)) if humidity else 0.0,
            'average_soil_moisture': float(np.mean(soil_moisture)) if soil_moisture else 0.0,
            'temperature_range': [float(np.min(temperatures)), float(np.max(temperatures))] if temperatures else [0.0, 0.0],
            'data_points': len(sensor_data),
            'last_reading': max([d['timestamp'] for d in sensor_data]) if sensor_data else 0
        }
    
    def _analyze_climate_zone(self, farm_config, sensor_analysis):
        """Analyze based on Sri Lankan climate zones"""
        climate_zone = farm_config.get('climateZone', '').strip()
        
        print(f"🐛 CLIMATE DEBUG: climate_zone='{climate_zone}', available zones: {list(self.sri_lanka_data['climate_zones'].keys())}")
        
        if not climate_zone:
            print(f"🐛 CLIMATE DEBUG: Climate zone is empty")
            return {
                'status': 'Climate zone not specified',
                'message': 'Please set your climate zone in the farm configuration settings',
                'available_zones': list(self.sri_lanka_data['climate_zones'].keys()),
                'required_fields': ['climateZone']
            }
        
        # Try exact match first
        zone_data = self.sri_lanka_data['climate_zones'].get(climate_zone)
        
        # If not found, try case-insensitive matching
        if not zone_data:
            for available_zone in self.sri_lanka_data['climate_zones']:
                if available_zone.lower() == climate_zone.lower():
                    zone_data = self.sri_lanka_data['climate_zones'][available_zone]
                    climate_zone = available_zone  # Use the correct case
                    print(f"🐛 CLIMATE DEBUG: Found case-insensitive match: '{climate_zone}'")
                    break
        
        if not zone_data:
            print(f"🐛 CLIMATE DEBUG: No matching climate zone found for '{climate_zone}'")
            return {
                'status': 'Unknown climate zone',
                'message': f'Climate zone "{climate_zone}" not recognized. Please select from available options.',
                'available_zones': list(self.sri_lanka_data['climate_zones'].keys()),
                'current_value': climate_zone,
                'required_fields': ['climateZone']
            }
        
        current_temp = sensor_analysis.get('average_temperature', 0)
        current_humidity = sensor_analysis.get('average_humidity', 0)
        
        # Check if conditions are within optimal range
        temp_optimal = zone_data['temperature_range'][0] <= current_temp <= zone_data['temperature_range'][1]
        humidity_optimal = zone_data['humidity_range'][0] <= current_humidity <= zone_data['humidity_range'][1]
        
        return {
            'climate_zone': climate_zone,
            'optimal_temperature_range': zone_data['temperature_range'],
            'optimal_humidity_range': zone_data['humidity_range'],
            'current_temperature_status': 'Optimal' if temp_optimal else 'Outside range',
            'current_humidity_status': 'Optimal' if humidity_optimal else 'Outside range',
            'recommended_crops': zone_data['optimal_crops'],
            'monthly_rainfall_pattern': zone_data['rainfall_mm']
        }
    
    def _analyze_monsoon_impact(self, current_time, farm_config):
        """Analyze current monsoon impact"""
        current_month = current_time.month
        climate_zone = farm_config.get('climateZone', '').strip()
        
        print(f"🐛 MONSOON DEBUG: current_month={current_month}, climate_zone='{climate_zone}'")
        
        active_monsoons = []
        for monsoon, data in self.monsoon_patterns.items():
            if current_month in data['months']:
                # Check if this monsoon affects the climate zone
                affected_zones = data.get('affected_zones', [])
                if not affected_zones or climate_zone in affected_zones or any(zone.lower() == climate_zone.lower() for zone in affected_zones):
                    active_monsoons.append(monsoon)
                    print(f"🐛 MONSOON DEBUG: {monsoon} is active (affects {affected_zones})")
        
        print(f"🐛 MONSOON DEBUG: active_monsoons={active_monsoons}")
        
        is_peak_rainfall = any(
            current_month in self.monsoon_patterns[m].get('peak_rainfall', [])
            for m in active_monsoons
        )
        
        return {
            'current_month': current_month,
            'current_month_name': current_time.strftime('%B'),
            'climate_zone': climate_zone,
            'active_monsoons': active_monsoons,
            'is_peak_rainfall_period': bool(is_peak_rainfall),
            'expected_rainfall_level': 'High' if is_peak_rainfall else 'Medium' if active_monsoons else 'Low',
            'farming_recommendations': self._get_monsoon_farming_advice(active_monsoons, is_peak_rainfall)
        }
    
    def _analyze_crop_specific(self, farm_config, sensor_analysis):
        """Analyze specific to the crop being grown"""
        crop_type = farm_config.get('cropType', '').strip()
        seed_variety = farm_config.get('seedVariety', '').strip()
        
        if not crop_type:
            return {'status': 'Crop type not specified'}
        
        crop_info = self.sri_lanka_data['crop_varieties'].get(crop_type, {})
        variety_info = crop_info.get(seed_variety, {}) if seed_variety else {}
        
        # Calculate growth stage if planting date is available
        growth_stage = self._calculate_growth_stage(farm_config)
        
        return {
            'crop_type': crop_type,
            'seed_variety': seed_variety,
            'variety_details': variety_info,
            'growth_stage': growth_stage,
            'optimal_conditions': self._get_crop_optimal_conditions(crop_type),
            'current_suitability': self._assess_current_suitability(crop_type, sensor_analysis)
        }
    
    def _predict_yield(self, farm_config, sensor_analysis):
        """Predict crop yield based on Sri Lankan agriculture data"""
        crop_type = farm_config.get('cropType', '').strip()
        seed_variety = farm_config.get('seedVariety', '').strip()
        # Handle both fieldSize (from Flutter) and field_size_acres
        field_size_str = farm_config.get('fieldSize', farm_config.get('field_size_acres', '0'))
        
        try:
            field_size = float(field_size_str or 0)
        except (ValueError, TypeError):
            field_size = 0
        
        print(f"🐛 YIELD DEBUG: crop_type='{crop_type}', seed_variety='{seed_variety}', field_size_str='{field_size_str}', field_size={field_size}")
        
        if not crop_type:
            print(f"🐛 YIELD DEBUG: Crop type is empty")
            return {
                'status': 'Crop type not specified',
                'message': 'Please set your crop type in the farm configuration settings',
                'required_fields': ['cropType']
            }
        
        if field_size <= 0:
            print(f"🐛 YIELD DEBUG: Invalid field size - field_size_str: '{field_size_str}', field_size: {field_size}")
            return {
                'status': 'Field size not specified or invalid',
                'message': 'Please enter a valid field size (in acres) in the farm configuration settings',
                'required_fields': ['fieldSize'],
                'current_value': field_size_str
            }
        
        # Get base yield from variety data
        crop_data = self.sri_lanka_data['crop_varieties'].get(crop_type, {})
        
        # If exact crop type not found, try case-insensitive matching
        if not crop_data:
            for available_crop in self.sri_lanka_data['crop_varieties']:
                if available_crop.lower() == crop_type.lower():
                    crop_data = self.sri_lanka_data['crop_varieties'][available_crop]
                    crop_type = available_crop  # Use the correct case
                    break
        
        print(f"🐛 YIELD DEBUG: Found crop_data: {bool(crop_data)}, available crops: {list(self.sri_lanka_data['crop_varieties'].keys())}")
        
        variety_data = crop_data.get(seed_variety, {})
        
        # If exact variety not found, try case-insensitive matching
        if not variety_data and seed_variety:
            for available_variety in crop_data:
                if available_variety.lower() == seed_variety.lower():
                    variety_data = crop_data[available_variety]
                    break
        
        if variety_data:
            base_yield_per_acre = variety_data.get('yield_per_acre', 0)
        else:
            # Use average for crop type
            base_yield_per_acre = np.mean([v.get('yield_per_acre', 0) for v in crop_data.values()]) if crop_data else 0
        
        if base_yield_per_acre == 0:
            return {'status': f'No yield data available for {crop_type}'}
        
        # Apply environmental factors
        temp_factor = self._calculate_temperature_factor(sensor_analysis.get('average_temperature', 25))
        moisture_factor = self._calculate_moisture_factor(sensor_analysis.get('average_soil_moisture', 50))
        climate_factor = self._calculate_climate_factor(farm_config)
        
        # Calculate predicted yield
        total_factor = (temp_factor + moisture_factor + climate_factor) / 3
        predicted_yield_per_acre = base_yield_per_acre * total_factor
        total_predicted_yield = predicted_yield_per_acre * field_size
        
        # Calculate confidence based on data quality
        confidence = min(95, max(60, 80 + (sensor_analysis.get('data_points', 1) * 2)))
        
        return {
            'crop_type': crop_type,
            'seed_variety': seed_variety,
            'field_size_acres': field_size,
            'base_yield_per_acre': round(base_yield_per_acre, 2),
            'predicted_yield_per_acre': round(predicted_yield_per_acre, 2),
            'total_predicted_yield': round(total_predicted_yield, 2),
            'yield_unit': self._get_yield_unit(crop_type),
            'environmental_factors': {
                'temperature_factor': round(temp_factor, 3),
                'moisture_factor': round(moisture_factor, 3),
                'climate_factor': round(climate_factor, 3)
            },
            'confidence_percentage': round(confidence, 1),
            'yield_category': self._categorize_yield(predicted_yield_per_acre, base_yield_per_acre)
        }
    
    def _forecast_harvest(self, farm_config, current_time):
        """Forecast harvest timing and expectations"""
        crop_type = farm_config.get('cropType', '').strip()
        planting_date = farm_config.get('plantingDate', '').strip()
        
        print(f"🐛 HARVEST DEBUG: crop_type='{crop_type}', planting_date='{planting_date}'")
        
        if not crop_type:
            print(f"🐛 HARVEST DEBUG: Crop type not specified")
            return {
                'status': 'Crop type not specified',
                'message': 'Please set your crop type in the farm configuration settings',
                'required_fields': ['cropType']
            }
        
        if not planting_date:
            print(f"🐛 HARVEST DEBUG: Planting date not specified")
            return {
                'status': 'Planting date not specified',
                'message': 'Please set your planting date in the farm configuration settings. Use YYYY-MM-DD format or "Yala"/"Maha" season',
                'required_fields': ['plantingDate']
            }
        
        # Try to parse planting date
        planting_datetime = None
        if planting_date:
            try:
                if 'yala' in planting_date.lower():
                    planting_datetime = datetime(current_time.year, 5, 15)  # Mid Yala season
                elif 'maha' in planting_date.lower():
                    planting_datetime = datetime(current_time.year, 11, 15)  # Mid Maha season
                else:
                    planting_datetime = datetime.strptime(planting_date, '%Y-%m-%d')
            except:
                pass
        
        if not planting_datetime:
            return {'status': 'Planting date not available or in unrecognized format'}
        
        # Get crop growth period
        crop_data = self.sri_lanka_data['crop_varieties'].get(crop_type, {})
        
        # If exact crop type not found, try case-insensitive matching
        if not crop_data:
            for available_crop in self.sri_lanka_data['crop_varieties']:
                if available_crop.lower() == crop_type.lower():
                    crop_data = self.sri_lanka_data['crop_varieties'][available_crop]
                    crop_type = available_crop  # Use the correct case
                    break
        
        print(f"🐛 HARVEST DEBUG: Found crop_data: {bool(crop_data)}, available crops: {list(self.sri_lanka_data['crop_varieties'].keys())}")
        
        if not crop_data:
            return {'status': f'No growth data available for {crop_type}'}
        
        # Use first variety's growth data or average
        growth_data = list(crop_data.values())[0]
        if 'growth_days' in growth_data:
            growth_period = growth_data['growth_days']
        elif 'growth_years' in growth_data:
            growth_period = growth_data['growth_years'] * 365
        else:
            growth_period = 120  # Default 4 months
        
        # Calculate harvest date
        harvest_date = planting_datetime + timedelta(days=growth_period)
        days_to_harvest = (harvest_date - current_time).days
        
        # Calculate current growth stage
        days_since_planting = (current_time - planting_datetime).days
        growth_percentage = min(100, max(0, (days_since_planting / growth_period) * 100))
        
        return {
            'crop_type': crop_type,
            'planting_date': planting_datetime.strftime('%Y-%m-%d'),
            'expected_harvest_date': harvest_date.strftime('%Y-%m-%d'),
            'days_to_harvest': days_to_harvest,
            'growth_stage_percentage': round(growth_percentage, 1),
            'growth_stage_name': self._get_growth_stage_name(growth_percentage),
            'harvest_season': self._get_harvest_season(harvest_date),
            'harvest_status': 'Ready' if days_to_harvest <= 0 else 'Growing' if days_to_harvest <= 30 else 'Early stage'
        }
    
    def _forecast_weather(self, farm_config, sensor_analysis):
        """7-day weather forecast based on patterns and current conditions"""
        climate_zone = farm_config.get('climateZone', '')
        location = farm_config.get('location', '')
        current_month = datetime.now().month
        
        zone_data = self.sri_lanka_data['climate_zones'].get(climate_zone, {})
        current_temp = sensor_analysis.get('average_temperature', 27)
        current_humidity = sensor_analysis.get('average_humidity', 75)
        
        # Generate 7-day forecast
        forecast_days = []
        for i in range(7):
            date = datetime.now() + timedelta(days=i)
            
            # Simulate weather variation
            temp_variation = np.random.normal(0, 2)  # ±2°C variation
            humidity_variation = np.random.normal(0, 5)  # ±5% variation
            
            forecasted_temp = current_temp + temp_variation
            forecasted_humidity = max(40, min(95, current_humidity + humidity_variation))
            
            # Rainfall probability based on monsoon
            rainfall_prob = self._calculate_rainfall_probability(date, climate_zone)
            
            forecast_days.append({
                'date': date.strftime('%Y-%m-%d'),
                'temperature_celsius': round(forecasted_temp, 1),
                'humidity_percentage': round(forecasted_humidity, 1),
                'rainfall_probability': round(rainfall_prob, 1),
                'conditions': self._determine_weather_conditions(forecasted_temp, forecasted_humidity, rainfall_prob)
            })
        
        return {
            'location': location,
            'climate_zone': climate_zone,
            'forecast_days': forecast_days,
            'summary': f"7-day forecast for {climate_zone} zone",
            'farming_advice': self._get_weather_farming_advice(forecast_days)
        }
    
    def _assess_disease_risk(self, sensor_analysis, farm_config):
        """Assess disease and pest risk based on conditions"""
        temp = sensor_analysis.get('average_temperature', 25)
        humidity = sensor_analysis.get('average_humidity', 70)
        soil_moisture = sensor_analysis.get('average_soil_moisture', 50)
        crop_type = farm_config.get('cropType', '')
        
        # Disease risk factors
        risk_factors = []
        risk_level = 0
        
        # High humidity + moderate temperature = fungal disease risk
        if humidity > 80 and 20 < temp < 30:
            risk_factors.append("High fungal disease risk due to humid conditions")
            risk_level += 30
        
        # Excessive soil moisture
        if soil_moisture > 80:
            risk_factors.append("Root rot risk due to waterlogged soil")
            risk_level += 25
        
        # Very low soil moisture
        if soil_moisture < 20:
            risk_factors.append("Plant stress due to drought conditions")
            risk_level += 20
        
        # Temperature stress
        if temp > 35:
            risk_factors.append("Heat stress risk for crops")
            risk_level += 15
        elif temp < 15:
            risk_factors.append("Cold stress risk for tropical crops")
            risk_level += 10
        
        # Crop-specific risks
        if crop_type == 'Rice':
            if humidity > 85:
                risk_factors.append("Blast disease risk in rice")
                risk_level += 20
        elif crop_type == 'Tea':
            if temp > 32:
                risk_factors.append("Tea leaf scorch risk")
                risk_level += 15
        
        risk_level = min(100, risk_level)
        
        return {
            'overall_risk_level': risk_level,
            'risk_category': 'Low' if risk_level < 30 else 'Medium' if risk_level < 60 else 'High',
            'risk_factors': risk_factors,
            'prevention_measures': self._get_prevention_measures(risk_factors, crop_type),
            'monitoring_advice': self._get_monitoring_advice(risk_level)
        }
    
    def _generate_sri_lankan_recommendations(self, farm_config, sensor_analysis, climate_analysis, monsoon_analysis):
        """Generate Sri Lankan agriculture specific recommendations"""
        recommendations = []
        
        crop_type = farm_config.get('cropType', '')
        climate_zone = farm_config.get('climateZone', '')
        current_temp = sensor_analysis.get('average_temperature', 0)
        current_humidity = sensor_analysis.get('average_humidity', 0)
        soil_moisture = sensor_analysis.get('average_soil_moisture', 0)
        
        # Climate-based recommendations
        if climate_analysis.get('current_temperature_status') == 'Outside range':
            if current_temp > climate_analysis.get('optimal_temperature_range', [0, 100])[1]:
                recommendations.append({
                    'category': 'Temperature Management',
                    'priority': 'High',
                    'action': 'Implement shade netting or mulching to reduce soil temperature',
                    'sri_lankan_context': 'Use coconut fronds or paddy straw as natural mulch'
                })
        
        # Monsoon-based recommendations
        if monsoon_analysis.get('is_peak_rainfall_period'):
            recommendations.append({
                'category': 'Monsoon Management',
                'priority': 'High',
                'action': 'Ensure proper drainage to prevent waterlogging',
                'sri_lankan_context': 'Check "bethma" cultivation drainage systems'
            })
        
        # Crop-specific recommendations
        if crop_type == 'Rice':
            if soil_moisture < 60:
                recommendations.append({
                    'category': 'Irrigation',
                    'priority': 'High',
                    'action': 'Increase irrigation frequency for rice fields',
                    'sri_lankan_context': 'Consider traditional "kanna" (bund) irrigation methods'
                })
        
        # Soil moisture recommendations
        if soil_moisture > 85:
            recommendations.append({
                'category': 'Drainage',
                'priority': 'Medium',
                'action': 'Improve field drainage to prevent root diseases',
                'sri_lankan_context': 'Create traditional "ela" (drainage channels)'
            })
        
        # Fertilizer recommendations
        recommendations.append({
            'category': 'Fertilization',
            'priority': 'Medium',
            'action': 'Apply organic fertilizer based on crop stage',
            'sri_lankan_context': 'Use traditional compost with cattle manure and coconut coir'
        })
        
        return recommendations
    
    # Helper methods for calculations
    def _calculate_temperature_factor(self, temp):
        """Calculate temperature impact factor (0.5 to 1.5)"""
        if 20 <= temp <= 30:
            return 1.0 + (0.1 * (30 - abs(temp - 25)) / 5)
        elif temp < 20:
            return 0.5 + (temp / 40)
        else:  # temp > 30
            return max(0.5, 1.0 - ((temp - 30) / 20))
    
    def _calculate_moisture_factor(self, moisture):
        """Calculate soil moisture impact factor (0.5 to 1.2)"""
        if 40 <= moisture <= 70:
            return 1.2
        elif moisture < 40:
            return 0.5 + (moisture / 80)
        else:  # moisture > 70
            return max(0.7, 1.2 - ((moisture - 70) / 60))
    
    def _calculate_climate_factor(self, farm_config):
        """Calculate climate zone factor"""
        climate_zone = farm_config.get('climateZone', '')
        crop_type = farm_config.get('cropType', '')
        
        zone_data = self.sri_lanka_data['climate_zones'].get(climate_zone, {})
        optimal_crops = zone_data.get('optimal_crops', [])
        
        if crop_type in optimal_crops:
            return 1.1
        else:
            return 0.9
    
    def _get_yield_unit(self, crop_type):
        """Get appropriate yield unit for crop type"""
        units = {
            'Rice': 'tons/acre',
            'Tea': 'kg/acre',
            'Coconut': 'nuts/tree',
            'Rubber': 'kg/acre'
        }
        return units.get(crop_type, 'kg/acre')
    
    def _categorize_yield(self, predicted, base):
        """Categorize yield prediction"""
        ratio = predicted / base if base > 0 else 0
        if ratio >= 1.1:
            return 'Excellent'
        elif ratio >= 0.9:
            return 'Good'
        elif ratio >= 0.7:
            return 'Average'
        else:
            return 'Below Average'
    
    def _calculate_growth_stage(self, farm_config):
        """Calculate current growth stage"""
        planting_date = farm_config.get('plantingDate', '')
        if not planting_date:
            return {'status': 'Planting date not provided'}
        
        try:
            if 'yala' in planting_date.lower():
                plant_date = datetime(datetime.now().year, 5, 15)
            elif 'maha' in planting_date.lower():
                plant_date = datetime(datetime.now().year, 11, 15)
            else:
                plant_date = datetime.strptime(planting_date, '%Y-%m-%d')
            
            days_since_planting = (datetime.now() - plant_date).days
            
            if days_since_planting < 0:
                return {'stage': 'Pre-planting', 'days': abs(days_since_planting)}
            elif days_since_planting < 30:
                return {'stage': 'Germination/Seedling', 'days': days_since_planting}
            elif days_since_planting < 60:
                return {'stage': 'Vegetative Growth', 'days': days_since_planting}
            elif days_since_planting < 90:
                return {'stage': 'Flowering/Reproductive', 'days': days_since_planting}
            else:
                return {'stage': 'Maturation/Harvest Ready', 'days': days_since_planting}
        
        except:
            return {'status': 'Could not calculate growth stage'}
    
    def _get_growth_stage_name(self, percentage):
        """Get growth stage name from percentage"""
        if percentage < 25:
            return 'Seedling Stage'
        elif percentage < 50:
            return 'Vegetative Growth'
        elif percentage < 75:
            return 'Flowering Stage'
        elif percentage < 95:
            return 'Fruit Development'
        else:
            return 'Harvest Ready'
    
    def _get_harvest_season(self, harvest_date):
        """Determine harvest season"""
        month = harvest_date.month
        if month in [3, 4, 5]:
            return 'Yala Harvest Season'
        elif month in [8, 9, 10]:
            return 'Maha Harvest Season'
        else:
            return 'Off-season Harvest'
    
    def _calculate_rainfall_probability(self, date, climate_zone):
        """Calculate rainfall probability based on monsoon patterns"""
        month = date.month
        zone_data = self.sri_lanka_data['climate_zones'].get(climate_zone, {})
        monthly_rainfall = zone_data.get('rainfall_mm', [100] * 12)
        
        # Higher rainfall means higher probability
        rainfall_mm = monthly_rainfall[month - 1]
        probability = min(90, max(10, rainfall_mm / 5))
        
        return probability
    
    def _determine_weather_conditions(self, temp, humidity, rainfall_prob):
        """Determine weather conditions description"""
        if rainfall_prob > 70:
            return 'Rainy'
        elif rainfall_prob > 40:
            return 'Partly Cloudy'
        elif temp > 32:
            return 'Hot and Sunny'
        elif humidity > 85:
            return 'Humid'
        else:
            return 'Fair'
    
    def _get_weather_farming_advice(self, forecast_days):
        """Get farming advice based on weather forecast"""
        advice = []
        
        high_rain_days = sum(1 for day in forecast_days if day['rainfall_probability'] > 70)
        hot_days = sum(1 for day in forecast_days if day['temperature_celsius'] > 32)
        
        if high_rain_days >= 3:
            advice.append("Heavy rain expected - ensure proper drainage")
        if hot_days >= 3:
            advice.append("Hot weather expected - increase irrigation frequency")
        
        return advice
    
    def _get_monsoon_farming_advice(self, active_monsoons, is_peak_rainfall):
        """Get monsoon-specific farming advice"""
        advice = []
        
        if 'Southwest Monsoon' in active_monsoons:
            advice.append("Southwest monsoon active - good time for Yala cultivation")
        if 'Northeast Monsoon' in active_monsoons:
            advice.append("Northeast monsoon active - prepare for Maha season")
        if is_peak_rainfall:
            advice.append("Peak rainfall period - monitor drainage systems")
        
        return advice
    
    def _get_crop_optimal_conditions(self, crop_type):
        """Get optimal growing conditions for crop"""
        conditions = {
            'Rice': {'temperature': [22, 32], 'humidity': [70, 85], 'soil_moisture': [60, 80]},
            'Tea': {'temperature': [18, 25], 'humidity': [75, 85], 'soil_moisture': [50, 70]},
            'Coconut': {'temperature': [24, 32], 'humidity': [70, 80], 'soil_moisture': [40, 60]},
            'Vegetables': {'temperature': [20, 28], 'humidity': [65, 80], 'soil_moisture': [50, 75]}
        }
        return conditions.get(crop_type, conditions['Vegetables'])
    
    def _assess_current_suitability(self, crop_type, sensor_analysis):
        """Assess if current conditions are suitable for crop"""
        optimal = self._get_crop_optimal_conditions(crop_type)
        temp = sensor_analysis.get('average_temperature', 25)
        humidity = sensor_analysis.get('average_humidity', 70)
        moisture = sensor_analysis.get('average_soil_moisture', 50)
        
        temp_ok = optimal['temperature'][0] <= temp <= optimal['temperature'][1]
        humidity_ok = optimal['humidity'][0] <= humidity <= optimal['humidity'][1]
        moisture_ok = optimal['soil_moisture'][0] <= moisture <= optimal['soil_moisture'][1]
        
        suitability_score = sum([temp_ok, humidity_ok, moisture_ok]) / 3 * 100
        
        return {
            'overall_suitability': round(suitability_score, 1),
            'temperature_suitable': bool(temp_ok),
            'humidity_suitable': bool(humidity_ok),
            'soil_moisture_suitable': bool(moisture_ok),
            'status': 'Excellent' if suitability_score > 90 else 'Good' if suitability_score > 70 else 'Fair' if suitability_score > 50 else 'Poor'
        }
    
    def _get_prevention_measures(self, risk_factors, crop_type):
        """Get prevention measures for identified risks"""
        measures = []
        
        for factor in risk_factors:
            if 'fungal' in factor.lower():
                measures.append("Apply organic fungicide (neem oil solution)")
            if 'root rot' in factor.lower():
                measures.append("Improve drainage and reduce irrigation frequency")
            if 'drought' in factor.lower():
                measures.append("Implement drip irrigation or mulching")
            if 'heat stress' in factor.lower():
                measures.append("Provide shade netting during hottest hours")
        
        return measures
    
    def _get_monitoring_advice(self, risk_level):
        """Get monitoring advice based on risk level"""
        if risk_level < 30:
            return "Regular weekly monitoring is sufficient"
        elif risk_level < 60:
            return "Monitor twice weekly and watch for early symptoms"
        else:
            return "Daily monitoring recommended - take immediate preventive action"
    
    def _generate_alerts(self, sensor_analysis, disease_risk, monsoon_analysis):
        """Generate actionable alerts"""
        alerts = []
        
        # Temperature alerts
        temp = sensor_analysis.get('average_temperature', 25)
        if temp > 35:
            alerts.append({
                'type': 'Warning',
                'message': 'Extreme heat detected - protect crops from heat stress',
                'action': 'Increase irrigation and provide shade'
            })
        
        # Disease risk alerts
        if disease_risk.get('overall_risk_level', 0) > 60:
            alerts.append({
                'type': 'Alert',
                'message': 'High disease risk detected',
                'action': 'Apply preventive treatments immediately'
            })
        
        # Monsoon alerts
        if monsoon_analysis.get('is_peak_rainfall_period'):
            alerts.append({
                'type': 'Info',
                'message': 'Peak monsoon season - high rainfall expected',
                'action': 'Ensure drainage systems are clear'
            })
        
        return alerts


# Initialize the AI system
ai_system = SriLankanAgricultureAI()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'Sri Lankan Agriculture AI'}), 200

@app.route('/analyze', methods=['POST'])
def analyze_farm():
    """Main analysis endpoint"""
    try:
        data = request.get_json()
        sensor_data = data.get('sensor_data', [])
        farm_config = data.get('farm_config', {})
        nodes = data.get('nodes', [])
        
        # Debug logging to understand what data is received
        print("🐛 DEBUG: Received farm_config:")
        for key, value in farm_config.items():
            print(f"   {key}: '{value}' (type: {type(value).__name__})")
        
        # Perform comprehensive analysis
        analysis = ai_system.analyze_farm_data(sensor_data, farm_config, nodes)
        
        response_data = {
            'status': 'success',
            'analysis': analysis,
            'service': 'Sri Lankan Agriculture AI'
        }
        
        # Use custom JSON encoder to handle numpy types
        json_str = json.dumps(response_data, cls=NumpyEncoder)
        return app.response_class(
            response=json_str,
            status=200,
            mimetype='application/json'
        )
        
    except Exception as e:
        print(f"❌ Error in analyze_farm: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e),
            'service': 'Sri Lankan Agriculture AI'
        }), 500

@app.route('/recommendations', methods=['POST'])
def get_recommendations():
    """Get specific recommendations"""
    try:
        data = request.get_json()
        sensor_data = data.get('sensor_data', [])
        farm_config = data.get('farm_config', {})
        
        # Analyze and get recommendations
        sensor_analysis = ai_system._analyze_sensor_data(sensor_data)
        climate_analysis = ai_system._analyze_climate_zone(farm_config, sensor_analysis)
        monsoon_analysis = ai_system._analyze_monsoon_impact(datetime.now(), farm_config)
        
        recommendations = ai_system._generate_sri_lankan_recommendations(
            farm_config, sensor_analysis, climate_analysis, monsoon_analysis
        )
        
        response_data = {
            'status': 'success',
            'recommendations': recommendations,
            'service': 'Sri Lankan Agriculture AI'
        }
        
        # Use custom JSON encoder to handle numpy types
        json_str = json.dumps(response_data, cls=NumpyEncoder)
        return app.response_class(
            response=json_str,
            status=200,
            mimetype='application/json'
        )
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/predict', methods=['POST'])
def predict_yield():
    """Yield prediction endpoint"""
    try:
        data = request.get_json()
        sensor_data = data.get('sensor_data', [])
        farm_config = data.get('farm_config', {})
        
        sensor_analysis = ai_system._analyze_sensor_data(sensor_data)
        yield_prediction = ai_system._predict_yield(farm_config, sensor_analysis)
        harvest_forecast = ai_system._forecast_harvest(farm_config, datetime.now())
        
        response_data = {
            'status': 'success',
            'yield_prediction': yield_prediction,
            'harvest_forecast': harvest_forecast,
            'service': 'Sri Lankan Agriculture AI'
        }
        
        # Use custom JSON encoder to handle numpy types
        json_str = json.dumps(response_data, cls=NumpyEncoder)
        return app.response_class(
            response=json_str,
            status=200,
            mimetype='application/json'
        )
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

if __name__ == '__main__':
    print("🇱🇰 Sri Lankan Agriculture AI Server Starting...")
    print("Features:")
    print("- Climate zone analysis (Wet/Dry/Intermediate)")
    print("- Monsoon impact assessment")
    print("- Crop-specific recommendations")
    print("- Yield predictions with Sri Lankan varieties")
    print("- Harvest forecasting")
    print("- Disease risk assessment")
    print("- Traditional farming method integration")
    print()
    
    # For Google Colab deployment with ngrok
    try:
        from pyngrok import ngrok
        import threading
        import time
        
        print("🚀 Starting Flask server...")
        
        # Start Flask app in background thread
        def run_flask():
            app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)
        
        flask_thread = threading.Thread(target=run_flask)
        flask_thread.daemon = True
        flask_thread.start()
        
        # Wait for server to start
        time.sleep(3)
        
        # Create ngrok tunnel
        print("🌐 Creating ngrok tunnel...")
        public_url = ngrok.connect(5000)
        
        print()
        print("=" * 60)
        print("🇱🇰 SRI LANKAN AGRICULTURE AI SERVER READY!")
        print("=" * 60)
        print(f"📡 PUBLIC URL: {public_url}")
        print(f"🏠 LOCAL URL:  http://localhost:5000")
        print()
        print("📱 FLUTTER APP SETUP:")
        print(f"   1. Open your Flutter app")
        print(f"   2. Go to Settings → AI Analysis Configuration")
        print(f"   3. Enter this URL: {public_url}")
        print(f"   4. Configure your Sri Lankan farm details")
        print()
        print("🔗 API ENDPOINTS:")
        print(f"   • Health Check: {public_url}/health")
        print(f"   • Farm Analysis: {public_url}/analyze")
        print(f"   • Recommendations: {public_url}/recommendations")
        print(f"   • Yield Prediction: {public_url}/predict")
        print()
        print("🌾 Ready to analyze Sri Lankan agriculture data!")
        print("=" * 60)
        print()
        
        # Keep the server running
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Server stopped by user")
            ngrok.kill()
            
    except ImportError:
        print("⚠️  pyngrok not found - running in local mode only")
        print("💡 For Google Colab: !pip install pyngrok")
        print(f"🏠 LOCAL URL: http://localhost:5000")
        print()
        app.run(host='0.0.0.0', port=5000, debug=True)
    except Exception as e:
        print(f"❌ Error setting up ngrok: {e}")
        print("🔄 Falling back to local server...")
        print(f"🏠 LOCAL URL: http://localhost:5000")
        print()
        app.run(host='0.0.0.0', port=5000, debug=True)
