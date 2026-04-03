import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MeshLinkApp());

class MeshLinkApp extends StatelessWidget {
  const MeshLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MeshScreen(),
    );
  }
}

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final TextEditingController _controller = TextEditingController();

  final Set<String> _receivedIds = {};
  final List<String> _devices = [];
  final List<String> _messages = [];

  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
    ].request();
  }

  // ================= MESH =================

  void startMesh() async {
    String name = "User_${DateTime.now().millisecondsSinceEpoch}";

    await Nearby().startAdvertising(
      name,
      strategy,
      onConnectionInitiated: (id, info) {
        Nearby().acceptConnection(id, onPayLoadRecieved: onReceive);
      },
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() => _devices.add(id));
        }
      },
      onDisconnected: (id) {
        setState(() => _devices.remove(id));
      },
    );

    await Nearby().startDiscovery(
      name,
      strategy,
      onEndpointFound: (id, name, sid) {
        Nearby().requestConnection(
          name,
          id,
          onConnectionInitiated: (id, info) {
            Nearby().acceptConnection(id, onPayLoadRecieved: onReceive);
          },
          onConnectionResult: (_, __) {},
          onDisconnected: (_) {},
        );
      },
      onEndpointLost: (_) {},
    );

    setState(() => _isActive = true);
  }

  void stopMesh() async {
    await Nearby().stopAllEndpoints();
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    setState(() {
      _isActive = false;
      _devices.clear();
    });
  }

  // ================= LOGIC =================

  bool isEmergency(String msg) {
    msg = msg.toLowerCase();
    return msg.contains("help") ||
        msg.contains("sos") ||
        msg.contains("accident") ||
        msg.contains("danger");
  }

  void onReceive(String id, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;

    String msg = String.fromCharCodes(payload.bytes!);
    var parts = msg.split("|");

    if (_receivedIds.contains(parts[0])) return;
    _receivedIds.add(parts[0]);

    // Relay (mesh)
    for (var d in _devices) {
      if (d != id) {
        Nearby().sendBytesPayload(d, payload.bytes!);
      }
    }

    setState(() {
      _messages.insert(0, "IN: ${parts[1]}");
    });

    if (parts[2] == "HIGH") {
      Vibration.vibrate();
    }
  }

  void send(String text) {
    if (!_isActive || text.isEmpty) return;

    String id = DateTime.now().millisecondsSinceEpoch.toString();
    String prio = isEmergency(text) ? "HIGH" : "LOW";

    String data = "$id|$text|$prio";
    Uint8List bytes = Uint8List.fromList(data.codeUnits);

    for (var d in _devices) {
      Nearby().sendBytesPayload(d, bytes);
    }

    setState(() {
      _messages.insert(0, "OUT: $text");
    });

    _controller.clear();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MeshLink"),
        actions: [
          Switch(
            value: _isActive,
            onChanged: (v) {
              v ? startMesh() : stopMesh();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Text("Connected Devices: ${_devices.length}"),
          ElevatedButton(
            onPressed: () => send("🚨 SOS"),
            child: const Text("SOS"),
          ),
          Expanded(
            child: ListView(
              children:
                  _messages.map((e) => ListTile(title: Text(e))).toList(),
            ),
          ),
          Row(
            children: [
              Expanded(child: TextField(controller: _controller)),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => send(_controller.text),
              )
            ],
          )
        ],
      ),
    );
  }
}