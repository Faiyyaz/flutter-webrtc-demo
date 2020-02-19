import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mime/mime.dart';

import '../../message_bean.dart';
import 'signaling.dart';

class DataChannelSample extends StatefulWidget {
  static String tag = 'call_sample';

  final String ip;

  DataChannelSample({Key key, @required this.ip}) : super(key: key);

  @override
  _DataChannelSampleState createState() =>
      new _DataChannelSampleState(serverIP: ip);
}

class _DataChannelSampleState extends State<DataChannelSample> {
  Signaling _signaling;
  List<dynamic> _peers;
  var _selfId;
  bool _inCalling = false;
  final String serverIP;
  RTCDataChannel _dataChannel;
  Timer _timer;
  List<MessageBean> _text = [];
  TextEditingController _controller = TextEditingController();
  List<String> _allowedExtension = [
    'image/jpeg',
    'image/png',
    'application/pdf'
  ];

  _DataChannelSampleState({Key key, @required this.serverIP});

  @override
  initState() {
    super.initState();
    _connect();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling.close();
    if (_timer != null) {
      _timer.cancel();
    }
  }

  void _connect() async {
    if (_signaling == null) {
      _signaling = new Signaling(serverIP)..connect();

      _signaling.onDataChannelMessage = (dc, RTCDataChannelMessage data) {
        setState(() {
          if (data.isBinary) {
            String extension = lookupMimeType('test', headerBytes: data.binary);
            _text.add(
                MessageBean(type: extension, text: '', bytes: data.binary));
          } else {
            _text.add(MessageBean(type: 'text', text: data.text, bytes: null));
          }
        });
      };

      _signaling.onDataChannel = (channel) {
        _dataChannel = channel;
      };

      _signaling.onStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.CallStateNew:
            {
              this.setState(() {
                _inCalling = true;
              });
              break;
            }
          case SignalingState.CallStateBye:
            {
              this.setState(() {
                _inCalling = false;
              });
              if (_timer != null) {
                _timer.cancel();
                _timer = null;
              }
              _dataChannel = null;
              _text = [];
              break;
            }
          case SignalingState.CallStateInvite:
          case SignalingState.CallStateConnected:
          case SignalingState.CallStateRinging:
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling.onPeersUpdate = ((event) {
        this.setState(() {
          _selfId = event['self'];
          _peers = event['peers'];
        });
      });
    }
  }

  _invitePeer(context, peerId) async {
    if (_signaling != null && peerId != _selfId) {
      _signaling.invite(peerId, 'data', false, false);
    }
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling.bye();
    }
  }

  _buildRow(context, peer) {
    var self = (peer['id'] == _selfId);
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(self
            ? peer['name'] + '[Your self]'
            : peer['name'] + '[' + peer['user_agent'] + ']'),
        onTap: () => _invitePeer(context, peer['id']),
        trailing: Icon(Icons.sms),
        subtitle: Text('id: ' + peer['id']),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Data Channel Sample'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButton: _inCalling
          ? FloatingActionButton(
              onPressed: _hangUp,
              tooltip: 'Hangup',
              child: new Icon(Icons.call_end),
            )
          : null,
      body: _inCalling
          ? new ListView.builder(
              shrinkWrap: true,
              itemCount: _text.length,
              itemBuilder: (context, index) {
                MessageBean messageBean = _text[index];
                switch (messageBean.type) {
                  case 'image/jpeg':
                  case 'image/png':
                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 8.0),
                      child: Image.memory(_text[index].bytes),
                    );
                    break;
                  case 'application/pdf':
                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 8.0),
                      child: Icon(
                        Icons.picture_as_pdf,
                        size: 50.0,
                      ),
                    );
                  default:
                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(_text[index].text),
                    );
                }
              })
          : new ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_peers != null ? _peers.length : 0),
              itemBuilder: (context, i) {
                return _buildRow(context, _peers[i]);
              }),
      persistentFooterButtons: <Widget>[
        Visibility(
          visible: _inCalling,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  icon: Icon(Icons.file_upload),
                  onPressed: () async {
                    File file = await FilePicker.getFile();
                    if (!mounted) return;
                    if (_dataChannel != null) {
                      Uint8List binary = file.readAsBytesSync();
                      _dataChannel
                          .send(RTCDataChannelMessage.fromBinary(binary));
                      String extension =
                          lookupMimeType('test', headerBytes: binary);

                      if (!_allowedExtension.contains(extension)) {
                        Fluttertoast.showToast(
                            msg: "File format not supported",
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.CENTER,
                            timeInSecForIos: 1,
                            backgroundColor: Colors.red,
                            textColor: Colors.white,
                            fontSize: 16.0);
                      } else {
                        _text.add(MessageBean(
                            type: extension, text: '', bytes: binary));
                        setState(() {});
                      }
                    }
                  },
                  iconSize: 24.0,
                ),
                Container(
                  width: MediaQuery.of(context).size.width * 0.65,
                  child: TextField(
                    autofocus: false,
                    autocorrect: false,
                    controller: _controller,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    if (_dataChannel != null) {
                      String text = _controller.text;
                      _controller.clear();
                      _dataChannel.send(RTCDataChannelMessage(text));
                      _text.add(
                          MessageBean(type: 'text', text: text, bytes: null));
                      setState(() {});
                    }
                  },
                  iconSize: 24.0,
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}
