import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import 'package:benzmobitraq_mobile/core/constants/app_constants.dart';

/// Selection returned by [PlacesAutocompleteField] when the user picks
/// (or types) something. Either:
///   - [placeId] + [name] + [address] are set (user picked an autocomplete
///     row from Google), or
///   - only [freeText] is set (user typed something free-form and didn't
///     pick a suggestion — e.g. "Personal errand" / "Lunch break").
///
/// Both fields are nullable so a caller can detect "user typed something
/// but didn't pick a place" and store both: the free text shows on the
/// UI, the missing placeId tells downstream code there's nothing to bind.
class PlacesSelection {
  final String? placeId;
  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? freeText;

  const PlacesSelection({
    this.placeId,
    this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.freeText,
  });

  /// What we save into shift_sessions.purpose. Place name beats free text.
  String get displayLabel {
    if (name != null && name!.isNotEmpty) return name!;
    return (freeText ?? '').trim();
  }

  bool get isEmpty => (placeId == null || placeId!.isEmpty) &&
      (freeText == null || freeText!.trim().isEmpty);
}

/// Google Places Autocomplete textbox.
///
/// - Debounces input by 300ms so we don't burn through the Autocomplete
///   session quota on every keystroke.
/// - Uses Autocomplete Session Tokens (free under India pricing) so the
///   subsequent Place Details call is billed as part of the session.
/// - Falls back gracefully to a plain text input if there's no internet
///   or the key is unset — user can still type any purpose.
/// - Biases results to the user's current location (passed in) so an
///   employee in Manesar sees Manesar businesses first.
class PlacesAutocompleteField extends StatefulWidget {
  final double? biasLatitude;
  final double? biasLongitude;
  final ValueChanged<PlacesSelection> onChanged;
  final String hintText;
  final int maxLength;

  const PlacesAutocompleteField({
    super.key,
    this.biasLatitude,
    this.biasLongitude,
    required this.onChanged,
    this.hintText = 'Search customer, site, or type a purpose',
    this.maxLength = 120,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _logger = Logger();
  final _layerLink = LayerLink();

  Timer? _debounce;
  List<_Prediction> _predictions = const [];
  bool _loading = false;
  String? _sessionToken;
  OverlayEntry? _overlay;
  /// Human-readable last error so the user actually sees WHY no
  /// suggestions are showing instead of staring at an empty box.
  /// Cleared on a successful request. Common values:
  ///   - 'Places API not enabled on this Google Cloud project'
  ///   - 'API key invalid or restricted to a different package/SHA-1'
  ///   - 'Daily quota exceeded'
  ///   - 'No internet'
  String? _lastError;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
  ));

