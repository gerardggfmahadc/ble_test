# BLE Test - Aplicación Flutter con Bluetooth Low Energy + Riverpod

Aplicación completa de Flutter para trabajar con dispositivos Bluetooth Low Energy (BLE) usando `flutter_blue_plus` y gestión de estado con `flutter_riverpod`.

## 🚀 Características

- ✅ Escaneo de dispositivos BLE cercanos
- ✅ Conexión y desconexión de dispositivos
- ✅ Visualización de servicios y características
- ✅ Lectura y escritura de características
- ✅ Suscripción a notificaciones BLE
- ✅ Gestión automática de permisos
- ✅ Interfaz intuitiva y fácil de usar
- ✅ Soporte para Android e iOS
- ✅ **Gestión de estado reactiva con Riverpod**
- ✅ **Filtrado y ordenamiento de dispositivos**
- ✅ **Arquitectura escalable y testeable**

## 📦 Dependencias

```yaml
flutter_blue_plus: ^1.32.12  # Librería BLE principal
permission_handler: ^11.3.1  # Gestión de permisos
flutter_riverpod: ^2.6.1     # Gestión de estado
```

## 🛠️ Configuración

### Android

Los permisos ya están configurados en `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Permisos BLE para Android 12+ (API 31+) -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Permisos BLE para Android < 12 -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

El `minSdkVersion` está configurado en 21 en `android/app/build.gradle.kts`.

### iOS

Los permisos ya están configurados en `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Esta aplicación necesita Bluetooth para conectarse a dispositivos BLE</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Esta aplicación necesita Bluetooth para conectarse a dispositivos BLE</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Esta aplicación necesita acceso a la ubicación para escanear dispositivos BLE</string>
```

## 🏗️ Estructura del Proyecto

```
lib/
├── main.dart                                 # App con ProviderScope
├── services/
│   └── ble_service.dart                     # Servicio BLE (Singleton)
├── providers/
│   └── ble_providers.dart                   # Providers de Riverpod
├── pages/
│   ├── ble_home_page_riverpod.dart         # Pantalla principal
│   └── ble_device_detail_page_riverpod.dart # Detalles del dispositivo
├── examples/
│   └── riverpod_examples.dart              # Ejemplos de uso
├── utils/
│   └── ble_examples.dart                   # Utilidades BLE
├── README_BLE.md                           # Documentación BLE
└── README_RIVERPOD.md                      # Documentación Riverpod
```

## 🎯 Arquitectura con Riverpod

### Providers Principales

- **bleServiceProvider**: Instancia del servicio BLE
- **scanNotifierProvider**: Gestión del escaneo
- **deviceConnectionProvider**: Gestión de conexiones
- **connectedDeviceProvider**: Dispositivo actual
- **deviceServicesProvider**: Servicios del dispositivo
- **characteristicNotifierProvider**: Gestión de características
- **filteredDevicesProvider**: Dispositivos filtrados
- **sortedDevicesProvider**: Dispositivos ordenados por RSSI

Ver `lib/README_RIVERPOD.md` para documentación completa.

## 🎯 Uso del Servicio BLE con Riverpod

### Inicializar en main.dart

```dart
void main() {
  runApp(
    const ProviderScope(  // Requerido para Riverpod
      child: MyApp(),
    ),
  );
}
```

### Crear un ConsumerWidget

```dart
class BleHomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Leer estado
    final scanState = ref.watch(scanNotifierProvider);
    final connectedDevice = ref.watch(connectedDeviceProvider);
    
    return Scaffold(...);
  }
}
```

### Escanear dispositivos

```dart
// Iniciar escaneo
ref.read(scanNotifierProvider.notifier).startScan();

// Observar resultados
final sortedDevices = ref.watch(sortedDevicesProvider);
sortedDevices.when(
  data: (devices) => ListView.builder(...),
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => Text('Error: $error'),
);
```

### Conectar a un dispositivo

```dart
await ref.read(deviceConnectionProvider.notifier).connectToDevice(device);

// El estado se actualiza automáticamente
final connectedDevice = ref.watch(connectedDeviceProvider);
```

### Trabajar con características

```dart
// Leer característica
await ref.read(characteristicNotifierProvider.notifier)
   .readCharacteristic(characteristic);

// Escribir característica
await ref.read(characteristicNotifierProvider.notifier)
   .writeCharacteristic(characteristic, [0xFF, 0x00]);

// Suscribirse a notificaciones
ref.read(characteristicNotifierProvider.notifier)
   .subscribeToCharacteristic(characteristic);

// Los valores se actualizan automáticamente
final values = ref.watch(characteristicNotifierProvider);
final value = values[characteristic.uuid.toString()];
```

### Filtrar y ordenar dispositivos

```dart
// Establecer filtro
ref.read(deviceFilterProvider.notifier).state = 'Arduino';

// Activar ordenamiento por RSSI
ref.read(sortByRssiProvider.notifier).state = true;

