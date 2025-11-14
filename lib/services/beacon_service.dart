import 'dart:async';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class BeaconService {
  StreamSubscription<RangingResult>? _streamRanging;
  final _beaconsController = StreamController<List<Beacon>>.broadcast();

  Stream<List<Beacon>> get beaconsStream => _beaconsController.stream;

  // Inicializar el servicio
  Future<void> initialize() async {
    await flutterBeacon.initializeScanning;
  }

  // Solicitar permisos
  Future<bool> requestPermissions() async {
    await flutterBeacon.initializeScanning;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    return statuses[Permission.location]?.isGranted == true;
  }

  // Iniciar escaneo
  Future<void> startScanning() async {
    try {
      final regions = <Region>[Region(identifier: 'AllBeacons')];

      _streamRanging = flutterBeacon
          .ranging(regions)
          .listen(
            (result) {
              _beaconsController.add(result.beacons);
            },
            onError: (error) {
              print('Error scanning: $error');
              _beaconsController.addError(error);
            },
          );
    } catch (e) {
      print('Error starting scan: $e');
      _beaconsController.addError(e);
    }
  }

  // Detener escaneo
  void stopScanning() {
    _streamRanging?.cancel();
    _streamRanging = null;
  }

  void dispose() {
    stopScanning();
    _beaconsController.close();
  }
}

// Provider del servicio
final beaconServiceProvider = Provider<BeaconService>((ref) {
  final service = BeaconService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provider del estado de escaneo
final beaconScanProvider = StreamProvider.autoDispose<List<Beacon>>((ref) {
  final service = ref.watch(beaconServiceProvider);
  return service.beaconsStream;
});
