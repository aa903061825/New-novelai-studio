class GenerationRuntimeState {
  bool vibeEnabled;
  bool hasPendingBatchResume;
  int resumeTargetTotalCount;
  int resumeCompletedCount;
  DateTime? resumeStartedAt;

  GenerationRuntimeState({
    this.vibeEnabled = true,
    this.hasPendingBatchResume = false,
    this.resumeTargetTotalCount = 0,
    this.resumeCompletedCount = 0,
    this.resumeStartedAt,
  });

  factory GenerationRuntimeState.fromJson(Map<String, dynamic> json) {
    return GenerationRuntimeState(
      vibeEnabled: json['vibe_enabled'] ?? true,
      hasPendingBatchResume: json['has_pending_batch_resume'] ?? false,
      resumeTargetTotalCount: json['resume_target_total_count'] ?? 0,
      resumeCompletedCount: json['resume_completed_count'] ?? 0,
      resumeStartedAt: DateTime.tryParse(json['resume_started_at'] ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vibe_enabled': vibeEnabled,
      'has_pending_batch_resume': hasPendingBatchResume,
      'resume_target_total_count': resumeTargetTotalCount,
      'resume_completed_count': resumeCompletedCount,
      'resume_started_at': resumeStartedAt?.toIso8601String(),
    };
  }

  void clearPendingBatchResume() {
    hasPendingBatchResume = false;
    resumeTargetTotalCount = 0;
    resumeCompletedCount = 0;
    resumeStartedAt = null;
  }
}
