import 'package:material_ui/material_ui.dart';

import 'config.dart';

class ResidentialRouteEditor extends StatefulWidget {
  final ResidentialRouteConfig initial;
  final List<String> nodes;
  final Map<String, String> labels;
  final Future<bool> Function(ResidentialRouteConfig config, bool connect)
  onSave;

  const ResidentialRouteEditor({
    super.key,
    required this.initial,
    required this.nodes,
    required this.labels,
    required this.onSave,
  });

  @override
  State<ResidentialRouteEditor> createState() => _ResidentialRouteEditorState();
}

class _ResidentialRouteEditorState extends State<ResidentialRouteEditor> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  late final _server = TextEditingController(text: widget.initial.server);
  late final _port = TextEditingController(text: '${widget.initial.port}');
  late final _username = TextEditingController(text: widget.initial.username);
  late final _password = TextEditingController(text: widget.initial.password);
  late final _transit = TextEditingController(text: widget.initial.transit);
  late bool _enabled = widget.initial.enabled;
  bool _busy = false;
  bool _showPassword = false;
  String? _status;

  String _label(String key) => widget.labels[key]!;

  @override
  void dispose() {
    _url.dispose();
    _server.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _transit.dispose();
    super.dispose();
  }

  ResidentialRouteConfig _config(bool enabled) => ResidentialRouteConfig(
    enabled: enabled,
    server: _server.text.trim(),
    port: int.tryParse(_port.text) ?? 0,
    username: _username.text,
    password: _password.text,
    transit: _transit.text,
  );

  void _parseUrl() {
    try {
      final config = ResidentialRouteConfig.parseSocksUrl(_url.text);
      _server.text = config.server;
      _port.text = '${config.port}';
      _username.text = config.username;
      _password.text = config.password;
      _url.clear();
      setState(() => _status = null);
    } on FormatException {
      setState(() => _status = _label('urlError'));
    }
  }

  Future<void> _save(bool connect) async {
    final enabled = connect || _enabled;
    if (enabled && !_formKey.currentState!.validate()) return;
    final config = _config(enabled);
    if (enabled) {
      try {
        config.validate();
      } on FormatException {
        setState(() => _status = _label('endpointError'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _status = _label('working');
    });
    try {
      final verified = await widget.onSave(config, connect);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _status = verified
            ? _label(connect ? 'verified' : 'saved')
            : _label('failed');
      });
    } catch (_) {
      if (mounted) setState(() => _status = _label('failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    TextEditingController controller, {
    TextInputType? keyboardType,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() => _status = null),
      decoration: InputDecoration(labelText: _label(key)),
      validator: (value) =>
          (key == 'server' || key == 'port' || key == 'transit') &&
              (value?.isEmpty ?? true)
          ? _label('endpointError')
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_label('description')),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_label('enabled')),
            value: _enabled,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _enabled = value;
                    _status = null;
                  }),
          ),
          _field('url', _url, obscure: true),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _parseUrl,
              child: Text(_label('parse')),
            ),
          ),
          const SizedBox(height: 8),
          _field('server', _server),
          _field('port', _port, keyboardType: TextInputType.number),
          _field('username', _username),
          _field('password', _password, obscure: !_showPassword),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_label('showPassword')),
            value: _showPassword,
            onChanged: _busy
                ? null
                : (value) => setState(() => _showPassword = value ?? false),
          ),
          if (widget.nodes.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: widget.nodes.contains(_transit.text)
                  ? _transit.text
                  : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: _label('transit')),
              items: widget.nodes
                  .map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _transit.text = value ?? '';
                      _status = null;
                    }),
            ),
            const SizedBox(height: 16),
          ] else
            _field('transit', _transit),
          Text(_label('transitHelp')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : () => _save(true),
            child: Text(_label('connect')),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(false),
            child: Text(_label('save')),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, key: const ValueKey('residential-status')),
          ],
        ],
      ),
    );
  }
}
