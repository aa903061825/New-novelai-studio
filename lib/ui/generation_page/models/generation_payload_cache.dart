class GenerationPayloadCache<T> {
  Object? _cached;
  bool _hasCached = false;

  T takeOrGenerate(T Function() generate) {
    if (!_hasCached) {
      _cached = generate();
      _hasCached = true;
    }

    return _cached as T;
  }

  void markSuccess() {
    reset();
  }

  void reset() {
    _hasCached = false;
    _cached = null;
  }
}
