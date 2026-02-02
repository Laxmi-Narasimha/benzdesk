import 'package:geocoding/geocoding.dart';
import 'package:logger/logger.dart';

/// Service for converting coordinates to human-readable addresses
/// 
/// Uses reverse geocoding to get address from latitude/longitude.
/// This enables admins to verify if employees visited assigned locations.
class GeocodingService {
  static final Logger _logger = Logger();

  // Cache to avoid repeated lookups for same coordinates
  static final Map<String, String> _addressCache = {};

  /// Get human-readable address from coordinates
  /// 
  /// Returns format: "Street, Area, City, State"
  /// Falls back to coordinates if geocoding fails
  static Future<String> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    // Check cache first
    final cacheKey = '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    if (_addressCache.containsKey(cacheKey)) {
      return _addressCache[cacheKey]!;
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = _formatAddress(place);
        
        // Cache the result
        _addressCache[cacheKey] = address;
        
        return address;
      }
    } catch (e) {
      _logger.w('Geocoding failed: $e');
    }

    // Fallback to coordinates
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// Format placemark into a clean address string
  static String _formatAddress(Placemark place) {
    final parts = <String>[];

    // Add street/sublocality (most specific)
    if (place.street != null && place.street!.isNotEmpty) {
      parts.add(place.street!);
    }
    
    // Add locality/sublocality
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    } else if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }

    // Add city (administrativeArea)
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      if (!parts.contains(place.administrativeArea)) {
        parts.add(place.administrativeArea!);
      }
    }

    // If no parts, use name or country
    if (parts.isEmpty) {
      if (place.name != null && place.name!.isNotEmpty) {
        parts.add(place.name!);
      }
      if (place.country != null && place.country!.isNotEmpty) {
        parts.add(place.country!);
      }
    }

    return parts.join(', ');
  }

  /// Get a simplified location name (city/area only)
  /// 
  /// Returns format: "Area, City"
  static Future<String> getSimpleLocation(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[];
        
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          parts.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          parts.add(place.locality!);
        }
        
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (e) {
      _logger.w('Simple geocoding failed: $e');
    }

    return 'Unknown Location';
  }

  /// Clear the address cache
  static void clearCache() {
    _addressCache.clear();
  }
}
