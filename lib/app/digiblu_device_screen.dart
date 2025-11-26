import 'package:ble_test/services/digiblu_service.dart';
import 'package:ble_test/services/tachograph_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Pantalla para interactuar con el dispositivo digiblu conectado
class DigibluDeviceScreen extends StatefulWidget {
  final DigibluService digibluService;

  const DigibluDeviceScreen({super.key, required this.digibluService});

  @override
  State<DigibluDeviceScreen> createState() => _DigibluDeviceScreenState();
}

class _DigibluDeviceScreenState extends State<DigibluDeviceScreen> {
  final Map<String, List<int>> _characteristicValues = {};
  bool _isReading = false;
  late TachographDownloader _downloader;
  String _downloadStatus = '';

  @override
  void initState() {
    super.initState();
    _downloader = TachographDownloader(widget.digibluService);
    _downloader.onStatusChange = (status) {
      if (mounted) {
        setState(() => _downloadStatus = status);
      }
    };
    _startReading();
  }

  Future<void> _startReading() async {
    setState(() => _isReading = true);

    // Intentar leer todas las características disponibles
    for (var service in widget.digibluService.services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.read) {
          try {
            final value = await widget.digibluService.readCharacteristic(
              characteristic,
            );
            if (value != null && mounted) {
              setState(() {
                _characteristicValues[characteristic.uuid.toString()] = value;
              });
            }
          } catch (e) {
            debugPrint(
              'Error leyendo característica ${characteristic.uuid}: $e',
            );
          }
        }

        // Suscribirse a notificaciones si está disponible
        if (characteristic.properties.notify) {
          try {
            await widget.digibluService.subscribeToNotifications(
              characteristic,
              (data) {
                if (mounted) {
                  setState(() {
                    _characteristicValues[characteristic.uuid.toString()] =
                        data;
                  });
                }
              },
            );
          } catch (e) {
            debugPrint(
              'Error suscribiendo a notificaciones ${characteristic.uuid}: $e',
            );
          }
        }
      }
    }
    if (mounted) {
      setState(() => _isReading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceInfo = widget.digibluService.getDeviceInfo();

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceInfo['name'] ?? 'Dispositivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isReading ? null : _startReading,
            tooltip: 'Actualizar datos',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header con información del dispositivo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      'Conectado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Indicador de autenticación
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.digibluService.isAuthenticated
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.digibluService.isAuthenticated
                                ? Icons.lock_open
                                : Icons.lock,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.digibluService.isAuthenticated
                                ? 'Autenticado'
                                : 'No autenticado',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('ID: ${deviceInfo['id']}'),
                Text('Servicios: ${deviceInfo['services']}'),
                Text('Características: ${deviceInfo['characteristics']}'),
                if (_downloadStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        if (_downloader.isDownloading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_downloader.isDownloading) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _downloadStatus,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Lista de servicios y características
          Expanded(
            child: _isReading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: widget.digibluService.services.length,
                    itemBuilder: (context, index) {
                      final service = widget.digibluService.services[index];
                      return _buildServiceCard(service);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botón de prueba de comandos (solo para debugging)
          FloatingActionButton.extended(
            onPressed: () async {
              await _downloader.testCommands();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Revisa la consola para ver los resultados'),
                    backgroundColor: Colors.blue,
                  ),
                );
              }
            },
            icon: const Icon(Icons.science),
            label: const Text('Probar comandos'),
            backgroundColor: Colors.orange,
            heroTag: 'test',
          ),
          const SizedBox(height: 8),
          // Botón para descargar archivo TGD
          if (widget.digibluService.isAuthenticated)
            FloatingActionButton.extended(
              onPressed: _downloader.isDownloading ? null : _downloadTGD,
              icon: const Icon(Icons.download),
              label: const Text('Descargar TGD'),
              backgroundColor: Colors.blue,
              heroTag: 'download',
            ),
          if (widget.digibluService.isAuthenticated) const SizedBox(height: 8),
          // Botón de desconectar
          FloatingActionButton.extended(
            onPressed: () async {
              await widget.digibluService.disconnect();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.close),
            label: const Text('Desconectar'),
            backgroundColor: Colors.red,
            heroTag: 'disconnect',
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTGD() async {
    if (!widget.digibluService.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes autenticarte primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descargar archivo TGD'),
        content: const Text(
          '¿Deseas iniciar la descarga de datos del tacógrafo?\n\n'
          'Este proceso puede tardar varios minutos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _downloader.downloadVehicleUnit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Descarga completada exitosamente'
                  : 'Error durante la descarga',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildServiceCard(BluetoothService service) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        leading: const Icon(Icons.settings_bluetooth, color: Colors.blue),
        title: Text(
          'Servicio',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          service.uuid.toString(),
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        children: service.characteristics.map((char) {
          return _buildCharacteristicTile(char);
        }).toList(),
      ),
    );
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic characteristic) {
    final uuid = characteristic.uuid.toString();
    final value = _characteristicValues[uuid];
    final props = characteristic.properties;

    return ListTile(
      dense: true,
      leading: const Icon(Icons.data_object, size: 20),
      title: Text(
        uuid,
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'R: ${props.read} | W: ${props.write} | N: ${props.notify}',
            style: const TextStyle(fontSize: 10),
          ),
          if (value != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hex: ${_bytesToHex(value)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'Dec: ${value.join(", ")}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  if (_tryDecodeString(value) != null)
                    Text(
                      'String: ${_tryDecodeString(value)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (props.read)
            IconButton(
              icon: const Icon(Icons.download, size: 20),
              onPressed: () async {
                final data = await widget.digibluService.readCharacteristic(
                  characteristic,
                );
                if (data != null) {
                  setState(() {
                    _characteristicValues[uuid] = data;
                  });
                }
              },
              tooltip: 'Leer',
            ),
          if (props.write)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _showWriteDialog(characteristic),
              tooltip: 'Escribir',
            ),
        ],
      ),
    );
  }

  void _showWriteDialog(BluetoothCharacteristic characteristic) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escribir datos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Hex (ej: 01 02 03)',
                hintText: 'Escribe bytes en hexadecimal',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Separa los bytes con espacios',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final hexString = controller.text.trim();
                final bytes = hexString
                    .split(' ')
                    .map((h) => int.parse(h, radix: 16))
                    .toList();

                await widget.digibluService.writeCharacteristic(
                  characteristic,
                  bytes,
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Datos escritos correctamente'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String? _tryDecodeString(List<int> bytes) {
    try {
      final str = String.fromCharCodes(bytes);
      if (str.contains(RegExp(r'[^\x20-\x7E]'))) return null;
      return str;
    } catch (e) {
      return null;
    }
  }
}
