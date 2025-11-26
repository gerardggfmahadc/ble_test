import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ble_test/services/digiblu_service.dart';

/// Servicio para descargar datos del tacógrafo via Bluetooth
class TachographDownloader {
  final DigibluService digibluService;

  // Buffer para acumular datos recibidos
  final List<int> _dataBuffer = [];
  bool _isDownloading = false;

  // Callbacks para progreso
  Function(String)? onStatusChange;
  Function(int)? onBytesReceived;
  Function(List<int>)? onDownloadComplete;

  TachographDownloader(this.digibluService);

  bool get isDownloading => _isDownloading;

  /// Comandos comunes para tacógrafos (según estándar EU)
  /// Nota: Estos son comandos genéricos, pueden variar según el fabricante
  ///
  /// ⚠️ IMPORTANTE: Estos comandos son genéricos y pueden NO funcionar con Digiblu
  /// El protocolo real de Digiblu/Tachosys no está documentado públicamente
  /// Usa nRF Connect para hacer ingeniería inversa del protocolo real
  static const List<int> CMD_INIT_SESSION = [0x81, 0x00];
  static const List<int> CMD_CLOSE_SESSION = [0x82, 0x00];
  static const List<int> CMD_DOWNLOAD_VU = [0x84, 0x00]; // Vehicle Unit (TGD)
  static const List<int> CMD_DOWNLOAD_DRIVER = [
    0x85,
    0x00,
  ]; // Driver Card (DDD)
  static const List<int> CMD_GET_STATUS = [0x80, 0x01];

  // Comandos alternativos para probar (diferentes fabricantes)
  static const List<int> CMD_INIT_ALT1 = [0x01]; // Init simple
  static const List<int> CMD_INIT_ALT2 = [0xFF, 0x00]; // Init alternativo
  static const List<int> CMD_STATUS_ALT = [0x00]; // Status simple

  // UUIDs comunes en dispositivos tacógrafo (pueden variar)
  // Estos son los más probables según el estándar Nordic UART Service
  static const String UART_SERVICE = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String UART_TX_CHAR =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // Escribir
  static const String UART_RX_CHAR =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // Leer

  /// Encontrar las características de comunicación
  Future<Map<String, BluetoothCharacteristic?>?>
  _findCommunicationCharacteristics() async {
    BluetoothCharacteristic? txChar; // Para enviar comandos
    BluetoothCharacteristic? rxChar; // Para recibir datos

    // Buscar primero por UUIDs conocidos
    txChar = digibluService.findCharacteristic(UART_TX_CHAR);
    rxChar = digibluService.findCharacteristic(UART_RX_CHAR);

    // Si no se encuentran, buscar características con propiedades adecuadas
    if (txChar == null || rxChar == null) {
      for (var service in digibluService.services) {
        for (var char in service.characteristics) {
          // TX: Debe permitir escribir
          if (txChar == null &&
              (char.properties.write || char.properties.writeWithoutResponse)) {
            txChar = char;
            debugPrint('🔍 TX encontrado: ${char.uuid}');
          }

          // RX: Debe permitir notify/indicate
          if (rxChar == null &&
              (char.properties.notify || char.properties.indicate)) {
            rxChar = char;
            debugPrint('🔍 RX encontrado: ${char.uuid}');
          }

          if (txChar != null && rxChar != null) break;
        }
        if (txChar != null && rxChar != null) break;
      }
    }

    if (txChar == null || rxChar == null) {
      debugPrint('❌ No se encontraron características de comunicación');
      return null;
    }

    return {'tx': txChar, 'rx': rxChar};
  }

