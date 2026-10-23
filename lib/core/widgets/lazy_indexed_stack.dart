import 'package:flutter/widgets.dart';

/// An [IndexedStack] that only builds a page once it has been selected.
///
/// The toolbox keeps pages mounted after the first visit so their editor state
/// and scroll position survive switching. Building them all at launch would
/// create every tool page before the user ever opens it, and each page hosts
/// its own WebKit editor, so the empty entries stay unbuilt until needed.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  /// The page to show. Adding it to the visited set happens automatically.
  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          // Pages read `Visibility.of(context)` to blur their editor while
          // another page is in front, so the wrapper has to stay even though
          // IndexedStack already keeps only one child painted.
          Visibility(
            visible: index == widget.index,
            maintainState: true,
            child: _visited.contains(index)
                ? widget.children[index]
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
