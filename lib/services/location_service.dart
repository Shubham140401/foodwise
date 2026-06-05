import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position?> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }

  // Returns 'home', 'work', or 'current' based on proximity to saved addresses.
  // Actual geocoding is out of scope — we just return the label for the prompt.
  Future<String> resolveLocationLabel({
    required String? homeAddress,
    required String? workAddress,
  }) async {
    final pos = await getCurrentPosition();
    if (pos == null) {
      if (homeAddress != null) return 'home ($homeAddress)';
      return 'unknown location';
    }
    // Without a geocoding service we report coordinates and let Claude interpret.
    return 'current location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
  }
}
