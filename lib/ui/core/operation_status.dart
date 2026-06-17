enum OperationStatusKind { idle, running, success, failure }

enum OperationStatusCode {
  none,
  importScript,
  importFailed,
  cacheRestore,
  cacheSave,
  aiExtraction,
  catalogRefresh,
}

class OperationStatus {
  final OperationStatusKind kind;
  final OperationStatusCode code;
  final String message;
  final bool recoverable;

  const OperationStatus._({
    required this.kind,
    required this.code,
    required this.message,
    required this.recoverable,
  });

  const OperationStatus.idle()
      : this._(
          kind: OperationStatusKind.idle,
          code: OperationStatusCode.none,
          message: '',
          recoverable: false,
        );

  const OperationStatus.running({
    required OperationStatusCode code,
    required String message,
  }) : this._(
          kind: OperationStatusKind.running,
          code: code,
          message: message,
          recoverable: false,
        );

  const OperationStatus.success({
    required OperationStatusCode code,
    required String message,
  }) : this._(
          kind: OperationStatusKind.success,
          code: code,
          message: message,
          recoverable: false,
        );

  const OperationStatus.failure({
    required OperationStatusCode code,
    required String message,
    bool recoverable = false,
  }) : this._(
          kind: OperationStatusKind.failure,
          code: code,
          message: message,
          recoverable: recoverable,
        );
}
