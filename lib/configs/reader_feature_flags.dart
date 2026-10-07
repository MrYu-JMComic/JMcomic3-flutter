/// Compile-time switches for reader optimizations.
///
/// Each capability is intentionally independent.  A release can disable one
/// experiment without changing the on-disk cache or the legacy reader path.
/// Keep the defaults conservative until device/network evidence is recorded.
const bool readerPageDescriptorV1 = bool.fromEnvironment(
  'JM_READER_PAGE_DESCRIPTOR_V1',
  defaultValue: false,
);

const bool readerPrefetchSchedulerV1 = bool.fromEnvironment(
  'JM_READER_PREFETCH_SCHEDULER_V1',
  defaultValue: false,
);

const bool readerBatchApiV1 = bool.fromEnvironment(
  'JM_READER_BATCH_API_V1',
  defaultValue: false,
);

const bool readerOfflineOwnerV1 = bool.fromEnvironment(
  'JM_READER_OFFLINE_OWNER_V1',
  defaultValue: false,
);

const bool readerTwoPageWindowV1 = bool.fromEnvironment(
  'JM_READER_TWO_PAGE_WINDOW_V1',
  defaultValue: false,
);

const bool readerPreciseProgressV1 = bool.fromEnvironment(
  'JM_READER_PRECISE_PROGRESS_V1',
  defaultValue: false,
);

const bool readerViewLogQueueV1 = bool.fromEnvironment(
  'JM_READER_VIEWLOG_QUEUE_V1',
  defaultValue: false,
);
