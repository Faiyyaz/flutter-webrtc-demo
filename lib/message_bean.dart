import 'dart:typed_data';

class MessageBean {
  String type;
  Uint8List bytes;
  String text;
  bool shouldHide;

  MessageBean({this.type, this.text, this.bytes, this.shouldHide});
}