  /// Iniciar descarga del Vehicle Unit (datos del vehículo - archivo TGD)
  Future<bool> downloadVehicleUnit({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return _performDownload(
      'Vehicle Unit (TGD)',
      CMD_DOWNLOAD_VU,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Iniciar descarga de Driver Card (datos del conductor - archivo DDD)
  Future<bool> downloadDriverCard({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return _performDownload(
      'Driver Card (DDD)',
      CMD_DOWNLOAD_DRIVER,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Enviar comando personalizado
  Future<bool> sendCustomCommand(
    List<int> command, {
    String? description,
  }) async {
    return _performDownload(description ?? 'Comando personalizado', command);
  }

  /// Proceso principal de descarga
  Future<bool> _performDownload(
    String downloadType,
    List<int> downloadCommand, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_isDownloading) {
      debugPrint('⚠️ Ya hay una descarga en progreso');
      return false;
    }

    _isDownloading = true;
    _dataBuffer.clear();
    _updateStatus('Preparando descarga de $downloadType...');

    try {
      // 1. Encontrar características de comunicación
      final chars = await _findCommunicationCharacteristics();
      if (chars == null) {
        _updateStatus('❌ Error: No se encontraron características BLE');
        return false;
      }

      final txChar = chars['tx']!;
      final rxChar = chars['rx']!;

      // 2. Suscribirse a notificaciones para recibir datos
      _updateStatus('📡 Configurando canal de recepción...');

      final completer = Completer<void>();
      late StreamSubscription subscription;

      subscription = rxChar.onValueReceived.listen(
        (data) {
          debugPrint('');
          debugPrint('═══════════════════════════════════════════════════');
          debugPrint('📨 RESPUESTA DEL DISPOSITIVO');
          debugPrint('   Bytes recibidos: ${data.length}');
          debugPrint('   HEX: ${_bytesToHex(data)}');
          debugPrint('   DEC: ${data.join(", ")}');

          // Intentar interpretar como texto
          try {
            final asText = String.fromCharCodes(data);
            if (asText.trim().isNotEmpty && !asText.contains('\u0000')) {
              debugPrint('   Texto: "$asText"');
            }
          } catch (e) {
            debugPrint('   (No es texto válido)');
          }

          debugPrint(
            '   Buffer total: ${_dataBuffer.length + data.length} bytes',
          );
          debugPrint('═══════════════════════════════════════════════════');
          debugPrint('');

          _dataBuffer.addAll(data);
          onBytesReceived?.call(_dataBuffer.length);

          // Detectar fin de transmisión (esto varía según fabricante)
          // Típicamente: secuencia específica o timeout sin datos
          if (_isEndOfTransmission(data)) {
            debugPrint('✅ Fin de transmisión detectado');
            completer.complete();
          }
        },
        onError: (error) {
          debugPrint('❌ Error en stream de recepción: $error');
        },
      );

      await rxChar.setNotifyValue(true);
      debugPrint('✅ Suscrito a notificaciones en: ${rxChar.uuid}');
      debugPrint('   Esperando respuesta del dispositivo...');

      // 3. Enviar comando de inicio de sesión
      _updateStatus('🔐 Iniciando sesión con tacógrafo...');
      debugPrint(
        '📤 Enviando CMD_INIT_SESSION: ${_bytesToHex(CMD_INIT_SESSION)} a ${txChar.uuid}',
      );
      await digibluService.writeCharacteristic(txChar, CMD_INIT_SESSION);
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Enviar rango de fechas si se especifica
      if (startDate != null && endDate != null) {
        _updateStatus('📅 Configurando rango de fechas...');
        final dateCommand = _buildDateRangeCommand(startDate, endDate);
        await digibluService.writeCharacteristic(txChar, dateCommand);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 5. Enviar comando de descarga
      _updateStatus('⬇️ Descargando $downloadType...');
      debugPrint(
        '📤 Enviando CMD_DOWNLOAD: ${_bytesToHex(downloadCommand)} a ${txChar.uuid}',
      );
      await digibluService.writeCharacteristic(txChar, downloadCommand);

      // 6. Esperar a recibir todos los datos (timeout 5 minutos para archivos grandes)
      await completer.future.timeout(
        const Duration(minutes: 1),
        onTimeout: () {
          debugPrint('⏱️ Timeout alcanzado (5 min), finalizando descarga');
          debugPrint(
            '   Datos recibidos hasta ahora: ${_dataBuffer.length} bytes',
          );
        },
      );

      // 7. Cerrar sesión
      _updateStatus('🔒 Cerrando sesión...');
      await digibluService.writeCharacteristic(txChar, CMD_CLOSE_SESSION);
      await rxChar.setNotifyValue(false);
      await subscription.cancel();

      // 8. Guardar archivo
      if (_dataBuffer.isNotEmpty) {
        final filename = await _saveDownloadedFile(downloadType);
        _updateStatus(
          '✅ Descarga completa: $_dataBuffer.length bytes guardados en $filename',
        );
        onDownloadComplete?.call(_dataBuffer);
        return true;
      } else {
        _updateStatus('⚠️ No se recibieron datos');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error durante descarga: $e');
      _updateStatus('❌ Error: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Construir comando con rango de fechas
  List<int> _buildDateRangeCommand(DateTime start, DateTime end) {
    // Formato típico de tacógrafos: YY MM DD HH MM SS
    return [
      0x83, 0x00, // Comando set date range
      start.year % 100,
      start.month,
      start.day,
      start.hour,
      start.minute,
      start.second,
      end.year % 100,
      end.month,
      end.day,
      end.hour,
      end.minute,
      end.second,
    ];
  }

  /// Detectar fin de transmisión
  bool _isEndOfTransmission(List<int> data) {
    // Heurísticas comunes para detectar fin:

    // 1. Secuencias de fin conocidas
    if (data.length >= 2) {
      // EOT (End of Transmission) = 0x04
      if (data.last == 0x04) return true;

      // Secuencia de finalización común: 0x00 0x00
      if (data.length >= 2 &&
          data[data.length - 2] == 0x00 &&
          data.last == 0x00) {
        return true;
      }
    }

    // 2. Si recibimos menos de 20 bytes después de haber recibido muchos,
    //    probablemente sea el último paquete
    if (_dataBuffer.length > 1000 && data.length < 20) {
      return true;
    }

    return false;
  }

  /// Guardar archivo descargado
  Future<String> _saveDownloadedFile(String downloadType) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

    // Determinar extensión según tipo
    String extension = '.bin';
    if (downloadType.contains('Vehicle')) {
      extension = '.tgd';
    } else if (downloadType.contains('Driver')) {
      extension = '.ddd';
    }

    final filename = 'download_$timestamp$extension';
    final file = File('${directory.path}/$filename');

    await file.writeAsBytes(_dataBuffer);
    debugPrint('💾 Archivo guardado: ${file.path}');

    return filename;
  }

  void _updateStatus(String status) {
    debugPrint(status);
    onStatusChange?.call(status);
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Probar respuesta del dispositivo con diferentes comandos
  /// Útil para hacer ingeniería inversa del protocolo
  Future<void> testCommands() async {
    debugPrint('');
    debugPrint('🔬 ════════════════════════════════════════════════');
    debugPrint('🔬 MODO PRUEBA: Probando comandos con Digiblu');
    debugPrint('🔬 ════════════════════════════════════════════════');

    final chars = await _findCommunicationCharacteristics();
    if (chars == null) {
      debugPrint('❌ No se encontraron características');
      return;
    }

    final txChar = chars['tx']!;
    final rxChar = chars['rx']!;

    // Suscribirse a respuestas
    debugPrint('📡 Suscribiéndose a respuestas...');

    final List<List<int>> responses = [];
    final subscription = rxChar.onValueReceived.listen((data) {
      debugPrint('   📨 Respuesta: ${_bytesToHex(data)}');
      responses.add(data);
    });

    await rxChar.setNotifyValue(true);
    await Future.delayed(const Duration(milliseconds: 500));

    // Lista de comandos para probar
    final commandsToTest = [
      {
        'name': 'Status simple',
        'cmd': [0x00],
      },
      {
        'name': 'Init 1',
        'cmd': [0x01],
      },
      {
        'name': 'Status GET',
        'cmd': [0x80, 0x01],
      },
      {
        'name': 'Init session',
        'cmd': [0x81, 0x00],
      },
      {
        'name': 'Download VU',
        'cmd': [0x84, 0x00],
      },
      {
        'name': 'Download Driver',
        'cmd': [0x85, 0x00],
      },
      {
        'name': 'Init alternativo',
        'cmd': [0xFF, 0x00],
      },
      {
        'name': 'Info',
        'cmd': [0xAA],
      },
      {
        'name': 'Ping',
        'cmd': [0x10],
      },
    ];

    for (var test in commandsToTest) {
      debugPrint('');
      debugPrint('┌─────────────────────────────────────────');
      debugPrint('│ Probando: ${test['name']}');
      debugPrint('│ Comando: ${_bytesToHex(test['cmd'] as List<int>)}');

      responses.clear();

      await digibluService.writeCharacteristic(
        txChar,
        test['cmd'] as List<int>,
        withResponse: false,
      );

      // Esperar respuesta (2 segundos)
      await Future.delayed(const Duration(seconds: 2));

      if (responses.isEmpty) {
        debugPrint('│ ❌ Sin respuesta');
      } else {
        debugPrint('│ ✅ ${responses.length} respuesta(s):');
        for (var resp in responses) {
          debugPrint('│    → ${_bytesToHex(resp)}');
        }
      }
      debugPrint('└─────────────────────────────────────────');

      // Pausa entre comandos
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await subscription.cancel();
    await rxChar.setNotifyValue(false);

    debugPrint('');
    debugPrint('🔬 ════════════════════════════════════════════════');
    debugPrint('🔬 FIN DE PRUEBAS');
    debugPrint('🔬 ════════════════════════════════════════════════');
  }

  /// Obtener información del buffer actual
  Map<String, dynamic> getBufferInfo() {
    return {
      'size': _dataBuffer.length,
      'hex_preview': _dataBuffer
          .take(100)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' '),
      'downloading': _isDownloading,
    };
  }

  /// Limpiar buffer
  void clearBuffer() {
    _dataBuffer.clear();
  }
}
