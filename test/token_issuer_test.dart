import 'package:nectar_sts_dart/src/exceptions/exceptions.dart';
import 'package:nectar_sts_dart/src/server/token_issuer.dart';
import 'package:test/test.dart';

void main() {
  group('PrismIssuer', () {
    final issuer = PrismIssuer(
      const PrismConfig(
        host: '10.0.0.1',
        port: 9000,
        realm: 'utility',
        username: 'vending',
        password: 'pw',
      ),
    );

    test('name advertises host:port', () {
      expect(issuer.name, 'PrismIssuer(10.0.0.1:9000)');
    });

    test('generateToken throws NotImplementedException', () {
      expect(
        () => issuer.generateToken('req-1', {}),
        throwsA(isA<NotImplementedException>()),
      );
    });

    test('decodeToken throws NotImplementedException', () {
      expect(
        () => issuer.decodeToken('req-1', '00000000000000000000', {}),
        throwsA(isA<NotImplementedException>()),
      );
    });
  });
}
