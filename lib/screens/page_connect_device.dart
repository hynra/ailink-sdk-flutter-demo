import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:ailink/ailink.dart';
import 'package:ailink/utils/ble_common_util.dart';
import 'package:ailink/utils/common_extensions.dart';
import 'package:ailink/utils/elink_cmd_utils.dart';
import 'package:ailink/utils/broadcast_scale_data_utils.dart';
import 'package:ailink/model/param_body_fat_data.dart';
import 'package:ailink/model/body_fat_data.dart';
import 'package:ailink_flutter_demo_1/impl/elink_common_data_parse_callback.dart';
import 'package:ailink_flutter_demo_1/utils/elink_common_cmd_utils.dart';
import 'package:ailink_flutter_demo_1/utils/elink_common_data_parse_utils.dart';
import 'package:ailink_flutter_demo_1/utils/extensions.dart';
import 'package:ailink_flutter_demo_1/widgets/widget_ble_state.dart';
import 'package:ailink_flutter_demo_1/widgets/widget_operate_btn.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ConnectDevicePage extends StatefulWidget {
  const ConnectDevicePage({super.key, required this.device});
  final BluetoothDevice device;

  @override
  State<ConnectDevicePage> createState() => _ConnectDevicePageState();
}

class _ConnectDevicePageState extends State<ConnectDevicePage> {
  final logList = <String>[];
  final _ailinkPlugin = Ailink();
  final ScrollController _controller = ScrollController();

  BluetoothDevice? _bluetoothDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _onReceiveDataSubscription;

  BluetoothCharacteristic? _dataA6Characteristic;
  late ElinkCommonDataParseUtils _elinkCommonDataParseUtils;

  String _currentWeight = "N/A";
  String _bodyFatData = "N/A";

