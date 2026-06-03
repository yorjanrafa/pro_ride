import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // IMPORTANTE: Para SystemNavigator
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
          onWebResourceError: (error) {
            setState(() => _isOffline = true);
          },
          onPageFinished: (url) {
            print("Página cargada: $url");
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://deliverypro.system.deliverypro.com.ve/workers/login-rider',
        ),
      );

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        setState(() => _isOffline = true);
      } else {
        _retryConnection();
      }
    });
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

  // Lógica de retroceso mejorada para evitar pantalla negra
  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      // Si hay historial en la web, retrocedemos
      await _controller.goBack();
    } else {
      // Si ya no hay historial, cerramos la app limpiamente
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.white, // Fondo blanco para evitar destellos negros
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          // Ejecutamos nuestra propia lógica de cierre
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
                        boxShadow: [
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
                            "tu conexion a internet es mala",
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
                            child: const Text("reintentar"),
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
