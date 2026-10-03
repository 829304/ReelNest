import 'server_address.dart';

class ServerDescriptor {
  ServerDescriptor({
    required this.id,
    required this.name,
    required this.apiVersion,
    required List<String> capabilities,
  }) : capabilities = List.unmodifiable(capabilities);

  final String id;
  final String name;
  final String apiVersion;
  final List<String> capabilities;
}

/// Public connection metadata. Passwords and tokens never enter widget state.
class ServerConnection {
  const ServerConnection({
    required this.address,
    required this.server,
    required this.username,
  });

  final ServerAddress address;
  final ServerDescriptor server;
  final String username;
}