  bool _isHandshaking = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addLog('addPostFrameCallback');
      _bluetoothDevice = widget.device;
      _setupConnectionListener();
      _connectToDevice();
    });

    _elinkCommonDataParseUtils = ElinkCommonDataParseUtils();
    _elinkCommonDataParseUtils.setElinkCommonDataParseCallback(ElinkCommonDataParseCallback((version) {
      _addLog('onGetBmVersion: $version');
    }));
  }

  void _setupConnectionListener() {
    _connectionStateSubscription = _bluetoothDevice?.connectionState.listen((state) {
      setState(() {
        _isConnected = state == BluetoothConnectionState.connected;
      });
      if (state == BluetoothConnectionState.connected) {
        _addLog('Connected');
        _discoverServices();
      } else {
        _dataA6Characteristic = null;
        _addLog('Disconnected: code(${_bluetoothDevice?.disconnectReason?.code}), desc(${_bluetoothDevice?.disconnectReason?.description})');
        if (!_isHandshaking) {
          _reconnectWithDelay();
        }
      }
    });
  }

  void _connectToDevice() {
    _bluetoothDevice?.connect(timeout: Duration(seconds: 15)).then((_) {
      _addLog('Connection successful');
    }).catchError((error) {
      _addLog('Connection error: $error');
      _reconnectWithDelay();
    });
  }

  void _reconnectWithDelay() {
    Future.delayed(Duration(seconds: 5), () {
      if (mounted && !_isConnected && !_isHandshaking) {
        _addLog('Attempting to reconnect...');
        _connectToDevice();
      }
    });
  }

  void _discoverServices() {
    _bluetoothDevice?.discoverServices().then((services) {
      _addLog('DiscoverServices success: ${services.map((e) => e.serviceUuid).join(',').toUpperCase()}');
      if (services.isNotEmpty) {
        _setNotify(services);
      }
    }).catchError((error) {
      _addLog('DiscoverServices error: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _bluetoothDevice?.advName ?? 'Unknown',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              _isConnected ? 'Connected' : 'Disconnected',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          BleStateWidget(
            bluetoothDevice: _bluetoothDevice,
            onPressed: _connectToDevice,
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OperateBtnWidget(
                onPressed: _isConnected ? () => _restartBleModule(_dataA6Characteristic!) : null,
                title: 'RestartBle',
              ),
              OperateBtnWidget(
                onPressed: _isConnected ? () => _getBmVersion(_dataA6Characteristic!) : null,
                title: 'GetBmVersion',
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OperateBtnWidget(
                onPressed: _isConnected ? () => _setHandShake(_dataA6Characteristic!) : null,
                title: 'SetHandShake (Debug)',
              ),
              OperateBtnWidget(
                onPressed: _isConnected ? () => _clearHandShake(_dataA6Characteristic!) : null,
                title: 'ClearHandShake',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text('Current Weight: $_currentWeight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Body Fat Data: $_bodyFatData', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _controller,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Text(
                    '${DateTime.now()}: \n${logList[index]}',
                    style: TextStyle(
                      color: index % 2 == 0 ? Colors.black : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) {
                return const Divider(height: 0.5, color: Colors.grey);
              },
              itemCount: logList.length,
            ),
          ),
        ],
      ),
    );
  }

  void _setNotify(List<BluetoothService> services) async {
    final service = services.firstWhere((service) => service.serviceUuid.str.equal(ElinkBleCommonUtils.elinkConnectDeviceUuid));
    _addLog('_setNotify characteristics: ${service.characteristics.map((e) => e.uuid).join(',').toUpperCase()}');
    for (var characteristic in service.characteristics) {
      if (characteristic.uuid.str.equal(ElinkBleCommonUtils.elinkNotifyUuid) || characteristic.uuid.str.equal(ElinkBleCommonUtils.elinkWriteAndNotifyUuid)) {
        _addLog('_setNotify characteristics uuid: ${characteristic.uuid}');
        await characteristic.setNotifyValue(true);
        if (characteristic.uuid.str.equal(ElinkBleCommonUtils.elinkWriteAndNotifyUuid)) {
          _onReceiveDataSubscription = characteristic.onValueReceived.listen((data) {
            _addLog('OnValueReceived [${characteristic.uuid.str}]: ${data.toHex()}, checked: ${ElinkCmdUtils.checkElinkCmdSum(data)}');
            if (ElinkBleCommonUtils.isSetHandShakeCmd(data)) {
              _replyHandShake(characteristic, data);
            }
            if (ElinkBleCommonUtils.isGetHandShakeCmd(data)) {
              Future.delayed(const Duration(milliseconds: 500), () async {
                final handShakeStatus = await _ailinkPlugin.checkHandShakeStatus(Uint8List.fromList(data));
                _addLog('handShakeStatus: $handShakeStatus');
                setState(() {
                  _isHandshaking = false;
                });
              });
            }
            _elinkCommonDataParseUtils.parseElinkCommonData(data);
            _processReceivedData(data);
          });

          _dataA6Characteristic = characteristic;
          // Initiate handshake immediately after setting up notifications
          _setHandShake(characteristic);
        }
      }
    }
  }

  Future<void> _processReceivedData(List<int> data) async {
    try {
      final decryptedData = await _ailinkPlugin.decryptBroadcast(Uint8List.fromList(data));
      if (decryptedData != null) {
        final weightData = BroadcastScaleDataUtils().getWeightData(decryptedData);
        if (weightData != null) {
          setState(() {
            _currentWeight = "${weightData.weightStr} ${weightData.weightUnitStr}";
          });
          _addLog('Weight: $_currentWeight');

          if (weightData.status == 0xFF && !weightData.isAdcError) {
            final bodyFatParam = ParamBodyFatData(
                double.parse(weightData.weightStr),
                weightData.adc,
                0,  // You may need to set appropriate values for sex, age, and height
                34,
                170,
                weightData.algorithmId
            );
            final bodyFatJson = await _ailinkPlugin.getBodyFatData(bodyFatParam.toJson());
            if (bodyFatJson != null) {
              final bodyFatData = BodyFatData.fromJson(json.decode(bodyFatJson));
              setState(() {
                _bodyFatData = "BFR: ${bodyFatData.bfr}%, Muscle: ${bodyFatData.rom}%";
              });
              _addLog('Body Fat Data: $_bodyFatData');
            }
          }
        }
      }
    } catch (e) {
      _addLog('Error processing data: $e');
    }
  }

  Future<void> _setHandShake(BluetoothCharacteristic characteristic) async {
    if (_isHandshaking) {
      _addLog('Handshake already in progress');
      return;
    }

    setState(() {
      _isHandshaking = true;
    });
    try {
      Uint8List? data = await _ailinkPlugin.initHandShake();
      if (data != null && data.isNotEmpty) {
        _addLog('_setHandShake: ${data.toHex()}');
        await characteristic.write(data.toList(), withoutResponse: true);
      } else {
        _addLog('Failed to initialize handshake');
        setState(() {
          _isHandshaking = false;
        });
      }
    } catch (e) {
      _addLog('Error during handshake: $e');
      setState(() {
        _isHandshaking = false;
      });
    }
  }

  Future<void> _clearHandShake(BluetoothCharacteristic characteristic) async {
    final data = ElinkCommonCmdUtils.clearElinkHandShake();
    _addLog('_clearHandShake: ${data.toHex()}');
    await characteristic.write(data, withoutResponse: true);
  }

  Future<void> _restartBleModule(BluetoothCharacteristic characteristic) async {
    final data = ElinkCommonCmdUtils.restartElinkBleModule();
    _addLog('_restartBleModule: ${data.toHex()}');
    await characteristic.write(data, withoutResponse: true);
  }

  Future<void> _getBmVersion(BluetoothCharacteristic characteristic) async {
    final data = ElinkCommonCmdUtils.getElinkBmVersion();
    _addLog('_getBmVersion: ${data.toHex()}');
    await characteristic.write(data, withoutResponse: true);
  }

  Future<void> _replyHandShake(BluetoothCharacteristic characteristic, List<int> data) async {
    try {
      Uint8List? replyData = await _ailinkPlugin.getHandShakeEncryptData(Uint8List.fromList(data));
      if (replyData != null && replyData.isNotEmpty) {
        _addLog('_replyHandShake: ${replyData.toHex()}');
        await characteristic.write(replyData.toList(), withoutResponse: true);
      } else {
        _addLog('Failed to generate handshake reply');
      }
    } catch (e) {
      _addLog('Error during handshake reply: $e');
    }
  }

  void _addLog(String log) {
    if (mounted) {
      setState(() {
        logList.insert(0, log);
      });
    }
  }

  @override
  void dispose() {
    _bluetoothDevice?.disconnect();
    _bluetoothDevice = null;
    _dataA6Characteristic = null;
    _onReceiveDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }
}