// Los dispositivos se actualizan automáticamente
final filteredDevices = ref.watch(sortedDevicesProvider);
```

## 📱 Pantallas

### 1. Pantalla Principal (BleHomePageRiverpod)
- Botón para iniciar/detener escaneo
- Lista de dispositivos encontrados
- Indicador de intensidad de señal (RSSI) con colores
- Botón de conexión para cada dispositivo
- Estado de conexión actual
- **Filtrado de dispositivos por nombre**
- **Ordenamiento por señal (RSSI)**
- **Actualización reactiva automática**

### 2. Pantalla de Detalles (BleDeviceDetailPageRiverpod)
- Lista de servicios del dispositivo
- Características de cada servicio
- Botones para leer/escribir características
- Activar/desactivar notificaciones
- Visualización en tiempo real de notificaciones
- **Chips de propiedades (Read, Write, Notify)**
- **Formato de datos: Hex, Decimal y ASCII**
- **Indicador visual de notificaciones activas**

## 🔧 Instalación y Ejecución

1. **Clonar o abrir el proyecto**

2. **Instalar dependencias**
   ```bash
   flutter pub get
   ```

3. **Ejecutar en dispositivo**
   ```bash
   # Android
   flutter run
   
   # iOS
   flutter run
   ```

   ⚠️ **Nota**: Debes ejecutar en un dispositivo físico ya que el emulador no soporta BLE.

## 🧪 Testing

Para probar la aplicación, necesitarás:
- Un dispositivo Android/iOS físico con Bluetooth
- Un dispositivo BLE (smartwatch, sensor, beacon, etc.)

Dispositivos BLE comunes para testing:
- Smartwatches y fitness trackers
- Sensores de temperatura/humedad
- Beacons BLE
- Arduino/ESP32 con BLE
- Dispositivos médicos BLE

## 📚 Documentación Adicional

- `lib/README_BLE.md` - Documentación completa del servicio BLE
- `lib/README_RIVERPOD.md` - Guía completa de Riverpod
- `lib/examples/riverpod_examples.dart` - 20+ ejemplos de código
- [flutter_blue_plus Documentation](https://pub.dev/packages/flutter_blue_plus)
- [Riverpod Documentation](https://riverpod.dev/)

## 🎓 Características de Riverpod

### ✨ Ventajas

1. **Gestión de Estado Reactiva**: Los widgets se reconstruyen automáticamente
2. **Type Safety**: Compilación type-safe con mejor autocompletado
3. **Testeable**: Fácil de mockear y testear
4. **Sin Boilerplate**: Código más limpio sin `ChangeNotifier`
5. **Lazy Loading**: Providers se crean solo cuando se necesitan
6. **Scope Control**: Control fino sobre el alcance del estado
7. **Debugging**: Herramientas de debugging integradas

### 🔍 Providers Disponibles

```dart
// Estado del escaneo
final scanState = ref.watch(scanNotifierProvider);

// Dispositivos filtrados y ordenados
final devices = ref.watch(sortedDevicesProvider);

// Dispositivo conectado
final device = ref.watch(connectedDeviceProvider);

// Servicios del dispositivo
final services = ref.watch(deviceServicesProvider);

// Valores de características
final values = ref.watch(characteristicNotifierProvider);

// RSSI
final rssi = ref.watch(rssiProvider);
```

## 🐛 Solución de Problemas

### ⚠️ Dispositivo No Detectado (Nuevo!)

**Si tu dispositivo BLE no aparece en el escaneo:**

1. **Usa la Herramienta de Diagnóstico Integrada** 🩺
   - Toca el ícono de diagnóstico en la barra superior de la app
   - Ingresa la MAC address de tu dispositivo (ej: `7C:D9:F4:15:0A:DE`)
   - Presiona "Iniciar Escaneo Mejorado" (30 segundos)
   - Revisa los logs detallados en tiempo real
   - Ve TODOS los dispositivos detectados en la pestaña "Dispositivos"

2. **Checklist Rápido:**
   - ✅ Dispositivo BLE encendido y en modo anunciante
   - ✅ NO conectado a otro dispositivo
   - ✅ A menos de 5 metros sin obstáculos
   - ✅ Bluetooth del teléfono encendido
   - ✅ Permisos otorgados (Bluetooth + Ubicación)

3. **Lee la guía completa**: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)

### No se encuentran dispositivos
- Verifica que Bluetooth esté encendido
- Asegúrate de que los permisos estén otorgados
- El dispositivo BLE debe estar en modo anunciante

### Error de conexión
- El dispositivo puede estar fuera de rango
- Puede estar conectado a otro dispositivo
- Reinicia el Bluetooth

### Problemas de permisos
- Verifica AndroidManifest.xml (Android)
- Verifica Info.plist (iOS)
- En Android 12+, acepta los permisos cuando se soliciten

## 📄 Licencia

Este proyecto es de código abierto y está disponible para uso educativo y comercial.

## 👤 Autor

Creado con Flutter y ❤️

