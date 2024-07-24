import 'dart:async';

import 'package:ailink/ailink.dart';
import 'package:ailink/utils/broadcast_scale_data_utils.dart';
import 'package:ailink/utils/common_extensions.dart';
import 'package:ailink/utils/ble_common_util.dart';
import 'package:ailink/utils/elink_broadcast_data_utils.dart';
import 'package:ailink/model/param_body_fat_data.dart';
import 'package:ailink/model/body_fat_data.dart';
import 'package:ailink_flutter_demo_1/screens/page_connect_device.dart';
import 'package:ailink_flutter_demo_1/utils/constants.dart';
import 'package:ailink_flutter_demo_1/utils/log_utils.dart';
import 'package:ailink_flutter_demo_1/widgets/widget_ble_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ailinkPlugin = Ailink();
  List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    }, onError: (e) {
      LogUtils().log('Scan Error: ${e.toString()}');
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      setState(() {
        _isScanning = state;
      });
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AiLink Secret Tool example app'),
          actions: const [
            BleStateWidget(),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            children: [
              _buildNotSupportedWidget,
              ..._buildScanResultTiles(context),
            ],
          ),
        ),
        floatingActionButton: _buildScanButton(context),
      ),
    );
  }

  Widget get _buildNotSupportedWidget => FutureBuilder<bool>(
        future: FlutterBluePlus.isSupported,
        builder: (context, snapshot) {
          return Visibility(
            visible: !(snapshot.hasData && snapshot.data == true),
            child: const Text(
              'Bluetooth is not supported',
              style: TextStyle(color: Colors.red, fontSize: 18),
            ),
          );
        },
      );

  Widget _buildScanButton(BuildContext context) {
    if (_isScanning) {
      return FloatingActionButton(
        child: const Icon(Icons.stop),
        onPressed: onStopPressed,
        backgroundColor: Colors.red,
      );
    } else {
      return FloatingActionButton(
        child: const Text("SCAN"),
        onPressed: onScanPressed,
      );
    }
  }

  Future onScanPressed() async {
    try {
      _systemDevices = await FlutterBluePlus.systemDevices;
    } catch (e) {
      LogUtils().log('System Devices Error: ${e.toString()}');
    }
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [
          Guid(ElinkBleCommonUtils.elinkBroadcastDeviceUuid),
          Guid(ElinkBleCommonUtils.elinkConnectDeviceUuid)
        ],
      );
    } catch (e) {
      LogUtils().log('Start Scan Error: ${e.toString()}');
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      LogUtils().log('Stop Scan Error: ${e.toString()}');
    }
  }

  Future onRefresh() {
    if (!_isScanning) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults.map((r) => _buildScanResultTile(r, context)).toList();
  }

  Widget _buildScanResultTile(ScanResult r, BuildContext context) {
    List<int> manufacturerData =
        getManufacturerData(r.advertisementData.manufacturerData);
    final uuids = r.advertisementData.serviceUuids
        .map((uuid) => uuid.str.toUpperCase())
        .toList();
    final isBroadcastDevice = ElinkBleCommonUtils.isBroadcastDevice(uuids);
    final elinkBleData = ElinkBroadcastDataUtils.getElinkBleData(
        manufacturerData,
        isBroadcastDevice: isBroadcastDevice);
    LogUtils().log("Is Broadcast data: $isBroadcastDevice");

    return ListTile(
      title: Text(
        r.device.advName.isEmpty ? 'Unknown' : r.device.advName,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MAC: ${elinkBleData.mac}'),
          Text(
              'CID: ${elinkBleData.cidStr}(${elinkBleData.cid}), VID: ${elinkBleData.vidStr}(${elinkBleData.vid}), PID: ${elinkBleData.pidStr}(${elinkBleData.pid})'),
          Text('UUIDs: ${uuids.join(', ').toUpperCase()}'),
          Text('Data: ${manufacturerData.toHex()}'),
          isBroadcastDevice
              ? _buildBroadcastWidget(manufacturerData)
              : _buildConnectDeviceWidget(r, context),
        ],
      ),
      trailing: Text(r.rssi.toString()),
    );
  }

  Widget _buildBroadcastWidget(List<int> manufacturerData) {
    return FutureBuilder(
      future: _ailinkPlugin.decryptBroadcast(
        Uint8List.fromList(manufacturerData),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final weightData =
              BroadcastScaleDataUtils().getWeightData(snapshot.data);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ParseResult: ${snapshot.data?.toHex()}'),
              Text('Status: ${weightData?.statusStr}'),
              Text('Impedance value: ${weightData?.adc}'),
              Text(
                  'WeightData: ${weightData?.weightStr} ${weightData?.weightUnitStr}'),
              if (weightData != null && weightData.isAdcError != true)
                FutureBuilder(
                  future: _ailinkPlugin.getBodyFatData(ParamBodyFatData(
                          double.parse(weightData.weightStr),
                          weightData.adc,
                          0,
                          34,
                          170,
                          weightData.algorithmId)
                      .toJson()),
                  builder: (context, snapshot) {
                    if (weightData.status == 0xFF &&
                        snapshot.hasData &&
                        snapshot.data != null) {
                      return Text(
                          'BodyFatData: ${BodyFatData.fromJson(json.decode(snapshot.data!)).toJson()}');
                    }
                    return Container();
                  },
                ),
            ],
          );
        } else {
          return Container();
        }
      },
    );
  }

  Widget _buildConnectDeviceWidget(
      ScanResult scanResult, BuildContext context) {
    final device = scanResult.device;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        InkWell(
          onTap: () {
            FlutterBluePlus.stopScan();
            // Navigator.pushNamed(context, page_connect_device,
            //     arguments: device);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>  ConnectDevicePage(device: device,),
              ),
            );
          },
          child: Container(
            color: Colors.black,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Text(
                'Connect',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        )
      ],
    );
  }

  List<int> getManufacturerData(Map<int, List<int>> data) {
    return data.entries
        .map((entry) {
          List<int> manufacturerData = intToLittleEndian(entry.key, 2);
          List<int> results = List.empty(growable: true);
          results.addAll(manufacturerData);
          results.addAll(entry.value);
          return results;
        })
        .expand((element) => element)
        .toList();
  }

  List<int> intToLittleEndian(int value, int length) {
    List<int> result = List<int>.filled(length, 0);
    for (int i = 0; i < length; i++) {
      result[i] = (value >> (i * 8)) & 0xFF;
    }
    return result;
  }
}
