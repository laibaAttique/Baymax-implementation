/// One body landmark from the pose model.
///
/// [x] and [y] are normalised to the upright image (0..1, origin top-left).
/// [visibility] is the model's 0..1 likelihood that the point is visible.
class PoseLandmark {
  final double x;
  final double y;
  final double z;
  final double visibility;
  const PoseLandmark(this.x, this.y, this.z, this.visibility);

  bool get isFinite => x.isFinite && y.isFinite && visibility.isFinite;
}

/// Indices of the 33 MediaPipe Pose landmarks used by the app.
class PoseIndex {
  PoseIndex._();
  static const count = 33;

  static const nose = 0;
  static const leftShoulder = 11;
  static const rightShoulder = 12;
  static const leftElbow = 13;
  static const rightElbow = 14;
  static const leftWrist = 15;
  static const rightWrist = 16;
  static const leftHip = 23;
  static const rightHip = 24;
  static const leftKnee = 25;
  static const rightKnee = 26;
  static const leftAnkle = 27;
  static const rightAnkle = 28;
  static const leftHeel = 29;
  static const rightHeel = 30;
  static const leftFoot = 31;
  static const rightFoot = 32;

  /// Bones drawn by the skeleton overlay.
  static const connections = <List<int>>[
    [leftShoulder, rightShoulder],
    [leftShoulder, leftElbow],
    [leftElbow, leftWrist],
    [rightShoulder, rightElbow],
    [rightElbow, rightWrist],
    [leftShoulder, leftHip],
    [rightShoulder, rightHip],
    [leftHip, rightHip],
    [leftHip, leftKnee],
    [leftKnee, leftAnkle],
    [rightHip, rightKnee],
    [rightKnee, rightAnkle],
    [leftAnkle, leftHeel],
    [leftHeel, leftFoot],
    [rightAnkle, rightHeel],
    [rightHeel, rightFoot],
  ];

  /// Joints drawn as dots (face landmarks other than the nose are skipped).
  static const drawnJoints = <int>[
    nose, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, //
    leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, leftHeel, rightHeel, leftFoot, rightFoot,
  ];
}

/// The pose model's output for one camera frame.
class PoseFrame {
  /// Either 33 landmarks or empty when no person was found.
  final List<PoseLandmark> landmarks;

  /// The same 33 points as 3-D coordinates in metres with the origin between
  /// the hips ("world landmarks"). Empty when the model does not provide them.
  /// Joint angles prefer these because they do not depend on the camera angle.
  final List<PoseLandmark> worldLandmarks;

  /// Monotonic capture time in milliseconds.
  final int timestampMs;

  /// Width / height of the upright image the landmarks are normalised to.
  final double aspectRatio;

  /// Time the model took for this frame, when measured.
  final int? inferenceMs;

  /// Time spent converting the camera frame for the model, when measured.
  final int? convertMs;

  const PoseFrame({
    required this.landmarks,
    required this.timestampMs,
    this.worldLandmarks = const [],
    this.aspectRatio = 1,
    this.inferenceMs,
    this.convertMs,
  });

  bool get hasPose => landmarks.length == PoseIndex.count;
  bool get hasWorld => worldLandmarks.length == PoseIndex.count;
}
