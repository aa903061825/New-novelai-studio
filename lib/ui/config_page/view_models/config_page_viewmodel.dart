import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';

class ConfigPageViewmodel {
  final PayloadConfig? _payloadConfig;

  PayloadConfig get payloadConfig => _payloadConfig ?? GetIt.I();

  ConfigPageViewmodel({PayloadConfig? payloadConfig})
      : _payloadConfig = payloadConfig;
}
