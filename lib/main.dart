import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// ★ ここにAPIキーを直接記述してください
const String googleApiKey = '';
const String openaiApiKey = '';

Future<void> main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: GasStationAiApp());
  }
}

class GasStationAiApp extends StatefulWidget {
  const GasStationAiApp({super.key});

  @override
  State<GasStationAiApp> createState() => _GasStationAiAppState();
}

class _GasStationAiAppState extends State<GasStationAiApp> {
  Position? _currentPosition;
  List<Map<String, dynamic>> _stations = [];
  bool _loading = false;
  String? _errorMessage;
  String? _aiMessage;

  Future<void> _getLocationAndStations() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _stations = [];
      _aiMessage = null;
    });

    try {
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

      if (googleApiKey.isEmpty) {
        setState(() {
          _errorMessage = 'Google APIキーが設定されていません。';
          _loading = false;
        });
        return;
      }

      final url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${pos.latitude},${pos.longitude}'
          '&radius=3000&type=gas_station&language=ja&key=$googleApiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        final stations = results.map((item) {
          final name = item['name'] ?? '';
          final lat = item['geometry']['location']['lat'];
          final lng = item['geometry']['location']['lng'];
          final address = item['vicinity'] ?? '';
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            lat,
            lng,
          ).round();
          return {
            'name': name,
            'lat': lat,
            'lng': lng,
            'address': address,
            'distance': distance,
            'price': '不明',
          };
        }).toList();

        setState(() {
          _stations = stations;
          _loading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'APIリクエスト失敗: ${response.statusCode}\n${response.body}';
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

  // AIでおすすめGSを問い合わせ
  Future<void> _getAiRecommendation() async {
    setState(() => _aiMessage = "AIに問い合わせ中...");
    if (openaiApiKey.isEmpty) {
      setState(() => _aiMessage = 'OpenAI APIキーが未設定です');
      return;
    }
    if (_stations.isEmpty) {
      setState(() => _aiMessage = 'ガソリンスタンド情報がありません。');
      return;
    }

    final promptBuffer = StringBuffer();
    promptBuffer.writeln('あなたはガソリンスタンド選びのプロです。');
    promptBuffer.writeln(
      '以下のガソリンスタンド情報から「最も近く、かつ価格が安いスタンド」を1つだけ日本語で理由も教えてください。\n',
    );
    for (int i = 0; i < _stations.length; i++) {
      final s = _stations[i];
      promptBuffer.writeln(
        'No.${i + 1}: ${s['name']}（距離: ${s['distance']}m, 価格: ${s['price']}）',
      );
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $openaiApiKey',
    };
    final body = json.encode({
      //モデルは1番安い3.5-turbo
      "model": "gpt-3.5-turbo-0125",
      "messages": [
        {"role": "system", "content": "あなたはガソリンスタンド選びのプロです。"},
        {"role": "user", "content": promptBuffer.toString()},
      ],
      "max_tokens": 200,
    });

    try {
      final res = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: headers,
        body: body,
      );
      if (res.statusCode == 200) {
        final content = json.decode(
          res.body,
        )['choices'][0]['message']['content'];
        setState(() => _aiMessage = content);
      } else {
        setState(() => _aiMessage = "AIによる推薦に失敗しました（${res.statusCode}）");
      }
    } catch (e) {
      setState(() => _aiMessage = "AI連携エラー: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _getLocationAndStations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ガソリンスタンドAI検索')),
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
                                subtitle: Text(
                                  '${gs['address']}（${gs['distance']}m）',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (!_loading && _stations.isEmpty && _errorMessage == null)
                      const Text('ガソリンスタンド情報がありません。'),
                    const SizedBox(height: 12),
                    if (_stations.isNotEmpty)
                      ElevatedButton(
                        onPressed: _getAiRecommendation,
                        child: const Text('AIでおすすめを表示'),
                      ),
                    if (_aiMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'AIのおすすめ:\n$_aiMessage',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
