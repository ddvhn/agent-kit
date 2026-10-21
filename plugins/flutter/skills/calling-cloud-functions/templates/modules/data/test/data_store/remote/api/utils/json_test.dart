import 'package:data/src/data_store/remote/api/utils/json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts nested maps and lists to JSON objects', () {
    final Object value = <Object?, Object?>{
      'id': 'foo-1',
      'bar': <Object?, Object?>{'rank': 1},
      'tags': [
        <Object?, Object?>{'name': 'a'},
        'b',
      ],
    };
    expect(jsonObject(value), {
      'id': 'foo-1',
      'bar': {'rank': 1},
      'tags': [
        {'name': 'a'},
        'b',
      ],
    });
  });

  test('anything else is a FormatException', () {
    expect(() => jsonObject('text'), throwsFormatException);
    expect(() => jsonObject(null), throwsFormatException);
  });
}
