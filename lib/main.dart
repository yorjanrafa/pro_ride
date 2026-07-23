import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

// 1. NUEVA IMPORTACIÓN PARA ABRIR MAPS
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  static const _channel = MethodChannel('com.example.rider_data_load/cookie_manager');

  Future<void> _flushCookies() async {
    try {
      await _channel.invokeMethod('flushCookies');
      print("Cookies flushed successfully");
    } on PlatformException catch (e) {
      print("Failed to flush cookies: ${e.message}");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushCookies();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          // --- AQUÍ EMPIEZA LA INTERCEPCIÓN DE URLS (SOLUCIÓN GOOGLE MAPS) ---
          onNavigationRequest: (NavigationRequest request) async {
            final url = Uri.parse(request.url);

            // Manejar URLs con esquema de intent nativo de Android (ej. 'intent://maps.google.com/...')
            if (request.url.startsWith('intent:')) {
              String webUrl = request.url;
              final intentIndex = webUrl.indexOf('#Intent;');
              if (intentIndex != -1) {
                // Intentar extraer la URL de fallback del navegador si está disponible
                final fallbackRegex = RegExp(r'S\.browser_fallback_url=([^;]+)');
                final match = fallbackRegex.firstMatch(webUrl.substring(intentIndex));
                if (match != null) {
                  final decodedUrl = Uri.decodeComponent(match.group(1)!);
                  final fallbackUri = Uri.parse(decodedUrl);
                  if (await canLaunchUrl(fallbackUri)) {
                    await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                    return NavigationDecision.prevent;
                  }
                }
                // Si no hay fallback, recortar los metadatos de Chrome/Android
                webUrl = webUrl.substring(0, intentIndex);
              }

              // Reemplazar el esquema "intent" por "https"
              if (webUrl.startsWith('intent://')) {
                webUrl = webUrl.replaceFirst('intent://', 'https://');
              } else {
                webUrl = webUrl.replaceFirst('intent:', 'https:');
              }

              final targetUri = Uri.parse(webUrl);
              if (await canLaunchUrl(targetUri)) {
                await launchUrl(targetUri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            // Si la URL NO empieza con http o https (ej. geo:, whatsapp://, google.navigation:)
            if (!request.url.startsWith('http://') &&
                !request.url.startsWith('https://')) {
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision
                  .prevent; // Bloquea que el WebView intente cargarlo
            }

            // Filtro adicional por si los botones usan links normales de Maps
            if (request.url.contains('maps.google.com') ||
                request.url.contains('goo.gl/maps')) {
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            return NavigationDecision
                .navigate; // Deja pasar la navegación normal web
          },

          // --- AQUÍ TERMINA LA SOLUCIÓN ---
          onWebResourceError: (error) {
            setState(() => _isOffline = true);
          },
          onPageFinished: (url) {
            print("Página cargada: $url");
            _flushCookies();
          },
        ),
      );

    _setupWebView();

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        setState(() => _isOffline = true);
      } else {
        _retryConnection();
      }
    });
  }

  Future<void> _setupWebView() async {
    // 2. CONFIGURACIÓN DE PERMISOS GPS Y COOKIES PARA ANDROID
    if (_controller.platform is AndroidWebViewController) {
      final AndroidWebViewController androidController =
          _controller.platform as AndroidWebViewController;

      // Aceptar cookies de terceros para persistencia de sesión
      final WebViewCookieManager cookieManager = WebViewCookieManager();
      if (cookieManager.platform is AndroidWebViewCookieManager) {
        await (cookieManager.platform as AndroidWebViewCookieManager)
            .setAcceptThirdPartyCookies(androidController, true);
      }

      await androidController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          var status = await Permission.locationWhenInUse.request();
          return GeolocationPermissionsResponse(
            allow: status.isGranted,
            retain: true,
          );
        },
      );
    }

    // 3. CARGAMOS LA URL DESPUÉS DE CONFIGURAR TODO
    await _controller.loadRequest(
      Uri.parse(
        'https://deliverypro.system.deliverypro.com.ve/workers/login-rider',
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    super.dispose();
  }

  void _retryConnection() async {
    final results = await Connectivity().checkConnectivity();
    if (!results.contains(ConnectivityResult.none)) {
      setState(() => _isOffline = false);
      _controller.reload();
    }
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleBack();
        },
        child: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isOffline)
                Container(
                  color: Colors.white.withOpacity(1),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 10),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 70,
                            color: Color(0xFF4F46E5),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "La conexión a internet es inestable o se ha perdido la conexión. Vuelve a intentarlo.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 25),
                          ElevatedButton(
                            onPressed: _retryConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 45),
                            ),
                            child: const Text("Reintentar"),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
