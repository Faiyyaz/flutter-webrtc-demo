import 'dart:typed_data';

class MessageBean {
  String type;
  Uint8List bytes;
  String text;

  MessageBean({this.type, this.text, this.bytes});
}
