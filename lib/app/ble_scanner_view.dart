import 'package:ble_test/app/digiblu_device_screen.dart';
import 'package:ble_test/services/digiblu_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

// Provider para el estado de escaneo
final scanningProvider = StateProvider<bool>((ref) => false);

// Provider para el servicio digiblu
final digibluServiceProvider = Provider<DigibluService>(
  (ref) => DigibluService(),
);

// Provider para los dispositivos encontrados
final devicesProvider = StateProvider<List<ScanResult>>((ref) => []);

// Provider para manejar el escaneo
final bleScannerProvider = Provider<BleScanner>((ref) => BleScanner(ref));

class BleScanner {
  final Ref ref;

  BleScanner(this.ref);

  Future<void> startScan() async {
    // Verificar permisos
    final permissionsGranted = await _checkPermissions();
    if (!permissionsGranted) {
      debugPrint('Permisos BLE no concedidos');
      return;
    }

    // Verificar Bluetooth
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('Bluetooth está apagado');
      return;
    }

    ref.read(scanningProvider.notifier).state = true;
    ref.read(devicesProvider.notifier).state = [];

    // Iniciar escaneo
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    // Escuchar resultados y filtrar solo dispositivos con nombre
    FlutterBluePlus.scanResults.listen((results) {
      final devicesWithName = results
          .where((result) => result.device.platformName.isNotEmpty)
          .toList();
      ref.read(devicesProvider.notifier).state = devicesWithName;
    });

    // Esperar a que termine el escaneo
    await Future.delayed(const Duration(seconds: 15));
    await stopScan();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    ref.read(scanningProvider.notifier).state = false;
  }

  Future<bool> _checkPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    for (final permission in permissions) {
      final status = await permission.request();
      if (!status.isGranted) return false;
    }
    return true;
  }
}

class BleScannerView extends ConsumerWidget {
  const BleScannerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScanning = ref.watch(scanningProvider);
    final devices = ref.watch(devicesProvider);
    final scanner = ref.read(bleScannerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('BLE Scanner'), centerTitle: true),
      body: Column(
        children: [
          // Header con botón de escaneo
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                Text(
                  isScanning ? 'Escaneando...' : 'Listo para escanear',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${devices.length} dispositivos encontrados',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: isScanning
                      ? () => scanner.stopScan()
                      : () => scanner.startScan(),
                  icon: Icon(isScanning ? Icons.stop : Icons.search),
                  label: Text(isScanning ? 'Detener' : 'Iniciar Escaneo'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ],
            ),
          ),

          // Lista de dispositivos
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_searching,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isScanning
                              ? 'Buscando dispositivos...'
                              : 'Pulsa el botón para iniciar',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final result = devices[index];
                      final device = result.device;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(
                              Icons.bluetooth,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          title: Text(
                            device.platformName.isEmpty
                                ? 'Dispositivo desconocido'
                                : device.platformName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${device.remoteId}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'RSSI: ${result.rssi} dBm',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getRssiColor(result.rssi),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (result
                                  .advertisementData
                                  .serviceUuids
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Servicios: ${result.advertisementData.serviceUuids.length}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Icon(
                            _getRssiIcon(result.rssi),
                            color: _getRssiColor(result.rssi),
                          ),
                          onTap: () {
                            _connectToDevice(context, ref, device);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -60) return Colors.green;
    if (rssi > -80) return Colors.orange;
    return Colors.red;
  }

  IconData _getRssiIcon(int rssi) {
    if (rssi > -60) return Icons.signal_cellular_alt;
    if (rssi > -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  Future<void> _connectToDevice(
    BuildContext context,
    WidgetRef ref,
    BluetoothDevice device,
  ) async {
    final digibluService = ref.read(digibluServiceProvider);

    // Mostrar diálogo de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Conectando...'),
          ],
        ),
      ),
    );

    final success = await digibluService.connect(device);

    if (context.mounted) {
      Navigator.pop(context); // Cerrar diálogo de progreso

      if (success) {
        // Pedir contraseña para autenticación
        final password = await _showPasswordDialog(context);

        if (password != null && password.isNotEmpty) {
          // Mostrar diálogo de autenticación
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const AlertDialog(
                content: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text('Autenticando...'),
                  ],
                ),
              ),
            );
          }

          final authenticated = await digibluService.authenticate(password);

          if (context.mounted) {
            Navigator.pop(context); // Cerrar diálogo de autenticación

            if (authenticated) {
              // Mostrar pantalla de dispositivo conectado
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      DigibluDeviceScreen(digibluService: digibluService),
                ),
              );
            } else {
              await digibluService.disconnect();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Error de autenticación. Contraseña incorrecta.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else {
          // Usuario canceló o no ingresó contraseña
          await digibluService.disconnect();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Autenticación cancelada')),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al conectar al dispositivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Autenticación Digiblu'),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Introduce la contraseña del dispositivo:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
                hintText: 'Contraseña del Digiblu',
              ),
              onSubmitted: (value) {
                Navigator.pop(context, value);
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta contraseña se usará para acceder a las funciones de descarga de archivos TGD.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, controller.text);
            },
            child: const Text('Autenticar'),
          ),
        ],
      ),
    );
  }
}
