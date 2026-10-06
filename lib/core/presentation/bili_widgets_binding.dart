import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Guards the Windows AX bridge in the pinned Flutter 3.47.6 engine.
///
/// Hidden OverlayPortal children can stay attached to the paint semantics tree
/// while their traversal parent is absent. Sending those dirty nodes can leave
/// the native tree malformed and crash a later reparent operation. Preserve
/// accessibility by only submitting nodes reachable in the current traversal
/// tree, including clean nodes when a retained page becomes visible again.
/// See https://github.com/flutter/flutter/issues/193410.
class BiliWidgetsBinding extends WidgetsFlutterBinding {
  BiliWidgetsBinding._() {
    addSemanticsEnabledListener(() {
      if (!semanticsEnabled) _resetSemanticsUpdates();
    });
  }

  static BiliWidgetsBinding? _binding;

  static WidgetsBinding ensureInitialized() {
    if (_binding case final binding?) return binding;
    // Respect a binding supplied by the widget/integration harness in debug.
    if (kDebugMode && BindingBase.debugBindingType() != null) {
      return WidgetsBinding.instance;
    }
    final binding = BiliWidgetsBinding._();
    _binding = binding;
    return binding;
  }

  SemanticsOwner? _semanticsOwner;
  final _nodeUpdates = <int, _NodeUpdate>{};
  final _previousReachable = <int>{};

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final delegate = super.createSemanticsUpdateBuilder();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return delegate;
    }
    final owners = renderViews
        .map((view) => view.owner?.semanticsOwner)
        .whereType<SemanticsOwner>()
        .where((owner) => owner.rootSemanticsNode != null)
        .toSet();
    // The app has one Flutter view. Do not combine unrelated view roots, whose
    // semantics root IDs are both 0, if multi-view support is added later.
    if (owners.length != 1) {
      _resetSemanticsUpdates();
      return delegate;
    }
    final owner = owners.single;
    if (!identical(owner, _semanticsOwner)) {
      _resetSemanticsUpdates();
      _semanticsOwner = owner;
    }
    final root = owner.rootSemanticsNode;
    if (root == null) return delegate;
    final tree = _TraversalTree(root);
    _nodeUpdates.removeWhere(
      (id, update) => !identical(owner.getSemanticsNode(id), update.node),
    );
    _previousReachable.retainAll(_nodeUpdates.keys);
    return _ReachableSemanticsBuilder(
      delegate,
      owner,
      tree,
      _nodeUpdates,
      _previousReachable,
    );
  }

  void _resetSemanticsUpdates() {
    _semanticsOwner = null;
    _nodeUpdates.clear();
    _previousReachable.clear();
  }
}

/// Paint ancestry is insufficient: portal children are grafted onto a separate
/// traversal parent. Derive connectivity from the current framework nodes,
/// rather than cached updates (a hidden parent may no longer be dirty).
final class _TraversalTree {
  _TraversalTree(SemanticsNode root) {
    final nodes = <int, SemanticsNode>{};
    final portalChildren = <Object, List<SemanticsNode>>{};
    final paintPending = <SemanticsNode>[root];
    while (paintPending.isNotEmpty) {
      final node = paintPending.removeLast();
      if (!node.attached || nodes.containsKey(node.id)) continue;
      nodes[node.id] = node;
      final childIdentifier = node.traversalChildIdentifier;
      if (!node.isMergedIntoParent &&
          childIdentifier != null &&
          node.traversalParentIdentifier == null) {
        portalChildren.putIfAbsent(childIdentifier, () => []).add(node);
      }
      node.visitChildren((child) {
        paintPending.add(child);
        return true;
      });
    }

    final traversalPending = <(SemanticsNode, int?)>[(root, null)];
    while (traversalPending.isNotEmpty) {
      final (node, parent) = traversalPending.removeLast();
      if (!node.attached ||
          node.isMergedIntoParent ||
          (node.id == 0 && parent != null) ||
          !reachable.add(node.id)) {
        continue;
      }
      if (parent != null) parentByChild[node.id] = parent;
      final parentIdentifier = node.traversalParentIdentifier;
      if (!node.mergeAllDescendantsIntoThisNode) {
        node.visitChildren((child) {
          if (child.traversalChildIdentifier == null ||
              parentIdentifier != null) {
            traversalPending.add((child, node.id));
          }
          return true;
        });
      }
      if (parentIdentifier != null) {
        for (final child
            in portalChildren[parentIdentifier] ?? const <SemanticsNode>[]) {
          traversalPending.add((child, node.id));
        }
      }
    }
  }

  final reachable = <int>{};
  // First visit fixes one parent per node and prevents ancestor cycles. This
  // also rejects a stale cached edge when a reachable child changes parents.
  final parentByChild = <int, int>{};
}

typedef _WriteNode = void Function(
  ui.SemanticsUpdateBuilder,
  Int32List,
  Int32List,
  int,
);

final class _NodeUpdate {
  _NodeUpdate({
    required this.node,
    required this.traversalChildren,
    required this.hitTestChildren,
    required this.traversalParent,
    required this.write,
  });

  final SemanticsNode node;
  final Int32List traversalChildren;
  final Int32List hitTestChildren;
  final int traversalParent;
  final _WriteNode write;
  Int32List? _sentTraversalChildren;
  Int32List? _sentHitTestChildren;
  int? _sentTraversalParent;

