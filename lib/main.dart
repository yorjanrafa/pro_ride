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

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          // --- AQUÍ EMPIEZA LA INTERCEPCIÓN DE URLS (SOLUCIÓN GOOGLE MAPS) ---
          onNavigationRequest: (NavigationRequest request) async {
            final url = Uri.parse(request.url);

            // Si la URL NO empieza con http o https (ej. intent://, geo:, whatsapp://)
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
