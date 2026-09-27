// =============================================================================
// File: anti_gravity_game.dart
// Description: Production-ready "Voxel Anti-Gravity Word Shooter" core game module
// Engine: Flame Engine (^1.21.0) & Flutter
// Style: Roblox / Minecraft procedural 3D Voxel Canvas Graphics
// Cross-Platform: Mobile (Touch/Drag) & Web/Desktop (Mouse/Arrows/WASD/Space)
// =============================================================================

import 'dart:math';
import 'dart:ui' show AppExitType;
import 'package:flame/camera.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mixin satisfying the HorizontalDragCallbacks specification by delegating
/// Flame's DragCallbacks.
mixin HorizontalDragCallbacks on FlameGame, DragCallbacks {
  void onHorizontalDragUpdate(DragUpdateEvent event) {}

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    onHorizontalDragUpdate(event);
  }
}

// =============================================================================
// ENTRY POINT / FLUTTER RUNNER
// =============================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AntiGravityGameApp());
}

/// Root Flutter application widget wrapping the Flame Game with a constrained
/// 450x800 aspect ratio container for flawless desktop/web letterboxing.
class AntiGravityGameApp extends StatelessWidget {
  const AntiGravityGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voxel Anti-Gravity Word Shooter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF07080D),
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 450,
              height: 800,
              child: ClipRect(
                child: GameWidget.controlled(
                  gameFactory: AntiGravityGame.new,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CAMERA SHAKE EXTENSION & EFFECT
// =============================================================================

/// Custom screen shake effect component attached to the Viewfinder.
/// Emulates the classic Flame `camera.shake()` API with smooth temporal decay.
class CameraShakeEffect extends Component {
  CameraShakeEffect({this.duration = 0.35, this.intensity = 10.0});

  final double duration;
  final double intensity;
  double _elapsed = 0.0;
  final Random _rng = Random();
  Vector2? _initialPos;

  @override
  void onMount() {
    super.onMount();
    if (parent is Viewfinder) {
      _initialPos = (parent as Viewfinder).position.clone();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_initialPos == null) return;
    final viewfinder = parent as Viewfinder;

    _elapsed += dt;
    if (_elapsed >= duration) {
      viewfinder.position.setFrom(_initialPos!);
      removeFromParent();
      return;
    }

    // Cubic falloff for punchy initial impact that settles smoothly
    final progress = 1.0 - (_elapsed / duration);
    final decay = progress * progress * progress;
    final currentIntensity = intensity * decay;

    final dx = (_rng.nextDouble() * 2.0 - 1.0) * currentIntensity;
    final dy = (_rng.nextDouble() * 2.0 - 1.0) * currentIntensity;

    viewfinder.position.setValues(_initialPos!.x + dx, _initialPos!.y + dy);
  }

  @override
  void onRemove() {
    if (_initialPos != null && parent is Viewfinder) {
      (parent as Viewfinder).position.setFrom(_initialPos!);
    }
    super.onRemove();
  }
}

/// Provides the standard `camera.shake()` syntax required by specifications.
extension CameraShakeExtension on CameraComponent {
  void shake({double duration = 0.35, double intensity = 10.0}) {
    // Remove existing shake to avoid compounded offset drift
    viewfinder.children.whereType<CameraShakeEffect>().forEach((e) => e.removeFromParent());
    viewfinder.add(CameraShakeEffect(duration: duration, intensity: intensity));
  }
}

// =============================================================================
// MAIN FLAME GAME CLASS
// =============================================================================

/// Main Game orchestrator implementing collision detection, input callbacks,
/// and fixed-resolution logical world scaling (450x800).
class AntiGravityGame extends FlameGame
    with
        HasCollisionDetection,
        DragCallbacks,
        HorizontalDragCallbacks,
        TapCallbacks,
        KeyboardEvents {
  AntiGravityGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: 450,
            height: 800,
          ),
        );

  // Logical units
  static const double gameWidth = 450.0;
  static const double gameHeight = 800.0;

  late PlayerShipComponent player;
  late TargetDockComponent targetDock;
  late VoxelStarfieldComponent starfield;

  int score = 0;
  int wave = 1;
  int currentTargetWordIndex = 0;

  // Word pool
  final List<String> targetWordDictionary = [
    'VOXEL',
    'LEXIQ',
    'ORBIT',
    'FLAME',
    'SPACE',
  ];

  final List<String> distractorWordDictionary = [
    'CHAOS',
    'PULSAR',
    'METEOR',
    'GRAVITY',
    'NEBULA',
    'QUARK',
  ];

  String get currentTargetWord =>
      targetWordDictionary[currentTargetWordIndex % targetWordDictionary.length];

  // Active word rigs in play
  WordRigComponent? targetWordRig;
  final List<WordRigComponent> distractorWordRigs = [];

  // Music Playlist and Track Rotation
  final List<String> musicPlaylists = [
    'space_theme.wav',
    'space_theme_2.wav',
    'space_theme_3.wav',
  ];
  int currentMusicTrackIndex = 0;

  // Interactive Voxel HUD Buttons
  late VoxelButtonComponent exitButton;
  late VoxelButtonComponent musicButton;
  late VoxelButtonComponent restartButton;
  bool isMusicMuted = false;

  // Keyboard navigation state
  bool _keyLeftDown = false;
  bool _keyRightDown = false;

  @override
  Color backgroundColor() => const Color(0xFF090A12);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Lock camera viewfinder top-left anchor to (0,0)
    camera.viewfinder.anchor = Anchor.topLeft;

    // Preload audio assets for zero latency
    try {
      await FlameAudio.audioCache.loadAll([
        'boom.wav',
        'space_theme.wav',
        'space_theme_2.wav',
        'space_theme_3.wav',
      ]);
    } catch (_) {}

    // 1. Background Voxel Starfield
    starfield = VoxelStarfieldComponent();
    world.add(starfield);

    // 2. Bottom Target Slot (Docking Bay)
    targetDock = TargetDockComponent(
      position: Vector2(gameWidth / 2, 700),
      size: Vector2(280, 50),
    );
    world.add(targetDock);

    // 3. Player Ship
    player = PlayerShipComponent(
      position: Vector2(gameWidth / 2, 740),
    );
    world.add(player);

    // 4. Interactive Voxel Buttons in HUD
    restartButton = VoxelButtonComponent(
      label: 'RESET',
      baseColor: const Color(0xFFFFB300), // Amber Gold Voxel
      position: Vector2(gameWidth - 170, 18),
      size: Vector2(50, 34),
      onPressed: restartGame,
    );
    world.add(restartButton);

    musicButton = VoxelButtonComponent(
      label: '♫ ON',
      baseColor: const Color(0xFF00E5FF),
      position: Vector2(gameWidth - 114, 18),
      size: Vector2(46, 34),
      onPressed: toggleMusic,
    );
    world.add(musicButton);

    exitButton = VoxelButtonComponent(
      label: 'EXIT',
      baseColor: const Color(0xFFFF1744),
      position: Vector2(gameWidth - 62, 18),
      size: Vector2(48, 34),
      onPressed: exitGame,
    );
    world.add(exitButton);

    // 5. Start Background Music
    startMusic();

    // 6. Spawn First Wave
    spawnWave();
  }

  @override
  void onRemove() {
    try {
      FlameAudio.bgm.stop();
      FlameAudio.bgm.dispose();
    } catch (_) {}
    super.onRemove();
  }

  /// Restarts the game, resetting targets and switching to a different space soundtrack.
  void restartGame() {
    // 1. Advance to the next space soundtrack in playlist
    currentMusicTrackIndex = (currentMusicTrackIndex + 1) % musicPlaylists.length;
    if (!isMusicMuted) {
      playCurrentTrack();
    }

    // 2. Reset score & wave state
    score = 0;
    wave = 1;
    currentTargetWordIndex = 0;
    player.position = Vector2(gameWidth / 2, 740);

    // 3. Play restart boom sound
    try {
      FlameAudio.play('boom.wav', volume: 0.85);
    } catch (_) {}

    // 4. Spawn clean wave
    spawnWave();
  }

  /// Plays the currently active space soundtrack.
  Future<void> playCurrentTrack() async {
    try {
      final track = musicPlaylists[currentMusicTrackIndex];
      await FlameAudio.bgm.play(track, volume: 0.45);
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  /// Initializes and plays looping background music.
  Future<void> startMusic() async {
    try {
      FlameAudio.bgm.initialize();
      await playCurrentTrack();
    } catch (e) {
      debugPrint('Audio autoplay waiting for user interaction: $e');
    }
  }

  /// Toggles background music between play and pause.
  void toggleMusic() {
    isMusicMuted = !isMusicMuted;
    if (isMusicMuted) {
      FlameAudio.bgm.pause();
      musicButton.label = '♫ OFF';
      musicButton.baseColor = const Color(0xFF64748B);
    } else {
      if (!FlameAudio.bgm.isPlaying) {
        playCurrentTrack();
      } else {
        FlameAudio.bgm.resume();
      }
      musicButton.label = '♫ ON';
      musicButton.baseColor = const Color(0xFF00E5FF);
    }
  }

  /// Cross-platform graceful application exit.
  void exitGame() {
    try {
      FlameAudio.bgm.stop();
      FlameAudio.bgm.dispose();
    } catch (_) {}

    try {
      ServicesBinding.instance.exitApplication(AppExitType.required);
    } catch (_) {
      SystemNavigator.pop();
    }
  }

  /// Spawns the correct target word and two floating distractor words.
  void spawnWave() {
    // Clear any previous words
    targetWordRig?.removeFromParent();
    for (final rig in distractorWordRigs) {
      rig.removeFromParent();
    }
    distractorWordRigs.clear();

    // Setup dock slot preview for current target
    targetDock.setTargetWord(currentTargetWord);

    // Spawn Correct Target Word at mid-upper altitude
    targetWordRig = WordRigComponent(
      word: currentTargetWord,
      isTargetWord: true,
      spawnY: 180.0,
      baseSpeedX: 45.0,
      baseColor: const Color(0xFF00E5FF), // Cyber Cyan Voxel
    );
    world.add(targetWordRig!);

    // Spawn Distractor Word 1 (Higher tier)
    final distractor1 = distractorWordDictionary[(wave * 2) % distractorWordDictionary.length];
    final distractorRig1 = WordRigComponent(
      word: distractor1,
      isTargetWord: false,
      spawnY: 100.0,
      baseSpeedX: -55.0,
      baseColor: const Color(0xFFFFB300), // Amber Gold Voxel
    );
    distractorWordRigs.add(distractorRig1);
    world.add(distractorRig1);

    // Spawn Distractor Word 2 (Lower tier)
    final distractor2 = distractorWordDictionary[(wave * 2 + 1) % distractorWordDictionary.length];
    final distractorRig2 = WordRigComponent(
      word: distractor2,
      isTargetWord: false,
      spawnY: 260.0,
      baseSpeedX: 40.0,
      baseColor: const Color(0xFFE040FB), // Neon Purple Voxel
    );
    distractorWordRigs.add(distractorRig2);
    world.add(distractorRig2);
  }

  /// Handles completion sequence when all letters of the correct word turn red.
  void onTargetWordCompleted(WordRigComponent completedRig) {
    score += 1000;

    // Switch to the next space music soundtrack when all of the target word is hit
    currentMusicTrackIndex = (currentMusicTrackIndex + 1) % musicPlaylists.length;
    if (!isMusicMuted) {
      playCurrentTrack();
    }

    // Trigger massive voxel celebratory explosion at completed word's location
    world.add(
      VoxelParticleExplosion(
        center: completedRig.position + Vector2(completedRig.size.x / 2, completedRig.size.y / 2),
        count: 50,
        colors: const [
          Color(0xFFFF1744),
          Color(0xFF00E5FF),
          Color(0xFFFFEA00),
          Color(0xFFFFFFFF),
        ],
      ),
    );

    // Target word prepares to advance wave upon docking in TargetDockComponent
    targetDock.highlightSuccess();

    // Advance to next target word after docking delay
    world.add(
      TimerComponent(
        period: 2.2,
        repeat: false,
        onTick: () {
          currentTargetWordIndex++;
          wave++;
          spawnWave();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INPUT HANDLING (Mobile Touch & Web Desktop)
  // ---------------------------------------------------------------------------

  /// Mobile & Web: Horizontal drag moves the player ship smoothly.
  @override
  void onHorizontalDragUpdate(DragUpdateEvent event) {
    player.position.x = (player.position.x + event.localDelta.x).clamp(
      player.size.x / 2 + 10,
      gameWidth - player.size.x / 2 - 10,
    );
  }

  /// Mobile & Web: Tapping anywhere on the screen fires the voxel cannons.
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);

    // On web/desktop, start music on first user tap if autoplay was suspended
    if (!isMusicMuted && !FlameAudio.bgm.isPlaying) {
      FlameAudio.bgm.play('space_theme.wav', volume: 0.45);
    }

    // Only fire ship cannons if tap is below top HUD header
    if (event.localPosition.y > 65) {
      player.fireLasers();
    }
  }

  /// Web & Desktop: Arrow keys / A-D for movement, Spacebar for firing.
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _keyLeftDown = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    _keyRightDown = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      player.fireLasers();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Keyboard horizontal movement interpolation
    const keyboardSpeed = 380.0;
    if (_keyLeftDown) {
      player.position.x -= keyboardSpeed * dt;
    }
    if (_keyRightDown) {
      player.position.x += keyboardSpeed * dt;
    }

    // Clamp player to logical screen boundaries
    player.position.x = player.position.x.clamp(
      player.size.x / 2 + 10,
      gameWidth - player.size.x / 2 - 10,
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Procedural Voxel HUD overlay
    _renderVoxelHUD(canvas);
  }

  void _renderVoxelHUD(Canvas canvas) {
    // HUD Header Panel
    final hudRect = Rect.fromLTWH(12, 12, gameWidth - 24, 46);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: hudRect,
      baseColor: const Color(0xFF161928),
      depth: 4.0,
      strokeColor: Colors.black,
    );

    // Score Text
    final scorePainter = TextPainter(
      text: TextSpan(
        text: 'SCORE: ${score.toString().padLeft(6, '0')}',
        style: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Color(0xFF00E5FF),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scorePainter.paint(canvas, const Offset(22, 26));

    // Wave Text
    final wavePainter = TextPainter(
      text: TextSpan(
        text: 'W$wave',
        style: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Color(0xFFFFEA00),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    wavePainter.paint(canvas, const Offset(170, 26));
  }
}

// =============================================================================
// ANTI-GRAVITY HARMONIC WORD RIG COMPONENT
// =============================================================================

/// ============================================================================
/// ANTI-GRAVITY COMPOUND HARMONIC PHYSICS EXPLANATION
/// ============================================================================
/// In a zero-g vacuum, unanchored voxel word clusters experience continuous
/// buoyancy oscillations and rotational wobble due to micro-gravitational
/// field fluctuations.
///
/// Rather than simple pendular motion, this component simulates multi-frequency
/// compound sinusoids with physical deflection damping:
///
/// 1. Primary Horizontal Drift with Edge Bounce:
///    X(t) = currentX + (velocity_x + deflectionVelocity_x) * dt
///    - Bounces elastically off left (x = 15) and right (x = 435 - width) walls.
///
/// 2. Compound Anti-Gravity Vertical Buoyancy:
///    Y(t) = baseY + A_y1 * sin(ω_y1 * t + φ_y1) + A_y2 * cos(ω_y2 * t + φ_y2)
///    - Primary wave (ω_y1 ≈ 1.6 rad/s, A_y1 ≈ 14px): Low-frequency macro levitation.
///    - Secondary wave (ω_y2 ≈ 3.4 rad/s, A_y2 ≈ 5px): High-frequency zero-g flutter.
///
/// 3. Angular Wobble & Rotational Inertia:
///    Angle(t) = A_rot * sin(ω_rot * t + φ_rot) + deflectionAngle
///    - A_rot (~0.06 rad): Natural floating tilt.
///    - Deflection feedback: Gunfire imparts instantaneous angular torque and
///      translational impulses that exponentially decay via viscous fluid damping:
///      deflection *= exp(-damping * dt).
/// ============================================================================
class WordRigComponent extends PositionComponent
    with HasGameReference<AntiGravityGame> {
  WordRigComponent({
    required this.word,
    required this.isTargetWord,
    required this.spawnY,
    required this.baseSpeedX,
    required this.baseColor,
  }) {
    anchor = Anchor.topLeft;
  }

  final String word;
  final bool isTargetWord;
  final double spawnY;
  final double baseSpeedX;
  final Color baseColor;

  // Individual letter block children
  final List<LetterBlockComponent> letterBlocks = [];

  // Harmonic parameters
  late double _baseY;
  late double _speedX;
  double _lifetime = 0.0;

  // Compound Wave Phase Offsets & Frequencies (Randomized for organic movement)
  final double _phaseY1 = Random().nextDouble() * 2 * pi;
  final double _phaseY2 = Random().nextDouble() * 2 * pi;
  final double _phaseRot = Random().nextDouble() * 2 * pi;
  final double _omegaY1 = 1.4 + Random().nextDouble() * 0.5; // ~1.4 - 1.9 rad/s
  final double _omegaY2 = 3.0 + Random().nextDouble() * 1.0; // ~3.0 - 4.0 rad/s
  final double _omegaRot = 1.0 + Random().nextDouble() * 0.8;

  // Deflection Feedback Physics
  final Vector2 _deflectionImpulse = Vector2.zero();
  double _deflectionTorque = 0.0;

  // Success detachment state
  bool isCompleted = false;

  static const double letterBlockSize = 38.0;
  static const double letterBlockSpacing = 4.0;
  static const double voxelExtrudeDepth = 5.0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _baseY = spawnY;
    _speedX = baseSpeedX;

    // Calculate total rig dimensions
    final totalWidth =
        word.length * letterBlockSize + (word.length - 1) * letterBlockSpacing;
    size = Vector2(totalWidth, letterBlockSize + voxelExtrudeDepth);

    // Initial random X placement within boundaries
    final minX = 20.0;
    final maxX = AntiGravityGame.gameWidth - totalWidth - 20.0;
    position = Vector2(
      minX + Random().nextDouble() * max(10.0, maxX - minX),
      spawnY,
    );

    // Assemble compound letter blocks
    for (int i = 0; i < word.length; i++) {
      final letter = word[i];
      final blockX = i * (letterBlockSize + letterBlockSpacing);
      final block = LetterBlockComponent(
        character: letter,
        index: i,
        baseColor: baseColor,
        size: Vector2(letterBlockSize, letterBlockSize),
        position: Vector2(blockX, 0),
      );
      letterBlocks.add(block);
      add(block);
    }
  }

  /// Handles collision with a letter block.
  void onLetterHit(LetterBlockComponent hitBlock) {
    if (isCompleted) return;

    // Play punchy retro boom explosion sound effect on letter impact
    try {
      FlameAudio.play('boom.wav', volume: 0.75);
    } catch (_) {}

    if (isTargetWord) {
      // CORRECT WORD HIT:
      // Turn letter neon red immediately and trigger sparks
      hitBlock.turnNeonRed();

      // Check if ALL letters in the word are now destroyed
      final allDestroyed = letterBlocks.every((b) => b.isDestroyed);
      if (allDestroyed) {
        _triggerSuccessSequence();
      }
    } else {
      // INCORRECT (DISTRACTOR) WORD HIT:
      // 1. Screen Shake penalty
      game.camera.shake(duration: 0.4, intensity: 12.0);

      // 2. Physical Deflection Feedback (recoil impulse & angular kick)
      final recoilDir = Random().nextBool() ? 1.0 : -1.0;
      _deflectionImpulse.setValues(recoilDir * 140.0, -80.0);
      _deflectionTorque = (Random().nextDouble() * 2.0 - 1.0) * 0.35;

      // 3. Mark hit letter red as well
      hitBlock.turnNeonRed();
    }
  }

  /// Initiates the success flow: detach from motion and glide to bottom target slot.
  void _triggerSuccessSequence() {
    isCompleted = true;

    // Notify Game of completion
    game.onTargetWordCompleted(this);

    // Reset rotation smoothly to 0
    add(
      RotateEffect.to(
        0.0,
        EffectController(duration: 0.4, curve: Curves.easeOut),
      ),
    );

    // Smoothly glide completed word to the Target Dock at the bottom
    final dockTargetX = (AntiGravityGame.gameWidth - size.x) / 2;
    const dockTargetY = 704.0;

    add(
      MoveEffect.to(
        Vector2(dockTargetX, dockTargetY),
        EffectController(
          duration: 1.2,
          curve: Curves.easeInOutCubic,
        ),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    // If completed and gliding to the dock, skip harmonic physics updates
    if (isCompleted) return;

    _lifetime += dt;

    // 1. Update horizontal movement with edge bouncing
    position.x += (_speedX + _deflectionImpulse.x) * dt;

    final minX = 12.0;
    final maxX = AntiGravityGame.gameWidth - size.x - 12.0;

    if (position.x <= minX) {
      position.x = minX;
      _speedX = _speedX.abs();
    } else if (position.x >= maxX) {
      position.x = maxX;
      _speedX = -_speedX.abs();
    }

    // 2. Compound Anti-Gravity Vertical Harmonic Levitation
    final heave = 14.0 * sin(_omegaY1 * _lifetime + _phaseY1);
    final flutter = 5.0 * cos(_omegaY2 * _lifetime + _phaseY2);
    position.y = _baseY + heave + flutter + _deflectionImpulse.y * dt;

    // 3. Rotational Zero-G Wobble
    final naturalWobble = 0.07 * sin(_omegaRot * _lifetime + _phaseRot);
    angle = naturalWobble + _deflectionTorque;

    // 4. Exponential Damping of Deflection Impulses
    final damping = exp(-5.0 * dt);
    _deflectionImpulse.scale(damping);
    _deflectionTorque *= exp(-4.0 * dt);
  }
}

// =============================================================================
// VOXEL LETTER BLOCK COMPONENT
// =============================================================================

/// Individual letter unit within a WordRig.
/// Implements collision detection, voxel canvas rendering, and neon destruction.
class LetterBlockComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AntiGravityGame> {
  LetterBlockComponent({
    required this.character,
    required this.index,
    required this.baseColor,
    required super.size,
    required super.position,
  });

  final String character;
  final int index;
  final Color baseColor;

  bool isDestroyed = false;

  late final RectangleHitbox _hitbox;

  static const Color neonRedColor = Color(0xFFFF1744);
  static const Color neonRedBright = Color(0xFFFF5252);
  static const Color neonRedShadow = Color(0xFFB71C1C);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Standard collision hitbox encompassing the letter voxel
    _hitbox = RectangleHitbox(
      size: size,
      position: Vector2.zero(),
    );
    add(_hitbox);
  }

  /// Sets letter state to destroyed (Neon Red voxel).
  void turnNeonRed() {
    if (isDestroyed) return;
    isDestroyed = true;

    // Emit small voxel spark burst on destruction
    final worldCenter = absolutePositionOf(Vector2(size.x / 2, size.y / 2));
    game.world.add(
      VoxelParticleExplosion(
        center: worldCenter,
        count: 12,
        colors: const [neonRedColor, neonRedBright, Colors.white],
      ),
    );
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);

    // Laser collision handling (single laser destroys single letter block)
    if (other is VoxelLaser && !other.isRemoved) {
      other.removeFromParent(); // Destroy laser bullet immediately

      // Forward hit event to parent WordRig
      final parentRig = parent;
      if (parentRig is WordRigComponent) {
        parentRig.onLetterHit(this);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final currentColor = isDestroyed ? neonRedColor : baseColor;
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Draw 3D Voxel Cube on Canvas
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: rect,
      baseColor: currentColor,
      depth: 5.0,
      strokeColor: Colors.black,
      isEmissive: isDestroyed,
    );

    // Draw Monospace Letter Character on Front Face
    final textColor = isDestroyed ? const Color(0xFFFFF0F5) : Colors.black;
    final textPainter = TextPainter(
      text: TextSpan(
        text: character,
        style: TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: 22,
          color: textColor,
          shadows: [
            Shadow(
              color: isDestroyed
                  ? const Color(0xFFFF0055).withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.6),
              blurRadius: isDestroyed ? 8.0 : 0.0,
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      (size.x - textPainter.width) / 2,
      (size.y - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);
  }
}

// =============================================================================
// VOXEL LASER COMPONENT
// =============================================================================

/// Procedural voxel energy projectile fired by the player ship.
class VoxelLaser extends PositionComponent
    with CollisionCallbacks, HasGameReference<AntiGravityGame> {
  VoxelLaser({required super.position})
      : super(
          size: Vector2(6, 18),
          anchor: Anchor.center,
        );

  static const double laserSpeed = -780.0; // Moving upward

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox(size: size, position: Vector2.zero()));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y += laserSpeed * dt;

    // Despawn when exiting screen top
    if (position.y < -30) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Chunky neon laser bolt
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: rect,
      baseColor: const Color(0xFF00FF66), // Neon Voxel Green
      depth: 3.0,
      strokeColor: Colors.black,
      isEmissive: true,
    );
  }
}

// =============================================================================
// PLAYER SHIP COMPONENT
// =============================================================================

/// Roblox/Minecraft styled voxel spacecraft.
class PlayerShipComponent extends PositionComponent
    with HasGameReference<AntiGravityGame> {
  PlayerShipComponent({required super.position})
      : super(
          size: Vector2(64, 48),
          anchor: Anchor.center,
        );

  // Laser firing cooldown
  double _fireCooldown = 0.0;
  static const double fireRate = 0.16; // Minimum seconds between shots

  // Thruster animation timer
  double _thrusterTimer = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _fireCooldown = max(0.0, _fireCooldown - dt);
    _thrusterTimer += dt;
  }

  /// Fires twin voxel laser bolts from the wingtip cannons.
  void fireLasers() {
    if (_fireCooldown > 0.0) return;
    _fireCooldown = fireRate;

    // Left cannon
    game.world.add(
      VoxelLaser(
        position: Vector2(position.x - 22, position.y - 18),
      ),
    );

    // Right cannon
    game.world.add(
      VoxelLaser(
        position: Vector2(position.x + 22, position.y - 18),
      ),
    );

    // Subtle gun recoil effect
    add(
      MoveByEffect(
        Vector2(0, 4),
        EffectController(
          duration: 0.06,
          alternate: true,
        ),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Procedural Voxel Thruster Flame
    final flameHeight = 8.0 + 5.0 * sin(_thrusterTimer * 25.0);
    final flameRectLeft = Rect.fromLTWH(18, size.y - 2, 8, flameHeight);
    final flameRectRight = Rect.fromLTWH(size.x - 26, size.y - 2, 8, flameHeight);

    final flamePaint = Paint()
      ..color = const Color(0xFFFF9100)
      ..style = PaintingStyle.fill;
    final flameStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(flameRectLeft, flamePaint);
    canvas.drawRect(flameRectLeft, flameStroke);
    canvas.drawRect(flameRectRight, flamePaint);
    canvas.drawRect(flameRectRight, flameStroke);

    // 2. Wings (Dark Navy/Slate Voxels)
    final wingRectLeft = Rect.fromLTWH(0, 18, 22, 18);
    final wingRectRight = Rect.fromLTWH(size.x - 22, 18, 22, 18);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: wingRectLeft,
      baseColor: const Color(0xFF1E293B),
      depth: 4.0,
      strokeColor: Colors.black,
    );
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: wingRectRight,
      baseColor: const Color(0xFF1E293B),
      depth: 4.0,
      strokeColor: Colors.black,
    );

    // 3. Wingtip Laser Cannons (Bright Neon Green Voxel accents)
    final cannonLeft = Rect.fromLTWH(2, 6, 6, 14);
    final cannonRight = Rect.fromLTWH(size.x - 8, 6, 6, 14);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: cannonLeft,
      baseColor: const Color(0xFF00E676),
      depth: 2.0,
      strokeColor: Colors.black,
    );
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: cannonRight,
      baseColor: const Color(0xFF00E676),
      depth: 2.0,
      strokeColor: Colors.black,
    );

    // 4. Center Fuselage / Hull (Cobalt Blue Voxel)
    final hullRect = Rect.fromLTWH(16, 8, 32, 34);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: hullRect,
      baseColor: const Color(0xFF0284C7),
      depth: 5.0,
      strokeColor: Colors.black,
    );

    // 5. Cockpit Canopy (Cyber Yellow / Glass Voxel)
    final cockpitRect = Rect.fromLTWH(24, 12, 16, 16);
    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: cockpitRect,
      baseColor: const Color(0xFFFFEA00),
      depth: 4.0,
      strokeColor: Colors.black,
      isEmissive: true,
    );
  }
}

// =============================================================================
// TARGET DOCK COMPONENT (Bottom Goal Slot)
// =============================================================================

/// Target dock slot at bottom of screen where completed words land.
class TargetDockComponent extends PositionComponent {
  TargetDockComponent({
    required super.position,
    required super.size,
  }) : super(anchor: Anchor.center);

  String _targetWord = '';
  bool _isSuccessFlashing = false;
  double _flashTimer = 0.0;

  void setTargetWord(String word) {
    _targetWord = word;
    _isSuccessFlashing = false;
  }

  void highlightSuccess() {
    _isSuccessFlashing = true;
    _flashTimer = 1.6;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isSuccessFlashing) {
      _flashTimer -= dt;
      if (_flashTimer <= 0.0) {
        _isSuccessFlashing = false;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Dock Base Frame
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final borderColor = _isSuccessFlashing ? const Color(0xFF00FF66) : const Color(0xFF2A2E44);

    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: rect,
      baseColor: const Color(0xFF0D101C),
      depth: 4.0,
      strokeColor: borderColor,
    );

    // Target Prompt Header Label
    final promptPainter = TextPainter(
      text: TextSpan(
        text: 'TARGET ACQUISITION: [ $_targetWord ]',
        style: TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: _isSuccessFlashing ? const Color(0xFF00FF66) : const Color(0xFF94A3B8),
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    promptPainter.paint(
      canvas,
      Offset((size.x - promptPainter.width) / 2, (size.y - promptPainter.height) / 2),
    );
  }
}

// =============================================================================
// VOXEL BUTTON COMPONENT (Exit & Music Controls)
// =============================================================================

/// Interactive 3D voxel button with mechanical press bounce and tap handling.
class VoxelButtonComponent extends PositionComponent
    with TapCallbacks, HasGameReference<AntiGravityGame> {
  VoxelButtonComponent({
    required this.label,
    required this.baseColor,
    required this.onPressed,
    required super.position,
    required super.size,
  });

  String label;
  Color baseColor;
  final VoidCallback onPressed;
  bool _isPressed = false;

  @override
  void onTapDown(TapDownEvent event) {
    _isPressed = true;
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_isPressed) {
      _isPressed = false;
      onPressed();
    }
    event.handled = true;
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _isPressed = false;
    event.handled = true;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final offset = _isPressed ? const Offset(0, 2) : Offset.zero;
    final depth = _isPressed ? 2.0 : 4.0;
    final rect = Rect.fromLTWH(offset.dx, offset.dy, size.x, size.y);

    VoxelDrawingUtils.drawVoxelBox(
      canvas: canvas,
      rect: rect,
      baseColor: baseColor,
      depth: depth,
      strokeColor: Colors.black,
      isEmissive: _isPressed,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: Colors.black,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        offset.dx + (size.x - textPainter.width) / 2,
        offset.dy + (size.y - textPainter.height) / 2,
      ),
    );
  }
}

// =============================================================================
// VOXEL STARFIELD COMPONENT
// =============================================================================

/// Procedural background rendering twinkling, slow-drifting square voxel stars.
class VoxelStarfieldComponent extends PositionComponent {
  VoxelStarfieldComponent() : super(size: Vector2(450, 800));

  final List<_VoxelStar> _stars = [];
  final Random _rng = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Populate starfield
    for (int i = 0; i < 45; i++) {
      _stars.add(
        _VoxelStar(
          x: _rng.nextDouble() * 450,
          y: _rng.nextDouble() * 800,
          size: (_rng.nextInt(3) + 1) * 2.0, // 2px, 4px, or 6px chunky squares
          speed: 15.0 + _rng.nextDouble() * 40.0,
          alpha: 0.3 + _rng.nextDouble() * 0.7,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final star in _stars) {
      star.y += star.speed * dt;
      if (star.y > 800) {
        star.y = -10;
        star.x = _rng.nextDouble() * 450;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final star in _stars) {
      final paint = Paint()
        ..color = Color(0xFF90CAF9).withValues(alpha: star.alpha)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: star.alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final rect = Rect.fromLTWH(star.x, star.y, star.size, star.size);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }
  }
}

class _VoxelStar {
  _VoxelStar({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.alpha,
  });

  double x;
  double y;
  final double size;
  final double speed;
  final double alpha;
}

// =============================================================================
// VOXEL PARTICLE EXPLOSION SYSTEM
// =============================================================================

/// Burst of individual 3D voxel cubes that tumble, fly outward, and fade out.
class VoxelParticleExplosion extends Component {
  VoxelParticleExplosion({
    required this.center,
    required this.count,
    required this.colors,
  });

  final Vector2 center;
  final int count;
  final List<Color> colors;

  final List<_VoxelParticle> _particles = [];
  final Random _rng = Random();

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    for (int i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 70.0 + _rng.nextDouble() * 260.0;
      final particleSize = 4.0 + _rng.nextDouble() * 6.0;
      final color = colors[_rng.nextInt(colors.length)];

      _particles.add(
        _VoxelParticle(
          pos: center.clone(),
          velocity: Vector2(cos(angle) * speed, sin(angle) * speed),
          size: particleSize,
          color: color,
          maxLife: 0.6 + _rng.nextDouble() * 0.7,
          rotation: _rng.nextDouble() * 2 * pi,
          rotSpeed: (_rng.nextDouble() * 2.0 - 1.0) * 8.0,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    bool allDead = true;
    for (final p in _particles) {
      if (p.isAlive) {
        allDead = false;
        p.update(dt);
      }
    }

    if (allDead) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final p in _particles) {
      if (!p.isAlive) continue;

      final progress = p.life / p.maxLife;
      final alpha = (1.0 - progress).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(p.pos.x, p.pos.y);
      canvas.rotate(p.rotation);

      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size,
        height: p.size,
      );

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);

      canvas.restore();
    }
  }
}

class _VoxelParticle {
  _VoxelParticle({
    required this.pos,
    required this.velocity,
    required this.size,
    required this.color,
    required this.maxLife,
    required this.rotation,
    required this.rotSpeed,
  });

  Vector2 pos;
  Vector2 velocity;
  final double size;
  final Color color;
  final double maxLife;
  double life = 0.0;
  double rotation;
  final double rotSpeed;

  bool get isAlive => life < maxLife;

  void update(double dt) {
    life += dt;
    pos += velocity * dt;
    rotation += rotSpeed * dt;
    // Viscous air drag
    velocity.scale(exp(-2.0 * dt));
  }
}

// =============================================================================
// PROCEDURAL VOXEL CANVAS DRAWING UTILITIES
// =============================================================================

/// Helper functions for drawing Roblox/Minecraft style pseudo-3D voxel blocks
/// on a 2D Canvas without requiring any external image assets.
class VoxelDrawingUtils {
  /// Renders a 3D chunky voxel block with:
  /// - Front face (base color or brightened)
  /// - Top face (beveled highlight polygon)
  /// - Right face (beveled shadow polygon)
  /// - Heavy black outlines
  static void drawVoxelBox({
    required Canvas canvas,
    required Rect rect,
    required Color baseColor,
    required double depth,
    required Color strokeColor,
    bool isEmissive = false,
  }) {
    // 1. Calculate Face Colors
    final topFaceColor = Color.lerp(baseColor, Colors.white, 0.35)!;
    final rightFaceColor = Color.lerp(baseColor, Colors.black, 0.45)!;

    // Paints
    final frontPaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill;

    final topPaint = Paint()
      ..color = topFaceColor
      ..style = PaintingStyle.fill;

    final rightPaint = Paint()
      ..color = rightFaceColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Optional Emissive Outer Glow
    if (isEmissive) {
      final glowPaint = Paint()
        ..color = baseColor.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8.0);
      canvas.drawRect(rect, glowPaint);
    }

    // 2. Draw Top Polygon (Beveled Up & Right)
    final topPath = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.left + depth, rect.top - depth)
      ..lineTo(rect.right + depth, rect.top - depth)
      ..lineTo(rect.right, rect.top)
      ..close();

    canvas.drawPath(topPath, topPaint);
    canvas.drawPath(topPath, strokePaint);

    // 3. Draw Right Polygon (Beveled Shadow)
    final rightPath = Path()
      ..moveTo(rect.right, rect.top)
      ..lineTo(rect.right + depth, rect.top - depth)
      ..lineTo(rect.right + depth, rect.bottom - depth)
      ..lineTo(rect.right, rect.bottom)
      ..close();

    canvas.drawPath(rightPath, rightPaint);
    canvas.drawPath(rightPath, strokePaint);

    // 4. Draw Front Face
    canvas.drawRect(rect, frontPaint);
    canvas.drawRect(rect, strokePaint);
  }
}