  @override
  void initState() {
    super.initState();
    _sessionToken = _newSessionToken();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _ctrl.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      // Keep the overlay open briefly so a tap on a suggestion still
      // registers. The overlay's own onTap removes it.
      Future.delayed(const Duration(milliseconds: 150), _removeOverlay);
    } else if (_predictions.isNotEmpty) {
      _showOverlay();
    }
  }

  String? _apiKey() {
    // Mobile uses the SAME browser-style key. Restrict it in Google Cloud
    // to "Android apps" with your package + SHA-1, plus enabled APIs:
    // Places API. Geocoding/Roads run server-side, never with this key.
    final fromConst = AppConstants.googlePlacesApiKey;
    if (fromConst.isNotEmpty) return fromConst;
    return null;
  }

  Future<void> _fetchPredictions(String input) async {
    if (input.trim().length < 2) {
      setState(() {
        _predictions = const [];
        _lastError = null;
      });
      _removeOverlay();
      return;
    }
    final key = _apiKey();
    if (key == null) {
      setState(() => _lastError = 'No API key configured');
      _showOverlay();
      return;
    }

    setState(() {
      _loading = true;
      _lastError = null;
    });
    try {
      final params = <String, String>{
        'input': input,
        'key': key,
        'sessiontoken': _sessionToken!,
        // India bias keeps the rest of the world out of the suggestions.
        'components': 'country:in',
      };
      if (widget.biasLatitude != null && widget.biasLongitude != null) {
        params['location'] = '${widget.biasLatitude},${widget.biasLongitude}';
        params['radius'] = '15000'; // 15 km bias circle
      }
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: params,
      );
      if (res.statusCode != 200 || res.data == null) {
        _logger.w('Places Autocomplete HTTP ${res.statusCode}');
        if (mounted) {
          setState(() =>
              _lastError = 'Network error (HTTP ${res.statusCode})');
          _showOverlay();
        }
        return;
      }
      final body = res.data!;
      // Google ALWAYS returns a `status` field. We MUST surface it —
      // 'REQUEST_DENIED' / 'OVER_QUERY_LIMIT' / 'INVALID_REQUEST' all
      // come back with HTTP 200 + an empty predictions array, which
      // looks exactly like "no matches" if we don't read the status.
      final status = body['status'] as String?;
      final errorMsg = body['error_message'] as String?;
      _logger.i(
          'Places Autocomplete: status=$status results=${(body['predictions'] as List?)?.length ?? 0} input="$input"');
      if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
        final msg = _humanError(status, errorMsg);
        _logger.w('Places Autocomplete: $status — $errorMsg');
        if (mounted) {
          setState(() => _lastError = msg);
          _showOverlay();
        }
        return;
      }
      final preds = (body['predictions'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(_Prediction.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _predictions = preds);
      if (_focus.hasFocus) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } catch (e) {
      _logger.w('Places Autocomplete error: $e');
      if (mounted) {
        setState(() => _lastError = 'No internet or request failed');
        _showOverlay();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _humanError(String status, String? googleMessage) {
    switch (status) {
      case 'REQUEST_DENIED':
        // Most common: Places API not enabled on the Google Cloud
        // project, OR the API key has Application restrictions that
        // exclude this APK's package/SHA-1.
        return 'Search unavailable: API key issue. '
            '${googleMessage ?? "Enable Places API and check key restrictions."}';
      case 'OVER_QUERY_LIMIT':
        return 'Daily search quota reached. Try again tomorrow.';
      case 'INVALID_REQUEST':
        return 'Search failed: invalid request.';
      case 'UNKNOWN_ERROR':
        return 'Search service temporarily unavailable. Try again.';
      default:
        return 'Search failed ($status).';
    }
  }

  Future<void> _selectPrediction(_Prediction p) async {
    _ctrl.text = p.primary;
    _ctrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    _removeOverlay();
    setState(() => _predictions = const []);

    // Place Details fetch (fields chosen to stay on the IDs-only-ish
    // billing tier where possible). Same session token so this is
    // billed as part of the autocomplete session, not a fresh call.
    final key = _apiKey();
    PlacesSelection selection = PlacesSelection(
      placeId: p.placeId,
      name: p.primary,
      address: p.secondary,
      freeText: p.primary,
    );
    if (key != null) {
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': p.placeId,
            'key': key,
            'sessiontoken': _sessionToken!,
            'fields': 'place_id,name,formatted_address,geometry/location',
          },
        );
        if (res.statusCode == 200 && res.data != null) {
          final r = res.data!['result'] as Map<String, dynamic>?;
          if (r != null) {
            final geom = r['geometry'] as Map<String, dynamic>?;
            final loc = geom?['location'] as Map<String, dynamic>?;
            selection = PlacesSelection(
              placeId: r['place_id'] as String? ?? p.placeId,
              name: r['name'] as String? ?? p.primary,
              address: r['formatted_address'] as String? ?? p.secondary,
              latitude: (loc?['lat'] as num?)?.toDouble(),
              longitude: (loc?['lng'] as num?)?.toDouble(),
              freeText: r['name'] as String? ?? p.primary,
            );
          }
        }
      } catch (e) {
        _logger.w('Place Details fetch failed: $e');
      }
    }
    // Rotate session token after a successful pick — Google bills the
    // next autocomplete as a fresh session.
    _sessionToken = _newSessionToken();
    widget.onChanged(selection);
  }

  void _onChangedText(String value) {
    _debounce?.cancel();
    // Notify caller with the typed text so they can submit even
    // without a pick.
    widget.onChanged(PlacesSelection(freeText: value));
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchPredictions(value);
    });
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context, rootOverlay: true);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlay = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            offset: Offset(0, size.height + 4),
            showWhenUnlinked: false,
            child: _SuggestionList(
              predictions: _predictions,
              errorMessage: _lastError,
              onTap: _selectPrediction,
            ),
          ),
        );
      },
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  String _newSessionToken() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'sess-$now-${now ^ 0x5A5A5A5A}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        maxLength: widget.maxLength,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onChanged: _onChangedText,
        decoration: InputDecoration(
          hintText: widget.hintText,
          counterText: '',
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: const Icon(Icons.search, size: 22),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _Prediction {
  final String placeId;
  final String primary;
  final String? secondary;

  const _Prediction({
    required this.placeId,
    required this.primary,
    this.secondary,
  });

  factory _Prediction.fromJson(Map<String, dynamic> j) {
    final structured = j['structured_formatting'] as Map<String, dynamic>?;
    return _Prediction(
      placeId: j['place_id'] as String,
      primary: (structured?['main_text'] as String?) ??
          (j['description'] as String? ?? ''),
      secondary: structured?['secondary_text'] as String?,
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final List<_Prediction> predictions;
  final ValueChanged<_Prediction> onTap;
  final String? errorMessage;
  const _SuggestionList({
    required this.predictions,
    required this.onTap,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty && (errorMessage == null || errorMessage!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    // No results AND there is an error → render the error message.
    if (predictions.isEmpty) {
      return Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.error_outline,
                  size: 18, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: predictions.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: scheme.outline.withValues(alpha: 0.1)),
          itemBuilder: (ctx, i) {
            final p = predictions[i];
            return InkWell(
              onTap: () => onTap(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 18,
                        color: scheme.onSurface.withValues(alpha: 0.55)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.primary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (p.secondary != null && p.secondary!.isNotEmpty)
                            Text(
                              p.secondary!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
