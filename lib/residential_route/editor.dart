import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'connection.dart';

class ResidentialRouteEditor extends StatefulWidget {
  final ResidentialRouteConfig initial;
  final List<String> nodes;
  final Map<String, String> labels;
  final Widget Function(BuildContext, String, bool, VoidCallback?)? nodeBuilder;
  final double? nodeHeight;
  final Future<void> Function()? onTestNodes;
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
    this.nodeBuilder,
    this.nodeHeight,
    this.onTestNodes,
  });

  @override
  State<ResidentialRouteEditor> createState() => _ResidentialRouteEditorState();
}

class _ResidentialRouteEditorState extends State<ResidentialRouteEditor> {
  late final _url = TextEditingController(text: widget.initial.socksUrl);
  late final _transits = widget.initial.selectedTransits.toSet();
  late bool _enabled = widget.initial.enabled;
  bool _busy = false;
  bool _testing = false;
  String? _status;

  String _label(String key) => widget.labels[key]!;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  ResidentialRouteConfig _config(bool enabled) {
    ResidentialRouteConfig endpoint;
    try {
      endpoint = ResidentialRouteConfig.parseSocksUrl(_url.text);
    } on FormatException {
      if (enabled) rethrow;
      endpoint = widget.initial;
    }
    return ResidentialRouteConfig(
      enabled: enabled,
      server: endpoint.server,
      port: endpoint.port,
      username: endpoint.username,
      password: endpoint.password,
      transit: _transits.firstOrNull ?? '',
      transits: _transits.toList(),
    );
  }

  Future<void> _save(bool connect) async {
    final enabled = connect || _enabled;
    ResidentialRouteConfig config;
    try {
      config = _config(enabled);
    } on FormatException {
      setState(() => _status = _label('urlError'));
      return;
    }
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

  Widget _urlField() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _url,
      enabled: !_busy,
      keyboardType: TextInputType.url,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() => _status = null),
      decoration: InputDecoration(labelText: _label('url')),
    ),
  );

  Future<void> _testNodes() async {
    setState(() => _testing = true);
    try {
      await widget.onTestNodes!();
    } catch (_) {
      if (mounted) setState(() => _status = _label('delayFailed'));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _node(BuildContext context, String name) {
    final selected = _transits.contains(name);
    final onTap = _busy
        ? null
        : () => setState(() {
            if (selected) {
              _transits.remove(name);
            } else {
              _transits.add(name);
            }
            _status = null;
          });
    return Semantics(
      selected: selected,
      child:
          widget.nodeBuilder?.call(context, name, selected, onTap) ??
          Card(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(name),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
        _urlField(),
        Text(_label('urlHelp')),
        const SizedBox(height: 16),
        if ({...widget.nodes, ..._transits}.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('${_label('transit')} (${_transits.length})'),
              ),
              if (widget.onTestNodes != null)
                TextButton(
                  onPressed: _busy || _testing ? null : _testNodes,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_testing) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(_label('testNodes')),
                    ],
                  ),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final names = {...widget.nodes, ..._transits}.toList();
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (constraints.maxWidth / 240).floor().clamp(
                    1,
                    6,
                  ),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: widget.nodeHeight ?? 100,
                ),
                itemCount: names.length,
                itemBuilder: (context, index) => _node(context, names[index]),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        Text(_label('transitHelp')),
        const SizedBox(height: 24),
        if (_status != null) ...[
          Text(_status!, key: const ValueKey('residential-status')),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _busy || _testing ? null : () => _save(true),
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
          onPressed: _busy || _testing ? null : () => _save(false),
          child: Text(_label('save')),
        ),
      ],
    );
  }
}
