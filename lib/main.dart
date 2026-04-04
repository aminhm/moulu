import 'dart:math';

import 'package:flutter/material.dart';

void main() {
  runApp(const MouluApp());
}

class MouluApp extends StatelessWidget {
  const MouluApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'IranSans',
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFC857),
        secondary: Color(0xFFFF6B6B),
        surface: Color(0xFF181B2B),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مولی',
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RoleAssignmentScreen(),
    );
  }
}

class RoleAssignmentScreen extends StatefulWidget {
  const RoleAssignmentScreen({super.key});

  @override
  State<RoleAssignmentScreen> createState() => _RoleAssignmentScreenState();
}

class _RoleAssignmentScreenState extends State<RoleAssignmentScreen>
    with TickerProviderStateMixin {
  final Random _random = Random();
  late final AnimationController _backdropController;
  late final AnimationController _entranceController;

  int _playerCount = 10;
  int _nightNumber = 1;
  List<TextEditingController> _controllers = [];
  late Map<String, int> _selectedRoleCounts;

  List<RoleAssignment> _allAssignments = [];
  List<RoleAssignment> _remainingAssignments = [];
  Map<String, PlayerLifeStatus> _playerStates = {};

  List<NightStep> _nightSteps = [];
  int _nightStepIndex = -1;
  Map<String, List<String>> _pendingNightTargets = {};
  Map<String, Map<String, GunType>> _pendingNightGunTypes = {};
  List<NightReport> _nightReports = [];
  Set<String> _usedOneShotAbilities = <String>{};
  Map<String, int> _doctorSelfSaveUses = <String, int>{};

  bool get _isNightInProgress =>
      _nightStepIndex >= 0 && _nightStepIndex < _nightSteps.length;

  NightStep? get _currentNightStep =>
      _isNightInProgress ? _nightSteps[_nightStepIndex] : null;

  int get _selectedRoleTotal =>
      _selectedRoleCounts.values.fold(0, (sum, count) => sum + count);

  int get _remainingRoleSlots => _playerCount - _selectedRoleTotal;

  List<RoleSpec> get _selectedRolesDeck {
    final roles = <RoleSpec>[];
    for (final entry in roleCatalog) {
      final count = _selectedRoleCounts[entry.key] ?? 0;
      for (var i = 0; i < count; i++) {
        roles.add(entry.role);
      }
    }
    return roles;
  }

  int get _selectedMafiaCount =>
      _selectedRolesDeck.where((role) => role.team == Team.mafia).length;

  int get _selectedCityCount => _selectedRolesDeck.length - _selectedMafiaCount;

  List<RoleAssignment> get _aliveAssignments => _allAssignments
      .where(
        (assignment) => _playerStates[assignment.id] == PlayerLifeStatus.alive,
      )
      .toList();

  int get _eliminatedMafiaCount => _allAssignments
      .where(
        (assignment) =>
            assignment.role.team == Team.mafia &&
            _playerStates[assignment.id] == PlayerLifeStatus.eliminated,
      )
      .length;

  int get _eliminatedCityCount => _allAssignments
      .where(
        (assignment) =>
            assignment.role.team == Team.city &&
            _playerStates[assignment.id] == PlayerLifeStatus.eliminated,
      )
      .length;

  @override
  void initState() {
    super.initState();
    _backdropController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _selectedRoleCounts = defaultRoleCountsForPlayerCount(_playerCount);
    _syncControllersToCount();
  }

  @override
  void dispose() {
    _backdropController.dispose();
    _entranceController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllersToCount() {
    if (_controllers.length < _playerCount) {
      for (var i = _controllers.length; i < _playerCount; i++) {
        _controllers.add(TextEditingController(text: 'بازیکن ${i + 1}'));
      }
    } else if (_controllers.length > _playerCount) {
      final extra = _controllers.sublist(_playerCount);
      for (final controller in extra) {
        controller.dispose();
      }
      _controllers = _controllers.sublist(0, _playerCount);
    }
  }

  void _resetGame({bool keepNames = true}) {
    _allAssignments = [];
    _remainingAssignments = [];
    _playerStates = {};
    _nightSteps = [];
    _nightStepIndex = -1;
    _pendingNightTargets = {};
    _pendingNightGunTypes = {};
    _nightReports = [];
    _usedOneShotAbilities = <String>{};
    _doctorSelfSaveUses = <String, int>{};
    _nightNumber = 1;
    if (!keepNames) {
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = 'بازیکن ${i + 1}';
      }
    }
  }

  void _setPlayerCount(double value) {
    setState(() {
      _playerCount = value.round();
      _syncControllersToCount();
      _selectedRoleCounts = defaultRoleCountsForPlayerCount(_playerCount);
      _resetGame(keepNames: true);
    });
  }

  void _changeRoleCount(RoleCatalogEntry entry, int delta) {
    final current = _selectedRoleCounts[entry.key] ?? 0;
    final next = (current + delta).clamp(0, entry.maxCount(_playerCount));
    if (next == current) {
      return;
    }
    setState(() {
      _selectedRoleCounts[entry.key] = next;
      _resetGame(keepNames: true);
    });
  }

  void _assignRoles() {
    if (_selectedRoleTotal != _playerCount) {
      return;
    }

    final players = _controllers
        .take(_playerCount)
        .map((controller) => controller.text.trim())
        .toList();

    for (var i = 0; i < players.length; i++) {
      if (players[i].isEmpty) {
        players[i] = 'بازیکن ${i + 1}';
        _controllers[i].text = players[i];
      }
    }

    final shuffledPlayers = [...players]..shuffle(_random);
    final shuffledRoles = [..._selectedRolesDeck]..shuffle(_random);

    final assignments = List.generate(
      _playerCount,
      (index) => RoleAssignment(
        id: 'p$index-${shuffledPlayers[index]}-${shuffledRoles[index].key}',
        playerName: shuffledPlayers[index],
        role: shuffledRoles[index],
      ),
    );

    setState(() {
      _allAssignments = assignments;
      _remainingAssignments = List.of(assignments);
      _playerStates = {
        for (final assignment in assignments)
          assignment.id: PlayerLifeStatus.alive,
      };
      _nightSteps = [];
      _nightStepIndex = -1;
      _pendingNightTargets = {};
      _pendingNightGunTypes = {};
      _nightReports = [];
      _usedOneShotAbilities = <String>{};
      _doctorSelfSaveUses = <String, int>{};
      _nightNumber = 1;
    });
  }

  void _approveCurrentCard() {
    if (_remainingAssignments.isEmpty) {
      return;
    }
    setState(() {
      _remainingAssignments = _remainingAssignments.sublist(1);
    });
  }

  void _startNight() {
    final steps = [..._aliveAssignments]
      ..sort((a, b) {
        final order = a.role.wakeOrder.compareTo(b.role.wakeOrder);
        if (order != 0) {
          return order;
        }
        return a.playerName.compareTo(b.playerName);
      });

    final actionable = steps
        .where(
          (assignment) =>
              assignment.role.maxTargets > 0 &&
              !_hasConsumedNightAbility(assignment),
        )
        .map((assignment) => NightStep(actor: assignment))
        .toList();

    setState(() {
      _nightSteps = actionable;
      _nightStepIndex = actionable.isEmpty ? -1 : 0;
      _pendingNightTargets = {
        for (final step in actionable) step.actor.id: <String>[],
      };
      _pendingNightGunTypes = {
        for (final step in actionable) step.actor.id: <String, GunType>{},
      };
    });
  }

  void _toggleNightTarget(RoleAssignment actor, RoleAssignment target) {
    final current = List<String>.from(
      _pendingNightTargets[actor.id] ?? const <String>[],
    );
    final selected = current.contains(target.id);

    setState(() {
      if (selected) {
        current.remove(target.id);
        _pendingNightGunTypes[actor.id]?.remove(target.id);
      } else if (actor.role.maxTargets == 1) {
        _pendingNightGunTypes[actor.id]?.clear();
        current
          ..clear()
          ..add(target.id);
        if (actor.role.actionType == RoleActionType.armPlayers) {
          _pendingNightGunTypes[actor.id]![target.id] = GunType.blank;
        }
      } else if (current.length < actor.role.maxTargets) {
        current.add(target.id);
        if (actor.role.actionType == RoleActionType.armPlayers) {
          _pendingNightGunTypes[actor.id]![target.id] = GunType.blank;
        }
      }
      _pendingNightTargets[actor.id] = current;
    });
  }

  void _setGunTypeForTarget(
    RoleAssignment actor,
    RoleAssignment target,
    GunType gunType,
  ) {
    if (actor.role.actionType != RoleActionType.armPlayers) {
      return;
    }
    if (actor.id == target.id && gunType == GunType.live) {
      return;
    }
    setState(() {
      _pendingNightGunTypes.putIfAbsent(actor.id, () => <String, GunType>{});
      _pendingNightGunTypes[actor.id]![target.id] = gunType;
    });
  }

  void _submitCurrentNightStep() {
    final step = _currentNightStep;
    if (step == null) {
      return;
    }
    final selected = _pendingNightTargets[step.actor.id] ?? const <String>[];
    final enoughSelected =
        step.actor.role.actionType == RoleActionType.interrogate
        ? selected.isEmpty || selected.length == 2
        : selected.length >= step.actor.role.minTargets &&
              selected.length <= step.actor.role.maxTargets;
    final gunTypes =
        _pendingNightGunTypes[step.actor.id] ?? const <String, GunType>{};
    final allGunTypesSelected =
        step.actor.role.actionType != RoleActionType.armPlayers ||
        selected.every((targetId) => gunTypes[targetId] != null);
    if (!enoughSelected || !allGunTypesSelected) {
      return;
    }

    if (_nightStepIndex == _nightSteps.length - 1) {
      _finalizeNight();
    } else {
      setState(() {
        _nightStepIndex += 1;
      });
    }
  }

  void _finalizeNight() {
    final living = _aliveAssignments;
    final livingById = {for (final item in living) item.id: item};
    final saves = <String, List<RoleAssignment>>{};
    final eliminatedIds = <String>{};

    for (final actor in living) {
      if (actor.role.actionType == RoleActionType.save) {
        for (final targetId
            in _pendingNightTargets[actor.id] ?? const <String>[]) {
          saves.putIfAbsent(targetId, () => []).add(actor);
        }
      }
    }

    for (final actor in living) {
      final targets = (_pendingNightTargets[actor.id] ?? const <String>[])
          .map((id) => livingById[id])
          .whereType<RoleAssignment>()
          .toList();

      switch (actor.role.actionType) {
        case RoleActionType.kill:
          if (targets.isEmpty) {
            break;
          }
          final target = targets.first;
          final saved = saves.containsKey(target.id);
          if (!saved && !target.role.isBulletproof) {
            eliminatedIds.add(target.id);
          }
        case RoleActionType.sniperShot:
          if (targets.isEmpty) {
            break;
          }
          final target = targets.first;
          final saved = saves.containsKey(target.id);
          if (target.role.key == bazporsBoss.key) {
            break;
          }
          if (target.role.team == Team.city) {
            eliminatedIds.add(actor.id);
          } else if (!saved) {
            eliminatedIds.add(target.id);
          }
        case RoleActionType.link:
        case RoleActionType.guess:
        case RoleActionType.discoverDetective:
        case RoleActionType.revealCheck:
        case RoleActionType.save:
        case RoleActionType.interrogate:
        case RoleActionType.armPlayers:
        case RoleActionType.none:
          break;
      }
    }

    for (final actor in living.where(
      (assignment) => assignment.role.actionType == RoleActionType.link,
    )) {
      if (!eliminatedIds.contains(actor.id)) {
        continue;
      }
      final targets = (_pendingNightTargets[actor.id] ?? const <String>[])
          .map((id) => livingById[id])
          .whereType<RoleAssignment>();
      for (final target in targets) {
        if (target.role.key == nato.key || target.role.key == shiad.key) {
          eliminatedIds.add(target.id);
        }
      }
    }

    final actionSummaries = <String>[];
    for (final actor in living) {
      final targets = (_pendingNightTargets[actor.id] ?? const <String>[])
          .map((id) => livingById[id])
          .whereType<RoleAssignment>()
          .toList();
      actionSummaries.add(
        _buildResolvedActionSummary(
          actor,
          targets,
          eliminatedIds,
          saves,
          _pendingNightGunTypes[actor.id] ?? const <String, GunType>{},
        ),
      );
    }

    final eliminatedNames = _allAssignments
        .where((assignment) => eliminatedIds.contains(assignment.id))
        .map((assignment) => assignment.playerName)
        .toList();

    final nextStates = Map<String, PlayerLifeStatus>.from(_playerStates);
    final nextOneShot = Set<String>.from(_usedOneShotAbilities);
    final nextDoctorSelfSaveUses = Map<String, int>.from(_doctorSelfSaveUses);
    for (final id in eliminatedIds) {
      nextStates[id] = PlayerLifeStatus.eliminated;
    }

    for (final actor in living) {
      final selectedTargetIds =
          _pendingNightTargets[actor.id] ?? const <String>[];
      if (actor.role.actionType == RoleActionType.interrogate &&
          selectedTargetIds.isNotEmpty) {
        final anySelectedTargetEliminated = selectedTargetIds.any(
          (targetId) => eliminatedIds.contains(targetId),
        );
        if (!anySelectedTargetEliminated) {
          nextOneShot.add(actor.id);
        }
      }
      if (actor.role.actionType == RoleActionType.save &&
          selectedTargetIds.contains(actor.id)) {
        nextDoctorSelfSaveUses[actor.id] =
            (nextDoctorSelfSaveUses[actor.id] ?? 0) + 1;
      }
    }

    setState(() {
      _playerStates = nextStates;
      _usedOneShotAbilities = nextOneShot;
      _doctorSelfSaveUses = nextDoctorSelfSaveUses;
      _nightReports = [
        NightReport(
          nightNumber: _nightNumber,
          actionSummaries: actionSummaries,
          eliminatedIds: eliminatedIds.toList(),
          eliminatedNames: eliminatedNames,
        ),
        ..._nightReports,
      ];
      _nightNumber += 1;
      _nightSteps = [];
      _nightStepIndex = -1;
      _pendingNightTargets = {};
      _pendingNightGunTypes = {};
    });
  }

  bool _hasConsumedNightAbility(RoleAssignment assignment) {
    if (assignment.role.actionType == RoleActionType.interrogate) {
      return _usedOneShotAbilities.contains(assignment.id);
    }
    return false;
  }

  void _setPlayerLifeStatus(String assignmentId, PlayerLifeStatus status) {
    setState(() {
      _playerStates[assignmentId] = status;
    });
  }

  String _buildResolvedActionSummary(
    RoleAssignment actor,
    List<RoleAssignment> targets,
    Set<String> eliminatedIds,
    Map<String, List<RoleAssignment>> saves,
    Map<String, GunType> gunTypes,
  ) {
    if (targets.isEmpty) {
      return '${actor.playerName} (${actor.role.name}) هدفی انتخاب نکرد.';
    }

    final targetNames = targets.map((target) => target.playerName).join(' و ');
    return switch (actor.role.actionType) {
      RoleActionType.kill =>
        eliminatedIds.contains(targets.first.id)
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد و هدف حذف شد.'
            : targets.first.role.isBulletproof
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد اما رویین‌تن حذف نشد.'
            : saves.containsKey(targets.first.id)
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد اما دکتر او را نجات داد.'
            : '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد و نتیجه‌ای نداشت.',
      RoleActionType.guess =>
        '${actor.playerName} (${actor.role.name}) برای حدس نقش، $targetNames را انتخاب کرد. نتیجه این اکشن با راوی مشخص می‌شود.',
      RoleActionType.discoverDetective =>
        '${actor.playerName} (${actor.role.name}) به سراغ $targetNames رفت. نتیجه این اکشن فوری نیست.',
      RoleActionType.save =>
        '${actor.playerName} (${actor.role.name}) روی $targetNames سیو گذاشت.',
      RoleActionType.revealCheck =>
        '${actor.playerName} (${actor.role.name}) از $targetNames استعلام گرفت. نتیجه نزد گرداننده است.',
      RoleActionType.sniperShot =>
        eliminatedIds.contains(actor.id)
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد اما چون هدف شهر بود، خودش حذف شد.'
            : eliminatedIds.contains(targets.first.id)
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد و هدف حذف شد.'
            : targets.first.role.key == bazporsBoss.key
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد اما روی رئیس مافیا اثر نداشت.'
            : saves.containsKey(targets.first.id)
            ? '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد اما هدف نجات پیدا کرد.'
            : '${actor.playerName} (${actor.role.name}) به $targetNames شلیک کرد و نتیجه‌ای نداشت.',
      RoleActionType.link =>
        eliminatedIds.contains(actor.id) &&
                targets.any((target) => eliminatedIds.contains(target.id))
            ? '${actor.playerName} (${actor.role.name}) به $targetNames پیوند خورد و با حذف خودش، هدف پیوند هم حذف شد.'
            : '${actor.playerName} (${actor.role.name}) به $targetNames پیوند خورد.',
      RoleActionType.interrogate =>
        '${actor.playerName} (${actor.role.name}) بازپرسی را برای $targetNames ثبت کرد.',
      RoleActionType.armPlayers =>
        '${actor.playerName} (${actor.role.name}) به ${targets.map((target) {
          final gunType = gunTypes[target.id] ?? GunType.blank;
          final returned = eliminatedIds.contains(target.id) ? ' و چون هدف در شب حذف شد، تفنگ به تفنگدار برگشت' : '';
          return '${target.playerName} (${gunType.label})$returned';
        }).join(' و ')} تفنگ داد.',
      RoleActionType.none =>
        '${actor.playerName} (${actor.role.name}) اکشن شب ندارد.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _backdropController,
              builder: (context, child) => CustomPaint(
                painter: NebulaPainter(progress: _backdropController.value),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF040611).withValues(alpha: 0.78),
                    const Color(0xFF0F1424).withValues(alpha: 0.92),
                    const Color(0xFF05070F),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeSlideIn(
                    controller: _entranceController,
                    beginOffset: const Offset(0, 0.14),
                    interval: const Interval(
                      0,
                      0.5,
                      curve: Curves.easeOutCubic,
                    ),
                    child: _HeroSection(
                      playerCount: _playerCount,
                      mafiaCount: _selectedMafiaCount,
                      cityCount: _selectedCityCount,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeSlideIn(
                    controller: _entranceController,
                    beginOffset: const Offset(0, 0.18),
                    interval: const Interval(
                      0.12,
                      0.68,
                      curve: Curves.easeOutCubic,
                    ),
                    child: _SetupPanel(
                      playerCount: _playerCount,
                      controllers: _controllers,
                      selectedRoleCounts: _selectedRoleCounts,
                      selectedRoleTotal: _selectedRoleTotal,
                      remainingRoleSlots: _remainingRoleSlots,
                      onPlayerCountChanged: _setPlayerCount,
                      onRoleCountChanged: _changeRoleCount,
                      onTextChanged: () {
                        if (_allAssignments.isNotEmpty) {
                          setState(() {
                            _resetGame(keepNames: true);
                          });
                        }
                      },
                      onAssign: _assignRoles,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeSlideIn(
                    controller: _entranceController,
                    beginOffset: const Offset(0, 0.22),
                    interval: const Interval(
                      0.22,
                      1,
                      curve: Curves.easeOutCubic,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _buildBottomSection(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    if (_allAssignments.isEmpty) {
      return const _EmptyState();
    }

    if (_remainingAssignments.isNotEmpty) {
      return _RevealSection(
        key: const ValueKey('reveal-state'),
        remainingAssignments: _remainingAssignments,
        totalCount: _allAssignments.length,
        onApprove: _approveCurrentCard,
      );
    }

    if (_isNightInProgress) {
      final step = _currentNightStep!;
      final selectedTargets =
          _pendingNightTargets[step.actor.id] ?? const <String>[];
      final availableTargets = _aliveAssignments.where((assignment) {
        if (assignment.id != step.actor.id) {
          return true;
        }
        if (!step.actor.role.canTargetSelf) {
          return false;
        }
        if (step.actor.role.actionType == RoleActionType.save &&
            (_doctorSelfSaveUses[step.actor.id] ?? 0) >= 2) {
          return false;
        }
        return true;
      }).toList();
      return _NightWizardSection(
        key: const ValueKey('night-wizard'),
        nightNumber: _nightNumber,
        stepIndex: _nightStepIndex,
        totalSteps: _nightSteps.length,
        actor: step.actor,
        doctorSelfSaveUses: _doctorSelfSaveUses[step.actor.id] ?? 0,
        selectedTargetIds: selectedTargets,
        selectedGunTypes:
            _pendingNightGunTypes[step.actor.id] ?? const <String, GunType>{},
        availableTargets: availableTargets,
        onTargetToggle: (assignment) =>
            _toggleNightTarget(step.actor, assignment),
        onGunTypeChanged: (assignment, gunType) =>
            _setGunTypeForTarget(step.actor, assignment, gunType),
        onConfirm: _submitCurrentNightStep,
      );
    }

    return _CoordinatorSection(
      key: const ValueKey('coordinator-state'),
      assignments: _allAssignments,
      playerStates: _playerStates,
      eliminatedMafiaCount: _eliminatedMafiaCount,
      eliminatedCityCount: _eliminatedCityCount,
      nightNumber: _nightNumber,
      nightReports: _nightReports,
      onStartNight: _startNight,
      onPlayerStateChanged: _setPlayerLifeStatus,
      onRestart: () {
        setState(() {
          _resetGame(keepNames: true);
        });
      },
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.playerCount,
    required this.mafiaCount,
    required this.cityCount,
  });

  final int playerCount;
  final int mafiaCount;
  final int cityCount;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x29FFC857),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'مولی / سناریوی بازپرس',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFD68A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'تقسیم نقش با ترتیب واقعی بیدار شدن نقش‌ها.',
            style: TextStyle(
              fontSize: 32,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'گرداننده می‌تواند نقش‌های میز را انتخاب کند، کارت‌ها را یکی‌یکی نمایش بدهد، فاز شب را به ترتیب درست جلو ببرد و وضعیت هر بازیکن را دستی تغییر دهد.',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFFD3DAF8),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 140,
                child: StatTile(
                  label: 'بازیکن',
                  value: '$playerCount',
                  accent: const Color(0xFFFFC857),
                ),
              ),
              SizedBox(
                width: 140,
                child: StatTile(
                  label: 'مافیا',
                  value: '$mafiaCount',
                  accent: const Color(0xFFFF6B6B),
                ),
              ),
              SizedBox(
                width: 140,
                child: StatTile(
                  label: 'شهر',
                  value: '$cityCount',
                  accent: const Color(0xFF56E39F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.playerCount,
    required this.controllers,
    required this.selectedRoleCounts,
    required this.selectedRoleTotal,
    required this.remainingRoleSlots,
    required this.onPlayerCountChanged,
    required this.onRoleCountChanged,
    required this.onTextChanged,
    required this.onAssign,
  });

  final int playerCount;
  final List<TextEditingController> controllers;
  final Map<String, int> selectedRoleCounts;
  final int selectedRoleTotal;
  final int remainingRoleSlots;
  final ValueChanged<double> onPlayerCountChanged;
  final void Function(RoleCatalogEntry entry, int delta) onRoleCountChanged;
  final VoidCallback onTextChanged;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final roleColumns = width > 980
            ? 3
            : width > 680
            ? 2
            : 1;
        final playerColumns = width > 980
            ? 3
            : width > 540
            ? 2
            : 1;

        return GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text(
                'نقش‌ها را خودت انتخاب کن. فقط وقتی مجموع نقش‌ها دقیقا با تعداد بازیکن‌ها برابر شود، ساخت کارت‌ها فعال می‌شود.',
                style: TextStyle(color: Color(0xFFC6CCE9), height: 1.55),
              ),
              const SizedBox(height: 18),
              Text(
                'تعداد بازیکن‌ها: $playerCount',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFD68A),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFFC857),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFFFF6B6B),
                  overlayColor: const Color(0x33FFC857),
                ),
                child: Slider(
                  min: 10,
                  max: 15,
                  divisions: 5,
                  value: playerCount.toDouble(),
                  onChanged: onPlayerCountChanged,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  InfoChip(
                    label: 'مجموع نقش‌ها',
                    value: '$selectedRoleTotal',
                    accent: const Color(0xFFFFC857),
                  ),
                  InfoChip(
                    label: 'جای خالی',
                    value: '$remainingRoleSlots',
                    accent: remainingRoleSlots == 0
                        ? const Color(0xFF56E39F)
                        : const Color(0xFFFF6B6B),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AdaptiveGrid(
                columns: roleColumns,
                children: roleCatalog.map((entry) {
                  final count = selectedRoleCounts[entry.key] ?? 0;
                  return RoleCounterTile(
                    entry: entry,
                    count: count,
                    onIncrement: () => onRoleCountChanged(entry, 1),
                    onDecrement: () => onRoleCountChanged(entry, -1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              AdaptiveGrid(
                columns: playerColumns,
                children: List.generate(playerCount, (index) {
                  return TextField(
                    controller: controllers[index],
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'جایگاه ${index + 1}',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      labelStyle: const TextStyle(color: Color(0xFFD3DAF8)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    onChanged: (_) => onTextChanged(),
                  );
                }),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: remainingRoleSlots == 0 ? onAssign : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC857),
                    foregroundColor: const Color(0xFF231700),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'ساخت کارت‌های نقش',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اتاق نمایش نقش',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 10),
          Text(
            'هنوز کارتی ساخته نشده. از بخش بالا نقش‌ها را بچین و کارت‌ها را بساز.',
            style: TextStyle(color: Color(0xFFC6CCE9), height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _RevealSection extends StatelessWidget {
  const _RevealSection({
    super.key,
    required this.remainingAssignments,
    required this.totalCount,
    required this.onApprove,
  });

  final List<RoleAssignment> remainingAssignments;
  final int totalCount;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final current = remainingAssignments.first;
    final shownIndex = totalCount - remainingAssignments.length + 1;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$totalCount / $shownIndex',
                style: const TextStyle(
                  color: Color(0xFFFFD68A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              const Text(
                'اتاق نمایش نقش',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'هر بار فقط کارت نفر بعدی دیده می‌شود. بعد از تایید، همان لحظه کارت بعدی ظاهر می‌شود.',
            style: TextStyle(color: Color(0xFFC6CCE9), height: 1.55),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 500,
            child: RevealCard(
              key: ValueKey(current.id),
              assignment: current,
              index: shownIndex,
              totalCount: totalCount,
              onApprove: onApprove,
            ),
          ),
        ],
      ),
    );
  }
}

class _NightWizardSection extends StatelessWidget {
  const _NightWizardSection({
    super.key,
    required this.nightNumber,
    required this.stepIndex,
    required this.totalSteps,
    required this.actor,
    required this.doctorSelfSaveUses,
    required this.selectedTargetIds,
    required this.selectedGunTypes,
    required this.availableTargets,
    required this.onTargetToggle,
    required this.onGunTypeChanged,
    required this.onConfirm,
  });

  final int nightNumber;
  final int stepIndex;
  final int totalSteps;
  final RoleAssignment actor;
  final int doctorSelfSaveUses;
  final List<String> selectedTargetIds;
  final Map<String, GunType> selectedGunTypes;
  final List<RoleAssignment> availableTargets;
  final ValueChanged<RoleAssignment> onTargetToggle;
  final void Function(RoleAssignment assignment, GunType gunType)
  onGunTypeChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final canSubmit = actor.role.actionType == RoleActionType.interrogate
        ? selectedTargetIds.isEmpty || selectedTargetIds.length == 2
        : selectedTargetIds.length >= actor.role.minTargets &&
              selectedTargetIds.length <= actor.role.maxTargets;
    final rangeText = actor.role.actionType == RoleActionType.interrogate
        ? 'صفر یا دو هدف'
        : actor.role.minTargets == actor.role.maxTargets
        ? '${actor.role.minTargets} هدف'
        : '${actor.role.minTargets} تا ${actor.role.maxTargets} هدف';

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$totalSteps / ${stepIndex + 1}',
                style: const TextStyle(
                  color: Color(0xFFFFD68A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                'شب $nightNumber',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${actor.playerName} / ${actor.role.name}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: actor.role.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$rangeText انتخاب کن. ${actor.role.stepHint}',
            style: const TextStyle(color: Color(0xFFC6CCE9), height: 1.6),
          ),
          if (actor.role.actionType == RoleActionType.save &&
              doctorSelfSaveUses > 0)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                doctorSelfSaveUses >= 2
                    ? 'این دکتر دو بار خودش را نجات داده و دیگر نمی‌تواند خودش را انتخاب کند.'
                    : 'این دکتر یک بار خودش را نجات داده و فقط یک خودنجات دیگر دارد.',
                style: const TextStyle(
                  color: Color(0xFFFFD68A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableTargets.map((target) {
              return SelectablePlayerChip(
                assignment: target,
                selected: selectedTargetIds.contains(target.id),
                onTap: () => onTargetToggle(target),
              );
            }).toList(),
          ),
          if (actor.role.actionType == RoleActionType.armPlayers &&
              selectedTargetIds.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'نوع تفنگ هر نفر را مشخص کن',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Column(
              children: availableTargets
                  .where((target) => selectedTargetIds.contains(target.id))
                  .map(
                    (target) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GunTypeSelector(
                        assignment: target,
                        value: selectedGunTypes[target.id] ?? GunType.blank,
                        selfOnlyBlank: target.id == actor.id,
                        onChanged: (gunType) =>
                            onGunTypeChanged(target, gunType),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? onConfirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: actor.role.accent,
                foregroundColor: const Color(0xFF10131D),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'ثبت و ادامه',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinatorSection extends StatelessWidget {
  const _CoordinatorSection({
    super.key,
    required this.assignments,
    required this.playerStates,
    required this.eliminatedMafiaCount,
    required this.eliminatedCityCount,
    required this.nightNumber,
    required this.nightReports,
    required this.onStartNight,
    required this.onPlayerStateChanged,
    required this.onRestart,
  });

  final List<RoleAssignment> assignments;
  final Map<String, PlayerLifeStatus> playerStates;
  final int eliminatedMafiaCount;
  final int eliminatedCityCount;
  final int nightNumber;
  final List<NightReport> nightReports;
  final VoidCallback onStartNight;
  final void Function(String assignmentId, PlayerLifeStatus status)
  onPlayerStateChanged;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: onRestart,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('شروع دوباره'),
              ),
              FilledButton(
                onPressed: onStartNight,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC857),
                  foregroundColor: const Color(0xFF231700),
                ),
                child: const Text(
                  'شروع فاز شب',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Text(
                'داشبورد گرداننده',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 150,
                child: StatTile(
                  label: 'مافیای حذف‌شده',
                  value: '$eliminatedMafiaCount',
                  accent: const Color(0xFFFF6B6B),
                ),
              ),
              SizedBox(
                width: 150,
                child: StatTile(
                  label: 'شهر حذف‌شده',
                  value: '$eliminatedCityCount',
                  accent: const Color(0xFF56E39F),
                ),
              ),
              SizedBox(
                width: 150,
                child: StatTile(
                  label: 'شب فعلی',
                  value: '$nightNumber',
                  accent: const Color(0xFFFFC857),
                ),
              ),
            ],
          ),
          if (nightReports.isNotEmpty) ...[
            const SizedBox(height: 20),
            NightReportCard(report: nightReports.first),
          ],
          const SizedBox(height: 20),
          const Text(
            'وضعیت بازیکن‌ها',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: assignments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              final status =
                  playerStates[assignment.id] ?? PlayerLifeStatus.alive;
              return PlayerStatusTile(
                assignment: assignment,
                status: status,
                onStatusChanged: (status) =>
                    onPlayerStateChanged(assignment.id, status),
              );
            },
          ),
        ],
      ),
    );
  }
}

class RevealCard extends StatefulWidget {
  const RevealCard({
    super.key,
    required this.assignment,
    required this.index,
    required this.totalCount,
    required this.onApprove,
  });

  final RoleAssignment assignment;
  final int index;
  final int totalCount;
  final VoidCallback onApprove;

  @override
  State<RevealCard> createState() => _RevealCardState();
}

class _RevealCardState extends State<RevealCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _revealed = !_revealed;
      if (_revealed) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.assignment.role;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _controller.value * pi;
        final showFront = angle < pi / 2;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFront
              ? _CardFaceFront(
                  assignment: widget.assignment,
                  index: widget.index,
                  totalCount: widget.totalCount,
                  onTap: _toggle,
                )
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: _CardFaceBack(
                    role: role,
                    onFlipBack: _toggle,
                    onApprove: widget.onApprove,
                  ),
                ),
        );
      },
    );
  }
}

class _CardFaceFront extends StatelessWidget {
  const _CardFaceFront({
    required this.assignment,
    required this.index,
    required this.totalCount,
    required this.onTap,
  });

  final RoleAssignment assignment;
  final int index;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseCardShell(
      accent: const Color(0xFFFFC857),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$totalCount / $index',
                  style: const TextStyle(
                    color: Color(0xFFFFD68A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.visibility_rounded, color: Colors.white70),
              ],
            ),
            const Spacer(),
            Text(
              assignment.playerName,
              style: const TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'برای دیدن نقش، روی کارت بزن',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFFC6CCE9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'بعد از دیدن نقش، تایید کن تا کارت نفر بعدی بلافاصله نمایش داده شود.',
              style: TextStyle(color: Color(0xFFC6CCE9), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFaceBack extends StatelessWidget {
  const _CardFaceBack({
    required this.role,
    required this.onFlipBack,
    required this.onApprove,
  });

  final RoleSpec role;
  final VoidCallback onFlipBack;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return _BaseCardShell(
      accent: role.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onFlipBack,
                icon: const Icon(Icons.flip_rounded, color: Colors.white70),
              ),
              const Spacer(),
              TeamBadge(team: role.team),
            ],
          ),
          const Spacer(),
          Text(
            role.name,
            style: const TextStyle(
              fontSize: 32,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            role.summary,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Color(0xFFE8ECFF),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            role.highlight,
            style: TextStyle(color: role.accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onApprove,
              style: FilledButton.styleFrom(
                backgroundColor: role.accent,
                foregroundColor: const Color(0xFF10131D),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'تایید و نمایش کارت بعدی',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NightReportCard extends StatelessWidget {
  const NightReportCard({super.key, required this.report});

  final NightReport report;

  @override
  Widget build(BuildContext context) {
    final eliminatedText = report.eliminatedNames.isEmpty
        ? 'هیچ بازیکنی حذف نشد.'
        : report.eliminatedNames.join('، ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFC857).withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFFFC857).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'گزارش کوتاه شب ${report.nightNumber}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            'حذف‌شده‌ها: $eliminatedText',
            style: const TextStyle(
              color: Color(0xFFFFD68A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...report.actionSummaries.map(
            (summary) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '• $summary',
                style: const TextStyle(color: Color(0xFFC6CCE9), height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerStatusTile extends StatelessWidget {
  const PlayerStatusTile({
    super.key,
    required this.assignment,
    required this.status,
    required this.onStatusChanged,
  });

  final RoleAssignment assignment;
  final PlayerLifeStatus status;
  final ValueChanged<PlayerLifeStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final alive = status == PlayerLifeStatus.alive;
    const eliminatedGray = Color(0xFF9CA3AF);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: assignment.role.accent.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<PlayerLifeStatus>(
                  value: status,
                  dropdownColor: const Color(0xFF181B2B),
                  decoration: InputDecoration(
                    labelText: 'وضعیت',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: PlayerLifeStatus.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onStatusChanged(value);
                    }
                  },
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    assignment.playerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    assignment.role.name,
                    style: TextStyle(
                      color: assignment.role.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: alive
                      ? const Color(0xFF56E39F).withValues(alpha: 0.15)
                      : eliminatedGray.withValues(alpha: 0.18),
                ),
                child: Text(
                  alive ? 'زنده' : 'حذف شده',
                  style: TextStyle(
                    color: alive ? const Color(0xFF56E39F) : eliminatedGray,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              TeamBadge(team: assignment.role.team),
            ],
          ),
        ],
      ),
    );
  }
}

class SelectablePlayerChip extends StatelessWidget {
  const SelectablePlayerChip({
    super.key,
    required this.assignment,
    required this.selected,
    required this.onTap,
  });

  final RoleAssignment assignment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected
              ? assignment.role.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? assignment.role.accent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              assignment.playerName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              assignment.role.name,
              style: TextStyle(
                color: assignment.role.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GunTypeSelector extends StatelessWidget {
  const GunTypeSelector({
    super.key,
    required this.assignment,
    required this.value,
    required this.selfOnlyBlank,
    required this.onChanged,
  });

  final RoleAssignment assignment;
  final GunType value;
  final bool selfOnlyBlank;
  final ValueChanged<GunType> onChanged;

  @override
  Widget build(BuildContext context) {
    final allowedTypes = selfOnlyBlank ? [GunType.blank] : GunType.values;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: assignment.role.accent.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<GunType>(
              value: value,
              dropdownColor: const Color(0xFF181B2B),
              decoration: InputDecoration(
                labelText: 'نوع تفنگ',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: allowedTypes
                  .map(
                    (gunType) => DropdownMenuItem(
                      value: gunType,
                      child: Text(gunType.label),
                    ),
                  )
                  .toList(),
              onChanged: (gunType) {
                if (gunType != null) {
                  onChanged(gunType);
                }
              },
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                assignment.playerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              if (selfOnlyBlank)
                const Text(
                  'برای خود تفنگدار فقط مشقی مجاز است',
                  style: TextStyle(color: Color(0xFFC6CCE9), fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RoleCounterTile extends StatelessWidget {
  const RoleCounterTile({
    super.key,
    required this.entry,
    required this.count,
    required this.onIncrement,
    required this.onDecrement,
  });

  final RoleCatalogEntry entry;
  final int count;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: entry.role.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.role.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: entry.role.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.role.summary,
            style: const TextStyle(color: Color(0xFFC6CCE9), height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove_rounded),
              ),
              const Spacer(),
              TeamBadge(team: entry.role.team),
            ],
          ),
        ],
      ),
    );
  }
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.columns,
    required this.children,
  });

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: accent, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BaseCardShell extends StatelessWidget {
  const _BaseCardShell({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.30),
            const Color(0xFF15192A),
            const Color(0xFF0B0E19),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 30,
            spreadRadius: 1,
            offset: const Offset(0, 18),
          ),
        ],
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(22),
      child: child,
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 36,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFC6CCE9))),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final isMafia = team == Team.mafia;
    final color = isMafia ? const Color(0xFFFF6B6B) : const Color(0xFF56E39F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        isMafia ? 'تیم مافیا' : 'تیم شهر',
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.controller,
    required this.beginOffset,
    required this.interval,
    required this.child,
  });

  final AnimationController controller;
  final Offset beginOffset;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: controller, curve: interval);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - curved.value) * 80,
              beginOffset.dy * (1 - curved.value) * 80,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class NebulaPainter extends CustomPainter {
  NebulaPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF03040A);
    canvas.drawRect(Offset.zero & size, background);

    void drawOrb({
      required Alignment alignment,
      required double radius,
      required Color color,
      required double driftX,
      required double driftY,
    }) {
      final center =
          alignment.alongSize(size) +
          Offset(
            sin(progress * 2 * pi) * driftX,
            cos(progress * 2 * pi) * driftY,
          );
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.48),
            color.withValues(alpha: 0.12),
            Colors.transparent,
          ],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }

    drawOrb(
      alignment: const Alignment(-0.7, -0.8),
      radius: size.width * 0.42,
      color: const Color(0xFFFF6B6B),
      driftX: 20,
      driftY: 26,
    );
    drawOrb(
      alignment: const Alignment(0.85, -0.2),
      radius: size.width * 0.34,
      color: const Color(0xFFFFC857),
      driftX: 18,
      driftY: 20,
    );
    drawOrb(
      alignment: const Alignment(-0.2, 0.95),
      radius: size.width * 0.48,
      color: const Color(0xFF4D7CFE),
      driftX: 24,
      driftY: 18,
    );
  }

  @override
  bool shouldRepaint(covariant NebulaPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

enum Team { mafia, city }

enum RoleActionType {
  none,
  kill,
  guess,
  discoverDetective,
  save,
  revealCheck,
  sniperShot,
  link,
  interrogate,
  armPlayers,
}

enum PlayerLifeStatus {
  alive('زنده'),
  eliminated('حذف شده');

  const PlayerLifeStatus(this.label);

  final String label;
}

enum GunType {
  blank('مشقی'),
  live('جنگی');

  const GunType(this.label);

  final String label;
}

class RoleSpec {
  const RoleSpec({
    required this.key,
    required this.name,
    required this.team,
    required this.summary,
    required this.highlight,
    required this.accent,
    required this.wakeOrder,
    required this.actionType,
    required this.minTargets,
    required this.maxTargets,
    required this.canTargetSelf,
    required this.stepHint,
    this.isBulletproof = false,
  });

  final String key;
  final String name;
  final Team team;
  final String summary;
  final String highlight;
  final Color accent;
  final int wakeOrder;
  final RoleActionType actionType;
  final int minTargets;
  final int maxTargets;
  final bool canTargetSelf;
  final String stepHint;
  final bool isBulletproof;
}

class RoleCatalogEntry {
  const RoleCatalogEntry({
    required this.key,
    required this.role,
    required this.maxCount,
  });

  final String key;
  final RoleSpec role;
  final int Function(int playerCount) maxCount;
}

class RoleAssignment {
  const RoleAssignment({
    required this.id,
    required this.playerName,
    required this.role,
  });

  final String id;
  final String playerName;
  final RoleSpec role;
}

class NightStep {
  const NightStep({required this.actor});

  final RoleAssignment actor;
}

class NightReport {
  const NightReport({
    required this.nightNumber,
    required this.actionSummaries,
    required this.eliminatedIds,
    required this.eliminatedNames,
  });

  final int nightNumber;
  final List<String> actionSummaries;
  final List<String> eliminatedIds;
  final List<String> eliminatedNames;
}

Map<String, int> defaultRoleCountsForPlayerCount(int playerCount) {
  final counts = <String, int>{
    bazporsBoss.key: 1,
    nato.key: 1,
    shiad.key: 1,
    doctor.key: 1,
    detective.key: 1,
    bulletproof.key: 1,
    sniper.key: 1,
    investigator.key: 1,
    interrogator.key: 1,
    gunner.key: 0,
    simpleMafia.key: 0,
    citizen.key: 1,
  };

  if (playerCount >= 11) {
    counts[citizen.key] = 2;
  }
  if (playerCount >= 12) {
    counts[simpleMafia.key] = 1;
  }
  if (playerCount >= 13) {
    counts[citizen.key] = 3;
  }
  if (playerCount >= 14) {
    counts[citizen.key] = 4;
  }
  if (playerCount >= 15) {
    counts[citizen.key] = 5;
  }

  return counts;
}

const bazporsBoss = RoleSpec(
  key: 'mafia_boss',
  name: 'رئیس مافیا',
  team: Team.mafia,
  summary: 'شلیک شب را انتخاب می‌کند.',
  highlight: 'برای کارآگاه منفی است.',
  accent: Color(0xFFFF6B6B),
  wakeOrder: 2,
  actionType: RoleActionType.kill,
  minTargets: 1,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'هدف شلیک شب را مشخص کن.',
);

const nato = RoleSpec(
  key: 'nato',
  name: 'ناتو',
  team: Team.mafia,
  summary: 'می‌تواند نقش یک نفر را حدس بزند.',
  highlight: 'در این نسخه فقط هدف او ثبت می‌شود.',
  accent: Color(0xFFFF8E72),
  wakeOrder: 3,
  actionType: RoleActionType.guess,
  minTargets: 0,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'اگر می‌خواهی از قابلیت استفاده کنی، یک هدف انتخاب کن.',
);

const shiad = RoleSpec(
  key: 'shiad',
  name: 'شیاد',
  team: Team.mafia,
  summary: 'به دنبال پیدا کردن کارآگاه است.',
  highlight: 'فقط هدف شب او ثبت می‌شود.',
  accent: Color(0xFFFF7CA8),
  wakeOrder: 4,
  actionType: RoleActionType.discoverDetective,
  minTargets: 1,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'بازیکن موردنظر را انتخاب کن.',
);

const simpleMafia = RoleSpec(
  key: 'simple_mafia',
  name: 'مافیای ساده',
  team: Team.mafia,
  summary: 'قدرت مستقل شب ندارد.',
  highlight: 'در روز برای پوشش دادن تیم مافیا مهم است.',
  accent: Color(0xFFE05A74),
  wakeOrder: 99,
  actionType: RoleActionType.none,
  minTargets: 0,
  maxTargets: 0,
  canTargetSelf: false,
  stepHint: '',
);

const doctor = RoleSpec(
  key: 'doctor',
  name: 'دکتر',
  team: Team.city,
  summary: 'هر شب یک نفر را نجات می‌دهد.',
  highlight: 'می‌تواند در کل بازی دو بار خودش را نجات دهد.',
  accent: Color(0xFF56E39F),
  wakeOrder: 7,
  actionType: RoleActionType.save,
  minTargets: 1,
  maxTargets: 1,
  canTargetSelf: true,
  stepHint:
      'بازیکنی که می‌خواهی نجات بدهی را انتخاب کن. خودنجات فقط دو بار در کل بازی مجاز است.',
);

const detective = RoleSpec(
  key: 'detective',
  name: 'کارآگاه',
  team: Team.city,
  summary: 'از یک بازیکن استعلام می‌گیرد.',
  highlight: 'فقط هدف استعلام ثبت می‌شود.',
  accent: Color(0xFF52C7EA),
  wakeOrder: 5,
  actionType: RoleActionType.revealCheck,
  minTargets: 1,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'هدف استعلام را انتخاب کن.',
);

const bulletproof = RoleSpec(
  key: 'bulletproof',
  name: 'رویین‌تن',
  team: Team.city,
  summary: 'در برابر شلیک عادی مافیا در شب حذف نمی‌شود.',
  highlight: 'در رای‌گیری روز همچنان می‌تواند حذف شود.',
  accent: Color(0xFF7BE0C3),
  wakeOrder: 99,
  actionType: RoleActionType.none,
  minTargets: 0,
  maxTargets: 0,
  canTargetSelf: false,
  stepHint: '',
  isBulletproof: true,
);

const sniper = RoleSpec(
  key: 'sniper',
  name: 'اسنایپر',
  team: Team.city,
  summary: 'یک تیر برای کل بازی دارد.',
  highlight: 'اگر به شهر شلیک کند خودش حذف می‌شود.',
  accent: Color(0xFF7AA2FF),
  wakeOrder: 6,
  actionType: RoleActionType.sniperShot,
  minTargets: 0,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'در صورت نیاز یک هدف انتخاب کن.',
);

const investigator = RoleSpec(
  key: 'investigator',
  name: 'محقق',
  team: Team.city,
  summary: 'هر شب به یک بازیکن پیوند می‌خورد.',
  highlight: 'اگر خودش حذف شود و به ناتو یا شیاد وصل باشد، آن‌ها را هم می‌برد.',
  accent: Color(0xFFD9A6FF),
  wakeOrder: 1,
  actionType: RoleActionType.link,
  minTargets: 1,
  maxTargets: 1,
  canTargetSelf: false,
  stepHint: 'بازیکنی که می‌خواهی به او وصل شوی را انتخاب کن.',
);

const interrogator = RoleSpec(
  key: 'interrogator',
  name: 'بازپرس',
  team: Team.city,
  summary: 'یک بار در کل بازی دو بازیکن را برای بازپرسی انتخاب می‌کند.',
  highlight:
      'اگر یکی از هدف‌ها همان شب حذف شود، دوباره در شب بعد هم می‌تواند بازپرسی کند.',
  accent: Color(0xFFFFD166),
  wakeOrder: 8,
  actionType: RoleActionType.interrogate,
  minTargets: 0,
  maxTargets: 2,
  canTargetSelf: false,
  stepHint:
      'می‌توانی فعلا کسی را انتخاب نکنی یا دو نفر را برای بازپرسی ببندی. اگر هر دو هدف زنده بمانند، این توانایی مصرف می‌شود.',
);

const gunner = RoleSpec(
  key: 'gunner',
  name: 'تفنگدار',
  team: Team.city,
  summary: 'هر شب می‌تواند حداکثر به دو نفر تفنگ بدهد.',
  highlight:
      'در این نسخه فقط دریافت‌کننده‌ها ثبت می‌شوند و راوی می‌تواند نتیجه شلیک روز را دستی اعمال کند.',
  accent: Color(0xFFB38CFF),
  wakeOrder: 9,
  actionType: RoleActionType.armPlayers,
  minTargets: 0,
  maxTargets: 2,
  canTargetSelf: true,
  stepHint: 'می‌توانی صفر، یک یا دو هدف انتخاب کنی.',
);

const citizen = RoleSpec(
  key: 'citizen',
  name: 'شهروند ساده',
  team: Team.city,
  summary: 'نقش شب ندارد و در روز بازی را می‌سازد.',
  highlight: 'برای بالانس تعداد نفرات استفاده می‌شود.',
  accent: Color(0xFFA7F3D0),
  wakeOrder: 99,
  actionType: RoleActionType.none,
  minTargets: 0,
  maxTargets: 0,
  canTargetSelf: false,
  stepHint: '',
);

final roleCatalog = <RoleCatalogEntry>[
  RoleCatalogEntry(key: bazporsBoss.key, role: bazporsBoss, maxCount: (_) => 1),
  RoleCatalogEntry(key: nato.key, role: nato, maxCount: (_) => 1),
  RoleCatalogEntry(key: shiad.key, role: shiad, maxCount: (_) => 1),
  RoleCatalogEntry(
    key: simpleMafia.key,
    role: simpleMafia,
    maxCount: (playerCount) => max(0, playerCount ~/ 4),
  ),
  RoleCatalogEntry(key: doctor.key, role: doctor, maxCount: (_) => 1),
  RoleCatalogEntry(key: detective.key, role: detective, maxCount: (_) => 1),
  RoleCatalogEntry(key: bulletproof.key, role: bulletproof, maxCount: (_) => 1),
  RoleCatalogEntry(key: sniper.key, role: sniper, maxCount: (_) => 1),
  RoleCatalogEntry(
    key: investigator.key,
    role: investigator,
    maxCount: (_) => 1,
  ),
  RoleCatalogEntry(
    key: interrogator.key,
    role: interrogator,
    maxCount: (_) => 1,
  ),
  RoleCatalogEntry(key: gunner.key, role: gunner, maxCount: (_) => 1),
  RoleCatalogEntry(
    key: citizen.key,
    role: citizen,
    maxCount: (playerCount) => playerCount,
  ),
];
