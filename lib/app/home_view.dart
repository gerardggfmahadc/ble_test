import 'package:ble_test/services/beacon_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initBeacon();
  }

  Future<void> _initBeacon() async {
    final service = ref.read(beaconServiceProvider);
    await service.initialize();
  }

  Future<void> _requestPermissionsAndStart() async {
    final service = ref.read(beaconServiceProvider);
    final granted = await service.requestPermissions();

    if (granted) {
      await service.startScanning();
      setState(() => _isScanning = true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permisos necesarios denegados')),
        );
      }
    }
  }

  void _stopScanning() {
    final service = ref.read(beaconServiceProvider);
    service.stopScanning();
    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final beaconsAsync = ref.watch(beaconScanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Beacon Scanner'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _requestPermissionsAndStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar Escaneo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScanning : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Detener'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: beaconsAsync.when(
              data: (beacons) {
                if (beacons.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_searching,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No se encontraron beacons',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: beacons.length,
                  itemBuilder: (context, index) {
                    final beacon = beacons[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getSignalColor(beacon.rssi),
                          child: const Icon(
                            Icons.bluetooth,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          'UUID: ${beacon.proximityUUID}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Major: ${beacon.major} | Minor: ${beacon.minor}',
                            ),
                            Text('RSSI: ${beacon.rssi} dBm'),
                            Text(
                              'Distancia: ${beacon.accuracy.toStringAsFixed(2)}m',
                            ),
                            Text(
                              'Proximidad: ${_getProximity(beacon.proximity)}',
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Buscando beacons...'),
                  ],
                ),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('Error: $error'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi > -60) return Colors.green;
    if (rssi > -80) return Colors.orange;
    return Colors.red;
  }

  String _getProximity(Proximity proximity) {
    switch (proximity) {
      case Proximity.immediate:
        return 'Inmediato';
      case Proximity.near:
        return 'Cerca';
      case Proximity.far:
        return 'Lejos';
      case Proximity.unknown:
        return 'Desconocido';
    }
  }
}
