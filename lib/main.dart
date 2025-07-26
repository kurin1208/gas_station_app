import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

Future<void> main() async {
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: GasStationListApp());
  }
}

class GasStationListApp extends StatefulWidget {
  const GasStationListApp({super.key});

  @override
  State<GasStationListApp> createState() => _GasStationListAppState();
}

class _GasStationListAppState extends State<GasStationListApp> {
  Position? _currentPosition;
  List<Map<String, dynamic>> _stations = [];
  bool _loading = false;
  String? _errorMessage;

  // ① 現在地を取得
  Future<void> _getLocationAndStations() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _stations = [];
    });

    try {
      // パーミッション確認・取得
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _loading = false;
            _errorMessage = '位置情報の権限がありません。';
          });
          return;
        }
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = pos;
      });

      // ② Google Places APIでガソリンスタンド取得
      final apiKey = dotenv.env['GOOGLE_API_KEY'];
      final url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${pos.latitude},${pos.longitude}'
          '&radius=3000&type=gas_station&language=ja&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        final stations = results.map((item) {
          final name = item['name'] ?? '';
          final lat = item['geometry']['location']['lat'];
          final lng = item['geometry']['location']['lng'];
          final address = item['vicinity'] ?? '';
          return {'name': name, 'lat': lat, 'lng': lng, 'address': address};
        }).toList();

        setState(() {
          _stations = stations;
          _loading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'APIリクエスト失敗: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'エラー: $e';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _getLocationAndStations(); // 起動時に自動実行（ボタンでも可）
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ガソリンスタンド一覧')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _getLocationAndStations,
                      child: const Text('再取得'),
                    ),
                    const SizedBox(height: 16),
                    if (_currentPosition != null)
                      Text(
                        '現在地: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    if (_stations.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: _stations.length,
                          itemBuilder: (context, idx) {
                            final gs = _stations[idx];
                            return Card(
                              child: ListTile(
                                title: Text(gs['name']),
                                subtitle: Text(gs['address']),
                              ),
                            );
                          },
                        ),
                      ),
                    if (!_loading && _stations.isEmpty && _errorMessage == null)
                      const Text('ガソリンスタンド情報がありません。'),
                  ],
                ),
        ),
      ),
    );
  }
}
