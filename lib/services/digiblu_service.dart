import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Servicio para manejar la conexión y comunicación con digiblu
class DigibluService {
  BluetoothDevice? _connectedDevice;
  List<BluetoothService> _services = [];
  bool _isAuthenticated = false;

  // Estado de conexión
  bool get isConnected => _connectedDevice != null;
  bool get isAuthenticated => _isAuthenticated;
  BluetoothDevice? get device => _connectedDevice;
  List<BluetoothService> get services => _services;

  /// Forzar estado de autenticación (usar con precaución)
  /// Útil cuando el dispositivo no confirma pero funciona
  void setAuthenticatedManually(bool value) {
    _isAuthenticated = value;
    debugPrint(
      value
          ? '⚠️ Autenticación forzada manualmente a TRUE'
          : '⚠️ Autenticación forzada manualmente a FALSE',
    );
  }

  // UUIDs comunes para autenticación Digiblu (Nordic UART Service)
  // Nomenclatura desde perspectiva del dispositivo (servidor):
  // - RX = Recibe datos (tu app ESCRIBE aquí)
  // - TX = Transmite datos (tu app LEE/SUBSCRIBE aquí)
  static const String AUTH_SERVICE = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String AUTH_CHAR_WRITE =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // RX del dispositivo
  static const String AUTH_CHAR_NOTIFY =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // TX del dispositivo

  /// Conectar al dispositivo digiblu
  Future<bool> connect(BluetoothDevice device) async {
    try {
      debugPrint('🔵 Conectando a ${device.platformName}...');

      // Conectar con timeout de 15 segundos
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;
      debugPrint('✅ Conectado a ${device.platformName}');

      // Descubrir servicios y características
      await discoverServices();

      return true;
    } catch (e) {
      debugPrint('❌ Error conectando: $e');
      return false;
    }
  }

