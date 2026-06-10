/// Static OpenAPI 3.0 description of the NectarAPI-compatible REST
/// surface exposed by [buildApiHandler]. Served verbatim by
/// `GET /openapi.json` so callers (and tools like swagger-ui /
/// redoc / curl --next /generated SDKs) can introspect the contract
/// without scraping the source.
///
/// This is intentionally a curated map literal (not auto-generated
/// from shelf_router) — the router's `<param>` syntax doesn't carry
/// type / description metadata. Keep this file in sync when adding
/// routes; the test in `test/openapi_spec_test.dart` only checks
/// that the top-level shape is valid and the major paths are listed.
library;

Map<String, dynamic> openApiSpec() => {
      'openapi': '3.0.3',
      'info': {
        'title': 'nectar_sts_dart',
        'version': '0.1.0',
        'description':
            'STS prepaid-electricity token service. Issues, decodes and '
                'verifies tokens through a VirtualHsm (in-process) or Prism HSM '
                '(Thrift) backend. All responses use the ApiResponse envelope.',
      },
      'servers': [
        {'url': 'http://localhost:2000', 'description': 'local dev'},
      ],
      'components': {
        'securitySchemes': {
          'bearerAuth': {
            'type': 'http',
            'scheme': 'bearer',
            'description': 'Required when the server was started with '
                'NECTAR_API_TOKEN set. Omitted requests get 401.',
          },
        },
        'parameters': {
          'XRequestId': {
            'in': 'header',
            'name': 'X-Request-Id',
            'required': false,
            'schema': {'type': 'string', 'pattern': r'^[A-Za-z0-9._-]{1,128}$'},
            'description':
                'Optional caller-supplied request id. Forwarded to Prism '
                    'as the Thrift messageId and echoed on the response. '
                    'Required for safe idempotency replay via '
                    'GET /v1/tokens/results/{originalRequestId}.',
          },
        },
        'schemas': {
          'ApiResponse': {
            'type': 'object',
            'required': ['status', 'request_id'],
            'properties': {
              'status': {
                'type': 'object',
                'required': ['code', 'message'],
                'properties': {
                  'code': {'type': 'integer'},
                  'message': {'type': 'string'},
                },
              },
              'request_id': {'type': 'string'},
              'data': {'description': 'Endpoint-specific payload.'},
            },
          },
          'IssuedToken': {
            'type': 'object',
            'properties': {
              'tokenNo': {'type': 'string'},
              'subclass': {'type': 'integer'},
              'description': {'type': 'string'},
              'scaledAmount': {'type': 'string'},
            },
          },
          'VirtualHsmParams': {
            'type': 'object',
            'description':
                'Meter context + token control. Either supply the full '
                    'fingerprint (supply_group_code, key_revision_no, '
                    'tariff_index, decoder_reference_number, '
                    'issuer_identification_no, decoder_key_generation_algorithm, '
                    'encryption_algorithm, key_type) or shortcut via '
                    'meter_serial when a meter registry is configured.',
            'properties': {
              'meter_serial': {'type': 'string'},
              'decoder_reference_number': {'type': 'string'},
              'issuer_identification_no': {'type': 'string'},
              'supply_group_code': {'type': 'string'},
              'tariff_index': {'type': 'string'},
              'key_revision_no': {'type': 'integer'},
              'decoder_key_generation_algorithm': {'type': 'string'},
              'encryption_algorithm': {'type': 'string'},
              'key_type': {'type': 'integer'},
              'class': {'type': 'string'},
              'subclass': {'type': 'string'},
              'amount': {'type': 'number'},
              'token_id': {'type': 'string'},
              'random_no': {'type': 'integer'},
              'base_date': {'type': 'string'},
              'request_id': {'type': 'string'},
            },
          },
        },
        'responses': {
          'Envelope': {
            'description': 'Standard ApiResponse envelope.',
            'content': {
              'application/json': {
                'schema': {r'$ref': '#/components/schemas/ApiResponse'},
              },
            },
          },
        },
      },
      'security': [
        {'bearerAuth': <Object>[]},
      ],
      'paths': {
        '/healthz': {
          'get': {
            'summary': 'Liveness probe (no auth).',
            'security': <Map<String, Object>>[],
            'responses': {'200': _ref('Envelope')},
          },
        },
        '/v1/health/backend': {
          'get': {
            'summary': 'Issuer-backend health (Prism / VirtualHsm).',
            'responses': {'200': _ref('Envelope'), '503': _ref('Envelope')},
          },
        },
        '/v1/status/nodes': {
          'get': {
            'summary': 'Per-node status (Prism cluster info + alerts).',
            'responses': {'200': _ref('Envelope'), '503': _ref('Envelope')},
          },
        },
        '/v1/tokens': {
          'post': _issueOp('Generate a Class 0/0 electricity-credit token.'),
          'get': {
            'summary': 'List previously issued tokens (audit log).',
            'parameters': [
              {
                'in': 'query',
                'name': 'iin',
                'schema': {'type': 'string'},
              },
              {
                'in': 'query',
                'name': 'iain',
                'schema': {'type': 'string'},
              },
            ],
            'responses': {'200': _ref('Envelope')},
          },
        },
        '/v1/tokens/key-change': {
          'post': _issueOp(
            'Issue the atomic Key Change Token bundle (2 entries for '
            'STA/DEA, 4 for MISTY1).',
          ),
        },
        '/v1/tokens/mse/clear-credit': {
          'post': _issueOp('Class 2 / subclass 1 — ClearCredit.'),
        },
        '/v1/tokens/mse/clear-tamper': {
          'post': _issueOp('Class 2 / subclass 5 — ClearTamper.'),
        },
        '/v1/tokens/mse/set-max-power': {
          'post': _issueOp(
            'Class 2 / subclass 0 — SetMaxPower. Body adds '
            'maximum_power_limit (kW).',
          ),
        },
        '/v1/tokens/mse/set-tariff': {
          'post': _issueOp(
            'Class 2 / subclass 2 — SetTariff. Body adds tariff_rate.',
          ),
        },
        '/v1/tokens/mse/set-flag': {
          'post': _issueOp(
            'Class 2 / subclass 10 — SetFlag. Body adds flag_type (0..11) '
            'and flag_value (0|1).',
          ),
        },
        '/v1/tokens/meter-test': {
          'post': _issueOp(
            'Class 1 / 3 NMSE meter-test token. Body: subclass (int), '
            'control (int), manufacturer_code (int).',
          ),
        },
        '/v1/tokens/credit/electricity-currency': {
          'post': _issueOp('Class 0 / subclass 4 — ElectricityCurrency.'),
        },
        '/v1/tokens/credit/water-currency': {
          'post': _issueOp('Class 0 / subclass 5 — WaterCurrency.'),
        },
        '/v1/tokens/credit/gas-currency': {
          'post': _issueOp('Class 0 / subclass 6 — GasCurrency.'),
        },
        '/v1/tokens/credit/time-currency': {
          'post': _issueOp('Class 0 / subclass 7 — TimeCurrency.'),
        },
        '/v1/tokens/results/{originalRequestId}': {
          'get': {
            'summary': 'Idempotency replay — re-fetch tokens previously issued '
                'for an earlier request id whose reply was lost.',
            'parameters': [
              {
                'in': 'path',
                'name': 'originalRequestId',
                'required': true,
                'schema': {'type': 'string'},
              },
            ],
            'responses': {'200': _ref('Envelope'), '404': _ref('Envelope')},
          },
        },
        '/v1/tokens/{tokenNo}/verify': {
          'post': {
            'summary': 'Non-throwing token validation. Always 200 on a completed '
                'verify; result is in data.validationResult and data.isValid.',
            'parameters': [
              {
                'in': 'path',
                'name': 'tokenNo',
                'required': true,
                'schema': {'type': 'string'},
              },
              {r'$ref': '#/components/parameters/XRequestId'},
            ],
            'requestBody': _virtualHsmBody(),
            'responses': {'200': _ref('Envelope')},
          },
        },
        '/v1/tokens/{tokenNo}': {
          'get': {
            'summary': 'Look up a previously issued token by token number.',
            'parameters': [
              {
                'in': 'path',
                'name': 'tokenNo',
                'required': true,
                'schema': {'type': 'string'},
              },
            ],
            'responses': {'200': _ref('Envelope'), '404': _ref('Envelope')},
          },
          'post': {
            'summary':
                'Decode a token (raises on invalid). Body is the standard '
                    'VirtualHsmParams shape (meter context).',
            'parameters': [
              {
                'in': 'path',
                'name': 'tokenNo',
                'required': true,
                'schema': {'type': 'string'},
              },
              {r'$ref': '#/components/parameters/XRequestId'},
            ],
            'requestBody': _virtualHsmBody(),
            'responses': {'200': _ref('Envelope'), '400': _ref('Envelope')},
          },
        },
        '/v1/meters': {
          'post': {
            'summary': 'Register a meter in the local registry.',
            'requestBody': _virtualHsmBody(),
            'responses': {'200': _ref('Envelope'), '400': _ref('Envelope')},
          },
          'get': {
            'summary': 'List registered meters.',
            'responses': {'200': _ref('Envelope')},
          },
        },
        '/v1/meters/{serial}': {
          'get': {
            'summary': 'Get a registered meter by serial.',
            'parameters': [
              {
                'in': 'path',
                'name': 'serial',
                'required': true,
                'schema': {'type': 'string'},
              },
            ],
            'responses': {'200': _ref('Envelope'), '404': _ref('Envelope')},
          },
          'delete': {
            'summary': 'De-register a meter.',
            'parameters': [
              {
                'in': 'path',
                'name': 'serial',
                'required': true,
                'schema': {'type': 'string'},
              },
            ],
            'responses': {'200': _ref('Envelope'), '404': _ref('Envelope')},
          },
        },
        '/openapi.json': {
          'get': {
            'summary': 'This document.',
            'security': <Map<String, Object>>[],
            'responses': {
              '200': {
                'description': 'OpenAPI 3.0 spec',
                'content': {
                  'application/json': {
                    'schema': {'type': 'object'},
                  },
                },
              },
            },
          },
        },
      },
    };

Map<String, Object?> _ref(String name) => {
      r'$ref': '#/components/responses/$name',
    };

Map<String, Object?> _virtualHsmBody() => {
      'required': true,
      'content': {
        'application/json': {
          'schema': {r'$ref': '#/components/schemas/VirtualHsmParams'},
        },
      },
    };

Map<String, Object?> _issueOp(String summary) => {
      'summary': summary,
      'parameters': [
        {r'$ref': '#/components/parameters/XRequestId'},
      ],
      'requestBody': _virtualHsmBody(),
      'responses': {
        '200': _ref('Envelope'),
        '400': _ref('Envelope'),
        '409': _ref('Envelope'),
        '501': _ref('Envelope'),
      },
    };
