import 'package:flutter/widgets.dart';

void main() => runApp(const HelloWorld());

class HelloWorld extends StatelessWidget {
  const HelloWorld({super.key});

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0xffffffff),
      child: Center(
        child: Text('Hello, world!', style: TextStyle(
          fontSize: 32, color: Color(0xff202124), fontFamily: '.AppleSystemUIFont',
        )),
      ),
    ),
  );
}