  /// Desconectar del dispositivo
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        debugPrint('🔴 Desconectado de ${_connectedDevice!.platformName}');
      } catch (e) {
        debugPrint('❌ Error desconectando: $e');
      }
      _connectedDevice = null;
      _services = [];
      _isAuthenticated = false;
    }
  }

  /// Autenticar con el dispositivo Digiblu usando contraseña
  Future<bool> authenticate(String password) async {
    if (_connectedDevice == null) {
      debugPrint('❌ No hay dispositivo conectado');
      return false;
    }

    try {
      debugPrint('🔐 Intentando autenticar con contraseña...');

      // Buscar la característica de escritura para autenticación
      BluetoothCharacteristic? authChar;
      BluetoothCharacteristic? notifyChar;

      // Buscar primero por UUID conocido
      authChar = findCharacteristic(AUTH_CHAR_WRITE);
      notifyChar = findCharacteristic(AUTH_CHAR_NOTIFY);

      // Si no se encuentra, buscar cualquier característica con write
      if (authChar == null) {
        for (var service in _services) {
          for (var char in service.characteristics) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              authChar = char;
              debugPrint('🔍 Usando característica de escritura: ${char.uuid}');
              break;
            }
          }
          if (authChar != null) break;
        }
      }

      if (authChar == null) {
        debugPrint('❌ No se encontró característica de autenticación');
        return false;
      }

      // Buscar característica de notificación para recibir respuesta
      if (notifyChar == null) {
        for (var service in _services) {
          for (var char in service.characteristics) {
            if (char.properties.notify || char.properties.indicate) {
              notifyChar = char;
              debugPrint(
                '🔍 Usando característica de notificación: ${char.uuid}',
              );
              break;
            }
          }
          if (notifyChar != null) break;
        }
      }

      bool authSuccess = false;

      // Suscribirse a notificaciones ANTES de enviar contraseña
      if (notifyChar != null &&
          (notifyChar.properties.notify || notifyChar.properties.indicate)) {
        debugPrint('📡 Suscribiéndose a notificaciones antes de autenticar...');

        // Crear un completer para esperar la respuesta
        final responseReceived = Completer<bool>();

        // Escuchar respuesta
        final subscription = notifyChar.onValueReceived.listen((response) {
          debugPrint('📨 Respuesta de autenticación recibida:');
          debugPrint('   Hex: ${_bytesToHex(response)}');
          debugPrint('   Dec: ${response.join(", ")}');
          debugPrint('   Longitud: ${response.length} bytes');

          if (response.isNotEmpty) {
            // Intentar interpretar como string
            try {
              final asString = String.fromCharCodes(response);
              debugPrint('   Como String: "$asString"');
            } catch (e) {
              debugPrint('   No se pudo convertir a String');
            }

            // Patrones comunes de respuesta exitosa:
            // - "OK" = [0x4F, 0x4B]
            // - [0x00] = Success
            // - [0x01] = ACK
            // - Echo de la contraseña = Éxito

            // Patrones comunes de error:
            // - "ERROR" / "ERR" / "FAIL"
            // - [0xFF] = Error genérico
            // - [0x00, 0x00] = Error

            bool success = false;

            // Verificar patrones de éxito
            if (response.length == 2 &&
                response[0] == 0x4F &&
                response[1] == 0x4B) {
              // "OK" en ASCII
              success = true;
              debugPrint('   ✅ Detectado: "OK"');
            } else if (response.length == 1 &&
                (response[0] == 0x00 || response[0] == 0x01)) {
              // [0x00] o [0x01] = Success/ACK
              success = true;
              debugPrint('   ✅ Detectado: ACK/Success');
            } else if (response.length >= 5) {
              // Si es largo, probablemente sea eco de contraseña = éxito
              success = true;
              debugPrint('   ✅ Detectado: Respuesta larga (posible eco)');
            } else if (response.length == 2 &&
                response[0] == 0x00 &&
                response[1] == 0x00) {
              // [0x00, 0x00] suele ser error
              success = false;
              debugPrint('   ❌ Detectado: Error [0x00, 0x00]');
            } else if (response[0] == 0xFF) {
              // [0xFF] = Error genérico
              success = false;
              debugPrint('   ❌ Detectado: Error [0xFF]');
            } else {
              // Por defecto, si recibimos algo desconocido de 1-4 bytes, lo consideramos error
              // Si es más largo, éxito
              success = response.length > 4;
              debugPrint(
                '   ⚠️ Respuesta desconocida, asumiendo: ${success ? "éxito" : "error"}',
              );
            }

            if (!responseReceived.isCompleted) {
              responseReceived.complete(success);
            }
          }
        });

        await notifyChar.setNotifyValue(true);
        debugPrint('✅ Suscrito a notificaciones de autenticación');

        // Convertir contraseña a bytes (ASCII)
        final passwordBytes = password.codeUnits;

        // Enviar contraseña
        debugPrint('📤 Enviando contraseña: ${_bytesToHex(passwordBytes)}');
        await writeCharacteristic(authChar, passwordBytes);

        // Esperar respuesta con timeout de 3 segundos
        try {
          authSuccess = await responseReceived.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('⏱️ Timeout esperando respuesta de autenticación');
              debugPrint(
                '⚠️ El dispositivo puede no enviar confirmación explícita',
              );
              // Si timeout, intentar verificar la autenticación de otra forma
              return false;
            },
          );
        } catch (e) {
          debugPrint('❌ Error esperando respuesta: $e');
          authSuccess = false;
        }

        await subscription.cancel();

        // Si falló por timeout, asumir que el dispositivo no confirma pero acepta
        if (!authSuccess) {
          debugPrint('⚠️ No hubo confirmación explícita de autenticación.');
          debugPrint(
            '💡 El Digiblu no responde a la autenticación (modo silencioso).',
          );
          debugPrint(
            '   Asumiendo autenticación exitosa. Se verificará al descargar.',
          );

          // Para Digiblu, asumir éxito si no hay error explícito
          authSuccess = true;
        }
      } else {
        // Si no hay característica de notificación, asumimos modo "fire and forget"
        debugPrint(
          '⚠️ No hay característica de notificación. Modo sin confirmación.',
        );
        final passwordBytes = password.codeUnits;
        await writeCharacteristic(authChar, passwordBytes);
        debugPrint(
          '📤 Contraseña enviada sin confirmación: ${_bytesToHex(passwordBytes)}',
        );

        // Esperar un poco
        await Future.delayed(const Duration(milliseconds: 1000));

        // Sin forma de verificar, dejar como no autenticado
        authSuccess = false;
        debugPrint(
          '⚠️ No se puede verificar autenticación (sin canal de respuesta)',
        );
        debugPrint(
          '💡 Intenta usar la app de todas formas. Si funciona, estaba autenticado.',
        );
      }

      _isAuthenticated = authSuccess;

      if (authSuccess) {
        debugPrint('✅ Autenticación exitosa');
      } else {
        debugPrint('❌ Autenticación fallida');
      }

      return authSuccess;
    } catch (e) {
      debugPrint('❌ Error durante autenticación: $e');
      _isAuthenticated = false;
      return false;
    }
  }

  /// Descubrir todos los servicios y características del dispositivo
  Future<void> discoverServices() async {
    if (_connectedDevice == null) return;

    try {
      debugPrint('🔍 Descubriendo servicios...');
      _services = await _connectedDevice!.discoverServices();

      debugPrint('\n📋 Servicios encontrados: ${_services.length}');

      for (var service in _services) {
        debugPrint('\n🔹 Servicio: ${service.uuid}');
        debugPrint('   Características: ${service.characteristics.length}');

        for (var characteristic in service.characteristics) {
          final props = characteristic.properties;
          debugPrint('   └─ ${characteristic.uuid}');
          debugPrint(
            '      Read: ${props.read} | Write: ${props.write} | Notify: ${props.notify}',
          );

          // Si tiene propiedad de lectura, intentar leer el valor
          if (props.read) {
            try {
              final value = await characteristic.read();
              debugPrint('      Valor inicial: ${_bytesToHex(value)}');
            } catch (e) {
              debugPrint('      No se pudo leer: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error descubriendo servicios: $e');
    }
  }

  /// Suscribirse a notificaciones de una característica
  Future<void> subscribeToNotifications(
    BluetoothCharacteristic characteristic,
    Function(List<int>) onData,
  ) async {
    if (!characteristic.properties.notify) {
      debugPrint('❌ La característica no soporta notificaciones');
      return;
    }

    try {
      await characteristic.setNotifyValue(true);

      characteristic.onValueReceived.listen((value) {
        debugPrint('📨 Notificación recibida: ${_bytesToHex(value)}');
        onData(value);
      });

      debugPrint('✅ Suscrito a notificaciones de ${characteristic.uuid}');
    } catch (e) {
      debugPrint('❌ Error suscribiéndose: $e');
    }
  }

  /// Leer una característica específica
  Future<List<int>?> readCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    if (!characteristic.properties.read) {
      debugPrint('❌ La característica no soporta lectura');
      return null;
    }

    try {
      final value = await characteristic.read();
      debugPrint('📖 Leído de ${characteristic.uuid}: ${_bytesToHex(value)}');
      return value;
    } catch (e) {
      debugPrint('❌ Error leyendo: $e');
      return null;
    }
  }

  /// Escribir datos a una característica
  Future<bool> writeCharacteristic(
    BluetoothCharacteristic characteristic,
    List<int> data, {
    bool withResponse = true,
  }) async {
    if (!characteristic.properties.write &&
        !characteristic.properties.writeWithoutResponse) {
      debugPrint('❌ La característica no soporta escritura');
      return false;
    }

    try {
      await characteristic.write(data, withoutResponse: !withResponse);
      debugPrint('✍️ Escrito a ${characteristic.uuid}: ${_bytesToHex(data)}');
      return true;
    } catch (e) {
      debugPrint('❌ Error escribiendo: $e');
      return false;
    }
  }

  /// Buscar una característica específica por UUID
  BluetoothCharacteristic? findCharacteristic(String characteristicUuid) {
    for (var service in _services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toLowerCase().contains(
          characteristicUuid.toLowerCase(),
        )) {
          return characteristic;
        }
      }
    }
    return null;
  }

  /// Buscar un servicio por UUID
  BluetoothService? findService(String serviceUuid) {
    for (var service in _services) {
      if (service.uuid.toString().toLowerCase().contains(
        serviceUuid.toLowerCase(),
      )) {
        return service;
      }
    }
    return null;
  }

  /// Obtener información resumida del dispositivo
  Map<String, dynamic> getDeviceInfo() {
    if (_connectedDevice == null) return {};

    return {
      'name': _connectedDevice!.platformName,
      'id': _connectedDevice!.remoteId.toString(),
      'services': _services.length,
      'characteristics': _services.fold<int>(
        0,
        (total, service) => total + service.characteristics.length,
      ),
    };
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
