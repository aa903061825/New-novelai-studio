enum WorkspaceValidationSeverity { warning, error }

class WorkspaceValidationIssue {
  final WorkspaceValidationSeverity severity;
  final String code;
  final String path;
  final String message;

  const WorkspaceValidationIssue({
    required this.severity,
    required this.code,
    required this.path,
    required this.message,
  });
}

class WorkspaceValidationReport {
  final List<WorkspaceValidationIssue> issues;

  const WorkspaceValidationReport(this.issues);

  bool get hasErrors {
    return issues.any(
      (issue) => issue.severity == WorkspaceValidationSeverity.error,
    );
  }

  int get warningCount {
    return issues
        .where((issue) => issue.severity == WorkspaceValidationSeverity.warning)
        .length;
  }

  int get errorCount {
    return issues
        .where((issue) => issue.severity == WorkspaceValidationSeverity.error)
        .length;
  }
}
