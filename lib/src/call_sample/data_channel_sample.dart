import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:fluttertoast/fluttertoast.dart';

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
  List<String> _allowedExtension = ['.jpeg', '.png', '.pdf'];
  String _lastExtension = '';

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
        if (data.isBinary) {
          print(data.binary.toString());
        } else {
          print(data.text.toString());
        }

        setState(() {
          if (data.isBinary) {
            _text.add(
              MessageBean(
                  type: _lastExtension,
                  text: '',
                  bytes: data.binary,
                  shouldHide: false),
            );
            _lastExtension = '';
          } else {
            if (!data.text.startsWith('.')) {
              _text.add(
                MessageBean(
                    type: 'text',
                    text: data.text,
                    bytes: null,
                    shouldHide: false),
              );
            } else {
              _lastExtension = data.text;
            }
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
                bool shouldHide = messageBean.shouldHide;
                if (!shouldHide) {
                  switch (messageBean.type) {
                    case '.jpeg':
                    case '.png':
                      return Container(
                        margin: EdgeInsets.symmetric(vertical: 8.0),
                        child: Image.memory(_text[index].bytes),
                      );
                      break;
                    case '.pdf':
                      return Container(
                        margin: EdgeInsets.symmetric(vertical: 8.0),
                        child: Icon(
                          Icons.picture_as_pdf,
                          size: 50.0,
                        ),
                      );
                    default:
                      if (_text[index]
                              .text
                              .toLowerCase()
                              .contains('https://') ||
                          _text[index].text.toLowerCase().contains('http://')) {
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 8.0),
                          child: Linkify(
                            onOpen: (link) => print("Clicked ${link.url}!"),
                            text: _text[index].text,
                          ),
                        );
                      } else {
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(_text[index].text),
                        );
                      }
                  }
                } else {
                  return Container(
                    height: 0,
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
                      String extension =
                          file.path.substring(file.path.lastIndexOf('.'));
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
                        _dataChannel
                            .send(RTCDataChannelMessage(extension))
                            .then((response) {
                          print('Text Success');
                        }, onError: (e) {
                          print(e.toString());
                        });

                        _dataChannel
                            .send(RTCDataChannelMessage.fromBinary(binary))
                            .then((response) {
                          print('Binary Success');
                        }, onError: (e) {
                          print(e.toString());
                        });

//                        await Future.delayed(Duration(seconds: 5), () {
//                          _dataChannel
//                              .send(RTCDataChannelMessage.fromBinary(binary));
//                        });
//
////                        _text.add(MessageBean(
////                            type: 'text',
////                            text: extension,
////                            bytes: null,
////                            shouldHide: true));
////
////                        _text.add(MessageBean(
////                            type: extension,
////                            text: '',
////                            bytes: binary,
////                            shouldHide: false));
//
//                        setState(() {});
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
                      _text.add(MessageBean(
                          type: 'text',
                          text: text,
                          bytes: null,
                          shouldHide: false));
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