  void submit(
    ui.SemanticsUpdateBuilder builder,
    _TraversalTree tree, {
    required bool force,
  }) {
    final traversal = _children(
      node.id,
      traversalChildren,
      tree,
      traversal: true,
    );
    final hitTest = _children(node.id, hitTestChildren, tree);
    final parent = traversalParent >= 0
        ? tree.parentByChild[node.id] ?? -1
        : -1;
    if (force ||
        !listEquals(_sentTraversalChildren, traversal) ||
        !listEquals(_sentHitTestChildren, hitTest) ||
        _sentTraversalParent != parent) {
      write(builder, traversal, hitTest, parent);
      _sentTraversalChildren = traversal;
      _sentHitTestChildren = hitTest;
      _sentTraversalParent = parent;
    }
  }

  static Int32List _children(
    int parent,
    Int32List children,
    _TraversalTree tree, {
    bool traversal = false,
  }) {
    bool valid(int child) =>
        child != 0 &&
        child != parent &&
        tree.reachable.contains(child) &&
        (!traversal || tree.parentByChild[child] == parent);
    if (children.every(valid)) return children;
    // A partially filled framework child array can contain root ID 0. The
    // native root must never be reparented under one of its descendants.
    return Int32List.fromList(children.where(valid).toList());
  }
}

final class _ReachableSemanticsBuilder implements ui.SemanticsUpdateBuilder {
  _ReachableSemanticsBuilder(
    this._delegate,
    this._owner,
    this._tree,
    this._nodeUpdates,
    this._previousReachable,
  );

  final ui.SemanticsUpdateBuilder _delegate;
  final SemanticsOwner _owner;
  final _TraversalTree _tree;
  final Map<int, _NodeUpdate> _nodeUpdates;
  final Set<int> _previousReachable;
  final _changed = <int>{};

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    final node = _owner.getSemanticsNode(id);
    if (node == null) return;
    // The framework can mutate matrices and lists after this batch. Each
    // retained node owns its latest payload until it detaches or reconnects.
    transform = Float64List.fromList(transform);
    hitTestTransform = Float64List.fromList(hitTestTransform);
    childrenInTraversalOrder = Int32List.fromList(childrenInTraversalOrder);
    childrenInHitTestOrder = Int32List.fromList(childrenInHitTestOrder);
    additionalActions = Int32List.fromList(additionalActions);
    labelAttributes = List.unmodifiable(labelAttributes);
    valueAttributes = List.unmodifiable(valueAttributes);
    increasedValueAttributes = List.unmodifiable(increasedValueAttributes);
    decreasedValueAttributes = List.unmodifiable(decreasedValueAttributes);
    hintAttributes = List.unmodifiable(hintAttributes);
    controlsNodes = controlsNodes == null
        ? null
        : List.unmodifiable(controlsNodes);
    _changed.add(id);
    _nodeUpdates[id] = _NodeUpdate(
      node: node,
      traversalChildren: childrenInTraversalOrder,
      hitTestChildren: childrenInHitTestOrder,
      traversalParent: traversalParent,
      write: (builder, traversal, hitTest, parent) => builder.updateNode(
        id: id,
        flags: flags,
        actions: actions,
        maxValueLength: maxValueLength,
        currentValueLength: currentValueLength,
        textSelectionBase: textSelectionBase,
        textSelectionExtent: textSelectionExtent,
        platformViewId: platformViewId,
        scrollChildren: scrollChildren,
        scrollIndex: scrollIndex,
        traversalParent: parent,
        scrollPosition: scrollPosition,
        scrollExtentMax: scrollExtentMax,
        scrollExtentMin: scrollExtentMin,
        rect: rect,
        identifier: identifier,
        label: label,
        labelAttributes: labelAttributes,
        value: value,
        valueAttributes: valueAttributes,
        increasedValue: increasedValue,
        increasedValueAttributes: increasedValueAttributes,
        decreasedValue: decreasedValue,
        decreasedValueAttributes: decreasedValueAttributes,
        hint: hint,
        hintAttributes: hintAttributes,
        tooltip: tooltip,
        textDirection: textDirection,
        transform: transform,
        hitTestTransform: hitTestTransform,
        childrenInTraversalOrder: traversal,
        childrenInHitTestOrder: hitTest,
        additionalActions: additionalActions,
        headingLevel: headingLevel,
        linkUrl: linkUrl,
        role: role,
        controlsNodes: controlsNodes,
        validationResult: validationResult,
        hitTestBehavior: hitTestBehavior,
        inputType: inputType,
        locale: locale,
        minValue: minValue,
        maxValue: maxValue,
      ),
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    // AX removes unreachable nodes. Reconnecting a retained clean node needs
    // its payload even when Flutter omits that node from the dirty batch.
    for (final id in _tree.reachable) {
      // A clean parent also needs resubmitting when filtering changes its child
      // lists; otherwise native AX would retain the old disconnected edge.
      _nodeUpdates[id]?.submit(
        _delegate,
        _tree,
        force: _changed.contains(id) || !_previousReachable.contains(id),
      );
    }
    _previousReachable
      ..clear()
      ..addAll(_tree.reachable);
    return _delegate.build();
  }
}
