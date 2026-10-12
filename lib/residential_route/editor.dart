import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'connection.dart';

class ResidentialRouteEditor extends StatefulWidget {
  final ResidentialRouteConfig initial;
  final List<String> nodes;
  final Map<String, String> labels;
  final Future<ResidentialRouteOutcome> Function(
    ResidentialRouteConfig config,
    bool connect,
  )
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
  late final _transits = widget.initial.selectedTransits.toSet();
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
    transits: widget.nodes.isEmpty ? const [] : _transits.toList(),
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
      final outcome = await widget.onSave(config, connect);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _status = _label(outcome.name);
      });
      final details = config.enabled && config.selectedTransits.isNotEmpty
          ? '\n${config.nodeName(config.selectedTransits.first)}'
          : '';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('$_status$details'),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _status = _label('failed'));
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(_status!)));
      }
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
            Text('${_label('transit')} (${_transits.length})'),
            SizedBox(
              height: (({...widget.nodes, ..._transits}.length * 64).clamp(
                64,
                280,
              )).toDouble(),
              child: ListView(
                children: [
                  for (final name in {...widget.nodes, ..._transits})
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name),
                      value: _transits.contains(name),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _transits.add(name);
                              } else {
                                _transits.remove(name);
                              }
                              _transit.text = _transits.firstOrNull ?? '';
                              _status = null;
                            }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else
            _field('transit', _transit),
          Text(_label('transitHelp')),
          const SizedBox(height: 24),
          if (_status != null) ...[
            Text(_status!, key: const ValueKey('residential-status')),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: _busy ? null : () => _save(true),
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(_label('working')),
                    ],
                  )
                : Text(_label('connect')),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(false),
            child: Text(_label('save')),
          ),
        ],
      ),
    );
  }
}
